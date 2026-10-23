class_name LevelGen
extends RefCounted
## Pure-data floor layout: a vertical, multi-route space, not a corridor.
##
## The shape of a floor
##   A continuous bottom ledge runs the whole width. Rooms sit above it on
##   slabs that step up and down, and most rooms also carry a SECOND and
##   THIRD deck. Two kinds of surface exist:
##
##     one-way decks  jump up THROUGH them, land on top. Thin, light, with a
##                    dashed under-edge so they read as pass-through.
##     solid masses   slabs, pillars, ceiling blocks. You must go around or
##                    over them; you cannot pass through.
##
##   Every floor also places a few tall PILLARS rising from the ledge between
##   rooms. A pillar cannot be jumped, so the only way past is the room's
##   decks: the level forces vertical movement instead of letting the player
##   hold right along the floor.
##
## Everything here is generated from (floor, seed) and then BFS-verified: if
## the exit cannot be reached from the start, the generator warns instead of
## shipping a dead level.

# Jump budget measured from player.gd: v0=630, gravity_rise=1800 -> ~110 px
# apex; ~0.42 s of air at 300 px/s -> ~180 px of travel.
const JUMP_HEIGHT := 110.0
const JUMP_LENGTH := 180.0
const MAX_UP := 100.0
const MAX_SPAN := 170.0
## Vertical gap between decks. 92 leaves 18 px of headroom under MAX_UP.
const TIER := 92.0

const BASE_Y := 150.0
const LEDGE_H := 340.0
const SLAB_H := 150.0
const GAP_MIN := 70.0
const GAP_MAX := 190.0
## Centre of a spawn point above its surface. WHY 38 and not 42: the tightest
## ceiling over any spawn surface is a 26 px solid mass exactly TIER (92) above
## it, so lift + 25 (half of the tallest 50 px body) has to stay under 66.
const SPAWN_LIFT := 38.0
## Widest body in data/enemies.json (the Warden). A spawn point must clear this
## much on both sides, or the enemy is born inside the platform above it.
const SPAWN_RADIUS := 20.0
const DECK_H := 13.0

const KIND_WEIGHT := {"gate": 1.2, "hall": 1.4, "shaft": 0.8, "vault": 1.0, "bridge": 0.9, "well": 0.9}
const KIND_MIN := {"gate": 420.0, "hall": 460.0, "shaft": 280.0, "vault": 380.0, "bridge": 440.0, "well": 400.0}
const MIDDLE_KINDS := ["shaft", "vault", "gate", "bridge", "hall", "well"]


