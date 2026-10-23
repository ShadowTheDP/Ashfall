extends Node
## AUDITOR V3 probe: run flow + meta progression.
## Covers the hub door's floor selection, the full hub -> floor -> clear/death
## loop, cross-floor state leaks, and the camera limits / walk bounds at the
## new 1600 px hub and 4200+ px floor scale.
##
## Run: godot --headless --path . tests/audit_v3.tscn

var _main: Node
var _fails := 0
var _checks := 0
var _died_count := 0

## Headless still has to execute _draw(), or a probe can never see a draw-path
## error. This proves the draw pass runs before the other checks rely on it.
class DrawCounter extends Node2D:
	var drawn := 0

	func _draw() -> void:
		drawn += 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = $Main
	Profile.reset_profile()
	await get_tree().process_frame
	await _wait(0.4)

	var counter := DrawCounter.new()
	_main.add_child(counter)
	counter.queue_redraw()
	await _wait(0.2)
	print("--- draw pass: %d ---" % counter.drawn)
	_check(counter.drawn > 0, "headless never runs _draw(), so draw bugs are invisible")
	counter.queue_free()

	await _test_selection()
	await _test_door_input()
	await _test_camera_and_bounds()
	await _test_loop()
	await _test_victory()
	await _test_leaks()
	await _test_character_gate()
	await _test_dead_player()

	Profile.reset_profile()
	print("AUDIT V3 %s (%d checks, %d failures)" % [
		"OK" if _fails == 0 else "FAILED", _checks, _fails])
	await _wait(0.2)
	get_tree().quit(0 if _fails == 0 else 1)


# ---------------------------------------------------------------- 1. selection

func _test_selection() -> void:
	print("--- floor selection ---")
	for best in [0, 1, 3, 5, 99]:
		Profile.best_floor = best
		await _enter_hub()
		var hub: Node = _main.hub
		if hub == null:
			_check(false, "hub missing for best_floor %d" % best)
			continue
		var top: int = Data.floors.size()
		var want := clampi(best + 1, 1, top)
		print("  best=%d -> target=%d available=%d top=%d" % [
			best, int(hub.floor_target), int(hub.floor_available), top])
		_check(int(hub.floor_available) == maxi(0, best), "available != best_floor (%d)" % best)
		_check(int(hub.floor_target) == want, "target %d != %d for best %d" % [
			int(hub.floor_target), want, best])
		_check(int(hub.floor_target) <= top, "target past the last floor")
		# Down past the bottom, then up past the top: both clamp.
		for i in 12:
			hub._step_floor(-1)
		_check(int(hub.floor_target) == 1, "left did not clamp at floor 1 (best %d, got %d)" % [
			best, int(hub.floor_target)])
		for i in 12:
			hub._step_floor(1)
		_check(int(hub.floor_target) == want, "right did not clamp at %d (best %d, got %d)" % [
			want, best, int(hub.floor_target)])
		# Every reachable target must be unlocked (<= best + 1).
		for i in 12:
			hub._step_floor(-1)
			_check(int(hub.floor_target) <= best + 1, "stepped onto a locked floor")


## The door is driven by real key events, not by calling _step_floor: the input
## path is where a picker can leak into walking or vice versa.
func _test_door_input() -> void:
	print("--- door input ---")
	Profile.best_floor = 3
	await _enter_hub()
	var hub: Node = _main.hub
	var player: Player = hub.get("player") as Player
	player.global_position = Vector2(float(hub.DOOR_X) - 30.0, -30.0)
	await _wait(0.15)
	_check(int(hub.floor_target) == 4, "door did not open on best+1")
	await _press(KEY_LEFT)
	await _press(KEY_LEFT)
	_check(int(hub.floor_target) == 2, "two LEFT presses -> %d, expected 2" % int(hub.floor_target))
	await _press(KEY_RIGHT)
	await _press(KEY_RIGHT)
	await _press(KEY_RIGHT)
	_check(int(hub.floor_target) == 4, "RIGHT past the top -> %d, expected 4" % int(hub.floor_target))
	# Away from the door the same keys must only walk.
	player.global_position = Vector2(500.0, -30.0)
	await _wait(0.15)
	await _press(KEY_LEFT)
	_check(int(hub.floor_target) == 4, "LEFT away from the door moved the picker")


# ------------------------------------------------------- 4. camera and bounds

