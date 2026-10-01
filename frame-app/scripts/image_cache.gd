class_name ImageCache
extends Node
## Loads poster images, with an in-memory and on-disk cache and a cap on
## concurrent downloads (a Netflix home page has hundreds).

const DISK_DIR := "user://posters"
const MAX_CONCURRENT := 6

var _textures: Dictionary[String, Texture2D] = {}
## url -> callbacks waiting for it
var _waiting: Dictionary[String, Array] = {}
var _queue: Array[String] = []
var _active := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DISK_DIR)


func load_into(url: String, target: TextureRect) -> void:
	load_texture(url, func(texture: Texture2D) -> void:
		if is_instance_valid(target):
			target.texture = texture)


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
	var cached := _decode(FileAccess.get_file_as_bytes(_disk_path(url)))
	if cached:
		_finish(url, cached)
		return
	DirAccess.remove_absolute(_disk_path(url))  # missing or corrupt: fetch again
	_queue.append(url)
	_pump()


func _pump() -> void:
	while _active < MAX_CONCURRENT and not _queue.is_empty():
		_download(_queue.pop_front())


func _download(url: String) -> void:
	_active += 1
	var http := HTTPRequest.new()
	http.timeout = 30.0
	add_child(http)
	var texture: Texture2D = null
	if http.request(url) == OK:
		var result: Array = await http.request_completed
		if result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200:
			texture = _decode(result[3])
			# Only cache what decodes, so an error page served with a 200
			# can't poison the poster for good.
			var file := FileAccess.open(_disk_path(url), FileAccess.WRITE) if texture else null
			if file:
				file.store_buffer(result[3])
	http.queue_free()
	_active -= 1
	_finish(url, texture)
	_pump()


func _finish(url: String, texture: Texture2D) -> void:
	if texture:
		_textures[url] = texture
	for callback: Callable in _waiting.get(url, []):
		if callback.is_valid():
			callback.call(texture)
	_waiting.erase(url)


func _decode(bytes: PackedByteArray) -> Texture2D:
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
	if err != OK:
		return null
	return ImageTexture.create_from_image(image)


func _disk_path(url: String) -> String:
	return DISK_DIR.path_join(url.md5_text())
