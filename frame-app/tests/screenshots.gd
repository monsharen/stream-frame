extends Node
## Renders the main views to PNGs (needs a real display, not --headless).
## Run via: SCENE=res://tests/screenshots.tscn tests/run_selftest.sh

var app: Control


func _ready() -> void:
	var out := OS.get_environment("SCREENSHOT_DIR")
	app = load("res://main.tscn").instantiate()
	add_child(app)
	await _until(func() -> bool: return app.browse.find_children("*", "PosterCard", true, false).size() > 0)
	await get_tree().create_timer(3.0).timeout  # posters
	await _capture(out.path_join("browse.png"))
	app._play(app.browse.find_children("*", "PosterCard", true, false)[0].item)
	await _until(func() -> bool: return app.agent.state.get("status") == "playing")
	await _until(func() -> bool: return app.agent.state.get("status") == "paused")
	await get_tree().create_timer(1.0).timeout
	await _capture(out.path_join("player.png"))
	app._stop()
	await get_tree().create_timer(1.0).timeout
	app._open_settings()
	await get_tree().create_timer(0.5).timeout
	await _capture(out.path_join("settings.png"))
	get_tree().quit()


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _until(condition: Callable) -> bool:
	for _i in 300:
		if condition.call():
			return true
		await get_tree().create_timer(0.1).timeout
	return false
