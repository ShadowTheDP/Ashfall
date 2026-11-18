extends Node
## Automatic keyboard play. Reads world state, never changes actors, rewards or routes.
## This is NOT human signoff. Seed fixes randomness, not outcomes.
var _main: Node
var _frame := 0
var _held: Dictionary = {}
var _capture := false
var _run := 0
var _checks := 0
var _started := 0
var _evidence: Array = []
var _shots: Dictionary = {}
var _limit_node := ""
var _failed := false
var _transactions := {"scroll":0, "replacement":0, "purchase":0}
var _boss_states: Dictionary = {}
var _passage_only := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Profile.require_test_profile(): return
	_capture = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute("res://output/screenshots/l6")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stop-after="):
			_limit_node = arg.trim_prefix("--stop-after=")
		if arg == "--passage-only":
			_passage_only = true
	_started = Time.get_ticks_msec()
	seed(60601)
	Profile.reset_profile()
	_main = $Main
	await _frames(40)
	if _passage_only:
		await _passage_fixture()
		return
	await _press(KEY_ENTER)
	await _frames(40)
	if not _check(Game.in_hub and Profile.unlocked_runes.is_empty(), "fresh title -> Hub, no granted Runes"): return
	for attempt in 2:
		_run = attempt
		if attempt == 1:
			var persisted := {"runes":Profile.unlocked_runes.duplicate(), "victories":Profile.victories,
				"blueprints":Profile.blueprint_cells.duplicate(), "forge":Profile.forge_cells}
			Profile.load_profile(true)
			if not _check(Profile.unlocked_runes == persisted.runes and Profile.victories == persisted.victories and Profile.victories == 1 and Profile.blueprint_cells == persisted.blueprints and Profile.forge_cells == persisted.forge and Profile.run_checkpoint.is_empty(), "first victory and investments survive forced disk reload before alternate route"): return
		await _flat(float(_main.hub.DOOR_X) - 25)
		await _press(KEY_R)
		await _frames(50)
		var route: Array = Data.route_graph.default_0_bsc_route.duplicate()
		if attempt == 1:
			route[1] = "silt_cistern"
		for index in route.size():
			var id: String = route[index]
			if not _check(Game.run_node_id == id and Game.run_bsc == 0, "entered " + id): return
			_log("enter")
			await _shot(id)
			await _visit()
			if _failed: return
			if not _limit_node.is_empty() and id == _limit_node:
				_log("BOUNDED DIAGNOSTIC ONLY")
				_finish(false)
				return
			var target := str(route[index + 1]) if index + 1 < route.size() else ""
			var exit: Dictionary = {}
			for item: Dictionary in _main.level.data.exits:
				if str(item.to) == target:
					exit = item
			if not _check(not exit.is_empty(), "destination has physical exit"): return
			await _go(exit.pos)
			await _press(KEY_R)
			await _frames(240)
			if target.is_empty():
				if not _check(Game.victory and Game.run_over and Profile.boss_cells_unlocked == 1, "nine-visit keyboard victory / BSC1"): return
				_log("victory")
				await _shot("victory")
			else:
				if not _check(Game.run_phase == "passage", "physical exit enters Passage"): return
				await _passage()
		if not _check(Game.route_history == route and Game.defeated_bosses.size() == 3, "exact route and three actual boss deaths"): return
		if not _check(Profile.unlocked_runes.has("canopy_rune") and Profile.unlocked_runes.has("homunculus_rune"), "earned persistent Runes"): return
		if attempt == 1:
			if not _check(Profile.unlocked_runes.has("phase_rune"), "alternative has distinct earned reward"): return
		await _press(KEY_ENTER)
		await _frames(40)
		if not _check(Game.in_hub, "keyboard returns to Hub"): return
		await _shot("hub_unlocks")
	if not _check(_transactions.scroll >= 12 and _transactions.replacement > 0 and _transactions.purchase >= 2, "observed Scrolls, replacements and paid purchases in both runs"): return
	for boss in ["bridge_sentinel", "clock_warden", "silent_regent"]:
		for state in ["windup", "attack"]:
			if not _check(_boss_states.has(boss + "/" + state), "observed boss state " + boss + "/" + state): return
	_finish(true)


