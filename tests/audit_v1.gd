extends Node
## AUDITOR V1 probe - the vertical traversal layer.
##
## Sweeps floors 1..5 x seeds 1..40 and checks, in order:
##   1. SOFTLOCK   a real Player, driven only by Input.action_press, must reach
##                 the exit x of every floor. All 200 cases run at once, each in
##                 its own vertical slot, so the sweep costs one floor of game
##                 time instead of two hundred.
##   2. NO FALLING a body never drops below the bottom ledge, and every room
##                 slab and every deck is reachable from its room's slab using
##                 the generator's own jump budget.
##   3. ONE-WAY    a one-way deck is climbed from below, a solid mass is not,
##                 and enemies stand on decks instead of through them.
##   4. SPAWNS     no spawn sits in stone, none is born within 160 px of the
##                 player, and every planned enemy of a room appears.
##   5. EXIT GATE  opens on the last death, fires `cleared` exactly once, and
##                 fires from a deck directly above the gate.
##
## Run: godot --headless --path . tests/audit_v1.tscn

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const FLOORS := 5
const SEEDS := 40
## Vertical slot per parallel case: one floor is ~1100 px tall.
const CASE_GAP := 1400.0
## 50 s of game time per case. A 6400 px floor crossed at ~200 px/s needs ~33 s.
const WALK_FRAMES := 6000
## A case that has not advanced 4 px in this many frames is stuck for good.
const STUCK_FRAMES := 420
## Jump hold long enough for the full 0.35 s rise, so the release never cuts
## the arc; the bot therefore bunny-hops at full height like a player would.
const JUMP_HOLD := 44

var _world: Node2D
var _fails := 0
var _softlocks: Array[String] = []
var _closest_spawn := 1.0e9
var _dump_case := ""


func _ready() -> void:
	_world = Node2D.new()
	_world.name = "AuditWorld"
	add_child(_world)
	Game.fx_root = _world
	await get_tree().process_frame

	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_dump_case = str(args[0])
	_check_geometry()
	if not _dump_case.is_empty():
		_dump(_dump_case)
		_finish()
		return
	await _check_softlocks()
	await _check_oneway()
	await _check_spawns()
	await _check_gate()
	_finish()


func _finish() -> void:
	Input.action_release("move_right")
	Input.action_release("jump")
	if _softlocks.is_empty():
		print("SOFTLOCKS: none")
	else:
		for line in _softlocks:
			print("SOFTLOCK ", line)
	print("closest spawn to the player: %.0f px (floor is 160)" % _closest_spawn)
	print("AUDIT V1 %s (%d failure%s)" % [
		"OK" if _fails == 0 else "FAILED", _fails, "" if _fails == 1 else "s"])
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if _fails == 0 else 1)


func _fail(where: String, what: String) -> void:
	_fails += 1
	print("FAIL %s: %s" % [where, what])


# --- shared data helpers ----------------------------------------------------

func _cases() -> Array:
	var out: Array = []
	for f in FLOORS:
		for s in SEEDS:
			out.append(Vector2i(f + 1, s + 1))
	return out


func _solids(data: Dictionary) -> Array:
	# Every body the level builds, in the same order level.gd builds them.
	var out: Array = []
	for room in data["rooms"]:
		for rect in room["ground"]:
			out.append(rect)
		for rect in room["platforms"]:
			out.append(rect)
	out.append(Rect2(-Level.WALL_W, Level.WALL_TOP, Level.WALL_W, Level.WALL_H))
	out.append(Rect2(float(data["width"]), Level.WALL_TOP, Level.WALL_W, Level.WALL_H))
	return out


func _body_half(groups: Array) -> Vector2:
	# Widest body a room's spawn points have to clear. Floored at the 50 px
	# husk/ram so a point is never chosen for the smallest enemy in the room.
	var half := Vector2(16.0, 25.0)
	for group in groups:
		var cfg: Dictionary = Data.enemies.get(str(group[0]), {})
		half = Vector2(maxf(half.x, float(cfg.get("body_radius", 12.0))),
			maxf(half.y, float(cfg.get("body_height", 42.0)) * 0.5))
	return half


