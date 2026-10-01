class_name LocalPlayer
extends AgentClient
## The backend for on-device extensions: same interface as the host agent
## (catalog, play, control, state), so the app treats both alike. Each
## on-device extension is a VideoProvider that builds its catalog and turns
## a title into a playable https URL.
##
## Stopgap until video plays on the 3D screen itself: titles open in an
## external player window (mpv by default). It reports loading/playing/idle
## but can't be paused or seeked from the app (state has external = true),
## so the player view shows the window's own controls are in charge.

## How long after launch the player is assumed to be showing video.
const STARTUP_SECONDS := 1.0
## Split on spaces; {title} and {url} are substituted per argument (so they
## may contain spaces). Without {url}, "-- <url>" is appended. --no-ytdl
## stops mpv handing addresses to yt-dlp; "--" stops an address ever being
## read as an option.
const DEFAULT_COMMAND := "mpv --fs --force-window=immediate --no-ytdl --title={title} -- {url}"

var command := DEFAULT_COMMAND
var providers: Dictionary[String, VideoProvider] = {}

var _pid := -1
var _started_at := 0.0
## Bumped on play/stop so a slow resolve can't start a superseded title.
var _generation := 0


func add_provider(provider: VideoProvider, settings: Settings) -> void:
	provider.settings = settings
	providers[provider.id] = provider
	add_child(provider)


func configure(_base_url: String, _token: String) -> void:
	if not connected:
		_set_connected.call_deferred(true)


func request(method: HTTPClient.Method, path: String, body: Variant = null) -> Dictionary:
	await get_tree().process_frame  # always asynchronous, like the remote backend
	if path.begins_with("/api/catalog/"):
		var provider_id := path.trim_prefix("/api/catalog/").get_slice("?", 0)
		if not providers.has(provider_id):
			return {"ok": false, "error": "Not available on this device: " + provider_id}
		return await providers[provider_id].catalog(path.ends_with("?refresh"))
	if path == "/api/state":
		return {"ok": true, "data": state}
	if method == HTTPClient.METHOD_POST and path == "/api/play":
		return await _play(body.get("service", ""), body.get("watchUrl", ""), body.get("title", ""))
	if method == HTTPClient.METHOD_POST and path == "/api/control":
		return _control(body.get("action", ""))
	return {"ok": false, "error": "Not available on this device: " + path}


func _play(provider_id: String, watch_url: String, title: String) -> Dictionary:
	var provider: VideoProvider = providers.get(provider_id)
	if provider == null:
		return {"ok": false, "error": "Not available on this device: " + provider_id}
	_kill()
	_generation += 1
	var generation := _generation
	_set_state({"status": "loading", "service": provider_id, "title": title, "watchUrl": watch_url,
		"position": 0.0, "duration": 0.0, "error": null, "external": true})
	var resolved: Dictionary = await provider.resolve(watch_url)
	if generation != _generation:
		return {"ok": false, "error": "Superseded"}
	if not resolved.ok:
		_set_state({"status": "error", "error": resolved.error})
		return resolved
	var args := build_args(command, title, resolved.url)
	if args.is_empty():
		_set_state({"status": "error", "error": "No video player configured"})
		return {"ok": false, "error": "No video player configured"}
	_pid = OS.create_process(args[0], args.slice(1))
	if _pid <= 0:
		_pid = -1
		var message := "Couldn't start the video player (%s). Is it installed? Change it under Extensions." % args[0]
		_set_state({"status": "error", "error": message})
		return {"ok": false, "error": message}
	_started_at = Time.get_ticks_msec() / 1000.0
	return {"ok": true, "data": state}


## The player command line for one title (exposed for tests).
static func build_args(template: String, title: String, url: String) -> PackedStringArray:
	# mpv expands ${...} in its window title; titles come from third parties.
	var safe_title := title.replace("$", "").replace("\n", " ")
	var args := PackedStringArray()
	var has_url := false
	for part in template.split(" ", false):
		has_url = has_url or part.contains("{url}")
		args.append(part.replace("{title}", safe_title).replace("{url}", url))
	if not has_url and not args.is_empty():
		args.append_array(["--", url])
	return args


func _control(action: String) -> Dictionary:
	if action == "stop":
		_generation += 1
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
