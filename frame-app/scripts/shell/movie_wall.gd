class_name MovieWall
extends Node3D
## The catalog as a curved wall of posters wrapped around the viewer (this
## node sits at head height). Each row is a category; rows scroll vertically
## and fade out above and below a comfortable viewing band, so the wall
## feels endless without making you look up. Long rows scroll sideways.
## Implements the PointerRouter target API.
##
## Changes are animated: outgoing rows drift back and fade, incoming tiles
## rise into place in a wave from the centre (loading placeholders
## cross-fade into the real content the same way).
##
## Large catalogs: tiles only exist near the viewing band and the visible
## arc; they're created as you scroll towards them and freed when far away,
## so thousands of titles cost no more than a screenful. Scrolling a row
## near its end asks for more titles (row_end_reached).
##
## The posters light the room: floor_light holds the colours the wall casts
## on the floor below it, by angle (for WallReflection), lower rows
## counting most; light_color() is the light in front of you.

signal tile_chosen(tile: WallTile)
signal row_end_reached(row_index: int)

const RADIUS := 3.2
## The wall spans 180°, -90° to +90° around the viewer.
const ARC := PI
const EDGE_FADE := 0.2   # radians over which tiles fade at the arc's ends
const MARGIN := 0.12     # radians kept clear at the arc's ends when a row overflows
const GAP := 0.07
const ROW_HEIGHT := 0.68
## Room for a row's title above its tiles.
const LABEL_SPACE := 0.1
## The first row's label line, relative to eye height.
const TOP := 0.55
## Comfortable band (relative to eye height) with fades at its edges.
const BAND_TOP := 0.95
const BAND_BOTTOM := -1.45
const BAND_FADE := 0.35
## Content moves back by this much while faded (behind panels, or hidden
## while a film plays).
const DIM_PUSH := 0.8
## Behind a panel the wall stays faintly visible; while watching it's gone.
const DIMMED := 0.85
const HIDDEN := 1.0
## Incoming tiles start this far behind their place.
const APPROACH := 0.5
## Wave timing for incoming tiles: per row, per tile from the centre, cap.
const ROW_STAGGER := 0.07
const TILE_STAGGER := 0.035
const MAX_STAGGER := 0.6
## How long outgoing rows take to drift back and fade.
const LEAVE_SECONDS := 0.3
const SCROLL_STEP := 0.34
const HSCROLL_STEP := 0.14
const SMOOTHING := 12.0
const PLACEHOLDER_ROWS := 2
const PLACEHOLDER_TILES := 9
## Tiles live this many beyond each end of the visible arc, and rows this
## far outside the band keep none.
const LIVE_EXTRA_TILES := 2
const LIVE_EXTRA_HEIGHT := ROW_HEIGHT
## Within this many tiles of a row's end, ask for more.
const PAGE_AHEAD := 4
## Tiles made per frame at most: a new catalog brings dozens at once, and
## making them all in one frame would stutter (they rise in with the wave
## anyway, so the rest a frame or two later doesn't show).
const NEW_TILES_PER_FRAME := 16
## The home's row of extensions, relative to catalog tiles.
const HOME_SIZE := 1.2
## Extension tiles per row on the home.
const HOME_PER_ROW := 6
## A wall starting with an untitled row (the home) centres it just above
## eye level rather than leaving room for a title.
const UNTITLED_CENTRE := 0.1
## Floor light: angle bins across the arc, how fast lower rows dominate
## (metres above the floor), and how quickly it follows changes.
const FLOOR_BINS := 48
const FLOOR_FALLOFF := 0.9
const FLOOR_SMOOTHING := 4.0


class Row:
	var node := Node3D.new()
	var label := Label3D.new()
	var items: Array = []
	## One slot per item: its tile while live, null otherwise.
	var tiles: Array = []
	## Angle of the first tile's centre before scrolling.
	var start := 0.0
	var offset := 0.0
	var offset_target := 0.0
	var min_offset := 0.0
	## When the row arrived (tiles made soon after join its wave).
	var born := 0.0
	var wave := 0
	var asked_for_more := false
	## Tile size (1 = normal; the home's row is larger) and where the row's
	## top is, before scrolling.
	var size := 1.0
	var top := 0.0

	func height() -> float:
		return ROW_HEIGHT * size - (0.0 if label.text != "" else LABEL_SPACE)

	## Angle from one tile to the next.
	func step() -> float:
		return (WallTile.SIZE.x + GAP) * size / RADIUS

	## Where its tiles' centres are, relative to its top.
	func tile_drop() -> float:
		return (LABEL_SPACE if label.text != "" else 0.0) + WallTile.SIZE.y * size / 2.0


