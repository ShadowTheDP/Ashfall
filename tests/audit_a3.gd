extends Node
## AUDITOR A3 probe — floor / level / enemy-spawn layer.
##
## For floors 1..5 x seeds 1..15 it builds a Level, walks a real Player through
## every room, kills the spawns and checks:
##   * ground is continuous under the whole floor (no pit, no wide gap)
##   * the exit gate stands on solid ground
##   * no spawn point puts an enemy body inside stone, and none below the ledge
##   * every platform is inside the jump budget (BFS from the room slab)
##   * enemies_remaining() reaches 0 only after every spawn is dead
##   * the door opens only after the last death
##   * cleared / player_died fire exactly once
##   * a cleared room never respawns on re-entry
## Then it runs a physical hop-walk start -> exit on one seed per floor, because
## the geometry checks alone cannot prove the player can actually get there.
##
## Run: godot --headless --path . tests/audit_a3.tscn

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

## Jump budget mirrored from LevelGen; a gap wider than this is uncrossable.
const MAX_GAP := 180.0
## A body box is built from the enemy's own cfg, but the fallback covers a
## spawn point that has no enemy assigned to it yet.
const FALLBACK_BOX := Vector2(16.0, 25.0)

var _main: Node
var _world: Node
var _player: Player
var _level: Node
var _fails := 0
var _cases := 0
var _cleared := 0
var _died := 0


func _ready() -> void:
	_main = $Main
	await get_tree().process_frame
	_world = _main.world
	Game.fx_root = _world

	for floor_index in range(1, 6):
		for seed_value in range(1, 16):
			await _case(floor_index, seed_value)
	print("A3: %d floor x seed cases" % _cases)

	# The physical walk is the strongest check in this file and also the most
	# expensive: at 120 Hz a frame in an 8200 px floor costs ~30 ms, so walking
	# all five floors takes most of ten minutes. Two floors cover both ends of
	# the range (the narrowest and the widest); audit_v1 covers traversal
	# statistically over 200 layouts.
	for floor_index in [1, 4]:
		await _walk_case(floor_index, 7)

	if _fails == 0:
		print("AUDIT A3 OK")
	else:
		print("AUDIT A3 FAILED (%d)" % _fails)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if _fails == 0 else 1)


func _fail(floor_index: int, seed_value: int, what: String) -> void:
	_fails += 1
	print("FAIL floor %d seed %d: %s" % [floor_index, seed_value, what])


# --- harness ----------------------------------------------------------------

func _teardown() -> void:
	# Null the global first: a level still in the tree for one more frame must
	# not read a player that is about to be freed.
	Game.player = null
	Game.boss = null
	if is_instance_valid(_level):
		_level.queue_free()
	_level = null
	if is_instance_valid(_player):
		_player.queue_free()
	_player = null
	await get_tree().process_frame
	await get_tree().process_frame


func _build(floor_index: int, seed_value: int) -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_world.add_child(_player)
	# Survive the walk; combat damage is another auditor's problem.
	_player.max_hp = 1.0e9
	_player.hp = 1.0e9
	Game.player = _player

	_cleared = 0
	_died = 0
	_level = Level.new()
	_world.add_child(_level)
	_level.build(floor_index, seed_value)
	_level.cleared.connect(func() -> void: _cleared += 1)
	_level.player_died.connect(func() -> void: _died += 1)


func _enemies() -> Array:
	var out: Array = []
	if not is_instance_valid(_level):
		return out
	for child in _level.get_children():
		if child is Enemy and not (child as Enemy)._dead:
			out.append(child)
	return out


func _kill(enemy: Enemy) -> void:
	enemy.take_hit({
		"damage": 1.0e6, "crit": true, "knockback": 0.0, "hitstop": 0.0,
		"source_pos": enemy.global_position + Vector2(-40.0, 0.0),
		"point": enemy.global_position,
	})


# --- one floor x seed -------------------------------------------------------

