extends Node
## The libmpv extension (addons/mpv), headless: a real video plays into a
## texture, position advances, pause/seek work, a bad URL fails cleanly.
## Needs internet and the built extension (native/build.sh). Audio is off.
## Run: godot --headless --path . res://tests/mpv_test.tscn

const VIDEO := "https://download.blender.org/durian/trailer/sintel_trailer-1080p.mp4"
const TIMEOUT := 30.0

var mpv: Node


func _ready() -> void:
	var failure: Variant = await _run()
	failure = _as_failure(failure)
	if failure == "":
		print("MPV TEST PASS")
		get_tree().quit(0)
	else:
		printerr("MPV TEST FAIL: " + failure)
		get_tree().quit(1)


func _run() -> Variant:
	if not ClassDB.class_exists("MpvPlayer"):
		return "the MpvPlayer extension isn't loaded (build it with native/build.sh)"
	mpv = ClassDB.instantiate("MpvPlayer")
	mpv.set_option("ao", "null")
	add_child(mpv)
	mpv.load(VIDEO)
	if not await _until(func() -> bool: return mpv.is_loaded() and mpv.get_video_size().x > 0):
		return "the video never loaded"
	var texture: Texture2D = mpv.get_texture()
	var video_size: Vector2i = mpv.get_video_size()
	if Vector2i(texture.get_size()) != video_size or video_size.x > 1920:
		return "texture should match the video (%s, at most 1920 wide), got %s" % [video_size, texture.get_size()]
	var start: float = mpv.get_position()
	await get_tree().create_timer(1.5).timeout
	if mpv.get_position() <= start + 0.5:
		return "position should advance while playing (%.2f -> %.2f)" % [start, mpv.get_position()]
	# Well into the film (openings are often black), then look for picture
	# anywhere on a grid of points.
	mpv.seek(20.0, false)
	if not await _until(func() -> bool: return mpv.get_position() > 21.0):
		return "seeking to 20 s didn't play on"
	var frame: Image = mpv.get_frame()
	if frame.get_pixel(video_size.x / 2, video_size.y / 2).a < 1.0:
		return "frames should be opaque"
	var picture := false
	for gx in range(1, 8):
		for gy in range(1, 8):
			if frame.get_pixel(video_size.x * gx / 8, video_size.y * gy / 8).get_luminance() > 0.05:
				picture = true
	if not picture:
		return "frames should have picture in them, not just black"
	print("ok: plays into a %s texture, %.1fs of %.1fs" % [texture.get_size(), mpv.get_position(), mpv.get_duration()])
	var ambient: Image = mpv.get_ambient()
	if ambient.get_size() != Vector2i(32, 18):
		return "the ambient grid should be 32x18, got %s" % ambient.get_size()
	var average: Color = mpv.get_average_color()
	if average.get_luminance() <= 0.01:
		return "the average colour of a playing film shouldn't be black"
	print("ok: ambient grid %s, average colour %s" % [ambient.get_size(), average])

	mpv.set_paused(true)
	await get_tree().create_timer(0.5).timeout
	var held: float = mpv.get_position()
	await get_tree().create_timer(1.0).timeout
	if not mpv.is_paused() or absf(mpv.get_position() - held) > 0.05:
		return "pause should hold the position"
	mpv.seek(30.0, false)
	if not await _until(func() -> bool: return absf(mpv.get_position() - 30.0) < 1.0):
		return "seek should land near 30s (at %.2f)" % mpv.get_position()
	mpv.set_paused(false)
	print("ok: pause holds, seek lands at %.1fs" % mpv.get_position())

	mpv.seek(mpv.get_duration() - 1.0, false)
	if not await _until(func() -> bool: return mpv.has_ended()):
		return "playing to the end should report ended"
	print("ok: end of video reported")

	var failed := []
	mpv.failed.connect(func(message: String) -> void: failed.append(message))
	mpv.load("http://insecure.example/video.mp4")  # http is not allowed
	if not await _until(func() -> bool: return not failed.is_empty()):
		return "a non-https URL should fail"
	print("ok: non-https URL refused (%s)" % failed[0])
	return ""


func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT * 1000
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().create_timer(0.05).timeout
	return false


static func _as_failure(result: Variant) -> String:
	return result if result is String else "the test hit a script error (see the log above)"