## Off while dimmed behind the player.
var interactive := true
## Rows may page in more titles (off for search results, sorted views…).
var paging := false

var _images: ImageCache
var _rows: Array[Row] = []
var _scroll := 0.0
var _scroll_target := 0.0
var _max_scroll := 0.0
var _dim := 0.0
var _dim_target := 0.0
## Rows added so far in the current change (for the wave's row index).
var _incoming := 0
var _incoming_delay := 0.0
var _hover: WallTile
var _pressed: WallTile
var _loading := false
var _pulse := 0.0
var _dirty := true
var _more_tiles_pending := false
## The wall's light on the floor (FLOOR_BINS × 1), see above.
var floor_light: ImageTexture
var _floor_image := Image.create(FLOOR_BINS, 1, false, Image.FORMAT_RGB8)
var _floor_target := PackedColorArray()
var _floor_now := PackedColorArray()


func _init(images: ImageCache) -> void:
	_images = images
	_floor_target.resize(FLOOR_BINS)
	_floor_target.fill(Color.BLACK)
	_floor_now = _floor_target.duplicate()
	floor_light = ImageTexture.create_from_image(_floor_image)


## The light the wall casts towards you (the middle of the floor light).
func light_color() -> Color:
	var sum := Color(0, 0, 0)
	for i in range(FLOOR_BINS / 3, FLOOR_BINS * 2 / 3):
		sum += _floor_now[i]
	return Color(sum / float(FLOOR_BINS / 3), 1.0)


## Re-applies the tiles' light after WallTile.light_level changed.
func refresh_light() -> void:
	for row in _rows:
		for tile in row.tiles:
			if tile:
				tile.set_alpha(tile._alpha)
	_dirty = true


func show_loading() -> void:
	_clear()
	_loading = true
	for r in PLACEHOLDER_ROWS:
		var placeholders := []
		placeholders.resize(PLACEHOLDER_TILES)
		placeholders.fill({})
		_add_row("", placeholders)


func show_catalog(catalog: Dictionary, can_page := false) -> void:
	_clear()
	paging = can_page
	for row in catalog.get("rows", []):
		_add_row(row["title"], row["items"], row.get("size", 1.0))
	_update_max_scroll()


## More titles for a row (paging): they slot in at its end.
func append_items(row_index: int, items: Array) -> void:
	if row_index < 0 or row_index >= _rows.size():
		return
	var row := _rows[row_index]
	row.items.append_array(items)
	row.tiles.resize(row.items.size())
	_measure(row)
	row.asked_for_more = items.is_empty()  # nothing came: that was all
	_dirty = true


## Every tile in view has been made and finished appearing (tests,
## screenshots).
func is_settled() -> bool:
	if _dirty:
		return false
	for row in _rows:
		var live := 0
		for tile in row.tiles:
			if tile:
				live += 1
				if tile.appear < 1.0:
					return false
		if live == 0 and not row.items.is_empty() and row.node.visible:
			return false  # not laid out yet
	return true


## How many tiles exist right now (tests: virtualisation keeps this small).
func live_tile_count() -> int:
	var count := 0
	for row in _rows:
		for tile in row.tiles:
			count += 1 if tile else 0
	return count


## The home: the enabled extensions, HOME_PER_ROW to a row, larger than
## catalog tiles, then Continue watching. Every tile looks the same whether
## or not its extension is ready: selecting one that isn't explains why.
func show_sources(sources: Array, continue_items: Array = []) -> void:
	var rows := []
	var ordered := BrowseView.home_order(sources)
	for start in range(0, ordered.size(), HOME_PER_ROW):
		var items := []
		for source: Dictionary in ordered.slice(start, start + HOME_PER_ROW):
			items.append({
				"kind": "source", "source": source, "title": _source_title(source),
				"art_text": source["name"], "art_color": SourceCard.tile_color(source),
				"image": source.get("image", ""), "title_color": UiTheme.TEXT,
			})
		rows.append({"title": "", "items": items, "size": HOME_SIZE})
	if not continue_items.is_empty():
		rows.append({"title": "Continue watching", "items": continue_items})
	show_catalog({"rows": rows})


## Under an extension's tile (which is just its logo): its name. Whether
## it's ready shows in the tile (greyed out) and, when selected, on its page.
static func _source_title(source: Dictionary) -> String:
	return source["name"]


## Loading failed: drop placeholders (real rows from before a failed refresh stay).
func show_error() -> void:
	if _loading:
		_clear()


