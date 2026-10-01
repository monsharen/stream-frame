class_name ScreenGlow
extends MeshInstance3D
## A band around and behind the curved screen, glowing in the colours at
## the matching edge of the picture (bias lighting / "Ambilight"). Lives
## under the screen node, so it follows the screen's size and tilt.

const SHADER := preload("res://shaders/ambient_glow.gdshader")
const SEGMENTS := 64
const SCALE := Vector2(1.9, 1.9)
## Never wrap further round than this (radians), for big screens.
const MAX_ARC := 2.9

var _material := ShaderMaterial.new()
var _band_inner := Vector2.ONE
var _screen_aspect := 1.7778


func _init() -> void:
	_material.shader = SHADER
	_material.render_priority = -1
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func build(radius: float, screen_width: float, screen_height: float) -> void:
	var band_radius := radius + 0.03
	var scale_x := minf(SCALE.x, MAX_ARC * band_radius / screen_width)
	var band_width := screen_width * scale_x
	var band_height := screen_height * SCALE.y
	var arc := band_width / band_radius
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEGMENTS + 1:
		var u := float(i) / SEGMENTS
		var angle := (u - 0.5) * arc
		for row in [[0.0, band_height / 2.0], [1.0, -band_height / 2.0]]:
			st.set_uv(Vector2(u, row[0]))
			st.add_vertex(Vector3(band_radius * sin(angle), row[1], -band_radius * cos(angle)))
	for i in SEGMENTS:
		var top := i * 2
		for index in [top, top + 2, top + 1, top + 1, top + 2, top + 3]:
			st.add_index(index)
	mesh = st.commit()
	_band_inner = Vector2(1.0 / scale_x, 1.0 / SCALE.y)
	_screen_aspect = screen_width / screen_height
	set_picture_aspect(_screen_aspect)


## The glow starts at the picture's edges: a picture narrower or wider than
## the screen is centred in it (as the screen shows it).
func set_picture_aspect(picture_aspect: float) -> void:
	var fit := Vector2(1.0, _screen_aspect / picture_aspect) if picture_aspect > _screen_aspect \
		else Vector2(picture_aspect / _screen_aspect, 1.0)
	_material.set_shader_parameter("inner", _band_inner * fit)
	_material.set_shader_parameter("screen_aspect", picture_aspect)


## `ambient`: the film's colours; `menu`: what lights it otherwise (menus,
## a poster while loading), mixed in by `menu_mix`.
func set_light(ambient: Texture2D, menu: Texture2D, menu_mix: float, fade: float, strength: float) -> void:
	_material.set_shader_parameter("ambient", ambient)
	_material.set_shader_parameter("menu_light", menu)
	_material.set_shader_parameter("menu_mix", menu_mix)
	_material.set_shader_parameter("fade", fade)
	_material.set_shader_parameter("strength", strength)
	visible = fade > 0.001 and strength > 0.0 and (ambient != null or menu_mix > 0.0)
