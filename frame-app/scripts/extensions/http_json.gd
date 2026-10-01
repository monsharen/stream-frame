class_name HttpJson
## Fetches JSON documents for on-device extensions. Results are
## {ok: true, data} or {ok: false, error}.

const TIMEOUT := 20.0
const HEADERS := ["Accept: application/json", "User-Agent: StreamFrame/0.1 (+https://github.com/monsharen/stream-frame)"]


static func fetch(parent: Node, url: String, headers: Array = []) -> Dictionary:
	var results: Array = await fetch_all(parent, [url], headers)
	return results[0]


## Sends one request with a method and JSON body (e.g. a login).
static func send(parent: Node, method: HTTPClient.Method, url: String, headers: Array = [], body: Variant = null) -> Dictionary:
	var batch := _Batch.new(1)
	_start(parent, batch, 0, url, method, headers + ["Content-Type: application/json"], "" if body == null else JSON.stringify(body))
	if not batch.is_done():
		await batch.done
	return batch.results[0]


## Fetches several URLs at once; resolves to the results in the same order.
static func fetch_all(parent: Node, urls: Array, headers: Array = []) -> Array:
	var batch := _Batch.new(urls.size())
	for i in urls.size():
		_start(parent, batch, i, urls[i], HTTPClient.METHOD_GET, headers, "")
	if not batch.is_done():
		await batch.done
	return batch.results


static func _start(parent: Node, batch: _Batch, index: int, url: String, method: HTTPClient.Method, headers: Array, body: String) -> void:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	parent.add_child(http)
	# Collect via a callback, not by awaiting each request in turn: a
	# request that finishes before we get to it would be missed.
	http.request_completed.connect(func(result: int, status: int, _headers: PackedStringArray, response: PackedByteArray) -> void:
		http.queue_free()
		batch.put(index, _parse(url, result, status, response)))
	var err := http.request(url, PackedStringArray(HEADERS + headers), method, body)
	if err != OK:
		http.queue_free()
		batch.put(index, {"ok": false, "error": "Couldn't request %s (%s)" % [_host(url), error_string(err)]})


static func _parse(url: String, result: int, status: int, body: PackedByteArray) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "Couldn't reach %s. Is this device online?" % _host(url)}
	if status == 401 or status == 403:
		return {"ok": false, "error": "%s refused the login (HTTP %d). Check the user name and password." % [_host(url), status]}
	if status >= 400:
		return {"ok": false, "error": "%s answered HTTP %d" % [_host(url), status]}
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if data == null:
		return {"ok": false, "error": "%s sent something that isn't JSON" % _host(url)}
	return {"ok": true, "data": data}


static func _host(url: String) -> String:
	return url.get_slice("://", 1).get_slice("/", 0)


class _Batch:
	extends RefCounted

	signal done

	var results: Array = []
	var _pending: int

	func _init(count: int) -> void:
		results.resize(count)
		_pending = count

	func put(index: int, result: Dictionary) -> void:
		results[index] = result
		_pending -= 1
		if _pending == 0:
			done.emit()

	func is_done() -> bool:
		return _pending <= 0