static func generate(floor_index: int, seed_value: int) -> Dictionary:
	var cfg := _floor_config(floor_index)
	var rng := RandomNumberGenerator.new()
	# The floor index is folded in so one run seed does not produce five
	# identical room orders; (floor, seed) is still fully deterministic.
	rng.seed = seed_value * 7919 + floor_index * 131 + 17
	var room_count := maxi(1, int(cfg.get("rooms", 3)))
	var target := float(cfg.get("width", 3200.0))
	var boss := str(cfg.get("boss", ""))
	assert(room_count >= 1, "a floor needs at least one room")

	var kinds := _pick_kinds(room_count, rng)

	# Vertical offsets first, then gaps. A gap is only crossable if the room it
	# leads to is close enough, so the gap has to be derived FROM the climb.
	# Doing it the other way round produced floors whose exit slab sat 185 px
	# away and 26 px up - outside the 161 px budget, so the floor was dead.
	var offsets: Array = []
	for i in room_count:
		if i == 0:
			offsets.append(0.0)
			continue
		var previous: float = offsets[i - 1]
		# Capped at 96 so the continuous bottom ledge is always a valid way up:
		# a higher slab would be out of reach if the player fell.
		offsets.append(clampf(previous + rng.randf_range(-96.0, 96.0), 0.0, 96.0))

	var gaps: Array = []
	var gap_total := 0.0
	for i in room_count - 1:
		# Golden-ratio spacing: gaps vary without ever looking random.
		var t := fposmod(float(i + 1) * MathArt.INV_PHI * MathArt.INV_PHI + rng.randf() * 0.18, 1.0)
		var desired := lerpf(GAP_MIN, GAP_MAX, t)
		var up: float = offsets[i + 1] - offsets[i]
		var gap := desired
		if up > 0.0:
			# Same budget the reachability check uses, minus a margin so a
			# player who jumps late still makes it.
			var budget := JUMP_LENGTH * (1.0 - 0.45 * up / JUMP_HEIGHT) - 14.0
			gap = clampf(minf(desired, budget), GAP_MIN, GAP_MAX)
		gaps.append(gap)
		gap_total += gap
	var widths := _fit_widths(kinds, maxf(1100.0, target - gap_total))

	var plan := _plan_enemies(cfg, room_count, boss)

	var rooms: Array = []
	var cursor := 0.0
	for i in room_count:
		var w: float = widths[i]
		assert(w > 0.0, "room width must be positive")
		# Vertical variety: a room sits 0-96 px above the bottom ledge, so the
		# floor reads as terraced ground rather than a flat strip.
		var offset: float = offsets[i]
		var rect := Rect2(cursor, BASE_Y - offset, w, SLAB_H)
		var built := _build_room(kinds[i], rect, rng)
		var gap_after: float = gaps[i] if i < gaps.size() else 0.0
		# Ledge first: the ground array is draw order, deepest face first.
		var ground: Array = [Rect2(cursor, BASE_Y, w + gap_after, LEDGE_H), rect]
		var room := {
			"rect": rect,
			"kind": kinds[i],
			"platforms": built["platforms"],
			"oneway": built["oneway"],
			"ground": ground,
			"enemies": plan[i],
		}
		rooms.append(room)
		cursor += w + gap_after

	# Pillars between rooms. They rise from the ledge past the slab line, so the
	# only way forward is up and over the room's decks.
	_place_pillars(rooms, rng)

	# WHY after the pillars: _place_pillars adds a step deck and a pillar to the
	# room it leaves, and a spawn point computed before that does not know they
	# exist - the enemy is then born inside the step deck. Spawns are derived
	# from the final surface list, so the last mutation has to come first.
	for i in room_count:
		rooms[i]["spawns"] = _spawns_for(rooms[i]["rect"], rooms[i]["platforms"],
			_spawn_half(plan[i]))

	var first: Rect2 = rooms[0]["rect"]
	var last: Rect2 = rooms[room_count - 1]["rect"]
	# A boss floor spawns its single enemy in the only room, and the room's
	# generic spawn points are chosen for a 42 px husk. Pin the boss to a lane
	# with no deck in front of it so the fight is readable.
	var boss_at: Variant = null
	if not boss.is_empty():
		boss_at = boss_spawn(last, rooms[room_count - 1]["platforms"])
	return {
		"boss_at": boss_at,
		"seed": seed_value,
		"name": str(cfg.get("name", "FLOOR %d" % floor_index)),
		"palette": int(cfg.get("palette", 0)),
		"width": cursor,
		"rooms": rooms,
		"start": Vector2(first.position.x + 70.0, first.position.y - 44.0),
		"exit": Vector2(last.end.x - 90.0, last.position.y),
		"boss": boss,
		"reachable": _verify(rooms, Vector2(first.position.x + 70.0, first.position.y - 44.0), floor_index, seed_value),
	}


# --- room construction ------------------------------------------------------

