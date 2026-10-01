extends Node
## Extensions and offline demo, headless, no host agent running.
## Pass 1 (unconfigured): the home lists the enabled extensions; PC ones
##   report a problem with what to do next; the Extensions app enables,
##   disables and configures extensions (saved); Netflix's info page offers
##   the offline demo.
## Pass 2 (offline demo): the demo PC source works end to end (simulated);
##   the on-device Open movies source plays in the external player (a fake
##   here); saving real settings leaves the demo.
## Pass 3: back out of the demo.
## The on-device player is always tests/fake_moonlight.sh here.
## Run: STREAM_FRAME_SETTINGS_PATH=/tmp/x.cfg STREAM_FRAME_DEMO_LATENCY=0.3 \
##   godot --headless --path . res://tests/offline_test.tscn

const MainScript := preload("res://scripts/main.gd")
const TIMEOUT := 15.0

var app: Control


func _ready() -> void:
	# This test covers the external player path (with a fake player); the
	# built-in one has its own test.
	var settings := Settings.load_or_default()
	settings.set_extension_value("device", "builtin_player", false)
	settings.save()
	app = load("res://main.tscn").instantiate()
	add_child(app)
	# Never launch a real video player from a test.
	app.local.command = "bash " + ProjectSettings.globalize_path("res://tests/fake_moonlight.sh")
	var failure: Variant
	if MainScript.offline_override == null:
		failure = await _unconfigured_pass()
		failure = _as_failure(failure)
	elif MainScript.offline_override == true:
		failure = await _demo_pass()
		failure = _as_failure(failure)
	else:
		failure = "" if not app.offline and not (app.agent is OfflineAgent) else "saving settings did not leave the demo"
		if failure == "":
			print("ok: 'Save and connect' left the offline demo")
	if failure == "reloading":
		return
	if failure == "":
		print("OFFLINE TEST PASS")
		MainScript.offline_override = null
		get_tree().quit(0)
	else:
		printerr("OFFLINE TEST FAIL: " + failure)
		get_tree().quit(1)


func _unconfigured_pass() -> Variant:
	if app.current_view != "browse":
		return "the app should open on the home, not %s" % app.current_view
	var home_ids: Array = app.sources.map(func(s: Dictionary) -> String: return s["id"])
	if home_ids != ["open-movies", "internet-archive", "nasa", "peertube", "netflix", "demo", "extensions"]:
		return "the home should show the enabled extensions and the Extensions app, got %s" % [home_ids]
	var netflix := _source("netflix")
	if not _source("open-movies").get("available") or netflix.get("available", true):
		return "unconfigured: on-device extensions should be available, PC ones not"
	if netflix["status"] != "Set up your PC" or not netflix["problem"] or not "pc" in netflix["actions"]:
		return "Netflix should report a problem (PC not set up) and offer the PC connection: %s" % netflix
	if _cards("SourceCard").size() != app.sources.size():
		return "the home should show a card per entry (%d cards, %d entries: %s)" % [_cards("SourceCard").size(), app.sources.size(),
			_cards("SourceCard").map(func(c: SourceCard) -> String: return c.source["id"])]
	print("ok: home shows enabled extensions + Extensions app; Netflix reports '%s'" % netflix["status"])

	# Launching an extension with a problem explains what to do next.
	app.browse.source_chosen.emit(netflix)
	if app.current_view != "info" or app.info_view._title.text != "Netflix":
		return "launching an extension with a problem should show its info page"
	if _button(app.info_view, "PC connection") == null or _button(app.info_view, "Try the offline demo") == null:
		return "Netflix's info page should offer the PC connection and the offline demo"
	_button(app.info_view, "PC connection").pressed.emit()
	if app.current_view != "extensions" or app.extensions_view._selected != ExtensionsView.PC:
		return "'PC connection' should open the Extensions app on the PC connection"
	print("ok: Netflix info page -> PC connection in the Extensions app")

	# The Extensions app: enable, disable, configure; all saved.
	app.show_home()
	app.browse.source_chosen.emit(_entry("extensions"))
	if app.current_view != "extensions":
		return "the Extensions tile should open the Extensions app"
	var disney_toggle: Button = _toggle("Disney+")
	if disney_toggle == null or disney_toggle.button_pressed:
		return "Disney+ should be listed, switched off"
	disney_toggle.toggled.emit(true)
	_toggle("Open movies").toggled.emit(false)
	app.extensions_view.back_requested.emit()
	if _entry("disney").is_empty() or not _entry("open-movies").is_empty():
		return "toggles should add Disney+ to the home and remove Open movies"
	if _entry("disney")["available"]:
		return "Disney+ should be greyed out (no PC)"
	print("ok: switching extensions on/off updates the home")
	app.open_extensions("open-movies")
	_toggle("Open movies").toggled.emit(true)
	# Per-extension configuration (PeerTube) and the shared on-device player.
	app.extensions_view._select("peertube")
	app.extensions_view._config_fields["topics"].text = "space, ocean"
	_button(app.extensions_view, "Save").pressed.emit()
	app.extensions_view._select(ExtensionsView.DEVICE)
	app.extensions_view._config_fields["player_command"].text = "my-player --fullscreen {url}"
	_button(app.extensions_view, "Save").pressed.emit()
	if app.local.command != "my-player --fullscreen {url}":
		return "saving the on-device player should apply it"
	var saved := Settings.load_or_default()
	if not saved.is_extension_enabled("disney", false) or not saved.is_extension_enabled("open-movies", false) \
			or ExtensionRegistry.config_value(saved, "peertube", "topics") != "space, ocean" \
			or saved.player_command != "my-player --fullscreen {url}":
		return "extension toggles and configuration should be saved"
	app.local.command = "bash " + ProjectSettings.globalize_path("res://tests/fake_moonlight.sh")
	print("ok: configuring an extension applies and saves it")

	app.show_home()
	app.browse.source_chosen.emit(netflix)
	_button(app.info_view, "Try the offline demo").pressed.emit()
	return "reloading"


