class_name CurvedScreen
extends MeshInstance3D
## A section of a cylinder, centred on this node's origin, showing a 2D UI
## rendered in a SubViewport. Stand at the origin (the cylinder's axis) and
## every point of the screen is the same distance away.
##
## Pointers (controller rays, the desktop mouse) are mapped from 3D rays to
## viewport pixels with an exact ray/cylinder intersection, then delivered
## to the UI as ordinary mouse events, so the UI doesn't know it's in 3D.

const SEGMENTS := 64

var viewport := SubViewport.new()
var radius: float
var width: float
var height: float
## Angle the screen spans, in radians.
var arc: float

var _last_pixel := Vector2(-1, -1)
var _buttons_down := 0


func _init(content: Control, resolution := Vector2i(1920, 1080), screen_radius := 2.4, screen_width := 2.8) -> void:
	radius = screen_radius
	width = screen_width
	height = screen_width * resolution.y / resolution.x
	arc = screen_width / screen_radius

	viewport.size = resolution
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_embed_subwindows = true
	viewport.add_child(content)
	add_child(viewport)

	mesh = _build_mesh()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.albedo_texture = viewport.get_texture()
	material_override = material


## Where a ray hits the screen: {pixel, point, distance}, or {} for a miss.
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
		"pixel": Vector2(u * viewport.size.x, v * viewport.size.y),
		"point": global_transform * p,
		"distance": t,
	}


## The 3D point for a viewport pixel (the inverse of intersect()).
func pixel_to_point(pixel: Vector2) -> Vector3:
	var angle := (pixel.x / viewport.size.x - 0.5) * arc
	var y := (0.5 - pixel.y / viewport.size.y) * height
	return global_transform * Vector3(radius * sin(angle), y, -radius * cos(angle))


func pointer_move(pixel: Vector2) -> void:
	if pixel == _last_pixel:
		return
	var event := InputEventMouseMotion.new()
	event.position = pixel
	event.global_position = pixel
	event.relative = pixel - _last_pixel if _last_pixel.x >= 0 else Vector2.ZERO
	event.button_mask = _buttons_down
	_last_pixel = pixel
	viewport.push_input(event, true)


func pointer_button(pixel: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	pointer_move(pixel)
	var mask := 1 << (button - 1)
	_buttons_down = (_buttons_down | mask) if pressed else (_buttons_down & ~mask)
	var event := InputEventMouseButton.new()
	event.position = pixel
	event.global_position = pixel
	event.button_index = button
	event.pressed = pressed
	event.button_mask = _buttons_down
	viewport.push_input(event, true)


## Positive scrolls content down (like wheel-down).
func pointer_scroll(pixel: Vector2, amount: float) -> void:
	var button := MOUSE_BUTTON_WHEEL_DOWN if amount > 0 else MOUSE_BUTTON_WHEEL_UP
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = pixel
		event.global_position = pixel
		event.button_index = button
		event.factor = absf(amount)
		event.pressed = pressed
		viewport.push_input(event, true)


## The pointer left the screen: release anything held so the UI doesn't get
## stuck mid-drag.
func pointer_exit() -> void:
	if _buttons_down & 1 and _last_pixel.x >= 0:
		pointer_button(_last_pixel, false)
	_last_pixel = Vector2(-1, -1)


func _build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEGMENTS + 1:
		var u := float(i) / SEGMENTS
		var angle := (u - 0.5) * arc
		var x := radius * sin(angle)
		var z := -radius * cos(angle)
		var inward := Vector3(-sin(angle), 0, cos(angle))
		for row in [[0.0, height / 2.0], [1.0, -height / 2.0]]:
			st.set_normal(inward)
			st.set_uv(Vector2(u, row[0]))
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
