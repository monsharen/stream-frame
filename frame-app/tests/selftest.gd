extends Node
## End-to-end check of the app against a running host agent (Demo service),
## with tests/fake_moonlight.sh standing in for Moonlight. Run via
## tests/run_selftest.sh, which sets up the agent and environment.

const TIMEOUT := 30.0

var app: Control


func _ready() -> void:
	app = load("res://main.tscn").instantiate()
	add_child(app)
	var failure: String = await _run()
	if failure == "":
		print("SELFTEST PASS")
		get_tree().quit(0)
	else:
		printerr("SELFTEST FAIL: " + failure)
		get_tree().quit(1)


func _run() -> String:
	if not await _until(func() -> bool: return _cards().size() > 0):
		return "catalog never showed any cards"
	var card: PosterCard = _cards()[0]
	print("playing: ", card.item["title"])
	card.pressed.emit()

	if not await _until(func() -> bool: return _status() == "playing" and app.stream.is_running()):
		return "playback did not start with the stream open (status=%s)" % _status()
	print("ok: playing, stream window open")

	# fake_moonlight exits on its own: the user closed the stream window.
	if not await _until(func() -> bool: return not app.stream.is_running() and _status() == "paused"):
		return "closing the stream did not pause playback (status=%s)" % _status()
	print("ok: stream closed -> paused")

	app._show_stream()
	if not await _until(func() -> bool: return app.stream.is_running() and _status() == "playing"):
		return "Show stream did not reopen and resume (status=%s)" % _status()
	print("ok: show stream -> reopened and playing")

	app._control("seekTo", 30.0)
	if not await _until(func() -> bool: return app.agent.state.get("position", 0.0) >= 30.0):
		return "seek was not reflected in state"
	print("ok: seek")

	app._stop()
	if not await _until(func() -> bool: return _status() == "idle" and app.browse.visible and not app.stream.is_running()):
		return "stop did not return to browse (status=%s)" % _status()
	print("ok: stop -> browse")
	return ""


func _status() -> String:
	return app.agent.state.get("status", "")


func _cards() -> Array:
	return app.browse.find_children("*", "PosterCard", true, false)


func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT * 1000
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().create_timer(0.1).timeout
	return false
