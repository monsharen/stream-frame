extends Node
## Performance measurements for the 3D shell (desktop preview, one eye's
## worth of pixels): GPU time and real (wall-clock) frame time in typical
## scenes, what each part of the scene costs (by switching it off), and
## hitches: the worst frame and how many took over 20 ms while something
## happens (opening a catalog, scrolling the wall). Numbers are for this
## machine; on the headset compare them relative to each other.
##   STREAM_FRAME_MUTE=1 godot --display-driver x11 --disable-vsync \
##     --resolution 1920x1920 --path . res://tools/perf.tscn
## Playing a film needs internet and the built-in player.

const FRAMES := 180

var shell: Node3D
var app: Control
var _results := []


func _ready() -> void:
	shell = load("res://shell.tscn").instantiate()
	add_child(shell)
	app = shell.ui
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await _wait(4.0)

	await _measure("home (wall of extensions)")
	if OS.get_environment("PERF_QUICK") == "1":
		print("QUICK home GPU %.2f ms" % _results[0][1])
		get_tree().quit()
		return
	await _without("  without the night sky", func(on: bool) -> void:
		shell._environment.background_mode = Environment.BG_SKY if on else Environment.BG_COLOR)
	await _without("  without the water", func(on: bool) -> void:
		shell._floor_material.shader = shell.FLOOR_SHADER if on else _plain_shader())
	await _without("  without the UI viewport redraw", func(on: bool) -> void:
		shell.ui_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED)

	# Hitches while a catalog opens (posters decode, tiles appear) and
	# while scrolling (tiles made and freed).
	app.open_source(ExtensionRegistry.by_id(app.sources, "internet-archive"))
	await _hitches("opening a catalog (Internet Archive)", 6.0)
	await _measure("catalog wall (posters)")
	var scroller := func() -> void:
		for i in 12:
			shell.wall.pointer_scroll({}, 1.0, 0.0)
			await get_tree().create_timer(0.15).timeout
	scroller.call()
	await _hitches("scrolling the wall", 2.5)
	app.show_home()
	await _wait(1.0)
	app.open_source(ExtensionRegistry.by_id(app.sources, "open-movies"))
	await _until(func() -> bool: return not app.browse.is_loading() and shell.wall._rows.size() > 2)
	await _wait(3.0)

	if app.local.embedded:
		app.play_item(shell.wall._rows[0].items[0])
		await _until(func() -> bool: return app.local.state.get("status") == "playing" and app.player.video_reveal > 0.99)
		await _wait(8.0)  # controls faded, sky dimmed
		app.local._mpv.reset_stats()
		await _measure("watching a film (1080p, built-in player)")
		_video_stats("  video frames during that", app.local._mpv.get_stats())
		await _without("  without the night sky", func(on: bool) -> void:
			shell._environment.background_mode = Environment.BG_SKY if on else Environment.BG_COLOR)
		await _without("  without the water", func(on: bool) -> void:
			shell._floor_material.shader = shell.FLOOR_SHADER if on else _plain_shader())
		await _without("  without the UI viewport redraw", func(on: bool) -> void:
			shell.ui_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED)
		app._stop()

	print("\n%-46s %8s %8s %8s %6s" % ["scene", "GPU ms", "frame ms", "worst", ">20ms"])
	for r in _results:
		print("%-46s %8s %8.2f %8.1f %6d" % [r[0], "-" if r[1] < 0.0 else "%.2f" % r[1], r[2], r[3], r[4]])
	get_tree().quit()


func _measure(label: String) -> void:
	var rid := get_viewport().get_viewport_rid()
	var gpu := 0.0
	await _wait(0.5)
	var frames := []
	var last := Time.get_ticks_usec()
	for i in FRAMES:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	_record(label, gpu / FRAMES, frames)


## Frame times for `seconds` from now, while something happens.
func _hitches(label: String, seconds: float) -> void:
	var frames := []
	var last := Time.get_ticks_usec()
	var end := last + int(seconds * 1000000.0)
	while last < end:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
	_record(label, -1.0, frames)


func _record(label: String, gpu: float, frames: Array) -> void:
	var total := 0.0
	var worst := 0.0
	var slow := 0
	for f: float in frames:
		total += f
		worst = maxf(worst, f)
		slow += 1 if f > 20.0 else 0
	_results.append([label, gpu, total / frames.size(), worst, slow])


## The player's own timing: render thread per frame, main-thread upload.
func _video_stats(label: String, stats: Dictionary) -> void:
	print("%s: %d rendered (%.1f ms avg, %.1f worst, render thread), %d uploaded (%.2f ms avg, %.1f worst, main thread)" % [
		label, stats["renders"], stats["render_ms"], stats["render_worst_ms"],
		stats["uploads"], stats["upload_ms"], stats["upload_worst_ms"]])


func _without(label: String, toggle: Callable) -> void:
	toggle.call(false)
	await _measure(label)
	toggle.call(true)


func _plain_shader() -> Shader:
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nvoid fragment() { ALBEDO = vec3(0.02); }\n"
	return shader


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(condition: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < deadline and not condition.call():
		await get_tree().create_timer(0.1).timeout
