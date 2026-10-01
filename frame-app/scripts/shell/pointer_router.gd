class_name PointerRouter
extends RefCounted
## Routes one pointer ray (the desktop "head", or the active VR controller)
## to whichever target it hits first. Targets are duck-typed and provide:
##   pointer_hit(origin, direction) -> Dictionary   # {} for a miss, else at least {distance, point}
##   pointer_move(hit), pointer_button(hit, pressed), pointer_scroll(hit, dy, dx), pointer_exit()
## dy > 0 scrolls content down (like wheel-down); dx > 0 scrolls right.

var targets: Array[Object] = []
var hover_target: Object
var hover_hit: Dictionary = {}
## The target a press started on keeps the release, so drags and clicks
## can't end up split across two targets.
var _pressed_target: Object


## The nearest hit without side effects: [target, hit], or [null, {}].
func cast(origin: Vector3, direction: Vector3) -> Array:
	var best: Object = null
	var best_hit := {}
	for target in targets:
		var hit: Dictionary = target.pointer_hit(origin, direction)
		if not hit.is_empty() and (best_hit.is_empty() or hit.distance < best_hit.distance):
			best = target
			best_hit = hit
	return [best, best_hit]


## Moves the pointer; returns the hit (or {}) so callers can draw a dot.
func update(origin: Vector3, direction: Vector3) -> Dictionary:
	var result := cast(origin, direction)
	var target: Object = result[0]
	if target != hover_target:
		if hover_target:
			hover_target.pointer_exit()
		hover_target = target
	hover_hit = result[1]
	if target:
		target.pointer_move(hover_hit)
	return hover_hit


func button(pressed: bool) -> void:
	if pressed:
		if hover_target:
			_pressed_target = hover_target
			hover_target.pointer_button(hover_hit, true)
	elif _pressed_target:
		_pressed_target.pointer_button(hover_hit if hover_target == _pressed_target else {}, false)
		_pressed_target = null


func scroll(dy: float, dx := 0.0) -> void:
	if hover_target:
		hover_target.pointer_scroll(hover_hit, dy, dx)
