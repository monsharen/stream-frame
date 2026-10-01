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
	var urls := ROWS.map(func(r: Array) -> String: return _search_url(r[1]))
	var results: Array = await HttpJson.fetch_all(self, urls)
	var rows := []
	for i in ROWS.size():
		if not results[i].ok:
			return results[i]
		var items := []
		for doc in results[i].data.get("response", {}).get("docs", []):
			var identifier := _text(doc.get("identifier", ""))
			var title := _text(doc.get("title", identifier))
			if doc.has("year"):
				title += " (%s)" % _text(doc["year"]).left(4)
			items.append({
				"title": title,
				"image": "https://archive.org/services/img/" + identifier.uri_encode(),
				"watchUrl": "ia:" + identifier,
			})
		rows.append(VideoProvider.row(ROWS[i][0], items))
	return {"ok": true, "data": {"service": id, "rows": rows}}


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


static func _search_url(collection: String) -> String:
	var query := "collection:%s AND mediatype:movies" % collection
	return "https://archive.org/advancedsearch.php?q=%s&fl[]=identifier&fl[]=title&fl[]=year&sort[]=downloads+desc&rows=%d&output=json" \
		% [query.uri_encode(), PER_ROW]
