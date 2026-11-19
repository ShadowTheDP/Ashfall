extends Node
## Isolated disk round trips: slots, entry rollback, Passage debit/claims and title input.
var _checks := 0
var _main: Node
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
	if not Profile.require_test_profile(): return
	_capture = DisplayServer.get_name() != "headless"
	if _capture:
		_check(get_viewport().get_visible_rect().size == Vector2(768, 480) and DisplayServer.window_get_size() == Vector2i(1536, 960), "768x480 logical / 1536x960 display window")
	_main = $Main
	await get_tree().process_frame
	# The first title of a session is the action list, not three slot cards.
	if not is_instance_valid(_main.title_screen):
		push_error("SAVE SLOTS FAIL: initial title missing")
		get_tree().quit(1)
		return
	_check(_main.title_screen._view == "main", "initial title opens on the main action list")
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	_check(_main.title_screen._action == 2 and _main.title_screen._view == "main", "W/S moves the main action list")
	await _key(KEY_ENTER)
	_check(_main.title_screen._view == "saves" and get_tree().paused, "Saves action opens the horizontal cards")
	var active := Profile.active_slot
	await _key(KEY_RIGHT)
	await _key(KEY_LEFT)
	_check(_main.title_screen._slot == active - 1 and Profile.active_slot == active, "A/D moves the card candidate without reading or writing a slot")
	await _shot("title-saves")
	await _key(KEY_ESCAPE)
	_check(_main.title_screen._view == "main", "Esc returns to the action list without leaving the title")
	await _key(KEY_UP)
	await _key(KEY_ENTER)
	await _wait(0.3)
	_check(Game.in_hub and not is_instance_valid(_main.title_screen), "Enter Hub starts the game exactly once")
	var base := Profile.SAVE_PATH
	var legacy := JSON.stringify({"version":5, "cells":21, "unlocked_runes":["canopy_rune"], "unlocked_weapons":["rusty_sword"]})
	_put(base, legacy)
	_check(Profile.select_slot(1) and Profile.cells == 21 and Profile.save(), "legacy file is slot 1")
	_check(_text(base + ".v5.bak") == legacy and JSON.parse_string(_text(base)).version == Profile.VERSION, "v5 migration retains exact original")
	for slot in [2, 3]:
		_check(Profile.select_slot(slot) and Profile.cells == 0 and Profile.unlocked_runes.is_empty(), "new independent slot %d" % slot)
		Profile.cells = slot * 21
		_check(Profile.save(), "commit slot %d" % slot)
	for slot in [1, 2, 3, 1]:
		Profile.cells = 999
		_check(Profile.select_slot(slot) and Profile.cells == slot * 21, "selection forces disk reload %d" % slot)
	_check(Profile.SAVE_PATH == base and Profile.unlocked_runes == ["canopy_rune"], "slot 1 unlocks retained, no stale source payload")
	_check(Profile.slot_path(2) == base + ".slot2" and Profile.slot_path(3) == base + ".slot3", "all slots stay beside exact isolated override")
	var third := _text(Profile.slot_path(3))
	for raw in ["{broken", JSON.stringify({"version":Profile.VERSION + 1, "cells":82}), JSON.stringify({"version":Profile.VERSION, "run_checkpoint":true})]:
		_put(Profile.slot_path(3), raw)
		_check(Profile.slot_summary(3).blocked and not Profile.select_slot(3), "corrupt/future slot cannot masquerade as empty")
		_check(Profile.active_slot == 1 and Profile.SAVE_PATH == base and _text(Profile.slot_path(3)) == raw, "rejected selection preserves active slot and bytes")
	# A nonempty but malformed checkpoint is not a blocked file: it must read as
	# unusable, keep its bytes, and never fall through to Hub or EMPTY display.
	var malformed := JSON.stringify({"version":Profile.VERSION, "run_checkpoint":{"kind":"biome_entry"}})
	_put(Profile.slot_path(3), malformed)
	var display := Profile.slot_summary(3)
	_check(not display.blocked and not display.resume and not str(display.resume_error).is_empty(), "malformed checkpoint is unusable, not blocked or resumable")
	_check(str(display.label) != "EMPTY" and not str(display.label).begins_with("HUB"), "unusable checkpoint never displays as empty or Hub")
	_check(_text(Profile.slot_path(3)) == malformed, "reading an unusable checkpoint never rewrites the file")
	var shown := Hud.slot_label(display)
	_check(shown == ContentText.of("UI_S7_TITLE_UNUSABLE_CHECKPOINT", "Checkpoint cannot resume: {reason} · original data retained.").format({"reason": str(display.resume_error)}) and not shown.contains("EMPTY") and not shown.begins_with("Hub"), "unusable checkpoint names its canonical reason instead of Hub or Empty")
	_put(Profile.slot_path(3), third)
	Game.settlement_pending = {"kills":1, "died":true}
	_check(not Profile.select_slot(2) and Profile.active_slot == 1, "pending settlement cannot cross slots")
	Game.settlement_pending.clear()
	_check(_main.start_node("ash_gate"), "fresh route entry")
	await get_tree().process_frame
	var seed_value := int(_main.level.data.seed)
	Game.player.hp = 80
	Game.player.weapon_slot = 1
	Game.player._apply_loadout()
	Game.build.use(2)
	Game.build.tick(0.5)
	_check(_main._save_checkpoint("biome_entry", seed_value), "entry captures carried HP and skill state")
	var entry := Profile.run_checkpoint.duplicate(true)
	_check(RunCheckpoint.error(entry).is_empty(), "captured checkpoint validates")
	var history := Game.route_history.duplicate()
	for field in ["version", "content", "state", "build", "hp", "uid", "charges"]:
		var bad: Dictionary = JSON.parse_string(JSON.stringify(entry))
		match field:
			"version": bad.version = RunCheckpoint.VERSION + 1
			"content": bad.content = "incompatible"
			"state": bad.state = {"run_node_id":"silent_regent"}
			"build": bad.build.slots[2] = null
			"hp": bad.hp = null
			"uid": bad.build.slots[1].uid = bad.build.slots[0].uid
			"charges": bad.build.slots[2].charges = 999
		_check(Profile.save(bad), "store isolated invalid-checkpoint fixture")
		Profile.load_profile(true)
		var raw := _text(base)
		_check(not RunCheckpoint.error(Profile.run_checkpoint).is_empty() and not _main.resume_checkpoint(), "reject invalid checkpoint " + field)
		if field == "content":
			var stale := Profile.slot_summary(1)
			_check(not stale.resume and not str(stale.resume_error).is_empty(), "stale-content checkpoint is never offered as resumable")
		_check(Game.route_history == history and _text(base) == raw, "rejection leaves world and saved bytes untouched")
	_check(Profile.save(entry), "restore valid entry fixture")
	var gold := Game.build.gold
	Game.add_cells(7)
	Game.build.gold += 99
	Game.run_keys.append("found_after_entry")
	Game.player.hp = 25
	_check(Profile.unlock_rune("homunculus_rune"), "permanent Rune writes while keeping entry snapshot")
	Profile.load_profile(true)
	_check(_main.resume_checkpoint(), "entry resumes from forced disk reload")
	_check(Game.route_history == history and int(_main.level.data.seed) == seed_value, "resume retains seed without appending route")
	_check(Game.run_cells == int(entry.state.run_cells) and Game.build.gold == gold and not Game.run_keys.has("found_after_entry"), "replay rolls Cells, gold and keys back together")
	_check(Profile.unlocked_runes.has("homunculus_rune") and Game.player.hp == 80 and Game.player.weapon_slot == 1, "permanent Rune survives, HP and weapon restore after actor ready")
	var skill := Game.build.slots[2]
	_check(int(skill.charges) == 1 and is_equal_approx(float(skill.cooldown), 1), "charges and partial cooldown restore")
	_check(Game.build.owns(skill), "restored slot is the canonical registered item")
	var canonical: Dictionary = Game.build._items[int(skill.uid)]
	canonical.charges = 0
	_check(int(Game.build.slots[2].charges) == 0, "restored slot is the canonical item")
	canonical.charges = 1
	var old_serial := int(entry.build.serial)
	_check(int(Game.build.create("rusty_sword").uid) > old_serial, "restored serial never reuses UID")
	var original := _text(base)
	DirAccess.make_dir_absolute(base + ".tmp")
	_check(not _main._save_checkpoint("biome_entry", seed_value) and _main.hud.checkpoint_blocked and get_tree().paused, "failed boundary pauses with explicit retry")
	await _shot("checkpoint-save-failed")
	await _key(KEY_ESCAPE)
	await _key(KEY_KP_ENTER)
	await _key(KEY_S)
	_check(_main.hud.checkpoint_blocked and get_tree().paused and not Game.run_over and _text(base) == original, "failed retry cannot resume, abandon, or replace last durable checkpoint")
	DirAccess.remove_absolute(base + ".tmp")
	await _key(KEY_S)
	_check(not _main.hud.checkpoint_blocked and not get_tree().paused, "successful explicit retry releases play")
	# A lawful first exit gives a reusable Passage fixture with a fixed destination.
	_check(Game.select_destination("hanging_gallery"), "choose legal destination")
	Game.run_phase = "transition"
	_main.enter_passage()
	Game.run_cells = 20
	Game.cells = 20
	Game.build.gold = 100
	Game.player.hp = 50
	Game.flask_charges = 0
	Game.carried_blueprints.append("chain_lash")
	_check(Game.save_passage(), "persist pre-transaction Passage")
	await _shot("passage")
	var before := Profile.run_checkpoint.duplicate(true)
	Profile._save_blocked = true
	_check(not Game.deliver_blueprint("chain_lash") and Game.carried_blueprints.has("chain_lash") and not Profile.delivered_blueprints.has("chain_lash"), "delivery failure rolls back both owners")
	_check(not Game.refill_flask() and Game.player.hp == 50 and Game.flask_charges == 0 and not Game.passage_claims.has("fountain"), "Fountain failure restores HP, charges and claim")
	_check(not Game.choose_mutation("edge") and Game.build.mutations.is_empty(), "Mutation failure rolls back effect")
	var item := Game.build.slots[2]
	var prior_item := item.duplicate(true)
	_check(not Game.craft(2, false) and item == prior_item and Game.build.gold == 100, "craft failure preserves canonical gear and gold")
	_check(not Game.claim_challenge("time") and Game.build.gold == 100 and Game.run_cells == 20 and not Game.passage_claims.has("time"), "challenge failure rolls back grant and claim")
	_check(Profile.run_checkpoint == before, "failed writes retain previous in-memory checkpoint")
	Profile.load_profile(true)
	_check(_main.resume_checkpoint(), "Passage failure can reload last durable state")
	_check(Game.deliver_blueprint("chain_lash") and Game.invest_blueprint("chain_lash", 5) == 5, "blueprint delivery and partial investment commit")
	Profile.load_profile(true)
	_check(_main.resume_checkpoint() and Game.run_cells == 15 and Profile.blueprint_cells.chain_lash == 5 and not Game.carried_blueprints.has("chain_lash"), "forced reload cannot recover spent blueprint Cells or redeliver")
	before = Profile.run_checkpoint.duplicate(true)
	Profile._save_blocked = true
	_check(Game.invest_blueprint("chain_lash", 5) == 0 and Game.run_cells == 15 and Profile.blueprint_cells.chain_lash == 5 and Profile.run_checkpoint == before, "investment failure restores permanent balance and saved wallet")
	Profile.load_profile(true)
	_check(Game.refill_flask() and Game.choose_mutation("flow") and Game.craft(2, true) and Game.claim_challenge("time"), "Passage services persist successful changes")
	var paid_gold := Game.build.gold
	var affix := str(Game.build.slots[2].affix)
	var saved_charge := Game.flask_charges
	Game.player.hp -= 30
	_check(Game.drink_flask(), "Passage flask consumption commits")
	var saved_hp := Game.player.hp
	Profile.load_profile(true)
	_check(_main.resume_checkpoint() and Game.build.gold == paid_gold and Game.build.slots[2].affix == affix and Game.build.mutations == ["flow"], "craft and Mutation survive disk reload")
	_check(not Game.refill_flask() and not Game.claim_challenge("time") and Game.flask_charges == saved_charge - 1 and Game.player.hp == saved_hp, "reopened Passage cannot repeat Fountain or challenge; consumed flask stays spent")
	Profile._save_blocked = true
	_check(not Game.reset_mutations() and Game.build.mutations == ["flow"] and Game.build.gold == paid_gold and Game.build.mutation_resets == 0, "failed Mutation reset restores effects, gold and price counter")
	Profile.load_profile(true)
	_check(Game.reset_mutations(), "Mutation reset commits")
	Profile.load_profile(true)
	_check(_main.resume_checkpoint() and Game.build.mutations.is_empty() and Game.build.mutation_resets == 1 and Game.build.gold == paid_gold - 30, "reset payment and next price survive reload")
	# Advance real legal route nodes to test Forge with a boss Passage boundary.
	for id in ["hanging_gallery", "stone_ramparts", "bridge_sentinel"]:
		_check(_main.start_node(id), "advance legal node " + id)
		if id == "bridge_sentinel": Game.boss_defeated = true
		var destination := "stone_ramparts" if id == "hanging_gallery" else ("bridge_sentinel" if id == "stone_ramparts" else "stilt_foundry")
		_check(Game.select_destination(destination), "select next legal node")
		Game.run_phase = "transition"
		_main.enter_passage()
	Game.run_cells = 30
	_check(Game.save_passage(), "persist boss Passage")
	before = Profile.run_checkpoint.duplicate(true)
	Profile._save_blocked = true
	_check(Game.invest_forge(5) == 0 and Game.run_cells == 30 and Profile.forge_cells == 0 and Profile.run_checkpoint == before, "Forge failure changes neither owner")
	Profile.load_profile(true)
	_check(Game.invest_forge(5) == 5, "Forge investment succeeds")
	Profile.load_profile(true)
	_check(_main.resume_checkpoint() and Game.run_cells == 25 and Profile.forge_cells == 5, "Forge Cells remain spent after reload")
	# Title routing and explicit destructive action use real key events.
	await _key(KEY_ESCAPE)
	await _key(KEY_T)
	_check(is_instance_valid(_main.title_screen) and _main.title_screen.visible and get_tree().paused and not Game.run_over, "pause T opens slots without settling checkpoint")
	await _shot("slots")
	await _key(KEY_TAB)
	await _key(KEY_L)
	_check(_main.title_screen.visible and not _main.exploration_map.visible and not _main.hud.paused, "title isolates map and pause input")
	await _key(KEY_DOWN)
	await _key(KEY_KP_ENTER)
	await _wait(0.2)
	_check(Profile.active_slot == 2 and Game.in_hub and Profile.cells == 42 and Profile.run_checkpoint.is_empty(), "keyboard selects independent slot 2")
	await _key(KEY_ESCAPE)
	await _key(KEY_T)
	await _key(KEY_UP)
	await _key(KEY_ENTER)
	await _wait(0.2)
	_check(Profile.active_slot == 1 and Game.run_phase == "passage" and Game.run_cells == 25 and Profile.forge_cells == 5, "switch back resumes original Passage without extra spending")
	await _key(KEY_ESCAPE)
	await _key(KEY_T)
	await _new_run_arm()
	_check(_main.title_screen.visible and not Profile.run_checkpoint.is_empty(), "new run needs explicit second confirmation")
	await _shot("slots-new-confirm")
	Profile._save_blocked = true
	# select_slot force-loads; make the actual temp destination unwritable instead.
	DirAccess.make_dir_absolute(base + ".tmp")
	await _key(KEY_ENTER)
	_check(_main.title_screen.visible and not Profile.run_checkpoint.is_empty() and _main.title_screen.note.begins_with("SAVE FAILED"), "failed abandonment retains checkpoint and title")
	await _shot("slots-save-failed")
	DirAccess.remove_absolute(base + ".tmp")
	var runs := Profile.runs
	await _key(KEY_ENTER)
	await _wait(0.2)
	_check(Game.in_hub and Profile.run_checkpoint.is_empty() and Profile.runs == runs + 1, "confirmed new run commits one abandonment and keeps unlocks")
	Profile.load_profile(true)
	_check(Profile.run_checkpoint.is_empty() and Profile.unlocked_runes.has("canopy_rune") and Profile.forge_cells == 5, "terminal checkpoint clear survives forced reload")
	for invalid_kills in [null, [], {}, -1, 1.5, "3"]:
		var damaged := entry.duplicate(true)
		damaged.state.kills = invalid_kills
		_check(Profile.save(damaged), "store damaged count recovery fixture")
		await _key(KEY_ESCAPE)
		await _key(KEY_T)
		await _key(KEY_ENTER)
		_check(_main.title_screen.visible and not _main.title_screen.note.is_empty(), "Continue rejects damaged count without closing title")
		await _new_run_arm()
		var prior_runs := Profile.runs
		var prior_kills := Profile.total_kills
		var disk_before := _text(base)
		DirAccess.make_dir_absolute(base + ".tmp")
		await _key(KEY_ENTER)
		_check(_main.title_screen.visible and _main.title_screen.note.begins_with("SAVE FAILED") and Profile.runs == prior_runs and _text(base) == disk_before, "failed damaged-checkpoint recovery retains counters and bytes")
		DirAccess.remove_absolute(base + ".tmp")
		await _key(KEY_ENTER)
		await _wait(0.2)
		_check(Game.in_hub and Profile.run_checkpoint.is_empty() and Profile.runs == prior_runs + 1 and Profile.total_kills == prior_kills, "two accepts recover damaged checkpoint with zero invalid kills")
		Profile.load_profile(true)
		_check(Profile.run_checkpoint.is_empty() and Profile.runs == prior_runs + 1 and Profile.total_kills == prior_kills and Profile.unlocked_runes.has("canopy_rune"), "recovery survives forced reload and keeps unlocks")
	# A second explicit accept confirms; any navigation cancels the pending
	# confirmation first, and the keyboard accept is edge-triggered.
	_check(Profile.save(entry), "store checkpoint for confirmation-key fixture")
	_check(str(entry.kind) == "biome_entry", "confirmation fixture is a biome entry checkpoint")
	Profile.load_profile(true)
	_main.enter_hub()
	await _wait(0.2)
	var confirm_runs := Profile.runs
	var confirm_disk := _text(base)
	await _key(KEY_ESCAPE)
	await _key(KEY_T)
	# The pause-menu title opens on the slot cards; the new-run action is action 1.
	var title: Node = _main.title_screen
	var slot_before: int = title._slot
	await _new_run_arm()
	_check(title._confirm_new and int(title._action) == 1, "accept arms the new-run confirmation")
	await _key(KEY_DOWN)
	await _key(KEY_UP)
	_check(not title._confirm_new and title._slot == slot_before and title._view == "main" and int(title._action) == 1, "DOWN then UP cancels confirmation and returns to the new-run action")
	_check(Profile.runs == confirm_runs and _text(base) == confirm_disk and str(Profile.run_checkpoint.kind) == "biome_entry", "cancelled confirmation changes no counters or bytes before Enter")
	await _key(KEY_UP)
	await _key(KEY_ENTER)
	await _wait(0.3)
	_check(not is_instance_valid(_main.title_screen) and not Game.in_hub and int(_main.level.data.seed) == seed_value and not Profile.run_checkpoint.is_empty(), "Enter resumes the same entry checkpoint after a cancelled confirmation")
	await _key(KEY_ESCAPE)
	await _key(KEY_T)
	await _new_run_arm()
	await _key(KEY_ENTER)
	await _wait(0.3)
	_check(Game.in_hub and Profile.run_checkpoint.is_empty() and Profile.runs == confirm_runs + 1, "second accept confirms the new run")
	print("SAVE SLOTS OK (%d checks)" % _checks)
	get_tree().quit()

