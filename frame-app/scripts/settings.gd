class_name Settings
extends RefCounted
## Persistent app settings: the PC connection (shared by all PC extensions),
## the on-device player (shared by all on-device ones), which extensions are
## enabled, and each extension's own configuration.
## Any top-level key can be overridden with a STREAM_FRAME_<KEY>
## environment variable, and STREAM_FRAME_SETTINGS_PATH moves the file, which
## is handy for development and tests.

const DEFAULT_PATH := "user://settings.cfg"
const KEYS := ["agent_url", "token", "sunshine_host", "sunshine_app", "moonlight_command", "player_command", "last_source"]

var agent_url := ""
var token := ""
## Empty means "same host as the agent", which is the usual setup.
var sunshine_host := ""
var sunshine_app := "Desktop"
## Split on spaces, so e.g. "flatpak run com.moonlight_stream.Moonlight" works.
var moonlight_command := "moonlight"
## Plays on-device titles until video plays on the 3D screen itself (see
## LocalPlayer.DEFAULT_COMMAND for the placeholders).
var player_command := LocalPlayer.DEFAULT_COMMAND
var last_source := ""

## Extension id -> enabled, for extensions the user has switched; the rest
## use their default.
var enabled_extensions: Dictionary = {}
## Extension id -> {config key: value}.
var extension_config: Dictionary = {}


static func load_or_default() -> Settings:
	var settings := Settings.new()
	var cfg := ConfigFile.new()
	if cfg.load(_path()) == OK:
		for key in KEYS:
			settings.set(key, cfg.get_value("settings", key, settings.get(key)))
		if cfg.has_section("extensions"):
			for id in cfg.get_section_keys("extensions"):
				settings.enabled_extensions[id] = cfg.get_value("extensions", id)
		for section in cfg.get_sections():
			if section.begins_with("extension:"):
				var values := {}
				for key in cfg.get_section_keys(section):
					values[key] = cfg.get_value(section, key)
				settings.extension_config[section.trim_prefix("extension:")] = values
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
	for id in enabled_extensions:
		cfg.set_value("extensions", id, enabled_extensions[id])
	for id in extension_config:
		for key in extension_config[id]:
			cfg.set_value("extension:" + id, key, extension_config[id][key])
	cfg.save(_path())


func is_extension_enabled(id: String, default: bool) -> bool:
	return enabled_extensions.get(id, default)


func set_extension_enabled(id: String, on: bool) -> void:
	enabled_extensions[id] = on


func extension_value(id: String, key: String, default: Variant) -> Variant:
	return extension_config.get(id, {}).get(key, default)


func set_extension_value(id: String, key: String, value: Variant) -> void:
	if not extension_config.has(id):
		extension_config[id] = {}
	extension_config[id][key] = value


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
