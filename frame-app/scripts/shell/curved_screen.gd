class_name CurvedScreen
extends MeshInstance3D
## A section of a cylinder, centred on this node's origin, showing a region
## of a 2D UI rendered in a SubViewport. Several screens can show different
## regions of the same viewport (e.g. the big screen and the control deck).
## Stand at the origin (the cylinder's axis) and every point of the screen is
## the same distance away.
##
## Pointer input is mapped from 3D rays to viewport pixels with an exact
## ray/cylinder intersection and delivered as ordinary mouse events, so the
## UI doesn't know it's in 3D. Implements the PointerRouter target API.

const SEGMENTS := 64

var viewport: SubViewport
## The part of the viewport shown, in viewport pixels.
var region: Rect2
var radius: float
var width: float
var height: float
## Angle the screen spans, in radians.
var arc: float

var _material := StandardMaterial3D.new()
var _fade: Tween
var _last_pixel := Vector2(-1, -1)
var _buttons_down := 0


func _init(source: SubViewport, screen_radius: float, screen_width: float, source_region := Rect2()) -> void:
	viewport = source
	region = source_region if source_region.has_area() else Rect2(Vector2.ZERO, Vector2(source.size))
	radius = screen_radius
	width = screen_width
	height = screen_width * region.size.y / region.size.x
	arc = screen_width / screen_radius

	mesh = _build_mesh()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_texture = viewport.get_texture()
	material_override = _material


## Fades to `opacity` (hidden, and not pointable, at 0).
func fade(opacity: float, seconds := 0.25) -> void:
	if _fade:
		_fade.kill()
	if opacity > 0.0:
		visible = true
	else:
		pointer_exit()
	_fade = create_tween()
	_fade.tween_property(_material, "albedo_color:a", opacity, seconds)
	if opacity <= 0.0:
		_fade.tween_callback(hide)


func set_opacity(opacity: float) -> void:
	if _fade:
		_fade.kill()
	_material.albedo_color.a = opacity
	visible = opacity > 0.0


## Where a ray hits the screen: {pixel, point, distance}, or {} for a miss.
## `pixel` is in viewport coordinates.
func intersect(origin: Vector3, direction: Vector3) -> Dictionary:
	var to_local := global_transform.affine_inverse()
	var o := to_local * origin
	var d := (to_local.basis * direction).normalized()
	# Solve |(o + t*d).xz| = radius. From inside the cylinder the screen is
	# the far root; looking away from it lands outside the arc.
	var a := d.x * d.x + d.z * d.z
	var b := 2.0 * (o.x * d.x + o.z * d.z)
	var c := o.x * o.x + o.z * o.z - radius * radius
	var discriminant := b * b - 4.0 * a * c
	if a < 1e-9 or discriminant < 0.0:
		return {}
	var t := (-b + sqrt(discriminant)) / (2.0 * a)
	if t <= 0.0:
		return {}
	var p := o + d * t
	var u := atan2(p.x, -p.z) / arc + 0.5
	var v := 0.5 - p.y / height
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return {}
	return {
		"pixel": region.position + Vector2(u, v) * region.size,
		"point": global_transform * p,
		"distance": t,
	}


## The 3D point for a viewport pixel (the inverse of intersect()).
func pixel_to_point(pixel: Vector2) -> Vector3:
	var uv := (pixel - region.position) / region.size
	var angle := (uv.x - 0.5) * arc
	var y := (0.5 - uv.y) * height
	return global_transform * Vector3(radius * sin(angle), y, -radius * cos(angle))


# --- PointerRouter target API ---

func pointer_hit(origin: Vector3, direction: Vector3) -> Dictionary:
	if not is_visible_in_tree() or _material.albedo_color.a < 0.5:
		return {}
	return intersect(origin, direction)


func pointer_move(hit: Dictionary) -> void:
	_send_motion(hit.pixel)


func pointer_button(hit: Dictionary, pressed: bool) -> void:
	var pixel: Vector2 = hit.get("pixel", _last_pixel)
	if pixel.x < 0:
		return
	_send_button(pixel, pressed, MOUSE_BUTTON_LEFT)


func pointer_scroll(hit: Dictionary, dy: float, dx: float) -> void:
	if dy != 0.0:
		_send_wheel(hit.pixel, MOUSE_BUTTON_WHEEL_DOWN if dy > 0 else MOUSE_BUTTON_WHEEL_UP, absf(dy))
	if dx != 0.0:
		_send_wheel(hit.pixel, MOUSE_BUTTON_WHEEL_RIGHT if dx > 0 else MOUSE_BUTTON_WHEEL_LEFT, absf(dx))


## The pointer left the screen: release anything held so the UI doesn't get
## stuck mid-drag.
func pointer_exit() -> void:
	if _buttons_down & 1 and _last_pixel.x >= 0:
		_send_button(_last_pixel, false, MOUSE_BUTTON_LEFT)
	_last_pixel = Vector2(-1, -1)


# --- Event synthesis ---

func _send_motion(pixel: Vector2) -> void:
	if pixel == _last_pixel:
		return
	var event := InputEventMouseMotion.new()
	event.position = pixel
	event.global_position = pixel
	event.relative = pixel - _last_pixel if _last_pixel.x >= 0 else Vector2.ZERO
	event.button_mask = _buttons_down
	_last_pixel = pixel
	viewport.push_input(event, true)


func _send_button(pixel: Vector2, pressed: bool, button: MouseButton) -> void:
	_send_motion(pixel)
	var mask := 1 << (button - 1)
	_buttons_down = (_buttons_down | mask) if pressed else (_buttons_down & ~mask)
	var event := InputEventMouseButton.new()
	event.position = pixel
	event.global_position = pixel
	event.button_index = button
	event.pressed = pressed
	event.button_mask = _buttons_down
	viewport.push_input(event, true)


func _send_wheel(pixel: Vector2, button: MouseButton, factor: float) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = pixel
		event.global_position = pixel
		event.button_index = button
		event.factor = factor
		event.pressed = pressed
		viewport.push_input(event, true)


func _build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uv_origin := region.position / Vector2(viewport.size)
	var uv_size := region.size / Vector2(viewport.size)
	for i in SEGMENTS + 1:
		var u := float(i) / SEGMENTS
		var angle := (u - 0.5) * arc
		var x := radius * sin(angle)
		var z := -radius * cos(angle)
		var inward := Vector3(-sin(angle), 0, cos(angle))
		for row in [[0.0, height / 2.0], [1.0, -height / 2.0]]:
			st.set_normal(inward)
			st.set_uv(uv_origin + Vector2(u, row[0]) * uv_size)
			st.add_vertex(Vector3(x, row[1], z))
	for i in SEGMENTS:
		var top := i * 2
		st.add_index(top)
		st.add_index(top + 2)
		st.add_index(top + 1)
		st.add_index(top + 1)
		st.add_index(top + 2)
		st.add_index(top + 3)
	return st.commit()