## Fades the wall behind a panel (DIMMED) or away entirely (HIDDEN, while
## a film plays); 0 brings it back.
func set_faded(amount: float) -> void:
	_dim_target = amount
	interactive = amount == 0.0
	if not interactive:
		pointer_exit()


func set_dimmed(dimmed: bool) -> void:
	set_faded(DIMMED if dimmed else 0.0)


## The tile showing `item` (by watchUrl), if live; used by tests.
func tile_for(watch_url: String) -> WallTile:
	for row in _rows:
		for tile in row.tiles:
			if tile and tile.item.get("watchUrl") == watch_url:
				return tile
	return null


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var k := 1.0 - exp(-SMOOTHING * delta)
	if not is_equal_approx(_scroll, _scroll_target):
		_scroll = lerpf(_scroll, _scroll_target, k) if absf(_scroll - _scroll_target) > 0.001 else _scroll_target
		_dirty = true
	if not is_equal_approx(_dim, _dim_target):
		_dim = move_toward(_dim, _dim_target, delta * 3.0)
		_dirty = true
	for r in _rows.size():
		var row := _rows[r]
		if not is_equal_approx(row.offset, row.offset_target):
			row.offset = lerpf(row.offset, row.offset_target, k) if absf(row.offset - row.offset_target) > 0.0005 else row.offset_target
			_dirty = true
		for tile in row.tiles:
			if tile and tile.animate(delta, now):
				_dirty = true
		_maybe_page(r)
	if _loading:
		_pulse += delta
		_dirty = true
	if _dirty:
		_more_tiles_pending = false
		_layout(now)
		_dirty = _more_tiles_pending  # the rest next frame
	_update_floor(delta)


func _layout(now: float) -> void:
	var new_tiles := 0
	var pulse := 0.7 + 0.3 * sin(_pulse * 4.0) if _loading else 1.0
	var wall_alpha := (1.0 - _dim) * pulse
	var radius := RADIUS + DIM_PUSH * _dim
	for r in _rows.size():
		var row := _rows[r]
		var step := row.step()
		var half_tile := WallTile.SIZE.x * row.size / 2.0 / RADIUS
		var y0 := row.top + _scroll
		var tile_y := y0 - row.tile_drop()
		var near_band := tile_y < BAND_TOP + LIVE_EXTRA_HEIGHT and tile_y > BAND_BOTTOM - LIVE_EXTRA_HEIGHT
		var row_alpha := _band_alpha(tile_y) * wall_alpha
		row.node.visible = row_alpha > 0.01
		var first := row.start + row.offset
		# Which tiles should exist: those near the visible arc, in rows near
		# the band. Everything else is freed.
		var lo := 0
		var hi := -1
		if near_band:
			lo = maxi(0, ceili((-ARC / 2.0 - first) / step) - LIVE_EXTRA_TILES)
			hi = mini(row.items.size() - 1, floori((ARC / 2.0 - first) / step) + LIVE_EXTRA_TILES)
		for i in row.tiles.size():
			if (i < lo or i > hi) and row.tiles[i]:
				_free_tile(row, i)
		if not row.node.visible:
			continue
		var label_appear := 1.0
		for i in range(lo, hi + 1):
			var tile: WallTile = row.tiles[i]
			if tile == null:
				if new_tiles >= NEW_TILES_PER_FRAME:
					_more_tiles_pending = true
					continue
				tile = _make_tile(row, i, now)
				new_tiles += 1
			if i == lo:
				label_appear = tile.appear_eased() if row.start + row.offset > -ARC / 2.0 else 1.0
			var angle := first + i * step
			var approach := APPROACH * (1.0 - tile.appear_eased())
			_place(tile, angle, tile_y - 0.06 * (1.0 - tile.appear_eased()),
				radius - WallTile.HOVER_LIFT * tile.hover + approach)
			var alpha := row_alpha * _edge_alpha(angle)
			tile.set_alpha(alpha)
			if alpha > 0.01:
				tile.ensure_texture(_images)
		_place(row.label, first - half_tile, y0, radius + APPROACH * (1.0 - label_appear))
		row.label.modulate.a = row_alpha * _edge_alpha(first - half_tile) * label_appear
	_gather_floor_light()


