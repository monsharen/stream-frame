class_name PosterFactory
extends Node
## Renders artwork ("posters") for extensions and apps, like the app tiles
## on Apple TV: the service's logo on its own background colour, nothing
## else. Rendered once in an offscreen viewport and kept as a texture.
##
## Logos are the services' trademarks, so none ship with the app: each is
## fetched when first needed and cached on this device (like a browser's
## site icons). Without one (and for apps), the tile shows the name instead.
##
## Posters are addressed as poster://<id> and served through the
## ImageCache, so they fade in like any other artwork.

const SIZE := Vector2i(640, 360)
## The logo fits in this much of the tile (width, height), centred.
const LOGO_BOX := Vector2(0.62, 0.6)

## id -> {name, background, logo, logo_tint}
var _entries: Dictionary = {}
var _cache: Dictionary[String, Texture2D] = {}
## Fetches logos (set by the app).
var images: ImageCache


static func url_for(entry: Dictionary) -> String:
	return "poster://%s" % entry["id"]


## Registers what to draw for an id (called whenever the extensions change).
func describe(entry: Dictionary) -> void:
	_entries[entry["id"]] = {
		"name": entry["name"], "background": entry.get("poster", entry["color"]),
		"logo": entry.get("logo", ""), "logo_tint": entry.get("logo_tint", ""),
	}


## Resolves to a texture, or null (e.g. headless, where nothing renders).
func make(url: String) -> Texture2D:
	if _cache.has(url):
		return _cache[url]
	var parts := url.trim_prefix("poster://").split("/")
	var entry: Dictionary = _entries.get(parts[0], {})
	if entry.is_empty() or DisplayServer.get_name() == "headless":
		return null
	var logo: Texture2D = await _fetch_logo(entry["logo"])
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.transparent_bg = false
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.add_child(_layout(entry, logo))
	add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null or image.is_empty():
		return null
	var texture := ImageTexture.create_from_image(image)
	if images:
		images.set_ambient_from(url, image)  # its light (no read-back later)
	_cache[url] = texture
	return texture


func _fetch_logo(url: String) -> Texture2D:
	if url == "" or images == null:
		return null
	var result := [null, false]
	images.load_texture(url, func(texture: Texture2D) -> void:
		result[0] = texture
		result[1] = true)
	while not result[1]:
		await get_tree().process_frame
	return result[0]


func _layout(entry: Dictionary, logo: Texture2D) -> Control:
	var root := Control.new()
	root.size = SIZE
	var background := ColorRect.new()
	background.color = entry["background"]
	background.size = SIZE
	root.add_child(background)

	if logo:
		# Centred, as large as fits a calm margin.
		var box := Vector2(SIZE) * LOGO_BOX
		var mark := TextureRect.new()
		mark.texture = logo
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.position = (Vector2(SIZE) - box) / 2.0
		mark.size = box
		if entry["logo_tint"] == "white":
			mark.material = _whiten_material()
		root.add_child(mark)
	else:
		var name_label := Label.new()
		name_label.text = entry["name"]
		var on_light: bool = entry["background"].get_luminance() > 0.6
		name_label.add_theme_color_override("font_color", Color.BLACK if on_light else Color.WHITE)
		name_label.add_theme_font_size_override("font_size", _fit(entry["name"], SIZE.x * 0.8, 72, 36))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.size = SIZE
		root.add_child(name_label)

	return root


## The largest font size (from `largest` down to `smallest`) at which
## `text` fits in `width` pixels on one line.
static func _fit(text: String, width: float, largest: int, smallest: int) -> int:
	var font := ThemeDB.fallback_font
	for font_size in range(largest, smallest - 1, -2):
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
			return font_size
	return smallest


## Turns a dark, see-through logo white (keeping its shape), for dark posters.
static func _whiten_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	// COLOR is the texture times modulate here: keep its alpha, make it white.
	COLOR = vec4(1.0, 1.0, 1.0, COLOR.a);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