func _visit() -> void:
	var level: Node = _main.level
	for kind in ["gold", "scroll"]:
		await _loot(kind)
	var rune: String = level.data.rune
	if not rune.is_empty() and not Profile.unlocked_runes.has(rune):
		var room: Dictionary = level.data.rooms[int(level.data.rune_room)]
		await _go(room.rect.position + Vector2(320, -24))
		await _fight_room(int(level.data.rune_room))
		if not _check(is_instance_valid(level.rune_pickup), "guard reveals actual Rune pickup"): return
		await _go(level.rune_pickup.position)
		for n in 3:
			await _press(KEY_R)
			await _modal()
			await _frames(18)
			if Profile.unlocked_runes.has(rune):
				break
		if not _check(Profile.unlocked_runes.has(rune), "keyboard earned " + rune): return
	for key: Dictionary in level.data.keys:
		await _go(key.pos)
		await _press(KEY_R)
		await _frames(18)
		if not _check(Game.run_keys.has(str(key.id)), "keyboard acquired " + str(key.id)): return
	for gate in level._gates.values():
		if not gate.unlocked and str(gate.spec.kind) == "key" and Game.run_keys.has(str(gate.spec.key)):
			var rect: Rect2 = gate.spec.rect
			var room: Dictionary = level.data.rooms[level.data.room_ids[gate.spec.room]]
			await _go(Vector2(rect.position.x - 42, room.rect.position.y - 24))
			await _press(KEY_R)
			await _frames(4)
			if not _check(gate.unlocked, "keyboard opens required local gate"): return
	for id: String in Data.passage.blueprints:
		var cfg: Dictionary = Data.passage.blueprints[id]
		if cfg.biome == Game.run_node_id and not Profile.delivered_blueprints.has(id):
			var room: Dictionary = level.data.rooms[level.data.room_ids[cfg.room]]
			await _go(room.rect.position + Vector2(cfg.at[0], cfg.at[1]))
			await _press(KEY_R)
			if not _check(Game.carried_blueprints.has(id), "physical blueprint pickup " + id): return
			await _shot("blueprint_carried")
	# Free replacement and paid offers use the production comparison UI.
	await _loot("chest")
	await _loot("shop")
	if not str(level.data.boss).is_empty():
		await _go(level.data.boss_at)
		await _fight_room(int(level.data.room_ids.arena))
		if not _check(Game.boss_defeated and Game.defeated_bosses.has(Game.run_node_id), "boss died through normal combat"): return
		await _shot("boss_defeated_" + Game.run_node_id)
	await _loot("gear")
	await _shot("explored_" + Game.run_node_id)
	await _press(KEY_TAB)
	await _shot("map")
	await _press(KEY_ESCAPE)
	_log("visited")


func _loot(kind: String) -> void:
	var expected := false
	for placement: Dictionary in Data.gear.placements:
		if placement.kind == kind and _main.level.data.room_ids.has(placement.room):
			expected = true
	for node in _main.level.get_children():
		if node is RunLoot and node.kind == kind and node.available():
			await _go(node.position)
			var gold := Game.build.gold
			var amount: int = node.amount
			await _press(KEY_R)
			if kind == "gold":
				if not _check(Game.build.gold == gold + amount, "gold pickup changed wallet exactly"): return
			else:
				if not _check(_main.build_screen.is_open(), "expected " + kind + " comparison opened"): return
				await _modal()
			return
	if not _check(not expected, "expected " + kind + " offer exists"): return


