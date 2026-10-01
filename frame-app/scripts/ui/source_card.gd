class_name SourceCard
extends Button
## An entry on the 2D home (an extension, or an app like Extensions): a
## coloured tile (its logo, once ready) with its name underneath. They all
## look the same: selecting one that isn't ready explains what's up and how
## to get started.

const ART_SIZE := Vector2(320, 180)

var source: Dictionary


func _init(source_entry: Dictionary, images: ImageCache = null) -> void:
	source = source_entry
	var available: bool = source["available"]
	set_meta("glow_color", tile_color(source))
	custom_minimum_size = Vector2(ART_SIZE.x, ART_SIZE.y + 48)
	for state in ["normal", "hover", "pressed"]:
		add_theme_stylebox_override(state, UiTheme.box(UiTheme.PANEL, UiTheme.BORDER, 2, 0))

	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)

	var art := ColorRect.new()
	art.custom_minimum_size = ART_SIZE
	art.color = tile_color(source)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := UiTheme.label(source["name"], 40, UiTheme.TEXT if available else UiTheme.MUTED)
	name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	art.add_child(name_label)
	# The generated poster covers the colour and name once it's ready.
	var poster := TextureRect.new()
	poster.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	poster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	poster.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	poster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(poster)
	if images and source.get("image", "") != "":
		images.load_into(source["image"], poster)
	layout.add_child(art)

	var caption := UiTheme.label(source["name"], 20)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(caption)


## The tile colour: the extension's own (shared with the wall).
static func tile_color(source_entry: Dictionary) -> Color:
	return source_entry["color"]
