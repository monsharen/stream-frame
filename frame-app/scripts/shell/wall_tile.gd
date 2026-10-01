class_name WallTile
extends Node3D
## One tile on the movie wall: a poster, or an extension/app card (its
## generated poster, with its name as a stand-in until that is ready) and a
## title underneath. Hovered (looked or pointed at), the artwork comes
## forward slightly, tilts towards the pointer (like Apple TV's cards) and
## casts a soft light around itself in its own colours, like the screen's
## glow while a film plays, and the title brightens.
##
## The wall positions it; the tile animates itself: appearing (it rises
## into place, timed by the wall for a wave across the wall), its artwork
## developing from dark when it arrives, and the hover lift and tilt.

const SIZE := Vector2(0.56, 0.315)
## Hover comes forward just noticeably; the light and title do the rest.
const HOVER_LIFT := 0.05
const HOVER_SCALE := 0.03
const HOVER_SPEED := 8.0
const APPEAR_SECONDS := 0.45
const DEVELOP_SECONDS := 0.5
const TITLE_MAX_CHARS := 34
## Artwork starts this dark and brightens to full colour.
const UNDEVELOPED := Color(0.12, 0.13, 0.16)
const ART_SHADER := preload("res://shaders/tile_art.gdshader")
const CORNER_RADIUS := 0.018
const LIGHT_SHADER := preload("res://shaders/ambient_glow.gdshader")
## The hover light's quad, in tile sizes (room for the glow to fade out
## fully), and its strength.
const LIGHT_SCALE := Vector2(2.0, 2.6)
const LIGHT_STRENGTH := 0.7
## Every tile lights the floor a little; the hovered one more.
const FLOOR_BASE := 0.35
## Hover tilt: the most it turns (radians), and how fast it follows.
const TILT := 0.2
const TILT_SPEED := 10.0

## Scales every tile's light (0 = off); set from the glow setting.
static var light_level := 1.0

## Empty for loading placeholders.
var item: Dictionary
var art := MeshInstance3D.new()
## 0..1, animated towards the hover target; the wall reads it for the lift.
var hover := 0.0
## 0..1 as the tile rises into place; the wall reads it for the approach.
var appear := 0.0

var _art_material := ShaderMaterial.new()
var _light := MeshInstance3D.new()
var _light_material := ShaderMaterial.new()
## The artwork's average colour (black until it has arrived).
var _light_color := Color.BLACK
var _images: ImageCache
var _art_url := ""
## Where the pointer is on the artwork (-1..1 each way), and the tilt
## easing towards it.
var _tilt := Vector2.ZERO
var _tilt_target := Vector2.ZERO
var _title := Label3D.new()
var _card_text: Label3D
var _hover_target := 0.0
var _alpha := 1.0
var _image_url := ""
var _base_color: Color
## Seconds (engine time) when the tile starts appearing.
var _appear_at := INF
## 0..1 once artwork has arrived; -1 while there is none.
var _develop := -1.0