func _modal() -> void:
	if not _main.build_screen.is_open():
		return
	await _shot("scroll" if _main.build_screen.offer.kind == "scroll" else "gear")
	var offer: RunLoot = _main.build_screen.offer
	if offer.kind == "scroll":
		var before: int = Game.build.attributes.brutality
		await _press(KEY_1)
		if not _check(Game.build.attributes.brutality == before and _main.build_screen.is_open() and not offer.consumed, "Scroll number key previews without consuming"): return
		await _press(KEY_ENTER)
		if not _check(Game.build.attributes.brutality == before + 1 and not _main.build_screen.is_open(), "Scroll commit increases selected axis once"): return
		_transactions.scroll += 1
	else:
		var definition: Dictionary = Game.build.definition(offer.item)
		var cost: int = offer.cost
		if Game.build.gold < cost:
			_log("SKIP unaffordable offer " + str(offer.item.id))
			await _press(KEY_ESCAPE)
			return
		var selection := 1 if definition.get("action", "") in ["shield", "aegis"] else 0
		await _press(KEY_1 + selection)
		var slot: int = _main.build_screen._slots[selection]
		var old: Dictionary = Game.build.slots[slot]
		var uid: int = offer.item.uid
		var expected := Game.build.gold - cost + Game.build.recycle_value(old)
		await _press(KEY_ENTER)
		if not _check(not _main.build_screen.is_open() and Game.build.slots[slot].uid == uid and Game.build.gold == expected, "replacement/purchase commits exact item and wallet"): return
		_transactions.replacement += 1
		if cost > 0: _transactions.purchase += 1
	await _frames(18)


## Focused Passage fixture for the bounded UI step: real keyboard entry, a real
## Passage object, and the same `_passage` driver the full route uses.
## The run-scoped Cells/blueprint values below are FIXTURE SETUP so the delivery,
## partial-invest and real-unlock branches are reachable inside the 30s gate. It
## is fixture evidence, not normal-run acceptance - the 900s route earns its own
## Cells from real kills.
func _passage_fixture() -> void:
	await _press(KEY_ENTER)
	await _frames(40)
	if not _check(Game.in_hub, "focused fixture reaches Hub by keyboard"): return
	await _flat(float(_main.hub.DOOR_X) - 25)
	await _press(KEY_R)
	await _frames(50)
	if not _check(Game.run_phase == "biome" and not Game.run_node_id.is_empty(), "focused fixture starts a real run"): return
	# Setup shortcut through the production entry point; every interaction below
	# is a real key press.
	Game.run_phase = "transition"
	_main.enter_passage(false)
	await _frames(30)
	if not _check(Game.run_phase == "passage" and is_instance_valid(_main.passage), "focused fixture enters the real Passage"): return
	# `enter_passage()` is normally reached through `select_destination()`, which also
	# records the passage metrics the services require. Restore that one field so
	# `service_ready()` stays a real gate instead of being bypassed.
	Game.passage_snapshot = {"time": 0.0, "streak": 0, "flawless": false}
	if not _check(Game.service_ready(), "fixture passage is service-ready"): return
	var ids: Array = Data.passage.blueprints.keys()
	var step := int(Data.passage.investment_step)
	var deliver_id := str(ids[0])
	var partial_id := ""
	for id in ids:
		if str(id) != deliver_id and int(Data.passage.blueprints[id].cost) > step * 2:
			partial_id = str(id)
			break
	if not _check(not partial_id.is_empty(), "fixture finds a blueprint that stays partial after one step"): return
	Game.carried_blueprints.append(deliver_id)
	Profile.delivered_blueprints.append(partial_id)
	# One step short of the cost: the first invest inside `_passage` crosses it.
	Profile.blueprint_cells[deliver_id] = maxi(0, int(Data.passage.blueprints[deliver_id].cost) - step)
	Profile.blueprint_cells[partial_id] = 0
	Game.run_cells = step * 4
	if not _check(int(Profile.blueprint_cells[deliver_id]) + step >= int(Data.passage.blueprints[deliver_id].cost), "fixture seeds one real crossing"): return
	await _passage()
	if not _check(int(Profile.blueprint_cells[deliver_id]) == int(Data.passage.blueprints[deliver_id].cost), "fixture run persists the crossing blueprint at full cost"): return
	if str(Data.passage.blueprints[deliver_id].kind) == "gear":
		if not _check(Profile.gear_available(deliver_id), "fixture run unlocks the crossed weapon in the profile"): return
	if not _check(int(Profile.blueprint_cells[partial_id]) < int(Data.passage.blueprints[partial_id].cost), "fixture run leaves the second blueprint partial"): return
	# `_passage()` already left through the Passage exit; sending Esc here would open
	# the pause menu in the live world and is not part of the service flow.
	await _frames(20)
	if not _check(not get_tree().paused and not is_instance_valid(_main.collector), "passage left without a modal owner"): return
	_log("passage_only_complete")
	_finish(true)


