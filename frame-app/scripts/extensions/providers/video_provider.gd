class_name VideoProvider
extends Node
## The source behind one on-device extension: builds its catalog, searches
## it, pages in more titles as a row is scrolled to its end, and turns a
## title's watch URL into a playable media URL.
##
## Catalog items: {title, image, watchUrl} plus, where known, year and
## duration (seconds), used for sorting and filtering.
##
## Catalog data comes from third-party APIs (and anyone can run a PeerTube
## instance), so the media URLs handed to the player are untrusted input:
## resolve() only accepts titles this provider issued, and only https URLs
## (plain http only for `trusted_http_host`: a server the user configured,
## e.g. Jellyfin on the home network).

## Matches the extension id.
var id := ""
var settings: Settings
var trusted_http_host := ""

var _catalog: Dictionary = {}
## Watch URLs this provider handed out (catalog, search, more).
var _issued := {}
## Row index -> next page to fetch; absent once a row is exhausted.
var _next_page := {}


## Resolves to {ok, data: catalog} or {ok: false, error}. Cached until refresh.
func catalog(refresh := false) -> Dictionary:
	if _catalog.is_empty() or refresh:
		var res: Dictionary = await _fetch_catalog()
		if not res.ok:
			return res
		_catalog = res.data
		_next_page.clear()
		for i in _catalog["rows"].size():
			_issue(_catalog["rows"][i]["items"])
			if _pages_rows():
				_next_page[i] = 1
	return {"ok": true, "data": _catalog.duplicate(true)}


## Resolves to {ok, data: {service, rows: [{title: "Results for …", items}]}}.
func search(query: String) -> Dictionary:
	query = query.strip_edges()
	if query == "":
		return {"ok": false, "error": "Type something to search for."}
	var res: Dictionary = await _search(query)
	if not res.ok:
		return res
	_issue(res.items)
	return {"ok": true, "data": {"service": id, "rows": [{"title": "Results for “%s”" % query, "items": res.items}]}}


## More titles for a catalog row: {ok, data: {items, done}}.
func more(row_index: int) -> Dictionary:
	if not _next_page.has(row_index):
		return {"ok": true, "data": {"items": [], "done": true}}
	var page: int = _next_page[row_index]
	var res: Dictionary = await _more(row_index, page)
	if not res.ok:
		return res
	_issue(res.items)
	if res.items.is_empty():
		_next_page.erase(row_index)
	else:
		_next_page[row_index] = page + 1
		_catalog["rows"][row_index]["items"].append_array(res.items)
	return {"ok": true, "data": {"items": res.items, "done": res.items.is_empty()}}


## Resolves to {ok, url} (a playable URL) or {ok: false, error}.
func resolve(watch_url: String) -> Dictionary:
	if not _issued.has(watch_url):
		return {"ok": false, "error": "Unknown title"}
	var res: Dictionary = await _resolve(watch_url)
	if not res.ok:
		return res
	var url := acceptable_url(res.url)
	if url == "":
		return {"ok": false, "error": "The source returned a video address that isn't https; not playing it."}
	return {"ok": true, "url": url}


## https, or http from the trusted host; spaces encoded. "" if unacceptable.
func acceptable_url(url: String) -> String:
	var safe := safe_media_url(url)
	if safe != "":
		return safe
	url = url.strip_edges().replace(" ", "%20")
	if trusted_http_host != "" and url.begins_with("http://") and not url.contains("\n") \
			and url.trim_prefix("http://").get_slice("/", 0) == trusted_http_host:
		return url
	return ""


# --- For subclasses ---

## {ok, data: {rows: [{title, items}]}}.
func _fetch_catalog() -> Dictionary:
	return {"ok": false, "error": "Not implemented"}


## {ok, items}. Default: titles in the loaded catalog containing the query.
func _search(query: String) -> Dictionary:
	var res: Dictionary = await catalog()
	if not res.ok:
		return res
	var seen := {}
	var items := []
	for row in res.data["rows"]:
		for item in row["items"]:
			if item["title"].to_lower().contains(query.to_lower()) and not seen.has(item["watchUrl"]):
				seen[item["watchUrl"]] = true
				items.append(item)
	return {"ok": true, "items": items}


## Whether catalog rows can page in more titles (see _more).
func _pages_rows() -> bool:
	return false


## {ok, items} for page `page` (1 = the second page) of row `row_index`.
func _more(_row_index: int, _page: int) -> Dictionary:
	return {"ok": true, "items": []}


## {ok, url} for an issued watch URL.
func _resolve(_watch_url: String) -> Dictionary:
	return {"ok": false, "error": "Not implemented"}


## A lighter version (e.g. lower resolution) of a media URL this provider
## resolved, for devices that can't keep up with the full one; "" if there
## is none. The player switches to it when it has to decode in software
## and starts dropping frames.
func lighter_url(_url: String) -> String:
	return ""


func _issue(items: Array) -> void:
	for item in items:
		_issued[item["watchUrl"]] = true


## https only; spaces encoded. "" if unacceptable.
static func safe_media_url(url: String) -> String:
	url = url.strip_edges().replace(" ", "%20")
	return url if url.begins_with("https://") and not url.contains("\n") else ""


static func row(title: String, items: Array) -> Dictionary:
	return {"title": title, "items": items.filter(func(i: Dictionary) -> bool: return i["watchUrl"] != "")}
