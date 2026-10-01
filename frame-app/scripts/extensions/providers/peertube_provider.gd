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
	var index := VideoProvider.safe_media_url(str(_config("search_index")).trim_suffix("/"))
	if index == "":
		return {"ok": false, "error": "The PeerTube search index must be an https:// address (Extensions → PeerTube)."}
	var topics: Array = Array(str(_config("topics")).split(",", false)).map(func(t: String) -> String: return t.strip_edges())
	topics = topics.filter(func(t: String) -> bool: return t != "")
	if topics.is_empty():
		return {"ok": false, "error": "No PeerTube topics configured (Extensions → PeerTube)."}
	var language := str(_config("language")).strip_edges()
	var urls := topics.map(func(topic: String) -> String:
		var url := "%s/api/v1/search/videos?search=%s&count=%d&nsfw=false&durationMin=%d" % [index, topic.uri_encode(), PER_ROW, MIN_SECONDS]
		if language != "":
			url += "&languageOneOf[]=" + language.uri_encode()
		return url)
	var results: Array = await HttpJson.fetch_all(self, urls)
	var rows := []
	for i in topics.size():
		if not results[i].ok:
			return results[i]
		var items := []
		for video in results[i].data.get("data", []):
			if video.get("nsfw", false):
				continue
			# Host and id end up in a URL we request: accept only plain
			# hostnames and UUIDs, so a bad index entry can't redirect it.
			var host: String = video.get("account", {}).get("host", "")
			if not _is_hostname(host) or not _is_uuid(video.get("uuid", "")):
				continue
			items.append({
				"title": video.get("name", ""),
				"image": VideoProvider.safe_media_url(video.get("thumbnailUrl", "")),
				"watchUrl": "peertube:%s/%s" % [host, video.get("uuid", "")],
			})
		rows.append(VideoProvider.row(topics[i].capitalize(), items))
	return {"ok": true, "data": {"service": id, "rows": rows}}


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
