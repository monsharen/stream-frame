class_name PeerTubeProvider
extends VideoProvider
## PeerTube, the open federated video network, searched across instances
## through a search index (SepiaSearch by default). Rows are topics; a title
## resolves to its HLS stream (or a direct file) on the instance hosting it.
## Videos marked sensitive are always excluded.

const DEFAULT_INDEX := "https://sepiasearch.org"
const DEFAULT_TOPICS := "nature, science, documentary, animation, travel, music"
const PER_ROW := 24
## Skip clips too short to be worth watching on a big screen.
const MIN_SECONDS := 120


func _init() -> void:
	id = "peertube"


func _fetch_catalog() -> Dictionary:
	var index := _index()
	if index == "":
		return {"ok": false, "error": "The PeerTube search index must be an https:// address (Extensions → PeerTube)."}
	_topics = Array(str(_config("topics")).split(",", false)).map(func(t: String) -> String: return t.strip_edges())
	_topics = _topics.filter(func(t: String) -> bool: return t != "")
	if _topics.is_empty():
		return {"ok": false, "error": "No PeerTube topics configured (Extensions → PeerTube)."}
	var results: Array = await HttpJson.fetch_all(self, _topics.map(func(t: String) -> String: return _search_url(index, t)))
	var rows := []
	for i in _topics.size():
		if not results[i].ok:
			return results[i]
		rows.append(VideoProvider.row(_topics[i].capitalize(), _items(results[i].data)))
	return {"ok": true, "data": {"service": id, "rows": rows}}


func _search(query: String) -> Dictionary:
	if _index() == "":
		return {"ok": false, "error": "The PeerTube search index must be an https:// address (Extensions → PeerTube)."}
	var res: Dictionary = await HttpJson.fetch(self, _search_url(_index(), query, 0, 48))
	return {"ok": true, "items": _items(res.data)} if res.ok else res


func _pages_rows() -> bool:
	return true


func _more(row_index: int, page: int) -> Dictionary:
	var res: Dictionary = await HttpJson.fetch(self, _search_url(_index(), _topics[row_index], page * PER_ROW))
	return {"ok": true, "items": _items(res.data)} if res.ok else res


var _topics: Array = []


func _index() -> String:
	return VideoProvider.safe_media_url(str(_config("search_index")).trim_suffix("/"))


func _search_url(index: String, query: String, start := 0, count := PER_ROW) -> String:
	var url := "%s/api/v1/search/videos?search=%s&start=%d&count=%d&nsfw=false&durationMin=%d" \
		% [index, query.uri_encode(), start, count, MIN_SECONDS]
	var language := str(_config("language")).strip_edges()
	if language != "":
		url += "&languageOneOf[]=" + language.uri_encode()
	return url


func _items(data: Dictionary) -> Array:
	var items := []
	for video in data.get("data", []):
		if video.get("nsfw", false):
			continue
		# Host and id end up in a URL we request: accept only plain
		# hostnames and UUIDs, so a bad index entry can't redirect it.
		var host: String = video.get("account", {}).get("host", "")
		if not _is_hostname(host) or not _is_uuid(video.get("uuid", "")):
			continue
		var item := {
			"title": video.get("name", ""),
			"image": VideoProvider.safe_media_url(video.get("thumbnailUrl", "")),
			"watchUrl": "peertube:%s/%s" % [host, video.get("uuid", "")],
			"duration": float(video.get("duration", 0)),
		}
		var year := str(video.get("publishedAt", "")).left(4)
		if year.is_valid_int():
			item["year"] = year.to_int()
		items.append(item)
	return items


func _resolve(watch_url: String) -> Dictionary:
	var ref := watch_url.trim_prefix("peertube:")
	var host := ref.get_slice("/", 0)
	var uuid := ref.get_slice("/", 1)
	if not _is_hostname(host) or not _is_uuid(uuid):
		return {"ok": false, "error": "Unexpected PeerTube address"}
	var res: Dictionary = await HttpJson.fetch(self, "https://%s/api/v1/videos/%s" % [host, uuid.uri_encode()])
	if not res.ok:
		return res
	var video: Dictionary = res.data
	if video.get("nsfw", false):
		return {"ok": false, "error": "This video is marked sensitive."}
	for playlist in video.get("streamingPlaylists", []):
		if playlist.get("playlistUrl", "") != "":
			return {"ok": true, "url": playlist["playlistUrl"]}
	var files: Array = video.get("files", [])
	files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("resolution", {}).get("id", 0) > b.get("resolution", {}).get("id", 0))
	for file in files:
		if file.get("fileUrl", "") != "":
			return {"ok": true, "url": file["fileUrl"]}
	return {"ok": false, "error": "This PeerTube video has no playable stream."}


static func _is_hostname(host: String) -> bool:
	return RegEx.create_from_string("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+(:[0-9]{1,5})?$").search(host.to_lower()) != null


static func _is_uuid(value: String) -> bool:
	return RegEx.create_from_string("^[0-9a-fA-F-]{36}$").search(value) != null


func _config(key: String) -> Variant:
	return ExtensionRegistry.config_value(settings, id, key)