## Returns { "platforms": Array[Rect2], "oneway": Array[bool] }.
## Two parallel arrays instead of a dictionary per surface: the geometry is
## what every consumer (collision, BFS, spawn clearance) needs, and a bare
## Rect2 cannot disagree with itself about its own rect.
static func _build_room(kind: String, rect: Rect2, rng: RandomNumberGenerator) -> Dictionary:
	var x := rect.position.x
	var w := rect.size.x
	var top := rect.position.y
	var out: Array = []
	var flags: Array = []

	var deck := func(dx: float, dy: float, dw: float, oneway: bool) -> void:
		out.append(Rect2(x + dx, top - dy, dw, DECK_H if oneway else 26.0))
		flags.append(oneway)
	var mass := func(mr: Rect2) -> void:
		out.append(mr)
		flags.append(false)

	match kind:
		"gate":
			# Two pass-through decks: the classic lower/upper route split.
			deck.call(w * 0.06, TIER, w * 0.52, true)
			deck.call(w * 0.62, TIER, w * 0.32, true)
			deck.call(w * 0.30, TIER * 2.0, w * 0.34, true)

		"hall":
			# Column capitals, then an upper gallery that runs most of the room.
			var pw := clampf(w * 0.18, 96.0, 150.0)
			for i in 3:
				deck.call(w * (0.12 + 0.29 * float(i)), TIER, pw, true)
			deck.call(w * 0.04, TIER * 2.0, w * 0.44, true)
			deck.call(w * 0.56, TIER * 2.0, w * 0.40, true)

		"shaft":
			# Narrow and tall: a zigzag climb to a high shelf. This is the room
			# that makes a floor feel vertical instead of flat.
			# WHY no upper cap on the rung width: the rungs alternate sides, so a
			# cap (240) makes them 2 x 240 = 480 apart in a 700 px room, which is
			# four times the horizontal budget of a 92 px climb. Keeping every
			# rung at 62% of the room width leaves 24% of overlap at each step.
			var sw := maxf(150.0, w * 0.62)
			for i in 4:
				var side := 0.0 if i % 2 == 0 else (w - sw)
				deck.call(side, TIER * float(i + 1), sw, true)
			deck.call(w * 0.10, TIER * 5.0, w * 0.80, false)

		"vault":
			# Two chambers: a solid floor with a hole, bridged by a one-way
			# platform so the climb reads as "through, then up".
			var hole := clampf(w * 0.18, 80.0, 120.0)
			var left := w * 0.04
			var right := w * 0.04 + hole + w * 0.30
			mass.call(Rect2(x + left, top - TIER * 2.0, w * 0.30, 26.0))
			mass.call(Rect2(x + right, top - TIER * 2.0, w * 0.94 - right, 26.0))
			deck.call(w * 0.06, TIER, hole + w * 0.14, true)
			deck.call(w * 0.55, TIER, w * 0.24, true)

		"bridge":
			# A wide gap crossed by stepping stones at two heights. The lower
			# line is safe and slow; the upper line is fast and exposed.
			var stones := 4
			for i in stones:
				var t := (float(i) + 0.5) / float(stones)
				deck.call(w * t - 46.0, TIER, 92.0, true)
			for i in 3:
				var t := (float(i) + 0.5) / 3.0
				deck.call(w * t - 40.0, TIER * 2.0, 80.0, true)

		"well":
			# A solid wall across the middle of the room, taller than a single
			# jump. The only way past is up: two stacked pass-through decks on
			# the approach side, then over the wall and drop.
			#
			# The wall sits INSIDE the room, never on its boundary: a wall at
			# the boundary blocks entry and the room can never be entered.
			var wall_w := clampf(w * 0.09, 48.0, 70.0)
			var wall_h := 168.0
			mass.call(Rect2(x + w * 0.44, top - wall_h, wall_w, wall_h + 40.0))
			# WHY the lower step runs all the way to the wall's face (0.44): a
			# pocket of slab between the last step and the wall is a dead end for
			# anyone running right. The wall is 168 tall and the only thing
			# overhead there is the TIER*2 deck, out of reach, so the player is
			# walled in with the climb behind them.
			deck.call(w * 0.06, TIER, w * 0.38, true)
			# WHY the upper step stops at the wall's face instead of overhanging
			# it: the wall top is a standable surface, and a deck TIER*2 up puts
			# its underside 3 px over that top - a body standing there is born
			# inside stone. There is no room to raise the deck (the wall is 168
			# tall, a climb is capped at 192), so the crossing is
			# step-off-the-deck, walk the wall, drop.
			deck.call(w * 0.18, TIER * 2.0, w * 0.26, true)
			deck.call(w * 0.66, TIER, w * 0.22, true)
	return {"platforms": out, "oneway": flags}


