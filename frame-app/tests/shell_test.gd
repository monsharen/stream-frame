extends Node
## The 3D shell in desktop-preview mode (offline demo, headless): ray math on
## the curved screens, the movie wall following the catalog, and real mouse
## input travelling mouse -> head direction -> gaze ray -> target: a poster
## click starts playback, the deck's buttons work, the wheel scrolls the wall.
## Run: STREAM_FRAME_OFFLINE=1 STREAM_FRAME_DEMO_LATENCY=0.2 STREAM_FRAME_SETTINGS_PATH=/tmp/x.cfg \
##   godot --headless --path . res://tests/shell_test.tscn

const TIMEOUT := 15.0

var shell: Node3D


func _ready() -> void:
	shell = load("res://shell.tscn").instantiate()
	add_child(shell)
	var failure: Variant = await _run()
	failure = _as_failure(failure)
	if failure == "":
		print("SHELL TEST PASS")
		get_tree().quit(0)
	else:
		printerr("SHELL TEST FAIL: " + failure)
		get_tree().quit(1)


func _run() -> Variant:
	var screen: CurvedScreen = shell.screen
	var deck: CurvedScreen = shell.deck
	var wall: MovieWall = shell.wall
	if screen == null or shell.xr_active:
		return "expected the desktop preview"

	# pixel -> 3D point -> ray from the eye -> same pixel, on both screens.
	var eye := Vector3(0, shell.EYE_HEIGHT, 0)
	for target: CurvedScreen in [screen, deck]:
		for uv in [Vector2(0.01, 0.02), Vector2(0.5, 0.5), Vector2(0.99, 0.98), Vector2(0.2, 0.8)]:
			var pixel: Vector2 = target.region.position + uv * target.region.size
			var hit := target.intersect(eye, (target.pixel_to_point(pixel) - eye).normalized())
			if hit.is_empty() or hit.pixel.distance_to(pixel) > 0.5:
				return "round trip failed for %s: %s" % [pixel, hit]
	print("ok: ray/screen math round-trips (screen and deck)")

	var app: Control = shell.ui
	# The home: source tiles in two rows (on this device, from your PC).
	if not await _until(func() -> bool: return _tile_for_source("demo") != null and _tile_for_source("demo").item["source"]["available"]):
		return "the wall never showed the sources home with the demo PC source"
	if screen.visible or not deck.visible:
		return "browsing should show the deck, not the big screen"
	await _settle()
	print("ok: wall shows the sources home; deck visible, screen hidden")

	# A greyed-out source explains itself on the big screen.
	await _look(_tile_for_source("netflix").art.global_position)
	await _click()
	if not await _until(func() -> bool: return app.current_view == "info" and screen.visible and not wall.interactive):
		return "clicking a greyed-out source should show its info page on the big screen"
	if wall._dim_target != MovieWall.DIMMED:
		return "behind an info page the wall should be dimmed, not hidden"
	app.info_view.back_requested.emit()
	if not await _until(func() -> bool: return app.current_view == "browse" and wall.interactive):
		return "Back from the info page should return to the wall"
	await _settle()
	print("ok: greyed-out source -> info page on the screen -> back")

	# Open the demo PC source: its catalog replaces the sources on the wall.
	await _look(_tile_for_source("demo").art.global_position)
	await _click()
	if not await _until(func() -> bool: return wall._rows.size() == OfflineAgent.catalog()["rows"].size() and not wall._loading):
		return "opening a source should fill the wall with its catalog"
	await _settle()
	await get_tree().create_timer(MovieWall.LEAVE_SECONDS + 0.1).timeout
	if wall.get_child_count() != wall._rows.size():
		return "rows that animated out should be freed (%d children, %d rows)" % [wall.get_child_count(), wall._rows.size()]
	print("ok: source tile opens its catalog on the wall; the old rows animate out and are freed")

	# Look at the Refresh button on the deck and click it.
	var refresh: Button = app.browse._refresh
	if not await _look_and_click(deck.pixel_to_point(refresh.get_global_rect().get_center())):
		return "could not aim at the Refresh button"
	if not await _until(func() -> bool: return app.browse.is_loading()):
		return "clicking Refresh on the deck did nothing"
	print("ok: deck button clicked by gaze")
	if not await _until(func() -> bool: return not app.browse.is_loading() and not wall._loading and wall._rows.size() > 0):
		return "refresh never finished"
	await _settle()

	# Wheel down while looking at the wall scrolls it; the top rows fade away.
	await _look(wall._rows[0].tiles[0].art.global_position)
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN, 3)
	if not await _until(func() -> bool: return wall._scroll > 0.6):
		return "the wheel should scroll the wall"
	print("ok: wheel scrolls the wall (%.2f m)" % wall._scroll)
	await _wheel(MOUSE_BUTTON_WHEEL_UP, 10)
	if not await _until(func() -> bool: return is_zero_approx(wall._scroll)):
		return "scrolling back up should stop at the top"

	# Look at the second poster: it should highlight, then a click plays it.
	var tile: WallTile = wall._rows[1].tiles[1]
	await _look(tile.art.global_position)
	if not await _until(func() -> bool: return wall._hover == tile and tile.hover > 0.5):
		return "looking at a poster should highlight it"
	print("ok: gaze highlights '%s'" % tile.item["title"])
	await _click()
	if not await _until(func() -> bool: return app.agent.state.get("status") in ["loading", "playing"]):
		return "clicking a poster did not start playback"
	if app.agent.state.get("title") != tile.item["title"]:
		return "started the wrong title: %s" % app.agent.state.get("title")
	if not await _until(func() -> bool: return screen.visible and screen.pointer_hit(eye, Vector3.FORWARD).size() > 0):
		return "the big screen should take over after the poster flies in"
	if wall.interactive or deck.visible:
		return "the wall should be dimmed and the deck hidden while playing"
	if wall._dim_target != MovieWall.HIDDEN:
		return "while a film plays the wall should be hidden entirely, not just dimmed"
	if not await _until(func() -> bool: return shell._spill.light_energy < 0.2):
		return "the room lights should dim while a film plays"
	print("ok: poster click plays it; viewing mode: wall hidden, deck hidden, lights down")

	# The film's controls are on their own panel below the screen, never
	# over the picture: look at Pause there and click it.
	var bar: CurvedScreen = shell.controls_bar
	if not await _until(func() -> bool: return app.agent.state.get("status") == "playing" and app.player._controls.visible and bar.visible):
		return "the film's controls panel should show under the screen"
	var toggle: Control = app.player._toggle
	if toggle.get_global_rect().position.y < shell.UI_SIZE.y:
		return "the controls should sit in the strip below the screen's area"
	var pause_at := bar.pixel_to_point(toggle.get_global_rect().get_center())
	if pause_at.y >= screen.global_position.y - screen.height / 2.0:
		return "the controls panel should be below the screen"
	if not await _look_and_click(pause_at):
		return "could not aim at Pause on the controls panel"
	if not await _until(func() -> bool: return app.agent.state.get("status") == "paused"):
		return "clicking Pause on the controls panel should pause"
	print("ok: controls on their own panel below the screen; Pause clicked by gaze")

	app._stop()
	if not await _until(func() -> bool: return app.current_view == "browse" and wall.interactive and not screen.visible):
		return "stopping should bring the wall back"
	print("ok: stop brings the wall back")

	var home: Button = app.browse._home
	if not await _look_and_click(deck.pixel_to_point(home.get_global_rect().get_center())):
		return "could not aim at the Sources button"
	if not await _until(func() -> bool: return _tile_for_source("netflix") != null):
		return "the deck's Sources button should bring back the sources home"
	print("ok: deck's Sources button returns home")

	# A row longer than the wall (a real Netflix row has ~40 titles) starts
	# at the left edge and scrolls sideways with shift+wheel.
	var long_row := []
	for i in 30:
		long_row.append({"title": "Title %d" % i, "watchUrl": "offline://x%d" % i, "image": ""})
	wall.show_catalog({"rows": [{"title": "Long row", "items": long_row}]})
	var row: MovieWall.Row = wall._rows[0]
	if row.min_offset >= 0.0:
		return "a 30-title row should overflow the wall"
	await _settle()
	await _look(row.tiles[3].art.global_position)
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN, 4, true)
	if not await _until(func() -> bool: return row.offset < -0.4):
		return "shift+wheel should scroll the row sideways"
	if row.tiles[0] and row.tiles[0].visible:
		return "titles scrolled past the left edge should fade out (or be freed)"
	print("ok: long row overflows and scrolls sideways")
	return ""


