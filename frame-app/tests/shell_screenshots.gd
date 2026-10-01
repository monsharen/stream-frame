extends Node
## Renders the 3D shell (desktop preview, offline demo) to PNGs, including
## the README images. Needs a display, and the window must be drawn: Wayland
## stops rendering hidden windows, so on Wayland run it through XWayland:
##   STREAM_FRAME_OFFLINE=1 SCREENSHOT_DIR=/tmp/shots godot --display-driver x11 \
##     --disable-vsync --resolution 1600x900 --path . res://tests/shell_screenshots.tscn

const SHOT_SIZE := Vector2i(1600, 900)

var shell: Node3D
var camera: DesktopRig
## Renders the same world at a fixed size, whatever the window's size.
var _shot := SubViewport.new()
var _shot_camera := Camera3D.new()


func _ready() -> void:
	var out := OS.get_environment("SCREENSHOT_DIR")
	shell = load("res://shell.tscn").instantiate()
	add_child(shell)
	camera = get_viewport().get_camera_3d()
	# Scripted camera: don't trap the real mouse or let it steer.
	camera.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_shot.size = SHOT_SIZE
	_shot.world_3d = get_viewport().world_3d
	_shot.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_shot_camera.fov = camera.fov
	_shot.add_child(_shot_camera)
	add_child(_shot)
	var wall: MovieWall = shell.wall
	var ui: Control = shell.ui
	# The sources home, then a greyed-out source's info page.
	while not ExtensionRegistry.by_id(ui.sources, "demo").get("available", false):
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(0.5).timeout
	await _aim(Vector3(0, 1.3, -3.0))
	await _capture(out.path_join("shell_sources.png"))
	ui.open_source(ExtensionRegistry.by_id(ui.sources, "netflix"))
	await get_tree().create_timer(0.8).timeout
	await _aim(Vector3(0, 1.6, -2.4))
	await _capture(out.path_join("shell_info.png"))
	ui.open_extensions("peertube")
	await get_tree().create_timer(0.8).timeout
	await _capture(out.path_join("shell_extensions.png"))

	# A live on-device catalog: the Internet Archive (needs internet).
	ui.open_source(ExtensionRegistry.by_id(ui.sources, "internet-archive"))
	while ui.browse.is_loading() or wall._loading or wall._rows.size() < 3:
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(6.0).timeout  # posters
	await _aim(Vector3(0, 1.4, -3.0))
	await _capture(out.path_join("shell_archive.png"))
	ui.show_home()

	ui.open_source(ExtensionRegistry.by_id(ui.sources, "demo"))
	while ui.browse.is_loading() or wall._loading or wall._rows.size() < 3:
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(4.0).timeout  # posters

	await _aim(Vector3(0, 1.45, -3.0))
	await _capture(out.path_join("shell_wall.png"))

	var tile: WallTile = wall._rows[1].tiles[4]
	await _aim(tile.art.global_position)
	await get_tree().create_timer(0.6).timeout  # hover lift
	await _capture(out.path_join("shell_hover.png"))

	await _aim(tile.art.global_position)
	shell.router.button(true)
	shell.router.button(false)
	await get_tree().create_timer(0.3).timeout  # mid-flight
	await _capture(out.path_join("shell_flight.png"))
	await _aim(Vector3(0, 1.5, -2.4))
	while shell.ui.agent.state.get("status") != "playing":
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(1.0).timeout
	await _capture(out.path_join("shell_player.png"))
	get_tree().quit()


func _aim(point: Vector3) -> void:
	camera._target = camera.look_for_mouse(camera.mouse_for_direction(point - camera.global_position))
	camera.snap()
	# process_frame fires before nodes process, so wait two: one for the rig
	# to cast the new gaze ray, one more to be safe.
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(path: String) -> void:
	_shot_camera.global_transform = camera.global_transform
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := _shot.get_texture().get_image()
	# The gaze reticle, as the desktop preview shows it.
	var center := Vector2i(SHOT_SIZE / 2)
	for x in range(-6, 7):
		for y in range(-6, 7):
			if x * x + y * y <= 36:
				image.set_pixelv(center + Vector2i(x, y), UiTheme.ACCENT if shell.router.hover_target else Color.WHITE)
	image.save_png(path)
	print("saved ", path)
