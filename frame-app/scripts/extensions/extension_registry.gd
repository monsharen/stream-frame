class_name ExtensionRegistry
## Every source of video is an extension. Each can be enabled or disabled,
## may have its own configuration, and reports a status: available, or not
## (with why, and what to do about it).
##
## Local extensions play on the device. Remote ones play in Chrome on the PC
## (for DRM-protected services) and stream back; they share the PC
## connection, and need the host agent to be reachable and to support them.
##
## build() returns one Dictionary per extension:
##   id, name, kind ("local" | "remote"), color, description,
##   enabled, default_enabled, config: Array of field dicts {key, label, placeholder, default},
##   available: bool, status: short label, problem: bool (something is wrong,
##   as opposed to merely not ready yet), reason, steps: Array[String],
##   actions: Array of "pc" | "retry" | "demo" | "configure".

enum Host { NOT_CONFIGURED, CONNECTING, OFFLINE, ONLINE, DEMO }

const DEFINITIONS := [
	{
		"id": "open-movies", "name": "Open movies", "kind": "local", "color": "e87d0d",
		"default_enabled": true, "ready": true,
		"description": "The Blender Studio open movies, free to watch, streamed straight to this device. No PC needed.",
		"config": [
			{"key": "player_command", "label": "Video player", "placeholder": "mpv --fs",
				"default": "mpv --fs --force-window=immediate",
				"help": "Plays titles until video plays on the 3D screen itself. The video URL is added at the end."},
		],
	},
	{
		"id": "jellyfin", "name": "Jellyfin", "kind": "local", "color": "aa5cc3",
		"default_enabled": false, "ready": false,
		"description": "Your own films and series from a Jellyfin server, played on this device in full quality, including 4K, HDR and 3D.",
		"steps": [
			"Coming soon: on-device Jellyfin support is the next big source on the roadmap.",
			"Meanwhile, set up a Jellyfin server on a PC or NAS (jellyfin.org) so your library is ready.",
		],
	},
	{
		"id": "youtube", "name": "YouTube", "kind": "local", "color": "cc0000",
		"default_enabled": false, "ready": false,
		"description": "YouTube doesn't use DRM for most videos, so it can play on this device without the PC.",
		"steps": ["Coming soon: YouTube will play through YouTube's own embedded player, as its terms require."],
	},
	{
		"id": "netflix", "name": "Netflix", "kind": "remote", "color": "e50914", "default_enabled": true,
		"description": "Netflix, played in Chrome on your PC and streamed to this device.",
	},
	{
		"id": "disney", "name": "Disney+", "kind": "remote", "color": "113ccf", "default_enabled": false,
		"description": "Disney+, played in Chrome on your PC and streamed to this device.",
	},
	{
		"id": "max", "name": "Max", "kind": "remote", "color": "002be7", "default_enabled": false,
		"description": "Max, played in Chrome on your PC and streamed to this device.",
	},
	{
		"id": "prime", "name": "Prime Video", "kind": "remote", "color": "00a8e1", "default_enabled": false,
		"description": "Prime Video, played in Chrome on your PC and streamed to this device.",
	},
	{
		"id": "demo", "name": "Demo films (via PC)", "kind": "remote", "color": "1f8a70", "default_enabled": true,
		"description": "DRM-free open movies played through your PC: a quick way to check the whole PC setup works.",
	},
]

const PC_SETUP_STEPS := [
	"On your Windows PC: install Node, Google Chrome and Sunshine, and add a virtual display.",
	"Start the host agent (host-agent: npm start) and note the URL and token it prints.",
	"Pair Moonlight on this device with Sunshine on the PC.",
	"Open the PC connection (Extensions app) and enter the agent URL and token.",
]


