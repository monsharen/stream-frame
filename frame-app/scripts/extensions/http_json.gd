class_name HttpJson
## Fetches JSON documents for on-device extensions. Results are
## {ok: true, data} or {ok: false, error}.

const TIMEOUT := 20.0
const HEADERS := ["Accept: application/json", "User-Agent: StreamFrame/0.1 (+https://github.com/monsharen/stream-frame)"]


static func fetch(parent: Node, url: String) -> Dictionary:
	var results: Array = await fetch_all(parent, [url])
	return results[0]


## Fetches several URLs at once; resolves to the results in the same order.
static func fetch_all(parent: Node, urls: Array) -> Array:
	var batch := _Batch.new(urls.size())
	for i in urls.size():
		var http := HTTPRequest.new()
		http.timeout = TIMEOUT
		parent.add_child(http)
		# Collect via a callback, not by awaiting each request in turn: a
		# request that finishes before we get to it would be missed.
		http.request_completed.connect(func(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			batch.put(i, _parse(urls[i], result, status, body)))
		var err := http.request(urls[i], PackedStringArray(HEADERS))
		if err != OK:
			http.queue_free()
			batch.put(i, {"ok": false, "error": "Couldn't request %s (%s)" % [_host(urls[i]), error_string(err)]})
	if not batch.is_done():
		await batch.done
	return batch.results


static func _parse(url: String, result: int, status: int, body: PackedByteArray) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "Couldn't reach %s. Is this device online?" % _host(url)}
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