func _init(catalog_item: Dictionary = {}) -> void:
	item = catalog_item
	_image_url = item.get("image", "")
	_base_color = item.get("art_color", UiTheme.BORDER)

	var quad := QuadMesh.new()
	quad.size = SIZE
	art.mesh = quad
	# Rounded corners; writes depth, so the hover light (drawn after) stays
	# behind it.
	_art_material.shader = ART_SHADER
	_art_material.set_shader_parameter("size", SIZE)
	_art_material.set_shader_parameter("radius", CORNER_RADIUS)
	_art_material.set_shader_parameter("tint", _base_color)  # until the artwork arrives
	art.material_override = _art_material
	add_child(art)

	if item.has("art_text"):
		# The name, until the generated poster (which includes it) is ready.
		_card_text = Label3D.new()
		_card_text.text = item["art_text"]
		var fit := int(SIZE.x / 0.001 * 0.9 / (0.55 * maxi(1, item["art_text"].length())))
		_card_text.font_size = clampi(fit, 32, 72)
		_card_text.pixel_size = 0.001
		_card_text.position.z = 0.002
		_card_text.modulate = UiTheme.TEXT
		art.add_child(_card_text)

	# The light the artwork casts while hovered: drawn after the other
	# tiles, so it spills over its neighbours (it's lifted in front of them).
	var light_mesh := QuadMesh.new()
	light_mesh.size = SIZE * LIGHT_SCALE
	_light.mesh = light_mesh
	_light.position.z = -0.01
	_light.visible = false
	_light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light_material.shader = LIGHT_SHADER
	_light_material.render_priority = 1
	_light_material.set_shader_parameter("inner", Vector2.ONE / LIGHT_SCALE)
	_light_material.set_shader_parameter("screen_aspect", SIZE.x / SIZE.y)
	_light_material.set_shader_parameter("spread", 0.26)
	_light.material_override = _light_material
	art.add_child(_light)
	if not is_placeholder():
		# Until the artwork arrives, the light is the card's colour.
		_set_light_source(ImageTexture.create_from_image(Image.create_from_data(1, 1, false, Image.FORMAT_RGB8,
			PackedByteArray([_base_color.r8, _base_color.g8, _base_color.b8]))), _base_color)

	var text: String = item.get("display_title", item.get("title", ""))
	if text.length() > TITLE_MAX_CHARS:
		text = text.left(TITLE_MAX_CHARS - 1) + "…"
	_title.text = text
	# Extension cards have a short status line; make it readable from afar.
	_title.font_size = 46 if item.get("kind") == "source" else 36
	_title.pixel_size = 0.001
	_title.position.y = -SIZE.y / 2.0 - 0.035
	_title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_title.outline_size = 0
	add_child(_title)
	_apply()


func is_placeholder() -> bool:
	return item.is_empty()


func texture() -> Texture2D:
	return _art_material.get_shader_parameter("art") if _art_material.get_shader_parameter("has_art") else null


## Starts the appear animation `delay` seconds from now (engine time).
func start_appearing(now: float, delay: float) -> void:
	_appear_at = now + delay


func appear_eased() -> float:
	return ease(appear, 0.4)  # fast start, soft landing


## Fetches the artwork the first time the tile becomes visible.
func ensure_texture(images: ImageCache) -> void:
	if _image_url == "":
		return
	_images = images
	_art_url = _image_url
	_image_url = ""
	images.load_texture(_art_url, _set_texture)


## The light this tile casts on the floor right now (colour × strength).
func light() -> Color:
	return _light_color * _lit() * (FLOOR_BASE + hover)


func set_hovered(hovered: bool) -> void:
	_hover_target = 1.0 if hovered else 0.0
	if not hovered:
		_tilt_target = Vector2.ZERO


## The pointer is at `point` (global) on the hovered artwork: tilt so that
## side dips away. True if that changes the tilt.
func point_at(point: Vector3) -> bool:
	var local := global_transform.affine_inverse() * point
	var target := Vector2(clampf(local.x / (SIZE.x / 2.0), -1.0, 1.0), clampf(local.y / (SIZE.y / 2.0), -1.0, 1.0))
	if target.distance_to(_tilt_target) < 0.01:
		return false
	_tilt_target = target
	return true


## Advances hover/appear/develop; true while any of them is still moving.
func animate(delta: float, now: float) -> bool:
	var moving := false
	if not is_equal_approx(hover, _hover_target):
		hover = move_toward(hover, _hover_target, delta * HOVER_SPEED)
		art.scale = Vector3.ONE * (1.0 + HOVER_SCALE * hover)
		moving = true
	if not _tilt.is_equal_approx(_tilt_target):
		_tilt = _tilt.lerp(_tilt_target, 1.0 - exp(-TILT_SPEED * delta))
		if _tilt.distance_to(_tilt_target) < 0.002:
			_tilt = _tilt_target
		art.rotation = Vector3(-_tilt.y * TILT, _tilt.x * TILT, 0.0)
		moving = true
	if appear < 1.0 and now >= _appear_at:
		appear = minf(1.0, appear + delta / APPEAR_SECONDS)
		moving = true
	if _develop >= 0.0 and _develop < 1.0:
		_develop = minf(1.0, _develop + delta / DEVELOP_SECONDS)
		moving = true
	if moving:
		_apply()
	return moving or appear < 1.0


