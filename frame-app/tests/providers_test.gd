extends Node
## On-device providers, headless. Unit checks of the security guards, then
## LIVE checks against the real services (needs internet): each catalog
## loads with titles and thumbnails, and a title resolves to an https URL
## that really serves video.
## Run: godot --headless --path . res://tests/providers_test.tscn

const MEDIA_TYPES := ["video/", "application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl"]


func _ready() -> void:
	var failure: Variant = await _run()
	failure = _as_failure(failure)
	if failure == "":
		print("PROVIDERS TEST PASS")
		get_tree().quit(0)
	else:
		printerr("PROVIDERS TEST FAIL: " + failure)
		get_tree().quit(1)


func _run() -> Variant:
	# --- Guards (no network) ---
	var args := LocalPlayer.build_args(LocalPlayer.DEFAULT_COMMAND, "A ${path} film", "https://x.test/v.mp4")
	if Array(args) != ["mpv", "--fs", "--force-window=immediate", "--no-ytdl", "--title=A {path} film", "--", "https://x.test/v.mp4"]:
		return "default player args wrong: %s" % [args]
	if Array(LocalPlayer.build_args("vlc --fullscreen", "T", "https://x.test/v")) != ["vlc", "--fullscreen", "--", "https://x.test/v"]:
		return "a command without {url} should get '-- <url>' appended"
	for bad in ["http://x.test/v.mp4", "file:///etc/passwd", "--script=x.lua", "https://x.test/a\nb", ""]:
		if VideoProvider.safe_media_url(bad) != "":
			return "safe_media_url should reject %s" % bad.c_escape()
	if VideoProvider.safe_media_url("https://x.test/a b.mp4") != "https://x.test/a%20b.mp4":
		return "safe_media_url should encode spaces"
	for host in ["evil.example/x", "a@b.example", "localhost", "-x.example", "x.example:99999999"]:
		if PeerTubeProvider._is_hostname(host):
			return "PeerTube host check should reject %s" % host
	if not PeerTubeProvider._is_hostname("videos.trom.tf") or not PeerTubeProvider._is_uuid("dc563059-878f-4dab-af01-1984b4df26e9"):
		return "PeerTube checks should accept a real host and uuid"
	print("ok: player args, https-only URLs and PeerTube host/id checks")

	# --- Live services ---
	var settings := Settings.new()
	for provider: VideoProvider in [OpenMoviesProvider.new(), InternetArchiveProvider.new(), NasaProvider.new(), PeerTubeProvider.new()]:
		provider.settings = settings
		add_child(provider)
		var unknown: Dictionary = await provider.resolve("https://evil.example/not-issued.mp4")
		if unknown.ok:
			return "%s resolved a title it never issued" % provider.id
		var started := Time.get_ticks_msec()
		var res: Dictionary = await provider.catalog()
		if not res.ok:
			return "%s catalog failed: %s" % [provider.id, res.error]
		var rows: Array = res.data["rows"]
		var count := 0
		var with_images := 0
		for row in rows:
			for item in row["items"]:
				count += 1
				with_images += 1 if str(item.get("image", "")).begins_with("https://") else 0
		if rows.size() < 3 or count < 15:
			return "%s catalog too small: %d rows, %d titles" % [provider.id, rows.size(), count]
		if with_images < count * 0.8:
			return "%s: most titles should have an https thumbnail (%d/%d)" % [provider.id, with_images, count]
		# Resolve the first title that resolves (an odd item may lack a video).
		var played := ""
		for row in rows:
			for item in row["items"].slice(0, 3):
				var resolved: Dictionary = await provider.resolve(item["watchUrl"])
				if resolved.ok:
					var check := await _check_media(resolved.url)
					if check != "":
						return "%s: '%s' resolved to %s but %s" % [provider.id, item["title"], resolved.url, check]
					played = item["title"]
					break
			if played != "":
				break
		if played == "":
			return "%s: no title resolved to playable video" % provider.id
		print("ok: %-16s %d rows, %d titles in %.1fs; '%s' resolves to video" % [
			provider.id, rows.size(), count, (Time.get_ticks_msec() - started) / 1000.0, played])
	return ""


## "" if `url` answers with a video/HLS content type; otherwise why not.
func _check_media(url: String) -> String:
	var http := HTTPRequest.new()
	http.body_size_limit = 64 * 1024  # just the start; we only want the headers
	http.timeout = 20.0
	add_child(http)
	http.request(url, PackedStringArray(["Range: bytes=0-1023"]))
	var result: Array = await http.request_completed
	http.queue_free()
	var status: int = result[1]
	var content_type := ""
	for header: String in result[2]:
		if header.to_lower().begins_with("content-type:"):
			content_type = header.substr(13).strip_edges().to_lower()
	if status != 200 and status != 206:
		return "it answered HTTP %d" % status
	if not MEDIA_TYPES.any(func(t: String) -> bool: return content_type.begins_with(t)):
		return "its content type is '%s'" % content_type
	return ""


static func _as_failure(result: Variant) -> String:
	return result if result is String else "the test hit a script error (see the log above)"
