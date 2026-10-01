class_name FloorReflection
extends MeshInstance3D
## A soft reflection of the picture on the floor in front of the screen.

const SHADER := preload("res://shaders/floor_reflection.gdshader")
const DEPTH := 2.0

var _material := ShaderMaterial.new()


func _init() -> void:
	_material.shader = SHADER
	_material.render_priority = -1
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Covers the floor from the foot of a screen `radius` away towards the viewer.
func build(radius: float, screen_width: float) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(screen_width * 1.3, DEPTH)
	mesh = plane
	position = Vector3(0, 0.003, -radius + DEPTH / 2.0 + 0.05)


## As ScreenGlow.set_light.
func set_light(ambient: Texture2D, menu: Texture2D, menu_mix: float, fade: float) -> void:
	_material.set_shader_parameter("ambient", ambient)
	_material.set_shader_parameter("menu_light", menu)
	_material.set_shader_parameter("menu_mix", menu_mix)
	_material.set_shader_parameter("fade", fade)
	visible = fade > 0.001 and (ambient != null or menu_mix > 0.0)
