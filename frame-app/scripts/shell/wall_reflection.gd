class_name WallReflection
extends MeshInstance3D
## The movie wall's light on the floor: a curved strip at the wall's foot,
## coloured by the posters above it (MovieWall.floor_light).

const SHADER := preload("res://shaders/wall_reflection.gdshader")
const SEGMENTS := 64
## How far in from the wall the light reaches.
const DEPTH := 1.6

var _material := ShaderMaterial.new()


func _init() -> void:
	_material.shader = SHADER
	_material.render_priority = -1
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A strip on the floor from the wall (`radius`) inwards, spanning `arc`.
func build(radius: float, arc: float, light: Texture2D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEGMENTS + 1:
		var u := float(i) / SEGMENTS
		var angle := (u - 0.5) * arc
		for edge in [[0.0, radius], [1.0, radius - DEPTH]]:
			st.set_uv(Vector2(u, edge[0]))
			st.add_vertex(Vector3(edge[1] * sin(angle), 0.0, -edge[1] * cos(angle)))
	for i in SEGMENTS:
		var a := i * 2
		for index in [a, a + 2, a + 1, a + 1, a + 2, a + 3]:
			st.add_index(index)
	mesh = st.commit()
	_material.set_shader_parameter("wall_light", light)


func set_fade(fade: float) -> void:
	_material.set_shader_parameter("fade", fade)
	visible = fade > 0.001