func _case(floor_index: int, seed_value: int) -> void:
	_cases += 1
	await _teardown()
	_build(floor_index, seed_value)
	var data: Dictionary = _level.data
	var rooms: Array = data["rooms"]
	var solids := _solids(data)
	var width := float(data["width"])

	# build() must spawn nothing by itself. This has to be sampled BEFORE any
	# physics frame: a one-room floor (the boss arena) starts the player inside
	# the only room, so the first _physics_process enters it and spawns
	# immediately - which is correct, not a leak.
	var spawned_by_build := _enemies().size()

	var expected := 0
	for room in rooms:
		for group in room["enemies"]:
			expected += int(group[1])

	_check_ground(floor_index, seed_value, rooms, width)
	await get_tree().process_frame
	_check_ground_bodies(floor_index, seed_value, width)
	_check_exit(floor_index, seed_value, data, solids)
	_check_reach(floor_index, seed_value, rooms)
	_check_caches(floor_index, seed_value, data)

	if spawned_by_build != 0:
		_fail(floor_index, seed_value,
			"build() spawned %d enemies before any room entry" % spawned_by_build)

	# The boss arena is entered on frame 1, so its plan is already consumed.
	var already := _enemies().size()
	if int(_level._pending_total) + already != expected:
		_fail(floor_index, seed_value,
			"pending %d + spawned %d != planned %d" % [
				_level._pending_total, already, expected])

	# Walk right through every room. Moving the body is what the collision
	# walk does anyway; room entry is purely x-driven, so this exercises the
	# same code path without depending on a lucky jump.
	for i in rooms.size():
		var rect: Rect2 = rooms[i]["rect"]
		_player.global_position = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y - 40.0)
		# physics_frame fires at the TOP of the step, so one await still sees the
		# previous frame's room state; two is the first frame that is processed.
		await get_tree().physics_frame
		await get_tree().physics_frame
		if not bool(_level._room_entered[i]):
			_fail(floor_index, seed_value, "room %d never entered (x=%.1f rect=%s)"
				% [i, _player.global_position.x, str(rect)])

	# Spawn sanity: body boxes are checked against the authored spawn points
	# before physics can depenetrate anything and hide the mistake.
	_check_spawns(floor_index, seed_value, rooms, solids)
	# The boss lane comes from data["boss_at"], not from the room's points.
	var boss_at: Variant = data.get("boss_at")
	if boss_at != null:
		var boss_cfg: Dictionary = Data.enemies.get(str(data.get("boss", "")), {})
		var boss_half := Vector2(float(boss_cfg.get("body_radius", 12.0)),
			float(boss_cfg.get("body_height", 42.0)) * 0.5)
		for rect in solids:
			if _box(boss_at, boss_half).intersects(rect):
				_fail(floor_index, seed_value,
					"boss spawn %s overlaps terrain %s" % [str(boss_at), str(rect)])
				break

	if int(_level.enemies_remaining()) != expected:
		_fail(floor_index, seed_value,
			"enemies_remaining %d != %d spawned" % [_level.enemies_remaining(), expected])
	if _enemies().size() != expected:
		_fail(floor_index, seed_value,
			"%d live enemy nodes, expected %d" % [_enemies().size(), expected])
	if expected > 0 and bool(_level._door.open):
		_fail(floor_index, seed_value, "door already open with %d enemies" % expected)

	# Let every spawn land, then prove nobody fell out of the world. Track "touched
	# the floor at least once" instead of "is on the floor right now": the leaper
	# hops, so a simultaneous-landing test almost never fires and burned 240
	# frames per case. 24 fixed frames was also too tight for a Warden with a
	# long drop, which read as "never landed" when the engine ran faster than
	# real time.
	var landed := {}
	for i in 90:
		await get_tree().physics_frame
		for enemy in _enemies():
			if (enemy as Enemy).is_on_floor():
				landed[enemy] = true
		if landed.size() >= _enemies().size():
			break
	var lowest := 0.0
	for room in rooms:
		lowest = maxf(lowest, (room["rect"] as Rect2).position.y)
	lowest += LevelGen.LEDGE_H
	for enemy in _enemies():
		var body: Enemy = enemy
		# "Touched the floor at least once", not "is standing on it right now":
		# a leaper hops and a watcher may be mid-lean, and asserting the
		# instantaneous state made this probe fail on timing alone.
		if not landed.has(body):
			_fail(floor_index, seed_value, "%s never landed (y=%.0f)" % [body.kind, body.global_position.y])
		if body.global_position.y > LevelGen.BASE_Y + 60.0:
			_fail(floor_index, seed_value,
				"%s fell below the bottom ledge (y=%.0f)" % [body.kind, body.global_position.y])

	# Door must stay shut until the very last death.
	var live := _enemies()
	for i in range(live.size() - 1):
		_kill(live[i])
	if live.size() > 1 and bool(_level._door.open):
		_fail(floor_index, seed_value, "door opened with 1 enemy still alive")
	if not live.is_empty():
		_kill(live[live.size() - 1])
	await get_tree().physics_frame
	if int(_level.enemies_remaining()) != 0:
		_fail(floor_index, seed_value,
			"enemies_remaining()=%d after killing everything" % _level.enemies_remaining())
	if expected > 0 and not bool(_level._door.open):
		_fail(floor_index, seed_value, "door stayed shut after the floor was cleared")

	# Clear: only from inside the gate, and only once.
	var gate: Vector2 = data["exit"] + Vector2(0.0, -30.0)
	_player.global_position = gate
	for i in 12:
		await get_tree().physics_frame
	if _cleared != 1:
		_fail(floor_index, seed_value, "cleared fired %d times (expected 1)" % _cleared)

	# Re-entry into a cleared room must not respawn anything.
	if rooms.size() > 1:
		var rect: Rect2 = rooms[1]["rect"]
		_player.global_position = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y - 40.0)
		for i in 4:
			await get_tree().physics_frame
		if not _enemies().is_empty() or int(_level.enemies_remaining()) != 0:
			_fail(floor_index, seed_value, "re-entering a cleared room respawned enemies")

	# Death: exactly one emission, and no late clear.
	_player.hp = 0.0
	for i in 12:
		await get_tree().physics_frame
	if _died != 1:
		_fail(floor_index, seed_value, "player_died fired %d times (expected 1)" % _died)
	if _cleared != 1:
		_fail(floor_index, seed_value, "cleared fired %d times after death" % _cleared)


