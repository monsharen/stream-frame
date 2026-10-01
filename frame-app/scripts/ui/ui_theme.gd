class_name UiTheme
## Colors and the app-wide Theme. Sizes are generous: this is read at a
## distance in a headset and navigated with controllers, so focus must be
## obvious. The look is calm and Apple-like: borderless, translucent,
## rounded controls; focus is shown by FocusHighlight, not frames.

const BG := Color("0e0f12")
const PANEL := Color("181a20")
const BORDER := Color("2a2d36")
const TEXT := Color("eceef2")
const MUTED := Color("8a8f9c")
const ACCENT := Color("e5a50a")
const ERROR := Color("ff6b6b")
## Translucent fills for controls, so they sit lightly on whatever is
## behind them (the room, a film).
const FILL := Color(1, 1, 1, 0.09)
const FILL_HOVER := Color(1, 1, 1, 0.16)
const FILL_PRESSED := Color(1, 1, 1, 0.85)
const RADIUS := 16

const FONT_SIZE := 24


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE

	theme.set_color("font_color", "Label", TEXT)
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		theme.set_color(state, "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", BG)
	theme.set_color("font_disabled_color", "Button", MUTED)
	for type in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, box(FILL, FILL, 0, 14))
		theme.set_stylebox("hover", type, box(FILL_HOVER, FILL_HOVER, 0, 14))
		theme.set_stylebox("pressed", type, box(FILL_PRESSED, FILL_PRESSED, 0, 14))
		theme.set_stylebox("disabled", type, box(Color(1, 1, 1, 0.04), Color.TRANSPARENT, 0, 14))
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(state, "OptionButton", TEXT)
	theme.set_color("font_pressed_color", "OptionButton", BG)
	theme.set_stylebox("panel", "PopupMenu", box(PANEL, PANEL, 0, 10))
	theme.set_stylebox("hover", "PopupMenu", box(FILL_HOVER, FILL_HOVER, 0, 8))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", TEXT)
	# Focus is shown by FocusHighlight (lift and glow), not a frame.
	for type in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		theme.set_stylebox("focus", type, StyleBoxEmpty.new())

	theme.set_stylebox("normal", "LineEdit", box(FILL, FILL, 0, 14))
	theme.set_stylebox("focus", "LineEdit", box(Color(1, 1, 1, 0.06), Color.TRANSPARENT, 0, 14))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)

	theme.set_stylebox("panel", "PanelContainer", box(PANEL, PANEL, 0, 16))

	# The scrubber: a thin white line on a faint track.
	theme.set_stylebox("slider", "HSlider", box(Color(1, 1, 1, 0.22), Color.TRANSPARENT, 0, 3, 6))
	theme.set_stylebox("grabber_area", "HSlider", box(TEXT, TEXT, 0, 3, 6))
	theme.set_stylebox("grabber_area_highlight", "HSlider", box(TEXT, TEXT, 0, 3, 6))
	return theme


static func box(fill: Color, border: Color, border_width: int, padding := 12, height := -1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(RADIUS)
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


## The back control, the same everywhere: a round chevron at the start of
## the view's top bar. It does exactly what the Back action does.
static func back_button(on_pressed: Callable) -> GlyphButton:
	return GlyphButton.new("back", "Back", on_pressed, 56)


static func button(text: String, on_pressed: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.pressed.connect(on_pressed)
	return node
