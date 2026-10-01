class_name SettingsView
extends CenterContainer
## Connection settings. Shown on first launch and from the browse view.

signal saved
signal offline_requested

var _settings: Settings
var _fields: Dictionary[String, LineEdit] = {}

const FIELDS := [
	["agent_url", "Host agent URL", "http://192.168.1.20:8787"],
	["token", "Agent token", "AGENT_TOKEN on the host"],
	["sunshine_host", "Sunshine host", "Same host as the agent"],
	["sunshine_app", "Sunshine app", "Desktop"],
	["moonlight_command", "Moonlight command", "moonlight"],
]


func _init(settings: Settings) -> void:
	_settings = settings
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 900
	add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	panel.add_child(layout)
	layout.add_child(UiTheme.label("Connect to your streaming PC", 36))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 12)
	layout.add_child(grid)
	for field in FIELDS:
		grid.add_child(UiTheme.label(field[1], 22, UiTheme.MUTED))
		var edit := LineEdit.new()
		edit.placeholder_text = field[2]
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.secret = field[0] == "token"
		edit.text_submitted.connect(func(_text: String) -> void: _save())
		grid.add_child(edit)
		_fields[field[0]] = edit

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_child(UiTheme.button("Try offline demo", offline_requested.emit))
	buttons.add_child(UiTheme.button("Save and connect", _save))
	layout.add_child(buttons)


func open() -> void:
	for key in _fields:
		_fields[key].text = str(_settings.get(key))
	_fields["agent_url"].grab_focus()


func focus_content() -> void:
	_fields["agent_url"].grab_focus()


func _save() -> void:
	for key in _fields:
		_settings.set(key, _fields[key].text.strip_edges())
	if _settings.sunshine_app == "":
		_settings.sunshine_app = "Desktop"
	if _settings.moonlight_command == "":
		_settings.moonlight_command = "moonlight"
	_settings.save()
	saved.emit()
