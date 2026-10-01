extends Node
## In-app playback through the built-in (libmpv) player, headless, audio
## off: a real NASA video plays into the player view with working controls,
## the controls fade while watching, and Stop returns to the catalog.
## Needs internet and the built extension (native/build.sh).
## Run: STREAM_FRAME_SETTINGS_PATH=/tmp/x.cfg godot --headless --path . res://tests/embedded_test.tscn

const TIMEOUT := 30.0

var app: Control


func _ready() -> void:
	app = load("res://main.tscn").instantiate()
	app.local.mpv_options = {"ao": "null"}  # before the app starts the player
	add_child(app)
	var failure: Variant = await _run()
	failure = _as_failure(failure)
	if failure == "":
		print("EMBEDDED TEST PASS")
		get_tree().quit(0)
	else:
		printerr("EMBEDDED TEST FAIL: " + failure)
		get_tree().quit(1)


func _run() -> Variant:
	if not LocalPlayer.builtin_available() or not app.local.embedded:
		return "the built-in player isn't available (build it with native/build.sh)"
	app.open_source(ExtensionRegistry.by_id(app.sources, "nasa"))
	if not await _until(func() -> bool: return _cards().size() > 10):
		return "the NASA catalog didn't load"
	var item: Dictionary = _cards()[0].item
	app.play_item(item)
	if not app.player.is_showing_video():
		return "playing an on-device title should show the video in the player view"
	if not await _until(func() -> bool: return _state().get("status") == "playing"):
		return "never started playing (status=%s, error=%s)" % [_state().get("status"), _state().get("error")]
	if _state().get("external", true) or not app.player._controls.visible:
		return "in-app playback should have the app's own controls"
	var texture: Texture2D = app.local.video_texture()
	if texture.get_width() == 0:
		return "the video texture should have frames"
	print("ok: '%s' plays in the app (%dx%d)" % [item["title"], texture.get_width(), texture.get_height()])

	if not await _until(func() -> bool: return _state().get("position", 0.0) > 2.0):
		return "position should advance"
	app._control("toggle", null)
	if not await _until(func() -> bool: return _state().get("status") == "paused"):
		return "pause should work"
	var held: float = _state()["position"]
	app._control("seekBy", 10)
	if not await _until(func() -> bool: return _state().get("position", 0.0) >= held + 9.0):
		return "+10s should seek forward (%.1f -> %.1f)" % [held, _state().get("position", 0.0)]
	app._control("toggle", null)
	if not await _until(func() -> bool: return _state().get("status") == "playing"):
		return "play should resume"
	print("ok: pause, +10s, resume")

	# Watching undisturbed: the controls fade away; any input brings them back.
	app.player._last_activity = 0.0
	if not await _until(func() -> bool: return app.player._chrome.modulate.a < 0.05):
		return "controls should fade while the video plays undisturbed"
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(960, 540)
	motion.relative = Vector2(40, 0)  # a deliberate movement, not jitter
	app.player.get_viewport().push_input(motion, true)
	if not await _until(func() -> bool: return app.player._chrome.modulate.a > 0.95):
		return "input should bring the controls back"
	var jitter := InputEventMouseMotion.new()
	jitter.position = Vector2(962, 540)
	jitter.relative = Vector2(2, 0)
	app.player._last_activity = 0.0
	if not await _until(func() -> bool: return app.player._chrome.modulate.a < 0.05):
		return "controls should fade again"
	# Checked on the activity clock right around the input, not on the fade
	# later: a moment of buffering on the real network also (rightly) brings
	# the controls back. push_input handles the event straight away.
	var before: float = app.player._last_activity
	app.player.get_viewport().push_input(jitter, true)
	if app.player._last_activity != before:
		return "pointer jitter shouldn't bring the controls back"
	print("ok: controls fade while watching, return on a deliberate move, ignore jitter")

	app._stop()
	if not await _until(func() -> bool: return _state().get("status") == "idle" and app.current_view == "browse"):
		return "stop should return to the catalog"
	if app.player.is_showing_video():
		return "the video should be cleared after stopping"
	print("ok: stop returns to the catalog")
	return ""


func _state() -> Dictionary:
	return app.local.state


func _cards() -> Array:
	return app.browse.find_children("*", "PosterCard", true, false)


func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT * 1000
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().create_timer(0.05).timeout
	return false


static func _as_failure(result: Variant) -> String:
	return result if result is String else "the test hit a script error (see the log above)"
