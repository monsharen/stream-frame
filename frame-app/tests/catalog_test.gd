extends Node
## Catalog tools in the 3D shell against live sources (needs internet):
## large catalogs keep only nearby tiles alive, rows page in more titles
## at their end, sorting and the length filter rearrange the wall, and
## search shows results with a way back.
## Run: STREAM_FRAME_OFFLINE=1 STREAM_FRAME_SETTINGS_PATH=/tmp/x.cfg \
##   godot --headless --path . res://tests/catalog_test.tscn

const TIMEOUT := 40.0

var shell: Node3D
var app: Control
var wall: MovieWall


func _ready() -> void:
	shell = load("res://shell.tscn").instantiate()
	add_child(shell)
	app = shell.ui
	wall = shell.wall
	var failure: Variant = await _run()
	failure = _as_failure(failure)
	if failure == "":
		print("CATALOG TEST PASS")
		get_tree().quit(0)
	else:
		printerr("CATALOG TEST FAIL: " + failure)
		get_tree().quit(1)


func _run() -> Variant:
	app.open_source(ExtensionRegistry.by_id(app.sources, "internet-archive"))
	if not await _until(func() -> bool: return wall._rows.size() == 7 and not app.browse.is_loading() and wall.is_settled()):
		return "the Internet Archive catalog didn't load"
	var total := 0
	for row in wall._rows:
		total += row.items.size()
	var live := wall.live_tile_count()
	if live >= total * 0.75:
		return "only tiles near view should exist (%d of %d)" % [live, total]
	wall._scroll_target = wall._max_scroll  # to the bottom rows
	await get_tree().create_timer(1.5).timeout
	if wall._rows[0].tiles.any(func(t: Variant) -> bool: return t != null):
		return "rows scrolled far out of view should free their tiles"
	print("ok: %d titles, %d tiles alive at the top; top rows freed when scrolled away" % [total, live])

	wall._scroll_target = 0.0
	var first_row: MovieWall.Row = wall._rows[0]
	var before := first_row.items.size()
	first_row.offset_target = first_row.min_offset  # sideways to the row's end
	if not await _until(func() -> bool: return first_row.items.size() > before):
		return "scrolling a row to its end should page in more titles"
	print("ok: row paged %d -> %d titles at its end" % [before, first_row.items.size()])

	app.browse._sort.select(1)
	app.browse.arrange_changed.emit()
	await _until(func() -> bool: return wall.is_settled())
	var titles: Array = wall._rows[0].items.map(func(i: Dictionary) -> String: return i["title"])
	var sorted := titles.duplicate()
	sorted.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	if titles != sorted or wall.paging:
		return "A–Z should sort each row (and stop paging): %s" % [titles.slice(0, 4)]
	print("ok: A–Z sorts rows ('%s', '%s', …); paging off while sorted" % [titles[0], titles[1]])

	app.show_home()
	app.open_source(ExtensionRegistry.by_id(app.sources, "open-movies"))
	await _until(func() -> bool: return not app.browse.is_loading() and wall._rows.size() == 6)
	app.browse._length.select(1)  # under 10 minutes
	app.browse.arrange_changed.emit()
	await _until(func() -> bool: return wall.is_settled())
	for row in wall._rows:
		for item in row.items:
			if item["duration"] >= 600.0:
				return "'Under 10 min' kept '%s' (%ds)" % [item["title"], item["duration"]]
	print("ok: 'Under 10 min' leaves %d short films" % wall._rows.reduce(func(n: int, r: MovieWall.Row) -> int: return n + r.items.size(), 0))

	app.show_home()
	app.open_source(ExtensionRegistry.by_id(app.sources, "nasa"))
	await _until(func() -> bool: return not app.browse.is_loading() and wall._rows.size() == 6)
	app.browse.search_requested.emit("apollo")
	if not await _until(func() -> bool: return wall._rows.size() == 1 and wall._rows[0].label.text.contains("apollo")):
		return "searching should show a results row"
	var results := wall._rows[0].items.size()
	app.browse._clear_search.pressed.emit()
	if not await _until(func() -> bool: return wall._rows.size() == 6):
		return "clearing the search should bring the catalog back"
	print("ok: search 'apollo' -> %d results; ✕ brings the catalog back" % results)
	return ""


func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT * 1000
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().create_timer(0.05).timeout
	return false


static func _as_failure(result: Variant) -> String:
	return result if result is String else "the test hit a script error (see the log above)"