func _test_camera_and_bounds() -> void:
	print("--- camera limits / bounds ---")
	Profile.best_floor = 1
	await _enter_hub()
	var hub: Node = _main.hub
	var player: Player = hub.get("player") as Player
	var cam: Camera2D = player.camera
	print("  hub limits L%d R%d T%d B%d" % [
		cam.limit_left, cam.limit_right, cam.limit_top, cam.limit_bottom])
	_check(cam.limit_left == -20 and cam.limit_right == 1620,
		"hub camera x limits wrong (%d..%d)" % [cam.limit_left, cam.limit_right])
	_check(cam.limit_top == -420 and cam.limit_bottom == 200,
		"hub camera y limits wrong (%d..%d)" % [cam.limit_top, cam.limit_bottom])

	# Walk bounds inside the hub: neither wall may be passable.
	player.global_position = Vector2(1580.0, -30.0)
	Input.action_press("move_right")
	await _wait(1.0)
	Input.action_release("move_right")
	var right_x := player.global_position.x
	player.global_position = Vector2(40.0, -30.0)
	Input.action_press("move_left")
	await _wait(1.0)
	Input.action_release("move_left")
	var left_x := player.global_position.x
	print("  hub walk bounds x %.1f .. %.1f" % [left_x, right_x])
	_check(right_x <= 1620.0, "walked through the hub's right wall (%.1f)" % right_x)
	_check(left_x >= -20.0, "walked through the hub's left wall (%.1f)" % left_x)

	# The floor must reset the widened hub limits, not inherit them.
	_main.start_floor(1)
	await _wait(0.8)
	player = Game.player
	cam = player.camera
	var width := float(_main.level.data.get("width", 0.0))
	print("  floor limits L%d R%d T%d B%d (width %.0f)" % [
		cam.limit_left, cam.limit_right, cam.limit_top, cam.limit_bottom, width])
	_check(width > 1600.0, "floor 1 is not wider than the hub")
	_check(cam.limit_left == -120 and cam.limit_right == int(width) + 120,
		"floor did not reset the camera x limits (%d..%d)" % [cam.limit_left, cam.limit_right])
	_check(cam.limit_top == -600 and cam.limit_bottom == 400,
		"floor did not reset the camera y limits (%d..%d)" % [cam.limit_top, cam.limit_bottom])
	_check(cam.limit_right > 1620, "floor camera narrower than the hub's")

	# Walk bounds on the floor: the right wall is the level width.
	player.global_position = Vector2(width - 60.0, 40.0)
	await _wait(0.2)
	Input.action_press("move_right")
	await _wait(1.2)
	Input.action_release("move_right")
	var edge := player.global_position.x
	print("  floor right bound x %.1f (width %.0f)" % [edge, width])
	_check(edge <= width + 1.0, "walked off the level (%.1f > %.0f)" % [edge, width])


# ------------------------------------------------------------------ 2. loop

