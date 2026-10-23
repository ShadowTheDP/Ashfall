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

	# hub -> floor 2 -> die: unbanked cells are lost, banked cells stay.
	_main.start_floor(int(hub.floor_target))
	await _wait(0.8)
	_check(Game.floor_index == 2, "door target did not become the live floor")
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
	_main.start_floor(int(hub.floor_target))
	await _wait(0.8)
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

func _enter_hub() -> void:
	_main.enter_hub()
	await _wait(0.35)


func _clear(level: Node) -> void:
	var rooms: Array = level.data.get("rooms", [])
	for i in rooms.size():
		var rect: Rect2 = rooms[i]["rect"]
		if Game.player != null:
			Game.player.global_position = Vector2(rect.position.x + 40.0, rect.position.y - 40.0)
		await get_tree().process_frame
		await get_tree().physics_frame
		await _kill_all(level)
	await get_tree().process_frame
	_check(int(level.enemies_remaining()) == 0, "floor still has %d enemies" % int(level.enemies_remaining()))
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
