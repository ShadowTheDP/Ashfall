extends Node
## Formal run restart abandons the run; R only interacts. No same-biome retry.
var _main: Node
var _fails := 0
var _checks := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = $Main
	Profile.reset_profile()
	await get_tree().process_frame
	_main.enter_hub()
	await _start()
	Game.add_cells(9)
	Game.add_kill()
	var total_kills := Profile.total_kills
	Game.run_keys.append("test_key")
	Game.apply_reward("edge")
	var runs := Profile.runs
	var deaths := Profile.deaths
	await _key(KEY_ESCAPE)
	_check(_main.hud.paused and get_tree().paused, "Esc pauses")
	await _key(KEY_R)
	_check(_main.hud.paused and Game.run_node_id == "ash_gate" and Profile.runs == runs, "R while paused cannot retry")
	await _key(KEY_ENTER)
	_check(_main.hud._abandon_confirm and _main.hud.paused and Profile.runs == runs and Game.run_cells == 9, "first Enter only asks; run remains untouched")
	await _key(KEY_T)
	_check(_main.hud._abandon_confirm and not Game.in_hub and _main.hud.paused, "confirmation owns title key; no flow leaks underneath")
	await _key(KEY_ESCAPE)
	_check(not _main.hud._abandon_confirm and _main.hud.paused and Profile.runs == runs, "Escape cancels abandonment back to pause")
	await _key(KEY_ENTER)
	await _key(KEY_KP_ENTER)
	await _wait(0.1)
	_check(Game.in_hub and Game.run_node_id.is_empty(), "abandon returns to start")
	_check(Profile.runs == runs + 1 and Profile.deaths == deaths, "abandon counts once without fake death")
	_check(Profile.total_kills == total_kills + 1, "abandon settles the displayed kill count once")
	_check(Game.run_cells == 0 and Game.run_keys.is_empty() and Game.attr.is_empty() and not Game.exit_selected and Game.pending_destination.is_empty(), "abandon clears run resources and destination")
	_check(not get_tree().paused and not _main.hud.paused and Engine.time_scale == 1.0, "abandon clears pause/hitstop")
	await _start()
	await _die(false)
	await _start()
	await _die(true)
	await _start()
	# Build a boss state via legal selected edges; physical exits are in run_probe.
	var carried_kills := 0
	for id in ["hanging_gallery", "stone_ramparts", "bridge_sentinel"]:
		Game.add_kill()
		carried_kills += 1
		_check(Game.select_destination(id), "fixture selects next exit")
		Game.run_phase = "passage"
		_check(_main.start_node(id), "boss fixture follows legal edge")
		await _wait(0.05)
		_check(Game.kills == carried_kills, "kills accumulate across biome transitions")
	await _die(false)
	print("RESTART PROBE %s (%d checks, %d failures)" % ["OK" if _fails == 0 else "FAILED", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _start() -> void:
	await _wait(0.12)
	_main._on_descend(1)
	await _wait(0.15)
	_check(Game.kills == 0, "next run resets its kill counter")


func _die(clearing: bool) -> void:
	Game.add_kill()
	var kills := Game.kills
	var total_kills := Profile.total_kills
	Game.add_cells(13)
	var runs := Profile.runs
	var deaths := Profile.deaths
	var banked := Profile.cells
	if clearing:
		_main._on_exit_chosen(str(Game.route_exits()[0]["to"]))
		_check(Game.exit_selected, "transition fixture has selected exit")
	Game.player.invuln = 0
	Game.player.take_hit({"damage": 99999.0, "source_pos": Game.player.position - Vector2(40, 0)})
	Combat.cancel_hitstop()
	await _wait(0.08)
	_check(Game.run_over and not _main._cleared_floor and not Game.exit_selected and Game.pending_destination.is_empty(), "ordinary/boss/transition death cancels clear and destination")
	_check(Profile.runs == runs + 1 and Profile.deaths == deaths + 1, "death settles once")
	_check(Profile.total_kills == total_kills + kills, "death settles all displayed cross-biome kills")
	Game.add_cells(5)
	_main._on_player_died()
	_check(Game.run_cells == 0 and Profile.cells == banked and Profile.deaths == deaths + 1 and Profile.total_kills == total_kills + kills, "late pickup and repeated signal cannot settle again")
	await _key(KEY_R)
	_check(Game.run_over, "R cannot revive dead run")
	await _key(KEY_ENTER)
	await _wait(0.08)
	_check(Game.in_hub and Profile.runs == runs + 1, "Enter returns clean hub without duplicate run")
	var players := 0
	for node in _main.world.get_children():
		if node is Player or node is Projectile or node is FunctionWave or node.is_in_group("hazard_pool"):
			players += 1
	_check(players == 0 and is_instance_valid(Game.player), "world has no stale floor body/FX; Hub owns player")


func _key(code: int) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("RESTART FAIL: " + message)
		get_tree().quit(1)
