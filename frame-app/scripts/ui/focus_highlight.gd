class_name FocusHighlight
extends Node
## How the menus show what's selected, the same way as the movie wall:
## the focused control comes forward slightly and glows softly behind, in
## its own colour where it has one (a poster's colours, an extension's
## colour), and its title brightens. No frame.
##
## Focus follows the pointer: looking or pointing at a button selects it,
## so gaze, a controller ray and controller navigation all look the same.
##
## Controls opt into a colour and a title with metadata:
##   glow_color: Color   (default: a soft neutral light)
##   focus_label: Label  (dimmed until focused)

const LIFT := 1.03
const SECONDS := 0.15
const GLOW_SIZE := 22
const NEUTRAL := Color(0.75, 0.8, 0.95, 0.35)
const GLOW_NAME := "FocusGlow"

var _current: Control
## The pointer moved since the last frame (focus follows it once per frame:
## moving focus re-lays out the buttons, which itself counts as pointer
## motion, so reacting straight away could ping-pong between two buttons
## forever within one frame).
var _pointer_moved := false


func _ready() -> void:
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pointer_moved = true


func _process(_delta: float) -> void:
	if _pointer_moved:
		_pointer_moved = false
		_follow_pointer()
	# Focus can also just go away (released, or the control hidden).
	if not is_instance_valid(_current):
		_current = null
	elif not _current.has_focus():
		_show(_current, false)
		_current = null


func _follow_pointer() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var focused := viewport.gui_get_focus_owner()
	# Don't take focus away from text being typed.
	if focused is LineEdit or focused is TextEdit:
		return
	var hovered := _button_at(viewport.gui_get_hovered_control())
	if hovered and hovered != focused and hovered.is_visible_in_tree():
		hovered.grab_focus()


## The control's own colour for its glow, e.g. after its artwork arrived.
static func set_color(control: Control, colour: Color) -> void:
	control.set_meta("glow_color", colour)
	var glow: Panel = control.get_node_or_null(GLOW_NAME)
	if glow:
		_style(glow, colour)


func _on_focus_changed(control: Control) -> void:
	if is_instance_valid(_current):
		_show(_current, false)
	_current = control if control is BaseButton else null
	if _current:
		_show(_current, true)


func _show(control: Control, on: bool) -> void:
	var glow: Panel = control.get_node_or_null(GLOW_NAME)
	if glow == null:
		if not on:
			return
		glow = Panel.new()
		glow.name = GLOW_NAME
		glow.show_behind_parent = true
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		glow.modulate.a = 0.0
		_style(glow, control.get_meta("glow_color", NEUTRAL))
		control.add_child(glow, false, Node.INTERNAL_MODE_FRONT)
	control.pivot_offset = control.size / 2.0
	control.z_index = 1 if on else 0
	var tween := control.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE * (LIFT if on else 1.0), SECONDS)
	tween.tween_property(glow, "modulate:a", 1.0 if on else 0.0, SECONDS)
	var label: Label = control.get_meta("focus_label") if control.has_meta("focus_label") else null
	if is_instance_valid(label):
		tween.tween_property(label, "theme_override_colors/font_color", UiTheme.TEXT if on else UiTheme.MUTED, SECONDS)


static func _style(glow: Panel, colour: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(colour, 0.0)
	style.set_corner_radius_all(12)
	# Opaque colours (artwork) glow at 0.6; NEUTRAL brings its own alpha.
	style.shadow_color = Color(colour, minf(colour.a, 0.6))
	style.shadow_size = GLOW_SIZE
	glow.add_theme_stylebox_override("panel", style)


## The focusable button under the pointer (the hovered control or one of
## its parents), or null.
static func _button_at(control: Control) -> BaseButton:
	while control:
		if control is BaseButton:
			var button := control as BaseButton
			return button if button.focus_mode != Control.FOCUS_NONE and not button.disabled else null
		control = control.get_parent() as Control
	return null