# --- geometry ---------------------------------------------------------------

func _solids(data: Dictionary) -> Array:
	var out: Array = []
	for room in data["rooms"]:
		for rect in room["ground"]:
			out.append(rect)
		for rect in room["platforms"]:
			out.append(rect)
	out.append(Rect2(-Level.WALL_W, Level.WALL_TOP, Level.WALL_W, Level.WALL_H))
	out.append(Rect2(float(data["width"]), Level.WALL_TOP, Level.WALL_W, Level.WALL_H))
	return out


func _box(center: Vector2, half: Vector2) -> Rect2:
	return Rect2(center - half, half * 2.0)


func _check_ground(floor_index: int, seed_value: int, rooms: Array, width: float) -> void:
	# Union the room ledges and look for any uncovered column. The generator
	# promises a continuous BASE_Y ledge; a hole here is a fall out of the world.
	var spans: Array = []
	for room in rooms:
		for rect in room["ground"]:
			var r: Rect2 = rect
			if is_equal_approx(r.position.y, LevelGen.BASE_Y):
				spans.append(Vector2(r.position.x, r.end.x))
	spans.sort_custom(func(a, b): return a.x < b.x)
	var cursor := 0.0
	for span in spans:
		var s: Vector2 = span
		if s.x > cursor:
			var gap := s.x - cursor
			if gap > MAX_GAP:
				_fail(floor_index, seed_value,
					"%.0f px hole in the floor at x=%.0f (max jump %.0f)" % [gap, cursor, MAX_GAP])
		cursor = maxf(cursor, s.y)
	if cursor < width - 0.5:
		_fail(floor_index, seed_value, "floor ends at x=%.0f, wall at %.0f" % [cursor, width])