func _test_loop() -> void:
	print("--- whole loop ---")
	Profile.reset_profile()
	Profile.best_floor = 0
	await _enter_hub()
	var hub: Node = _main.hub
	_check(int(hub.floor_target) == 1, "fresh profile door is not floor 1")
	var old_hub: Node = hub

	# hub -> floor 1 via the real door key
	var player: Player = hub.get("player") as Player
	player.global_position = Vector2(float(hub.DOOR_X) - 30.0, -30.0)
	await _wait(0.15)
	await _press(KEY_J)
	await _wait(0.8)
	_check(not Game.in_hub and Game.floor_index == 1, "J at the door did not descend")
	var level: Node = _main.level
	if level == null:
		_check(false, "no level after descend")
		return
	# Unbanked cells earned on the floor.
	Game.add_cells(7)
	_check(Game.run_cells == 7, "run_cells did not track a pickup")
	var banked_before := Profile.cells

	await _clear(level)
	await _wait(0.2)
	_check(Game.run_cells == 0, "run_cells not zeroed after banking")
	_check(Profile.cells == banked_before + 7, "clear banked %d, expected %d" % [
		Profile.cells - banked_before, 7])
	_check(Profile.best_floor == 1, "best_floor not advanced to 1")
	var banked_after_clear := Profile.cells

	await _wait(2.0)   # clear transition -> hub
	await _wait(0.4)
	hub = _main.hub
	if hub == null:
		_check(false, "no hub after clearing floor 1")
		return
	_check(_main.level == null, "level node survived the return to the hub")
	_check(not is_instance_valid(old_hub), "the hub node survived the descent")
	_check(int(hub.floor_target) == 2, "second run would replay floor %d, not 2" % int(hub.floor_target))
	_check(Game.fx_root == hub, "fx_root still points at the freed floor")
	_check(Game.player == hub.get("player"), "Game.player is not the hub player")

	# The old floor must be gone: no enemy, no projectile left in the world.
	var leftovers := _count_nodes([Enemy, Projectile])
	_check(leftovers == 0, "%d enemy/projectile nodes survived the floor" % leftovers)
	var names: Array = []
	for node in _main.world.get_children():
		names.append("%s:%s" % [node.name, node.get_class()])
	print("  world after clear: %s" % str(names))
	var hp_before := (hub.get("player") as Player).hp
	await _wait(1.0)
	_check(is_equal_approx((hub.get("player") as Player).hp, hp_before),
		"hub player took damage from a previous floor")

	# hub -> floor 2 via the door key again: this is the "second run replays
	# floor 1" regression, so the whole path has to be the key, not an API call.
	await _descend_via_door(hub, 2)
	_check(Game.floor_index == 2, "second run went to floor %d, not 2" % Game.floor_index)
	Game.add_cells(5)
	_died_count = 0
	(_main.level as Node).player_died.connect(func() -> void: _died_count += 1)
	var p := Game.player
	p.invuln = 0.0
	p.take_hit({"damage": 9999.0, "source_pos": p.global_position + Vector2(-30, 0)})
	await _wait(0.3)
	_check(_died_count == 1, "player_died fired %d times" % _died_count)
	_check(p.hp == 0.0, "player survived 9999 damage")
	await _wait(2.4)   # death transition -> hub
	await _wait(0.4)
	hub = _main.hub
	if hub == null:
		_check(false, "no hub after dying on floor 2")
		return
	print("  after death: cells %d (was %d) best_floor %d target %d" % [
		Profile.cells, banked_after_clear, Profile.best_floor, int(hub.floor_target)])
	_check(Profile.cells == banked_after_clear, "death banked or spent unbanked cells (%d -> %d)" % [
		banked_after_clear, Profile.cells])
	_check(Game.run_cells == 0, "run_cells survived the death")
	_check(Profile.best_floor >= 2, "best_floor went backwards")
	_check(int(hub.floor_target) == 3, "door after dying on floor 2 is %d, expected 3" % int(hub.floor_target))
	_check(Game.run_over == false, "run_over leaked into the hub")

	# A third clear must bank exactly its own cells, not the earlier ones.
	var banked_before_3 := Profile.cells
	await _descend_via_door(hub, 3)
	_check(Game.floor_index == 3, "third run went to floor %d, not 3" % Game.floor_index)
	Game.add_cells(4)
	await _clear(_main.level)
	await _wait(2.0)
	await _wait(0.4)
	_check(Profile.cells == banked_before_3 + 4, "double-banking: clear 3 banked %d, expected 4" % [
		Profile.cells - banked_before_3])
	hub = _main.hub
	if hub != null:
		_check(int(hub.floor_target) == 4, "door after clearing floor 3 is %d, expected 4" % int(hub.floor_target))
		# A hub must always keep its door and its stations.
		_check(not (hub.get("STATIONS") as Array).is_empty(), "hub lost its stations")
		# And every one of them must sit inside the walkable span, or a player
		# could end up in a hub whose door and stations are unreachable.
		var reach := float(hub.WIDTH) + 20.0 - 13.0
		_check(float(hub.DOOR_X) <= reach and float(hub.DOOR_X) >= 13.0,
			"the door sits outside the walkable hub (x %.0f)" % float(hub.DOOR_X))
		for station in hub.get("STATIONS") as Array:
			var sx := float(station.get("x", -999.0))
			_check(sx >= 13.0 and sx <= reach, "station %s is outside the walkable hub" % station.get("id"))


# ------------------------------------------------------------ 2b. victory leg

