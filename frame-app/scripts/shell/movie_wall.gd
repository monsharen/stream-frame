class_name MovieWall
extends Node3D
## The catalog as a curved wall of posters wrapped around the viewer (this
## node sits at head height). Each row is a category; rows scroll vertically
## and fade out above and below a comfortable viewing band, so the wall
## feels endless without making you look up. Long rows scroll sideways.
## Implements the PointerRouter target API.

signal tile_chosen(tile: WallTile)

const RADIUS := 3.2
## The wall spans 180°, -90° to +90° around the viewer.
const ARC := PI
const EDGE_FADE := 0.2   # radians over which tiles fade at the arc's ends
const MARGIN := 0.12     # radians kept clear at the arc's ends when a row overflows
const GAP := 0.07
const ROW_HEIGHT := 0.68
## The first row's label line, relative to eye height.
const TOP := 0.55
## Comfortable band (relative to eye height) with fades at its edges.
const BAND_TOP := 0.95
const BAND_BOTTOM := -1.45
const BAND_FADE := 0.35
## Content moves back by this much while dimmed (behind the player).
const DIM_PUSH := 0.8
const SCROLL_STEP := 0.34
const HSCROLL_STEP := 0.14
const SMOOTHING := 12.0
const PLACEHOLDER_ROWS := 2
const PLACEHOLDER_TILES := 9


class Row:
	var node := Node3D.new()
	var label := Label3D.new()
	var tiles: Array[WallTile] = []
	## Angle of the first tile's centre before scrolling.
	var start := 0.0
	var offset := 0.0
	var offset_target := 0.0
	var min_offset := 0.0


## Off while dimmed behind the player.
var interactive := true

var _images: ImageCache
var _rows: Array[Row] = []
var _scroll := 0.0
var _scroll_target := 0.0
var _max_scroll := 0.0
var _dim := 0.0
var _dim_target := 0.0
var _hover: WallTile
var _pressed: WallTile
var _loading := false
var _pulse := 0.0
var _dirty := true


func _init(images: ImageCache) -> void:
	_images = images


func show_loading() -> void:
	_clear()
	_loading = true
	for r in PLACEHOLDER_ROWS:
		_add_row("", [], PLACEHOLDER_TILES)


func show_catalog(catalog: Dictionary) -> void:
	_clear()
	for row in catalog.get("rows", []):
		_add_row(row["title"], row["items"])
	_max_scroll = maxf(0.0, (_rows.size() - 1) * ROW_HEIGHT - 1.4)


## The home: enabled extensions (on this device, from your PC), then apps.
## Unavailable ones are dimmed but still selectable (they explain what's up).
func show_sources(sources: Array) -> void:
	var rows := []
	for group in BrowseView.HOME_GROUPS:
		var items := []
		for source in sources.filter(func(s: Dictionary) -> bool: return s["kind"] == group[1]):
			items.append({
				"kind": "source", "source": source, "title": source["status"],
				"art_text": source["name"], "art_color": SourceCard.tile_color(source),
				"dimmed": not source["available"], "title_color": SourceCard.status_color(source),
			})
		if not items.is_empty():
			rows.append({"title": group[0], "items": items})
	show_catalog({"rows": rows})


## Loading failed: drop placeholders (real rows from before a failed refresh stay).
func show_error() -> void:
	if _loading:
		_clear()


func set_dimmed(dimmed: bool) -> void:
	_dim_target = 1.0 if dimmed else 0.0
	interactive = not dimmed
	if dimmed:
		pointer_exit()


## The tile showing `item` (by watchUrl), if any; used by tests.
func tile_for(watch_url: String) -> WallTile:
	for row in _rows:
		for tile in row.tiles:
			if tile.item.get("watchUrl") == watch_url:
				return tile
	return null


func _process(delta: float) -> void:
	var k := 1.0 - exp(-SMOOTHING * delta)
	if not is_equal_approx(_scroll, _scroll_target):
		_scroll = lerpf(_scroll, _scroll_target, k) if absf(_scroll - _scroll_target) > 0.001 else _scroll_target
		_dirty = true
	if not is_equal_approx(_dim, _dim_target):
		_dim = move_toward(_dim, _dim_target, delta * 3.0)
		_dirty = true
	for row in _rows:
		if not is_equal_approx(row.offset, row.offset_target):
			row.offset = lerpf(row.offset, row.offset_target, k) if absf(row.offset - row.offset_target) > 0.0005 else row.offset_target
			_dirty = true
		for tile in row.tiles:
			if tile.animate(delta):
				_dirty = true
	if _loading:
		_pulse += delta
		_dirty = true
	if _dirty:
		_layout()
		_dirty = false


func _layout() -> void:
	var step := (WallTile.SIZE.x + GAP) / RADIUS
	var half_tile := WallTile.SIZE.x / 2.0 / RADIUS
	var pulse := 0.7 + 0.3 * sin(_pulse * 4.0) if _loading else 1.0
	var wall_alpha := (1.0 - 0.85 * _dim) * pulse
	var radius := RADIUS + DIM_PUSH * _dim
	for r in _rows.size():
		var row := _rows[r]
		var y0 := TOP - r * ROW_HEIGHT + _scroll
		var tile_y := y0 - 0.1 - WallTile.SIZE.y / 2.0
		var row_alpha := _band_alpha(tile_y) * wall_alpha
		row.node.visible = row_alpha > 0.01
		if not row.node.visible:
			continue
		var first := row.start + row.offset
		_place(row.label, first - half_tile, y0, radius)
		row.label.modulate.a = row_alpha * _edge_alpha(first - half_tile)
		for i in row.tiles.size():
			var tile := row.tiles[i]
			var angle := first + i * step
			_place(tile, angle, tile_y, radius - WallTile.HOVER_LIFT * tile.hover)
			var alpha := row_alpha * _edge_alpha(angle)
			tile.set_alpha(alpha)
			if alpha > 0.01:
				tile.ensure_texture(_images)


func _add_row(title: String, items: Array, placeholders := 0) -> void:
	var row := Row.new()
	row.label.text = title
	row.label.font_size = 56
	row.label.pixel_size = 0.001
	row.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	row.label.modulate = UiTheme.TEXT
	row.node.add_child(row.label)
	for item in items:
		row.tiles.append(WallTile.new(item))
	for i in placeholders:
		row.tiles.append(WallTile.new())
	for tile in row.tiles:
		row.node.add_child(tile)

	var step := (WallTile.SIZE.x + GAP) / RADIUS
	var content := row.tiles.size() * step - GAP / RADIUS
	var available := ARC - 2.0 * MARGIN
	if content <= available:
		row.start = -content / 2.0 + step / 2.0 - GAP / RADIUS / 2.0  # centred
	else:
		row.start = -ARC / 2.0 + MARGIN + WallTile.SIZE.x / 2.0 / RADIUS
		row.min_offset = available - content
	_rows.append(row)
	add_child(row.node)
	_dirty = true


func _clear() -> void:
	pointer_exit()
	for row in _rows:
		row.node.queue_free()
	_rows.clear()
	_loading = false
	_scroll = 0.0
	_scroll_target = 0.0
	_max_scroll = 0.0


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
	for r in _rows.size():
		var y0 := TOP - r * ROW_HEIGHT + _scroll
		if y_local <= y0 + 0.08 and y_local > y0 - ROW_HEIGHT + 0.08:
			return _rows[r]
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
			var distance := tile.hit_distance(origin, direction)
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
