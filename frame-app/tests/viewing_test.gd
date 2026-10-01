extends Node
## Viewing effects in the 3D shell with a real on-device film (needs
## internet and the built-in player; run muted): the film on the screen,
## glow, floor reflection and room light following it, screen sizes, lean
## back, 3D modes, and resume via Continue watching.
## Run: STREAM_FRAME_MUTE=1 STREAM_FRAME_OFFLINE=1 STREAM_FRAME_SETTINGS_PATH=/tmp/x.cfg \
##   godot --headless --path . res://tests/viewing_test.tscn

const TIMEOUT := 40.0

var shell: Node3D
var app: Control


func _ready() -> void:
	shell = load("res://shell.tscn").instantiate()
	add_child(shell)
	app = shell.ui
	var failure: Variant = await _run()
	failure = _as_failure(failure)
	if failure == "":
		print("VIEWING TEST PASS")
		get_tree().quit(0)
	else:
		printerr("VIEWING TEST FAIL: " + failure)
		get_tree().quit(1)


func _run() -> Variant:
	if not app.local.embedded:
		return "needs the built-in player (native/build.sh)"
	app.open_source(ExtensionRegistry.by_id(app.sources, "nasa"))
	if not await _until(func() -> bool: return shell.wall._rows.size() > 3 and not shell.wall._loading and shell.wall._rows[0].tiles[0] != null):
		return "the NASA catalog didn't load"
	var item: Dictionary = shell.wall._rows[0].tiles[0].item
	app.play_item(item)
	if not await _until(func() -> bool: return app.local.state.get("status") == "playing" and app.player.video_reveal > 0.99):
		return "the film never started (status %s)" % app.local.state.get("status")
	var material: ShaderMaterial = shell.screen.material_override
	if material.get_shader_parameter("video_alpha") < 0.99 or material.get_shader_parameter("video_tex") == null:
		return "the screen should draw the film"
	if app.background.modulate.a > 0.01 or app.player._bg.modulate.a > 0.01:
		return "the UI behind the film should be transparent"
	print("ok: '%s' plays on the screen under a transparent UI" % item["title"])

	if not await _until(func() -> bool: return shell.glow.visible and shell.reflection.visible and shell._effects > 0.99):
		return "glow and floor reflection should fade in with the film"
	app.local._mpv.seek(75.0, false)  # into the film: light, not the countdown
	if not await _until(func() -> bool: return shell._spill.light_energy > 0.05 and shell._spill.light_color != Color.WHITE):
		return "the room light should follow the film (energy %.2f)" % shell._spill.light_energy
	print("ok: glow, floor reflection and room light follow the film (light %s)" % shell._spill.light_color)

	var widths := []
	for i in 3:
		app.player.screen_size_requested.emit()
		await get_tree().create_timer(0.6).timeout
		widths.append(snappedf(shell.screen.width, 0.1))
	var expected := [4.2, 1.9, 2.8]
	for i in 3:
		if not is_equal_approx(widths[i], expected[i]):
			return "Size should cycle imax -> tv -> cinema, got %s" % [widths]
	var saved_size: String = Settings.load_or_default().extension_value("device", "screen_size", "")
	if saved_size != "cinema":
		return "the screen size should be saved, got '%s'" % saved_size
	app.player.lean_back_requested.emit()
	if not await _until(func() -> bool: return absf(shell.screen.rotation.x - shell.LEAN_ANGLE) < 0.01):
		return "lean back should tilt the screen up"
	if shell.reflection.visible:
		return "the floor reflection should hide while leaning back"
	app.player.lean_back_requested.emit()
	if not await _until(func() -> bool: return absf(shell.screen.rotation.x) < 0.01):
		return "sitting up should bring the screen back"
	print("ok: screen sizes %s, lean back and back" % [widths])

	app.player._cycle_stereo()
	await _frames(2)  # process_frame fires before the shell's _process runs
	if material.get_shader_parameter("stereo_mode") != 1:
		return "3D side by side should reach the screen"
	app.player._cycle_stereo()
	app.player._cycle_stereo()
	await _frames(2)
	if material.get_shader_parameter("stereo_mode") != 0:
		return "cycling 3D modes should come back to 2D"
	print("ok: 3D modes reach the screen")

	# Leave part-way: it should be on Continue watching and resume there.
	app.local._mpv.seek(100.0, false)
	await _until(func() -> bool: return app.local._mpv.get_position() > 99.0)
	app._stop()
	if not await _until(func() -> bool: return app.local.state.get("status") == "idle"):
		return "stop didn't stop"
	var saved: Dictionary = app.local.resume_entries().get(item["watchUrl"], {})
	if saved.get("position", 0.0) < 95.0:
		return "stopping part-way should remember the position, got %s" % saved
	app.show_home()
	# The home: the extensions row, then Continue watching.
	var resume_row := func() -> Variant:
		for row in shell.wall._rows:
			if row.label.text == "Continue watching":
				return row
		return null
	if not await _until(func() -> bool: return resume_row.call() != null and shell.wall._rows[-1] == resume_row.call() and resume_row.call().tiles[0] != null):
		return "the home should have Continue watching under the extensions"
	var resume_item: Dictionary = resume_row.call().tiles[0].item
	if resume_item["watchUrl"] != item["watchUrl"] or not resume_item["display_title"].contains("min left"):
		return "Continue watching should show the title with time left: %s" % resume_item
	app.play_item(resume_item)
	if not await _until(func() -> bool: return app.local.state.get("status") == "playing" and app.local.state.get("position", 0.0) > 95.0):
		return "picking it again should resume near 100s (at %.1f)" % app.local.state.get("position", 0.0)
	print("ok: stopped at 100s -> Continue watching ('%s') -> resumes at %.0fs" % [resume_item["display_title"], app.local.state["position"]])
	app._stop()

	# Falling behind: a VP9 film decoded in software (on machines without a
	# VP9 decoder) switches to the lighter version where it was.
	app.open_source(ExtensionRegistry.by_id(app.sources, "open-movies"))
	if not await _until(func() -> bool: return not app.browse.is_loading() and shell.wall._rows.size() > 0 and not shell.wall._loading):
		return "the Open movies catalog didn't load"
	app.play_item(shell.wall._rows[0].items[0])
	if not await _until(func() -> bool: return app.local.state.get("status") == "playing" and app.local._mpv.get_position() > 3.0):
		return "the Open movies film didn't start"
	if app.local._mpv.get_stats()["hwdec"] != "no":
		print("ok: (skipped falling-behind check: this machine decodes VP9 in hardware)")
		app._stop()
		return ""
	app.local.keep_up_drops = -1  # any check counts as falling behind
	var before: float = app.local._mpv.get_position()
	if not await _until(func() -> bool: return app.local._media_url.ends_with(".720p.vp9.webm")):
		return "falling behind should switch to the 720p version"
	if not await _until(func() -> bool: return app.local._mpv.is_loaded() and app.local._mpv.get_video_size().y > 0 and app.local._mpv.get_position() >= before - 1.0):
		return "the lighter version should continue where it was (was at %.1f s, now %.1f s)" % [before, app.local._mpv.get_position()]
	if not app.settings.extension_value("device", "lighter_video", false):
		return "falling behind should be remembered (Lighter video on)"
	print("ok: falling behind in software decoding -> 720p at %.0f s, remembered" % app.local._mpv.get_position())
	app.local.keep_up_drops = 10
	app._stop()
	return ""


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
