class_name Spinner
extends Control
## A rotating arc. Only animates (and redraws) while visible.

const TURNS_PER_SECOND := 1.1
const ARC := TAU * 0.7

var color := UiTheme.ACCENT
var thickness := 4.0
var _angle := 0.0


func _init(diameter := 32.0) -> void:
	custom_minimum_size = Vector2(diameter, diameter)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_angle = fmod(_angle + delta * TURNS_PER_SECOND * TAU, TAU)
	queue_redraw()


func _draw() -> void:
	var radius := minf(size.x, size.y) / 2.0 - thickness
	var center := size / 2.0
	draw_arc(center, radius, 0, TAU, 48, Color(color, 0.15), thickness, true)
	draw_arc(center, radius, _angle, _angle + ARC, 48, color, thickness, true)