static func build(settings: Settings, host: Host, agent_services: Array) -> Array:
	var definitions := DEFINITIONS.duplicate(true)
	# Services the agent offers that we don't know yet become extensions too,
	# so a new adapter on the PC shows up without an app update.
	for service in agent_services:
		if not definitions.any(func(d: Dictionary) -> bool: return d["id"] == service["id"]):
			definitions.append({
				"id": service["id"], "name": service["name"], "kind": "remote", "color": "5b7db1",
				"default_enabled": true,
				"description": "%s, offered by the host agent on your PC." % service["name"],
			})
	var offered := agent_services.map(func(s: Dictionary) -> String: return s["id"])
	var extensions := []
	for definition in definitions:
		var extension := {
			"id": definition["id"], "name": definition["name"], "kind": definition["kind"],
			"color": Color(definition["color"]), "description": definition["description"],
			"default_enabled": definition["default_enabled"],
			"enabled": settings.is_extension_enabled(definition["id"], definition["default_enabled"]),
			"config": definition.get("config", []),
			"problem": false, "steps": [], "actions": [],
		}
		if definition["kind"] == "local":
			_local_status(extension, definition)
		else:
			_remote_status(extension, host, settings.agent_url, definition["id"] in offered)
		extensions.append(extension)
	return extensions


static func enabled(extensions: Array) -> Array:
	return extensions.filter(func(e: Dictionary) -> bool: return e["enabled"])


static func by_id(extensions: Array, id: String) -> Dictionary:
	for extension in extensions:
		if extension["id"] == id:
			return extension
	return {}


## A config value, falling back to the field's default.
static func config_value(settings: Settings, extension_id: String, key: String) -> Variant:
	for definition in DEFINITIONS:
		if definition["id"] == extension_id:
			for field in definition.get("config", []):
				if field["key"] == key:
					return settings.extension_value(extension_id, key, field["default"])
	return settings.extension_value(extension_id, key, null)


static func _local_status(extension: Dictionary, definition: Dictionary) -> void:
	extension["available"] = definition["ready"]
	extension["status"] = "On this device" if definition["ready"] else "Coming soon"
	extension["reason"] = definition["description"]
	extension["steps"] = definition.get("steps", [])
	if not definition.get("config", []).is_empty():
		extension["actions"] = ["configure"]


static func _remote_status(extension: Dictionary, host: Host, host_url: String, offered: bool) -> void:
	var name: String = extension["name"]
	extension["available"] = offered and host in [Host.ONLINE, Host.DEMO]
	if extension["available"]:
		extension["status"] = "On your PC"
		extension["reason"] = extension["description"]
		return
	match host:
		Host.NOT_CONFIGURED:
			extension["status"] = "Set up your PC"
			extension["problem"] = true
			extension["reason"] = "%s protects its videos with DRM that only plays in full quality in Chrome on a PC. Stream Frame plays it there and streams the picture to this device, so it needs your PC set up first." % name
			extension["steps"] = PC_SETUP_STEPS
			extension["actions"] = ["pc", "demo"]
		Host.CONNECTING:
			extension["status"] = "Connecting…"
			extension["reason"] = "Contacting the host agent on your PC at %s." % host_url
			extension["actions"] = ["retry"]
		Host.OFFLINE:
			extension["status"] = "PC offline"
			extension["problem"] = true
			extension["reason"] = "Couldn't reach the host agent on your PC at %s." % host_url
			extension["steps"] = [
				"Check the PC is switched on and awake (not sleeping).",
				"On the PC, start the host agent: open a terminal in host-agent and run npm start.",
				"Check the PC and this device are on the same network, and the PC's firewall allows port 8787.",
				"Check the agent URL and token in the PC connection match what the agent printed.",
			]
			extension["actions"] = ["retry", "pc"]
		Host.DEMO:
			extension["status"] = "Needs your PC"
			extension["reason"] = "This is the offline demo, so there's no PC to play %s on. With a PC set up, it plays in Chrome there and streams to this device." % name
			extension["steps"] = PC_SETUP_STEPS
			extension["actions"] = ["pc"]
		Host.ONLINE:
			extension["status"] = "Coming soon"
			extension["reason"] = "Your PC's host agent doesn't support %s yet." % name
			extension["steps"] = [
				"Each service needs an adapter in the host agent (host-agent/src/services/). Contributions welcome.",
			]
