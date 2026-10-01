class_name OfflineAgent
extends AgentClient
## Stands in for the host agent so the app can be tried with no PC at all:
## serves a fixed catalog and simulates playback locally. Same interface as
## AgentClient, so the rest of the app can't tell the difference.
##
## Timings mimic the real thing (a LAN round trip, the host scraping a
## streaming site, a DRM'd title starting up, rebuffering after a seek), so
## the app's loading states get exercised. STREAM_FRAME_DEMO_LATENCY scales
## them: 0 makes everything instant, 2 doubles it.

## [min, max] seconds for each kind of operation.
const TIMINGS := {
	"request": [0.08, 0.25],      # LAN round trip + agent work
	"catalog": [0.6, 1.2],        # first load: agent reads its cache
	"refresh": [3.0, 5.0],        # agent scrapes the service's site
	"start": [3.5, 6.0],          # page load, DRM license, first frames
	"seek_buffer": [0.6, 1.6],    # rebuffering after a seek
	"stop": [0.3, 0.6],
}

const WATCH_PREFIX := "offline://"

var _latency := 1.0
## Bumped on play/stop so timers from a superseded title don't fire into
## the current one.
var _generation := 0


func _ready() -> void:
	var scale := OS.get_environment("STREAM_FRAME_DEMO_LATENCY")
	if scale.is_valid_float():
		_latency = maxf(0.0, scale.to_float())


func configure(_base_url: String, _token: String) -> void:
	if not connected:
		_set_connected.call_deferred(true)


func request(method: HTTPClient.Method, path: String, body: Variant = null) -> Dictionary:
	await _wait("request")
	if path == "/api/services":
		return {"ok": true, "data": [{"id": "demo", "name": "Demo (open movies)"}]}
	if path.begins_with("/api/catalog/"):
		await _wait("refresh" if path.ends_with("?refresh") else "catalog")
		return {"ok": true, "data": catalog()}
	if path == "/api/state":
		return {"ok": true, "data": state}
	if method == HTTPClient.METHOD_POST and path == "/api/play":
		return _play(body.get("watchUrl", ""))
	if method == HTTPClient.METHOD_POST and path == "/api/control":
		return await _control(body.get("action", ""), body.get("value"))
	return {"ok": false, "error": "Not available offline: " + path}


func _play(watch_url: String) -> Dictionary:
	var item := _find(watch_url)
	if item.is_empty():
		return {"ok": false, "error": "Unknown title"}
	_generation += 1
	var generation := _generation
	_set_state({"status": "loading", "service": "demo", "title": item["title"], "watchUrl": watch_url,
		"position": 0.0, "duration": 0.0, "error": null})
	_after("start", generation, func() -> void:
		_set_state({"status": "playing", "duration": item["duration"]}))
	return {"ok": true, "data": state}


func _control(action: String, value: Variant) -> Dictionary:
	var status: String = state["status"]
	if status in ["idle", "error"]:
		return {"ok": false, "error": "Nothing is playing"}
	var duration: float = state["duration"]
	match action:
		"toggle":
			_set_state({"status": "playing" if status == "paused" else "paused"})
		"play":
			_set_state({"status": "playing"})
		"pause":
			_set_state({"status": "paused"})
		"seekBy", "seekTo":
			if not (value is float or value is int):
				return {"ok": false, "error": "value must be a number of seconds"}
			var target: float = float(value) + (state["position"] if action == "seekBy" else 0.0)
			_set_state({"position": clampf(target, 0.0, duration)})
			if status != "paused":
				_set_state({"status": "buffering"})
				_after("seek_buffer", _generation, func() -> void:
					if state["status"] == "buffering":
						_set_state({"status": "playing"}))
		"stop":
			_generation += 1
			await _wait("stop")
			state = {"status": "idle", "position": 0.0, "duration": 0.0}
			state_changed.emit(state)
		_:
			return {"ok": false, "error": "Unknown action: " + action}
	return {"ok": true, "data": state}


func _process(delta: float) -> void:
	if state["status"] != "playing":
		return
	var position: float = state["position"] + delta
	if position >= state["duration"]:
		_set_state({"status": "ended", "position": state["duration"]})
	else:
		state["position"] = position
		# Throttle to roughly the real agent's update rate.
		if int(position * 2.0) != int((position - delta) * 2.0):
			state_changed.emit(state)


func _wait(kind: String) -> void:
	var bounds: Array = TIMINGS[kind]
	await get_tree().create_timer(randf_range(bounds[0], bounds[1]) * _latency).timeout


## Runs `then` after a delay, unless a newer play/stop happened meanwhile.
func _after(kind: String, generation: int, then: Callable) -> void:
	await _wait(kind)
	if generation == _generation:
		then.call()


func _set_state(patch: Dictionary) -> void:
	state.merge(patch, true)
	state_changed.emit(state)


## The demo PC service's catalog (a fresh copy each time).
static func catalog() -> Dictionary:
	return OpenMovies.catalog("demo", WATCH_PREFIX)


func _find(watch_url: String) -> Dictionary:
	var id := OpenMovies.id_for(watch_url, WATCH_PREFIX)
	return OpenMovies.item(id, WATCH_PREFIX) if OpenMovies.FILMS.has(id) else {}