func _passage() -> void:
	_release()
	await _shot("boss_passage" if Game.boss_passage() else "passage")
	await _flat(float(_main.passage.COLLECTOR_X))
	await _press(KEY_R)
	if not _check(is_instance_valid(_main.collector) and get_tree().paused, "Collector modal opens"): return
	for id: String in Data.passage.blueprints:
		if Game.carried_blueprints.has(id):
			await _press(KEY_ENTER)
			if not _check(Profile.delivered_blueprints.has(id) and not Game.carried_blueprints.has(id), "carried blueprint delivered " + id): return
		if Profile.delivered_blueprints.has(id) and Game.run_cells > 0:
			var before := int(Profile.blueprint_cells.get(id, 0))
			var cost := mini(int(Data.passage.investment_step), mini(Game.run_cells, int(Data.passage.blueprints[id].cost) - before))
			var cells := Game.run_cells
			await _press(KEY_ENTER)
			if not _check(int(Profile.blueprint_cells.get(id, 0)) == before + cost and Game.run_cells == cells - cost, "Collector exact partial investment " + id): return
			if before + cost >= int(Data.passage.blueprints[id].cost):
				if not _check(_main.collector._unlocked_id == id, "persisted crossing raises the unlock card for " + id): return
				# The unlock card owns the keyboard: one Enter acknowledges it and the
				# ledger must not move again.
				var cells_after := Game.run_cells
				var invested_after := int(Profile.blueprint_cells.get(id, 0))
				await _press(KEY_ENTER)
				if not _check(_main.collector._unlocked_id.is_empty() and Game.run_cells == cells_after and int(Profile.blueprint_cells.get(id, 0)) == invested_after, "unlock card closes by Enter without a second purchase"): return
			elif not _check(_main.collector._unlocked_id.is_empty(), "partial investment leaves no unlock card " + id): return
		await _press(KEY_DOWN)
	await _shot("collector")
	await _press(KEY_ESCAPE)
	await _flat(float(_main.passage.MUTATION_X))
	await _press(KEY_R)
	await _frames(20)
	await _shot("mutation")
	# Reset is the first entry now, so step past it before confirming a choice.
	if not _check(_main.collector._ids[0] == "reset", "Mutation list opens on reset"): return
	await _press(KEY_DOWN)
	if not _check(_main.collector._ids[_main.collector._index] != "reset", "first Move lands on a real Mutation, never Reset"): return
	for i in range(mini(Game.build.mutations.size(), 2)):
		await _press(KEY_DOWN)
	var mutation_before := Game.build.mutations.size()
	await _press(KEY_ENTER)
	if not _check(Game.build.mutations.size() == mini(mutation_before + 1, Game.build.mutation_capacity), "keyboard Mutation capacity/selection"): return
	await _press(KEY_ESCAPE)
	if Game.build.slots[0].quality == "plain" and Game.build.gold >= Game.build.craft_cost(0, false):
		await _flat(float(_main.passage.CRAFT_X))
		await _press(KEY_R)
		var gold := Game.build.gold
		var cost := Game.build.craft_cost(0, false)
		await _press(KEY_ENTER)
		if not _check(Game.build.slots[0].quality == "etched" and Game.build.gold == gold - cost, "paid upgrade in physical Passage"): return
		await _shot("craft")
		await _press(KEY_ESCAPE)
	if Game.boss_passage() and Game.run_cells > 0 and Profile.forge_cells < int(Data.passage.forge.cost):
		await _flat(float(_main.passage.FORGE_X))
		await _press(KEY_R)
		var cells := Game.run_cells
		var before := Profile.forge_cells
		var cost := mini(int(Data.passage.investment_step), mini(cells, int(Data.passage.forge.cost) - before))
		await _press(KEY_ENTER)
		if not _check(Profile.forge_cells == before + cost and Game.run_cells == cells - cost, "boss Forge commits actual carried Cells"): return
		await _shot("forge")
		await _press(KEY_ESCAPE)
	await _flat(float(_main.passage.CHALLENGE_X))
	await _press(KEY_R)
	for id: String in Game.challenge_ids():
		if Game.challenge_available(id):
			var gold := Game.build.gold
			await _press(KEY_ENTER)
			if not _check(Game.passage_claims.has(id) and Game.build.gold == gold + int(Data.passage.challenges[id].gold), "earned challenge award " + id): return
		await _press(KEY_DOWN)
	await _press(KEY_ESCAPE)
	await _flat(float(_main.passage.FOUNTAIN_X))
	await _press(KEY_R)
	if not _check(is_equal_approx(Game.player.hp, Game.player.max_hp) and Game.flask_charges == Game.flask_capacity, "keyboard Fountain full supply"): return
	_log("passage_complete")
	await _flat(float(_main.passage.EXIT_X))
	await _press(KEY_R)
	await _frames(45)


