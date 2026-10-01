extends Node
## Offline demo mode, headless and with no host agent running. Starts from an
## unconfigured app and enters the demo the way a user would: the settings
## screen's "Try offline demo" button (which reloads this scene). Then saves
## real settings and checks the app leaves offline mode (another reload).
## Run: STREAM_FRAME_SETTINGS_PATH=/tmp/x.cfg godot --headless --path . res://tests/offline_test.tscn

const MainScript := preload("res://scripts/main.gd")
const TIMEOUT := 10.0

var app: Control


func _ready() -> void:
	app = load("res://main.tscn").instantiate()
	add_child(app)
	var failure: String = await _run()
	if failure == "":
		print("OFFLINE TEST PASS")
		get_tree().quit(0)
	elif failure != "reloading":
		printerr("OFFLINE TEST FAIL: " + failure)
		get_tree().quit(1)


func _run() -> String:
	if MainScript.offline_override == false:
		# Third pass: after saving real settings.
		if app.offline or app.agent is OfflineAgent:
			return "saving settings did not leave offline mode"
		print("ok: 'Save and connect' left offline mode")
		return ""
	if MainScript.offline_override == null:
		if not app.settings_view.visible:
			return "unconfigured app should open on the settings screen"
		var demo_button := _button(app.settings_view, "Try offline demo")
		if demo_button == null:
			return "no 'Try offline demo' button"
		print("ok: settings screen shown, pressing 'Try offline demo'")
		demo_button.pressed.emit()
		return "reloading"

	if not app.offline or not (app.agent is OfflineAgent):
		return "app did not come back up in offline mode"
	if not await _until(func() -> bool: return _cards().size() == 3):
		return "offline catalog did not show 3 cards"
	print("ok: offline catalog with %d titles" % _cards().size())

	app._play(_cards()[0].item)
	if not await _until(func() -> bool: return _status() == "playing"):
		return "simulated playback never started (status=%s)" % _status()
	var start: float = app.agent.state["position"]
	await get_tree().create_timer(1.2).timeout
	if app.agent.state["position"] <= start:
		return "position did not advance while playing"
	if app.stream.is_running() or _button(app.player, "Show stream").visible:
		return "offline mode must not open or offer a stream"
	print("ok: playing, position advancing, no stream")

	app._control("toggle", null)
	if not await _until(func() -> bool: return _status() == "paused"):
		return "toggle did not pause"
	app._control("seekTo", 300.0)
	if not await _until(func() -> bool: return is_equal_approx(app.agent.state["position"], 300.0)):
		return "seek did not land"
	print("ok: pause and seek")

	app._stop()
	if not await _until(func() -> bool: return _status() == "idle" and app.browse.visible):
		return "stop did not return to browse"
	print("ok: stop -> browse")

	app._open_settings()
	var url_field: LineEdit = app.settings_view._fields["agent_url"]
	url_field.text = "127.0.0.1:9"  # nothing listens; we only check the mode switch
	_button(app.settings_view, "Save and connect").pressed.emit()
	return "reloading"


func _status() -> String:
	return app.agent.state.get("status", "")


func _cards() -> Array:
	return app.browse.find_children("*", "PosterCard", true, false)


func _button(root: Node, text: String) -> Button:
	for b: Button in root.find_children("*", "Button", true, false):
		if b.text == text:
			return b
	return null


func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT * 1000
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().create_timer(0.1).timeout
	return false
