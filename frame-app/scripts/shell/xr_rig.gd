class_name XrRig
extends XROrigin3D
## Headset and controllers. Each controller casts a laser; the trigger
## clicks, the thumbstick scrolls (up/down, and sideways along a wall row).
## Whichever controller last pulled its trigger is the pointer; the other
## just shows where it's aiming.

const RAY_LENGTH := 10.0
const SCROLL_DEADZONE := 0.3
const SCROLL_PER_SECOND := 12.0
const RAY_COLOR := Color(1, 1, 1, 0.35)
const DOT_COLOR := Color("e5a50a")

var _router: PointerRouter
var _controllers: Array[XRController3D] = []
var _active: XRController3D
var _scroll_accumulator := Vector2.ZERO
## While watching, rays stay hidden until a controller moves or is used.
var _quiet := false
var _last_activity := 0.0
var _last_positions: Dictionary = {}
const QUIET_SECONDS := 3.0
## Controller speed (m/s) that counts as reaching for the controls.
const WAKE_SPEED := 0.25


func _init(router: PointerRouter) -> void:
	_router = router
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


## Snap-turns you by `angle` (radians, positive = left) about where your
## head is: instant, the comfortable way to turn in VR.
func turn(angle: float) -> void:
	var head := (get_child(0) as Node3D).global_position
	var pivot := Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO)
	global_transform = Transform3D.IDENTITY.translated(head) * pivot * Transform3D.IDENTITY.translated(-head) * global_transform


func set_quiet(quiet: bool) -> void:
	_quiet = quiet
	_last_activity = Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for controller in _controllers:
		var position := controller.global_position
		if _last_positions.has(controller) and delta > 0.0 \
				and (position - _last_positions[controller]).length() / delta > WAKE_SPEED:
			_last_activity = now
		_last_positions[controller] = position
	var awake := not _quiet or now - _last_activity < QUIET_SECONDS
	for controller in _controllers:
		var ray: Node3D = controller.get_child(0)
		var dot: MeshInstance3D = controller.get_child(1)
		var tracked := controller.get_has_tracking_data()
		var hit := {}
		if tracked:
			var t := controller.global_transform
			if controller == _active:
				hit = _router.update(t.origin, -t.basis.z)
			else:
				hit = _router.cast(t.origin, -t.basis.z)[1]
		ray.visible = tracked and awake
		ray.scale.z = RAY_LENGTH if hit.is_empty() else hit.distance
		dot.visible = tracked and awake and not hit.is_empty()
		if dot.visible:
			dot.global_position = hit.point
		if controller == _active and not hit.is_empty():
			_scroll(controller, delta)


func _on_button(button: String, controller: XRController3D, pressed: bool) -> void:
	_last_activity = Time.get_ticks_msec() / 1000.0
	if button != "trigger_click":
		# Other buttons trigger whatever app action they're bound to (or,
		# while the Controls page waits for one, get bound).
		if InputActions.xr_capture.is_valid():
			if pressed:
				InputActions.xr_capture.call("xr:" + button)
			return
		var action := InputActions.for_xr_button(button)
		if action != &"":
			var event := InputEventAction.new()
			event.action = action
			event.pressed = pressed
			Input.parse_input_event(event)
		return
	if pressed and controller != _active:
		# Switch pointers: aim with this controller before clicking.
		_active = controller
		var t := controller.global_transform
		_router.update(t.origin, -t.basis.z)
	_router.button(pressed)


func _scroll(controller: XRController3D, delta: float) -> void:
	var stick := controller.get_vector2(&"primary")
	var dead := Vector2(absf(stick.x) < SCROLL_DEADZONE, absf(stick.y) < SCROLL_DEADZONE)
	if dead.x and dead.y:
		_scroll_accumulator = Vector2.ZERO
		return
	# Stick down = scroll down, like a wheel; stick right = scroll right.
	_scroll_accumulator += Vector2(0.0 if dead.x else stick.x, 0.0 if dead.y else -stick.y) * SCROLL_PER_SECOND * delta
	if absf(_scroll_accumulator.x) >= 1.0 or absf(_scroll_accumulator.y) >= 1.0:
		_router.scroll(_scroll_accumulator.y, _scroll_accumulator.x)
		_scroll_accumulator = Vector2.ZERO


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
