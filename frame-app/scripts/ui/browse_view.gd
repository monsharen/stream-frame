class_name BrowseView
extends MarginContainer
## The sources home (what you can watch, on this device or from your PC) and,
## inside a source, its catalog rows of posters.
##
## Loading states: a spinner + message line, skeleton rows while a catalog
## loads from scratch (refreshes keep the current rows visible), and errors
## with a Retry button.

signal source_chosen(source: Dictionary)
signal back_requested
signal refresh_requested
## "What's wrong?" on a loading error: explain the current source's state.
signal help_requested
signal search_requested(query: String)
signal search_cleared
## Sort or length filter changed.
signal arrange_changed
## A catalog row was scrolled near its end (2D; the wall has its own).
signal row_end_reached(row_index: int)
## Titles were added to a row (for the 3D wall to follow).
signal items_appended(row_index: int, items: Array)

const SORT_LABELS := ["Default order", "Title A–Z", "Newest first", "Oldest first", "Shortest first", "Longest first"]
const LENGTH_LABELS := ["Any length", "Under 10 min", "10–60 min", "Over an hour"]
signal retry_requested
signal item_chosen(item: Dictionary)
## Mirrors of what's shown, for the 3D wall.
signal sources_shown(sources: Array, continue_items: Array)
signal loading_started(keep_content: bool)
signal catalog_shown(catalog: Dictionary)
signal load_failed

## Height of the header (title bar + status line) in pixels; in wall mode this
## strip is all that's shown of the 2D browse view.
const HEADER_HEIGHT := 170

## Skeletons appear only if loading takes longer than this, so fast (cached)
## loads don't flash.
const SKELETON_DELAY := 0.15
## The home is a grid of extensions: where one plays (here or from the PC) is
## its own business, not something to sort by.
const SKELETON_ROWS := 2
const SKELETON_CARDS := 6

var _images: ImageCache
var _home := UiTheme.back_button(func() -> void: back_requested.emit())
var _title := UiTheme.label("", 30)
var _rows := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _status := HBoxContainer.new()
var _spinner := Spinner.new(28)
var _message := UiTheme.label("", 26, UiTheme.MUTED)
var _retry := UiTheme.button("Retry", retry_requested.emit)
var _help := UiTheme.button("What's wrong?", help_requested.emit)
var _refresh := GlyphButton.new("refresh", "Refresh", refresh_requested.emit, 56)
var _tools := HBoxContainer.new()
var _search := LineEdit.new()
var _clear_search := GlyphButton.new("close", "Back to the full catalog", func() -> void:
	_search.text = ""
	_clear_search.visible = false
	search_cleared.emit(), 48)
var _sort := OptionButton.new()
var _length := OptionButton.new()
var _paged_rows := {}
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
	# Search / sort / filter, inside a source.
	_tools.add_theme_constant_override("separation", 10)
	_search.placeholder_text = "Search"
	_search.custom_minimum_size.x = 340
	_search.text_submitted.connect(func(text: String) -> void:
		if text.strip_edges() != "":
			_clear_search.visible = true
			search_requested.emit(text.strip_edges()))
	_tools.add_child(_search)
	_clear_search.visible = false
	_tools.add_child(_clear_search)
	for label in SORT_LABELS:
		_sort.add_item(label)
	for label in LENGTH_LABELS:
		_length.add_item(label)
	_sort.item_selected.connect(func(_i: int) -> void: arrange_changed.emit())
	_length.item_selected.connect(func(_i: int) -> void: arrange_changed.emit())
	_tools.add_child(_sort)
	_tools.add_child(_length)
	_tools.visible = false
	top_bar.add_child(_tools)
	top_bar.add_child(_refresh)

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


## The home: the enabled extensions, six to a row (see home_order), then
## Continue watching. Ones that aren't ready look the same; selecting one
## explains what's up and how to get started.
func show_sources(sources: Array, continue_items: Array = []) -> void:
	_title.text = ""
	_home.visible = false
	_refresh.visible = false
	_tools.visible = false
	_hide_skeleton()
	_clear_rows()
	_status.visible = false
	sources_shown.emit(sources, continue_items)
	if _wall_mode:
		return
	var first: Control = null
	var strip := GridContainer.new()
	strip.columns = MovieWall.HOME_PER_ROW
	strip.add_theme_constant_override("h_separation", 14)
	strip.add_theme_constant_override("v_separation", 14)
	for source in home_order(sources):
		var card := SourceCard.new(source, _images)
		card.pressed.connect(source_chosen.emit.bind(source))
		strip.add_child(card)
		if first == null:
			first = card
	_rows.add_child(strip)
	if not continue_items.is_empty():
		var resume_section := VBoxContainer.new()
		resume_section.add_theme_constant_override("separation", 10)
		resume_section.add_child(UiTheme.label("Continue watching", 26))
		var resume_strip := HBoxContainer.new()
		resume_strip.add_theme_constant_override("separation", 14)
		for item in continue_items:
			var card := PosterCard.new(item, _images)
			card.pressed.connect(item_chosen.emit.bind(item))
			resume_strip.add_child(card)
		resume_section.add_child(resume_strip)
		_rows.add_child(resume_section)
	_stagger_in()
	if first and is_visible_in_tree():
		_focus_soon(first)


