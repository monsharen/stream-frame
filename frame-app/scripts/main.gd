extends Control
## App controller. The host agent's playback state drives which view is shown
## and whether the stream window is open, so playback started from another
## remote (e.g. the phone web UI) is picked up here too.

## Offline demo: a built-in fake agent, no host PC or Moonlight needed.
## Set from the settings screen (demo button, or saving real settings) and
## kept across the scene reload that switches modes; null = use the
## --offline flag / STREAM_FRAME_OFFLINE env.
static var offline_override: Variant = null

var offline: bool = offline_override if offline_override != null \
		else ("--offline" in OS.get_cmdline_user_args() or OS.get_environment("STREAM_FRAME_OFFLINE") == "1")
var settings := Settings.load_or_default()
var agent: AgentClient = OfflineAgent.new() if offline else AgentClient.new()
var images := ImageCache.new()
var stream := StreamLauncher.new()

var browse: BrowseView
var player: PlayerView
var settings_view: SettingsView

var _current_service := ""
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
	add_child(agent)
	add_child(images)
	add_child(stream)

	browse = BrowseView.new(images)
	player = PlayerView.new(images)
	player.offline = offline
	settings_view = SettingsView.new(settings)
	for view: Control in [browse, player, settings_view]:
		view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		view.visible = false
		add_child(view)

	browse.service_selected.connect(_select_service)
	browse.refresh_requested.connect(func() -> void: _select_service(_current_service, true))
	browse.settings_requested.connect(_open_settings)
	browse.item_chosen.connect(_play)
	player.control_requested.connect(_control)
	player.show_stream_requested.connect(_show_stream)
	player.back_requested.connect(_stop)
	settings_view.saved.connect(func() -> void:
		if offline:
			_switch_mode(false)
		else:
			_connect_to_host())
	settings_view.offline_requested.connect(_switch_mode.bind(true))
	agent.state_changed.connect(_on_state_changed)
	agent.connection_changed.connect(browse.set_connected)
	stream.closed.connect(_on_stream_closed)
	stream.failed.connect(func(message: String) -> void:
		_stream_dismissed = true
		player.show_error(message))

	if offline or settings.is_configured():
		_connect_to_host()
	else:
		_open_settings()


func _connect_to_host() -> void:
	agent.configure(settings.agent_url, settings.token)
	_show(browse)
	browse.show_message("Offline demo: simulated playback, no host PC." if offline else "Connecting to %s…" % settings.agent_url)
	var res := await agent.request(HTTPClient.METHOD_GET, "/api/services")
	if not res.ok:
		browse.show_message(res.error, true)
		return
	var services: Array = res.data
	browse.set_services(services)
	if services.is_empty():
		browse.show_message("The host agent has no services configured.", true)
		return
	var ids := services.map(func(s: Dictionary) -> String: return s["id"])
	_select_service(settings.last_service if settings.last_service in ids else ids[0])


func _select_service(service_id: String, refresh := false) -> void:
	if service_id == "":
		return
	_current_service = service_id
	settings.last_service = service_id
	settings.save()
	browse.set_active_service(service_id)
	browse.show_message("Refreshing…" if refresh else "Loading…")
	var res := await agent.request(HTTPClient.METHOD_GET, "/api/catalog/%s%s" % [service_id, "?refresh" if refresh else ""])
	if _current_service != service_id:
		return  # the user switched tabs while this was loading
	if not res.ok:
		browse.show_message(res.error, true)
		return
	for row in res.data.get("rows", []):
		for item in row["items"]:
			# Remember where each title came from: the user may switch tabs
			# while these cards are still on screen.
			item["service"] = service_id
			_artwork[item["watchUrl"]] = item.get("image", "")
	browse.show_catalog(res.data)


func _play(item: Dictionary) -> void:
	_stream_dismissed = false
	player.begin(item.get("title", ""), item.get("image", ""))
	_show(player)
	var res := await agent.request(HTTPClient.METHOD_POST, "/api/play", {
		"service": item.get("service", _current_service), "watchUrl": item["watchUrl"], "title": item.get("title", ""),
	})
	if not res.ok:
		player.show_error(res.error)


func _control(action: String, value: Variant) -> void:
	var res := await agent.control(action, value)
	if not res.ok:
		player.show_error(res.error)


func _stop() -> void:
	stream.stop()
	if agent.state.get("status", "idle") in ["idle", "error"]:
		_show(browse)  # nothing to stop on the host
		return
	var res := await agent.control("stop")
	if not res.ok:
		player.show_error(res.error)


func _show_stream() -> void:
	_stream_dismissed = false
	_open_stream_if_wanted()
	if agent.state.get("status") == "paused":
		_control("play", null)


func _on_stream_closed() -> void:
	# Closing the stream window means "I'm stepping out", not "stop the movie":
	# pause on the host and show our own controls.
	_stream_dismissed = true
	if agent.state.get("status") == "playing":
		_control("pause", null)
	_refresh_player()


func _on_state_changed(state: Dictionary) -> void:
	match state.get("status", "idle"):
		"idle":
			stream.stop()
			if player.visible:
				_show(browse)
			return
		"loading":
			if not player.visible:
				_stream_dismissed = false  # started from another remote
		"playing", "paused":
			_open_stream_if_wanted()
		"ended", "error":
			stream.stop()
	if not player.visible and not settings_view.visible:
		_show(player)
	_refresh_player()


func _open_stream_if_wanted() -> void:
	if offline or _stream_dismissed or stream.is_running():
		return
	if agent.state.get("status") not in ["playing", "paused"]:
		return
	var error := stream.start(settings)
	if error != "":
		_stream_dismissed = true
		player.show_error(error)


func _refresh_player() -> void:
	var state := agent.state
	player.update_state(state, _artwork.get(state.get("watchUrl", ""), ""), stream.is_running())


## Offline demo <-> real host. Rebuilds the scene so every node starts clean.
func _switch_mode(to_offline: bool) -> void:
	offline_override = to_offline
	get_tree().reload_current_scene.call_deferred()


func _open_settings() -> void:
	_show(settings_view)
	settings_view.open()


func _show(view: Control) -> void:
	for other: Control in [browse, player, settings_view]:
		other.visible = other == view
	view.call_deferred("focus_content")