func _tile_for_source(id: String) -> WallTile:
	for row in shell.wall._rows:
		for tile in row.tiles:  # slots are null for tiles not near view
			if tile and tile.item.get("kind") == "source" and tile.item["source"]["id"] == id and not tile.is_queued_for_deletion():
				return tile
	return null


## Lets freshly built rows finish rising into place before aiming at them.
func _settle() -> void:
	await _until(func() -> bool: return shell.wall.is_settled())
	for i in 2:
		await get_tree().process_frame


func _wheel(button: MouseButton, clicks: int, shift := false) -> void:
	for i in clicks:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = button
		wheel.pressed = true
		wheel.factor = 1.0
		wheel.shift_pressed = shift
		get_viewport().push_input(wheel, true)
		await get_tree().process_frame


## Moves the real mouse so the head turns to `point`, and waits until it has.
func _look(point: Vector3) -> void:
	var camera: DesktopRig = get_viewport().get_camera_3d()
	var motion := InputEventMouseMotion.new()
	motion.position = camera.mouse_for_direction(point - camera.global_position)
	motion.global_position = motion.position
	# Viewport coordinates, as real mouse events arrive after the OS window ->
	# viewport scaling (which a 64x64 headless window distorts).
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	camera.snap()
	await get_tree().process_frame


func _click() -> void:
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		get_viewport().push_input(click, true)
		await get_tree().process_frame


func _look_and_click(point: Vector3) -> bool:
	await _look(point)
	var hit: Dictionary = shell.router.hover_hit
	if hit.is_empty():
		return false
	await _click()
	return true


func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT * 1000
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().create_timer(0.05).timeout
	return false


## A script error aborts the test coroutine, which then returns null: that
## must count as a failure, not as "no failure message".
static func _as_failure(result: Variant) -> String:
	return result if result is String else "the test hit a script error (see the log above)"
