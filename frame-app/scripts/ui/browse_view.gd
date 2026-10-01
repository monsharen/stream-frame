class_name BrowseView
extends MarginContainer
## Service tabs across the top, catalog rows of posters below.

signal service_selected(service_id: String)
signal refresh_requested
signal settings_requested
signal item_chosen(item: Dictionary)

var _images: ImageCache
var _tabs := HBoxContainer.new()
var _rows := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _message := UiTheme.label("", 26, UiTheme.MUTED)
var _connection := UiTheme.label("", 20, UiTheme.MUTED)


func _init(images: ImageCache) -> void:
	_images = images
	for side in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + side, 32)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 24)
	add_child(layout)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 12)
	layout.add_child(top_bar)
	_tabs.add_theme_constant_override("separation", 12)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(_tabs)
	top_bar.add_child(_connection)
	top_bar.add_child(UiTheme.button("Refresh", refresh_requested.emit))
	top_bar.add_child(UiTheme.button("Settings", settings_requested.emit))

	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_message)

	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	layout.add_child(_scroll)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 28)
	_scroll.add_child(_rows)


func set_services(services: Array) -> void:
	for child in _tabs.get_children():
		child.queue_free()
	for service in services:
		var tab := UiTheme.button(service["name"], service_selected.emit.bind(service["id"]))
		tab.toggle_mode = true
		tab.set_meta("service_id", service["id"])
		_tabs.add_child(tab)


func set_active_service(service_id: String) -> void:
	for tab in _tabs.get_children():
		tab.set_pressed_no_signal(tab.get_meta("service_id") == service_id)


func set_connected(connected: bool) -> void:
	_connection.text = "" if connected else "Host offline"
	_connection.add_theme_color_override("font_color", UiTheme.ERROR)


func show_message(text: String, is_error := false) -> void:
	_message.text = text
	_message.visible = text != ""
	_message.add_theme_color_override("font_color", UiTheme.ERROR if is_error else UiTheme.MUTED)


func show_catalog(catalog: Dictionary) -> void:
	for child in _rows.get_children():
		child.queue_free()
	var rows: Array = catalog.get("rows", [])
	show_message("" if not rows.is_empty() else "Nothing here yet. Try Refresh.")
	var first_card: PosterCard = null
	for row in rows:
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 10)
		section.add_child(UiTheme.label(row["title"], 26))
		var strip_scroll := ScrollContainer.new()
		strip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		strip_scroll.follow_focus = true
		strip_scroll.custom_minimum_size.y = PosterCard.ART_SIZE.y + 64
		var strip := HBoxContainer.new()
		strip.add_theme_constant_override("separation", 14)
		strip_scroll.add_child(strip)
		for item in row["items"]:
			var card := PosterCard.new(item, _images)
			card.pressed.connect(item_chosen.emit.bind(item))
			strip.add_child(card)
			if first_card == null:
				first_card = card
		section.add_child(strip_scroll)
		_rows.add_child(section)
	if first_card and is_visible_in_tree():
		first_card.grab_focus.call_deferred()


func focus_content() -> void:
	var cards := find_children("*", "PosterCard", true, false)
	if not cards.is_empty():
		(cards[0] as Control).grab_focus()
	elif _tabs.get_child_count() > 0:
		(_tabs.get_child(0) as Control).grab_focus()
