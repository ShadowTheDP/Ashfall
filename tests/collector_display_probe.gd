extends Node
## Non-destructive regression probe for the paused Collector overlay.

var _main: Node
var _fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_check(Profile.SAVE_PATH != "user://ashfall_profile.json", "probe is using the live profile")
	_main = $Main
	await get_tree().process_frame
	_main._open_collector()
	await get_tree().create_timer(0.4, true).timeout
	_check(get_tree().paused, "Collector did not pause gameplay")
	_check(_main._fade_rect.color.a < 0.05, "Collector fade-in stayed black while paused")
	_check(_main.hud._modal_open(), "HUD does not treat Collector as modal")

	Game.floor_index = 1
	_main.hud.paused = true
	var restart := InputEventAction.new()
	restart.action = "restart"
	restart.pressed = true
	_main.hud._unhandled_input(restart)
	_check(is_instance_valid(_main.collector), "R input discarded the Collector overlay")
	_check(Game.floor_index == 1, "R input changed the floor while Collector was open")

	_main._cleared_floor = true
	_main._on_player_died()
	_check(not _main._cleared_floor and is_equal_approx(_main._transition, 2.2),
		"death during clear transition would carry a DEAD player forward")

	get_tree().paused = false
	print("COLLECTOR_DISPLAY_PROBE: %d failures" % _fails)
	get_tree().quit(1 if _fails else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		return
	_fails += 1
	push_error("FAIL: " + message)
