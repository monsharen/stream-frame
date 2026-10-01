class_name BrowseView
extends MarginContainer
## The sources home (what you can watch, on this device or from your PC) and,
## inside a source, its catalog rows of posters.
##
## Loading states: a spinner + message line, skeleton rows while a catalog
## loads from scratch (refreshes keep the current rows visible), and errors
## with a Retry button.

signal source_chosen(source: Dictionary)
signal home_requested
signal refresh_requested
signal extensions_requested
## "What's wrong?" on a loading error: explain the current source's state.
signal help_requested
signal retry_requested
signal item_chosen(item: Dictionary)
## Mirrors of what's shown, for the 3D wall.
signal sources_shown(sources: Array)
signal loading_started(keep_content: bool)
signal catalog_shown(catalog: Dictionary)
signal load_failed

## Height of the header (title bar + status line) in pixels; in wall mode this
## strip is all that's shown of the 2D browse view.
const HEADER_HEIGHT := 170

## Skeletons appear only if loading takes longer than this, so fast (cached)
## loads don't flash.
const SKELETON_DELAY := 0.15
## Home rows: [title, entry kind].
const HOME_GROUPS := [["On this device", "local"], ["From your PC", "remote"], ["Apps", "app"]]
const SKELETON_ROWS := 2
const SKELETON_CARDS := 6

var _images: ImageCache
var _home := UiTheme.button("←  Sources", home_requested.emit)
var _title := UiTheme.label("Stream Frame", 32)
var _rows := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _status := HBoxContainer.new()
var _spinner := Spinner.new(28)
var _message := UiTheme.label("", 26, UiTheme.MUTED)
var _retry := UiTheme.button("Retry", retry_requested.emit)
var _help := UiTheme.button("What's wrong?", help_requested.emit)
var _refresh := UiTheme.button("Refresh", refresh_requested.emit)
var _note := UiTheme.label("", 20, UiTheme.MUTED)
var _skeleton := VBoxContainer.new()
var _skeleton_timer := Timer.new()
var _skeleton_pulse: Tween
## The 3D shell draws the rows as a wall; only the header is 2D.
var _wall_mode := false


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
	top_bar.add_child(_home)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_bar.add_child(_title)
	_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_bar.add_child(_note)
	top_bar.add_child(_refresh)
	top_bar.add_child(UiTheme.button("Extensions", extensions_requested.emit))

	_status.add_theme_constant_override("separation", 14)
	_status.visible = false
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status.add_child(_spinner)
	_status.add_child(_message)
	_status.add_child(_help)
	_status.add_child(_retry)
	layout.add_child(_status)

	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	layout.add_child(_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(content)
	_rows.add_theme_constant_override("separation", 28)
	content.add_child(_rows)
	_build_skeleton()
	content.add_child(_skeleton)

	_skeleton_timer.one_shot = true
	_skeleton_timer.wait_time = SKELETON_DELAY
	_skeleton_timer.timeout.connect(_show_skeleton)
	add_child(_skeleton_timer)


## The home: the enabled extensions grouped by where they play, then apps
## (Extensions). Unavailable ones are greyed out but still selectable (they
## explain what's up and how to get started).
func show_sources(sources: Array) -> void:
	_title.text = "Stream Frame"
	_home.visible = false
	_refresh.visible = false
	_hide_skeleton()
	_clear_rows()
	_status.visible = false
	sources_shown.emit(sources)
	if _wall_mode:
		return
	var first: Control = null
	for group in HOME_GROUPS:
		var entries := sources.filter(func(s: Dictionary) -> bool: return s["kind"] == group[1])
		if entries.is_empty():
			continue
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 10)
		section.add_child(UiTheme.label(group[0], 26))
		var strip := HBoxContainer.new()
		strip.add_theme_constant_override("separation", 14)
		for source in entries:
			var card := SourceCard.new(source)
			card.pressed.connect(source_chosen.emit.bind(source))
			strip.add_child(card)
			if first == null:
				first = card
		section.add_child(strip)
		_rows.add_child(section)
	if first and is_visible_in_tree():
		first.grab_focus.call_deferred()


## Header for browsing inside one source.
func enter_source(source_name: String) -> void:
	_title.text = source_name
	_home.visible = true
	_refresh.visible = true


