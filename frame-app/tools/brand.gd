extends Node
## Draws the Stream Frame brand images with the app's own type: the boot
## splash (the night sky, a softly glowing curved screen, the wordmark) and
## the app icon (the screen alone). Needs a display:
##   godot --display-driver x11 --path . res://tools/brand.tscn
## Writes res://assets/brand/splash.png and icon.png.

const SPLASH_SIZE := Vector2i(1920, 1080)
const ICON_SIZE := Vector2i(512, 512)
## The night sky's colours (shaders/night_sky.gdshader) and the screen's.
const SKY_TOP := Color("020307")
const SKY_HORIZON := Color("0b0f19")
const SCREEN_TOP := Color("3b5bdb")
const SCREEN_BOTTOM := Color("1b1f5e")
const GLOW := Color("5b7cfa")


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/brand")
	await _render(_splash(), SPLASH_SIZE, "res://assets/brand/splash.png")
	await _render(_icon(), ICON_SIZE, "res://assets/brand/icon.png")
	print("brand images written")
	get_tree().quit()


func _render(content: Control, size: Vector2i, path: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.add_child(content)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(path)
	viewport.queue_free()


func _splash() -> Control:
	var root := Control.new()
	root.size = SPLASH_SIZE
	root.add_child(_sky(Vector2(SPLASH_SIZE)))
	var centre := Vector2(SPLASH_SIZE.x / 2.0, SPLASH_SIZE.y * 0.42)
	root.add_child(_screen(centre, 560.0))
	var title := Label.new()
	title.text = "Stream Frame"
	title.add_theme_font_size_override("font_size", 76)
	title.add_theme_color_override("font_color", Color("eceef2"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(SPLASH_SIZE.x, 120)
	title.position = Vector2(0, SPLASH_SIZE.y * 0.66)
	root.add_child(title)
	return root


func _icon() -> Control:
	var root := Control.new()
	root.size = ICON_SIZE
	var tile := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = SKY_HORIZON
	style.set_corner_radius_all(110)
	tile.add_theme_stylebox_override("panel", style)
	tile.size = ICON_SIZE
	tile.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	tile.add_child(_sky(Vector2(ICON_SIZE)))
	tile.add_child(_screen(Vector2(ICON_SIZE) / 2.0, 360.0))
	root.add_child(tile)
	return root


## A dark gradient with a scattering of stars.
func _sky(size: Vector2) -> Control:
	var sky := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, SKY_TOP)
	gradient.set_color(1, SKY_HORIZON)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	sky.texture = texture
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.size = size
	var stars := _Stars.new()
	stars.size = size
	sky.add_child(stars)
	return sky


## The curved screen, as seen from its centre (taller at the sides), with
## its glow around it and below.
func _screen(centre: Vector2, width: float) -> Control:
	var holder := Control.new()
	var glow := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(GLOW, 0.45))
	gradient.set_color(1, Color(GLOW, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	glow.texture = texture
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.size = Vector2(width * 1.9, width * 1.15)
	glow.position = centre - glow.size / 2.0
	holder.add_child(glow)

	var screen := _Screen.new()
	screen.centre = centre
	screen.width = width
	holder.add_child(screen)
	return holder


## The screen in thin vertical slices, so its gradient runs cleanly top to
## bottom, with a faint reflection below as on the app's polished floor.
class _Screen:
	extends Control

	var centre := Vector2.ZERO
	var width := 400.0

	func _draw() -> void:
		var height := width * 0.5
		var sag := height * 0.09
		var steps := 64
		for i in steps:
			var u0 := float(i) / steps * 2.0 - 1.0
			var u1 := float(i + 1) / steps * 2.0 - 1.0
			var x0 := centre.x + u0 * width / 2.0
			var x1 := centre.x + u1 * width / 2.0
			var t0 := centre.y - height / 2.0 + sag * (1.0 - u0 * u0)
			var t1 := centre.y - height / 2.0 + sag * (1.0 - u1 * u1)
			var b0 := centre.y + height / 2.0 - sag * (1.0 - u0 * u0)
			var b1 := centre.y + height / 2.0 - sag * (1.0 - u1 * u1)
			# A soft sheen across the middle.
			var light := 0.18 * (1.0 - absf((u0 + u1) / 2.0))
			var top := SCREEN_TOP.lightened(light)
			draw_polygon(PackedVector2Array([Vector2(x0, t0), Vector2(x1, t1), Vector2(x1, b1), Vector2(x0, b0)]),
				PackedColorArray([top, top, SCREEN_BOTTOM, SCREEN_BOTTOM]))
			# The reflection: the bottom of the screen, mirrored and fading.
			var depth := height * 0.35
			var fade := Color(SCREEN_BOTTOM.lightened(light), 0.35)
			draw_polygon(PackedVector2Array([Vector2(x0, b0 + 6), Vector2(x1, b1 + 6), Vector2(x1, b1 + 6 + depth), Vector2(x0, b0 + 6 + depth)]),
				PackedColorArray([fade, fade, Color(fade, 0.0), Color(fade, 0.0)]))


class _Stars:
	extends Control

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var count := int(size.x * size.y / 9000.0)
		for i in count:
			var p := Vector2(rng.randf() * size.x, pow(rng.randf(), 1.4) * size.y * 0.9)
			var brightness := pow(rng.randf(), 3.0) * 0.8 + 0.15
			draw_circle(p, 0.8 + brightness * 1.4, Color(0.85, 0.9, 1.0, brightness))