func _go(target: Vector2) -> void:
	var deadline := Time.get_ticks_msec() + 35000
	while Game.player.global_position.distance_to(target) > 22:
		if not _check(Time.get_ticks_msec() < deadline, "navigation timeout target=%s at=%s" % [target, Game.player.global_position]): return
		if not _check(not Game.run_over, "alive during navigation"): return
		var enemy := _near_enemy(260)
		if enemy != null:
			await _fight(enemy)
			continue
		if not Game.player.is_on_floor():
			_drive(target.x)
			await _tick()
			continue
		var data: Dictionary = _main.level.data
		var solids: Array = data.solids.duplicate()
		var floors: Array = data.surfaces.duplicate()
		for gate in _main.level._gates.values():
			if not gate.unlocked:
				if str(gate.spec.kind) == "key" and Game.run_keys.has(str(gate.spec.key)) and absf(Game.player.global_position.x - gate.global_position.x) < 60:
					await _press(KEY_R)
					await _frames(3)
				if not gate.unlocked:
					solids.append(gate.spec.rect)
					if str(gate.spec.kind) == "break":
						floors.append({"rect":gate.spec.rect, "oneway":false, "room":gate.spec.room})
		var surfaces := SurfaceReach._components(floors, solids)
		# A pickup may straddle a seam; walk to a supported point within interaction reach.
		var best := 24.0
		var landing := target
		for surface: Dictionary in surfaces:
			var rect: Rect2 = surface.rect
			var point := Vector2(clampf(target.x, rect.position.x + 16, rect.end.x - 16), rect.position.y - 24)
			if point.distance_to(target) < best and SurfaceReach.clear_box(point, solids):
				best = point.distance_to(target)
				landing = point
		target = landing
		var start := -1
		var end := -1
		for i in surfaces.size():
			var rect: Rect2 = surfaces[i].rect
			var at := Game.player.global_position
			# A grounded capsule can overhang a ledge while its feet still touch it.
			if at.x + SurfaceReach.HALF.x > rect.position.x and at.x - SurfaceReach.HALF.x < rect.end.x and absf(at.y + 23 - rect.position.y) < 8:
				start = i
			if SurfaceReach._on_surface(target, surfaces[i]):
				end = i
		if start < 0 or end < 0:
			print("L6 NAV SURFACES ", start, " ", end, " ", surfaces)
		if not _check(start >= 0 and end >= 0, "supported route points %s -> %s" % [Game.player.global_position, target]): return
		if start == end:
			_drive(target.x)
			await _tick()
			continue
		var queue: Array = [start]
		var parents := {start:-1}
		while not queue.is_empty() and not parents.has(end):
			var current: int = queue.pop_front()
			for i in surfaces.size():
				if not parents.has(i) and SurfaceReach.can_travel(surfaces[current], surfaces[i], solids, data.oneways):
					parents[i] = current
					queue.append(i)
		if not _check(parents.has(end), "physical walking path exists to %s" % target): return
		var next := end
		while int(parents[next]) != start:
			next = int(parents[next])
		var a: Rect2 = surfaces[start].rect
		var b: Rect2 = surfaces[next].rect
		var x := clampf(b.get_center().x, a.position.x + 15, a.end.x - 15)
		var end_x := clampf(x, b.position.x + 15, b.end.x - 15)
		await _flat(x, true)
		var up := a.position.y - b.position.y
		if absf(up) < 1:
			await _flat(end_x, true)
		else:
			var drop := bool(surfaces[start].oneway) and up < 0 and SurfaceReach._arc_clear(Vector2(x, a.position.y - 24), Vector2(end_x, b.position.y - 24), solids, data.oneways, a, true)
			_hold_key(KEY_S, drop)
			_hold_key(KEY_SPACE, true)
			for n in 125:
				_drive(end_x)
				await _tick()
				if n > 8 and Game.player.is_on_floor():
					break
			_hold_key(KEY_SPACE, false)
			_hold_key(KEY_S, false)
			await _frames(2)
	_release()
	await _frames(18)