## Tall solid columns between rooms. Height is capped at two tiers so the room
## decks next to them always provide a way over.
static func _place_pillars(rooms: Array, rng: RandomNumberGenerator) -> void:
	for i in range(1, rooms.size()):
		# Two out of three boundaries get a pillar: enough to force climbing,
		# few enough that the floor still flows.
		if rng.randf() > 0.66:
			continue
		var prev: Rect2 = rooms[i - 1]["rect"]
		var here: Rect2 = rooms[i]["rect"]
		var gap_start := prev.end.x
		var gap_width := here.position.x - gap_start
		if gap_width < 60.0:
			continue
		# Wide enough to be a landing pad, never wider than the gap.
		var pw := clampf(gap_width * 0.62, 64.0, 92.0)
		# Capped at 176: from the step deck at TIER (92) the climb to the top is
		# 84 px, inside MAX_UP (100). A taller pillar could not be climbed at
		# all and would wall the floor off.
		var height := lerpf(126.0, 176.0, rng.randf())
		var left := gap_start + (gap_width - pw) * 0.5
		# The step deck must TOUCH the pillar. With a gap between them the
		# player drops into it, and from the ledge the pillar top is out of
		# reach (apex is 110, the top is 126-176 up) - a guaranteed softlock.
		var step_w := 120.0
		(rooms[i - 1]["platforms"] as Array).append(
			Rect2(left - step_w, BASE_Y - TIER, step_w, DECK_H))
		(rooms[i - 1]["oneway"] as Array).append(true)
		(rooms[i - 1]["platforms"] as Array).append(
			Rect2(left, BASE_Y - height, pw, height + 40.0))
		(rooms[i - 1]["oneway"] as Array).append(false)


# --- layout helpers ---------------------------------------------------------

static func _pick_kinds(count: int, rng: RandomNumberGenerator) -> Array:
	if count == 1:
		# A single room is the boss arena: wide and open.
		return ["hall"]
	var kinds: Array = []
	for i in count:
		kinds.append("gate")
	kinds[count - 1] = "hall"
	var start := rng.randi_range(0, MIDDLE_KINDS.size() - 1)
	for i in range(1, count - 1):
		kinds[i] = MIDDLE_KINDS[(start + i - 1) % MIDDLE_KINDS.size()]
	return kinds


static func _fit_widths(kinds: Array, span: float) -> Array:
	var total := 0.0
	for kind in kinds:
		total += float(KIND_WEIGHT.get(kind, 1.0))
	var widths: Array = []
	for kind in kinds:
		var share: float = float(KIND_WEIGHT.get(kind, 1.0)) / total
		widths.append(maxf(float(KIND_MIN.get(kind, 300.0)), span * share))
	return widths


# --- data -------------------------------------------------------------------

static func _floor_config(floor_index: int) -> Dictionary:
	var table := _floors()
	var cfg: Dictionary = table.get(str(floor_index), {})
	if cfg.is_empty():
		# Foundation may run the generator before the tables exist (tests).
		push_warning("LevelGen: no floor %d in data/floors.json, using defaults" % floor_index)
		cfg = {
			"name": "FLOOR %d" % floor_index, "rooms": 3, "width": 3200.0,
			"enemies": [["grunt", 3]], "boss": "", "palette": (floor_index - 1) % 5,
		}
	return cfg


static func _floors() -> Dictionary:
	var node := Engine.get_main_loop() as SceneTree
	if node == null:
		return {}
	var data := node.root.get_node_or_null("Data")
	if data != null and "floors" in data:
		return data.floors
	return {}


static func _enemy_table() -> Dictionary:
	var node := Engine.get_main_loop() as SceneTree
	if node == null:
		return {}
	var data := node.root.get_node_or_null("Data")
	if data != null and "enemies" in data:
		return data.enemies
	return {}


# --- spawns -----------------------------------------------------------------

## Spawn points live on every surface, not just the slab, so upper decks are
## populated and the player has a reason to climb.
static func _spawns_for(rect: Rect2, platforms: Array, half: float) -> Array:
	var out: Array = []
	var span := maxf(60.0, rect.size.x - 80.0)
	for i in 4:
		var t := fposmod(float(i) * MathArt.INV_PHI, 1.0)
		var x := rect.position.x + 40.0 + span * t
		out.append(_settle(x, rect.position.y - SPAWN_LIFT, platforms, half))
	for pr in platforms:
		var r: Rect2 = pr
		out.append(_settle(r.get_center().x, r.position.y - SPAWN_LIFT, platforms, half))
	return out


