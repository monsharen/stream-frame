class_name UiTheme
## Colors and the app-wide Theme. Sizes are generous: this is read at a
## distance in a headset and navigated with controllers, so focus must be
## obvious.

const BG := Color("0e0f12")
const PANEL := Color("181a20")
const BORDER := Color("2a2d36")
const TEXT := Color("eceef2")
const MUTED := Color("8a8f9c")
const ACCENT := Color("e5a50a")
const ERROR := Color("ff6b6b")

const FONT_SIZE := 24


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE

	theme.set_color("font_color", "Label", TEXT)
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		theme.set_color(state, "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", BG)
	theme.set_color("font_disabled_color", "Button", MUTED)

	theme.set_stylebox("normal", "Button", box(PANEL, BORDER, 2))
	theme.set_stylebox("hover", "Button", box(PANEL.lightened(0.06), MUTED, 2))
	theme.set_stylebox("pressed", "Button", box(ACCENT, ACCENT, 2))
	theme.set_stylebox("disabled", "Button", box(PANEL, PANEL, 2))
	theme.set_stylebox("focus", "Button", box(Color.TRANSPARENT, ACCENT, 4))

	theme.set_stylebox("normal", "LineEdit", box(PANEL, BORDER, 2))
	theme.set_stylebox("focus", "LineEdit", box(Color.TRANSPARENT, ACCENT, 3))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)

	theme.set_stylebox("panel", "PanelContainer", box(PANEL, BORDER, 1, 16))

	theme.set_stylebox("slider", "HSlider", box(BORDER, BORDER, 0, 4, 6))
	theme.set_stylebox("grabber_area", "HSlider", box(ACCENT, ACCENT, 0, 4, 6))
	theme.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, ACCENT, 0, 4, 6))
	return theme


static func box(fill: Color, border: Color, border_width: int, padding := 12, height := -1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(padding)
	if height > 0:
		style.content_margin_top = height / 2.0
		style.content_margin_bottom = height / 2.0
	return style


static func label(text: String, size := FONT_SIZE, color := TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node


static func button(text: String, on_pressed: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.pressed.connect(on_pressed)
	return node
