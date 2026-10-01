class_name PosterCard
extends Button
## A focusable catalog tile: 16:9 artwork with the title underneath. Its
## focus glow takes the artwork's colours (see FocusHighlight).

const ART_SIZE := Vector2(320, 180)

var item: Dictionary
var _images: ImageCache


func _init(catalog_item: Dictionary, images: ImageCache) -> void:
	item = catalog_item
	custom_minimum_size = Vector2(ART_SIZE.x, ART_SIZE.y + 48)
	tooltip_text = item.get("title", "")
	for state in ["normal", "hover", "pressed"]:
		add_theme_stylebox_override(state, UiTheme.box(UiTheme.PANEL, UiTheme.BORDER, 2, 0))

	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)

	var art_frame := Control.new()
	art_frame.custom_minimum_size = ART_SIZE
	art_frame.clip_contents = true
	art_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(art_frame)

	# Shows until the artwork arrives (or if it never does).
	var placeholder := ColorRect.new()
	placeholder.color = UiTheme.BORDER
	placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_frame.add_child(placeholder)

	var art := TextureRect.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_frame.add_child(art)
	images.load_into(item.get("image", ""), art)
	_images = images
	images.load_texture(item.get("image", ""), _on_art)

	var title := UiTheme.label(item.get("display_title", item.get("title", "")), 20)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size = Vector2(ART_SIZE.x - 16, 0)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title.size_flags_vertical = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_color_override("font_color", UiTheme.MUTED)
	set_meta("focus_label", title)
	layout.add_child(title)


func _on_art(_texture: Texture2D) -> void:
	var ambient: Dictionary = _images.ambient(item.get("image", ""))
	if not ambient.is_empty():
		FocusHighlight.set_color(self, ambient["color"])
