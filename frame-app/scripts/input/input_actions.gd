class_name InputActions
## The app's input actions, what triggers them, and how that's changed.
##
## Everything the user can do with a button is a named action (Back, Play /
## pause, …), never a hard-coded key: views react to actions, and any key,
## gamepad button, mouse button or VR controller button can be bound to
## any action (Extensions → Controls). Bindings are short strings, so they
## store as plain settings:
##   key:<keycode name>     a keyboard key, e.g. "key:Escape"
##   joy:<button index>     a gamepad button (JoyButton), e.g. "joy:1" (B)
##   axis:<axis>:<+1|-1>    a gamepad stick or trigger pushed one way,
##                          e.g. "axis:2:-1" (right stick left)
##   mouse:<button index>   a mouse button, e.g. "mouse:8" (side/back)
##   xr:<button name>       a VR controller button, e.g. "xr:by_button"
##
## Pointing and clicking (gaze, controller ray, trigger, mouse) aren't
## actions: they select whatever is under the pointer.

## Settings section that holds the user's bindings (action -> Array[String]).
const SETTINGS_ID := "input"

const BACK := &"sf_back"
const SELECT := &"sf_select"
const PLAY_PAUSE := &"sf_play_pause"
const SEEK_BACK := &"sf_seek_back"
const SEEK_FORWARD := &"sf_seek_forward"
const OPTIONS := &"sf_options"
const HOME := &"sf_home"
const TURN_LEFT := &"sf_turn_left"
const TURN_RIGHT := &"sf_turn_right"
## How far a stick or trigger must go to count as pressed.
const AXIS_THRESHOLD := 0.6

## Bindings that always stay (shown locked on the Controls page): Escape
## is always Back.
const FIXED := {BACK: ["key:Escape"]}

## In the order the Controls page lists them: [action, label, default bindings].
const ACTIONS := [
	[BACK, "Back", ["key:Back", "joy:1", "mouse:8", "xr:by_button"]],
	[SELECT, "Select", ["key:Enter", "key:Kp Enter", "joy:0"]],
	[PLAY_PAUSE, "Play / pause", ["key:Space", "key:MediaPlay", "joy:2", "xr:ax_button"]],
	[SEEK_BACK, "Back 10 seconds", ["key:J", "key:MediaPrevious", "joy:9"]],
	[SEEK_FORWARD, "Forward 10 seconds", ["key:L", "key:MediaNext", "joy:10"]],
	[OPTIONS, "Viewing options", ["key:O", "joy:3", "xr:menu_button"]],
	[HOME, "Home", ["key:Home", "joy:4"]],
	[TURN_LEFT, "Turn left", ["key:Q", "axis:2:-1"]],
	[TURN_RIGHT, "Turn right", ["key:E", "axis:2:1"]],
]

const AXIS_NAMES := {
	"0:-1": "left stick left", "0:1": "left stick right", "1:-1": "left stick up", "1:1": "left stick down",
	"2:-1": "right stick left", "2:1": "right stick right", "3:-1": "right stick up", "3:1": "right stick down",
	"4:1": "left trigger", "5:1": "right trigger",
}

const JOY_NAMES := {
	0: "A", 1: "B", 2: "X", 3: "Y", 4: "View / Select", 5: "Guide", 6: "Menu / Start",
	7: "Left stick", 8: "Right stick", 9: "Left shoulder", 10: "Right shoulder",
	11: "D-pad up", 12: "D-pad down", 13: "D-pad left", 14: "D-pad right",
}
## Friendlier names for keys whose Godot names read oddly.
const KEY_NAMES := {
	"Back": "Back key", "Kp Enter": "Keypad Enter", "MediaPlay": "Media play",
	"MediaPrevious": "Media previous", "MediaNext": "Media next", "MediaStop": "Media stop",
}
const XR_NAMES := {
	"ax_button": "A / X", "by_button": "B / Y", "menu_button": "Menu",
	"grip_click": "Grip", "primary_click": "Stick press", "trigger_click": "Trigger",
}

## Godot's own UI actions follow ours, so a rebound Select presses buttons
## and a rebound Back closes popups: action -> built-in action.
const MIRRORS := {BACK: &"ui_cancel", SELECT: &"ui_accept"}

## VR button name -> action, for the current bindings (see apply()).
static var _xr: Dictionary = {}
## While the Controls page waits for a button to bind: called with the VR
## button's binding ("xr:…") instead of triggering its action.
static var xr_capture := Callable()
## Events added to the built-in actions (removed again on the next apply).
static var _mirrored: Array = []


## Sets up every action from the defaults and the user's changes. Call at
## start and after changing bindings.
static func apply(settings: Settings) -> void:
	_xr.clear()
	for pair: Array in _mirrored:
		InputMap.action_erase_event(pair[0], pair[1])
	_mirrored.clear()
	for entry in ACTIONS:
		var action: StringName = entry[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action, AXIS_THRESHOLD)
		InputMap.action_erase_events(action)
		for binding: String in fixed(action) + bindings(settings, action):
			if binding.begins_with("xr:"):
				_xr[binding.trim_prefix("xr:")] = action
				continue
			var event := to_event(binding)
			if event:
				InputMap.action_add_event(action, event)
				if MIRRORS.has(action) and not InputMap.action_has_event(MIRRORS[action], event):
					InputMap.action_add_event(MIRRORS[action], event)
					_mirrored.append([MIRRORS[action], event])