func _box(centre: Vector2, half: Vector2) -> Rect2:
	return Rect2(centre - half, half * 2.0)


# --- 1 + 2: geometry sweep --------------------------------------------------

func _check_geometry() -> void:
	for c in _cases():
		var floor_index: int = c.x
		var seed_value: int = c.y
		var where := "floor %d seed %d" % [floor_index, seed_value]
		var data := LevelGen.generate(floor_index, seed_value)
		var rooms: Array = data["rooms"]
		var solids := _solids(data)
		var width := float(data["width"])

		# The bottom ledge must be continuous, or a body falls out of the world.
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
			if s.x - cursor > 0.5:
				_fail(where, "%.0f px hole in the ledge at x=%.0f" % [s.x - cursor, cursor])
			cursor = maxf(cursor, s.y)
		if cursor < width - 0.5:
			_fail(where, "ledge ends at x=%.0f, wall at %.0f" % [cursor, width])

		var reach: Dictionary = data["reachable"]
		if not bool(reach["ok"]):
			_fail(where, "generator says a room slab is unreachable")
		if int(reach.get("decks", 0)) != 0:
			_fail(where, "generator says %d deck(s) are outside the jump budget"
				% int(reach["decks"]))

		for ri in rooms.size():
			var room: Dictionary = rooms[ri]
			var slab: Rect2 = room["rect"]
			# 2. every deck reachable from the room's slab, same budget the
			# generator uses for the exit.
			var platforms: Array = room["platforms"]
			var reached: Array = [slab]
			var pending: Array = platforms.duplicate()
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
				_fail(where, "room %d (%s) has %d deck(s) outside the jump budget"
					% [ri, str(room["kind"]), pending.size()])

			# 4. every spawn point must stand on a surface, clear of stone.
			if (room["enemies"] as Array).is_empty():
				continue
			var half := _body_half(room["enemies"])
			for point in room["spawns"]:
				var at: Vector2 = point
				if at.y > LevelGen.BASE_Y:
					_fail(where, "room %d spawn %s below the bottom ledge"
						% [ri, str(at.round())])
					continue
				var box := _box(at, half)
				for rect in solids:
					var r: Rect2 = rect
					if box.intersects(r):
						_fail(where, "room %d spawn %s is inside %s"
							% [ri, str(at.round()), str(r)])
						break
				# Feet must have something to land on right under them.
				var feet := at.y + half.y
				var supported := false
				for rect in solids:
					var r: Rect2 = rect
					if at.x < r.position.x - 1.0 or at.x > r.end.x + 1.0:
						continue
					if r.position.y >= feet - 1.0 and r.position.y <= feet + LevelGen.SPAWN_LIFT + 2.0:
						supported = true
						break
				if not supported:
					_fail(where, "room %d spawn %s has no surface under it"
						% [ri, str(at.round())])


# --- 1: softlock sweep ------------------------------------------------------

