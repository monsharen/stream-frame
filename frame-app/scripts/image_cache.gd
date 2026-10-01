class_name ImageCache
extends Node
## Loads poster images, with an in-memory and on-disk cache and a cap on
## concurrent downloads (a Netflix home page has hundreds). Reading from
## disk, decoding and measuring images happens on worker threads (each
## takes milliseconds, and a catalog brings dozens at once); the main
## thread only turns finished images into textures, a few per frame, so
## opening or scrolling a catalog stays smooth.

const DISK_DIR := "user://posters"
const MAX_CONCURRENT := 6
const FADE_IN_SECONDS := 0.35
## SVG logos are rasterised at this scale, so they stay sharp on posters.
const SVG_SCALE := 4.0
## Nothing here needs bigger images; keeps a huge SVG or file from eating memory.
const MAX_SIZE := 1200
const AMBIENT_GRID := Vector2i(16, 9)
## Image hosts (Wikimedia in particular) ask clients to identify themselves,
## and throttle generic ones.
const USER_AGENT := "StreamFrame/0.1 (https://github.com/monsharen/stream-frame)"
## A busy host's "slow down" gets one more try after this long.
const RETRY_SECONDS := 2.0
## Finished images turned into textures per frame (each is an upload).
const UPLOADS_PER_FRAME := 6

var _textures: Dictionary[String, Texture2D] = {}
## url -> callbacks waiting for it
var _waiting: Dictionary[String, Array] = {}
var _queue: Array[String] = []
var _active := 0
## Worker results waiting for the main thread: [url, Image or null,
## ambient [grid Image, Color] or [], from_disk]. Guarded by _done_lock.
var _done: Array = []
var _done_lock := Mutex.new()
var _tasks: Array[int] = []
## url -> {grid, color}: the image's colours, for the light it casts.
var _ambient: Dictionary[String, Dictionary] = {}
## Serves poster:// URLs (generated extension artwork).
var posters: PosterFactory


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DISK_DIR)


## Shows the image in `target` when it arrives, fading it in (via
## self_modulate, so callers stay free to dim it with modulate).
func load_into(url: String, target: TextureRect) -> void:
	# A weak reference: the card may be freed before the image arrives.
	var ref: WeakRef = weakref(target)
	load_texture(url, func(texture: Texture2D) -> void:
		var rect: TextureRect = ref.get_ref()
		if rect == null or texture == null:
			return
		rect.texture = texture
		rect.self_modulate.a = 0.0
		rect.create_tween().tween_property(rect, "self_modulate:a", 1.0, FADE_IN_SECONDS))


## Calls `callback(texture)` once the image is available (texture is null if
## it couldn't be loaded). Callbacks on freed objects are skipped.
func load_texture(url: String, callback: Callable) -> void:
	if url == "":
		return
	if _textures.has(url):
		callback.call(_textures[url])
		return
	if _waiting.has(url):
		_waiting[url].append(callback)
		return
	_waiting[url] = [callback]
	if url.begins_with("poster://"):
		_finish(url, await posters.make(url) if posters else null)
		return
	_decode_later(url, PackedByteArray(), true)


func _pump() -> void:
	while _active < MAX_CONCURRENT and not _queue.is_empty():
		_download(_queue.pop_front())


func _download(url: String, retried := false) -> void:
	_active += 1
	var http := HTTPRequest.new()
	http.timeout = 30.0
	add_child(http)
	var texture: Texture2D = null
	if http.request(url, ["User-Agent: " + USER_AGENT]) == OK:
		var result: Array = await http.request_completed
		if result[1] in [429, 503] and not retried:
			http.queue_free()
			await get_tree().create_timer(RETRY_SECONDS).timeout
			_active -= 1
			_download(url, true)
			return
		if result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200:
			http.queue_free()
			_active -= 1
			_decode_later(url, result[3], false)
			_pump()
			return
	http.queue_free()
	_active -= 1
	_finish(url, texture)
	_pump()


## Decodes (and, from disk, first reads) an image on a worker thread; the
## result is picked up in _process.
func _decode_later(url: String, bytes: PackedByteArray, from_disk: bool) -> void:
	_tasks.append(WorkerThreadPool.add_task(_decode_work.bind(url, bytes, from_disk), false, "decode image"))