## The bindings for an action: the user's, or the defaults.
static func bindings(settings: Settings, action: StringName) -> Array:
	var saved: Variant = settings.extension_value(SETTINGS_ID, action, null) if settings else null
	return Array(saved).duplicate() if saved is Array else defaults(action)


static func fixed(action: StringName) -> Array:
	return Array(FIXED.get(action, [])).duplicate()


## The action a binding is fixed to, or &"".
static func fixed_owner(binding: String) -> StringName:
	for action: StringName in FIXED:
		if binding in FIXED[action]:
			return action
	return &""


## Binds `binding` to `action`, taking it off any other action (one press,
## one meaning). False if it's fixed to another action.
static func bind(settings: Settings, action: StringName, binding: String) -> bool:
	var owner := fixed_owner(binding)
	if owner != &"":
		return owner == action
	for entry in ACTIONS:
		var other: StringName = entry[0]
		var list := bindings(settings, other)
		if other == action:
			if not binding in list:
				list.append(binding)
				settings.set_extension_value(SETTINGS_ID, other, list)
		elif binding in list:
			list.erase(binding)
			settings.set_extension_value(SETTINGS_ID, other, list)
	settings.save()
	apply(settings)
	return true


static func unbind(settings: Settings, action: StringName, binding: String) -> void:
	var list := bindings(settings, action)
	list.erase(binding)
	set_bindings(settings, action, list)


static func defaults(action: StringName) -> Array:
	for entry in ACTIONS:
		if entry[0] == action:
			return Array(entry[2]).duplicate()  # the constant itself is read-only
	return []


static func label(action: StringName) -> String:
	for entry in ACTIONS:
		if entry[0] == action:
			return entry[1]
	return String(action)


static func set_bindings(settings: Settings, action: StringName, list: Array) -> void:
	settings.set_extension_value(SETTINGS_ID, action, list)
	settings.save()
	apply(settings)


static func reset(settings: Settings, action: StringName) -> void:
	set_bindings(settings, action, defaults(action))


## The action a VR controller button triggers, or &"".
static func for_xr_button(button: String) -> StringName:
	return _xr.get(button, &"")


## A binding for a pressed key / gamepad button / mouse button, or "" if the
## event can't be bound (motion, releases, plain left clicks…).
static func binding_for(event: InputEvent) -> String:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: Key = event.physical_keycode if event.keycode == KEY_NONE else event.keycode
		return "key:" + OS.get_keycode_string(code)
	if event is InputEventJoypadButton and event.pressed:
		return "joy:%d" % event.button_index
	if event is InputEventJoypadMotion and absf(event.axis_value) >= AXIS_THRESHOLD:
		return "axis:%d:%d" % [event.axis, signi(roundi(signf(event.axis_value)))]
	if event is InputEventMouseButton and event.pressed and event.button_index in \
			[MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
		return "mouse:%d" % event.button_index
	return ""


static func to_event(binding: String) -> InputEvent:
	var kind := binding.get_slice(":", 0)
	var value := binding.substr(kind.length() + 1)
	match kind:
		"key":
			var code := OS.find_keycode_from_string(value)
			if code == KEY_NONE:
				return null
			var key := InputEventKey.new()
			key.keycode = code
			return key
		"joy":
			var joy := InputEventJoypadButton.new()
			joy.button_index = int(value) as JoyButton
			return joy
		"axis":
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(value.get_slice(":", 0)) as JoyAxis
			motion.axis_value = float(value.get_slice(":", 1))
			return motion
		"mouse":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(value) as MouseButton
			return mouse
	return null


## How a binding reads on the Controls page, e.g. "Escape", "Gamepad B".
static func describe(binding: String) -> String:
	var kind := binding.get_slice(":", 0)
	var value := binding.substr(kind.length() + 1)
	match kind:
		"key":
			return KEY_NAMES.get(value, value)
		"joy":
			return "Gamepad " + JOY_NAMES.get(int(value), "button %s" % value)
		"mouse":
			return {"3": "Middle mouse button", "8": "Mouse back button", "9": "Mouse forward button"}.get(value, "Mouse button " + value)
		"axis":
			return "Gamepad " + AXIS_NAMES.get(value, "axis " + value)
		"xr":
			return "Controller " + XR_NAMES.get(value, value)
	return binding


## Whether `event` triggers any app action (the shell forwards those to the UI).
static func is_app_event(event: InputEvent) -> bool:
	if event is InputEventAction:
		return true
	for entry in ACTIONS:
		if InputMap.has_action(entry[0]) and event.is_action(entry[0], true):
			return true
	return false
