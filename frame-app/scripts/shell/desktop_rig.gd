class_name DesktopRig
extends Camera3D
## Stand-in for a headset when no OpenXR runtime is available. The "head"
## follows the mouse: where the mouse is in the window sets where you look
## (left edge = far left, top = up), eased like a real head turn. You point
## with your gaze, as in a headset: a reticle marks the centre of view, and
## clicks and the wheel act on whatever it is on.

const YAW_RANGE := deg_to_rad(100.0)
const PITCH_UP := deg_to_rad(35.0)
const PITCH_DOWN := deg_to_rad(50.0)
## Higher is snappier. Head-like at ~8.
const SMOOTHING := 8.0

var _router: PointerRouter
## (yaw, pitch) in radians.
var _target := Vector2.ZERO
var _look := Vector2.ZERO
var _reticle := Reticle.new()


func _init(router: PointerRouter) -> void:
	_router = router
	fov = 75.0


func _ready() -> void:
	var layer := CanvasLayer.new()
	_reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_reticle)
	add_child(layer)
	# The reticle replaces the system cursor; keep the mouse inside the
	# window so the head can't "fall off" the edge.
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_target = look_for_mouse(event.position)
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_router.button(event.pressed)
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					var amount: float = event.factor if event.factor > 0.0 else 1.0
					amount *= 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0
					# Shift+wheel scrolls sideways, as in most desktop apps.
					if event.shift_pressed:
						_router.scroll(0.0, amount)
					else:
						_router.scroll(amount)
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT:
				if event.pressed:
					_router.scroll(0.0, 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_RIGHT else -1.0)


func _process(delta: float) -> void:
	_look = _look.lerp(_target, 1.0 - exp(-SMOOTHING * delta))
	basis = Basis.from_euler(Vector3(_look.y, _look.x, 0))
	var hit := _router.update(global_position, -global_basis.z)
	_reticle.set_active(not hit.is_empty())


## (yaw, pitch) for a mouse position in the viewport.
func look_for_mouse(mouse: Vector2) -> Vector2:
	var n := mouse / get_viewport().get_visible_rect().size * 2.0 - Vector2.ONE  # -1..1
	n = n.clamp(-Vector2.ONE, Vector2.ONE)
	var pitch := -n.y * (PITCH_UP if n.y < 0.0 else PITCH_DOWN)
	return Vector2(-n.x * YAW_RANGE, pitch)


## Inverse of look_for_mouse: the mouse position that looks along `direction`.
func mouse_for_direction(direction: Vector3) -> Vector2:
	var d := direction.normalized()
	var yaw := atan2(-d.x, -d.z)
	var pitch := asin(d.y)
	var n := Vector2(-yaw / YAW_RANGE, -pitch / (PITCH_UP if pitch > 0.0 else PITCH_DOWN))
	return (n + Vector2.ONE) / 2.0 * get_viewport().get_visible_rect().size


## Jump straight to where the mouse points (tests, and the first frame).
func snap() -> void:
	_look = _target
	basis = Basis.from_euler(Vector3(_look.y, _look.x, 0))


class Reticle:
	extends Control

	var _active := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_active(active: bool) -> void:
		if active != _active:
			_active = active
			queue_redraw()

	func _draw() -> void:
		var center := size / 2.0
		var radius := 9.0 if _active else 6.0
		draw_circle(center, radius + 2.0, Color(0, 0, 0, 0.5))
		draw_circle(center, radius, UiTheme.ACCENT if _active else Color(1, 1, 1, 0.85))
