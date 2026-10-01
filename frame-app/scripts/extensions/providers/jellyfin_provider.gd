class_name JellyfinProvider
extends VideoProvider
## Your own library from a Jellyfin server: Jellyfin's own "Continue
## watching", one row per film library and the latest episodes of each show
## library. Titles stream directly from the server (original quality; the
## built-in player handles the formats). A server on plain http is allowed:
## it's the one the user configured (trusted_http_host).

const PER_ROW := 24
const FIELDS := "ProductionYear,RunTimeTicks,SeriesName,ParentIndexNumber,IndexNumber"

var _token := ""
var _user := ""
## Row index -> the items query it was built from (for paging).
var _row_queries := {}


func _init() -> void:
	id = "jellyfin"


func _fetch_catalog() -> Dictionary:
	var login := await _login()
	if not login.ok:
		return login
	var views: Dictionary = await HttpJson.fetch(self, _api("/Users/%s/Views" % _user), _auth())
	if not views.ok:
		return views
	var queries := [["Continue watching", "/Users/%s/Items/Resume?MediaTypes=Video" % _user]]
	for view in views.data.get("Items", []):
		match view.get("CollectionType", ""):
			"movies":
				queries.append([view["Name"], _items_query("ParentId=%s&IncludeItemTypes=Movie" % view["Id"])])
			"tvshows":
				queries.append(["Latest in " + view["Name"], _items_query("ParentId=%s&IncludeItemTypes=Episode" % view["Id"])])
	var urls := queries.map(func(q: Array) -> String: return _api(q[1] + "&Limit=%d&Fields=%s" % [PER_ROW, FIELDS]))
	var results: Array = await HttpJson.fetch_all(self, urls, _auth())
	var rows := []
	_row_queries.clear()
	for i in queries.size():
		if not results[i].ok:
			return results[i]
		var items := _items(results[i].data)
		if items.is_empty():
			continue
		_row_queries[rows.size()] = queries[i][1]
		rows.append(VideoProvider.row(queries[i][0], items))
	if rows.is_empty():
		return {"ok": false, "error": "The Jellyfin server has no films or shows this user can see."}
	return {"ok": true, "data": {"service": id, "rows": rows}}


func _search(query: String) -> Dictionary:
	var login := await _login()
	if not login.ok:
		return login
	var url := _api(_items_query("searchTerm=%s&IncludeItemTypes=Movie,Episode" % query.uri_encode())
		+ "&Limit=48&Fields=" + FIELDS)
	var res: Dictionary = await HttpJson.fetch(self, url, _auth())
	return {"ok": true, "items": _items(res.data)} if res.ok else res


func _pages_rows() -> bool:
	return true


func _more(row_index: int, page: int) -> Dictionary:
	if not _row_queries.has(row_index):
		return {"ok": true, "items": []}
	var url := _api(_row_queries[row_index] + "&Limit=%d&StartIndex=%d&Fields=%s" % [PER_ROW, page * PER_ROW, FIELDS])
	var res: Dictionary = await HttpJson.fetch(self, url, _auth())
	return {"ok": true, "items": _items(res.data)} if res.ok else res


func _resolve(watch_url: String) -> Dictionary:
	var login := await _login()
	if not login.ok:
		return login
	var item_id := watch_url.trim_prefix("jellyfin:")
	return {"ok": true, "url": _api("/Videos/%s/stream?static=true&api_key=%s" % [item_id.uri_encode(), _token])}


func _login() -> Dictionary:
	if _token != "":
		return {"ok": true}
	var server := _server()
	if server == "":
		return {"ok": false, "error": "No Jellyfin server configured (Extensions → Jellyfin)."}
	trusted_http_host = server.trim_prefix("http://").get_slice("/", 0) if server.begins_with("http://") else ""
	var res := await HttpJson.send(self, HTTPClient.METHOD_POST, server + "/Users/AuthenticateByName", _auth(),
		{"Username": str(_config("username")), "Pw": str(_config("password"))})
	if not res.ok:
		return res
	_token = res.data.get("AccessToken", "")
	_user = res.data.get("User", {}).get("Id", "")
	if _token == "" or _user == "":
		return {"ok": false, "error": "The Jellyfin server didn't accept the login."}
	return {"ok": true}


## Forget the session (e.g. after the configuration changed).
func reset() -> void:
	_token = ""
	_user = ""
	_catalog = {}


func _items(data: Dictionary) -> Array:
	var items := []
	for entry in data.get("Items", []):
		var title: String = entry.get("Name", "")
		if entry.get("Type") == "Episode":
			title = "%s · S%dE%d · %s" % [entry.get("SeriesName", ""), entry.get("ParentIndexNumber", 0),
				entry.get("IndexNumber", 0), title]
		var item := {"title": title, "image": _image(entry), "watchUrl": "jellyfin:" + str(entry.get("Id", ""))}
		if entry.has("ProductionYear"):
			item["year"] = int(entry["ProductionYear"])
		if entry.has("RunTimeTicks"):
			item["duration"] = entry["RunTimeTicks"] / 10000000.0
		items.append(item)
	return items


## Wide artwork for the 16:9 tiles: backdrop, then thumb, then the poster.
func _image(entry: Dictionary) -> String:
	var item_id: String = entry.get("Id", "")
	var kind := "Primary"
	if not entry.get("BackdropImageTags", []).is_empty():
		kind = "Backdrop"
	elif entry.get("ImageTags", {}).has("Thumb"):
		kind = "Thumb"
	return _api("/Items/%s/Images/%s?maxWidth=640&quality=85" % [item_id.uri_encode(), kind])


func _items_query(filters: String) -> String:
	return "/Users/%s/Items?Recursive=true&SortBy=DateCreated&SortOrder=Descending&%s" % [_user, filters]


func _api(path: String) -> String:
	return _server() + path


func _server() -> String:
	return Settings.normalize_url(str(_config("server_url")))


func _auth() -> Array:
	var value := 'MediaBrowser Client="Stream Frame", Device="Steam Frame", DeviceId="%s", Version="0.1"' % _device_id()
	if _token != "":
		value += ', Token="%s"' % _token
	return ["Authorization: " + value]


## A stable id for this install, as Jellyfin expects per device.
func _device_id() -> String:
	var device: String = settings.extension_value("jellyfin", "device_id", "") if settings else ""
	if device == "" and settings:
		device = "streamframe-%x" % randi()
		settings.set_extension_value("jellyfin", "device_id", device)
		settings.save()
	return device


func _config(key: String) -> Variant:
	return ExtensionRegistry.config_value(settings, id, key)
