class_name Settings
extends RefCounted
## Persistent app settings. Any key can be overridden with a STREAM_FRAME_<KEY>
## environment variable, and STREAM_FRAME_SETTINGS_PATH moves the file, which is
## handy for development and tests.

const DEFAULT_PATH := "user://settings.cfg"
const KEYS := ["agent_url", "token", "sunshine_host", "sunshine_app", "moonlight_command", "last_service"]

var agent_url := ""
var token := ""
## Empty means "same host as the agent", which is the usual setup.
var sunshine_host := ""
var sunshine_app := "Desktop"
## Split on spaces, so e.g. "flatpak run com.moonlight_stream.Moonlight" works.
var moonlight_command := "moonlight"
var last_service := ""


static func load_or_default() -> Settings:
	var settings := Settings.new()
	var cfg := ConfigFile.new()
	if cfg.load(_path()) == OK:
		for key in KEYS:
			settings.set(key, cfg.get_value("settings", key, settings.get(key)))
	for key in KEYS:
		var value := OS.get_environment("STREAM_FRAME_" + key.to_upper())
		if value != "":
			settings.set(key, value)
	settings.agent_url = normalize_url(settings.agent_url)
	return settings


func save() -> void:
	agent_url = normalize_url(agent_url)
	var cfg := ConfigFile.new()
	for key in KEYS:
		cfg.set_value("settings", key, get(key))
	cfg.save(_path())


static func _path() -> String:
	var override := OS.get_environment("STREAM_FRAME_SETTINGS_PATH")
	return override if override != "" else DEFAULT_PATH


func is_configured() -> bool:
	return agent_url != ""


func stream_host() -> String:
	if sunshine_host != "":
		return sunshine_host
	return host_of(agent_url)


## "192.168.1.20:8787" -> "http://192.168.1.20:8787"; trailing slashes dropped.
static func normalize_url(url: String) -> String:
	url = url.strip_edges().trim_suffix("/")
	if url != "" and not url.contains("://"):
		url = "http://" + url
	return url


## "http://192.168.1.20:8787/x" -> "192.168.1.20"; "http://[fe80::1]:8787" -> "[fe80::1]".
static func host_of(url: String) -> String:
	var authority := normalize_url(url).get_slice("://", 1).get_slice("/", 0)
	if authority.begins_with("["):
		return authority.substr(0, authority.find("]") + 1)
	return authority.get_slice(":", 0)
