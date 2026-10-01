class_name SourceCard
extends Button
## An entry on the 2D home (an extension, or an app like Extensions): a
## coloured tile with its name, and its status underneath. Unavailable ones
## are greyed out but stay selectable, since selecting one explains what's
## up and how to get started; problems are shown in red.

const ART_SIZE := Vector2(320, 180)

var source: Dictionary


func _init(source_entry: Dictionary) -> void:
	source = source_entry
	var available: bool = source["available"]
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
	layout.add_child(art)

	var status := UiTheme.label(source["status"], 20, status_color(source))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(status)


static func status_color(source_entry: Dictionary) -> Color:
	if source_entry.get("problem", false):
		return UiTheme.ERROR
	return UiTheme.TEXT if source_entry["available"] else UiTheme.MUTED


## The tile colour: the source's own, or a dark grey with just a hint of it
## when unavailable, so "greyed out" reads at a glance. Shared with the wall.
static func tile_color(source_entry: Dictionary) -> Color:
	var color: Color = source_entry["color"]
	if source_entry["available"]:
		return color
	var grey := color.get_luminance()
	return Color(grey, grey, grey).lerp(color, 0.15).lerp(UiTheme.PANEL, 0.6)