## Where the wall's light falls on the floor: each lit tile adds its colour
## to the angle bins under it, weighted by how close to the floor it is.
func _gather_floor_light() -> void:
	_floor_target.fill(Color.BLACK)
	var bin_width := ARC / FLOOR_BINS
	for row in _rows:
		var spread := WallTile.SIZE.x * row.size / RADIUS / 2.0
		if not row.node.visible:
			continue
		for tile: WallTile in row.tiles:
			if tile == null or not tile.visible:
				continue
			var light: Color = tile.light()
			if light == Color.BLACK:
				continue
			var height := position.y + tile.position.y
			light *= exp(-maxf(height, 0.0) / FLOOR_FALLOFF)
			var angle := -tile.rotation.y
			var first := maxi(0, floori((angle - spread * 2.0 + ARC / 2.0) / bin_width))
			var last := mini(FLOOR_BINS - 1, ceili((angle + spread * 2.0 + ARC / 2.0) / bin_width))
			for b in range(first, last + 1):
				var d := ((b + 0.5) * bin_width - ARC / 2.0 - angle) / spread
				_floor_target[b] += light * exp(-d * d)


func _update_floor(delta: float) -> void:
	var k := 1.0 - exp(-FLOOR_SMOOTHING * delta)
	var changed := false
	for b in FLOOR_BINS:
		var target: Color = _floor_target[b]
		var current: Color = _floor_now[b]
		if current.is_equal_approx(target):
			continue
		current = current.lerp(target, k)
		if maxf(absf(current.r - target.r), maxf(absf(current.g - target.g), absf(current.b - target.b))) < 0.002:
			current = target
		_floor_now[b] = current
		_floor_image.set_pixel(b, 0, Color(minf(current.r, 1.0), minf(current.g, 1.0), minf(current.b, 1.0)))
		changed = true
	if changed:
		floor_light.update(_floor_image)


func _make_tile(row: Row, index: int, now: float) -> WallTile:
	var tile := WallTile.new(row.items[index])
	tile.scale = Vector3.ONE * row.size
	row.tiles[index] = tile
	row.node.add_child(tile)
	# Tiles there when the row arrives join its wave (from the centre out);
	# ones made later, as you scroll, just rise in.
	if now - row.born < 0.1:
		var centre := (mini(row.items.size(), 18) - 1) / 2.0
		var wave := row.wave * ROW_STAGGER + absf(index - centre) * TILE_STAGGER
		tile.start_appearing(now, _incoming_delay + minf(wave, MAX_STAGGER))
	else:
		tile.start_appearing(now, 0.0)
	return tile


func _free_tile(row: Row, index: int) -> void:
	var tile: WallTile = row.tiles[index]
	row.tiles[index] = null
	if tile == _hover:
		_set_hover(null)
	if tile == _pressed:
		_pressed = null
	tile.queue_free()


func _maybe_page(row_index: int) -> void:
	var row := _rows[row_index]
	if not paging or row.asked_for_more or row.min_offset >= 0.0:
		return
	if row.offset_target <= row.min_offset + PAGE_AHEAD * row.step():
		row.asked_for_more = true
		row_end_reached.emit(row_index)


func _add_row(title: String, items: Array, size := 1.0) -> void:
	var row := Row.new()
	row.label.text = title
	row.size = size
	if _rows.is_empty():
		row.top = TOP if title != "" else UNTITLED_CENTRE + WallTile.SIZE.y * size / 2.0
	else:
		row.top = _rows[-1].top - _rows[-1].height()
	row.label.font_size = 56
	row.label.pixel_size = 0.001
	row.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	row.label.modulate = UiTheme.TEXT
	row.node.add_child(row.label)
	row.items = items.duplicate()
	row.tiles.resize(row.items.size())
	row.born = Time.get_ticks_msec() / 1000.0
	row.wave = _incoming
	_incoming += 1
	_measure(row)
	_rows.append(row)
	add_child(row.node)
	_dirty = true


## Where a row starts and how far it can scroll, from its length.
func _measure(row: Row) -> void:
	var step := row.step()
	var gap := GAP * row.size / RADIUS
	var content := row.items.size() * step - gap
	var available := ARC - 2.0 * MARGIN
	if content <= available:
		row.start = -content / 2.0 + step / 2.0 - gap / 2.0  # centred
		row.min_offset = 0.0
	else:
		row.start = -ARC / 2.0 + MARGIN + WallTile.SIZE.x * row.size / 2.0 / RADIUS
		row.min_offset = available - content


func _update_max_scroll() -> void:
	_max_scroll = 0.0 if _rows.is_empty() else maxf(0.0, TOP - _rows[-1].top - 1.4)


func _clear() -> void:
	pointer_exit()
	# Outgoing rows drift back and fade while the new ones rise in.
	for row in _rows:
		_retire(row)
	_incoming_delay = LEAVE_SECONDS * 0.5 if not _rows.is_empty() else 0.0
	_rows.clear()
	_incoming = 0
	_loading = false
	paging = false
	_scroll = 0.0
	_scroll_target = 0.0
	_max_scroll = 0.0


