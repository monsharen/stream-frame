extends Control
## App controller. Starts on the home: the enabled extensions (sources of
## video, on this device or from your PC) and the Extensions app for
## enabling, disabling and configuring them. Launching an extension shows
## its catalog, or, if it can't be used right now, what's up and what to do
## next.
##
## Each extension has a backend with the same interface (AgentClient): the
## host agent for PC extensions, LocalPlayer for on-device ones. The playing
## backend's state drives the player view and, for the PC, the stream window;
## PC playback started from another remote (e.g. the phone web UI) is picked
## up too.

## "browse", "player", "extensions" or "info", whenever the visible view changes.
signal view_changed(view: String)

## Statuses where something is on screen.
const ACTIVE := ["playing", "buffering", "paused"]
## The Extensions app, shown on the home after the extensions.
const EXTENSIONS_APP := {
	"id": "extensions", "name": "Extensions", "kind": "app", "color": Color("3d4350"),
	"available": true, "problem": false, "status": "Enable, disable, configure",
}
## Cross-fade between views.
const VIEW_FADE_OUT := 0.15
const VIEW_FADE_IN := 0.25

## Offline demo: a built-in fake agent stands in for the PC. Set from the
## Extensions app or an info page, kept across the scene reload that
## switches modes; null = use the --offline flag / STREAM_FRAME_OFFLINE env.
static var offline_override: Variant = null

var offline: bool = offline_override if offline_override != null \
		else ("--offline" in OS.get_cmdline_user_args() or OS.get_environment("STREAM_FRAME_OFFLINE") == "1")
var settings := Settings.load_or_default()
## The PC.
var agent: AgentClient = OfflineAgent.new() if offline else AgentClient.new()
## This device.
var local := LocalPlayer.new()
var images := ImageCache.new()
var posters := PosterFactory.new()
var stream := StreamLauncher.new()

var browse: BrowseView
var player: PlayerView
var extensions_view: ExtensionsView
var info_view: SourceInfoView

## Every extension, enabled or not, with its current status.
var extensions: Array = []
## What the home shows: the enabled extensions, then the Extensions app.
var sources: Array = []
var current_view := ""
## The app's backdrop; the 3D shell fades it out under an on-screen film.
var background := ColorRect.new()
var _view_fades: Dictionary = {}

var _host := ExtensionRegistry.Host.CONNECTING
var _agent_services: Array = []
## The extension whose catalog is shown; {} on the home.
var _current_source: Dictionary = {}
## The last error while using the current extension, for "What's wrong?".
var _current_error := ""
## The catalog (or search results) as the source gave it; shown sorted and
## filtered by the browse tools.
var _catalog_raw: Dictionary = {}
var _showing_results := false
var _more_pending := {}
## The backend the player view follows.
var _playback: AgentClient
## What Retry on the browse screen re-runs (the last thing that failed).
var _retry: Callable = func() -> void: pass
var _control_pending := false
var _queued_control: Array = []
var _checking_host := false
## watchUrl -> image, so the player backdrop works for any known title.
var _artwork: Dictionary[String, String] = {}
## Set when the user closes the stream window, so we don't reopen it on the
## next state update. Cleared when they ask for it again or start a new title.
var _stream_dismissed := false


