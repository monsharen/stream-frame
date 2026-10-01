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
	var urls := ROWS.map(func(r: Array) -> String:
		return "https://images-api.nasa.gov/search?media_type=video&page_size=%d&q=%s" % [PER_ROW, r[1].uri_encode()])
	var results: Array = await HttpJson.fetch_all(self, urls)
	var rows := []
	for i in ROWS.size():
		if not results[i].ok:
			return results[i]
		var items := []
		for entry in results[i].data.get("collection", {}).get("items", []):
			var data: Dictionary = entry.get("data", [{}])[0]
			var thumb := ""
			for link in entry.get("links", []):
				if link.get("render") == "image":
					thumb = _https(link.get("href", ""))
					break
			items.append({
				"title": data.get("title", data.get("nasa_id", "")),
				"image": thumb,
				# The asset list's URL; resolve() picks a file from it.
				"watchUrl": "nasa:" + _https(entry.get("href", "")),
			})
		rows.append(VideoProvider.row(ROWS[i][0], items))
	return {"ok": true, "data": {"service": id, "rows": rows}}


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
