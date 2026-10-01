class_name PlayerView
extends Control
## Shown behind the stream: artwork while loading, and the app's own
## playback controls (the service's UI is hidden on the host). While the
## stream window is closed this is what the user sees and controls.

signal control_requested(action: String, value: Variant)
signal show_stream_requested
signal back_requested

const SEEK_DEBOUNCE_SECONDS := 0.35

## Offline demo: there is never a stream, so don't offer one.
var offline := false

var _images: ImageCache
var _backdrop := TextureRect.new()
var _title := UiTheme.label("", 44)
var _status := UiTheme.label("", 26, UiTheme.MUTED)
var _scrubber := HSlider.new()
var _time := UiTheme.label("0:00 / 0:00", 22, UiTheme.MUTED)
var _toggle := UiTheme.button("Pause", control_requested.emit.bind("toggle", null))
var _show_stream := UiTheme.button("Show stream", show_stream_requested.emit)
var _stop := UiTheme.button("Stop", back_requested.emit)
var _controls := HBoxContainer.new()
var _seek_timer := Timer.new()
var _scrubbing := false
var _syncing := false
var _duration := 0.0
var _backdrop_url := ""


func _init(images: ImageCache) -> void:
	_images = images

	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.modulate = Color(1, 1, 1, 0.25)
	add_child(_backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	margin.add_child(layout)

	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_title)
	layout.add_child(_status)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(spacer)

	var panel := PanelContainer.new()
	layout.add_child(panel)
	var panel_layout := VBoxContainer.new()
	panel_layout.add_theme_constant_override("separation", 12)
	panel.add_child(panel_layout)

	_scrubber.step = 1.0
	_scrubber.focus_mode = Control.FOCUS_ALL
	_scrubber.custom_minimum_size.y = 32
	_scrubber.drag_started.connect(func() -> void: _scrubbing = true)
	_scrubber.drag_ended.connect(func(_changed: bool) -> void:
		_scrubbing = false
		_request_seek())
	# Controller/keyboard nudges arrive as value changes without a drag;
	# debounce them so holding a direction produces one seek.
	_scrubber.value_changed.connect(func(value: float) -> void:
		_time.text = "%s / %s" % [_format(value), _format(_duration)]
		if not _syncing and not _scrubbing:
			_seek_timer.start())
	_seek_timer.one_shot = true
	_seek_timer.wait_time = SEEK_DEBOUNCE_SECONDS
	_seek_timer.timeout.connect(_request_seek)
	add_child(_seek_timer)
	panel_layout.add_child(_scrubber)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	panel_layout.add_child(bottom)
	_time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_time)
	_controls.add_theme_constant_override("separation", 12)
	_controls.add_child(UiTheme.button("−10s", control_requested.emit.bind("seekBy", -10)))
	_controls.add_child(_toggle)
	_controls.add_child(UiTheme.button("+10s", control_requested.emit.bind("seekBy", 10)))
	_controls.add_child(_show_stream)
	bottom.add_child(_controls)
	bottom.add_child(_stop)


## Called when a title is picked, before the host has reported anything.
func begin(title: String, image_url: String) -> void:
	_title.text = title
	_status.text = "Starting…"
	_status.add_theme_color_override("font_color", UiTheme.MUTED)
	_set_backdrop(image_url)
	_controls.visible = false
	_duration = 0.0
	_sync_scrubber(0.0, 0.0)


func update_state(state: Dictionary, image_url: String, stream_running: bool) -> void:
	var status: String = state.get("status", "idle")
	if state.get("title"):
		_title.text = state["title"]
	_set_backdrop(image_url)
	var controls_were_visible := _controls.visible
	_controls.visible = status in ["playing", "paused"]
	# Loading only offers Stop; once playback starts, move focus to Pause
	# so the obvious button press does the obvious thing.
	if _controls.visible and not controls_were_visible and _stop.has_focus():
		_toggle.grab_focus()
	_show_stream.visible = not stream_running and not offline
	_toggle.text = "Play" if status == "paused" else "Pause"
	match status:
		"loading":
			_status.text = "Starting…"
		"playing":
			if offline:
				_status.text = "Playing (simulated, offline demo)"
			else:
				_status.text = "" if stream_running else "Playing on the host. The stream window is closed."
		"paused":
			_status.text = "Paused"
		"ended":
			_status.text = "Finished"
		"error":
			_status.text = state.get("error", "Playback failed")
	_status.add_theme_color_override("font_color", UiTheme.ERROR if status == "error" else UiTheme.MUTED)
	_duration = state.get("duration", 0.0)
	if not _scrubbing and _seek_timer.is_stopped():
		_sync_scrubber(state.get("position", 0.0), _duration)


func show_error(message: String) -> void:
	_status.text = message
	_status.add_theme_color_override("font_color", UiTheme.ERROR)


func focus_content() -> void:
	if _controls.visible:
		_toggle.grab_focus()
	else:
		_stop.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_SPACE and _controls.visible:
		control_requested.emit("toggle", null)
		accept_event()


func _request_seek() -> void:
	_seek_timer.stop()
	control_requested.emit("seekTo", _scrubber.value)


func _sync_scrubber(position: float, duration: float) -> void:
	_syncing = true
	_scrubber.max_value = maxf(duration, 1.0)
	_scrubber.value = position
	_syncing = false
	_time.text = "%s / %s" % [_format(position), _format(duration)]


func _set_backdrop(url: String) -> void:
	if url == _backdrop_url:
		return
	_backdrop_url = url
	_backdrop.texture = null
	_images.load_into(url, _backdrop)


static func _format(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]