func _ready() -> void:
	theme = UiTheme.build()
	InputActions.apply(settings)
	add_child(FocusHighlight.new())
	var bg := background
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_apply_extension_config()
	local.settings = settings
	if OS.get_environment("STREAM_FRAME_MUTE") == "1":
		local.mpv_options["ao"] = "null"  # development: no sound from the built-in player
	for provider: VideoProvider in [OpenMoviesProvider.new(), InternetArchiveProvider.new(),
			NasaProvider.new(), PeerTubeProvider.new(), JellyfinProvider.new()]:
		local.add_provider(provider, settings)
	images.posters = posters
	posters.images = images
	for node: Node in [agent, local, images, posters, stream]:
		add_child(node)
	_playback = agent

	browse = BrowseView.new(images)
	player = PlayerView.new(images)
	player.offline = offline
	extensions_view = ExtensionsView.new(settings)
	info_view = SourceInfoView.new()
	for view: Control in [browse, player, extensions_view, info_view]:
		view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		view.visible = false
		add_child(view)

	browse.source_chosen.connect(open_source)
	browse.back_requested.connect(go_back)
	browse.refresh_requested.connect(func() -> void:
		if not browse.is_loading() and not _current_source.is_empty():
			_load_catalog(true))
	browse.retry_requested.connect(func() -> void: _retry.call())
	browse.help_requested.connect(func() -> void: _show_info(_current_source["id"], _current_error))
	browse.item_chosen.connect(play_item)
	browse.search_requested.connect(_search)
	browse.search_cleared.connect(func() -> void:
		_showing_results = false
		_load_catalog(false))
	browse.arrange_changed.connect(_present)
	browse.row_end_reached.connect(load_more)
	info_view.back_requested.connect(go_back)
	info_view.action_requested.connect(_on_info_action)
	extensions_view.back_requested.connect(go_back)
	extensions_view.extension_toggled.connect(func(_id: String, _on: bool) -> void: _rebuild())
	extensions_view.extension_configured.connect(func(id: String) -> void:
		var builtin_was: bool = local.embedded
		_apply_extension_config()
		if local.providers.has(id) and local.providers[id].has_method("reset"):
			local.providers[id].reset()  # sign in again with the new settings
		var builtin_now: bool = settings.extension_value("device", "builtin_player", true) and LocalPlayer.builtin_available()
		if id == ExtensionsView.DEVICE and builtin_now != builtin_was:
			# Switching players means a different backend setup: restart.
			get_tree().reload_current_scene.call_deferred()
			return
		_rebuild())
	extensions_view.pc_saved.connect(func() -> void:
		if offline:
			_switch_mode(false)
		else:
			_connect_to_host())
	extensions_view.demo_requested.connect(_switch_mode)
	player.control_requested.connect(_control)
	player.show_stream_requested.connect(_show_stream)
	player.back_requested.connect(go_back)
	agent.state_changed.connect(_on_state_changed.bind(agent))
	local.state_changed.connect(_on_state_changed.bind(local))
	agent.connection_changed.connect(_on_connection_changed)
	stream.closed.connect(_on_stream_closed)
	stream.opened.connect(_refresh_player)
	stream.failed.connect(func(message: String) -> void:
		_stream_dismissed = true
		player.show_error(message))

	local.configure("", "")
	_rebuild()
	show_home()
	_connect_to_host()


## Checks which PC extensions are available. Re-run whenever the connection
## changes or the PC connection is saved.
func _connect_to_host() -> void:
	if not offline and not settings.is_configured():
		_set_host(ExtensionRegistry.Host.NOT_CONFIGURED, [])
		return
	if _checking_host:
		return
	_checking_host = true
	agent.configure(settings.agent_url, settings.token)
	_set_host(ExtensionRegistry.Host.CONNECTING, _agent_services)
	var res := await agent.request(HTTPClient.METHOD_GET, "/api/services")
	_checking_host = false
	if res.ok:
		_set_host(ExtensionRegistry.Host.DEMO if offline else ExtensionRegistry.Host.ONLINE, res.data)
	else:
		_set_host(ExtensionRegistry.Host.OFFLINE, [])


func _set_host(host: ExtensionRegistry.Host, services: Array) -> void:
	_host = host
	_agent_services = services
	_rebuild()


## Recomputes every extension's status and refreshes whatever shows them.
func _rebuild() -> void:
	extensions = ExtensionRegistry.build(settings, _host, _agent_services)
	sources = ExtensionRegistry.enabled(extensions) + [EXTENSIONS_APP.duplicate()]
	for entry: Dictionary in extensions + [sources[-1]]:
		posters.describe(entry)
		entry["image"] = PosterFactory.url_for(entry)
	if _current_source.is_empty() and current_view == "browse":
		browse.show_sources(sources, continue_watching())
	if current_view == "info":
		_refresh_info()
	if current_view == "extensions":
		extensions_view.update_status(extensions, pc_status())


## One line about the PC connection, for the Extensions app.
func pc_status() -> String:
	match _host:
		ExtensionRegistry.Host.NOT_CONFIGURED:
			return "Not set up"
		ExtensionRegistry.Host.CONNECTING:
			return "Connecting to %s…" % settings.agent_url
		ExtensionRegistry.Host.OFFLINE:
			return "Offline: couldn't reach %s" % settings.agent_url
		ExtensionRegistry.Host.DEMO:
			return "Offline demo (no PC)"
	return "Connected to %s" % settings.agent_url


func _apply_extension_config() -> void:
	local.command = settings.player_command
	if not local.is_inside_tree():
		local.embedded = settings.extension_value("device", "builtin_player", true) and LocalPlayer.builtin_available()


## Back, from any back button or binding (InputActions.BACK): first the
## current view may close something of its own (the player's options, a
## search), otherwise up one level: the film stops, a page or a catalog
## gives way to the home.
func go_back() -> void:
	var view: Control = _view_node(current_view)
	if view and view.has_method("handle_back") and view.handle_back():
		return
	match current_view:
		"player":
			_stop()
		"info", "extensions":
			show_home()
		"browse":
			if not _current_source.is_empty():
				show_home()