func _new_run_arm() -> void:
	var title: Node = _main.title_screen
	if title == null:
		_check(false, "title available for new-run arm")
		return
	if str(title._view) != "main":
		await _key(KEY_ESCAPE)
	var guard := 0
	while int(title._action) != 1 and guard < 4:
		await _key(KEY_DOWN)
		guard += 1
	_check(int(title._action) == 1 and str(title._view) == "main", "new-run action focused before accept")
	await _key(KEY_ENTER)

func _key(code: int) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		if DisplayServer.get_name() != "headless": print("SAVE_SLOTS_PROBE INPUT %dms key=%d pressed=%s" % [Time.get_ticks_msec(), code, str(event.pressed)])
		await get_tree().process_frame

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout

func _shot(label: String) -> void:
	if not _capture: return
	DirAccess.make_dir_recursive_absolute("res://output/screenshots/saves")
	await _wait(0.3)
	await get_tree().process_frame
	$Main.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://output/screenshots/saves/" + label + ".png") == OK, "capture " + label)

	await _physical_capture(label)
	print("SAVE_SLOTS_PROBE FRAME %dms %s" % [Time.get_ticks_msec(), label])
	if OS.get_environment("ASHFALL_CAPTURE_ACK_DIR").is_empty(): await get_tree().create_timer(0.08, true).timeout

func _put(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "open isolated fixture")
	if file != null:
		file.store_string(text)
		file.close()

func _text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return ""
	var text := file.get_as_text()
	file.close()
	return text

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		push_error("SAVE SLOTS FAIL: " + message)
		get_tree().quit(1)

func _physical_capture(label: String) -> void:
	var directory := OS.get_environment("ASHFALL_CAPTURE_ACK_DIR")
	if directory.is_empty(): return
	var path := directory.path_join(label + ".json")
	var deadline := Time.get_ticks_msec() + 1500
	while not FileAccess.file_exists(path) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(FileAccess.file_exists(path), "owned physical capture acknowledgement: " + label)