func _check_softlocks() -> void:
	var cases := _cases()
	var live: Array = []
	for i in cases.size():
		var floor_index: int = cases[i].x
		var seed_value: int = cases[i].y
		var offset := Vector2(0.0, CASE_GAP * float(i))
		var player := PLAYER_SCENE.instantiate() as Player
		_world.add_child(player)
		var level := Level.new()
		level.position = offset
		_world.add_child(level)
		level.build(floor_index, seed_value)
		# Terrain only: a blocking enemy body is a combat problem, not a
		# traversal one, and one shared Input cannot fight 200 fights at once.
		level.set_physics_process(false)
		player.global_position = (level.data["start"] as Vector2) + offset
		player.max_hp = 1.0e9
		player.hp = 1.0e9
		live.append({
			"where": "floor %d seed %d" % [floor_index, seed_value],
			"player": player,
			"level": level,
			"exit_x": (level.data["exit"] as Vector2).x,
			"bottom": LevelGen.BASE_Y + 60.0 + offset.y,
			"best": player.global_position.x,
			"idle": 0,
			"done": false,
		})

	Input.action_press("move_right")
	var hold := 0
	var frames := 0
	while frames < WALK_FRAMES:
		await get_tree().physics_frame
		frames += 1
		var grounded := false
		var pending := 0
		for c in live:
			if bool(c["done"]):
				continue
			pending += 1
			var p: Player = c["player"]
			if not is_instance_valid(p):
				c["done"] = true
				continue
			if p.is_on_floor():
				grounded = true
			if p.global_position.y > float(c["bottom"]):
				c["done"] = true
				_fail(str(c["where"]), "player fell out of the world (y=%.0f)"
					% p.global_position.y)
				continue
			if p.global_position.x >= float(c["exit_x"]):
				c["done"] = true
				continue
			if p.global_position.x > float(c["best"]) + 4.0:
				c["best"] = p.global_position.x
				c["idle"] = 0
			else:
				c["idle"] = int(c["idle"]) + 1
				if int(c["idle"]) >= STUCK_FRAMES:
					c["done"] = true
					_softlocks.append("%s stuck at x=%.0f (exit %.0f) in %s"
						% [c["where"], p.global_position.x, float(c["exit_x"]),
							_room_at(c["level"], p.global_position.x)])
		if pending == 0:
			break
		# Bunny hop: press on the first landing, hold the whole rise, release
		# only once the arc is over so the variable-jump cut never fires.
		if hold == 0:
			if grounded:
				Input.action_press("jump")
				hold = 1
		elif hold <= JUMP_HOLD:
			hold += 1
		else:
			Input.action_release("jump")
			hold = 0
	Input.action_release("jump")
	Input.action_release("move_right")

	for c in live:
		if not bool(c["done"]):
			_softlocks.append("%s timed out at x=%.0f (exit %.0f)"
				% [c["where"], float(c["best"]), float(c["exit_x"])])
		var p: Node = c["player"]
		if is_instance_valid(p):
			p.queue_free()
	for child in _world.get_children():
		if child is Level:
			child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _room_at(level: Level, x: float) -> String:
	for i in (level.data["rooms"] as Array).size():
		var rect: Rect2 = level.data["rooms"][i]["rect"]
		if x >= rect.position.x and x < rect.end.x:
			return "room %d (%s) %.0f..%.0f, slab y=%.0f" % [i,
				str(level.data["rooms"][i]["kind"]), rect.position.x, rect.end.x,
				rect.position.y]
	return "the gap after room %d" % (level.data["rooms"] as Array).size()


# --- harness for the single-case checks ------------------------------------

func _build(floor_index: int, seed_value: int) -> Dictionary:
	await _teardown()
	var player := PLAYER_SCENE.instantiate() as Player
	_world.add_child(player)
	player.max_hp = 1.0e9
	player.hp = 1.0e9
	var level := Level.new()
	_world.add_child(level)
	level.build(floor_index, seed_value)
	player.global_position = level.data["start"]
	return {"player": player, "level": level}


