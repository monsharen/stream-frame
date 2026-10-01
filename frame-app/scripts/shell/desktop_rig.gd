class_name DesktopRig
extends Camera3D
## Stand-in for a headset when no OpenXR runtime is available: a camera at
## head position. Right-drag to look around; the mouse acts as the pointer
## on the screen (click, hover, wheel to scroll).

const LOOK_SENSITIVITY := 0.004
const MAX_PITCH := deg_to_rad(80.0)

var _screen: CurvedScreen
var _looking := false
var _yaw := 0.0
var _pitch := 0.0


func _init(screen: CurvedScreen) -> void:
	_screen = screen
	fov = 75.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_looking = event.pressed
			return
		var hit := _hit(event.position)
		if hit.is_empty():
			return
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if event.pressed:
				_screen.pointer_scroll(hit.pixel, event.factor if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -event.factor)
		else:
			_screen.pointer_button(hit.pixel, event.pressed, event.button_index)
	elif event is InputEventMouseMotion:
		if _looking:
			_yaw -= event.relative.x * LOOK_SENSITIVITY
			_pitch = clampf(_pitch - event.relative.y * LOOK_SENSITIVITY, -MAX_PITCH, MAX_PITCH)
			basis = Basis.from_euler(Vector3(_pitch, _yaw, 0))
			return
		var hit := _hit(event.position)
		if hit.is_empty():
			_screen.pointer_exit()
		else:
			_screen.pointer_move(hit.pixel)


func _hit(mouse_position: Vector2) -> Dictionary:
	return _screen.intersect(project_ray_origin(mouse_position), project_ray_normal(mouse_position))
