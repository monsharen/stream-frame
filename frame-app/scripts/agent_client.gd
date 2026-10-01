class_name AgentClient
extends Node
## Talks to the host agent: REST for commands and catalogs, a WebSocket for
## live playback state. Reconnects the WebSocket on its own.

signal state_changed(state: Dictionary)
signal connection_changed(connected: bool)

const RECONNECT_SECONDS := 2.0
## Catalog refreshes scrape the service's site and can take a while.
const REQUEST_TIMEOUT := 90.0

var state: Dictionary = {"status": "idle", "position": 0.0, "duration": 0.0}
var connected := false

var _base_url := ""
var _token := ""
var _ws := WebSocketPeer.new()
var _reconnect_at := 0.0


func configure(base_url: String, token: String) -> void:
	_base_url = Settings.normalize_url(base_url)
	_token = token
	_ws.close()
	_reconnect_at = 0.0


## Resolves to {ok: true, data} or {ok: false, error}.
func request(method: HTTPClient.Method, path: String, body: Variant = null) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if _token != "":
		headers.append("Authorization: Bearer " + _token)
	var payload := "" if body == null else JSON.stringify(body)
	var err := http.request(_base_url + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "Could not send request (%s)" % error_string(err)}

	var result: Array = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "Cannot reach the host agent at %s" % _base_url}
	var status: int = result[1]
	var data: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if status >= 400:
		var message: String = data.get("error", "") if data is Dictionary else ""
		return {"ok": false, "error": message if message != "" else "Host agent returned HTTP %d" % status}
	return {"ok": true, "data": data}


func control(action: String, value: Variant = null) -> Dictionary:
	var body := {"action": action}
	if value != null:
		body["value"] = value
	return await request(HTTPClient.METHOD_POST, "/api/control", body)


func _process(_delta: float) -> void:
	if _base_url == "":
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not connected:
				_set_connected(true)
			while _ws.get_available_packet_count() > 0:
				var message: Variant = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
				if message is Dictionary and message.get("type") == "state":
					state = message["state"]
					state_changed.emit(state)
		WebSocketPeer.STATE_CLOSED:
			if connected:
				_set_connected(false)
			var now := Time.get_ticks_msec() / 1000.0
			if now >= _reconnect_at:
				_reconnect_at = now + RECONNECT_SECONDS
				_ws = WebSocketPeer.new()
				_ws.connect_to_url(_ws_url())


func _ws_url() -> String:
	var url := _base_url.replace("https://", "wss://").replace("http://", "ws://") + "/ws"
	if _token != "":
		url += "?token=" + _token.uri_encode()
	return url


func _set_connected(value: bool) -> void:
	connected = value
	connection_changed.emit(value)