func _view_node(view_name: String) -> Control:
	return {"browse": browse, "player": player, "extensions": extensions_view, "info": info_view}.get(view_name)


## Back while typing only stops typing (before the text field sees it: it
## would drop focus and pass the key on, so one press would do two things).
## Mouse buttons bound to actions (e.g. the back button) act here too:
## otherwise the control under the pointer would take the click.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.BACK) and get_viewport().gui_get_focus_owner() is LineEdit:
		get_viewport().gui_get_focus_owner().release_focus()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		_act(event)


## App actions (InputActions) that aren't handled by a focused control.
func _unhandled_input(event: InputEvent) -> void:
	_act(event)


func _act(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(InputActions.BACK):
		go_back()
	elif event.is_action_pressed(InputActions.HOME):
		if current_view == "player":
			_stop()
		show_home()
	elif current_view == "player" and event.is_action_pressed(InputActions.PLAY_PAUSE):
		player.toggle()
	elif current_view == "player" and event.is_action_pressed(InputActions.SEEK_BACK):
		player.seek_by(-10.0)
	elif current_view == "player" and event.is_action_pressed(InputActions.SEEK_FORWARD):
		player.seek_by(10.0)
	elif current_view == "player" and event.is_action_pressed(InputActions.OPTIONS):
		player.toggle_options()
	else:
		return
	get_viewport().set_input_as_handled()


func show_home() -> void:
	_current_source = {}
	browse.show_sources(sources, continue_watching())
	_show(browse)


## On-device titles left part-way, most recent first (only from extensions
## that are enabled and available).
func continue_watching() -> Array:
	var entries: Dictionary = local.resume_entries()
	var items := []
	for url: String in entries:
		var entry: Dictionary = entries[url]
		var source := ExtensionRegistry.by_id(extensions, entry.get("source", ""))
		if source.is_empty() or not source["enabled"] or not source["available"]:
			continue
		var minutes_left := ceili((entry["duration"] - entry["position"]) / 60.0)
		items.append({
			"title": entry["title"], "image": entry.get("image", ""), "watchUrl": url, "source": entry["source"],
			"display_title": "%s · %d min left" % [entry["title"], minutes_left], "at": entry["at"],
		})
		_artwork[url] = entry.get("image", "")
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["at"] > b["at"])
	return items


func open_source(source: Dictionary) -> void:
	if source["kind"] == "app":
		open_extensions()
		return
	if not source["available"]:
		_show_info(source["id"])
		return
	_current_source = source
	settings.last_source = source["id"]
	settings.save()
	# Search needs the source's own API: on-device sources have one.
	browse.enter_source(source["name"], source["kind"] == "local")
	_showing_results = false
	_show(browse)
	_load_catalog(false)


## Opens the Extensions app; `select` is an extension id or ExtensionsView.PC.
func open_extensions(select := "") -> void:
	extensions_view.open(extensions, pc_status(), offline, select)
	_show(extensions_view)


func _show_info(extension_id: String, error := "") -> void:
	info_view.show_source(ExtensionRegistry.by_id(extensions, extension_id), error)
	_show(info_view)


func _load_catalog(refresh: bool) -> void:
	var source := _current_source
	# A refresh re-reads the service's site on the host (several seconds);
	# keep the current rows up meanwhile.
	browse.show_loading("Refreshing %s from the service…" % source["name"] if refresh else "Loading %s…" % source["name"], refresh)
	var res := await _backend(source).request(HTTPClient.METHOD_GET,
		"/api/catalog/%s%s" % [source["id"], "?refresh" if refresh else ""])
	if _current_source != source:
		return  # the user went elsewhere while this was loading
	if not res.ok:
		_retry = _load_catalog.bind(refresh)
		_current_error = res.error
		# "What's wrong?" only helps when we know the extension.
		browse.show_error(res.error, not ExtensionRegistry.by_id(extensions, source["id"]).is_empty())
		return
	for row in res.data.get("rows", []):
		_adopt(row["items"], source)
	_catalog_raw = res.data
	_more_pending.clear()
	_present()


## Remembers where each title came from (the user may move on while these
## cards are still on screen) and its artwork (for the player's backdrop).
func _adopt(items: Array, source: Dictionary) -> void:
	for item in items:
		item["source"] = source["id"]
		_artwork[item["watchUrl"]] = item.get("image", "")