## The last floor is the win: it must bank the run once, add one soul, advance
## nothing, and drop the player back into a hub whose door still works.
func _test_victory() -> void:
	print("--- victory ---")
	Profile.reset_profile()
	Profile.best_floor = 4
	await _enter_hub()
	var hub: Node = _main.hub
	_check(int(hub.floor_target) == 5, "door with best_floor 4 offers floor %d" % int(hub.floor_target))
	await _descend_via_door(hub, 5)
	var level: Node = _main.level
	if level == null:
		_check(false, "no level 5")
		return
	Game.add_cells(9)
	var souls_before := Profile.souls
	var banked_before := Profile.cells
	await _clear(level)
	await _wait(0.3)
	_check(Game.victory, "clearing floor 5 is not a victory")
	_check(Game.run_over, "the run did not end on the win")
	_check(Profile.souls == souls_before + 1, "win did not award exactly one soul")
	_check(Profile.cells == banked_before + 9, "win banked %d cells, expected 9" % [
		Profile.cells - banked_before])
	_check(Profile.victories >= 1, "victory not recorded")
	_check(Profile.best_floor == 5, "best_floor is %d after winning" % Profile.best_floor)
	await _wait(3.2)
	await _wait(0.4)
	hub = _main.hub
	if hub == null:
		_check(false, "no hub after the victory")
		return
	_check(not Game.run_over, "run_over leaked into the post-victory hub")
	_check(Profile.cells == banked_before + 9, "the victory banked twice (%d)" % Profile.cells)
	_check(int(hub.floor_target) == 5, "post-victory door offers %d" % int(hub.floor_target))
	# Still able to descend again: the game must not lock itself after a win.
	await _descend_via_door(hub, 5)


# ------------------------------------------------- 3. cross-floor leaks

func _test_leaks() -> void:
	print("--- cross-floor leaks ---")
	_main.start_floor(1)
	await _wait(0.8)
	var p := Game.player
	# An enemy bolt in flight when the floor is left. It lives in Game.fx_root
	# (the world), not in the level, so freeing the level does not free it.
	var bolt := Projectile.new()
	bolt.position = p.global_position + Vector2(30.0, -10.0)
	bolt.setup_ballistic(Vector2(-40.0, 0.0), 9.0, MathArt.PALE, null)
	# A bolt still in flight when the floor ends: 2.6 s of life against a 2.2 s
	# death transition leaves ~0.4 s to run after the hub is built.
	bolt._life = 2.6
	Game.fx_root.add_child(bolt)
	var fx_before := _count_nodes([Projectile])
	_check(fx_before == 1, "the probe could not place a bolt (%d)" % fx_before)

	p.invuln = 0.0
	p.take_hit({"damage": 9999.0, "source_pos": p.global_position + Vector2(-30, 0)})
	# Sample the instant the hub exists: waiting for the bolt to expire would
	# hide the leak instead of proving it is gone.
	for i in 400:
		if _main.hub != null:
			break
		await get_tree().process_frame
	var hub: Node = _main.hub
	if hub == null:
		_check(false, "no hub after the leak run")
		return
	var stray := _count_nodes([Projectile, FunctionWave])
	_check(stray == 0, "%d floor projectile(s) are still live in the new hub" % stray)
	var hub_player: Player = hub.get("player") as Player
	_check(is_equal_approx(hub_player.hp, hub_player.max_hp),
		"a floor projectile damaged the hub player (hp %.0f)" % hub_player.hp)

	# The archive and skill tree screens must not accumulate per hub visit.
	# (Known open bug: main.gd::_build_meta_screens() adds a new pair on every
	# enter_hub() and never frees the old ones. Reported, not fixed: main.gd is
	# outside this audit's write scope.)
	var screens_before := _count_screens()
	for i in 2:
		await _enter_hub()
	print("  meta screens per hub visit: %d -> %d" % [screens_before, _count_screens()])


# --------------------------------------------- 5. character floor gate

## data/characters.json carries `unlock_floor`, and HubUi already had an unused
## `lock` row key + `_draw_lock()`: the gate was designed and never wired, so a
## player on floor 1 could buy the floor-5 body with saved cells.
func _test_character_gate() -> void:
	print("--- character floor gate ---")
	Profile.reset_profile()
	Profile.bank(5000)
	Profile.best_floor = 1
	await _enter_hub()
	var hub: Node = _main.hub
	_main._on_station_opened("character")
	await _wait(0.2)
	var ui: HubUi = hub.get("ui") as HubUi
	var rows: Array = ui._rows()
	var index := -1
	for i in rows.size():
		if str(rows[i].get("id", "")) == "gyro":
			index = i
	_check(index >= 0, "the character list has no gyro row")
	if index >= 0:
		_check(bool(rows[index].get("lock", false)), "the floor-5 body is not locked on floor 1")
		ui._index = index
		ui._confirm()
		await _wait(0.2)
		_check(not Profile.is_unlocked("character", "gyro"),
			"bought the floor-5 body while best_floor is 1")
		_check(Profile.selected_character != "gyro", "equipped a floor-locked body")
	await _press(KEY_ESCAPE)
	await _wait(0.2)

	Profile.best_floor = 5
	await _enter_hub()
	hub = _main.hub
	_main._on_station_opened("character")
	await _wait(0.2)
	ui = hub.get("ui") as HubUi
	rows = ui._rows()
	for i in rows.size():
		if str(rows[i].get("id", "")) == "gyro":
			index = i
	_check(index >= 0 and not bool(rows[index].get("lock", true)),
		"the floor-5 body stays locked at best_floor 5")
	ui._index = index
	ui._confirm()
	await _wait(0.2)
	_check(Profile.is_unlocked("character", "gyro"), "floor-5 body cannot be bought at best_floor 5")
	await _press(KEY_ESCAPE)
	await _wait(0.2)


