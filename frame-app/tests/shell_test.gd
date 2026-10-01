extends Node
## The 3D shell in desktop-preview mode (offline demo, headless): the curved
## screen's ray math, and a real mouse click travelling camera ray -> screen
## hit -> UI. Run: STREAM_FRAME_OFFLINE=1 STREAM_FRAME_SETTINGS_PATH=/tmp/x.cfg \
##   godot --headless --path . res://tests/shell_test.tscn

const TIMEOUT := 10.0

var shell: Node3D


func _ready() -> void:
	shell = load("res://shell.tscn").instantiate()
	add_child(shell)
	var failure: String = await _run()
	if failure == "":
		print("SHELL TEST PASS")
		get_tree().quit(0)
	else:
		printerr("SHELL TEST FAIL: " + failure)
		get_tree().quit(1)


func _run() -> String:
	var screen: CurvedScreen = shell.screen
	if screen == null or shell.xr_active:
		return "expected desktop preview with a curved screen"

	# pixel -> 3D point -> ray from the eye -> same pixel, across the screen.
	var eye := Vector3(0, shell.EYE_HEIGHT, 0)
	for pixel in [Vector2(10, 10), Vector2(960, 540), Vector2(1900, 1070), Vector2(300, 900)]:
		var point := screen.pixel_to_point(pixel)
		var hit := screen.intersect(eye, (point - eye).normalized())
		if hit.is_empty() or hit.pixel.distance_to(pixel) > 0.5:
			return "round trip failed for %s: %s" % [pixel, hit]
	if not screen.intersect(eye, Vector3.BACK).is_empty():
		return "looking away from the screen must not hit it"
	print("ok: ray/screen math round-trips")

	var app: Control = shell.ui
	if not await _until(func() -> bool: return _cards(app).size() > 0):
		return "catalog never showed"
	var card: PosterCard = _cards(app)[0]
	await get_tree().process_frame
	var camera: Camera3D = get_viewport().get_camera_3d()
	var target := screen.pixel_to_point(card.get_global_rect().get_center())
	var viewport_pos := camera.unproject_position(target)
	print("clicking '%s' at %s" % [card.item["title"], viewport_pos])
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = viewport_pos
		click.global_position = viewport_pos
		# Viewport coordinates, as real mouse events arrive after the OS
		# window -> viewport scaling (which a 64x64 headless window distorts).
		get_viewport().push_input(click, true)
		await get_tree().process_frame
	if not await _until(func() -> bool: return app.agent.state.get("status") in ["loading", "playing"]):
		return "clicking the poster in 3D did not start playback"
	print("ok: 3D click started '%s'" % app.agent.state.get("title"))
	return ""


func _cards(app: Control) -> Array:
	return app.browse.find_children("*", "PosterCard", true, false)


func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT * 1000
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().create_timer(0.1).timeout
	return false
