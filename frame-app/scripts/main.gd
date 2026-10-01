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

var _host := ExtensionRegistry.Host.CONNECTING
var _agent_services: Array = []
## The extension whose catalog is shown; {} on the home.
var _current_source: Dictionary = {}
## The last error while using the current extension, for "What's wrong?".
var _current_error := ""
## The backend the player view follows.
var _playback: AgentClient
## What Retry on the browse screen re-runs (the last thing that failed).
var _retry: Callable = func() -> void: pass
var _control_pending := false
var _checking_host := false
## watchUrl -> image, so the player backdrop works for any known title.
var _artwork: Dictionary[String, String] = {}
## Set when the user closes the stream window, so we don't reopen it on the
## next state update. Cleared when they ask for it again or start a new title.
var _stream_dismissed := false


func _ready() -> void:
	theme = UiTheme.build()
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_apply_extension_config()
	for node: Node in [agent, local, images, stream]:
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
	browse.home_requested.connect(show_home)
	browse.refresh_requested.connect(func() -> void:
		if not browse.is_loading() and not _current_source.is_empty():
			_load_catalog(true))
	browse.retry_requested.connect(func() -> void: _retry.call())
	browse.help_requested.connect(func() -> void: _show_info(_current_source["id"], _current_error))
	browse.extensions_requested.connect(open_extensions)
	browse.item_chosen.connect(play_item)
	info_view.back_requested.connect(show_home)
	info_view.action_requested.connect(_on_info_action)
	extensions_view.back_requested.connect(show_home)
	extensions_view.extension_toggled.connect(func(_id: String, _on: bool) -> void: _rebuild())
	extensions_view.extension_configured.connect(func(_id: String) -> void:
		_apply_extension_config()
		_rebuild())
	extensions_view.pc_saved.connect(func() -> void:
		if offline:
			_switch_mode(false)
		else:
			_connect_to_host())
	extensions_view.demo_requested.connect(_switch_mode)
	player.control_requested.connect(_control)
	player.show_stream_requested.connect(_show_stream)
	player.back_requested.connect(_stop)
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
	match host:
		ExtensionRegistry.Host.DEMO:
			browse.set_note("Offline demo")
		ExtensionRegistry.Host.CONNECTING:
			browse.set_note("Connecting to your PC…")
		ExtensionRegistry.Host.OFFLINE:
			browse.set_note("PC offline", true)
		_:
			browse.set_note("")
	_rebuild()


## Recomputes every extension's status and refreshes whatever shows them.
func _rebuild() -> void:
	extensions = ExtensionRegistry.build(settings, _host, _agent_services)
	sources = ExtensionRegistry.enabled(extensions) + [EXTENSIONS_APP]
	if _current_source.is_empty() and browse.visible:
		browse.show_sources(sources)
	if info_view.visible:
		_refresh_info()
	if extensions_view.visible:
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
	local.command = ExtensionRegistry.config_value(settings, "open-movies", "player_command")


func show_home() -> void:
	_current_source = {}
	browse.show_sources(sources)
	_show(browse)


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
	browse.enter_source(source["name"])
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
		for item in row["items"]:
			# Remember where each title came from: the user may move on
			# while these cards are still on screen.
			item["source"] = source["id"]
			_artwork[item["watchUrl"]] = item.get("image", "")
	browse.show_catalog(res.data)


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
	player.begin(item.get("title", ""), item.get("image", ""))
	_show(player)
	var res := await backend.request(HTTPClient.METHOD_POST, "/api/play", {
		"service": source["id"], "watchUrl": item["watchUrl"], "title": item.get("title", ""),
	})
	if not res.ok:
		player.show_error(res.error)


func _backend(source: Dictionary) -> AgentClient:
	return local if source.get("kind") == "local" else agent


func _control(action: String, value: Variant) -> void:
	if _control_pending:
		return  # one command at a time; the UI is disabled meanwhile anyway
	_control_pending = true
	player.set_pending(true)
	var res := await _playback.control(action, value)
	_control_pending = false
	player.set_pending(false)
	if not res.ok:
		player.show_error(res.error)
	_refresh_player()  # undo optimistic UI if the backend disagreed


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
	match state.get("status", "idle"):
		"idle":
			stream.stop()
			if player.visible:
				_show(browse)
			return
		"loading":
			if not player.visible:
				_stream_dismissed = false  # started from another remote
		"playing", "buffering", "paused":
			_open_stream_if_wanted()
		"ended", "error":
			stream.stop()
	if not player.visible and not extensions_view.visible:
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


func _show(view: Control) -> void:
	for other: Control in [browse, player, extensions_view, info_view]:
		other.visible = other == view
	view.call_deferred("focus_content")
	var view_name: String = {browse: "browse", player: "player", extensions_view: "extensions", info_view: "info"}[view]
	if view_name != current_view:
		current_view = view_name
		view_changed.emit(view_name)