func _flat(x: float, combat := false) -> void:
	for n in 1800:
		if not _check(not Game.run_over, "alive walking"): return
		if absf(Game.player.global_position.x - x) <= 12:
			_release()
			await _frames(12)
			return
		var enemy := _near_enemy(220) if combat else null
		if enemy != null:
			await _fight(enemy)
		_drive(x)
		await _tick()
	if not _check(false, "walk timeout x=%s at=%s" % [x, Game.player.global_position]): return


func _near_enemy(distance: float) -> Enemy:
	if not is_instance_valid(_main.level):
		return null
	var nearest: Enemy
	for enemy: Enemy in _main.level._alive:
		var delta := enemy.global_position - Game.player.global_position
		if not enemy._dead and absf(delta.y) < 75 and absf(delta.x) < distance:
			nearest = enemy
			distance = absf(delta.x)
	return nearest


func _fight_room(index: int) -> void:
	for n in 12:
		var enemy: Enemy
		for item: Enemy in _main.level._alive:
			if int(item.get_meta("room", -1)) == index and not item._dead:
				enemy = item
				break
		if enemy == null:
			return
		await _fight(enemy)
	if not _check(false, "room fight not completed"): return


func _fight(enemy: Enemy) -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while is_instance_valid(enemy) and not enemy._dead:
		if not _check(not Game.run_over, "combat survival vs " + enemy.kind): return
		if not _check(Time.get_ticks_msec() < deadline, "combat deadline vs " + enemy.kind): return
		var delta := enemy.global_position - Game.player.global_position
		_drive(enemy.global_position.x - signf(delta.x) * 48)
		_hold_key(KEY_1, _frame % 20 == 0 and absf(delta.x) < 105)
		_hold_key(KEY_Q, _frame % 70 == 0)
		_hold_key(KEY_E, _frame % 60 == 0)
		_hold_key(KEY_2, _frame % 90 == 0 and absf(delta.x) < 90)
		if enemy is RouteBoss:
			var state := "windup" if enemy.state == Enemy.EState.WINDUP else ("attack" if enemy.state == Enemy.EState.ATTACK else "")
			if not state.is_empty():
				_boss_states[enemy.kind + "/" + state] = true
				await _shot(state + "_" + enemy.kind + "_" + enemy._pending_attack)
			_hold_key(KEY_SHIFT, enemy.state == Enemy.EState.ATTACK and _frame % 30 == 0)
		await _tick()
	_release()
	await _frames(16)