func _demo_pass() -> Variant:
	if not await _until(func() -> bool: return _source("demo").get("available", false)):
		return "in the offline demo, the demo PC source should become available"
	var netflix := _source("netflix")
	if netflix["available"] or not "offline demo" in netflix["reason"]:
		return "in the demo, Netflix should explain there's no PC: %s" % netflix
	print("ok: demo PC source available; Netflix explains the demo has no PC")

	# A PC source (simulated): catalog, play, pause, seek, stop.
	app.open_source(_source("demo"))
	if not await _until(func() -> bool: return _source_cards("demo").size() == _demo_cards()):
		return "the demo catalog did not show all %d posters" % _demo_cards()
	app.play_item(_source_cards("demo")[0].item)
	if not await _until(func() -> bool: return _status() == "playing"):
		return "simulated playback never started (status=%s)" % _status()
	if app.stream.is_running() or _button(app.player, "Show stream") != null:
		return "the offline demo must not open or offer a stream"
	app._control("toggle", null)
	if not await _until(func() -> bool: return _status() == "paused"):
		return "toggle did not pause"
	app._control("seekTo", 300.0)
	if not await _until(func() -> bool: return is_equal_approx(app.agent.state["position"], 300.0)):
		return "seek did not land"
	app._stop()
	if not await _until(func() -> bool: return _status() == "idle" and app.current_view == "browse"):
		return "stop did not return to the catalog"
	print("ok: demo PC source: catalog, play, pause, seek, stop")

	# An on-device source: plays in the external player (fake_moonlight.sh).
	app.show_home()
	app.open_source(_source("open-movies"))
	if not await _until(func() -> bool: return _source_cards("open-movies").size() == _demo_cards()):
		return "the Open movies catalog did not load"
	var item: Dictionary = _source_cards("open-movies")[1].item
	if not item["watchUrl"].begins_with("https://upload.wikimedia.org/wikipedia/commons/transcoded/"):
		return "on-device titles should play the real video files: %s" % item["watchUrl"]
	app.play_item(item)
	if not await _until(func() -> bool: return app.local.state.get("status") == "playing"):
		return "the external player never started"
	if app._playback != app.local or app.player._controls.visible:
		return "on-device playback should follow the local player and hide the app's transport controls"
	print("ok: Open movies plays '%s' in the external player" % item["title"])
	# fake_moonlight.sh exits after a few seconds: the window was closed.
	if not await _until(func() -> bool: return app.local.state.get("status") == "idle" and app.current_view == "browse"):
		return "closing the external player should return to the catalog"
	print("ok: closing the player window returns to the catalog")

	app.open_extensions(ExtensionsView.PC)
	app.extensions_view._pc_fields["agent_url"].text = "127.0.0.1:9"  # nothing listens; only the mode switch matters
	_button(app.extensions_view, "Save and connect").pressed.emit()
	return "reloading"


func _source(id: String) -> Dictionary:
	return ExtensionRegistry.by_id(app.extensions, id)


## An entry on the home (an enabled extension or an app), or {}.
func _entry(id: String) -> Dictionary:
	return ExtensionRegistry.by_id(app.sources, id)


## The On/Off switch for an extension in the Extensions app.
func _toggle(extension_name: String) -> Button:
	for toggle: Button in app.extensions_view.find_children("*", "Button", true, false):
		if toggle.toggle_mode and toggle.tooltip_text == "Show %s on the home screen" % extension_name:
			return toggle
	return null


func _status() -> String:
	return app.agent.state.get("status", "")


func _demo_cards() -> int:
	var count := 0
	for row in OfflineAgent.catalog()["rows"]:
		count += row["items"].size()
	return count


## Poster cards from one source's catalog (old cards may linger a frame
## while being freed).
func _source_cards(source_id: String) -> Array:
	return _cards("PosterCard").filter(func(c: PosterCard) -> bool:
		return not c.is_queued_for_deletion() and c.item.get("source") == source_id)


func _cards(type: String) -> Array:
	# Rebuilt views leave the old cards queued for deletion until frame end.
	return app.browse.find_children("*", type, true, false).filter(
		func(c: Node) -> bool: return not c.is_queued_for_deletion())


func _button(root: Node, text: String) -> Button:
	for b: Button in root.find_children("*", "Button", true, false):
		if b.text == text and b.visible:
			return b
	return null


func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT * 1000
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().create_timer(0.05).timeout
	return false


## A script error aborts the test coroutine, which then returns null: that
## must count as a failure, not as "no failure message".
static func _as_failure(result: Variant) -> String:
	return result if result is String else "the test hit a script error (see the log above)"
