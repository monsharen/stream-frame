class_name VideoProvider
extends Node
## The source behind one on-device extension: builds its catalog and turns
## a title's watch URL into a playable media URL.
##
## Catalog data comes from third-party APIs (and anyone can run a PeerTube
## instance), so the media URLs handed to the player are untrusted input:
## resolve() only accepts titles this provider issued, and only https URLs.

## Matches the extension id.
var id := ""
var settings: Settings

var _catalog: Dictionary = {}
## Watch URLs this provider handed out in its catalog.
var _issued := {}


## Resolves to {ok, data: catalog} or {ok: false, error}. Cached until refresh.
func catalog(refresh := false) -> Dictionary:
	if _catalog.is_empty() or refresh:
		var res: Dictionary = await _fetch_catalog()
		if not res.ok:
			return res
		_catalog = res.data
		for row in _catalog["rows"]:
			for item in row["items"]:
				_issued[item["watchUrl"]] = true
	return {"ok": true, "data": _catalog.duplicate(true)}


## Resolves to {ok, url} (an https media URL) or {ok: false, error}.
func resolve(watch_url: String) -> Dictionary:
	if not _issued.has(watch_url):
		return {"ok": false, "error": "Unknown title"}
	var res: Dictionary = await _resolve(watch_url)
	if not res.ok:
		return res
	var url := safe_media_url(res.url)
	if url == "":
		return {"ok": false, "error": "The source returned a video address that isn't https; not playing it."}
	return {"ok": true, "url": url}


## Override: {ok, data: {rows: [{title, items: [{title, image, watchUrl}]}]}}.
func _fetch_catalog() -> Dictionary:
	return {"ok": false, "error": "Not implemented"}


## Override: {ok, url} for an issued watch URL.
func _resolve(_watch_url: String) -> Dictionary:
	return {"ok": false, "error": "Not implemented"}


## https only; spaces encoded. "" if unacceptable.
static func safe_media_url(url: String) -> String:
	url = url.strip_edges().replace(" ", "%20")
	return url if url.begins_with("https://") and not url.contains("\n") else ""


static func row(title: String, items: Array) -> Dictionary:
	return {"title": title, "items": items.filter(func(i: Dictionary) -> bool: return i["watchUrl"] != "")}