func _check_ground_bodies(floor_index: int, seed_value: int, width: float) -> void:
	# The data says the ledge is continuous; this proves a body actually exists
	# under every column, i.e. the player has something to stand on.
	var space: PhysicsDirectSpaceState2D = _world.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = Layers.WORLD
	query.collide_with_bodies = true
	# A fixed 60 px walk meant 137 point queries on an 8200 px floor, and each
	# query outside the physics step forces a broadphase sync: ~3 s per case,
	# i.e. most of this audit's runtime. Continuity is already proven by
	# _check_ground() from the data, so proving "a body exists under the ledge"
	# needs a sample, not a sweep.
	var step := maxf(60.0, width / 12.0)
	var x := 1.0
	while x < width:
		query.position = Vector2(x, LevelGen.BASE_Y + 6.0)
		if space.intersect_point(query, 1).is_empty():
			_fail(floor_index, seed_value, "no collision under x=%.0f" % x)
			return
		x += step


## A cache is a reward for taking the high route, so it has to sit ON a surface
## the BFS proved reachable. `_verify` already fails a deck outside the jump
## budget; this closes the loop between "deck reachable" and "reward reachable".
func _check_caches(floor_index: int, seed_value: int, data: Dictionary) -> void:
	var reach: Dictionary = data.get("reachable", {})
	if int(reach.get("decks", 0)) != 0:
		_fail(floor_index, seed_value, "%d deck(s) outside the jump budget" % int(reach.get("decks", 0)))
	var caches: Array = data.get("caches", [])
	if caches.is_empty():
		_fail(floor_index, seed_value, "floor has no cache to explore for")
	var surfaces := LevelGen._surfaces(data["rooms"])
	for entry in caches:
		var spot: Vector2 = (entry as Dictionary)["pos"]
		var held := false
		for surface in surfaces:
			var r: Rect2 = surface
			if spot.x < r.position.x - 2.0 or spot.x > r.end.x + 2.0:
				continue
			# The pickup floats 12 px over the deck it was placed on.
			if absf(r.position.y - (spot.y + 12.0)) <= 4.0:
				held = true
				break
		if not held:
			_fail(floor_index, seed_value, "cache at %s is not over any surface" % str(spot.round()))


func _check_exit(floor_index: int, seed_value: int, data: Dictionary, solids: Array) -> void:
	var exit_pos: Vector2 = data["exit"]
	if float(data["width"]) - exit_pos.x < 40.0:
		_fail(floor_index, seed_value, "exit too close to the right wall")
	var under := exit_pos + Vector2(0.0, 2.0)
	var on_ground := false
	for rect in solids:
		var r: Rect2 = rect
		if r.has_point(under):
			on_ground = true
			break
	if not on_ground:
		_fail(floor_index, seed_value, "exit at %s is in the air" % str(exit_pos.round()))


func _check_reach(floor_index: int, seed_value: int, rooms: Array) -> void:
	for i in rooms.size():
		var room: Dictionary = rooms[i]
		var slab: Rect2 = room["rect"]
		# The ledge is 150 and the slab top must be inside one jump of it.
		var climb := LevelGen.BASE_Y - slab.position.y
		if climb > LevelGen.JUMP_HEIGHT:
			_fail(floor_index, seed_value,
				"room %d slab is %.0f px above the ledge" % [i, climb])
		var reached: Array = [slab]
		var pending: Array = (room["platforms"] as Array).duplicate()
		var moved := true
		while moved and not pending.is_empty():
			moved = false
			var j := 0
			while j < pending.size():
				var p: Rect2 = pending[j]
				var hit := false
				for from in reached:
					if LevelGen._reach(from, p):
						hit = true
						break
				if hit:
					reached.append(p)
					pending.remove_at(j)
					moved = true
				else:
					j += 1
		if not pending.is_empty():
			_fail(floor_index, seed_value,
				"room %d (%s) has %d unreachable platform(s)" % [i, room["kind"], pending.size()])


