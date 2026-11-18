extends Node
## L5 lifecycle/collision fixtures, NOT input-only L6 or human play acceptance.
var _main: Node
var _checks := 0
var _capture := false



func _ready() -> void:
	if not Data.is_node_ready():
		await Data.ready
	if not Interface.is_node_ready():
		await Interface.ready
	if not Sfx.is_node_ready():
		await Sfx.ready
	TranslationServer.set_locale("en")
	process_mode = Node.PROCESS_MODE_ALWAYS
	assert(Profile.SAVE_PATH != "user://ashfall_profile.json")
	Profile.reset_profile()
	_capture = DisplayServer.get_name() != "headless"
	if _capture:
		DirAccess.make_dir_recursive_absolute("res://output/screenshots/l5-labels")
	_main = $Main
	await get_tree().process_frame
	_main.enter_hub()
	await _wait(0.3)
	_check(not Game.end_run(true), "Hub cannot grant victory")
	await _start()
	var body := Game.player
	var build := Game.build
	for id: String in Data.route_graph.default_0_bsc_route:
		_check(Game.run_node_id == id and Game.run_bsc == 0, "real route visit " + id)
		_check(Game.player == body and Game.build == build, "body/build retained " + id)
		_check(not Game.end_run(true), "premature victory refused " + id)
		var level: Node = _main.level
		for i in level.data.rooms.size():
			level._enter_room(i)
		await _wait(0.1)
		for item: Dictionary in level.data.keys:
			body.relocate(item.pos)
			await _wait(0.14)
			await _key(KEY_R)
			_check(Game.run_keys.has(str(item.id)), "physical key " + str(item.id))
		if id == "high_keep":
			_check(Game.run_keys.has("court_key_left") and Game.run_keys.has("court_key_right"), "both court keys coexist")
		if str(Data.route_graph.nodes[id].kind) == "boss":
			_check(Game.boss is RouteBoss and Game.boss.kind == id, "distinct runtime boss dispatch " + id)
			_check(not Game.exit_reason("" if id == "silent_regent" else _next(id)).is_empty(), "alive boss locks exit")
			if _capture:
				body.relocate(Game.boss.global_position - Vector2(140, 0))
				await _shot(id)
		for enemy: Enemy in level._alive.duplicate():
			enemy.take_hit({"damage":1.0e6, "crit":true, "knockback":0.0, "source_pos":enemy.position - Vector2(40, 0)})
		Combat.cancel_hitstop()
		await _wait(0.1)
		if str(Data.route_graph.nodes[id].kind) == "boss":
			_check(Game.defeated_bosses.has(id), "real death records boss " + id)
		if id == "silent_regent":
			await _finale(level)
			break
		var target := _next(id)
		await _exit(level, target)
		_check(Game.run_phase == "passage" and Game.pending_destination == target, "Passage receives " + target)
		body.relocate(Vector2(float(_main.passage.EXIT_X), -24))
		await _wait(0.15)
		await _key(KEY_R)
		await _wait(0.3)
		body.invuln = 1000 # Integration fixture only; L6 uses unmodified input play.
	_check(Profile.victories == 1 and Profile.boss_cells_unlocked == 1, "first legal clear unlocks only BSC1")
	_check(Profile.unlocked_runes.has("homunculus_rune"), "final Rune is saved")
	if _capture: await _shot("victory-saved")
	Profile.load_profile(true)
	_check(Profile.victories == 1 and Profile.boss_cells_unlocked == 1 and Profile.active_bsc == 0, "reload retains victory without enabling L8")
	await _key(KEY_ENTER)
	await _wait(0.2)
	_check(Game.in_hub and Game.build == null, "victory returns clean starting area")
	if _capture:
		Game.player.relocate(Vector2(float(_main.hub.DOOR_X) - 100, -24))
		await _shot("hub_unlock")
	await _start()
	_check(Game.run_bsc == 0 and Game.route_history == ["ash_gate"], "next run fixed legal BSC0")
	await _failed_death()
	print("L5 ROUTE FIXTURES OK (%d checks); NOT input-only/human acceptance" % _checks)
	get_tree().quit()


func _start() -> void:
	Game.player.relocate(Vector2(float(_main.hub.DOOR_X) - 25, -24))
	await _wait(0.15)
	await _key(KEY_R)
	await _wait(0.3)
	Game.player.invuln = 1000


func _next(id: String) -> String:
	var route: Array = Data.route_graph.default_0_bsc_route
	return str(route[route.find(id) + 1])


