class_name PlayerView
extends Control
## Shown behind the stream: artwork while loading, and the app's own
## playback controls (the service's UI is hidden on the host). While the
## stream window is closed this is what the user sees and controls.
##
## Loading states: a centred spinner while the title starts, buffers or the
## stream window opens; a hint if starting takes unusually long; controls
## disabled while a command is in flight, with seeks shown immediately.

signal control_requested(action: String, value: Variant)
signal show_stream_requested
signal back_requested
## 3D shell only: the viewer asked for the next screen size / to lean back.
signal screen_size_requested
signal lean_back_requested
## 0 = 2D, 1 = side by side, 2 = top-bottom.
signal stereo_changed(mode: int)

const STEREO_LABELS := ["3D: off", "3D: side by side", "3D: top-bottom"]

const SEEK_DEBOUNCE_SECONDS := 0.35
## After a local seek, ignore reported positions this long so a poll that
## predates the seek doesn't snap the scrubber back.
const SEEK_HOLD_SECONDS := 1.5
const SLOW_START_SECONDS := 12.0
## With video showing, controls fade after this long without input.
const CONTROLS_IDLE_SECONDS := 3.5
## Pointer movement smaller than this (UI pixels per event) is jitter.
const ACTIVITY_PIXELS := 6.0

## Offline demo: there is never a stream, so don't offer one.
var offline := false
## Set by the 3D shell: the screen itself draws the video (needed for 3D
## films); this view then turns transparent where the film shows.
var video_on_screen := false
## 0..1: how far the film has replaced the curtain (and this view's
## background). The shell reads it to fade the video in on the screen.
var video_reveal := 0.0
var stereo := 0

var _images: ImageCache
var _backdrop := TextureRect.new()
## The in-app video (on-device titles), behind the controls.
var _video := TextureRect.new()
## Everything drawn over the video; fades while watching.
var _chrome := MarginContainer.new()
var _chrome_fade: Tween
var _last_activity := 0.0
## Whether the curtain (the title's artwork while starting) has lifted.
var _revealed := false
var _curtain: Tween
var _source_video: Texture2D
var _title := UiTheme.label("", 44)
var _status := UiTheme.label("", 26, UiTheme.MUTED)
var _scrubber := HSlider.new()
var _time := UiTheme.label("0:00", 22, UiTheme.MUTED)
var _remaining := UiTheme.label("", 22, UiTheme.MUTED)
var _toggle := GlyphButton.new("pause", "Pause", _on_toggle, 104)
## Shown as playing (the toggle offers Pause) or paused (it offers Play).
var _playing := true
var _stereo_button := UiTheme.button(STEREO_LABELS[0], _cycle_stereo)
var _size_button := UiTheme.button("Size: cinema", func() -> void: screen_size_requested.emit())
var _lean_button := UiTheme.button("Lean back", func() -> void: lean_back_requested.emit())
var _bg := ColorRect.new()
var _shade: TextureRect
## The title and controls (_chrome holds them; see place_controls_below).
var _layout := VBoxContainer.new()
var _spacer := Control.new()
var _show_stream := UiTheme.button("Show stream", show_stream_requested.emit)
var _stop := GlyphButton.new("close", "Stop", back_requested.emit)
## Transport: back 10 s, play/pause, forward 10 s.
var _controls := HBoxContainer.new()
## Viewing options (3D, size, lean back, glow), behind the ⋯ button.
var _options := HBoxContainer.new()
var _more := GlyphButton.new("more", "Viewing options", func() -> void: _options.visible = not _options.visible)
var _seek_timer := Timer.new()
var _scrubbing := false
var _syncing := false
var _duration := 0.0
var _backdrop_url := ""
var _overlay := CenterContainer.new()
var _overlay_label := UiTheme.label("", 30)
var _overlay_hint := UiTheme.label("", 22, UiTheme.MUTED)
var _pending_spinner := Spinner.new(24)
var _loading_since := -1.0
var _hold_position_until := 0.0