func _tick() -> void:
	_frame += 1
	if is_instance_valid(Game.player):
		_hold_key(KEY_F, Game.player.hp < Game.player.max_hp * 0.6 and Game.flask_charges > 0 and _frame % 24 == 0)
	await get_tree().physics_frame


func _drive(x: float) -> void:
	var delta := x - Game.player.global_position.x
	_hold_key(KEY_D, delta > 10)
	_hold_key(KEY_A, delta < -10)


func _hold_key(code: int, down: bool) -> void:
	if bool(_held.get(code, false)) == down:
		return
	_held[code] = down
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)


func _press(code: int) -> void:
	# Modal registration and input dispatch need idle frames, including while paused.
	await get_tree().process_frame
	_hold_key(code, true)
	await _frames(2)
	await get_tree().process_frame
	_hold_key(code, false)
	await _frames(2)
	await get_tree().process_frame


func _release() -> void:
	for code in _held.keys():
		_hold_key(int(code), false)


func _frames(count: int) -> void:
	for n in count:
		await _tick()


func _shot(label: String) -> void:
	var id := "%d_%s" % [_run, label]
	if not _capture or _shots.has(id):
		return
	_shots[id] = true
	await RenderingServer.frame_post_draw
	if not _check(get_viewport().get_texture().get_image().save_png("res://output/screenshots/l6/" + id + ".png") == OK, "saved screenshot " + id): return


func _log(event: String) -> void:
	var row := {"event":event, "run":_run, "node":Game.run_node_id, "visits":Game.route_history.duplicate(), "seed":_main.level.data.seed if is_instance_valid(_main.level) else 0, "hp":Game.player.hp, "kills":Game.kills, "cells":Game.run_cells, "runes":Profile.unlocked_runes.duplicate(), "elapsed_ms":Time.get_ticks_msec() - _started}
	row["keys"] = Game.run_keys.duplicate()
	row["bsc"] = Game.run_bsc
	row["flask"] = Game.flask_charges
	row["permanent"] = {"victories":Profile.victories, "bsc_unlocked":Profile.boss_cells_unlocked, "blueprints":Profile.delivered_blueprints.duplicate(), "investment":Profile.blueprint_cells.duplicate(), "forge":Profile.forge_cells}
	if Game.build != null:
		row["build"] = {"gold":Game.build.gold, "slots":Game.build.slots.duplicate(true), "attributes":Game.build.attributes.duplicate(), "mutations":Game.build.mutations.duplicate()}
	_evidence.append(row)
	print("L6 INPUT ", JSON.stringify(row))


func _finish(complete: bool) -> void:
	if _failed: return
	_release()
	_save_evidence(complete)
	print("L6 INPUT %s (%d checks, %.2fs); AUTOMATIC, NOT HUMAN" % ["OK" if complete else "DIAGNOSTIC", _checks, (Time.get_ticks_msec() - _started) / 1000.0])
	get_tree().quit()


func _save_evidence(complete: bool) -> void:
	var mode := "display" if _capture else "headless"
	var file := FileAccess.open("res://output/l6-" + mode + "-evidence.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"automatic_keyboard":true, "human_signoff":false, "complete":complete, "checks":_checks, "transactions":_transactions, "boss_states":_boss_states, "screenshots":_shots.keys(), "events":_evidence}, "\t"))
	file.close()


func _check(ok: bool, message: String) -> bool:
	if _failed: return false
	_checks += 1
	if not ok:
		_failed = true
		print("L6 INPUT STATE ", message)
		if is_instance_valid(_main.collector):
			print("SERVICE ", _main.collector.service, " index=", _main.collector._index, " ids=", _main.collector._ids, " note=", _main.collector._note, " ready=", Game.service_ready(), " carried=", Game.carried_blueprints, " error=", Profile.last_save_error)
		_log("FAIL: " + message)
		_save_evidence(false)
		_release()
		push_error("L6 INPUT FAIL: " + message)
		get_tree().quit(1)
	return ok
