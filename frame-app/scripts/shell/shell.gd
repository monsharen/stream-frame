extends Node3D
## App entry point. Puts the 2D app (main.tscn) on a curved screen in a dark
## room and picks how you look at it:
##   - OpenXR headset when a runtime is available (the Steam Frame),
##   - a desktop 3D preview otherwise (right-drag to look, click the screen),
##   - plain 2D with --flat / STREAM_FRAME_FLAT=1, for quick UI work.

const UiScene := preload("res://main.tscn")
## Head height for the desktop preview; in XR the headset reports the real one.
const EYE_HEIGHT := 1.6

var screen: CurvedScreen
var ui: Control
var xr_active := false


func _ready() -> void:
	ui = UiScene.instantiate()
	if "--flat" in OS.get_cmdline_user_args() or OS.get_environment("STREAM_FRAME_FLAT") == "1":
		add_child(ui)
		return

	_build_room()
	screen = CurvedScreen.new(ui)
	screen.position.y = EYE_HEIGHT
	add_child(screen)

	var openxr := XRServer.find_interface("OpenXR")
	xr_active = openxr != null and openxr.is_initialized()
	if xr_active:
		get_viewport().use_xr = true
		add_child(XrRig.new(screen))
	else:
		var camera := DesktopRig.new(screen)
		camera.position.y = EYE_HEIGHT
		add_child(camera)


func _unhandled_input(event: InputEvent) -> void:
	# Keyboard and gamepad go straight to the UI; pointer input is routed by
	# the rigs via ray hits.
	if screen and (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		screen.viewport.push_input(event)


func _build_room() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("07080a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("1a1c22")
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(40, 40)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("101217")
	floor_material.roughness = 0.6
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.material_override = floor_material
	add_child(floor_node)

	# The screen "lights" the floor in front of it.
	var spill := OmniLight3D.new()
	spill.position = Vector3(0, 0.6, -1.9)
	spill.light_color = Color("c9d4ff")
	spill.light_energy = 0.8
	spill.omni_range = 4.0
	add_child(spill)
