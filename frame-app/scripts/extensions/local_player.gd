class_name LocalPlayer
extends AgentClient
## The backend for on-device sources: same interface as the host agent
## (catalog, play, control, state), so the app treats both alike.
##
## Stopgap until video plays on the 3D screen itself: titles open in an
## external player window (mpv by default). It reports loading/playing/idle
## but can't be paused or seeked from the app (state has external = true),
## so the player view shows the window's own controls are in charge.

## How long after launch the player is assumed to be showing video.
const STARTUP_SECONDS := 1.0

## Split on spaces; the video URL is appended.
var command := "mpv --fs --force-window=immediate"

var _pid := -1
var _started_at := 0.0


func configure(_base_url: String, _token: String) -> void:
	if not connected:
		_set_connected.call_deferred(true)


func request(method: HTTPClient.Method, path: String, body: Variant = null) -> Dictionary:
	await get_tree().process_frame  # stay asynchronous, like the remote backend
	if path.begins_with("/api/catalog/open-movies"):
		return {"ok": true, "data": OpenMovies.catalog("open-movies")}
	if path == "/api/state":
		return {"ok": true, "data": state}
	if method == HTTPClient.METHOD_POST and path == "/api/play":
		return _play(body.get("watchUrl", ""), body.get("title", ""))
	if method == HTTPClient.METHOD_POST and path == "/api/control":
		return _control(body.get("action", ""))
	return {"ok": false, "error": "Not available on this device: " + path}


func _play(watch_url: String, title: String) -> Dictionary:
	if OpenMovies.id_for(watch_url) == "":
		return {"ok": false, "error": "Unknown title"}
	_kill()
	var parts := command.split(" ", false)
	if parts.is_empty():
		return {"ok": false, "error": "No player command configured"}
	var args := parts.slice(1)
	args.append_array(["--title=" + title, watch_url])
	_pid = OS.create_process(parts[0], args)
	if _pid <= 0:
		_pid = -1
		return {"ok": false, "error": "Couldn't start the video player (%s). Is it installed?" % parts[0]}
	_started_at = Time.get_ticks_msec() / 1000.0
	_set_state({"status": "loading", "service": "open-movies", "title": title, "watchUrl": watch_url,
		"position": 0.0, "duration": 0.0, "error": null, "external": true})
	return {"ok": true, "data": state}


func _control(action: String) -> Dictionary:
	if action == "stop":
		_kill()
		_set_idle()
		return {"ok": true, "data": state}
	return {"ok": false, "error": "Use the player window's own controls for now."}


func _process(_delta: float) -> void:
	if _pid <= 0:
		return
	if not OS.is_process_running(_pid):
		_pid = -1
		_set_idle()  # the window was closed
	elif state["status"] == "loading" and Time.get_ticks_msec() / 1000.0 - _started_at >= STARTUP_SECONDS:
		_set_state({"status": "playing"})


func _exit_tree() -> void:
	_kill()


func _kill() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1


func _set_idle() -> void:
	state = {"status": "idle", "position": 0.0, "duration": 0.0}
	state_changed.emit(state)


func _set_state(patch: Dictionary) -> void:
	state.merge(patch, true)
	state_changed.emit(state)