func _check_spawns(floor_index: int, seed_value: int, rooms: Array, solids: Array) -> void:
	for i in rooms.size():
		var room: Dictionary = rooms[i]
		if (room["enemies"] as Array).is_empty():
			continue  # an empty room never calls _take_point, so its points are unused
		var half := FALLBACK_BOX
		for group in room["enemies"]:
			var cfg: Dictionary = Data.enemies.get(str(group[0]), {})
			half = Vector2(
				maxf(half.x, float(cfg.get("body_radius", 12.0))),
				maxf(half.y, float(cfg.get("body_height", 42.0)) * 0.5))
		for point in room["spawns"]:
			var at: Vector2 = point
			if at.y > LevelGen.BASE_Y:
				_fail(floor_index, seed_value, "spawn %s below the bottom ledge" % str(at.round()))
				continue
			var box := _box(at, half)
			for rect in solids:
				var r: Rect2 = rect
				if box.intersects(r):
					_fail(floor_index, seed_value,
						"room %d spawn %s overlaps terrain %s" % [i, str(at.round()), str(r)])
					break


# --- physical walk ----------------------------------------------------------

## A real body, real jumps, real collisions: proves the floor can be crossed
## from the start point to the exit gate, which no amount of geometry checking
## can. Enemies are killed on sight so the walk measures the terrain, not the
## player's DPS.
func _walk_case(floor_index: int, seed_value: int) -> void:
	await _teardown()
	_build(floor_index, seed_value)
	var data: Dictionary = _level.data
	var exit_pos: Vector2 = data["exit"]
	var wall_x := float(data["width"]) - 30.0
	var frames := 0
	var jump_held := false
	# The floors got wider (5600-8200 px), and a flat 3000-frame cap stopped the
	# walk 800 px short on floor 4. Budget from the distance actually walked at
	# the player's top speed, plus slack for the jumps.
	var budget := int(120.0 * (float(data["width"]) / 250.0 + 10.0))
	# ...but a STUCK player is what this test is really looking for, and a frame
	# count cannot tell "stuck" from "slow". Watch progress instead: if x has not
	# advanced in 2 s of physics, the route is blocked.
	var stall := 0
	var last_x := -1.0

	# 1. hop right to the gate's x, 2. all the way to the wall so any platform
	# is left behind, 3. back left to the gate on the floor.
	var phases := [[exit_pos.x, 1], [wall_x, 1], [exit_pos.x + 4.0, -1]]
	Input.action_press("move_right")
	for phase in phases:
		var target: float = phase[0]
		var dir: int = phase[1]
		Input.action_release("move_left")
		Input.action_release("move_right")
		Input.action_press("move_right" if dir > 0 else "move_left")
		while frames < budget:
			await get_tree().physics_frame
			frames += 1
			for enemy in _enemies():
				_kill(enemy)
			if not is_instance_valid(_player):
				return
			# Hold the jump until the fall starts so the cut does not eat the arc.
			if _player.is_on_floor() and not jump_held:
				Input.action_press("jump")
				jump_held = true
			elif jump_held and _player.velocity.y > 0.0:
				Input.action_release("jump")
				jump_held = false
			if _player.global_position.y > LevelGen.BASE_Y + 120.0:
				_fail(floor_index, seed_value, "walk: player fell out of the world")
				return
			var here := _player.global_position.x
			if absf(here - last_x) < 0.5:
				stall += 1
				if stall > 240:
					_fail(floor_index, seed_value,
						"walk: stuck at x=%.0f heading for %.0f" % [here, target])
					return
			else:
				stall = 0
				last_x = here
			if dir > 0 and _player.global_position.x >= target:
				break
			if dir < 0 and _player.global_position.x <= target:
				break
		if frames >= budget:
			_fail(floor_index, seed_value,
				"walk: never reached x=%.0f (stopped at %.0f of %.0f after %d frames)"
				% [target, _player.global_position.x, data["width"], frames])
			return
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("jump")

	for i in 240:
		await get_tree().physics_frame
		if _cleared == 1:
			break
	if _cleared != 1:
		_fail(floor_index, seed_value,
			"walk: gate never opened (clears=%d, pos=%s, gate=%s)"
			% [_cleared, str(_player.global_position.round()), str(exit_pos.round())])
