extends Node
## Loading states, headless. First pass (host configured but unreachable):
## the home shows PC sources connecting, then offline with Try again; a
## catalog that fails to load shows an error with a working Retry. Second
## pass (offline demo, realistic timings): skeletons, refresh keeping rows,
## starting overlay, optimistic seek with controls locked, buffering,
## stopping.
## Run: STREAM_FRAME_AGENT_URL=http://127.0.0.1:9 STREAM_FRAME_SETTINGS_PATH=/tmp/x.cfg \
##   godot --headless --path . res://tests/loading_test.tscn

const MainScript := preload("res://scripts/main.gd")
const TIMEOUT := 15.0

var app: Control


func _ready() -> void:
	app = load("res://main.tscn").instantiate()
	add_child(app)
	var failure: Variant
	if MainScript.offline_override == null:
		failure = await _run_error_pass()
	else:
		failure = await _run_offline_pass()
	failure = _as_failure(failure)
	if failure == "reloading":
		return
	if failure == "":
		print("LOADING TEST PASS")
		get_tree().quit(0)
	else:
		printerr("LOADING TEST FAIL: " + failure)
		get_tree().quit(1)


func _run_error_pass() -> Variant:
	var browse: BrowseView = app.browse
	if _source("netflix").get("status") != "Connecting…" or browse._note.text != "Connecting to your PC…":
		return "PC sources should show as connecting at first"
	print("ok: PC sources connecting")
	if not await _until(func() -> bool: return _source("netflix").get("status") == "PC offline"):
		return "an unreachable host should mark PC sources offline"
	if not "retry" in _source("netflix")["actions"] or browse._note.text != "PC offline":
		return "offline PC sources should offer Try again"
	print("ok: unreachable host -> PC sources offline (%s)" % _source("netflix")["reason"])
	app.open_source(_source("netflix"))
	app.info_view.action_requested.emit("retry")
	if _source("netflix").get("status") != "Connecting…":
		return "Try again should re-check the PC"
	if not await _until(func() -> bool: return app.info_view._status.text == "PC offline"):
		return "the info page should update once the re-check fails"
	print("ok: Try again re-checks and updates the info page")

	# A catalog that fails to load: error with a Retry that loads again.
	app._current_source = {"id": "missing", "name": "Missing", "kind": "local"}
	app._load_catalog(false)
	if not await _until(func() -> bool: return browse._retry.visible):
		return "a failed catalog load should show an error with Retry"
	browse._retry.pressed.emit()
	if not browse.is_loading():
		return "Retry should start loading again"
	print("ok: catalog error -> Retry -> loading again")
	MainScript.offline_override = true
	get_tree().reload_current_scene.call_deferred()
	return "reloading"


func _run_offline_pass() -> Variant:
	var browse: BrowseView = app.browse
	var player: PlayerView = app.player
	if not await _until(func() -> bool: return _source("demo").get("available", false)):
		return "the demo PC source never became available"
	app.open_source(_source("demo"))
	if not browse.is_loading():
		return "opening a source should show a loading state"
	await get_tree().create_timer(BrowseView.SKELETON_DELAY + 0.1).timeout
	if _cards().is_empty() and not browse._skeleton.visible:
		return "skeleton rows should show while the catalog loads"
	print("ok: loading -> skeleton rows")
	if not await _until(func() -> bool: return _cards().size() == _demo_cards()):
		return "catalog never loaded"
	if browse._skeleton.visible or browse.is_loading():
		return "skeleton/loading should clear once the catalog is shown"
	print("ok: catalog replaces skeleton")

	var started := Time.get_ticks_msec()
	browse.refresh_requested.emit()
	await get_tree().process_frame
	if not browse.is_loading() or not browse._refresh.disabled:
		return "refresh should show loading and disable Refresh"
	if _cards().size() != _demo_cards() or browse._skeleton.visible:
		return "refresh should keep the current rows instead of skeletons"
	if not await _until(func() -> bool: return not browse.is_loading() and _cards().size() == _demo_cards()):
		return "refresh never finished"
	var took := (Time.get_ticks_msec() - started) / 1000.0
	if took < 2.5:
		return "demo refresh should take realistically long, took %.1fs" % took
	print("ok: refresh kept rows and took %.1fs" % took)

	app.play_item(_cards()[0].item)
	await get_tree().process_frame
	if not player._overlay.visible or not player._overlay_label.text.begins_with("Starting"):
		return "starting a title should show the starting overlay"
	if player._controls.visible:
		return "playback controls should be hidden while starting"
	print("ok: starting overlay ('%s')" % player._overlay_label.text)
	if not await _until(func() -> bool: return _status() == "playing"):
		return "never started playing"
	await get_tree().process_frame
	if player._overlay.visible or not player._controls.visible:
		return "overlay should clear and controls appear once playing"
	print("ok: playing -> overlay gone, controls shown")

	var before: float = player._scrubber.value
	player._seek_by(10.0)
	await get_tree().process_frame
	if player._scrubber.value < before + 9.0:
		return "seek should move the scrubber immediately"
	var buttons_locked: bool = (player._controls.get_child(0) as Button).disabled
	if not await _until(func() -> bool: return _status() == "buffering"):
		return "seeking while playing should rebuffer in the demo"
	await get_tree().process_frame
	if not player._overlay.visible or player._overlay_label.text != "Buffering…":
		return "buffering should show the spinner overlay"
	if not buttons_locked:
		return "controls should be disabled while the seek is in flight"
	print("ok: optimistic seek, controls locked, buffering overlay")
	if not await _until(func() -> bool: return _status() == "playing"):
		return "never recovered from buffering"
	print("ok: buffering -> playing")

	app._stop()
	await get_tree().process_frame
	if player._overlay_label.text != "Stopping…":
		return "stop should show Stopping…"
	if not await _until(func() -> bool: return _status() == "idle" and browse.visible):
		return "stop never returned to browse"
	print("ok: Stopping… -> browse")
	return ""


func _source(id: String) -> Dictionary:
	return ExtensionRegistry.by_id(app.sources, id)


func _status() -> String:
	return app.agent.state.get("status", "")


func _demo_cards() -> int:
	var count := 0
	for row in OfflineAgent.catalog()["rows"]:
		count += row["items"].size()
	return count


func _cards() -> Array:
	return app.browse.find_children("*", "PosterCard", true, false)


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
