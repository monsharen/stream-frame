extends Node
## Input actions in the 3D shell (offline demo): Escape is Back everywhere
## (the view's own things first: the player's options, a search), a mouse
## back button and a VR controller's action do the same, the player's
## bindings work, and bindings can be changed (and Escape can't be taken
## from Back).
## Run: STREAM_FRAME_OFFLINE=1 STREAM_FRAME_SETTINGS_PATH=/tmp/x.cfg \
##   godot --headless --path . res://tests/input_test.tscn

const TIMEOUT := 15.0

var shell: Node3D
var app: Control


func _ready() -> void:
	shell = load("res://shell.tscn").instantiate()
	add_child(shell)
	app = shell.ui
	var failure: Variant = await _run()
	failure = _as_failure(failure)
	if failure == "":
		print("INPUT TEST PASS")
		get_tree().quit(0)
	else:
		printerr("INPUT TEST FAIL: " + failure)
		get_tree().quit(1)


func _run() -> Variant:
	if not await _until(func() -> bool: return ExtensionRegistry.by_id(app.sources, "demo").get("available", false)):
		return "the demo PC source never became available"

	# Inside a catalog, Escape goes home.
	if not await _open_demo():
		return "the demo catalog didn't load"
	await _key(KEY_ESCAPE)
	if not _at_home():
		return "Escape in a catalog should go home"
	print("ok: Escape in a catalog -> home")

	# An info page and the Extensions app: Escape goes home.
	app.open_source(ExtensionRegistry.by_id(app.sources, "netflix"))
	await _frames(2)
	if app.current_view != "info":
		return "Netflix (no PC) should open its info page"
	await _key(KEY_ESCAPE)
	if not _at_home():
		return "Escape on an info page should go home"
	app.open_extensions()
	await _frames(2)
	await _key(KEY_ESCAPE)
	if not _at_home():
		return "Escape in the Extensions app should go home"
	print("ok: Escape on an info page / in Extensions -> home")

	# Search results: Escape leaves the search first, then the catalog.
	if not await _open_demo():
		return "the demo catalog didn't load again"
	var browse: BrowseView = app.browse
	browse._search.text = "a"
	browse._search.text_submitted.emit("a")
	if not await _until(func() -> bool: return browse._clear_search.visible and not browse.is_loading()):
		return "searching didn't show results"
	browse._search.grab_focus()
	await _frames(2)
	await _key(KEY_ESCAPE)
	if not browse._clear_search.visible or browse._search.has_focus():
		return "Escape while typing should only stop typing (results %s, focus %s)" % [browse._clear_search.visible, browse._search.has_focus()]
	await _key(KEY_ESCAPE)
	if browse._clear_search.visible or _at_home():
		return "Escape on search results should go back to the catalog"
	await _key(KEY_ESCAPE)
	if not _at_home():
		return "Escape after leaving the search should go home"
	print("ok: Escape stops typing, then leaves the search, then the catalog")

	# The player: O opens the options, Escape closes them, Escape stops.
	if not await _open_demo():
		return "the demo catalog didn't load for playback"
	app.play_item(shell.wall._rows[0].items[0])
	if not await _until(func() -> bool: return app.agent.state.get("status") == "playing" and app.player._controls.visible):
		return "the demo film didn't start"
	await _key(KEY_O)
	if not app.player._options.visible:
		return "O should open the viewing options"
	await _key(KEY_ESCAPE)
	if app.player._options.visible or app.current_view != "player":
		return "Escape should first close the viewing options"
	await _key(KEY_SPACE)
	if not await _until(func() -> bool: return app.agent.state.get("status") == "paused"):
		return "Space should pause"
	await _key(KEY_ESCAPE)
	if not await _until(func() -> bool: return app.current_view == "browse"):
		return "Escape should stop the film"
	print("ok: player: O options, Escape closes them, Space pauses, Escape stops")

	# Other ways to say Back: a mouse back button, a VR controller's action.
	app.open_extensions()
	await _frames(2)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_XBUTTON1
	mouse.pressed = true
	Input.parse_input_event(mouse)
	await _frames(3)
	if not _at_home():
		return "the mouse back button should go back"
	app.open_extensions()
	await _frames(2)
	if InputActions.for_xr_button("by_button") != InputActions.BACK:
		return "the controller's B/Y should be bound to Back"
	var action := InputEventAction.new()
	action.action = InputActions.BACK
	action.pressed = true
	Input.parse_input_event(action)
	await _frames(3)
	if not _at_home():
		return "a Back action (e.g. from a VR controller) should go back"
	print("ok: mouse back button and controller Back")

	# Rebinding: H becomes Home; J moves from seeking to Home; Escape stays Back.
	var settings: Settings = app.settings
	InputActions.bind(settings, InputActions.HOME, "key:H")
	InputActions.bind(settings, InputActions.HOME, "key:J")
	if "key:J" in InputActions.bindings(settings, InputActions.SEEK_BACK):
		return "binding J to Home should take it off Back 10 seconds"
	if InputActions.bind(settings, InputActions.HOME, "key:Escape"):
		return "Escape must stay Back"
	InputActions.unbind(settings, InputActions.BACK, "key:Escape")
	if not await _open_demo():
		return "the demo catalog didn't load for rebinding"
	await _key(KEY_H)
	if not _at_home():
		return "H (bound to Home) should go home"
	if not await _open_demo():
		return "the demo catalog didn't load for the last check"
	await _key(KEY_ESCAPE)
	if not _at_home():
		return "Escape must still go back after changing bindings"
	var saved: Variant = Settings.load_or_default().extension_value(InputActions.SETTINGS_ID, InputActions.HOME, [])
	if not "key:H" in Array(saved):
		return "bindings should be saved, got %s" % [saved]
	print("ok: rebinding (saved, moved off other actions, Escape kept as Back)")
	return ""


func _open_demo() -> bool:
	app.open_source(ExtensionRegistry.by_id(app.sources, "demo"))
	return await _until(func() -> bool: return app.current_view == "browse" and not app._current_source.is_empty() \
		and not app.browse.is_loading() and shell.wall._rows.size() > 0 and not shell.wall._loading)


func _at_home() -> bool:
	return app.current_view == "browse" and app._current_source.is_empty()


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT * 1000
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().create_timer(0.05).timeout
	return false


static func _as_failure(result: Variant) -> String:
	return result if result is String else "the test hit a script error (see the log above)"