func _exit(level: Node, target: String) -> void:
	var found := false
	for item: Dictionary in level.data.exits:
		if str(item.to) == target:
			Game.player.relocate(item.pos)
			found = true
	_check(found, "physical exit exists " + target)
	await _wait(0.15)
	await _key(KEY_R)
	await _wait(1.8)


func _finale(level: Node) -> void:
	_check(level._exit_label({"to":""}) == "VICTORY", "final physical and map marker identifies victory")
	if _capture:
		for item: Dictionary in level.data.exits:
			if str(item.to).is_empty():
				Game.player.relocate(item.pos - Vector2(45, 0))
		await _shot("final_exit")
	_check(Game.final_ready(), "nine visits, three boss deaths and required keys validate")
	var last_boss: String = Game.defeated_bosses.pop_back()
	_check(not Game.final_ready() and not Game.end_run(true), "missing boss receipt refuses finale")
	Game.defeated_bosses.append(last_boss)
	Game.run_keys.erase("court_key_right")
	_check(not Game.final_ready(), "missing second key refuses finale")
	Game.run_keys.append("court_key_right")
	var cells := Game.run_cells
	var bank := Profile.cells
	var runs := Profile.runs
	var build := Game.build
	Profile._save_blocked = true
	await _exit(level, "")
	_check(not Game.run_over and Game.build == build and Game.run_cells == cells, "failed final commit retains live run/rewards")
	_check(Profile.runs == runs and Profile.victories == 0 and Profile.cells == bank and Profile.boss_cells_unlocked == 0, "failed final commit rolls back every permanent field")
	_check(not Profile.unlocked_runes.has("homunculus_rune"), "failed save grants no Rune")
	if _capture: await _shot("final-save-failed")
	Profile._save_blocked = false
	await _key(KEY_R)
	await _wait(0.1)
	_check(Game.victory and Game.run_over and Game.build == null and Game.run_cells == 0, "retry physical exit commits before cleanup")
	_check(Profile.cells == bank + cells and Profile.runs == runs + 1, "residual Cells credited exactly once")
	_check(not Game.end_run(true), "duplicate victory settlement refused")
	await _key(KEY_R)
	_check(Profile.cells == bank + cells and Profile.runs == runs + 1, "repeated exit cannot duplicate reward")


func _failed_death() -> void:
	var runs := Profile.runs
	var deaths := Profile.deaths
	var wins := Profile.victories
	var bank := Profile.cells
	Game.add_cells(37)
	Profile._save_blocked = true
	Game.player.invuln = 0
	Game.player.take_hit({"damage":99999.0, "source_pos":Game.player.position - Vector2(40, 0)})
	Combat.cancel_hitstop()
	await _wait(0.1)
	_check(Game.run_over and Game.build == null and Game.run_cells == 0 and not Game.settlement_pending.is_empty(), "failed death save still forfeits carried resources")
	await _key(KEY_ENTER)
	_check(not Game.in_hub and Profile.runs == runs and Profile.deaths == deaths, "uncommitted death blocks restart and rolls back disk projection")
	Profile._save_blocked = false
	await _key(KEY_ENTER)
	await _wait(0.2)
	_check(Game.in_hub and Game.settlement_pending.is_empty() and Profile.runs == runs + 1 and Profile.deaths == deaths + 1, "death retry commits once before starting area")
	_check(Profile.cells == bank and Profile.victories == wins and Profile.boss_cells_unlocked == 1, "death keeps permanent progress without banking carried Cells")
	_check(Game.retry_settlement() and Profile.runs == runs + 1, "duplicate recovery is idempotent")


func _shot(label: String) -> void:
	await _wait(0.5)
	await get_tree().process_frame
	_main.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://output/screenshots/l5-labels/" + label + ".png") == OK, "saved fixture label capture " + label)
	var directory := OS.get_environment("ASHFALL_CAPTURE_ACK_DIR")
	if not directory.is_empty():
		var deadline := Time.get_ticks_msec() + 1500
		while not FileAccess.file_exists(directory.path_join(label + ".json")) and Time.get_ticks_msec() < deadline: await get_tree().process_frame
		_check(FileAccess.file_exists(directory.path_join(label + ".json")), "owned physical capture " + label)
	print("L5 UI FRAME %dms %s" % [Time.get_ticks_msec(), label])


func _key(code: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		push_error("L5 ROUTE FAIL: " + message)
		get_tree().quit(1)
