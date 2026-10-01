class_name LocalPlayer
extends AgentClient
## The backend for on-device extensions: same interface as the host agent
## (catalog, play, control, state), so the app treats both alike. Each
## on-device extension is a VideoProvider that builds its catalog and turns
## a title into a playable https URL.
##
## Titles play in-app through the libmpv extension (addons/mpv) when it is
## available and enabled: the video becomes a texture the player view shows
## (on the 3D screen in VR), with full pause/seek/buffering state. Otherwise
## they open in an external player window (state has external = true), which
## the app can only start and stop.

## How long after launch the player is assumed to be showing video.
const STARTUP_SECONDS := 1.0
## Split on spaces; {title} and {url} are substituted per argument (so they
## may contain spaces). Without {url}, "-- <url>" is appended. --no-ytdl
## stops mpv handing addresses to yt-dlp; "--" stops an address ever being
## read as an option.
const DEFAULT_COMMAND := "mpv --fs --force-window=immediate --no-ytdl --title={title} -- {url}"

var command := DEFAULT_COMMAND
var providers: Dictionary[String, VideoProvider] = {}
## Play in-app (needs the MpvPlayer extension). Set before _ready.
var embedded := LocalPlayer.builtin_available()
## Extra libmpv options, e.g. {"ao": "null"} to mute (tests). Set before _ready.
var mpv_options: Dictionary = {}

## Where to remember resume positions (set by the app).
var settings: Settings

## Resume a title from where it was left, unless barely started or nearly done.
const RESUME_MIN_SECONDS := 30.0
const RESUME_END_MARGIN := 60.0
const RESUME_SAVE_SECONDS := 10.0
const RESUME_KEEP := 20
## Keeping up: how often to check, and how many dropped frames in that
## time (while decoding in software) mean the device can't (see
## _check_keeping_up).
const KEEP_UP_SECONDS := 3.0
## Dropped frames per check that count as falling behind (tests lower it).
var keep_up_drops := 10

var _mpv: Node  # MpvPlayer
var _resume_pending := -1.0
var _last_saved := 0.0
## The last state values sent, to emit only on change.
var _reported := {}

var _pid := -1
var _started_at := 0.0
## Bumped on play/stop so a slow resolve can't start a superseded title.
var _generation := 0
## What's playing in the built-in player, and from which provider.
var _media_url := ""
var _provider: VideoProvider
var _next_check := 0.0
var _drops_at_check := 0
## Position to return to after switching to a lighter version.
var _seek_after_load := -1.0


static func builtin_available() -> bool:
	return ClassDB.class_exists("MpvPlayer")


func _ready() -> void:
	if embedded and builtin_available():
		_mpv = ClassDB.instantiate("MpvPlayer")
		for key in mpv_options:
			_mpv.set_option(key, mpv_options[key])
		_mpv.failed.connect(_on_mpv_failed)
		add_child(_mpv)
	else:
		embedded = false


## The in-app video, or null when titles play in an external window.
func video_texture() -> Texture2D:
	return _mpv.get_texture() if embedded else null


## The picture averaged into a small grid of colours (null without in-app video).
func ambient_texture() -> Texture2D:
	return _mpv.get_ambient_texture() if embedded else null


func average_color() -> Color:
	return _mpv.get_average_color() if embedded else Color.BLACK


## Where the picture is within the video frame, without baked-in black bars.
func content_rect() -> Rect2:
	return _mpv.get_content_rect() if embedded else Rect2(0, 0, 1, 1)


func add_provider(provider: VideoProvider, settings: Settings) -> void:
	provider.settings = settings
	providers[provider.id] = provider
	add_child(provider)


func configure(_base_url: String, _token: String) -> void:
	if not connected:
		_set_connected.call_deferred(true)