# ------------------------------------------------------- 3. dead player guard

func _test_dead_player() -> void:
	print("--- dead player ---")
	_main.start_floor(1)
	await _wait(0.8)
	var p := Game.player
	p.invuln = 0.0
	p.take_hit({"damage": 9999.0, "source_pos": p.global_position + Vector2(-30, 0)})
	await _wait(0.2)
	_check(p.state == Player.State.DEAD, "player is not DEAD at 0 hp")
	var hp := p.hp
	for i in 3:
		p.invuln = 0.0
		p.take_hit({"damage": 50.0, "source_pos": p.global_position + Vector2(-30, 0)})
	await _wait(0.1)
	_check(p.hp == hp and p.hp == 0.0, "a dead player kept taking hits (hp %.1f)" % p.hp)
	await _wait(2.6)
	await _wait(0.4)
	_check(_main.hub != null, "no hub after the death loop")


# -------------------------------------------------------------------- helpers

func _descend_via_door(hub: Node, expected: int) -> void:
	var player: Player = hub.get("player") as Player
	player.global_position = Vector2(float(hub.DOOR_X) - 30.0, -30.0)
	await _wait(0.2)
	await _press(KEY_J)
	await _wait(0.8)
	_check(not Game.in_hub, "the door did not descend")
	if Game.in_hub:
		return
	_check(Game.floor_index == expected, "the door sent the player to floor %d, not %d" % [
		Game.floor_index, expected])


func _enter_hub() -> void:
	_main.enter_hub()
	await _wait(0.35)


func _clear(level: Node) -> void:
	var rooms: Array = level.data.get("rooms", [])
	for i in rooms.size():
		var rect: Rect2 = rooms[i]["rect"]
		# Teleporting into a pillar lets move_and_slide shove the player out of
		# the room's x-range before it is entered, and the room's spawns stay
		# pending. Retry across the room width until progress() ticks.
		var entered := int(level.progress().x)
		for attempt in 3:
			if Game.player != null:
				Game.player.global_position = Vector2(
					rect.get_center().x - 60.0 + float(attempt) * 60.0, rect.position.y - 40.0)
			await get_tree().physics_frame
			await get_tree().physics_frame
			if int(level.progress().x) > entered:
				break
		await get_tree().process_frame
		await _kill_all(level)
	await get_tree().process_frame
	_check(int(level.enemies_remaining()) == 0, "floor still has %d enemies (rooms %s)" % [
		int(level.enemies_remaining()), str(level.progress())])
	var exit: Vector2 = level.data.get("exit", Vector2.ZERO)
	if Game.player != null:
		Game.player.global_position = exit + Vector2(0.0, -30.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func _kill_all(level: Node) -> void:
	for i in 40:
		var found := false
		for child in level.get_children():
			if child is Enemy and not (child as Enemy)._dead:
				found = true
				(child as Enemy).take_hit({
					"damage": 1.0e6, "crit": true, "knockback": 0.0, "hitstop": 0.0,
					"source_pos": (child as Enemy).global_position + Vector2(-40.0, 0.0),
					"point": (child as Enemy).global_position,
				})
		await get_tree().process_frame
		if not found:
			return


func _count_screens() -> int:
	# Duplicates are auto-renamed by Godot (@ArchiveScreen@39), so the node's
	# class is the only reliable identity here.
	var total := 0
	for node in _main.get_children():
		if node is ArchiveScreen or node is SkillTree:
			total += 1
	return total


func _count_nodes(kinds: Array) -> int:
	var total := 0
	for node in _main.world.get_children():
		for kind in kinds:
			if is_instance_of(node, kind):
				total += 1
	return total


func _press(key: int) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = key
	down.keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.physical_keycode = key
	up.keycode = key
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("AUDIT V3 FAIL: ", what)
