extends Node
## L4 service/transaction fixtures, NOT a full-run or human-play acceptance.
## World pickup and service controls use input; boundary fixtures set resources/context.
var _main: Node
var _p: Player
var _checks := 0
var _fails := 0

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
	await _frames(3)
	Profile.reset_profile()
	Profile.cells = 500
	for id in ["chain_lash", "arc_saber", "fractal_edge"]:
		_check(not Profile.unlock("weapon", id) and not Profile.gear_available(id) and Profile.cells == 500, "legacy bank cannot bypass blueprint " + id)
	# Existing ownership is an asset, including migrated legacy purchases.
	Profile.unlocked_weapons.append("arc_saber")
	Profile.selected_weapon = "arc_saber"
	Profile.save()
	Profile.load_profile(true)
	_check(Profile.gear_available("arc_saber") and Profile.selected_weapon == "arc_saber", "existing blueprint-target ownership remains usable on reload")
	Profile.reset_profile()
	_main = $Main
	_check(Data.valid_passage(Data.passage), "passage content validates")
	var bad := Data.passage.duplicate(true)
	bad.blueprints.chain_lash.cost = 0
	_check(not Data.valid_passage(bad), "invalid investment cost fails schema")
	for key in ["cost", "step", "capacity"]:
		bad = Data.passage.duplicate(true)
		bad.mutation_reset.erase(key)
		_check(not Data.valid_passage(bad), "mutation_reset." + key + " is required")
		bad.mutation_reset[key] = 0
		_check(not Data.valid_passage(bad), "mutation_reset." + key + " must stay positive")
	for key in ["upgrade_cost", "reforge_cost", "reforge_step"]:
		bad = Data.passage.duplicate(true)
		bad.craft.erase(key)
		_check(not Data.valid_passage(bad), "craft." + key + " is required")
		bad.craft[key] = 0
		_check(not Data.valid_passage(bad), "craft." + key + " must stay positive")
	_check(_main.start_node("ash_gate"), "formal first visit starts")
	await _frames(4)
	_p = Game.player
	var build := Game.build
	_check(build.mutation_capacity == 0 and not Game.choose_mutation("edge"), "no services or Mutation slots in biome")
	for seed in 12:
		_check(Game.create_loot("chest", seed).id == "rusty_sword", "locked blueprint absent from fresh loot")
	var pickup := preload("res://scripts/world/progress_pickup.gd").new()
	pickup.item_type = "blueprint"
	pickup.item_id = "chain_lash"
	pickup.position = _p.global_position
	_main.world.add_child(pickup)
	await _key(KEY_R)
	_check(Game.carried_blueprints.has("chain_lash") and not Profile.delivered_blueprints.has("chain_lash"), "R pickup carries blueprint without permanent grant")
	_check(not Game.deliver_blueprint("chain_lash"), "delivery outside Passage rejected")
	_main._on_exit_chosen("hanging_gallery")
	await _wait(1.8)
	_check(Game.service_ready() and Game.pending_destination == "hanging_gallery" and build.mutation_capacity == 1, "first exit snapshots state and opens one slot")
	await _walk(_main.passage.COLLECTOR_X)
	await _key(KEY_R)
	_check(get_tree().paused and is_instance_valid(_main.collector), "keyboard opens real Collector")
	await _capture("collector-entry")
	await _key(KEY_DOWN)
	_check(_main.collector._index == 1, "Collector keyboard selection responds")
	await _capture("collector-locked")
	await _key(KEY_UP)
	_check(_main._fade_rect.color.a < 0.05, "in-place service does not black out its UI on open")
	var original := FileAccess.get_file_as_string(Profile.SAVE_PATH)
	Profile._save_blocked = true
	await _key(KEY_ENTER)
	_check(Game.carried_blueprints.has("chain_lash") and not Profile.delivered_blueprints.has("chain_lash") and FileAccess.get_file_as_string(Profile.SAVE_PATH) == original, "failed delivery preserves carried item and disk")
	_check("SAVE FAILED" in _main.collector._note and "NOTHING COMMITTED" in _main.collector._note and "RETRY" in _main.collector._note, "failed delivery has persistent truthful retry feedback")
	await _capture("collector-save-failed")
	Profile._save_blocked = false
	await _key(KEY_ENTER)
	_check("SAVED" in _main.collector._note and "DELIVERED" in _main.collector._note, "delivery success follows real save, not just confirm")
	_check(Profile.delivered_blueprints.has("chain_lash") and not Game.carried_blueprints.has("chain_lash"), "Collector commits delivery exactly once")
	await _capture("collector")
	Game.run_cells = 7
	_check("5 CELLS" in str(_main.collector._row("chain_lash")[1]), "Collector previews exact full-step cost")
	await _key(KEY_ENTER)
	_check(Game.run_cells == 2 and int(Profile.blueprint_cells.chain_lash) == 5 and not Profile.gear_available("chain_lash"), "partial investment spends carried Cells only")
	_check(_main.collector._unlocked_id.is_empty(), "partial investment never raises the unlock card")
	original = FileAccess.get_file_as_string(Profile.SAVE_PATH)
	Profile._save_blocked = true
	await _key(KEY_ENTER)
	_check(Game.run_cells == 2 and int(Profile.blueprint_cells.chain_lash) == 5 and FileAccess.get_file_as_string(Profile.SAVE_PATH) == original, "failed investment rolls back progress and money")
	_check(_main.collector._unlocked_id.is_empty(), "failed save never raises the unlock card")
	_check("2 CELLS" in str(_main.collector._row("chain_lash")[1]), "last partial cost matches real available wallet")
	Profile._save_blocked = false
	await _key(KEY_ENTER)
	_check("2 CELLS INVESTED" in _main.collector._note, "receipt shows actual committed partial amount")
	await _capture("collector-partial")
	_check(Game.run_cells == 0 and int(Profile.blueprint_cells.chain_lash) == 7, "last partial amount never overdraws")
	await _key(KEY_ENTER)
	_check(int(Profile.blueprint_cells.chain_lash) == 7, "zero funds and repeated interaction do not mint progress")
	_check("NEED CARRIED CELLS" in str(_main.collector._row("chain_lash")[1]) and "NOT COMMITTED" in _main.collector._note, "zero cells is unavailable, never falsely committed")
	var message: String = _main.collector._note
	await _wait(2.0)
	_check(_main.collector._note == message, "service result persists until selection or new action")
	await _capture("collector-empty")
	var original_name: String = Data.passage.blueprints.chain_lash.name
	Data.passage.blueprints.chain_lash.name = "Chain Lash / " + "EXTENDED_BLUEPRINT_IDENTITY_".repeat(6)
	_main.collector._canvas.queue_redraw()
	await _frames(2)
	_check(_main.collector._detail_count > 4, "long blueprint identity remains in scrollable details")
	await _capture("collector-long-top")
	for i in 60: await _key(KEY_D)
	_check(_main.collector._detail_scroll == _main.collector._detail_count - 3, "Collector reaches final identity detail with keyboard")
	await _capture("collector-long-bottom")
	Data.passage.blueprints.chain_lash.name = original_name
	_main.collector._detail_scroll = 0
	_main.collector._canvas.queue_redraw()
	Profile.load_profile(true)
	_check(int(Profile.blueprint_cells.chain_lash) == 7 and Profile.delivered_blueprints.has("chain_lash"), "delivered partial progress reloads")
	Game.run_cells = 20
	# Real keyboard crossing through the service: 7 -> 12 -> 17 -> 20, where the
	# last ordinary step clamps to the remaining cost.
	for n in 3: await _key(KEY_ENTER)
	_check(int(Profile.blueprint_cells.chain_lash) == 20 and Game.run_cells == 7 and Profile.gear_available("chain_lash"), "keyboard completion clamps to the remaining cost and unlocks the drop")
	_check(_main.collector._unlocked_id == "chain_lash", "a persisted crossing raises the unlock card")
	await _capture("collector-unlocked")
	await _key(KEY_ENTER)
	_check(_main.collector._unlocked_id.is_empty() and Game.run_cells == 7 and int(Profile.blueprint_cells.chain_lash) == 20, "Enter closes the unlock card without spending again")
	await _capture("collector-unlocked-closed")
	_check(Game.invest_blueprint("chain_lash", 5) == 0 and not Game.deliver_blueprint("chain_lash") and Game.run_cells == 7, "completed blueprint cannot be double charged or delivered")
	_check(Game.create_loot("chest", 2).id == "chain_lash", "new loot now resolves unlocked content")
	var hp := _p.hp
	var flask := Game.flask_charges
	var node_time := Game.node_time
	for code in [KEY_Q, KEY_E, KEY_1, KEY_2, KEY_H, KEY_M, KEY_R]: await _key(code)
	_check(_p.hp == hp and Game.flask_charges == flask and Game.node_time == node_time and not _main.exploration_map.is_open(), "service owns combat heal map restart keys and timer")
	await _key(KEY_ESCAPE)
	_check(not get_tree().paused and Game.pending_destination == "hanging_gallery", "service close retains physical destination")
	await _walk(_main.passage.MUTATION_X)
	await _key(KEY_R)
	await _capture("mutation")
	_check(_main.collector._ids[0] == "reset", "Reset is the first Mutation row")
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	_check(build.mutations == ["edge"] and is_equal_approx(Game.total_damage_mult(), 1.12), "keyboard chooses one real outgoing-damage effect")
	await _capture("mutation-chosen")
	var mutations_before := build.mutations.duplicate()
	# Exercise the two-line effect window with long in-memory text, then restore it.
	var selected_id: String = _main.collector._ids[_main.collector._index]
	var original_text := str(Data.passage.mutations[selected_id].text)
	Data.passage.mutations[selected_id].text = "Long effect line for the isolated scroll fixture. ".repeat(12)
	_main.collector._canvas.queue_redraw()
	await _frames(2)
	_check(_main.collector._detail_count > 3, "selected Mutation keeps a scrollable effect")
	for i in 20: await _key(KEY_D)
	_check(_main.collector._detail_scroll == _main.collector._detail_count - 2 and build.mutations == mutations_before, "A/D scrolls a long effect to its last row without committing")
	Data.passage.mutations[selected_id].text = original_text
	_main.collector._canvas.queue_redraw()
	await _frames(2)
	for i in _main.collector._ids.size():
		var current: String = _main.collector._ids[_main.collector._index]
		if current != "reset" and not Profile.mutation_available(current): break
		await _key(KEY_DOWN)
	await _capture("mutation-locked")
	for i in _main.collector._ids.size():
		if _main.collector._index == 0: break
		await _key(KEY_DOWN)
	await _capture("mutation-reset")
	_check(not Game.choose_mutation("edge") and not Game.choose_mutation("flow") and not Game.choose_mutation("reaper"), "duplicate full and locked choices rejected")
	await _key(KEY_ESCAPE)
	await _walk((_main.passage.MUTATION_X + _main.passage.CRAFT_X) * 0.5)
	await _wait(0.2)
	var enemy := Enemy.new()
	enemy.configure("grunt", Data.enemies.grunt)
	enemy.position = _p.global_position + Vector2(58, 0)
	_main.world.add_child(enemy)
	await _frames(2)
	var before := enemy.hp
	await _key(KEY_J)
	await _wait(0.22)
	_check(enemy.hp < before and before - enemy.hp == Damage.compute(float(Data.weapons.rusty_sword.combo[0].damage) * 1.12, 0, false, 1), "Edge changes actual melee collision damage")
	enemy.queue_free()
	await _wait(0.6)
	build.gold = build.reset_cost() - 1
	_check(not Game.reset_mutations() and build.mutations == ["edge"], "insufficient reset funds preserve effects")
	build.gold = 200
	var coins := build.gold
	_check(Game.reset_mutations() and build.gold == coins - 30 and build.reset_cost() == 45 and is_equal_approx(Game.total_damage_mult(), 1.0), "paid reset removes effect once and increases next cost")
	_check(not Game.reset_mutations(), "empty reset cannot charge")
	_check(Game.choose_mutation("flow"), "choose recharge Mutation")
	var skill := build.slots[2]
	_check(build.use(2) and is_equal_approx(float(skill.cooldown), 1.2), "Flow starts actual reduced skill timer")
	build.tick(1.21)
	_check(int(skill.charges) == 2, "Flow actual charge restored before original 1.5 seconds")
	_check(Game.reset_mutations() and Game.choose_mutation("shell"), "swap to defensive Mutation")
	hp = _p.hp
	_p.take_hit({"damage":20, "source_pos":_p.position - Vector2(40,0)})
	_check(is_equal_approx(hp - _p.hp, 17), "Shell changes actual incoming damage")
	await _wait(0.8)
	build.gold = 0
	var item := build.slots[2]
	var snapshot := item.duplicate(true)
	_check(not Game.craft(2, false) and item == snapshot and not Game.craft(-1, true), "invalid or unaffordable craft is atomic")
	build.gold = 200
	await _walk(_main.passage.CRAFT_X)
	await _key(KEY_R)
	_check(get_tree().paused and _main.collector.service == "craft", "walking opens shared craft modal")
	_check(_main.collector._ids.size() == 8 and not _main.collector._ids.has("upgrade/4"), "craft UI offers only slots accepted by Game.craft")
	await _capture("craft")
	await _key(KEY_ESCAPE)
	build.use(2)
	var cooldown: float = item.cooldown
	var charges: int = item.charges
	_check(Game.craft(2, false) and item.quality == "etched" and item.cooldown == cooldown and item.charges == charges, "upgrade keeps UID and does not refill skill")
	coins = build.gold
	_check(not Game.craft(2, false) and build.gold == coins, "max quality cannot double charge")
	_check(Game.craft(2, true) and item.affix == "keen" and item.charges == charges and item.cooldown == cooldown, "reforge changes affix but preserves mutable state")
	_check(Game.craft(2, true) and item.affix == "quick" and build.cooldown(item) < 1.5, "second reforge changes actual cooldown")
	_main._open_service("craft")
	for i in 4: await _key(KEY_DOWN)
	await _capture("craft-max")
	await _key(KEY_DOWN)
	await _capture("craft-reforge")
	coins = build.gold
	build.gold = 0
	await _capture("craft-unaffordable")
	build.gold = coins
	await _key(KEY_ESCAPE)
	_check(not Game.invest_forge(5), "ordinary Passage has no Forge")
	_check(Game.challenge_available("time") and not Game.challenge_available("streak") and not Game.challenge_available("flawless"), "ordinary challenge result uses captured biome conditions")
	coins = build.gold
	var cells := Game.run_cells
	await _walk(_main.passage.CHALLENGE_X)
	await _key(KEY_R)
	await _capture("challenge")
	await _key(KEY_ENTER)
	_check(not Game.claim_challenge("time") and build.gold == coins + 24 and Game.run_cells == cells + 5, "keyboard challenge payout once only")
	await _capture("challenge-claimed")
	await _key(KEY_ESCAPE)
	Game.flask_charges = 0
	await _walk(_main.passage.FOUNTAIN_X)
	await _capture("fountain-ready")
	await _key(KEY_R)
	_check(_p.hp == _p.max_hp and Game.flask_charges == Game.flask_capacity, "keyboard Fountain restores real HP and flask")
	await _capture("fountain")
	_p.take_hit({"damage":10,"source_pos":_p.position - Vector2(40,0)})
	hp = _p.hp
	_check(not Game.refill_flask() and _p.hp == hp, "reopening Fountain never repeats its grant")
	for stage in [["hanging_gallery", "stone_ramparts", 2], ["stone_ramparts", "bridge_sentinel", 3]]:
		_check(_main.start_node(stage[0]), "legal next biome preserves service build")
		await _frames(3)
		_main._on_exit_chosen(stage[1])
		await _wait(1.8)
		_check(Game.build == build and build.mutation_capacity == stage[2] and is_same(build.slots[2], item) and build.mutations == ["shell"], "real transitions expand slots and retain exact gear/effects")
	_check(Game.refill_flask(), "new Passage resets Fountain claim")
	Game.carried_blueprints.append("reaper")
	Game.run_cells = 20
	_check(Game.deliver_blueprint("reaper") and Game.invest_blueprint("reaper", 15) == 15 and Profile.mutation_available("reaper") and Game.choose_mutation("reaper"), "Mutation blueprint requires delivery and complete investment")
	_p.take_hit({"damage":20, "source_pos":_p.position - Vector2(40,0)})
	hp = _p.hp
	Game.add_kill()
	_check(is_equal_approx(_p.hp - hp, 3) and Game.kill_streak == 1, "Reaper reacts to ordinary kill and heals actual HP")
	Game.add_kill(true)
	_check(is_equal_approx(_p.hp - hp, 3) and Game.kill_streak == 1, "Boss kills neither heal Reaper nor count ordinary streak")
	Game.add_kill()
	Game.add_kill()
	Game.note_damage_taken(1)
	_check(Game.kill_streak == 0 and Game.best_kill_streak == 3, "damage resets current streak but keeps achieved milestone")
	build.gold = 200
	_check(Game.reset_mutations() and Game.choose_mutation("shell"), "reset clears all selected effects without closing three slots")
	# Explicit service-context fixtures below test limits; no claim of route traversal.
	Game.run_node_id = "bridge_sentinel"
	Game.boss_defeated = true
	Game.passage_snapshot = {"time":999.0,"streak":0,"flawless":false}
	_check(Game.challenge_ids() == ["flawless"] and not Game.claim_challenge("flawless"), "damaged Boss snapshot cannot win flawless reward")
	Game.run_cells = 60
	Profile._save_blocked = true
	_check(Game.invest_forge(5) == 0 and Game.run_cells == 60 and Profile.forge_cells == 0, "failed Forge save refunds whole transaction")
	Profile._save_blocked = false
	await _walk(_main.passage.FORGE_X)
	await _key(KEY_R)
	_check(get_tree().paused and _main.collector.service == "forge", "Boss Passage exposes keyboard Forge")
	await _capture("forge")
	await _key(KEY_ENTER)
	_check(Game.run_cells == 55 and Profile.forge_cells == 5, "Boss Forge accepts retained Cells incrementally")
	await _key(KEY_ESCAPE)
	Profile.load_profile(true)
	_check(Profile.forge_cells == 5, "Forge partial investment reloads")
	_check(Game.invest_forge(100) == 35 and Game.run_cells == 20 and Profile.forge_chance() == 1.0 and Game.invest_forge(5) == 0, "Forge completion clamps cost and repeat is harmless")
	_main._open_service("forge")
	await _capture("forge-complete")
	await _key(KEY_ESCAPE)
	for seed in 12:
		_check(Game.create_loot("drop", seed).quality == "etched", "completed Forge changes future generated quality")
	_check(item.quality == "etched" and build.slots[0].quality == "plain", "Forge never retroactively mutates carried gear")
	_check(build.mutation_capacity == 3, "earned capacity persists in Boss Passage context")
	_check(Game.choose_mutation("edge") and Game.choose_mutation("flow") and build.mutations.size() == 3, "three distinct effects fit final capacity")
	_main._open_service("mutation")
	await _capture("mutation-full")
	await _key(KEY_ESCAPE)
	Game.carried_blueprints.append("arc_saber")
	var permanent := Profile.blueprint_cells.duplicate(true)
	Game.end_run(false)
	_check(Game.build == null and Game.carried_blueprints.is_empty() and Game.run_cells == 0 and Game.passage_snapshot.is_empty(), "death clears uncommitted blueprint gold build mutations and challenge state")
	_check(not Game.craft(0, false) and not Game.claim_challenge("time") and not Game.choose_mutation("edge"), "late service callbacks after death are harmless")
	Profile.load_profile(true)
	_check(Profile.blueprint_cells == permanent and Profile.forge_cells == 40 and Profile.gear_available("chain_lash") and not Profile.delivered_blueprints.has("arc_saber"), "only committed permanent progress survives death and reload")
	print("L4 PASSAGE %s (%d checks, %d failures)" % ["OK" if _fails == 0 else "FAILED", _checks, _fails])
	_main.enter_hub()
	await _frames(3)
	get_tree().quit(0 if _fails == 0 else 1)

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await get_tree().process_frame
	_main.hud.queue_redraw()
	if is_instance_valid(_main.collector): _main.collector._canvas.queue_redraw()
	await RenderingServer.frame_post_draw
	var folder := "res://output/screenshots/l4"
	DirAccess.make_dir_recursive_absolute(folder)
	_check(get_viewport().get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK, "capture " + label)
	await _physical_capture(label)
	print("L4 FRAME %dms %s" % [Time.get_ticks_msec(), label])
	if "entry" not in label and OS.get_environment("ASHFALL_CAPTURE_ACK_DIR").is_empty(): await get_tree().create_timer(0.08, true).timeout

func _walk(x: float) -> void:
	var deadline := Time.get_ticks_msec() + 3000
	Input.action_press("move_right")
	while _p.position.x < x - 12 and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	Input.action_release("move_right")
	await _wait(0.1)
	_check(absf(_p.position.x - x) < 70, "walk reaches service without relocation")

func _key(code: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		if DisplayServer.get_name() != "headless": print("L4 INPUT %dms key=%d pressed=%s" % [Time.get_ticks_msec(), code, str(pressed)])
		await get_tree().process_frame

func _frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("L4 PASSAGE FAIL: " + message)

func _physical_capture(label: String) -> void:
	var directory := OS.get_environment("ASHFALL_CAPTURE_ACK_DIR")
	if directory.is_empty(): return
	var path := directory.path_join(label + ".json")
	var deadline := Time.get_ticks_msec() + 1500
	while not FileAccess.file_exists(path) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(FileAccess.file_exists(path), "owned physical capture acknowledgement: " + label)