func request(method: HTTPClient.Method, path: String, body: Variant = null) -> Dictionary:
	await get_tree().process_frame  # always asynchronous, like the remote backend
	if path.begins_with("/api/search/"):
		var search_id := path.trim_prefix("/api/search/").get_slice("?", 0)
		if not providers.has(search_id):
			return {"ok": false, "error": "Search isn't available here."}
		return await providers[search_id].search(_query_value(path, "q"))
	if path.begins_with("/api/more/"):
		var more_id := path.trim_prefix("/api/more/").get_slice("?", 0)
		if not providers.has(more_id):
			return {"ok": true, "data": {"items": [], "done": true}}
		return await providers[more_id].more(_query_value(path, "row").to_int())
	if path.begins_with("/api/catalog/"):
		var provider_id := path.trim_prefix("/api/catalog/").get_slice("?", 0)
		if not providers.has(provider_id):
			return {"ok": false, "error": "Not available on this device: " + provider_id}
		return await providers[provider_id].catalog(path.ends_with("?refresh"))
	if path == "/api/state":
		return {"ok": true, "data": state}
	if method == HTTPClient.METHOD_POST and path == "/api/play":
		return await _play(body.get("service", ""), body.get("watchUrl", ""), body.get("title", ""), body.get("image", ""))
	if method == HTTPClient.METHOD_POST and path == "/api/control":
		return _control(body.get("action", ""), body.get("value"))
	return {"ok": false, "error": "Not available on this device: " + path}


func _play(provider_id: String, watch_url: String, title: String, image := "") -> Dictionary:
	var provider: VideoProvider = providers.get(provider_id)
	if provider == null:
		return {"ok": false, "error": "Not available on this device: " + provider_id}
	# A title from "Continue watching" was issued by this provider before.
	if resume_entries().has(watch_url):
		provider._issued[watch_url] = true
	_kill()
	_generation += 1
	var generation := _generation
	_set_state({"status": "loading", "service": provider_id, "title": title, "watchUrl": watch_url,
		"position": 0.0, "duration": 0.0, "error": null, "external": not embedded, "image": image})
	_resume_pending = resume_entries().get(watch_url, {}).get("position", -1.0)
	# First save after a while: right now the position is still pre-resume.
	_last_saved = Time.get_ticks_msec() / 1000.0
	var resolved: Dictionary = await provider.resolve(watch_url)
	if generation != _generation:
		return {"ok": false, "error": "Superseded"}
	if not resolved.ok:
		_set_state({"status": "error", "error": resolved.error})
		return resolved
	if embedded:
		_reported = {}
		var url: String = resolved.url
		# This device has struggled before: start on the lighter version.
		if settings and settings.extension_value("device", "lighter_video", false):
			var lighter := provider.lighter_url(url)
			url = lighter if lighter != "" else url
		_start_media(provider, url, -1.0)
		return {"ok": true, "data": state}
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


static func _query_value(path: String, key: String) -> String:
	for pair in path.get_slice("?", 1).split("&", false):
		if pair.get_slice("=", 0) == key:
			return pair.get_slice("=", 1).uri_decode()
	return ""


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


func _control(action: String, value: Variant = null) -> Dictionary:
	if action == "stop":
		_generation += 1
		_kill()
		if embedded:
			_remember_position()
			_mpv.stop()
		_set_idle()
		return {"ok": true, "data": state}
	if not embedded:
		return {"ok": false, "error": "Use the player window's own controls."}
	if state.get("status") in ["idle", "error"]:
		return {"ok": false, "error": "Nothing is playing"}
	match action:
		"toggle":
			_mpv.set_paused(not _mpv.is_paused())
		"play":
			_mpv.set_paused(false)
		"pause":
			_mpv.set_paused(true)
		"seekBy", "seekTo":
			if not (value is float or value is int):
				return {"ok": false, "error": "value must be a number of seconds"}
			_mpv.seek(float(value), action == "seekBy")
		_:
			return {"ok": false, "error": "Unknown action: " + action}
	_sync_embedded()
	return {"ok": true, "data": state}


func _process(_delta: float) -> void:
	if embedded:
		_sync_embedded()
		return
	if _pid <= 0:
		return
	if not OS.is_process_running(_pid):
		_pid = -1
		_set_idle()  # the window was closed
	elif state["status"] == "loading" and Time.get_ticks_msec() / 1000.0 - _started_at >= STARTUP_SECONDS:
		_set_state({"status": "playing"})


func _start_media(provider: VideoProvider, url: String, seek_to: float) -> void:
	_provider = provider
	_media_url = url
	_seek_after_load = seek_to
	_next_check = Time.get_ticks_msec() / 1000.0 + KEEP_UP_SECONDS * 2.0  # let it settle first
	_drops_at_check = 0
	# Plain http only for the provider's own trusted server.
	_mpv.set_allow_http(url.begins_with("http://"))
	_mpv.load(url)


