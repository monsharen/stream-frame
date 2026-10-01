class_name NasaProvider
extends VideoProvider
## Public-domain NASA video from the NASA Image and Video Library
## (images.nasa.gov): rows are topics. A title resolves to its MP4 via the
## item's asset list.

const ROWS := [
	["Apollo", "apollo"],
	["Artemis", "artemis"],
	["Mars", "mars rover"],
	["Space telescopes", "webb telescope"],
	["Space station", "international space station"],
	["Earth from space", "earth from space"],
]
const PER_ROW := 24
## Asset suffixes, best first (orig can be several GB).
const SIZES := ["~large.mp4", "~medium.mp4", "~mobile.mp4", "~orig.mp4"]


func _init() -> void:
	id = "nasa"


func _fetch_catalog() -> Dictionary:
	var urls := ROWS.map(func(r: Array) -> String: return _search_url(r[1]))
	var results: Array = await HttpJson.fetch_all(self, urls)
	var rows := []
	for i in ROWS.size():
		if not results[i].ok:
			return results[i]
		rows.append(VideoProvider.row(ROWS[i][0], _items(results[i].data)))
	return {"ok": true, "data": {"service": id, "rows": rows}}


func _search(query: String) -> Dictionary:
	var res: Dictionary = await HttpJson.fetch(self, _search_url(query, 1, 48))
	return {"ok": true, "items": _items(res.data)} if res.ok else res


func _pages_rows() -> bool:
	return true


func _more(row_index: int, page: int) -> Dictionary:
	var res: Dictionary = await HttpJson.fetch(self, _search_url(ROWS[row_index][1], page + 1))
	# Past the last page the API answers 400; that's simply the end.
	return {"ok": true, "items": _items(res.data) if res.ok else []}


func _items(data: Dictionary) -> Array:
	var items := []
	for entry in data.get("collection", {}).get("items", []):
		var meta: Dictionary = entry.get("data", [{}])[0]
		var thumb := ""
		for link in entry.get("links", []):
			if link.get("render") == "image":
				thumb = _https(link.get("href", ""))
				break
		var item := {
			"title": meta.get("title", meta.get("nasa_id", "")),
			"image": thumb,
			# The asset list's URL; resolve() picks a file from it.
			"watchUrl": "nasa:" + _https(entry.get("href", "")),
		}
		var year := str(meta.get("date_created", "")).left(4)
		if year.is_valid_int():
			item["year"] = year.to_int()
		items.append(item)
	return items


static func _search_url(query: String, page := 1, size := PER_ROW) -> String:
	return "https://images-api.nasa.gov/search?media_type=video&page_size=%d&page=%d&q=%s" % [size, page, query.uri_encode()]


func _resolve(watch_url: String) -> Dictionary:
	var assets_url := watch_url.trim_prefix("nasa:")
	if not assets_url.begins_with("https://images-assets.nasa.gov/"):
		return {"ok": false, "error": "Unexpected NASA asset address"}
	var res: Dictionary = await HttpJson.fetch(self, assets_url)
	if not res.ok:
		return res
	var files: Array = res.data if res.data is Array else []
	for suffix in SIZES:
		for file in files:
			if file is String and file.ends_with(suffix):
				return {"ok": true, "url": _https(file)}
	return {"ok": false, "error": "This NASA item has no MP4 video to play."}


## The API returns http:// links with raw spaces.
static func _https(url: String) -> String:
	return url.replace("http://", "https://").replace(" ", "%20")