func _retire(row: Row) -> void:
	var tiles := row.tiles.filter(func(t: Variant) -> bool: return t != null)
	var start_alpha := {}
	for tile in tiles:
		start_alpha[tile] = tile._alpha
	var label_alpha := row.label.modulate.a
	var tween := create_tween().set_parallel()
	tween.tween_method(func(f: float) -> void:
		for tile in tiles:
			if is_instance_valid(tile):
				tile.set_alpha(start_alpha[tile] * f)
		row.label.modulate.a = label_alpha * f, 1.0, 0.0, LEAVE_SECONDS)
	# Scaling about the viewer moves the row back without changing its size
	# in view: it recedes.
	tween.tween_property(row.node, "scale", Vector3.ONE * 1.15, LEAVE_SECONDS).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(row.node.queue_free)


## Places a node on the cylinder at `angle`, facing the centre.
static func _place(node: Node3D, angle: float, y: float, radius: float) -> void:
	node.position = Vector3(radius * sin(angle), y, -radius * cos(angle))
	node.rotation = Vector3(0, -angle, 0)


static func _band_alpha(y: float) -> float:
	var bottom := clampf((y - BAND_BOTTOM) / BAND_FADE, 0.0, 1.0)
	var top := clampf((BAND_TOP - y) / BAND_FADE, 0.0, 1.0)
	return smoothstep(0.0, 1.0, minf(bottom, top))


static func _edge_alpha(angle: float) -> float:
	return smoothstep(0.0, 1.0, clampf((ARC / 2.0 - absf(angle)) / EDGE_FADE, 0.0, 1.0))


func _row_at(y_local: float) -> Row:
	for row in _rows:
		var y0 := row.top + _scroll
		if y_local <= y0 + 0.08 and y_local > y0 - row.height() + 0.08:
			return row
	return null


func _set_hover(tile: WallTile) -> void:
	if tile == _hover:
		return
	if _hover and is_instance_valid(_hover):
		_hover.set_hovered(false)
	_hover = tile
	if _hover:
		_hover.set_hovered(true)


# --- PointerRouter target API ---

func pointer_hit(origin: Vector3, direction: Vector3) -> Dictionary:
	if not interactive or _rows.is_empty() or not is_visible_in_tree():
		return {}
	var best: WallTile = null
	var best_distance := INF
	for row in _rows:
		if not row.node.visible:
			continue
		for tile in row.tiles:
			if tile == null:
				continue
			var distance: float = tile.hit_distance(origin, direction)
			if distance >= 0.0 and distance < best_distance:
				best = tile
				best_distance = distance
	if best:
		return {"distance": best_distance, "point": origin + direction.normalized() * best_distance, "tile": best,
			"row": _row_at(to_local(origin + direction.normalized() * best_distance).y)}
	# Between tiles: still the wall (for scrolling), just nothing to click.
	var o := to_local(origin)
	var d := (global_transform.basis.inverse() * direction).normalized()
	var a := d.x * d.x + d.z * d.z
	var b := 2.0 * (o.x * d.x + o.z * d.z)
	var c := o.x * o.x + o.z * o.z - RADIUS * RADIUS
	var discriminant := b * b - 4.0 * a * c
	if a < 1e-9 or discriminant < 0.0:
		return {}
	var t := (-b + sqrt(discriminant)) / (2.0 * a)
	var p := o + d * t
	if t <= 0.0 or absf(atan2(p.x, -p.z)) > ARC / 2.0 or p.y > BAND_TOP or p.y < BAND_BOTTOM:
		return {}
	return {"distance": t, "point": to_global(p), "tile": null, "row": _row_at(p.y)}


func pointer_move(hit: Dictionary) -> void:
	_set_hover(hit.get("tile"))
	if _hover and _hover.point_at(hit["point"]):
		_dirty = true


func pointer_button(_hit: Dictionary, pressed: bool) -> void:
	if pressed:
		_pressed = _hover
	else:
		var chosen := _pressed if _pressed == _hover else null
		_pressed = null
		# Handlers may change the wall (dim it, clear hover), so emit last.
		if chosen:
			tile_chosen.emit(chosen)


func pointer_scroll(hit: Dictionary, dy: float, dx: float) -> void:
	if dy != 0.0:
		_scroll_target = clampf(_scroll_target + dy * SCROLL_STEP, 0.0, _max_scroll)
	var row: Row = hit.get("row")
	if dx != 0.0 and row:
		row.offset_target = clampf(row.offset_target - dx * HSCROLL_STEP, row.min_offset, 0.0)


func pointer_exit() -> void:
	_set_hover(null)
	_pressed = null