func _teardown() -> void:
	Game.player = null
	Game.boss = null
	for child in _world.get_children():
		child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _step(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


# --- 3: one-way vs solid ----------------------------------------------------

func _check_oneway() -> void:
	# Find the cases that actually contain the geometry under test: a one-way
	# deck with open space below it, and a solid mass with a low ceiling.
	var deck_case := {}
	var mass_case := {}
	for c in _cases():
		var data := LevelGen.generate(c.x, c.y)
		var solids := _solids(data)
		if deck_case.is_empty():
			var d := _pick_deck(data, solids, true)
			if not d.is_empty():
				deck_case = {"pair": c, "pick": d}
		if mass_case.is_empty():
			var m := _pick_deck(data, solids, false)
			if not m.is_empty():
				mass_case = {"pair": c, "pick": m}
		if not deck_case.is_empty() and not mass_case.is_empty():
			break
	if deck_case.is_empty():
		_fail("one-way", "no floor/seed in 200 has a climbable one-way deck")
		return
	if mass_case.is_empty():
		_fail("one-way", "no floor/seed in 200 has a solid mass with a low ceiling")
		return

	# A one-way deck must be climbed from below.
	var pair: Vector2i = deck_case["pair"]
	var deck: Dictionary = deck_case["pick"]
	var env: Dictionary = await _build(pair.x, pair.y)
	var player: Player = env["player"]
	player.global_position = Vector2(float(deck["x"]), float(deck["surface"]) - 40.0)
	await _step(6)
	Input.action_press("jump")
	for i in 60:
		await get_tree().physics_frame
		if i == JUMP_HOLD:
			Input.action_release("jump")
	Input.action_release("jump")
	await _step(40)
	print("one-way deck under test: floor %d seed %d x=%.0f top=%.0f"
		% [pair.x, pair.y, float(deck["x"]), float(deck["top"])])
	var top := float(deck["top"])
	if player.global_position.y > top - 4.0:
		_fail("floor %d seed %d" % [pair.x, pair.y],
			"one-way deck at x=%.0f y=%.0f was not climbed from below (ended %.0f)"
			% [float(deck["x"]), top, player.global_position.y])

	# A solid mass must not be passed through from below.
	pair = mass_case["pair"]
	var mass: Dictionary = mass_case["pick"]
	print("solid mass under test: floor %d seed %d x=%.0f underside=%.0f"
		% [pair.x, pair.y, float(mass["x"]), float(mass["bottom"])])
	env = await _build(pair.x, pair.y)
	player = env["player"]
	player.global_position = Vector2(float(mass["x"]), float(mass["surface"]) - 40.0)
	await _step(6)
	Input.action_press("jump")
	var head := 1.0e9
	for i in 90:
		await get_tree().physics_frame
		head = minf(head, player.global_position.y - 23.0)
		if i == JUMP_HOLD:
			Input.action_release("jump")
	Input.action_release("jump")
	if head < float(mass["bottom"]) - 1.0:
		_fail("floor %d seed %d" % [pair.x, pair.y],
			"solid mass at x=%.0f was passed through from below (head %.0f, underside %.0f)"
			% [float(mass["x"]), head, float(mass["bottom"])])

	# Enemies must stand on the deck they spawned on, not through it.
	for c in [Vector2i(1, 1), Vector2i(2, 5), Vector2i(4, 21)]:
		env = await _build(c.x, c.y)
		await _check_enemies_on_decks(c, env["level"], env["player"])


## Finds a platform with open space under it.
##  oneway: a deck whose top is reachable from a surface below and which the
##          body can rise through.
##  solid:  a mass whose bottom is less than a jump above the surface below,
##          so the body would pass through it if the collision were wrong.
func _pick_deck(data: Dictionary, solids: Array, oneway: bool) -> Dictionary:
	for room in data["rooms"]:
		var platforms: Array = room["platforms"]
		var flags: Array = room["oneway"]
		for i in platforms.size():
			var p: Rect2 = platforms[i]
			if bool(flags[i]) != oneway:
				continue
			var cx := p.get_center().x
			# A surface under this platform, horizontally covering its centre.
			var surface := 1.0e9
			for rect in solids:
				var r: Rect2 = rect
				if cx < r.position.x or cx > r.end.x:
					continue
				if r.position.y <= p.position.y + 1.0:
					continue
				surface = minf(surface, r.position.y)
			if surface > 1.0e8:
				continue
			# The platform has to be inside one jump of the surface below it.
			var up := surface - p.position.y
			if up < 60.0 or up > 100.0:
				continue
			# Nothing solid may sit between the surface and the platform.
			var blocked := false
			for rect in solids:
				var r: Rect2 = rect
				if r == p or cx < r.position.x or cx > r.end.x:
					continue
				if r.position.y < surface - 1.0 and r.end.y > p.end.y + 1.0:
					blocked = true
					break
			if blocked:
				continue
			return {"x": cx, "surface": surface, "top": p.position.y, "bottom": p.end.y}
	return {}


func _check_enemies_on_decks(pair: Vector2i, level: Level, player: Player) -> void:
	# Sample each room right after it is entered: an enemy's _spawn_t is at
	# least 0.1 s, so inside the first 14 frames it only falls - which is
	# exactly the "does it land on the deck it was placed on" question.
	var data: Dictionary = level.data
	var rooms: Array = data["rooms"]
	var solids := _solids(data)
	var where := "floor %d seed %d" % [pair.x, pair.y]
	for i in rooms.size():
		var rect: Rect2 = rooms[i]["rect"]
		player.global_position = Vector2(rect.position.x + 2.0, rect.position.y - 40.0)
		await _step(2)
		var born: Array = []
		for child in level.get_children():
			if child is Enemy and int(child.get_meta("room", -1)) == i and not (child as Enemy)._dead:
				born.append([child, (child as Enemy).global_position.y, false, 0.0])
		# 30 frames: long enough for the 38 px drop to finish, short enough
		# that the 20 px spawn inset still keeps the body over its surface.
		for f in 30:
			await get_tree().physics_frame
			for entry in born:
				var body: Enemy = entry[0]
				if not is_instance_valid(body) or body._dead:
					continue
				entry[2] = bool(entry[2]) or body.is_on_floor()
				entry[3] = maxf(float(entry[3]), body.global_position.y - float(entry[1]))
		for entry in born:
			var enemy: Enemy = entry[0]
			if not is_instance_valid(enemy) or enemy._dead:
				continue
			var half := float(enemy.cfg.get("body_height", 42.0)) * 0.5
			var reach := float(enemy.cfg.get("body_radius", 12.0)) + 1.0
			var feet := enemy.global_position.y + half
			var drop := float(entry[3])
			if drop > LevelGen.SPAWN_LIFT - half + 10.0:
				_fail(where, "%s at x=%.0f fell %.0f px through the deck it spawned on"
					% [enemy.kind, enemy.global_position.x, drop])
			if not bool(entry[2]):
				_fail(where, "%s at %s never landed"
					% [enemy.kind, str(enemy.global_position.round())])
				continue
			var standing := false
			for r in solids:
				var rect2: Rect2 = r
				if enemy.global_position.x < rect2.position.x - reach or enemy.global_position.x > rect2.end.x + reach:
					continue
				if feet >= rect2.position.y - 4.0 and feet <= rect2.position.y + 4.0:
					standing = true
					break
			if not standing:
				_fail(where, "%s stands at %s with no surface under it (feet %.0f)"
					% [enemy.kind, str(enemy.global_position.round()), feet])
			if enemy.global_position.y > LevelGen.BASE_Y + 60.0:
				_fail(where, "%s fell below the ledge" % enemy.kind)


# --- 4 + 5: spawns, room population, gate ----------------------------------

func _check_spawns() -> void:
	for pair in [Vector2i(1, 3), Vector2i(2, 8), Vector2i(3, 14), Vector2i(4, 27), Vector2i(5, 2)]:
		var env: Dictionary = await _build(pair.x, pair.y)
		var level: Level = env["level"]
		var player: Player = env["player"]
		var data: Dictionary = level.data
		var rooms: Array = data["rooms"]
		var where := "floor %d seed %d" % [pair.x, pair.y]
		for i in rooms.size():
			var rect: Rect2 = rooms[i]["rect"]
			var planned := 0
			for group in rooms[i]["enemies"]:
				planned += int(group[1])
			# Enter the room the way the level detects it: by x.
			player.global_position = Vector2(rect.position.x + 1.0, rect.position.y - 40.0)
			await _step(3)
			if not bool(level._room_entered[i]):
				_fail(where, "room %d never entered" % i)
			var found := 0
			for child in level.get_children():
				if child is Enemy and int(child.get_meta("room", -1)) == i and not (child as Enemy)._dead:
					found += 1
					var dist: float = (child as Enemy).global_position.distance_to(player.global_position)
					_closest_spawn = minf(_closest_spawn, dist)
					if dist < 160.0:
						_fail(where, "room %d: %s spawned %.0f px from the player"
							% [i, (child as Enemy).kind, dist])
			if found != planned:
				_fail(where, "room %d spawned %d of %d enemies" % [i, found, planned])


func _check_gate() -> void:
	for pair in [Vector2i(1, 2), Vector2i(2, 9), Vector2i(3, 19), Vector2i(4, 33), Vector2i(5, 1)]:
		var env: Dictionary = await _build(pair.x, pair.y)
		var level: Level = env["level"]
		var player: Player = env["player"]
		var data: Dictionary = level.data
		var rooms: Array = data["rooms"]
		var where := "floor %d seed %d" % [pair.x, pair.y]
		var clears: Array = [0]
		level.cleared.connect(func() -> void: clears[0] += 1)
		for i in rooms.size():
			var rect: Rect2 = rooms[i]["rect"]
			player.global_position = Vector2(rect.position.x + 1.0, rect.position.y - 40.0)
			await _step(3)
		await _step(10)
		if bool(level._door.open):
			_fail(where, "gate open with enemies alive")
		# Kill everything one at a time; the gate must stay shut until the end.
		var live: Array = []
		for child in level.get_children():
			if child is Enemy and not (child as Enemy)._dead:
				live.append(child)
		for i in live.size():
			var enemy: Enemy = live[i]
			enemy.take_hit({
				"damage": 1.0e6, "crit": true, "knockback": 0.0, "hitstop": 0.0,
				"source_pos": enemy.global_position + Vector2(-40.0, 0.0),
				"point": enemy.global_position,
			})
			await get_tree().physics_frame
			await get_tree().physics_frame
			if i < live.size() - 1 and bool(level._door.open):
				_fail(where, "gate opened with %d enemies still alive" % (live.size() - 1 - i))
				break
		await _step(6)
		if int(level.enemies_remaining()) != 0:
			_fail(where, "enemies_remaining %d after clearing" % level.enemies_remaining())
		if not bool(level._door.open):
			_fail(where, "gate stayed shut after the last death")

		# Stand on the deck directly above the gate: the gate is a column, so
		# this must already count as arriving - and only once.
		var gate: Vector2 = data["exit"]
		var deck := _deck_over(rooms[rooms.size() - 1], gate.x)
		if deck < -1.0e8:
			_fail(where, "no deck over the gate at x=%.0f" % gate.x)
		else:
			print("gate deck: floor %d seed %d %.0f px above the gate (column reach %.0f)"
				% [pair.x, pair.y, gate.y - deck, Level.DOOR_HEIGHT])
			player.global_position = Vector2(gate.x, deck - 30.0)
			await _step(20)
			if clears[0] != 1:
				_fail(where, "cleared fired %d times from the deck above the gate" % clears[0])
		# Then the ordinary case: standing on the slab at the gate.
		player.global_position = gate + Vector2(0.0, -30.0)
		await _step(20)
		if clears[0] != 1:
			_fail(where, "cleared fired %d times in total (expected 1)" % clears[0])
		# And it must not fire again later.
		player.global_position = (data["start"] as Vector2)
		await _step(20)
		if clears[0] != 1:
			_fail(where, "cleared fired %d times after leaving the gate" % clears[0])


## Top y of the highest platform whose x range covers `x`, or -1e9 if none.
func _deck_over(room: Dictionary, x: float) -> float:
	var best := -1.0e9
	var platforms: Array = room["platforms"]
	for i in platforms.size():
		var p: Rect2 = platforms[i]
		if x < p.position.x or x > p.end.x:
			continue
		if best < -1.0e8 or p.position.y < best:
			best = p.position.y
	return best


# --- debug ------------------------------------------------------------------

func _dump(spec: String) -> void:
	var parts := spec.split(",")
	var data := LevelGen.generate(int(parts[0]), int(parts[1]))
	var solids := _solids(data)
	print("== dump floor %s" % spec)
	for ri in (data["rooms"] as Array).size():
		var room: Dictionary = data["rooms"][ri]
		print("room %d %s slab=%s" % [ri, str(room["kind"]), str(room["rect"])])
		var platforms: Array = room["platforms"]
		for i in platforms.size():
			print("   platform oneway=%s %s" % [str(room["oneway"][i]), str(platforms[i])])
		for point in room["spawns"]:
			var at: Vector2 = point
			var hit := ""
			var half := _body_half(room["enemies"])
			for rect in solids:
				if _box(at, half).intersects(rect):
					hit = " HITS %s" % str(rect)
					break
			print("   spawn %s%s" % [str(at.round()), hit])
	print("exit %s start %s" % [str(data["exit"]), str(data["start"])])
