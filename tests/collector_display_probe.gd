extends Node
## Non-destructive regression probe for the paused Collector overlay.

var _main: Node
var _fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_check(Profile.SAVE_PATH != "user://ashfall_profile.json", "probe is using the live profile")
	_main = $Main
	await get_tree().process_frame

	# An empty reset is an explanatory state, not a failed purchase: the real
	# Accept event must never open a confirm, spend Gold, or reach _buy().
	var previous_build := Game.build
	var reset_build := RunBuild.new()
	var no_unlocks: Array[String] = []
	reset_build.start("rusty_sword", no_unlocks)
	reset_build.mutation_capacity = 1
	Game.build = reset_build
	var run_cells_before := Game.run_cells
	var gold_before := reset_build.gold
	var save_error_before := Profile.last_save_error
	_main._open_service("mutation")
	await get_tree().process_frame
	await get_tree().process_frame
	var empty_collector = _main.collector
	_check(is_instance_valid(empty_collector) and empty_collector.service == "mutation" and empty_collector._ids[0] == "reset", "empty reset service opens on its reset row")
	if is_instance_valid(empty_collector):
		await _tap_key(KEY_ENTER)
		_check(not empty_collector._reset_confirm, "empty reset does not open a confirmation")
		_check(empty_collector._note == ContentText.of("UI_S6_RESET_NONE", "No chosen effects to clear."), "empty reset explains there is nothing to clear")
		_check(not empty_collector._note.contains("NOT COMMITTED"), "empty reset never shows a failed-purchase receipt")
		_check(reset_build.gold == gold_before and reset_build.mutations.is_empty() and Game.run_cells == run_cells_before, "empty reset spends no Gold and changes no effects")
		_check(Profile.last_save_error == save_error_before, "empty reset does not attempt a save")
		await _tap_key(KEY_ESCAPE)
		await get_tree().process_frame
		await get_tree().process_frame
	Game.build = previous_build

	_main._open_collector()
	await get_tree().create_timer(0.4, true).timeout
	_check(get_tree().paused, "Collector did not pause gameplay")
	_check(_main._fade_rect.color.a < 0.05, "Collector fade-in stayed black while paused")
	_check(_main.hud._modal_open(), "HUD does not treat Collector as modal")
	_check(not _main.collector._ids.is_empty(), "Collector lists real permanent options")
	var states := ["available", "locked", "chosen", "owned", "completed", "insufficient"]
	for id in _main.collector._ids:
		_check(states.has(_main.collector._state_of(id)), "row state is one of the six explicit categories: " + str(id))
	_check(_main.collector._scope_context().split("·").size() == 3, "header states spend, effect scope and save point")
	_check(not _main.collector._empty_message().is_empty(), "empty service has honest text instead of a blank page")

	# Archives are created with the hub, not at boot. Use the real hub and station
	# entry so the fixture is the live panel the game shows, then reopen the
	# Collector for the later input guards.
	_main.enter_hub()
	await get_tree().process_frame
	await get_tree().process_frame
	_main._on_station_opened("archive")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var archive = _main.archive
	_check(is_instance_valid(archive), "Main built the ArchiveScreen fixture")
	if is_instance_valid(archive):
		archive._tab = "weapon"
		archive._reload()
		archive._failed = true
		archive._fail_reason = "LONG_DIAGNOSTIC_" + "X".repeat(200)
		_check(not archive._note_display().contains("LONG_DIAGNOSTIC_"), "archive receipt does not carry the raw save diagnostic")
		var record: Dictionary = archive._record_copy(archive._ids[0])
		var joined := "\n".join(record.details)
		_check(joined.contains("LONG_DIAGNOSTIC_") and record.details.size() > archive.DETAIL_ROWS, "archive raw diagnostic is reachable through the scrollable detail rows")
		archive._failed = false
		archive._fail_reason = ""
		archive._ids.clear()
		archive.close()
		await get_tree().process_frame
		await get_tree().process_frame
	_main._open_collector()
	await get_tree().create_timer(0.4, true).timeout

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

	# An empty list must stay escapable: Back closes it and consumes the event.
	_main.collector._ids.clear()
	await _tap_key(KEY_ESCAPE)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not is_instance_valid(_main.collector), "Back closes an empty service and never traps focus")

	get_tree().paused = false
	print("COLLECTOR_DISPLAY_PROBE: %d failures" % _fails)
	get_tree().quit(1 if _fails else 0)


func _tap_key(key: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.physical_keycode = key
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _check(ok: bool, message: String) -> void:
	if ok:
		return
	_fails += 1
	push_error("FAIL: " + message)