## Worker thread: no nodes, no textures, only Images and files.
func _decode_work(url: String, bytes: PackedByteArray, from_disk: bool) -> void:
	var path := _disk_path(url)
	if from_disk:
		bytes = FileAccess.get_file_as_bytes(path)
	var image := _decode_image(bytes)
	if image and not from_disk:
		# Only cache what decodes, so an error page served with a 200
		# can't poison the poster for good.
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_buffer(bytes)
	var light := _measure(image) if image else []
	_done_lock.lock()
	_done.append([url, image, light, from_disk])
	_done_lock.unlock()


func _process(_delta: float) -> void:
	# Finished worker tasks must be collected.
	for i in range(_tasks.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks.remove_at(i)
	_done_lock.lock()
	var ready := _done.slice(0, UPLOADS_PER_FRAME)
	_done = _done.slice(UPLOADS_PER_FRAME)
	_done_lock.unlock()
	for result: Array in ready:
		var url: String = result[0]
		var image: Image = result[1]
		if image == null and result[3]:
			DirAccess.remove_absolute(_disk_path(url))  # missing or corrupt: fetch again
			_queue.append(url)
			_pump()
			continue
		if not result[2].is_empty():
			_ambient[url] = {"grid": ImageTexture.create_from_image(result[2][0]), "color": result[2][1]}
		_finish(url, ImageTexture.create_from_image(image) if image else null)


func _exit_tree() -> void:
	for task in _tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	_tasks.clear()


func _finish(url: String, texture: Texture2D) -> void:
	if texture:
		_textures[url] = texture
	for callback: Callable in _waiting.get(url, []):
		if callback.is_valid():
			callback.call(texture)
	_waiting.erase(url)


## The colours of a loaded image, for lighting effects: `grid` is a small
## texture of it (AMBIENT_GRID cells, smoothly averaged) and `color` its
## average. Empty if the image isn't loaded (or can't be read back, e.g.
## headless).
func ambient(url: String) -> Dictionary:
	return _ambient.get(url, {})


## For images made in the app (generated posters): measure them now.
func set_ambient_from(url: String, image: Image) -> void:
	var light := _measure(image)
	if not light.is_empty():
		_ambient[url] = {"grid": ImageTexture.create_from_image(light[0]), "color": light[1]}


## [grid Image, average Color] of an image (any thread), or [].
static func _measure(source: Image) -> Array:
	if source == null or source.is_empty():
		return []
	var image := source.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGB8)
	# Halve in steps (each a proper average), then to the grid.
	while image.get_width() > AMBIENT_GRID.x * 4 and image.get_height() > AMBIENT_GRID.y * 4:
		image.resize(image.get_width() / 2, image.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	image.resize(AMBIENT_GRID.x, AMBIENT_GRID.y, Image.INTERPOLATE_BILINEAR)
	var sum := Color(0, 0, 0)
	for y in AMBIENT_GRID.y:
		for x in AMBIENT_GRID.x:
			sum += image.get_pixel(x, y)
	var average := sum / float(AMBIENT_GRID.x * AMBIENT_GRID.y)
	return [image, Color(average, 1.0)]


## Decodes PNG / JPEG / WebP / SVG bytes (any thread), or null.
static func _decode_image(bytes: PackedByteArray) -> Image:
	if bytes.size() < 12:
		return null
	var image := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes[1] == 0x50:
		err = image.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = image.load_jpg_from_buffer(bytes)
	elif bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = image.load_webp_from_buffer(bytes)
	elif _looks_like_svg(bytes):
		err = image.load_svg_from_buffer(bytes, SVG_SCALE)
	if err != OK:
		return null
	if image.get_width() > MAX_SIZE or image.get_height() > MAX_SIZE:
		var scale := float(MAX_SIZE) / maxi(image.get_width(), image.get_height())
		image.resize(int(image.get_width() * scale), int(image.get_height() * scale), Image.INTERPOLATE_LANCZOS)
	# Smaller copies for distant posters: less to read per pixel (GPU memory
	# bandwidth, which costs battery) and no shimmer.
	image.generate_mipmaps()
	return image


static func _looks_like_svg(bytes: PackedByteArray) -> bool:
	var head := bytes.slice(0, 256).get_string_from_utf8().strip_edges().to_lower()
	return head.begins_with("<svg") or (head.begins_with("<?xml") and head.contains("<svg"))


static func _disk_path(url: String) -> String:
	return DISK_DIR.path_join(url.md5_text())
