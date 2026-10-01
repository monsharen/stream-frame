class_name PosterCard
extends Button
## A focusable catalog tile: 16:9 artwork with the title underneath.

const ART_SIZE := Vector2(320, 180)

var item: Dictionary


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

	var art := TextureRect.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_frame.add_child(art)
	images.load_into(item.get("image", ""), art)

	var title := UiTheme.label(item.get("title", ""), 20)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size = Vector2(ART_SIZE.x - 16, 0)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title.size_flags_vertical = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(title)