## If the device decodes this video in software and keeps dropping frames
## (a 2014 laptop with VP9, say: it heats up and falls behind), switch to
## the provider's lighter version at the same position, and remember to
## start there next time. The user sees a moment of buffering, then a
## smooth film.
func _check_keeping_up(now: float) -> void:
	if now < _next_check or _provider == null:
		return
	_next_check = now + KEEP_UP_SECONDS
	var stats: Dictionary = _mpv.get_stats()
	var drops: int = stats.get("output_dropped", 0) + stats.get("decoder_dropped", 0)
	var new_drops := drops - _drops_at_check
	_drops_at_check = drops
	if stats.get("hwdec", "no") != "no" or new_drops < keep_up_drops:
		return
	var lighter := _provider.lighter_url(_media_url)
	if lighter == "":
		return
	if settings:
		settings.set_extension_value("device", "lighter_video", true)
		settings.save()
	_start_media(_provider, lighter, _mpv.get_position())


## Mirrors the in-app player's state into ours, emitting on change.
func _sync_embedded() -> void:
	var status: String = state.get("status", "idle")
	if status in ["idle", "error"]:
		return
	if not _mpv.is_loaded() or _mpv.get_video_size().x == 0:
		return  # still loading
	var next := {
		"status": "ended" if _mpv.has_ended() else "buffering" if _mpv.is_buffering() and not _mpv.is_paused()
			else "paused" if _mpv.is_paused() else "playing",
		"position": _mpv.get_position(),
		"duration": _mpv.get_duration(),
	}
	# Back to where we were, after switching to a lighter version.
	if _seek_after_load >= 0.0:
		_mpv.seek(_seek_after_load, false)
		next["position"] = _seek_after_load
		_seek_after_load = -1.0
	# Pick up where this title was left last time.
	if _resume_pending >= RESUME_MIN_SECONDS and _resume_pending < next["duration"] - RESUME_END_MARGIN:
		_mpv.seek(_resume_pending, false)
		next["position"] = _resume_pending
	_resume_pending = -1.0
	var now := Time.get_ticks_msec() / 1000.0
	if next["status"] == "playing":
		_check_keeping_up(now)
	if next["status"] == "ended":
		_forget_position(state.get("watchUrl", ""))
	elif next["status"] in ["playing", "paused"] and now - _last_saved > RESUME_SAVE_SECONDS:
		_last_saved = now
		_remember_position()
	# Positions arrive every frame; report about twice a second, like the
	# host agent, plus every status change.
	var changed: bool = next["status"] != _reported.get("status") or next["duration"] != _reported.get("duration") \
		or absf(next["position"] - _reported.get("position", -10.0)) >= 0.5
	if changed:
		_reported = next
		_set_state(next)
	else:
		state.merge(next, true)


## On-device titles to resume: watchUrl -> {source, title, image, position, duration, at}.
func resume_entries() -> Dictionary:
	return settings.extension_value("device", "resume", {}) if settings else {}


func _remember_position() -> void:
	var watch_url: String = state.get("watchUrl", "")
	var position: float = _mpv.get_position() if embedded else 0.0
	var duration: float = _mpv.get_duration() if embedded else 0.0
	if not settings or watch_url == "" or duration <= 0.0:
		return
	if position < RESUME_MIN_SECONDS or position > duration - RESUME_END_MARGIN:
		_forget_position(watch_url)
		return
	var entries := resume_entries().duplicate()
	entries[watch_url] = {
		"source": state.get("service", ""), "title": state.get("title", ""), "image": state.get("image", ""),
		"position": position, "duration": duration, "at": Time.get_unix_time_from_system(),
	}
	# Keep the most recent few.
	var urls := entries.keys()
	urls.sort_custom(func(a: String, b: String) -> bool: return entries[a]["at"] > entries[b]["at"])
	for old in urls.slice(RESUME_KEEP):
		entries.erase(old)
	settings.set_extension_value("device", "resume", entries)
	settings.save()


func _forget_position(watch_url: String) -> void:
	if settings and resume_entries().has(watch_url):
		var entries := resume_entries().duplicate()
		entries.erase(watch_url)
		settings.set_extension_value("device", "resume", entries)
		settings.save()


func _on_mpv_failed(message: String) -> void:
	if state.get("status") not in ["idle", "error"]:
		_set_state({"status": "error", "error": "Couldn't play this video: " + message})


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
