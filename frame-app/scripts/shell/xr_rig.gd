class_name XrRig
extends XROrigin3D
## Headset and controllers. Each controller casts a laser; the trigger
## clicks, the thumbstick scrolls. Whichever controller last pulled its
## trigger drives the UI's hover.

const RAY_LENGTH := 10.0
const SCROLL_DEADZONE := 0.3
const SCROLL_PER_SECOND := 12.0
const RAY_COLOR := Color(1, 1, 1, 0.35)
const DOT_COLOR := Color("e5a50a")

var _screen: CurvedScreen
var _controllers: Array[XRController3D] = []
var _active: XRController3D
var _scroll_accumulator := 0.0


func _init(screen: CurvedScreen) -> void:
	_screen = screen
	add_child(XRCamera3D.new())
	for tracker in [&"left_hand", &"right_hand"]:
		var controller := XRController3D.new()
		controller.tracker = tracker
		controller.pose = &"aim"
		controller.add_child(_make_ray())
		controller.add_child(_make_dot())
		controller.button_pressed.connect(_on_button.bind(controller, true))
		controller.button_released.connect(_on_button.bind(controller, false))
		add_child(controller)
		_controllers.append(controller)
	_active = _controllers[1]


func _process(delta: float) -> void:
	for controller in _controllers:
		var ray: Node3D = controller.get_child(0)
		var dot: MeshInstance3D = controller.get_child(1)
		var hit := _hit(controller)
		var length: float = RAY_LENGTH if hit.is_empty() else hit.distance
		ray.scale.z = length
		ray.visible = controller.get_has_tracking_data()
		dot.visible = ray.visible and not hit.is_empty()
		if hit.is_empty():
			if controller == _active:
				_screen.pointer_exit()
			continue
		dot.global_position = hit.point
		if controller == _active:
			_screen.pointer_move(hit.pixel)
			_scroll(controller, hit.pixel, delta)


func _on_button(button: String, controller: XRController3D, pressed: bool) -> void:
	if button != "trigger_click":
		return
	if pressed:
		_active = controller
	var hit := _hit(controller)
	if not hit.is_empty():
		_screen.pointer_button(hit.pixel, pressed)


func _scroll(controller: XRController3D, pixel: Vector2, delta: float) -> void:
	var stick := controller.get_vector2(&"primary")
	if absf(stick.y) < SCROLL_DEADZONE:
		_scroll_accumulator = 0.0
		return
	# Stick up = scroll up, like a wheel.
	_scroll_accumulator += -stick.y * SCROLL_PER_SECOND * delta
	if absf(_scroll_accumulator) >= 1.0:
		_screen.pointer_scroll(pixel, _scroll_accumulator)
		_scroll_accumulator = 0.0


func _hit(controller: XRController3D) -> Dictionary:
	if not controller.get_has_tracking_data():
		return {}
	var t := controller.global_transform
	return _screen.intersect(t.origin, -t.basis.z)


static func _make_ray() -> Node3D:
	# A 1 m beam along -Z under a holder that is scaled to the hit distance.
	var beam := BoxMesh.new()
	beam.size = Vector3(0.003, 0.003, 1.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = RAY_COLOR
	var node := MeshInstance3D.new()
	node.mesh = beam
	node.material_override = material
	node.position.z = -0.5
	var holder := Node3D.new()
	holder.add_child(node)
	return holder


static func _make_dot() -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 0.012
	sphere.height = 0.024
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = DOT_COLOR
	var node := MeshInstance3D.new()
	node.mesh = sphere
	node.material_override = material
	node.top_level = true
	return node