func _init(images: ImageCache) -> void:
	_images = images

	var bg := _bg
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.modulate = Color(1, 1, 1, 0.25)
	add_child(_backdrop)
	_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_video.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_video.visible = false
	add_child(_video)

	var margin := _chrome
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	add_child(margin)
	var layout := _layout
	layout.add_theme_constant_override("separation", 16)
	margin.add_child(layout)

	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_title)
	layout.add_child(_status)
	var spacer := _spacer
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(spacer)

	# Low on the screen, so the artwork shown while starting stays in view.
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.anchor_top = 0.55
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	var overlay_layout := VBoxContainer.new()
	overlay_layout.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay_layout.add_theme_constant_override("separation", 14)
	var big_spinner := Spinner.new(56)
	big_spinner.thickness = 5.0
	big_spinner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	overlay_layout.add_child(big_spinner)
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_layout.add_child(_overlay_label)
	overlay_layout.add_child(_overlay_hint)
	_overlay.add_child(overlay_layout)
	add_child(_overlay)

	# No panel: the controls float over a soft shade at the bottom, as on
	# Apple TV, and fade with the rest of the chrome.
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0))
	gradient.set_color(1, Color(0, 0, 0, 0.6))
	var shade_texture := GradientTexture2D.new()
	shade_texture.gradient = gradient
	shade_texture.fill_from = Vector2(0, 0)
	shade_texture.fill_to = Vector2(0, 1)
	shade.texture = shade_texture
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.anchor_top = 0.55
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	move_child(shade, _chrome.get_index())
	_shade = shade

	_options.add_theme_constant_override("separation", 10)
	_options.alignment = BoxContainer.ALIGNMENT_END
	_options.visible = false
	_options.add_child(_stereo_button)
	_options.add_child(_size_button)
	_options.add_child(_lean_button)
	_size_button.visible = false
	_lean_button.visible = false
	layout.add_child(_options)

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
		_show_times(value, _duration)
		if not _syncing and not _scrubbing:
			_seek_timer.start())
	_seek_timer.one_shot = true
	_seek_timer.wait_time = SEEK_DEBOUNCE_SECONDS
	_seek_timer.timeout.connect(_request_seek)
	add_child(_seek_timer)
	layout.add_child(_scrubber)

	# Elapsed and remaining time under the ends of the scrubber.
	var times := HBoxContainer.new()
	_time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	times.add_child(_time)
	_remaining.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	times.add_child(_remaining)
	layout.add_child(times)

	# Transport in the middle; the stream, options and close at the right.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	layout.add_child(bottom)
	var left := HBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	_pending_spinner.visible = false
	_pending_spinner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_child(_pending_spinner)
	bottom.add_child(left)
	_controls.add_theme_constant_override("separation", 20)
	_controls.alignment = BoxContainer.ALIGNMENT_CENTER
	_controls.add_child(GlyphButton.new("back10", "Back 10 seconds", _seek_by.bind(-10.0), 80))
	_controls.add_child(_toggle)
	_controls.add_child(GlyphButton.new("forward10", "Forward 10 seconds", _seek_by.bind(10.0), 80))
	for button in _controls.get_children():
		(button as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_controls)
	var right := HBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 12)
	_show_stream.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(_show_stream)
	_more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(_more)
	_stop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(_stop)
	bottom.add_child(right)
	for button: GlyphButton in [_toggle, _more, _stop] + _controls.get_children().filter(func(b: Node) -> bool: return b is GlyphButton):
		button.dark = true
	for label: Label in [_title, _time, _remaining]:
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		label.add_theme_constant_override("shadow_offset_y", 2)


