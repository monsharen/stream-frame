class_name OfflineAgent
extends AgentClient
## Stands in for the host agent so the app can be tried with no PC at all:
## serves a fixed catalog and simulates playback locally. Same interface as
## AgentClient, so the rest of the app can't tell the difference.

const LOAD_SECONDS := 1.5

const _POSTERS := "https://upload.wikimedia.org/wikipedia/commons/thumb/"
const CATALOG := {
	"service": "demo",
	"rows": [{
		"title": "Blender open movies",
		"items": [
			{"id": "sintel", "watchUrl": "offline://sintel", "title": "Sintel", "duration": 888.0,
				"image": _POSTERS + "8/8f/Sintel_poster.jpg/330px-Sintel_poster.jpg"},
			{"id": "tears-of-steel", "watchUrl": "offline://tears-of-steel", "title": "Tears of Steel", "duration": 734.0,
				"image": _POSTERS + "7/70/Tos-poster.png/330px-Tos-poster.png"},
			{"id": "big-buck-bunny", "watchUrl": "offline://big-buck-bunny", "title": "Big Buck Bunny", "duration": 596.0,
				"image": _POSTERS + "c/c5/Big_buck_bunny_poster_big.jpg/330px-Big_buck_bunny_poster_big.jpg"},
		],
	}],
}


func configure(_base_url: String, _token: String) -> void:
	if not connected:
		_set_connected.call_deferred(true)


func request(method: HTTPClient.Method, path: String, body: Variant = null) -> Dictionary:
	await get_tree().process_frame  # stay asynchronous, like the real thing
	if path == "/api/services":
		return {"ok": true, "data": [{"id": "demo", "name": "Offline demo"}]}
	if path.begins_with("/api/catalog/"):
		return {"ok": true, "data": CATALOG.duplicate(true)}  # callers may annotate it
	if path == "/api/state":
		return {"ok": true, "data": state}
	if method == HTTPClient.METHOD_POST and path == "/api/play":
		return _play(body.get("watchUrl", ""))
	if method == HTTPClient.METHOD_POST and path == "/api/control":
		return _control(body.get("action", ""), body.get("value"))
	return {"ok": false, "error": "Not available offline: " + path}


func _play(watch_url: String) -> Dictionary:
	var item := _find(watch_url)
	if item.is_empty():
		return {"ok": false, "error": "Unknown title"}
	_set_state({"status": "loading", "service": "demo", "title": item["title"], "watchUrl": watch_url,
		"position": 0.0, "duration": 0.0, "error": null})
	get_tree().create_timer(LOAD_SECONDS).timeout.connect(func() -> void:
		if state.get("watchUrl") == watch_url and state["status"] == "loading":
			_set_state({"status": "playing", "duration": item["duration"]}))
	return {"ok": true, "data": state}


func _control(action: String, value: Variant) -> Dictionary:
	var status: String = state["status"]
	if status == "idle":
		return {"ok": false, "error": "Nothing is playing"}
	var duration: float = state["duration"]
	match action:
		"toggle":
			_set_state({"status": "paused" if status == "playing" else "playing"})
		"play":
			_set_state({"status": "playing"})
		"pause":
			_set_state({"status": "paused"})
		"seekBy":
			_set_state({"position": clampf(state["position"] + float(value), 0.0, duration)})
		"seekTo":
			_set_state({"position": clampf(float(value), 0.0, duration)})
		"stop":
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


func _set_state(patch: Dictionary) -> void:
	state.merge(patch, true)
	state_changed.emit(state)


func _find(watch_url: String) -> Dictionary:
	for item in CATALOG["rows"][0]["items"]:
		if item["watchUrl"] == watch_url:
			return item
	return {}
