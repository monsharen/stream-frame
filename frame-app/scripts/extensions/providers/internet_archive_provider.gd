class_name InternetArchiveProvider
extends VideoProvider
## Public-domain films and TV from the Internet Archive (archive.org): rows
## are collections, ordered by popularity. A title resolves to the item's
## MP4 file via the metadata API.

const ROWS := [
	["Popular feature films", "feature_films"],
	["Silent films", "silent_films"],
	["Sci-fi and horror", "SciFi_Horror"],
	["Comedy", "Comedy_Films"],
	["Cartoons", "animationandcartoons"],
	["Classic TV", "classic_tv"],
	["Prelinger Archives", "prelinger"],
]
const PER_ROW := 24
## Preferred video formats, best first.
const FORMATS := ["h.264", "h.264 IA", "MPEG4", "512Kb MPEG4"]


func _init() -> void:
	id = "internet-archive"


func _fetch_catalog() -> Dictionary:
	var urls := ROWS.map(func(r: Array) -> String: return _search_url("collection:" + r[1]))
	var results: Array = await HttpJson.fetch_all(self, urls)
	var rows := []
	for i in ROWS.size():
		if not results[i].ok:
			return results[i]
		rows.append(VideoProvider.row(ROWS[i][0], _items(results[i].data)))
	return {"ok": true, "data": {"service": id, "rows": rows}}


## Searches titles across the public-domain collections the rows come from
## (not the whole archive, where rights vary).
func _search(query: String) -> Dictionary:
	var collections := " OR ".join(ROWS.map(func(r: Array) -> String: return r[1]))
	var res: Dictionary = await HttpJson.fetch(self, _search_url("title:(%s) AND collection:(%s)" % [_escape(query), collections], 48))
	return {"ok": true, "items": _items(res.data)} if res.ok else res


func _pages_rows() -> bool:
	return true


func _more(row_index: int, page: int) -> Dictionary:
	var res: Dictionary = await HttpJson.fetch(self, _search_url("collection:" + ROWS[row_index][1], PER_ROW, page + 1))
	return {"ok": true, "items": _items(res.data)} if res.ok else res


func _items(data: Dictionary) -> Array:
	var items := []
	for doc in data.get("response", {}).get("docs", []):
		var identifier := _text(doc.get("identifier", ""))
		var title := _text(doc.get("title", identifier))
		var year := _text(doc.get("year", "")).left(4)
		var item := {
			"title": title + (" (%s)" % year if year != "" else ""),
			"image": "https://archive.org/services/img/" + identifier.uri_encode(),
			"watchUrl": "ia:" + identifier,
		}
		if year.is_valid_int():
			item["year"] = year.to_int()
		items.append(item)
	return items


func _resolve(watch_url: String) -> Dictionary:
	var identifier := watch_url.trim_prefix("ia:")
	var res: Dictionary = await HttpJson.fetch(self, "https://archive.org/metadata/" + identifier.uri_encode())
	if not res.ok:
		return res
	var files: Array = res.data.get("files", [])
	for format in FORMATS:
		for file in files:
			if file.get("format") == format:
				return {"ok": true, "url": "https://archive.org/download/%s/%s" % [identifier.uri_encode(), file["name"].uri_encode()]}
	return {"ok": false, "error": "This Internet Archive item has no MP4 version to play."}


## Archive metadata fields can hold a list (several titles, years); use
## the first.
static func _text(value: Variant) -> String:
	if value is Array:
		return str(value[0]) if not value.is_empty() else ""
	return str(value)


static func _search_url(query: String, rows := PER_ROW, page := 1) -> String:
	# Only items that have a version the player takes (some are only in
	# other formats), so everything listed can be played.
	var full := "(%s) AND mediatype:movies AND format:(%s)" % [query, " OR ".join(FORMATS.map(func(f: String) -> String: return '"%s"' % f))]
	return "https://archive.org/advancedsearch.php?q=%s&fl[]=identifier&fl[]=title&fl[]=year&sort[]=downloads+desc&rows=%d&page=%d&output=json" \
		% [full.uri_encode(), rows, page]


## Keeps a search query from breaking out of its field.
static func _escape(query: String) -> String:
	var out := ""
	for c in query:
		out += c if c.is_valid_identifier() or c == " " or c.is_valid_int() else " "
	return out.strip_edges()
