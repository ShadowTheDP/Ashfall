extends Node
## Permanent storage failure must not trap ended-run keyboard controls.
var _checks := 0
var _main: Node
var _capture := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Profile.require_test_profile(): return
	_capture = DisplayServer.get_name() != "headless"
	Profile.reset_profile()
	_main = $Main
	await get_tree().process_frame
	_main.enter_hub()
	_check(_main.start_node("ash_gate"), "start abandonment fixture")
	Game.add_cells(11)
	Game.add_kill()
	# A successful explicit abandon keeps its kind even with nothing pending:
	# the result page must not need settlement_pending to know it was abandoned.
	_check(Game.end_run(false, true) and Game.run_abandoned and Game.settlement_pending.is_empty(), "successful abandon records its reason without a pending receipt")
	_main.enter_hub()
	_check(_main.start_node("ash_gate"), "restart for the failed-receipt fixture")
	var runs := Profile.runs
	var deaths := Profile.deaths
	var total := Profile.total_kills
	Game.add_cells(11)
	Game.add_kill()
	Profile._save_blocked = true
	await _key(KEY_ESCAPE)
	await _key(KEY_KP_ENTER)
	for step in 3:
		await _key(KEY_RIGHT)
	await _key(KEY_KP_ENTER)
	_check(_main.hud._abandon_confirm and not Game.run_over, "failed-save fixture first asks before abandoning")
	await _key(KEY_KP_ENTER)
	_check(Game.run_over and not Game.settlement_pending.is_empty() and Game.run_cells == 0 and Game.build == null, "failed keypad abandonment still forfeits run")
	_check(Profile.runs == runs and Profile.deaths == deaths and Profile.total_kills == total, "failed abandonment has no false permanent receipt")
	_check(Game.run_abandoned, "failed abandonment keeps its result kind")
	_check(_main.hud.run_over_action_ids() == ["retry", "quit"], "failed result offers retry and leave")
	_check(_main.hud._run_action == 0, "failed result defaults to Retry save")
	await _key(KEY_RIGHT)
	_check(_main.hud._run_action == 1, "keyboard moves the result focus to Leave")
	await _key(KEY_LEFT)
	_check(_main.hud._run_action == 0, "keyboard returns the result focus to Retry")
	Profile.last_save_error = "LONG_STORAGE_ERROR_TOKEN_".repeat(30)
	for frame in 3:
		await get_tree().process_frame
	_check(_main.hud._result_line_count > _main.hud.RESULT_DETAIL_ROWS, "long failed reason fills more lines than the result window")
	var scroll_before: int = _main.hud._result_scroll
	await _key(KEY_DOWN)
	_check(_main.hud._result_scroll == scroll_before + 1, "down pages the failed reason")
	await _key(KEY_UP)
	_check(_main.hud._result_scroll == scroll_before, "up pages back to the first line")
	await _shot("abandon-save-failed")
	for code in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]: await _key(code)
	_check(Game.run_over and Profile.runs == runs and Profile.total_kills == total and not get_tree().paused, "repeated refused retries neither resume nor double settle")
	_check(not _main.return_to_title() and not Profile.select_slot(2) and Profile.active_slot == 1, "pending settlement cannot switch to another save")
	Profile.load_profile(true)
	_main.enter_hub()
	_check(Game.in_hub and Game.settlement_pending.is_empty() and Profile.runs == runs + 1 and Profile.total_kills == total + 1 and Profile.deaths == deaths and Profile.run_checkpoint.is_empty(), "recovered abandonment settles once and clears checkpoint")
	_check(_main.start_node("ash_gate"), "start death fixture")
	Game.add_kill()
	Game.add_cells(13)
	Profile._save_blocked = true
	Game.player.invuln = 0
	Game.player.take_hit({"damage":99999.0, "source_pos":Game.player.position - Vector2(40, 0)})
	Combat.cancel_hitstop()
	# The death route owns a 2.2s transition; wait for the real countdown to end
	# instead of sleeping past it. The assertion still proves the automatic Hub
	# return refuses the failed receipt.
	await get_tree().process_frame
	var hub_deadline := Time.get_ticks_msec() + 2600
	while Game.hub_return_in > 0.0 and Time.get_ticks_msec() < hub_deadline:
		await get_tree().process_frame
	_check(Game.run_over and Game.hub_return_in == 0 and not Game.settlement_pending.is_empty(), "automatic Hub return refuses failed death receipt")
	for code in [KEY_KP_ENTER, KEY_ENTER, KEY_ESCAPE]: await _key(code)
	_check(Game.run_over and Game.run_cells == 0 and Game.build == null and Profile.runs == runs + 1 and Profile.deaths == deaths and Profile.total_kills == total + 1, "death retries retain forfeiture without duplicate receipts")
	_check(not Game.run_abandoned, "death result is never labelled abandoned")
	_check(not _main.hud.paused and not _main.hud._modal_open(), "ended overlay owns keyboard even when pause cannot open")
	await _shot("death-save-failed")
	# No explicit quit fallback: removing the HUD quit path makes this probe time out.
	var event := InputEventKey.new()
	event.physical_keycode = KEY_Q
	event.keycode = KEY_Q
	event.pressed = true
	_main.hud._unhandled_input(event)
	_check(get_viewport().is_input_handled(), "Q quit is consumed by ended overlay")
	print("TERMINAL FAILURE OK (%d checks; quit requested by HUD)" % _checks)

func _shot(label: String) -> void:
	if not _capture: return
	DirAccess.make_dir_recursive_absolute("res://output/screenshots/terminal")
	await get_tree().create_timer(0.32, true).timeout
	_check(_main._fade_rect.color.a < 0.01, "terminal retry overlay is readable after its scene veil settles")
	await get_tree().process_frame
	$Main.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://output/screenshots/terminal/" + label + ".png") == OK, "capture " + label)

	await _physical_capture(label)
	print("TERMINAL_FAILURE_PROBE FRAME %dms %s" % [Time.get_ticks_msec(), label])
	if OS.get_environment("ASHFALL_CAPTURE_ACK_DIR").is_empty(): await get_tree().create_timer(0.08, true).timeout

func _key(code: int) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		if DisplayServer.get_name() != "headless": print("TERMINAL_FAILURE_PROBE INPUT %dms key=%d pressed=%s" % [Time.get_ticks_msec(), code, str(event.pressed)])
		await get_tree().process_frame

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		push_error("TERMINAL FAILURE FAIL: " + message)
		get_tree().quit(1)

func _physical_capture(label: String) -> void:
	var directory := OS.get_environment("ASHFALL_CAPTURE_ACK_DIR")
	if directory.is_empty(): return
	var path := directory.path_join(label + ".json")
	var deadline := Time.get_ticks_msec() + 1500
	while not FileAccess.file_exists(path) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(FileAccess.file_exists(path), "owned physical capture acknowledgement: " + label)
