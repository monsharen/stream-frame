class_name ExtensionsView
extends CenterContainer
## The Extensions app: enable or disable extensions, configure them, set
## up the PC connection that all PC extensions share, and change what keys
## and buttons do (Controls). A list on the left,
## the selected item's details on the right.

signal back_requested
## The app should re-check and rebuild after any of these.
signal extension_toggled(id: String, on: bool)
signal extension_configured(id: String)
signal pc_saved
signal demo_requested(on: bool)

const PC := "__pc__"
const DEVICE := "__device__"
const CONTROLS := "__controls__"
## How long the Controls page waits for a key or button to bind.
const CAPTURE_SECONDS := 6.0
const PC_FIELDS := [
	["agent_url", "Host agent URL", "http://192.168.1.20:8787"],
	["token", "Agent token", "Printed by the agent when it starts"],
	["sunshine_host", "Sunshine host", "Same PC as the agent"],
	["sunshine_app", "Sunshine app", "Desktop"],
	["moonlight_command", "Moonlight command", "moonlight"],
]

var _settings: Settings
var _extensions: Array = []
var _pc_status := ""
var _offline := false
var _selected := PC

var _list := VBoxContainer.new()
var _selected_row: Button
var _detail := VBoxContainer.new()
## PC connection fields while its page is open (tests reach in here).
var _pc_fields: Dictionary[String, LineEdit] = {}
var _config_fields: Dictionary[String, LineEdit] = {}
var _builtin_switch: Button
## The action waiting for a key or button to bind (Controls), or &"".
var _capturing := &""
var _capture_timer := Timer.new()
var _capture_note := ""


func _init(settings: Settings) -> void:
	_settings = settings
	_capture_timer.one_shot = true
	_capture_timer.timeout.connect(func() -> void: _stop_capture())
	add_child(_capture_timer)
	# Leaving the app mid-capture cancels it.
	visibility_changed.connect(func() -> void:
		if not visible and _capturing != &"":
			_stop_capture())
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1760, 940)
	add_child(panel)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	panel.add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 620
	left.add_theme_constant_override("separation", 14)
	columns.add_child(left)
	# The back control, then the title, as in every view.
	var title_bar := HBoxContainer.new()
	title_bar.add_theme_constant_override("separation", 18)
	var back := UiTheme.back_button(back_requested.emit)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_bar.add_child(back)
	var title := UiTheme.label("Extensions", 44)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title)
	left.add_child(title_bar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	left.add_child(scroll)

	var divider := VSeparator.new()
	columns.add_child(divider)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail.add_theme_constant_override("separation", 18)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail)
	columns.add_child(detail_scroll)


## Shows the app with fresh data; `select` picks the item to open
## ("" keeps the current one, ExtensionsView.PC is the PC connection).
func open(extensions: Array, pc_status: String, offline: bool, select := "") -> void:
	_extensions = extensions
	_pc_status = pc_status
	_offline = offline
	if select != "":
		_selected = select
	_rebuild_list()
	_show_detail()


## New statuses while open (e.g. the PC came online); keeps edits in fields.
func update_status(extensions: Array, pc_status: String) -> void:
	_extensions = extensions
	_pc_status = pc_status
	_rebuild_list()
	if _selected == PC:
		var status: Label = _detail.get_child(1)
		status.text = pc_status
	elif not _selected in [DEVICE, CONTROLS] and _detail.get_child_count() > 1:
		var extension := ExtensionRegistry.by_id(_extensions, _selected)
		var status: Label = _detail.get_child(1)
		status.text = _status_text(extension)
		status.add_theme_color_override("font_color", _status_color(extension))


func focus_content() -> void:
	if is_instance_valid(_selected_row):
		_selected_row.grab_focus()


func _rebuild_list() -> void:
	var had_focus := is_instance_valid(_selected_row) and _selected_row.has_focus()
	_selected_row = null
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var pc_row := _row("PC connection", _pc_status, _selected == PC, UiTheme.MUTED)
	pc_row.pressed.connect(_select.bind(PC))
	_list.add_child(pc_row)
	var player_name := "Built-in" if LocalPlayer.builtin_available() and _settings.extension_value("device", "builtin_player", true) \
		else _settings.player_command.get_slice(" ", 0)
	var device_row := _row("On-device player", player_name, _selected == DEVICE, UiTheme.MUTED)
	device_row.pressed.connect(_select.bind(DEVICE))
	_list.add_child(device_row)
	var controls_row := _row("Controls", "Keys, gamepad and controller buttons", _selected == CONTROLS, UiTheme.MUTED)
	controls_row.pressed.connect(_select.bind(CONTROLS))
	_list.add_child(controls_row)
	for group in [["On this device", "local"], ["From your PC", "remote"]]:
		_list.add_child(UiTheme.label(group[0], 26, UiTheme.MUTED))
		for extension in _extensions.filter(func(e: Dictionary) -> bool: return e["kind"] == group[1]):
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 10)
			var row := _row(extension["name"], _status_text(extension), _selected == extension["id"], _status_color(extension))
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.set_meta("glow_color", extension["color"])
			row.pressed.connect(_select.bind(extension["id"]))
			line.add_child(row)
			line.add_child(_switch(extension))
			_list.add_child(line)
	if had_focus and _selected_row:
		_focus_soon(_selected_row)