## 3D shell: the title and controls go on a glass panel in the strip of
## the UI below the screen's area (`top`, `height` in pixels), which the
## shell shows as its own panel under the screen: the film is never
## covered. They fade, and answer to the pointer, as before.
func place_controls_below(top: float, height: float) -> void:
	_chrome.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_chrome.position = Vector2(0, top)
	_chrome.size = Vector2(size.x if size.x > 0.0 else 1920.0, height)
	for side in ["left", "right", "top", "bottom"]:
		_chrome.add_theme_constant_override("margin_" + side, 24)
	_spacer.visible = false
	var glass := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiTheme.PANEL, 0.88)
	style.set_corner_radius_all(28)
	style.set_content_margin_all(28)
	style.content_margin_left = 44
	style.content_margin_right = 44
	glass.add_theme_stylebox_override("panel", style)
	_chrome.remove_child(_layout)
	glass.add_child(_layout)
	_chrome.add_child(glass)
	_title.add_theme_font_size_override("font_size", 40)
	for label: Label in [_time, _remaining]:
		label.add_theme_font_size_override("font_size", 28)
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for label: Label in [_title, _time, _remaining]:
		label.remove_theme_color_override("font_shadow_color")


## A viewing option from the 3D shell (e.g. glow), next to the others.
func add_option(button: Button) -> void:
	_options.add_child(button)


## Shows in-app video behind the controls (null: artwork backdrop instead).
## The video stays hidden behind the curtain until it is playing.
func set_video(texture: Texture2D) -> void:
	_source_video = texture
	stereo = 0
	_stereo_button.text = STEREO_LABELS[0]
	_apply_video_texture()
	_video.modulate.a = 1.0 if _revealed else 0.0
	video_reveal = 1.0 if _revealed and texture else 0.0
	_bg.modulate.a = 1.0 - video_reveal if video_on_screen else 1.0
	_stereo_button.visible = texture != null
	_show_chrome()


func is_showing_video() -> bool:
	return _source_video != null


## Shows the 3D shell's screen controls (size, lean back).
func set_screen_controls(on: bool, size_label := "") -> void:
	_size_button.visible = on
	_lean_button.visible = on
	if size_label != "":
		_size_button.text = "Size: " + size_label


func set_lean_back(on: bool) -> void:
	_lean_button.text = "Sit up" if on else "Lean back"


func _cycle_stereo() -> void:
	stereo = (stereo + 1) % STEREO_LABELS.size()
	_stereo_button.text = STEREO_LABELS[stereo]
	_apply_video_texture()
	stereo_changed.emit(stereo)


## The flat view draws the video itself: one eye's half for 3D films.
func _apply_video_texture() -> void:
	_video.visible = _source_video != null and not video_on_screen
	if _source_video == null or stereo == 0:
		_video.texture = _source_video
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = _source_video
	var size := _source_video.get_size()
	atlas.region = Rect2(Vector2.ZERO, Vector2(size.x / 2, size.y) if stereo == 1 else Vector2(size.x, size.y / 2))
	_video.texture = atlas


## Called when a title is picked, before the host has reported anything.
func begin(title: String, image_url: String) -> void:
	_title.text = title
	_status.text = ""
	_options.visible = false
	_set_backdrop(image_url)
	# The curtain: the title's artwork at full brightness while it starts
	# (playback is already buffering behind it), lifted once it plays.
	_revealed = false
	if _curtain:
		_curtain.kill()
	_backdrop.modulate.a = 1.0
	_video.modulate.a = 0.0
	video_reveal = 0.0
	_bg.modulate.a = 1.0
	_controls.visible = false
	_duration = 0.0
	_hold_position_until = 0.0
	_sync_scrubber(0.0, 0.0)
	_set_loading("Starting %s…" % title if title != "" else "Starting…")