## Back (InputActions): leave search results for the full catalog first.
## True if that's what Back did here.
func handle_back() -> bool:
	if _clear_search.visible:
		_clear_search.pressed.emit()
		return true
	return false


## The home's order: ready extensions first, then ones that need setting up,
## then apps (Extensions); otherwise as listed.
static func home_order(sources: Array) -> Array:
	var rank := func(s: Dictionary) -> int:
		return 2 if s["kind"] == "app" else (0 if s["available"] else 1)
	var ordered := []
	for wanted in 3:
		ordered.append_array(sources.filter(func(s: Dictionary) -> bool: return rank.call(s) == wanted))
	return ordered


## Header for browsing inside one source.
func enter_source(source_name: String, searchable := true) -> void:
	_title.text = source_name
	_home.visible = true
	_refresh.visible = true
	_tools.visible = true
	_search.visible = searchable
	_search.text = ""
	_search.placeholder_text = "Search %s…" % source_name
	_clear_search.visible = false
	_sort.select(0)
	_length.select(0)


## Which sorts and filters make sense for the titles at hand.
func set_arrange_options(has_years: bool, has_durations: bool) -> void:
	_sort.set_item_disabled(2, not has_years)
	_sort.set_item_disabled(3, not has_years)
	_sort.set_item_disabled(4, not has_durations)
	_sort.set_item_disabled(5, not has_durations)
	_length.disabled = not has_durations


func sort_mode() -> int:
	return _sort.selected


func length_mode() -> int:
	return _length.selected if not _length.disabled else 0


func set_wall_mode(on: bool) -> void:
	_wall_mode = on
	_scroll.visible = not on
	if on:
		_hide_skeleton()


## Small label in the top bar: connection problems, or "Offline demo".
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
		_focus_soon(_retry)


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
	_paged_rows.clear()
	var paging: bool = catalog.get("_paging", false)
	var first_card: PosterCard = null
	for row in rows:
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 10)
		section.add_child(UiTheme.label(row["title"], 26))
		var strip_scroll := ScrollContainer.new()
		strip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		strip_scroll.follow_focus = true
		strip_scroll.custom_minimum_size.y = PosterCard.ART_SIZE.y + 64
		if paging:
			var row_index := _rows.get_child_count()
			var bar := strip_scroll.get_h_scroll_bar()
			bar.value_changed.connect(func(value: float) -> void:
				# Near the end of a row: ask for the next page, once.
				if not _paged_rows.has(row_index) and value >= bar.max_value - bar.page - PosterCard.ART_SIZE.x * 4:
					_paged_rows[row_index] = true
					row_end_reached.emit(row_index))
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
	_stagger_in()
	if first_card and is_visible_in_tree():
		_focus_soon(first_card)


## Adds titles to the end of a catalog row (paging).
func append_items(row_index: int, items: Array) -> void:
	items_appended.emit(row_index, items)
	if _wall_mode or row_index >= _rows.get_child_count():
		return
	var strip := _rows.get_child(row_index).find_children("*", "HBoxContainer", true, false)
	if strip.is_empty():
		return
	for item in items:
		var card := PosterCard.new(item, _images)
		card.pressed.connect(item_chosen.emit.bind(item))
		strip[0].add_child(card)
	if not items.is_empty():
		_paged_rows.erase(row_index)  # may ask again further along


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


## New rows fade and slide in, row by row and card by card.
func _stagger_in() -> void:
	for r in _rows.get_child_count():
		var section: Control = _rows.get_child(r)
		var cards := section.find_children("*", "Button", true, false)
		for c in cards.size():
			var card: Control = cards[c]
			card.modulate.a = 0.0
			var tween := card.create_tween().set_parallel()
			var delay := r * 0.06 + mini(c, 8) * 0.03
			tween.tween_property(card, "modulate:a", 1.0, 0.3).set_delay(delay)


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


## Focuses `control` after this frame's changes, unless it's gone by then
## (e.g. the cards were replaced in the meantime).
static func _focus_soon(control: Control) -> void:
	var ref: WeakRef = weakref(control)
	(func() -> void:
		var target: Control = ref.get_ref()
		if target and target.is_inside_tree():
			target.grab_focus()).call_deferred()
