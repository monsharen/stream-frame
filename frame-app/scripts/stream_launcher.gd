class_name StreamLauncher
extends Node
## Shows the host's video by running Moonlight as a separate fullscreen
## process. Phase 3 replaces this with a decoder embedded in the app; the
## rest of the app only depends on start/stop/is_running and `closed`.

## Emitted when the stream window goes away without us stopping it,
## i.e. the user closed Moonlight.
signal closed
## Emitted instead of `closed` when Moonlight exits almost immediately,
## which means it failed (not paired, host unreachable) rather than the user
## closing it.
signal failed(message: String)

## Exits faster than this count as a failed start.
const MIN_RUN_SECONDS := 3.0

var _pid := -1
var _host := ""
var _started_at := 0.0


func is_running() -> bool:
	return _pid > 0 and OS.is_process_running(_pid)


## Returns an error message, or "" on success.
func start(settings: Settings) -> String:
	if is_running():
		return ""
	var command := settings.moonlight_command.split(" ", false)
	if command.is_empty():
		return "No Moonlight command configured"
	var args := command.slice(1)
	args.append_array([
		"stream", settings.stream_host(), settings.sunshine_app,
		"--display-mode", "fullscreen",
		# Keep the host's session (and Chrome) alive when the stream closes.
		"--no-quit-after",
	])
	_pid = OS.create_process(command[0], args)
	_host = settings.stream_host()
	_started_at = Time.get_ticks_msec() / 1000.0
	if _pid <= 0:
		_pid = -1
		return "Could not start Moonlight (%s)" % command[0]
	return ""


func stop() -> void:
	if is_running():
		OS.kill(_pid)
	_pid = -1


func _process(_delta: float) -> void:
	if _pid > 0 and not OS.is_process_running(_pid):
		_pid = -1
		if Time.get_ticks_msec() / 1000.0 - _started_at < MIN_RUN_SECONDS:
			failed.emit("Moonlight exited right away. Is it paired with %s, and is Sunshine running there?" % _host)
		else:
			closed.emit()


func _exit_tree() -> void:
	stop()