## stream_opening: the stream window has been launched but is probably not
## on screen yet.
func update_state(state: Dictionary, image_url: String, stream_running: bool, stream_opening := false) -> void:
	var status: String = state.get("status", "idle")
	if state.get("title"):
		_title.text = state["title"]
	_set_backdrop(image_url)
	if not _revealed and status in ["playing", "paused", "ended"]:
		_lift_curtain()
	# On-device titles currently play in an external player window that the
	# app can't pause or seek, so its own controls are in charge.
	var external: bool = state.get("external", false)
	var controls_were_visible := _controls.visible
	_controls.visible = status in ["playing", "buffering", "paused"] and not external
	_scrubber.visible = not external
	_time.visible = not external
	_remaining.visible = not external
	_more.visible = _controls.visible
	# Loading only offers Stop; once playback starts, move focus to Pause
	# so the obvious button press does the obvious thing.
	if _controls.visible and not controls_were_visible and _stop.has_focus():
		_toggle.grab_focus()
	_show_stream.visible = not stream_running and not offline
	_set_playing(status != "paused")
	match status:
		"loading":
			if _loading_since < 0.0:
				_set_loading("Starting %s…" % _title.text)
		"buffering":
			_set_loading("Buffering…")
		"playing":
			if external:
				_status.text = "Playing in the player window. Use its controls; close it to come back here."
			elif offline:
				_status.text = "Playing (simulated, offline demo)"
			else:
				_status.text = "" if stream_running else "Playing on the host. The stream window is closed."
		"paused":
			_status.text = "Paused"
		"ended":
			_status.text = "Finished"
		"error":
			_status.text = state.get("error", "Playback failed")
	if status == "loading" or status == "buffering":
		_status.text = ""
	elif stream_opening and status in ["playing", "paused"]:
		_set_loading("Opening stream…")
	else:
		_set_loading("")
	_status.add_theme_color_override("font_color", UiTheme.ERROR if status == "error" else UiTheme.MUTED)
	_duration = state.get("duration", 0.0)
	var holding := Time.get_ticks_msec() / 1000.0 < _hold_position_until
	if not _scrubbing and _seek_timer.is_stopped() and not holding:
		_sync_scrubber(state.get("position", 0.0), _duration)


func show_error(message: String) -> void:
	_set_loading("")
	_status.text = message
	_status.add_theme_color_override("font_color", UiTheme.ERROR)


## Transient activity (e.g. "Stopping…") shown with the spinner.
func show_activity(text: String) -> void:
	_set_loading(text)


## A command is in flight: block repeats until the host has answered.
func set_pending(pending: bool) -> void:
	_pending_spinner.visible = pending
	for button in _controls.get_children():
		(button as Button).disabled = pending


func focus_content() -> void:
	if _controls.visible:
		_toggle.grab_focus()
	else:
		_stop.grab_focus()


## Nothing of this view is showing (watching, controls faded): the 3D
## shell can stop redrawing the UI until something changes.
func is_idle() -> bool:
	return _source_video != null and video_on_screen and _chrome.modulate.a <= 0.001 \
		and not _overlay.visible and video_reveal >= 1.0 and not (_chrome_fade and _chrome_fade.is_running())


## Back (InputActions): close the viewing options if they're open. True
## if that's what Back did here.
func handle_back() -> bool:
	if _options.visible:
		_options.visible = false
		_show_chrome()
		return true
	return false


## Play / pause from an action (InputActions.PLAY_PAUSE).
func toggle() -> void:
	if _controls.visible and not _toggle.disabled:
		_show_chrome()
		_on_toggle()


## Seek from an action (InputActions.SEEK_BACK / SEEK_FORWARD).
func seek_by(seconds: float) -> void:
	if _controls.visible and not _toggle.disabled:
		_show_chrome()
		_seek_by(seconds)


func toggle_options() -> void:
	if _more.visible:
		_options.visible = not _options.visible
		_show_chrome()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	# Hands are never perfectly still, and the desktop gaze eases to a stop:
	# only a deliberate movement brings the controls back.
	if event is InputEventMouseMotion and event.relative.length() < ACTIVITY_PIXELS:
		return
	if event is InputEventMouse or event is InputEventKey or event is InputEventJoypadButton:
		_show_chrome()