func _row(title: String, subtitle: String, selected: bool, subtitle_color: Color) -> Button:
	var button := Button.new()
	button.custom_minimum_size.y = 76
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if selected:
		button.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.BORDER, UiTheme.BORDER, 2))
		button.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.BORDER, UiTheme.MUTED, 2))
		_selected_row = button
	var text := VBoxContainer.new()
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.offset_left = 16
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override("separation", 2)
	var name_label := UiTheme.label(title, 28)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sub := UiTheme.label(subtitle, 20, subtitle_color)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(name_label)
	text.add_child(sub)
	button.add_child(text)
	return button


## The On/Off switch for an extension in the list.
func _switch(extension: Dictionary) -> Button:
	var toggle := _pill(extension["enabled"], "Show %s on the home screen" % extension["name"])
	toggle.toggled.connect(func(on: bool) -> void:
		_settings.set_extension_enabled(extension["id"], on)
		_settings.save()
		extension_toggled.emit(extension["id"], on))
	return toggle


## An On/Off pill: big and unambiguous, also from across a room in VR.
func _pill(on: bool, tooltip: String) -> Button:
	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.button_pressed = on
	toggle.custom_minimum_size = Vector2(110, 76)
	toggle.tooltip_text = tooltip
	toggle.add_theme_font_size_override("font_size", 24)
	# On: a solid white pill; off: a faint one.
	toggle.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.FILL, UiTheme.FILL, 0))
	toggle.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.FILL_HOVER, UiTheme.FILL_HOVER, 0))
	toggle.add_theme_stylebox_override("pressed", UiTheme.box(UiTheme.TEXT, UiTheme.TEXT, 0))
	toggle.add_theme_stylebox_override("hover_pressed", UiTheme.box(Color.WHITE, Color.WHITE, 0))
	toggle.add_theme_color_override("font_color", UiTheme.MUTED)
	toggle.add_theme_color_override("font_hover_color", UiTheme.TEXT)
	toggle.add_theme_color_override("font_hover_pressed_color", UiTheme.BG)
	toggle.text = "On" if on else "Off"
	toggle.toggled.connect(func(pressed: bool) -> void: toggle.text = "On" if pressed else "Off")
	return toggle


func _select(id: String) -> void:
	_selected = id
	_rebuild_list()
	_show_detail()


func _show_detail() -> void:
	# Detach now, free later: the old page's buttons mustn't linger until
	# the end of the frame (focus and lookups would find them).
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	_pc_fields.clear()
	_config_fields.clear()
	if _selected == PC:
		_show_pc()
	elif _selected == DEVICE:
		_show_device()
	elif _selected == CONTROLS:
		_show_controls()
	else:
		_show_extension(ExtensionRegistry.by_id(_extensions, _selected))


func _show_pc() -> void:
	_detail.add_child(UiTheme.label("PC connection", 44))
	_detail.add_child(UiTheme.label(_pc_status, 26, UiTheme.MUTED))
	var about := UiTheme.label("Netflix and other DRM-protected services play in Chrome on your PC; the host agent there controls it, and Sunshine streams the picture to Moonlight on this device. All PC extensions share this connection.", 24, UiTheme.MUTED)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(about)
	var grid := _grid()
	for field in PC_FIELDS:
		_pc_fields[field[0]] = _field(grid, field[1], field[2], str(_settings.get(field[0])), field[0] == "token")
	var buttons := _buttons()
	buttons.add_child(UiTheme.button("Leave offline demo" if _offline else "Try offline demo", demo_requested.emit.bind(not _offline)))
	buttons.add_child(UiTheme.button("Save and connect", _save_pc))