## Shows the current catalog or results, sorted and filtered.
func _present() -> void:
	if _catalog_raw.is_empty():
		return
	var has_years := false
	var has_durations := false
	for row in _catalog_raw.get("rows", []):
		for item in row["items"]:
			has_years = has_years or item.has("year")
			has_durations = has_durations or item.has("duration")
	browse.set_arrange_options(has_years, has_durations)
	var arranged := _arrange(_catalog_raw)
	# Paging adds to the source's own rows, so only while they're shown as is.
	arranged["_paging"] = not _showing_results and _current_source.get("kind") == "local" \
		and browse.sort_mode() == 0 and browse.length_mode() == 0
	browse.show_catalog(arranged)


func _arrange(catalog: Dictionary) -> Dictionary:
	var sort := browse.sort_mode()
	var length := browse.length_mode()
	var rows := []
	for row in catalog.get("rows", []):
		var items: Array = row["items"].filter(func(item: Dictionary) -> bool: return _fits_length(item, length))
		match sort:
			1: items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["title"].naturalnocasecmp_to(b["title"]) < 0)
			2: items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.get("year", 0) > b.get("year", 0))
			3: items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.get("year", 9999) < b.get("year", 9999))
			4: items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.get("duration", INF) < b.get("duration", INF))
			5: items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.get("duration", 0.0) > b.get("duration", 0.0))
		if not items.is_empty() or (sort == 0 and length == 0):
			rows.append({"title": row["title"], "items": items})
	return {"service": catalog.get("service", ""), "rows": rows}


static func _fits_length(item: Dictionary, length: int) -> bool:
	if length == 0:
		return true
	if not item.has("duration"):
		return false
	var minutes: float = item["duration"] / 60.0
	match length:
		1: return minutes < 10.0
		2: return minutes >= 10.0 and minutes <= 60.0
		3: return minutes > 60.0
	return true


func _search(query: String) -> void:
	var source := _current_source
	if source.is_empty() or source["kind"] != "local":
		return
	browse.show_loading("Searching %s for “%s”…" % [source["name"], query])
	var res := await local.request(HTTPClient.METHOD_GET, "/api/search/%s?q=%s" % [source["id"], query.uri_encode()])
	if _current_source != source:
		return
	if not res.ok:
		_retry = _search.bind(query)
		_current_error = res.error
		browse.show_error(res.error, true)
		return
	for row in res.data["rows"]:
		_adopt(row["items"], source)
	_showing_results = true
	_catalog_raw = res.data
	if res.data["rows"][0]["items"].is_empty():
		browse.show_catalog({"rows": []})
		browse.show_error("Nothing found for “%s”." % query)
		return
	_present()


## Pages more titles into a row scrolled near its end.
func load_more(row_index: int) -> void:
	var source := _current_source
	if source.get("kind") != "local" or _showing_results or _more_pending.has(row_index):
		return
	_more_pending[row_index] = true
	var res := await local.request(HTTPClient.METHOD_GET, "/api/more/%s?row=%d" % [source["id"], row_index])
	_more_pending.erase(row_index)
	if _current_source != source or _showing_results or not res.ok:
		return
	var items: Array = res.data["items"]
	_adopt(items, source)
	if row_index < _catalog_raw.get("rows", []).size():
		_catalog_raw["rows"][row_index]["items"].append_array(items)
	browse.append_items(row_index, items)


func play_item(item: Dictionary) -> void:
	var source := ExtensionRegistry.by_id(extensions, item.get("source", ""))
	if source.is_empty():
		return
	var backend := _backend(source)
	_stream_dismissed = false
	# Starting a title here takes over from whatever played before.
	if backend != _playback and _playback.state.get("status") in ACTIVE + ["loading"]:
		_playback.control("stop")
	stream.stop()
	_playback = backend
	# "Simulated" only applies to the offline demo's fake PC.
	player.offline = offline and backend == agent
	player.set_video(local.video_texture() if backend == local else null)
	player.begin(item.get("title", ""), item.get("image", ""))
	_show(player)
	var res := await backend.request(HTTPClient.METHOD_POST, "/api/play", {
		"service": source["id"], "watchUrl": item["watchUrl"], "title": item.get("title", ""),
		"image": item.get("image", ""),
	})
	if not res.ok:
		player.show_error(res.error)


func _backend(source: Dictionary) -> AgentClient:
	return local if source.get("kind") == "local" else agent


func _control(action: String, value: Variant) -> void:
	if _control_pending:
		# One command at a time: keep the latest and send it next (e.g.
		# "play" from Show stream while closing the stream's "pause" is
		# still on its way), rather than dropping it.
		_queued_control = [action, value]
		return
	_control_pending = true
	player.set_pending(true)
	var res := await _playback.control(action, value)
	_control_pending = false
	player.set_pending(false)
	if not res.ok:
		player.show_error(res.error)
	_refresh_player()  # undo optimistic UI if the backend disagreed
	if not _queued_control.is_empty():
		var next: Array = _queued_control
		_queued_control = []
		_control(next[0], next[1])