func set_wall_mode(on: bool) -> void:
	_wall_mode = on
	_scroll.visible = not on
	if on:
		_hide_skeleton()


## Small label in the top bar: connection problems, or "Offline demo".
func set_note(text: String, is_error := false) -> void:
	_note.text = text
	_note.add_theme_color_override("font_color", UiTheme.ERROR if is_error else UiTheme.MUTED)


## keep_content: leave the current rows up (a refresh) instead of replacing
## them with skeletons (a first load, or switching service).
func show_loading(text: String, keep_content := false) -> void:
	_set_status(text, true, false, UiTheme.MUTED)
	_refresh.disabled = true
	loading_started.emit(keep_content)
	if not keep_content and not _wall_mode:
		_clear_rows()
		# Already waiting (e.g. connecting, then loading the catalog): keep
		# the running delay or the visible skeleton rather than restarting.
		if not _skeleton.visible and _skeleton_timer.is_stopped():
			_skeleton_timer.start()


## help: offer "What's wrong?" (an explanation of the source's state).
func show_error(text: String, help := false) -> void:
	_set_status(text, false, true, UiTheme.ERROR)
	_help.visible = help
	_refresh.disabled = false
	_hide_skeleton()
	load_failed.emit()
	if is_visible_in_tree():
		_retry.grab_focus.call_deferred()


func show_catalog(catalog: Dictionary) -> void:
	_hide_skeleton()
	_clear_rows()
	_refresh.disabled = false
	var rows: Array = catalog.get("rows", [])
	if rows.is_empty():
		_set_status("Nothing here yet. Try Refresh.", false, false, UiTheme.MUTED)
	else:
		_status.visible = false
	catalog_shown.emit(catalog)
	if _wall_mode:
		return
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


func is_loading() -> bool:
	return _status.visible and _spinner.visible


func focus_content() -> void:
	var cards := find_children("*", "PosterCard", true, false) + find_children("*", "SourceCard", true, false)
	if not cards.is_empty():
		(cards[0] as Control).grab_focus()
	elif _retry.is_visible_in_tree():
		_retry.grab_focus()
	elif _home.visible:
		_home.grab_focus()


func _set_status(text: String, spinning: bool, retry: bool, color: Color) -> void:
	_status.visible = true
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_spinner.visible = spinning
	_retry.visible = retry
	_help.visible = false


func _clear_rows() -> void:
	# Detach now, free later: old cards must not linger in the tree (focus
	# and lookups would find them) until the end of the frame.
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()


func _build_skeleton() -> void:
	_skeleton.visible = false
	_skeleton.add_theme_constant_override("separation", 28)
	_skeleton.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for _row in SKELETON_ROWS:
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 10)
		var heading := _placeholder(Vector2(260, 30))
		heading.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		section.add_child(heading)
		var strip := HBoxContainer.new()
		strip.add_theme_constant_override("separation", 14)
		for _card in SKELETON_CARDS:
			strip.add_child(_placeholder(Vector2(PosterCard.ART_SIZE.x, PosterCard.ART_SIZE.y + 48)))
		# A plain Control doesn't take its child's minimum size, so the strip
		# is clipped at the screen edge instead of widening the whole layout.
		var clip := Control.new()
		clip.clip_contents = true
		clip.custom_minimum_size.y = PosterCard.ART_SIZE.y + 48
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(strip)
		section.add_child(clip)
		_skeleton.add_child(section)


func _show_skeleton() -> void:
	_skeleton.visible = true
	_skeleton.modulate.a = 1.0
	# One tween pulses the whole skeleton block.
	_skeleton_pulse = create_tween().set_loops()
	_skeleton_pulse.tween_property(_skeleton, "modulate:a", 0.45, 0.7).set_trans(Tween.TRANS_SINE)
	_skeleton_pulse.tween_property(_skeleton, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)


func _hide_skeleton() -> void:
	_skeleton_timer.stop()
	_skeleton.visible = false
	if _skeleton_pulse:
		_skeleton_pulse.kill()
		_skeleton_pulse = null


static func _placeholder(min_size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = min_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL, UiTheme.PANEL, 0, 0))
	return panel