## Every action with what triggers it. A binding's chip removes it; Add
## waits for the next key or button; Reset goes back to the defaults. The
## locked ones (Escape for Back) always stay.
func _show_controls() -> void:
	_detail.add_child(UiTheme.label("Controls", 44))
	_detail.add_child(UiTheme.label(_capture_note if _capture_note != "" else "Select a binding to remove it", 26, UiTheme.MUTED))
	for entry in InputActions.ACTIONS:
		var action: StringName = entry[0]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var name_label := UiTheme.label(entry[1], 26)
		name_label.custom_minimum_size.x = 260
		line.add_child(name_label)
		var chips := HFlowContainer.new()
		chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chips.add_theme_constant_override("h_separation", 8)
		chips.add_theme_constant_override("v_separation", 8)
		for binding: String in InputActions.fixed(action):
			var locked := UiTheme.button(InputActions.describe(binding), func() -> void: pass)
			locked.disabled = true
			locked.tooltip_text = "Always %s" % entry[1]
			chips.add_child(locked)
		for binding: String in InputActions.bindings(_settings, action):
			var chip := UiTheme.button(InputActions.describe(binding) + "  ✕", func() -> void:
				InputActions.unbind(_settings, action, binding)
				_show_detail())
			chip.tooltip_text = "Remove"
			chips.add_child(chip)
		line.add_child(chips)
		var add := UiTheme.button("Press a key or button…" if _capturing == action else "Add", _start_capture.bind(action))
		add.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		line.add_child(add)
		var reset := GlyphButton.new("refresh", "Reset %s to defaults" % entry[1], func() -> void:
			InputActions.reset(_settings, action)
			_show_detail(), 48)
		reset.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		line.add_child(reset)
		_detail.add_child(line)


func _start_capture(action: StringName) -> void:
	_capturing = action
	_capture_note = "Press a key, gamepad or controller button for %s (Escape cancels)" % InputActions.label(action)
	InputActions.xr_capture = _capture
	_capture_timer.start(CAPTURE_SECONDS)
	_show_detail()


func _stop_capture(note := "") -> void:
	_capturing = &""
	_capture_note = note
	InputActions.xr_capture = Callable()
	_capture_timer.stop()
	if _selected == CONTROLS:
		_show_detail()


func _capture(binding: String) -> void:
	var action := _capturing
	if action == &"":
		return
	if InputActions.fixed_owner(binding) == InputActions.BACK and action != InputActions.BACK:
		_stop_capture()  # Escape: cancel
		return
	if not InputActions.bind(_settings, action, binding):
		_stop_capture("%s is reserved" % InputActions.describe(binding))
		return
	_stop_capture("%s → %s" % [InputActions.describe(binding), InputActions.label(action)])


## While waiting for a binding, the next key or button is it (and does
## nothing else).
func _input(event: InputEvent) -> void:
	if _capturing == &"" or not is_visible_in_tree():
		return
	var binding := InputActions.binding_for(event)
	if binding == "":
		return
	get_viewport().set_input_as_handled()
	_capture(binding)


func _show_device() -> void:
	_detail.add_child(UiTheme.label("On-device player", 44))
	_detail.add_child(UiTheme.label("Used by all on-device extensions", 26, UiTheme.MUTED))
	var builtin_available := LocalPlayer.builtin_available()
	var builtin := HBoxContainer.new()
	builtin.add_theme_constant_override("separation", 16)
	var builtin_text := UiTheme.label("Play on the screen in the app (built-in player)" if builtin_available
		else "Built-in player not installed (build it with frame-app/native/build.sh)", 26,
		UiTheme.TEXT if builtin_available else UiTheme.MUTED)
	builtin_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	builtin_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	builtin.add_child(builtin_text)
	_builtin_switch = _pill(builtin_available and _settings.extension_value("device", "builtin_player", true), "Play in the app")
	_builtin_switch.disabled = not builtin_available
	builtin.add_child(_builtin_switch)
	_detail.add_child(builtin)
	# Lighter video: switched on automatically when this device falls behind
	# (decoding in software), and can be switched back here.
	var lighter := HBoxContainer.new()
	lighter.add_theme_constant_override("separation", 16)
	var lighter_text := UiTheme.label("Lighter video: start films in a lower resolution where the source has one. Turns on by itself if this device can't keep up.", 24, UiTheme.MUTED)
	lighter_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lighter_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lighter.add_child(lighter_text)
	var lighter_switch := _pill(_settings.extension_value("device", "lighter_video", false), "Lighter video")
	lighter_switch.toggled.connect(func(on: bool) -> void:
		_settings.set_extension_value("device", "lighter_video", on)
		_settings.save())
	lighter.add_child(lighter_switch)
	_detail.add_child(lighter)
	var about := UiTheme.label("Otherwise titles open in this external player. {title} and {url} are replaced per title; without {url}, \"-- <url>\" is added at the end. With mpv, keep --no-ytdl and the \"--\" before {url}: addresses come from third-party catalogs.", 24, UiTheme.MUTED)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(about)
	var grid := _grid()
	_config_fields["player_command"] = _field(grid, "External player", "mpv … -- {url}", _settings.player_command, false)
	var buttons := _buttons()
	buttons.add_child(UiTheme.button("Reset", func() -> void:
		_config_fields["player_command"].text = LocalPlayer.DEFAULT_COMMAND))
	buttons.add_child(UiTheme.button("Save", _save_device))