## Lift a point out of stone, then re-anchor it over the surface it will
## actually land on. Two rounds: the second x may belong to another platform.
static func _settle(x: float, y: float, platforms: Array, half: float) -> Vector2:
	var p := _clear_y(x, y, platforms, half)
	for _round in 2:
		p = _support(p, platforms, half)
		p = _clear_y(p.x, p.y, platforms, half)
	return p


## WHY: a point can be lifted onto a platform whose top is a few px below the
## body's feet, and land on a platform hanging over that one instead - perched
## on its corner with the centre outside the edge. The first step of the chase
## then drops the body off the level. Pull x inside the landing surface.
static func _support(p: Vector2, platforms: Array, half: float) -> Vector2:
	var feet := p.y + half
	var best := 1.0e9
	var under := Rect2()
	for pr in platforms:
		var r: Rect2 = pr
		if p.x < r.position.x - SPAWN_RADIUS or p.x > r.end.x + SPAWN_RADIUS:
			continue
		# A top between the feet and one lift below is what the body lands on.
		if r.position.y < feet - 1.0 or r.position.y > feet + SPAWN_LIFT + 2.0:
			continue
		if r.position.y < best:
			best = r.position.y
			under = r
	if best > 1.0e8:
		return p
	if under.size.x > SPAWN_RADIUS * 2.0:
		p.x = clampf(p.x, under.position.x + SPAWN_RADIUS, under.end.x - SPAWN_RADIUS)
	else:
		p.x = under.get_center().x
	return p


static func _spawn_half(groups: Array) -> float:
	# Lift from the tallest body that will actually use this room's points; a
	# room with no enemies needs no clearance at all.
	var half := 0.0
	var table := _enemy_table()
	for group in groups:
		var cfg: Dictionary = table.get(str(group[0]), {})
		half = maxf(half, float(cfg.get("body_height", 42.0)) * 0.5)
	return half


## A boss is 64 px tall and 40 px wide; the generic clearance pass uses the
## platform's SPAWN_LIFT, which is tuned for a 42 px husk and leaves the boss
## embedded in the slab. Bosses also need the widest clear lane in the room,
## because their attack reach is ~110 px and a deck in front of them makes the
## fight unreadable.
static func boss_spawn(rect: Rect2, platforms: Array) -> Vector2:
	var centre := rect.get_center().x
	var best := centre
	var best_gap := -1.0
	for candidate in [centre, rect.position.x + rect.size.x * 0.25, rect.position.x + rect.size.x * 0.75]:
		var gap := 1.0e9
		for entry in platforms:
			var pr: Rect2 = entry
			gap = minf(gap, absf(candidate - pr.get_center().x))
		if gap > best_gap:
			best_gap = gap
			best = candidate
	return Vector2(best, rect.position.y - 44.0)


static func _clear_y(x: float, y: float, platforms: Array, half: float) -> Vector2:
	# WHY: decks hang 64-96 px over the slab, and a body lifted only SPAWN_LIFT
	# from the slab pokes through them. The enemy then starts embedded in stone
	# and never lands. Spawn on top instead - and pull x back over the platform
	# it was lifted onto, or the body is left standing in the air beside it
	# (the ±SPAWN_RADIUS reach test is wider than the platform itself).
	# Five passes settle the stacked decks (shaft has five levels).
	if half <= 0.0:
		return Vector2(x, y)
	for _pass in 5:
		for pr in platforms:
			var r: Rect2 = pr
			if x < r.position.x - SPAWN_RADIUS or x > r.end.x + SPAWN_RADIUS:
				continue
			if y + half > r.position.y and y - half < r.end.y:
				y = r.position.y - SPAWN_LIFT
				if r.size.x > SPAWN_RADIUS * 2.0:
					x = clampf(x, r.position.x + SPAWN_RADIUS, r.end.x - SPAWN_RADIUS)
				else:
					x = r.get_center().x
	return Vector2(x, y)


