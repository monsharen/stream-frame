extends Node
## Renders the 3D shell (desktop preview, offline demo) to PNGs. Needs a display.
## Run: STREAM_FRAME_OFFLINE=1 SCREENSHOT_DIR=/tmp/shots godot --path . res://tests/shell_screenshots.tscn

var shell: Node3D


func _ready() -> void:
	var out := OS.get_environment("SCREENSHOT_DIR")
	shell = load("res://shell.tscn").instantiate()
	add_child(shell)
	var app: Control = shell.ui
	while app.browse.find_children("*", "PosterCard", true, false).is_empty():
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(3.0).timeout  # posters
	await _capture(out.path_join("shell_front.png"))

	var camera: Camera3D = get_viewport().get_camera_3d()
	camera.basis = Basis.from_euler(Vector3(deg_to_rad(-12), deg_to_rad(28), 0))
	camera.position = Vector3(0.9, 1.75, 0.8)
	await _capture(out.path_join("shell_angle.png"))

	camera.basis = Basis()
	camera.position = Vector3(0, shell.EYE_HEIGHT, 0)
	app._play(app.browse.find_children("*", "PosterCard", true, false)[1].item)
	while app.agent.state.get("status") != "playing":
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(2.0).timeout
	await _capture(out.path_join("shell_player.png"))
	get_tree().quit()


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