func _save_device() -> void:
	var text := _config_fields["player_command"].text.strip_edges()
	_settings.player_command = text if text != "" else LocalPlayer.DEFAULT_COMMAND
	if not _builtin_switch.disabled:
		_settings.set_extension_value("device", "builtin_player", _builtin_switch.button_pressed)
	_settings.save()
	extension_configured.emit(DEVICE)


func _show_extension(extension: Dictionary) -> void:
	if extension.is_empty():
		return
	_detail.add_child(UiTheme.label(extension["name"], 44))
	var status := UiTheme.label(_status_text(extension), 26, _status_color(extension))
	_detail.add_child(status)
	var description := UiTheme.label(extension["description"], 24)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(description)

	if not extension["available"] and extension["enabled"]:
		_detail.add_child(_paragraph(extension["reason"], UiTheme.MUTED))
		var steps: Array = extension["steps"]
		for i in steps.size():
			_detail.add_child(_paragraph("%d.  %s" % [i + 1, steps[i]], UiTheme.MUTED))

	var config: Array = extension["config"]
	if not config.is_empty():
		_detail.add_child(UiTheme.label("Configuration", 30))
		var grid := _grid()
		for field in config:
			var value: Variant = ExtensionRegistry.config_value(_settings, extension["id"], field["key"])
			_config_fields[field["key"]] = _field(grid, field["label"], field["placeholder"], str(value), field.get("secret", false))
			if field.has("help"):
				grid.add_child(Control.new())
				var help := UiTheme.label(field["help"], 20, UiTheme.MUTED)
				help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				grid.add_child(help)
	var buttons := _buttons()
	if extension["kind"] == "remote":
		buttons.add_child(UiTheme.button("PC connection", _select.bind(PC)))
	if not config.is_empty():
		buttons.add_child(UiTheme.button("Save", _save_config.bind(extension)))


func _save_pc() -> void:
	for key in _pc_fields:
		_settings.set(key, _pc_fields[key].text.strip_edges())
	if _settings.sunshine_app == "":
		_settings.sunshine_app = "Desktop"
	if _settings.moonlight_command == "":
		_settings.moonlight_command = "moonlight"
	_settings.save()
	_pc_fields["agent_url"].text = _settings.agent_url  # normalised
	pc_saved.emit()


func _save_config(extension: Dictionary) -> void:
	for field in extension["config"]:
		var text: String = _config_fields[field["key"]].text.strip_edges()
		_settings.set_extension_value(extension["id"], field["key"], text if text != "" else field["default"])
	_settings.save()
	extension_configured.emit(extension["id"])


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 12)
	_detail.add_child(grid)
	return grid


func _field(grid: GridContainer, label: String, placeholder: String, value: String, secret: bool) -> LineEdit:
	grid.add_child(UiTheme.label(label, 24, UiTheme.MUTED))
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.text = value
	edit.secret = secret
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_size_override("font_size", 24)
	grid.add_child(edit)
	return edit


func _buttons() -> HBoxContainer:
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	_detail.add_child(buttons)
	return buttons


func _paragraph(text: String, color: Color) -> Label:
	var label := UiTheme.label(text, 22, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


static func _status_text(extension: Dictionary) -> String:
	if not extension["enabled"]:
		return "Off"
	return extension["status"]


static func _status_color(extension: Dictionary) -> Color:
	if not extension["enabled"]:
		return UiTheme.MUTED
	if extension["problem"]:
		return UiTheme.ERROR
	return UiTheme.TEXT if extension["available"] else UiTheme.MUTED


## Focuses `control` after this frame's changes, unless it's gone by then
## (e.g. the cards were replaced in the meantime).
static func _focus_soon(control: Control) -> void:
	var ref: WeakRef = weakref(control)
	(func() -> void:
		var target: Control = ref.get_ref()
		if target and target.is_inside_tree():
			target.grab_focus()).call_deferred()