func _stop() -> void:
	stream.stop()
	if _playback.state.get("status", "idle") in ["idle", "error"]:
		_show(browse)  # nothing to stop
		return
	player.show_activity("Stopping…")
	var res := await _playback.control("stop")
	if not res.ok:
		player.show_error(res.error)


func _show_stream() -> void:
	_stream_dismissed = false
	_open_stream_if_wanted()
	if _playback.state.get("status") == "paused":
		_control("play", null)


func _on_stream_closed() -> void:
	# Closing the stream window means "I'm stepping out", not "stop the movie":
	# pause on the host and show our own controls.
	_stream_dismissed = true
	if agent.state.get("status") in ["playing", "buffering"]:
		_control("pause", null)
	_refresh_player()


func _on_state_changed(state: Dictionary, backend: AgentClient) -> void:
	if backend != _playback:
		# PC playback started from another remote while nothing plays here:
		# follow it. Anything else from an inactive backend is ignored.
		var local_idle: bool = local.state.get("status") in ["idle", "error"]
		if not (backend == agent and state.get("status") == "loading" and local_idle):
			return
		_playback = agent
		player.offline = offline
		player.set_video(null)
	match state.get("status", "idle"):
		"idle":
			stream.stop()
			player.set_video(null)
			if current_view == "player":
				_show(browse)
			return
		"loading":
			if current_view != "player":
				_stream_dismissed = false  # started from another remote
		"playing", "buffering", "paused":
			_open_stream_if_wanted()
		"ended", "error":
			stream.stop()
	if current_view != "player" and current_view != "extensions":
		_show(player)
	_refresh_player()


func _open_stream_if_wanted() -> void:
	if offline or _playback != agent or _stream_dismissed or stream.is_running():
		return
	if agent.state.get("status") not in ACTIVE:
		return
	var error := stream.start(settings)
	if error != "":
		_stream_dismissed = true
		player.show_error(error)


func _refresh_player() -> void:
	var state := _playback.state
	var streamed := _playback == agent
	player.update_state(state, _artwork.get(state.get("watchUrl", ""), ""),
		stream.is_running() if streamed else true, streamed and stream.is_opening())


func _on_connection_changed(connected: bool) -> void:
	if offline:
		return
	# The PC came or went: re-check which of its extensions are available.
	if connected != (_host == ExtensionRegistry.Host.ONLINE):
		_connect_to_host()


func _on_info_action(action: String) -> void:
	match action:
		"pc":
			open_extensions(ExtensionsView.PC)
		"configure":
			open_extensions(info_view.source_id)
		"demo":
			_switch_mode(true)
		"retry":
			await _connect_to_host()
			_refresh_info()


## Re-shows the open info page with the extension's current state, or
## launches the extension if it has become available.
func _refresh_info() -> void:
	var source := ExtensionRegistry.by_id(extensions, info_view.source_id)
	if source.is_empty():
		return
	if source["available"] and source["enabled"] and info_view.error == "":
		open_source(source)
	else:
		info_view.show_source(source, info_view.error)


## Offline demo <-> real host. Rebuilds the scene so every node starts clean.
func _switch_mode(to_offline: bool) -> void:
	offline_override = to_offline
	get_tree().reload_current_scene.call_deferred()


## Shows one view. The incoming view is already prepared by the caller; it
## fades in while the outgoing one fades out.
func _show(view: Control) -> void:
	var view_name: String = {browse: "browse", player: "player", extensions_view: "extensions", info_view: "info"}[view]
	var changed := view_name != current_view
	for other: Control in [browse, player, extensions_view, info_view]:
		if other == view:
			if changed or not other.visible:
				_fade_view(other, true)
		elif other.visible:
			_fade_view(other, false)
	view.call_deferred("focus_content")
	if changed:
		current_view = view_name
		view_changed.emit(view_name)


func _fade_view(view: Control, show: bool) -> void:
	if _view_fades.has(view):
		_view_fades[view].kill()
	var tween := create_tween()
	_view_fades[view] = tween
	if show:
		view.visible = true
		view.modulate.a = 0.0 if view.modulate.a >= 1.0 else view.modulate.a
		tween.tween_property(view, "modulate:a", 1.0, VIEW_FADE_IN).set_delay(VIEW_FADE_OUT * 0.5)
	else:
		tween.tween_property(view, "modulate:a", 0.0, VIEW_FADE_OUT)
		tween.tween_callback(view.hide)
