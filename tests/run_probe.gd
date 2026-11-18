extends Node
## L1/L2 integration fixtures: branch/rejoin then first-Boss continuation, not L6 play.
var _main: Node
var _fails := 0
var _checks := 0
var _captured: Dictionary = {}
var _capture := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = $Main
	assert(Profile.SAVE_PATH != "user://ashfall_profile.json")
	_capture = OS.get_cmdline_user_args().has("--capture")
	Profile.reset_profile()
	await get_tree().process_frame
	_main.enter_hub()
	await _wait(0.3)
	await _start()
	_check(Game.run_node_id == "ash_gate" and Game.route_history.size() == 1, "real Hub key enters Ash Gate")
	_check(not _main.start_node("bridge_sentinel"), "cannot skip to boss")
	var exits := Game.route_exits()
	_check(exits.size() == 2 and not str(exits[1]["reason"]).is_empty(), "fresh Cistern exit is locked")
	Game.add_cells(80)
	Game.apply_reward("edge")
	var body := Game.player
	var damage := Game.damage_mult
	body.hp = body.max_hp * 0.25
	var charges := Game.flask_charges
	await _key(KEY_F)
	_check(Game.flask_charges == charges - 1 and body.hp > body.max_hp * 0.25, "F consumes flask and heals")
	await _key(KEY_H)
	_check(Game.flask_charges == 0 and is_equal_approx(body.hp, body.max_hp), "H consumes final charge")
	body.hp = body.max_hp * 0.5
	await _key(KEY_F)
	_check(is_equal_approx(body.hp, body.max_hp * 0.5), "empty flask cannot heal")
	await _leave("hanging_gallery", true)
	_check(Game.player == body and is_equal_approx(Game.damage_mult, damage), "Passage/biome preserves same body and build")
	_check(Game.run_cells == 80, "L3 carries Cells while legacy stat purchases are archived")
	_check(not Profile.unlocked_runes.has("canopy_rune"), "entering Gallery does not award Rune")
	await _take_rune()
	var runs := Profile.runs
	var deaths := Profile.deaths
	body.invuln = 0
	body.take_hit({"damage": 99999.0, "source_pos": body.position - Vector2(40, 0)})
	Combat.cancel_hitstop()
	await _wait(0.1)
	_check(Game.run_over and Game.run_cells == 0, "death immediately forfeits carried Cells")
	Game.add_cells(9)
	_check(Game.run_cells == 0, "late pickup refused")
	await _key(KEY_R)
	_check(Game.run_over, "R cannot revive current biome")
	await _key(KEY_ENTER)
	await _wait(0.15)
	_check(Game.in_hub and Profile.runs == runs + 1 and Profile.deaths == deaths + 1, "dead Enter returns Hub without double settlement")
	_check(Profile.unlocked_runes.has("canopy_rune") and Profile.upgrade_level("vitality") == 0, "Rune survives death without adding legacy permanent power")
	await _start()
	_check(str(Game.route_exits()[1]["reason"]).is_empty(), "earned Rune opens next-run Cistern")
	await _leave("silt_cistern")
	await _take_rune("phase_rune")
	await _leave("stone_ramparts")
	await _leave("bridge_sentinel")
	_check(Game.route_history == ["ash_gate", "silt_cistern", "stone_ramparts", "bridge_sentinel"], "alternate four-visit route rejoins")
	await _end_slice()
	await _start()
	await _leave("hanging_gallery")
	await _leave("stone_ramparts")
	await _leave("bridge_sentinel")
	_check(Game.route_history == ["ash_gate", "hanging_gallery", "stone_ramparts", "bridge_sentinel"], "main four-visit route rejoins")
	await _end_slice()
	_check(Profile.victories == 0 and Profile.boss_cells_unlocked == 0 and Profile.souls == 0, "slice never grants full-run victory/BSC/soul")
	print("RUN SLICE %s (%d checks, %d failures)" % ["OK" if _fails == 0 else "FAILED", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _start() -> void:
	var hub: Node = _main.hub
	Game.player.position = Vector2(float(hub.DOOR_X) - 25, -24)
	await _wait(0.1)
	await _key(KEY_R)
	await _wait(0.3)
	Game.player.invuln = 1000
	await _shot(Game.run_node_id)


func _leave(target: String, service := false) -> void:
	var level: Node = _main.level
	var body := Game.player
	var count: int = level.enemies_remaining()
	if target == "stone_ramparts":
		_check(Profile.unlocked_runes.has("phase_rune") or Game.run_node_id != "silt_cistern", "Cistern Phase pickup was visited")
	if Game.run_node_id == "ash_gate" and not Profile.unlocked_runes.has("canopy_rune"):
		for exit: Dictionary in level.data["exits"]:
			if str(exit["to"]) == "silt_cistern":
				body.relocate(exit["pos"])
				await _wait(0.15)
				await _key(KEY_R)
				_check(Game.run_phase == "biome" and not _main._cleared_floor, "locked physical Cistern exit refuses entry")
	if not (level.data["key"] as Dictionary).is_empty():
		body.relocate(level.data["key"]["pos"])
		await _wait(0.15)
		await _key(KEY_R)
		_check(Game.run_keys.has("rampart_key"), "real key pickup precedes local door")
		var gate: Node = level._gates["rampart_lock"]
		var rect: Rect2 = gate.spec["rect"]
		body.relocate(Vector2(rect.position.x - 40, 126))
		await _wait(0.15)
		await _key(KEY_R)
		_check(gate.unlocked and not Game.run_keys.has("rampart_key"), "R opens local door and consumes key once")
	var found := false
	for exit: Dictionary in level.data["exits"]:
		if str(exit["to"]) == target:
			body.relocate(exit["pos"])
			found = true
	_check(found, "physical destination exists: " + target)
	await _wait(0.15)
	await _key(KEY_R)
	_check(_main._cleared_floor, "R at ordinary exit leaves without whole-biome wipe (%d hostiles)" % count)
	_check(Game.pending_destination == target and Game.exit_selected, "biome exit fixes destination before Passage")
	await _wait(1.8)
	_check(is_instance_valid(_main.passage) and Game.run_phase == "passage", "clear enters walkable Passage")
	if not is_instance_valid(_main.passage):
		return
	_check(Game.player == body, "Passage retained player")
	if service:
		body.position = Vector2(float(_main.passage.COLLECTOR_X), -24)
		await _key(KEY_R)
		_check(is_instance_valid(_main.collector) and get_tree().paused, "R opens Collector and pauses")
		var charges := Game.flask_charges
		await _key(KEY_H)
		_check(Game.flask_charges == charges, "modal rejects healing")
		await _key(KEY_ENTER)
		_check(Profile.upgrade_level("vitality") == 0 and Game.run_cells == 80, "L3 Collector refuses inactive legacy stats without spending Cells")
		await _key(KEY_SPACE)
		_check(Game.run_node_id == "ash_gate" and is_instance_valid(_main.passage), "closing service does not choose next node")
		body.position = Vector2(float(_main.passage.FOUNTAIN_X), -24)
		await _key(KEY_R)
		_check(is_equal_approx(body.hp, body.max_hp) and Game.flask_charges == Game.flask_capacity, "0 BSC fountain refills HP and flask")
		await _key(KEY_H)
		_check(Game.flask_charges == Game.flask_capacity, "full health does not waste flask")
		var time := Game.run_time
		await _wait(0.1)
		_check(is_equal_approx(time, Game.run_time), "Passage pauses run timer")
	await _shot("passage")
	await _continue_passage(target)
	await _wait(0.3)
	_check(Game.run_node_id == target, "keyboard destination chosen: " + target)
	print("route entered: ", Game.run_node_id)
	Game.player.invuln = 1000
	await _shot(target)


func _continue_passage(target: String) -> void:
	_check(Game.pending_destination == target and Game.exit_selected, "Passage retains selected destination")
	_check(not _main.start_node("silt_cistern" if target != "silt_cistern" else "hanging_gallery"), "cannot substitute another node inside Passage")
	Game.player.relocate(Vector2(float(_main.passage.EXIT_X), -24))
	await _wait(0.15)
	await _shot("destination")
	await _key(KEY_R)


func _take_rune(id := "canopy_rune") -> void:
	var level: Node = _main.level
	var index := int(level.data["rune_room"])
	var rect: Rect2 = level.data["rooms"][index]["rect"]
	Game.player.relocate(Vector2(rect.get_center().x, rect.position.y - 24))
	await _wait(0.15)
	_check(bool(level._room_entered[index]), "guard room entered through two-dimensional player position")
	_check(not is_instance_valid(level.rune_pickup), "Rune hidden until guard defeated")
	for enemy: Enemy in level._alive.duplicate():
		if int(enemy.get_meta("room", -1)) == index:
			enemy.take_hit({"damage": 1.0e6, "crit": true, "knockback": 0.0, "source_pos": enemy.position - Vector2(40, 0)})
	Combat.cancel_hitstop()
	await _wait(0.1)
	_check(is_instance_valid(level.rune_pickup), "guard defeat reveals world pickup")
	if is_instance_valid(level.rune_pickup):
		Game.player.relocate(level.rune_pickup.position)
		await _wait(0.15)
		var redraws := [0]
		level.draw.connect(func(): redraws[0] += 1)
		await _key(KEY_R)
		await _wait(0.05)
		_check(redraws[0] > 0, "Rune pickup redraws exit locks")
	_check(Profile.unlocked_runes.has(id), "R picks up and saves " + id)


func _end_slice() -> void:
	var level: Node = _main.level
	for i in level.data["rooms"].size():
		if not level._room_entered[i]:
			level._enter_room(i)
	Game.player.position = level.data["exit"] + Vector2(0, -30)
	await _wait(0.08)
	await _key(KEY_R)
	_check(not _main._cleared_floor and not Game.boss_defeated, "Boss exit requires defeating Boss")
	await _shot("boss_exit_locked")
	var redraws := [0]
	level.draw.connect(func(): redraws[0] += 1)
	for enemy: Enemy in level._alive.duplicate():
		enemy.take_hit({"damage": 1.0e6, "crit": true, "knockback": 0.0, "source_pos": enemy.position - Vector2(40, 0)})
	Combat.cancel_hitstop()
	await _wait(0.1)
	_check(redraws[0] > 0 and Game.exit_reason("stilt_foundry").is_empty(), "Boss death redraws the now-open physical exit")
	if _capture and Game.announce_t > 0:
		await _wait(Game.announce_t + 0.05)
	await _shot("boss_exit_open")
	await _key(KEY_R)
	await _wait(1.8)
	_check(Game.run_phase == "passage", "Boss clear has Passage services")
	await _continue_passage("stilt_foundry")
	_check(Game.run_node_id == "stilt_foundry" and not Game.run_over and not Game.victory, "first Boss continues into fifth visit without victory")
	await _wait(0.3)
	await _key(KEY_ESCAPE)
	await _key(KEY_ENTER)
	await _key(KEY_ENTER)
	await _wait(0.15)
	_check(Game.in_hub, "slice can return to start")


func _shot(label: String) -> void:
	if not _capture or _captured.has(label):
		return
	_captured[label] = true
	var dir := "res://output/screenshots/route"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if label in ["passage", "destination"]:
		await _wait(0.3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/" + label + ".png")


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
		_fails += 1
		push_error("RUN SLICE FAIL: " + message)
		get_tree().quit(1)
