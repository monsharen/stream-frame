class_name WallTile
extends Node3D
## One tile on the movie wall: a poster (artwork quad) or a source (a
## coloured card with the source's name), an accent glow behind it for hover,
## and a title underneath. The wall positions it; the tile animates
## its own hover lift.

const SIZE := Vector2(0.56, 0.315)
const HOVER_LIFT := 0.14
const HOVER_SCALE := 0.08
const HOVER_SPEED := 8.0
const TITLE_MAX_CHARS := 30

## Empty for loading placeholders.
var item: Dictionary
var art := MeshInstance3D.new()
## 0..1, animated towards the hover target; the wall reads it for the lift.
var hover := 0.0

var _art_material := StandardMaterial3D.new()
var _glow_material := StandardMaterial3D.new()
var _title := Label3D.new()
var _hover_target := 0.0
var _alpha := 1.0
var _image_url := ""


func _init(catalog_item: Dictionary = {}) -> void:
	item = catalog_item
	_image_url = item.get("image", "")

	var quad := QuadMesh.new()
	quad.size = SIZE
	art.mesh = quad
	_art_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_art_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_art_material.albedo_color = item.get("art_color", UiTheme.BORDER)  # placeholder until artwork arrives
	art.material_override = _art_material
	add_child(art)

	if item.has("art_text"):
		var card_text := Label3D.new()
		card_text.text = item["art_text"]
		# As large as fits the card (roughly 0.55 em per character).
		var fit := int(SIZE.x / 0.001 * 0.9 / (0.55 * maxi(1, item["art_text"].length())))
		card_text.font_size = clampi(fit, 32, 72)
		card_text.pixel_size = 0.001
		card_text.position.z = 0.002
		card_text.modulate = UiTheme.MUTED if item.get("dimmed", false) else UiTheme.TEXT
		art.add_child(card_text)

	# An accent frame just behind the artwork; a child of it, so it grows
	# with the hover scale instead of being covered.
	var glow := MeshInstance3D.new()
	var glow_mesh := QuadMesh.new()
	glow_mesh.size = SIZE + Vector2(0.05, 0.05)
	glow.mesh = glow_mesh
	glow.position.z = -0.004
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_material.albedo_color = Color(UiTheme.ACCENT, 0.0)
	glow.material_override = _glow_material
	art.add_child(glow)

	var text: String = item.get("title", "")
	if text.length() > TITLE_MAX_CHARS:
		text = text.left(TITLE_MAX_CHARS - 1) + "…"
	_title.text = text
	# Source cards have a short status line; make it readable from afar.
	_title.font_size = 46 if item.get("kind") == "source" else 36
	_title.pixel_size = 0.001
	_title.position.y = -SIZE.y / 2.0 - 0.035
	_title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_title.modulate = UiTheme.MUTED
	_title.outline_size = 0
	add_child(_title)


func is_placeholder() -> bool:
	return item.is_empty()


func texture() -> Texture2D:
	return _art_material.albedo_texture


## Fetches the artwork the first time the tile becomes visible.
func ensure_texture(images: ImageCache) -> void:
	if _image_url == "":
		return
	var url := _image_url
	_image_url = ""
	images.load_texture(url, _set_texture)


func set_hovered(hovered: bool) -> void:
	_hover_target = 1.0 if hovered else 0.0


## Returns true while the hover animation is still moving.
func animate(delta: float) -> bool:
	if is_equal_approx(hover, _hover_target):
		return false
	hover = move_toward(hover, _hover_target, delta * HOVER_SPEED)
	art.scale = Vector3.ONE * (1.0 + HOVER_SCALE * hover)
	_apply_alpha()
	return true


func set_alpha(alpha: float) -> void:
	_alpha = alpha
	visible = alpha > 0.01
	_apply_alpha()


## Ray test in the artwork's plane; returns the hit distance or -1.
func hit_distance(origin: Vector3, direction: Vector3) -> float:
	if not visible or _alpha < 0.3 or is_placeholder():
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


func _set_texture(loaded: Texture2D) -> void:  # posters only; source cards have no image
	if loaded:
		_art_material.albedo_texture = loaded
		_art_material.albedo_color = Color(1, 1, 1, _alpha)


func _apply_alpha() -> void:
	_art_material.albedo_color.a = _alpha
	_glow_material.albedo_color.a = 0.9 * hover * _alpha
	var base: Color = item.get("title_color", UiTheme.MUTED)
	var title_color := base.lerp(UiTheme.TEXT, hover * 0.6)
	_title.modulate = Color(title_color, _alpha)