func _show_chrome() -> void:
	_last_activity = Time.get_ticks_msec() / 1000.0
	if _chrome.modulate.a < 1.0:
		if _chrome_fade:
			_chrome_fade.kill()
		_chrome_fade = create_tween()
		_chrome_fade.tween_property(_chrome, "modulate:a", 1.0, 0.15)


## While video plays undisturbed, fade the title and controls away.
func _update_chrome() -> void:
	var watching := _source_video != null and _controls.visible and _playing and not _overlay.visible \
		and not _options.visible
	var idle := Time.get_ticks_msec() / 1000.0 - _last_activity > CONTROLS_IDLE_SECONDS
	if watching and idle and _chrome.modulate.a >= 1.0 and not (_chrome_fade and _chrome_fade.is_running()):
		_chrome_fade = create_tween()
		_chrome_fade.tween_property(_chrome, "modulate:a", 0.0, 0.6)
	elif not watching and _chrome.modulate.a < 1.0:
		_show_chrome()


func _process(_delta: float) -> void:
	_update_chrome()
	# On the 3D screen the shade would also darken the room around the
	# picture; there the buttons carry their own dark fill instead.
	_shade.modulate.a = 0.0 if video_on_screen else _chrome.modulate.a
	if _loading_since >= 0.0 and _overlay_hint.text == "" \
			and Time.get_ticks_msec() / 1000.0 - _loading_since > SLOW_START_SECONDS:
		_overlay_hint.text = "Still working on it. Streaming services can take a while to start."


func _set_loading(text: String) -> void:
	if text == "":
		_overlay.visible = false
		_loading_since = -1.0
		return
	if _overlay_label.text != text or not _overlay.visible:
		_overlay_hint.text = ""
		_loading_since = Time.get_ticks_msec() / 1000.0
	_overlay_label.text = text
	_overlay.visible = true


func _on_toggle() -> void:
	# Show the expected result straight away; the next state confirms it.
	_set_playing(not _playing)
	control_requested.emit("toggle", null)


func _set_playing(playing: bool) -> void:
	_playing = playing
	_toggle.glyph = "pause" if playing else "play"
	_toggle.tooltip_text = "Pause" if playing else "Play"


func _seek_by(seconds: float) -> void:
	_show_local_position(clampf(_scrubber.value + seconds, 0.0, _duration))
	control_requested.emit("seekBy", seconds)


func _request_seek() -> void:
	_seek_timer.stop()
	_show_local_position(_scrubber.value)
	control_requested.emit("seekTo", _scrubber.value)


func _show_local_position(position: float) -> void:
	_hold_position_until = Time.get_ticks_msec() / 1000.0 + SEEK_HOLD_SECONDS
	_sync_scrubber(position, _duration)


func _sync_scrubber(position: float, duration: float) -> void:
	_syncing = true
	_scrubber.max_value = maxf(duration, 1.0)
	_scrubber.value = position
	_syncing = false
	_show_times(position, duration)


func _show_times(position: float, duration: float) -> void:
	_time.text = _format(position)
	_remaining.text = "−" + _format(duration - position) if duration > 0.0 else ""


## Cross-fades from the artwork to the video (or, without in-app video, dims
## the artwork into a backdrop for the controls).
func _lift_curtain() -> void:
	_revealed = true
	_show_chrome()  # controls visible for a moment as the film starts
	if _curtain:
		_curtain.kill()
	_curtain = create_tween().set_parallel()
	if _source_video:
		_curtain.tween_property(_video, "modulate:a", 1.0, 0.6)
		_curtain.tween_property(self, "video_reveal", 1.0, 0.6)
		_curtain.tween_property(_backdrop, "modulate:a", 0.0, 0.8)
		if video_on_screen:
			_curtain.tween_property(_bg, "modulate:a", 0.0, 0.6)
	else:
		_curtain.tween_property(_backdrop, "modulate:a", 0.25, 0.6)


## The poster shown behind the controls (before the film appears).
func backdrop_url() -> String:
	return _backdrop_url


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
