class_name GlyphButton
extends Button
## A round icon button (play, pause, skip, close…), its icon drawn as
## shapes so it's crisp at any size and needs no icon font. The name is
## kept as the tooltip (and for tests).

const SIZE := 64.0

## play, pause, back10, forward10, more, close, back, refresh
## Dark translucent fill instead of the light one: for buttons over a film.
var dark := false
var glyph := "":
	set(value):
		glyph = value
		queue_redraw()


func _init(icon_glyph: String, label: String, on_pressed: Callable, diameter := SIZE) -> void:
	glyph = icon_glyph
	tooltip_text = label
	custom_minimum_size = Vector2(diameter, diameter)
	pressed.connect(on_pressed)


func _ready() -> void:
	# Theme styles are only known once in the tree; round them then.
	var radius := int(custom_minimum_size.x / 2.0)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := get_theme_stylebox(state).duplicate() as StyleBoxFlat
		if style:
			style.set_content_margin_all(0)
			style.set_corner_radius_all(radius)
			if dark and state != "pressed":
				style.bg_color = Color(0, 0, 0, 0.55 if state == "hover" else 0.4)
			add_theme_stylebox_override(state, style)


func _draw() -> void:
	var c := size / 2.0
	var s := minf(size.x, size.y) / SIZE  # 1 at the standard size
	var ink := UiTheme.MUTED if disabled else UiTheme.TEXT
	match glyph:
		"play":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -11) * s, c + Vector2(12, 0) * s, c + Vector2(-7, 11) * s]), ink)
		"pause":
			draw_rect(Rect2(c + Vector2(-9, -11) * s, Vector2(6, 22) * s), ink)
			draw_rect(Rect2(c + Vector2(3, -11) * s, Vector2(6, 22) * s), ink)
		"back10", "forward10":
			var forward := glyph == "forward10"
			var r := 15.0 * s
			# An open circle with an arrowhead at its top, and "10" inside.
			var from := -PI / 2.0 + (0.5 if forward else -0.5)
			var to := from + (TAU - 1.0) * (-1.0 if forward else 1.0)
			draw_arc(c, r, minf(from, to), maxf(from, to), 32, ink, 2.5 * s, true)
			var tip := c + Vector2(cos(from), sin(from)) * r
			var dir := 1.0 if forward else -1.0
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-5 * dir, -5) * s, tip + Vector2(3 * dir, 0) * s,
				tip + Vector2(-5 * dir, 5) * s]), ink)
			var font := get_theme_default_font()
			var font_size := int(12 * s)
			var text_size := font.get_string_size("10", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			draw_string(font, c + Vector2(-text_size.x / 2.0, text_size.y / 3.0), "10", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
		"more":
			for x in [-9.0, 0.0, 9.0]:
				draw_circle(c + Vector2(x, 0) * s, 2.6 * s, ink)
		"close":
			draw_line(c + Vector2(-8, -8) * s, c + Vector2(8, 8) * s, ink, 2.5 * s, true)
			draw_line(c + Vector2(8, -8) * s, c + Vector2(-8, 8) * s, ink, 2.5 * s, true)
		"back":
			draw_polyline(PackedVector2Array([c + Vector2(4, -10) * s, c + Vector2(-5, 0) * s, c + Vector2(4, 10) * s]), ink, 3.0 * s, true)
		"refresh":
			var r := 11.0 * s
			draw_arc(c, r, -PI * 0.35, PI * 1.45, 32, ink, 2.5 * s, true)
			var tip := c + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * r
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-6, -3) * s, tip + Vector2(3, -6) * s, tip + Vector2(2, 4) * s]), ink)