## Visibility from the wall (band, edges, dimming); combined with appear.
func set_alpha(alpha: float) -> void:
	_alpha = alpha
	_apply()


## Ray test in the artwork's plane; returns the hit distance or -1.
func hit_distance(origin: Vector3, direction: Vector3) -> float:
	if not visible or _alpha * appear_eased() < 0.3 or is_placeholder():
		return -1.0
	var to_local := art.global_transform.affine_inverse()
	var o := to_local * origin
	var d := to_local.basis * direction
	if absf(d.z) < 1e-6:
		return -1.0
	var t := -o.z / d.z
	if t <= 0.0:
		return -1.0
	var p := o + d * t
	if absf(p.x) > SIZE.x / 2.0 or absf(p.y) > SIZE.y / 2.0:
		return -1.0
	return (art.global_transform * p - origin).length()


func _set_texture(loaded: Texture2D) -> void:
	if loaded:
		_art_material.set_shader_parameter("art", loaded)
		_art_material.set_shader_parameter("has_art", true)
		_cover(loaded.get_size())
		var ambient: Dictionary = _images.ambient(_art_url) if _images else {}
		if not ambient.is_empty():
			_set_light_source(ambient["grid"], ambient["color"])
		_develop = 0.0
		_apply()


## Crops the artwork to fill the tile without stretching (like
## STRETCH_KEEP_ASPECT_COVERED): thumbnails come in every shape.
func _cover(texture_size: Vector2) -> void:
	if texture_size.x <= 0 or texture_size.y <= 0:
		return
	var tile_aspect := SIZE.x / SIZE.y
	var texture_aspect := texture_size.x / texture_size.y
	var scale := Vector2.ONE
	if texture_aspect > tile_aspect:
		scale.x = tile_aspect / texture_aspect  # wider: crop the sides
	else:
		scale.y = texture_aspect / tile_aspect  # taller: crop top and bottom
	_art_material.set_shader_parameter("uv_scale", scale)
	_art_material.set_shader_parameter("uv_offset", (Vector2.ONE - scale) / 2.0)


func _apply() -> void:
	var alpha := _alpha * appear_eased()
	visible = alpha > 0.01
	var develop := ease(_develop, 0.5) if _develop >= 0.0 else 0.0
	var color := _base_color if _develop < 0.0 else UNDEVELOPED.lerp(Color.WHITE, develop)
	_art_material.set_shader_parameter("tint", Color(color, alpha))
	if _card_text:
		_card_text.modulate.a = alpha * (1.0 - develop)
	var light := _lit() * hover
	_light.visible = light > 0.002
	_light_material.set_shader_parameter("fade", light)
	_light_material.set_shader_parameter("strength", LIGHT_STRENGTH * light_level)
	var base: Color = item.get("title_color", UiTheme.MUTED)
	_title.modulate = Color(base.lerp(UiTheme.TEXT, hover), alpha)


func _set_light_source(grid: Texture2D, average: Color) -> void:
	_light_material.set_shader_parameter("ambient", grid)
	_light_color = Color(average, 1.0)


## 0..1: how far the tile is there to give off light (shown; artwork that
## is arriving dips while it develops).
func _lit() -> float:
	if _light_color == Color.BLACK or light_level <= 0.0:
		return 0.0
	var develop := ease(_develop, 0.5) if _develop >= 0.0 else 1.0
	return _alpha * appear_eased() * develop