static func _plan_enemies(cfg: Dictionary, room_count: int, boss: String) -> Array:
	var plan: Array = []
	for i in room_count:
		plan.append([])
	if not boss.is_empty():
		plan[room_count - 1].append([boss, 1])
		return plan

	var middle: Array = []
	for i in range(1, room_count - 1):
		middle.append(i)
	if middle.is_empty():
		# Two-room floors have no middle; the exit room carries the fight.
		middle.append(room_count - 1)

	var flat: Array = []
	for group in cfg.get("enemies", []):
		for i in int(group[1]):
			flat.append(str(group[0]))
	for i in flat.size():
		plan[middle[i % middle.size()]].append(flat[i])

	for i in room_count:
		var merged: Array = []
		for kind in plan[i]:
			var found := false
			for group in merged:
				if group[0] == kind:
					group[1] += 1
					found = true
			if not found:
				merged.append([kind, 1])
		plan[i] = merged
	return plan


# --- reachability -----------------------------------------------------------

## Can a player standing on `from` reach `to`?
## One-way decks are climbed from below, so the same rule applies to both kinds;
## the difference is only whether you can fall through (you cannot, you land).
static func _reach(from: Rect2, to: Rect2) -> bool:
	var up := from.position.y - to.position.y
	if up > MAX_UP:
		return false
	var dx := maxf(0.0, maxf(to.position.x - from.end.x, from.position.x - to.end.x))
	# Climbing costs horizontal range: the arc is only 110 px up when it is
	# almost vertical, so a high platform must sit nearly on top of its parent.
	var budget := minf(MAX_SPAN, JUMP_LENGTH * (1.0 - 0.45 * maxf(up, 0.0) / JUMP_HEIGHT))
	return dx <= budget


## Every surface on the floor, as Rect2 tops.
static func _surfaces(rooms: Array) -> Array:
	var out: Array = []
	for room in rooms:
		for ground in (room["ground"] as Array):
			out.append(ground)
		for pr in (room["platforms"] as Array):
			out.append(pr)
	return out


## BFS from the start surface to the surface that holds the exit. Reports how
## many surfaces are reachable so a warning names a real number.
static func _verify(rooms: Array, start: Vector2, floor_index := 0, seed_value := 0) -> Dictionary:
	var surfaces := _surfaces(rooms)
	if surfaces.is_empty():
		return {"ok": false, "reached": 0, "total": 0}

	var seed_index := -1
	for i in surfaces.size():
		var r: Rect2 = surfaces[i]
		if start.x >= r.position.x - 40.0 and start.x <= r.end.x + 40.0:
			if absf(r.position.y - (start.y + 44.0)) < 80.0:
				seed_index = i
				break
	if seed_index < 0:
		seed_index = 0

	var reached := {}
	reached[seed_index] = true
	var queue: Array = [seed_index]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		var from: Rect2 = surfaces[current]
		for i in surfaces.size():
			if reached.has(i):
				continue
			if _reach(from, surfaces[i]):
				reached[i] = true
				queue.append(i)

	var ok := true
	var missed := 0
	var names := []
	for ri in rooms.size():
		var room: Dictionary = rooms[ri]
		var slab: Rect2 = room["rect"]
		var found := false
		for i in reached.keys():
			var r: Rect2 = surfaces[i]
			if absf(r.position.y - slab.position.y) < 4.0 and absf(r.position.x - slab.position.x) < 4.0:
				found = true
				break
		if not found:
			ok = false
			missed += 1
			names.append("%d:%s" % [ri, str(room["kind"])])
	if not ok:
		push_warning("LevelGen: floor %d seed %d: %d of %d room slab(s) unreachable: %s"
			% [floor_index, seed_value, missed, rooms.size(), ", ".join(names)])

	# Decks are the whole point of the vertical layer, so they get the same
	# budget check the slabs do. A rung the player cannot climb is a room that
	# cannot be read, and an unreachable perch is an enemy nobody can kill.
	var lost_decks := 0
	for ri in rooms.size():
		for pr in (rooms[ri]["platforms"] as Array):
			var deck: Rect2 = pr
			var seen := false
			for i in surfaces.size():
				if reached.has(i) and (surfaces[i] as Rect2) == deck:
					seen = true
					break
			if not seen:
				lost_decks += 1
	if lost_decks > 0:
		push_warning("LevelGen: floor %d seed %d: %d deck(s) outside the jump budget"
			% [floor_index, seed_value, lost_decks])
	return {"ok": ok, "reached": reached.size(), "total": surfaces.size(),
		"decks": lost_decks}
