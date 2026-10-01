class_name SourceInfoView
extends CenterContainer
## What's up with an extension: shown when an unavailable one is launched,
## or from "What's wrong?" when one fails in use. Why it can't be used right
## now, what to do next, and buttons for the relevant actions.

signal back_requested
signal action_requested(action: String)

const ACTION_LABELS := {
	"pc": "PC connection",
	"configure": "Configure",
	"retry": "Try again",
	"demo": "Try the offline demo",
}

## The extension on display (and the error shown, if any), so the page can
## be refreshed when its status changes.
var source_id := ""
var error := ""

var _title := UiTheme.label("", 56)
var _status := UiTheme.label("", 30, UiTheme.ACCENT)
var _reason := UiTheme.label("", 32)
var _error := UiTheme.label("", 28, UiTheme.ERROR)
var _steps := VBoxContainer.new()
var _buttons := HBoxContainer.new()
var _back := UiTheme.button("Back", back_requested.emit)


func _init() -> void:
	var panel := PanelContainer.new()
	# Big: in 3D this is read on the screen a couple of metres away.
	panel.custom_minimum_size.x = 1400
	add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 18)
	panel.add_child(layout)
	layout.add_child(_title)
	layout.add_child(_status)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_error)
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_reason)
	_steps.add_theme_constant_override("separation", 10)
	layout.add_child(_steps)
	_buttons.add_theme_constant_override("separation", 12)
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	layout.add_child(_buttons)


## `error`: what just went wrong while using it, if anything.
func show_source(source: Dictionary, error := "") -> void:
	source_id = source["id"]
	_title.text = source["name"]
	_status.text = source["status"]
	_status.add_theme_color_override("font_color", UiTheme.ERROR if source.get("problem", false) else UiTheme.ACCENT)
	self.error = error
	_error.text = error
	_error.visible = error != ""
	_reason.text = source["reason"]
	for child in _steps.get_children():
		child.queue_free()
	var steps: Array = source["steps"]
	if not steps.is_empty():
		_steps.add_child(UiTheme.label("What to do next" if source.get("problem", false) else "How to get started" if source["kind"] == "remote" else "Status", 32))
	for i in steps.size():
		var step := UiTheme.label("%d.  %s" % [i + 1, steps[i]], 28, UiTheme.MUTED)
		step.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_steps.add_child(step)
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		if child != _back:
			child.queue_free()
	_buttons.add_child(_back)
	for action: String in source["actions"]:
		_buttons.add_child(UiTheme.button(ACTION_LABELS[action], action_requested.emit.bind(action)))
	for button: Button in _buttons.get_children():
		button.add_theme_font_size_override("font_size", 28)


func focus_content() -> void:
	# The first action (the most useful one) if there is one; Back otherwise.
	(_buttons.get_child(mini(1, _buttons.get_child_count() - 1)) as Control).grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		accept_event()
