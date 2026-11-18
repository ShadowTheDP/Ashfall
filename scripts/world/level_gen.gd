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
## Width of the walkable slot a pillar must leave on the approach side. The
## player body is 28 px wide; 46 leaves room to line up a jump inside it.
const SLOT := 46.0
## Vertical air a generated surface must leave over/under another overlapping
## surface before anything may spawn on it. NOTE: this is measured TOP to TOP,
## so a 26 px mass one tier (92) up leaves 66 px of real air - which is exactly
## what SPAWN_LIFT (38, plus half the tallest 50 px body) was tuned against.
## The number is deliberately not "92 - 26": comparing bottom edges instead
## would reject every authored mass one tier above a deck, and the tight case is
## already proven safe by the audits' spawn checks.
const BODY_HEADROOM := 72.0
const GAP_MAX := 190.0
## Centre of a spawn point above its surface. WHY 38 and not 42: the tightest
## ceiling over any spawn surface is a 26 px solid mass exactly TIER (92) above
## it, so lift + 25 (half of the tallest 50 px body) has to stay under 66.
const SPAWN_LIFT := 38.0
## Widest body in data/enemies.json (the Warden). A spawn point must clear this
## much on both sides, or the enemy is born inside the platform above it.
const SPAWN_RADIUS := 20.0
## Matches tests/audit_a3.gd FALLBACK_BOX.y and tests/audit_v1.gd's body half.
## Keep them equal: this is the width of the body a spawn point must clear.
const SPAWN_HALF_MIN := 25.0
const DECK_H := 13.0

const KIND_WEIGHT := {"gate": 1.2, "hall": 1.4, "shaft": 0.8, "vault": 1.0, "bridge": 0.9, "well": 0.9}
const KIND_MIN := {"gate": 420.0, "hall": 460.0, "shaft": 280.0, "vault": 380.0, "bridge": 440.0, "well": 400.0}
# --- The beat sheet ---------------------------------------------------------
#
# A floor is not "N random rooms": data/floors.json gives it a BEAT SHEET, the
# Ashfall equivalent of the concept graph in a hand-authored roguelite. Each
# beat is a ROLE with a fixed job, and the role decides which kinds of room may
# fill it and how much of the floor's enemy budget it deserves:
#
#   entry     the first room. Always empty: the player has to read the floor
#             before anything can touch them.
#   combat    the bread: a fight with a real floor to move on.
#   climb     a vertical room, light on enemies: the breather between fights.
#   treasure  a vault-shaped room. The cache on its high route is the reward.
#   elite     the peak: heavier bodies, and the room that carries a boss floor's
#             approach.
#   exit      the last room, where the gate is.
#
# This is what makes two seeds of the same floor feel like the same PLACE with a
# different arrangement, instead of two unrelated corridors.
const ROLE_KINDS := {
	"entry": ["gate"],
	"combat": ["gate", "hall", "bridge"],
	"climb": ["shaft", "well"],
	"treasure": ["vault", "bridge"],
	"elite": ["hall", "vault"],
	"exit": ["hall"],
}
## How much of the enemy budget a room role asks for. 0 means "never".
const ROLE_ENEMY_WEIGHT := {
	"entry": 0.0, "combat": 1.0, "climb": 0.45, "treasure": 0.7, "elite": 1.45, "exit": 1.0,
}
## Bodies this heavy count double: a room should not receive two of them just
## because the budget allowed it.
const HEAVY_KINDS := ["bulwark", "charger", "warden"]


## A layout that failed its own verification is not a warning, it is a dead
## floor: an enemy on an unreachable deck means enemies_remaining() never hits
## zero, the door never opens, and the player is stuck with no exit. `_verify`
## used to only push_warning(), and nothing at runtime read its result. Retry
## with a perturbed seed instead - the generator is deterministic per seed, so
## the retry is deterministic too.
const MAX_GENERATE_ATTEMPTS := 8


static func generate(floor_index: int, seed_value: int) -> Dictionary:
	var data := _generate_once(floor_index, seed_value)
	for attempt in range(1, MAX_GENERATE_ATTEMPTS):
		var reach: Dictionary = data.get("reachable", {})
		if bool(reach.get("ok", true)) and int(reach.get("decks", 0)) == 0:
			if attempt > 1:
				push_warning("LevelGen: floor %d seed %d needed %d attempt(s) to verify"
					% [floor_index, seed_value, attempt - 1])
			return data
		data = _generate_once(floor_index, seed_value + attempt * 104729)
	var reach_last: Dictionary = data.get("reachable", {})
	if not bool(reach_last.get("ok", true)) or int(reach_last.get("decks", 0)) != 0:
		push_error("LevelGen: floor %d seed %d could not produce a verified layout in %d tries"
			% [floor_index, seed_value, MAX_GENERATE_ATTEMPTS])
	return data


static func _generate_once(floor_index: int, seed_value: int) -> Dictionary:
	var cfg := _floor_config(floor_index)
	var rng := RandomNumberGenerator.new()
	# The floor index is folded in so one run seed does not produce five
	# identical room orders; (floor, seed) is still fully deterministic.
	rng.seed = seed_value * 7919 + floor_index * 131 + 17
	var room_count := maxi(1, int(cfg.get("rooms", 3)))
	var target := float(cfg.get("width", 3200.0))
	var boss := str(cfg.get("boss", ""))
	assert(room_count >= 1, "a floor needs at least one room")

	var beat := _pick_kinds(room_count, rng, floor_index)
	var roles: Array = beat["roles"]
	var kinds: Array = beat["kinds"]

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
		# Capped at MAX_UP so the continuous bottom ledge is always a valid way up:
		# a higher slab would be out of reach from the ledge, and a fall would be
		# final. Vertical depth comes from the room templates (2-5 tiers of decks),
		# the gallery, the ladders and the annex chambers - not from stacking the
		# slabs themselves, which is what makes the ledge a guaranteed route.
		offsets.append(clampf(previous + rng.randf_range(-96.0, 100.0), 0.0, MAX_UP))

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

	var plan := _plan_enemies(cfg, roles, widths, boss)

	var rooms: Array = []
	var cursor := 0.0
	for i in room_count:
		var w: float = widths[i]
		assert(w > 0.0, "room width must be positive")
		# Vertical variety: a room sits 0-100 px above the bottom ledge, so the
		# floor reads as terraced ground rather than a flat strip. The slab grows
		# downward by the same amount, so its face still reaches the ledge.
		var offset: float = offsets[i]
		var rect := Rect2(cursor, BASE_Y - offset, w, SLAB_H + offset)
		var built := _build_room(kinds[i], rect, rng)
		var gap_after: float = gaps[i] if i < gaps.size() else 0.0
		# Ledge first: the ground array is draw order, deepest face first.
		var ground: Array = [Rect2(cursor, BASE_Y, w + gap_after, LEDGE_H), rect]
		var room := {
			"rect": rect,
			"kind": kinds[i],
			"role": roles[i],
			"template": str(built.get("id", kinds[i])),
			"platforms": built["platforms"],
			"oneway": built["oneway"],
			"ground": ground,
			"enemies": plan[i],
		}
		rooms.append(room)
		cursor += w + gap_after

	# Order matters, and it is pillars FIRST. A pillar raises a 126-176 px wall
	# plus a step deck in the gap; a gallery connector placed before it landed
	# 14 px above the pillar top and left the boss lane spawning with its head in
	# stone (audit_v1, floor 2 seed 37). The macro layer only ever ADDS surfaces,
	# so it has to be the part that knows what is already there.
	# Spawns stay last: they are derived from the FINAL surface list.
	_place_pillars(rooms, rng)
	_link_gallery(rooms, rng)
	_stack_ladders(rooms, rng)
	# Optional chambers above the main route. They carry the biggest cache on the
	# floor, so the upper route is worth the climb instead of merely possible.
	_annexes(rooms, rng)

	# Macro connectors can reopen cross-room cracks after template sealing.
	var platforms: Array = []
	var flags: Array = []
	for room in rooms:
		platforms.append_array(room["platforms"])
		flags.append_array(room["oneway"])
	_close_narrow_holes(platforms, flags)
	var platform_index := 0
	for room in rooms:
		var count: int = room["platforms"].size()
		room["platforms"] = platforms.slice(platform_index, platform_index + count)
		platform_index += count

	# WHY after the pillars: _place_pillars adds a step deck and a pillar to the
	# room it leaves, and a spawn point computed before that does not know they
	# exist - the enemy is then born inside the step deck. Spawns are derived
	# from the final surface list, so the last mutation has to come first.
	for i in room_count:
		var annex_skip: Array = []
		if rooms[i].has("annex"):
			annex_skip = [rooms[i]["annex"], rooms[i]["annex_landing"]] + (rooms[i]["annex_walls"] as Array)
		rooms[i]["spawns"] = _spawns_for(rooms[i]["rect"], rooms[i]["platforms"],
			_spawn_half(plan[i]), annex_skip)

	var caches := _caches(rooms, floor_index, rng)
	# Annex chambers, so the level can draw them as destinations rather than as
	# two more planks. A parallel list instead of a tag on every surface: there
	# are at most two per floor.
	var annex_floors: Array = []
	for room in rooms:
		if room.has("annex"):
			annex_floors.append(room["annex"] as Rect2)
			if room.has("annex_landing"):
				annex_floors.append(room["annex_landing"] as Rect2)

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
		"caches": caches,
		"annex_floors": annex_floors,
		"reachable": _verify(rooms, Vector2(first.position.x + 70.0, first.position.y - 44.0), floor_index, seed_value),
	}


# --- room construction ------------------------------------------------------

## Returns { "platforms": Array[Rect2], "oneway": Array[bool], "id": String }.
## Two parallel arrays instead of a dictionary per surface: the geometry is
## what every consumer (collision, BFS, spawn clearance) needs, and a bare
## Rect2 cannot disagree with itself about its own rect.
##
## The layout itself is authored content (data/rooms.json), not generated: the
## generator chooses WHICH authored tile a room gets, never what is inside it.
## That is the whole difference between "six random shapes" and a place the
## player can learn. _build_builtin() is the fallback for a missing data file
## and the reference layout each kind was designed around.
static func _build_room(kind: String, rect: Rect2, rng: RandomNumberGenerator) -> Dictionary:
	var tpl := _pick_template(kind, rect.size.x, rng)
	if not tpl.is_empty():
		var built := _build_template(tpl, rect)
		built["id"] = str(tpl.get("id", kind))
		return built
	var built := _build_builtin(kind, rect)
	built["id"] = kind
	return built


## One authored tile for this room, filtered by the room's width so a narrow
## room never receives a layout its budget cannot hold.
static func _pick_template(kind: String, width: float, rng: RandomNumberGenerator) -> Dictionary:
	var entry: Dictionary = _rooms_table().get(kind, {})
	var list: Array = entry.get("templates", [])
	var fits: Array = []
	for tpl in list:
		if float((tpl as Dictionary).get("min_width", 0.0)) <= width:
			fits.append(tpl)
	if fits.is_empty():
		return {}
	return fits[rng.randi_range(0, fits.size() - 1)]


## parts: ["d", x, tier, w, oneway] deck | ["m", x, tier, w, h] solid mass.
## x and w are fractions of the room width, tier is a multiple of TIER.
static func _build_template(tpl: Dictionary, rect: Rect2) -> Dictionary:
	var out: Array = []
	var flags: Array = []
	for part in (tpl.get("parts", []) as Array):
		var spec: Array = part
		if spec.size() < 5:
			continue
		var tag := str(spec[0])
		var x := rect.position.x + rect.size.x * float(spec[1])
		var w := rect.size.x * float(spec[3])
		var y := rect.position.y - float(spec[2]) * TIER
		if tag == "m":
			out.append(Rect2(x, y, w, float(spec[4])))
			flags.append(false)
		else:
			var oneway := int(spec[4]) != 0
			out.append(Rect2(x, y, w, DECK_H if oneway else 26.0))
			flags.append(oneway)
	_close_narrow_holes(out, flags)
	return {"platforms": out, "oneway": flags}


## Same-height cracks wedge a capsule between two wall normals, with no floor
## contact to jump from. Extend only one-way decks; solid walls keep their footprint.
static func _close_narrow_holes(platforms: Array, flags: Array) -> void:
	for i in platforms.size():
		if not bool(flags[i]):
			continue
		var a: Rect2 = platforms[i]
		for j in platforms.size():
			if i == j:
				continue
			var b: Rect2 = platforms[j]
			if absf(a.position.y - b.position.y) > 1.0:
				continue
			var right_gap := b.position.x - a.end.x
			var left_gap := a.position.x - b.end.x
			if right_gap > 0.0 and right_gap < SLOT + 12.0:
				a.size.x += right_gap
			elif left_gap > 0.0 and left_gap < SLOT + 12.0:
				a.position.x -= left_gap
				a.size.x += left_gap
			platforms[i] = a


static func _build_builtin(kind: String, rect: Rect2) -> Dictionary:
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
	# The builtin layouts are the fallback when data/rooms.json is missing, and
	# they contain the same same-tier cracks the authored templates do (a 17 px
	# crack at W=420 in gate, ~37 px between hall capitals). The invariant is
	# about the generator's output, not about one code path, so it is closed here
	# too - otherwise a missing data file silently restores the trap.
	_close_narrow_holes(out, flags)
	return {"platforms": out, "oneway": flags}


# --- macro layer: one continuous upper route --------------------------------
#
# The rooms are individually verified puzzles; on their own they read as a row
# of set pieces rather than a place. These three passes give the floor a
# SECOND, continuous route above the ledge and make the climb optional instead
# of mandatory:
#
#   _link_gallery  bridges the gaps at the height of the rooms' own upper
#                  decks, so the gallery is one line rather than six islands.
#   _stack_ladders puts a ladder of rungs at a few gaps so the player can get
#                  up (and back down) anywhere, not only through a shaft room.
#   _caches        puts the reward on the high route.

## Best deck in `room` within `tolerance` px of `want_y`, nearest to x.
static func _deck_near(room: Dictionary, x: float, want_y: float, tolerance: float) -> Rect2:
	var best := Rect2()
	var best_score := 1.0e9
	for entry in (room["platforms"] as Array):
		var r: Rect2 = entry
		if absf(r.position.y - want_y) > tolerance:
			continue
		# A one-way deck is the natural gallery floor, but a solid mass top is a
		# legal surface too (the verification pass treats every surface the same
		# way). Refusing the solid ones left a third of the gaps unbridged, and
		# the upper route then read as three separate perches instead of a route.

		var score := absf(clampf(x, r.position.x, r.end.x) - x)
		if score < best_score:
			best_score = score
			best = r
	return best


## A connector is kept only if the SAME predicate the BFS uses accepts the step
## from both neighbours. Generating then verifying is what stops this pass from
## ever adding an unreachable perch (which audit_v1 would flag as a softlock).
static func _link_gallery(rooms: Array, rng: RandomNumberGenerator) -> void:
	if rooms.size() < 2:
		return
	for i in range(1, rooms.size()):
		var prev: Rect2 = rooms[i - 1]["rect"]
		var here: Rect2 = rooms[i]["rect"]
		var gap := here.position.x - prev.end.x
		if gap < 60.0 or gap > GAP_MAX + 30.0:
			continue
		# Each neighbour is matched on its OWN upper-deck line (slab - TIER*2).
		# Matching both against one shared height looked right and produced a
		# link on only ~1 gap in 6: adjacent slabs differ by up to 96 px, so one
		# of the two decks was always 30+ px off the queried line and the pair
		# was thrown away. The connector then rides the HIGHER of the two decks;
		# climbing to it from the lower one is at most 96 px, inside MAX_UP.
		var a := _deck_near(rooms[i - 1], prev.end.x - 20.0, prev.position.y - TIER * 2.0, 30.0)
		var b := _deck_near(rooms[i], here.position.x + 20.0, here.position.y - TIER * 2.0, 30.0)
		if a.size.x <= 0.0 or b.size.x <= 0.0:
			continue
		var y := minf(a.position.y, b.position.y)
		var conn := Rect2(prev.end.x + 4.0, y, maxf(40.0, gap - 8.0), DECK_H)
		# Both directions: up from each deck onto the connector, and the drop
		# back down. _reach() already treats "down" as free.
		if not (_reach(a, conn) and _reach(b, conn)):
			continue
		if not (_reach(conn, a) and _reach(conn, b)):
			continue
		if not _headroom(conn, [rooms[i - 1], rooms[i]]):
			continue
		(rooms[i - 1]["platforms"] as Array).append(conn)
		(rooms[i - 1]["oneway"] as Array).append(true)
		rooms[i - 1]["gallery"] = true
		rooms[i]["gallery"] = true


## Is any solid mass already standing between x0 and x1? Used to keep a ladder
## out of a gap that already carries a pillar.
static func _gap_has_solid(room: Dictionary, x0: float, x1: float) -> bool:
	for index in (room["platforms"] as Array).size():
		if bool((room["oneway"] as Array)[index]):
			continue
		var r: Rect2 = (room["platforms"] as Array)[index]
		if r.end.x > x0 and r.position.x < x1:
			return true
	return false


## A connector must not become a ceiling. The two neighbours can carry surfaces
## at any height (their own TIER decks, masses, a pillar step), and a connector
## that lands 14 px above one of them leaves a body spawning there with its head
## in stone - audit_v1 reports that as a softlock. Require a real body's worth of
## air above and below every surface it overlaps horizontally.
static func _headroom(conn: Rect2, neighbours: Array) -> bool:
	for room in neighbours:
		for entry in (room["platforms"] as Array):
			var r: Rect2 = entry
			if r.position.x > conn.end.x or r.end.x < conn.position.x:
				continue
			var gap := absf(r.position.y - conn.position.y)
			if gap < BODY_HEADROOM:
				return false
	return true


## A ladder of pass-through rungs in the gap before rooms with no pillar. Every
## rung is TIER above the last, i.e. the same 92 px the room decks use, so the
## climb is guaranteed to be inside MAX_UP (100) without any per-rung solving.
static func _stack_ladders(rooms: Array, rng: RandomNumberGenerator) -> void:
	var made := 0
	for i in range(1, rooms.size()):
		# Two ladders a floor is enough to make the climb a choice everywhere;
		# more turns every gap into scaffolding.
		if made >= 2:
			return
		if rng.randf() > 0.5:
			continue
		var prev: Rect2 = rooms[i - 1]["rect"]
		var here: Rect2 = rooms[i]["rect"]
		var gap := here.position.x - prev.end.x
		if gap < 96.0:
			continue
		# A connector already bridges this gap at TIER*2; a ladder under it puts
		# a rung SPAWN_LIFT below the connector floor, and a body spawning on the
		# connector is then born with its head inside stone (audit_a3 flags it).
		if bool(rooms[i - 1].get("gallery", false)):
			continue
		# A pillar already stands in this gap, and its step deck lies at exactly
		# the first rung's height. Two ladders is not worth a wall of stone.
		if _gap_has_solid(rooms[i - 1], prev.end.x - 8.0, prev.end.x + gap):
			continue
		var rung_w := clampf(gap * 0.55, 70.0, 110.0)
		var left := prev.end.x + (gap - rung_w) * 0.5
		var kept := true
		var rungs: Array = []
		for step in 3:
			var rung := Rect2(left, BASE_Y - TIER * float(step + 1), rung_w, DECK_H)
			if not _headroom(rung, [rooms[i - 1], rooms[i]]):
				kept = false
				break
			rungs.append(rung)
		if not kept:
			continue
		for rung in rungs:
			(rooms[i - 1]["platforms"] as Array).append(rung)
			(rooms[i - 1]["oneway"] as Array).append(true)
		made += 1


## Optional chambers above the main route: the reason to climb.
##
## The gallery connects rooms at TIER*2, which makes the upper route CONTINUOUS
## but not DESTINED - it led from one room to the next and nowhere else. An
## annex is a real destination: a one-way chamber two tiers above the room's own
## highest deck, reached by one extra rung, holding the floor's biggest cache.
## Everything is gated by the same predicates the BFS uses, and the rung lands on
## the room's existing top deck, so the climb continues the route the player is
## already on instead of adding scaffolding beside it.
static func _annexes(rooms: Array, rng: RandomNumberGenerator) -> void:
	var want := 2 if rooms.size() >= 5 else 1
	var made := 0
	# Deterministic order: the seeded rng picks which rooms, never the frame.
	var order: Array = []
	for i in range(1, rooms.size()):
		order.append(i)
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = order[i]
		order[i] = order[j]
		order[j] = tmp
	for index in order:
		if made >= want:
			return
		if _annex(rooms[index]):
			made += 1


static func _annex(room: Dictionary) -> bool:
	var rect: Rect2 = room["rect"]
	var platforms: Array = room["platforms"]
	var flags: Array = room["oneway"]
	# The room's own highest surface is the launch pad.
	var top_y := rect.position.y
	var top := Rect2()
	for entry in platforms:
		var r: Rect2 = entry
		if r.position.y < top_y:
			top_y = r.position.y
			top = r
	if top.size.x <= 0.0:
		return false
	# Two more tiers of climb on top of the room's own: at most TIER*5 above the
	# slab, which is still inside the camera's 558 px of visible height.
	if top_y < rect.position.y - TIER * 3.0:
		return false
	var landing_y := top_y - TIER
	var floor_y := top_y - TIER * 2.0
	var aw := clampf(rect.size.x * 0.38, 150.0, 240.0)
	var cx := clampf(top.get_center().x, rect.position.x + aw * 0.5 + 16.0, rect.end.x - aw * 0.5 - 16.0)
	var landing := Rect2(cx - 45.0, landing_y, 90.0, DECK_H)
	var chamber := Rect2(cx - aw * 0.5, floor_y, aw, DECK_H)
	# One rung, then the chamber. Both must be inside the jump budget from the
	# surface below and must leave a body's worth of air around everything the
	# room already owns - the same rules the gallery connector obeys.
	if not _reach(top, landing):
		return false
	if not _reach(landing, chamber):
		return false
	if not _headroom(landing, [room]) or not _headroom(chamber, [room]):
		return false
	platforms.append(landing)
	flags.append(true)
	platforms.append(chamber)
	flags.append(true)
	# Low walls: they make the chamber read as a room rather than a plank, and
	# they keep a body from walking straight off the far edge.
	var walls: Array = []
	for side in [-1.0, 1.0]:
		var wx: float = cx + float(side) * (aw * 0.5) - 7.0
		var wall := Rect2(wx, floor_y - 54.0, 14.0, 54.0)
		walls.append(wall)
		platforms.append(wall)
		flags.append(false)
	room["annex"] = chamber
	room["annex_landing"] = landing
	# The short walls are standable too, and a body born on a 14 px cap is the
	# kind of spawn the audits exist to catch. Spawns skip all three. The SAME
	# rects are recorded here and appended above: computing them twice put the
	# skip list 7 px off the drawn wall, so the exclusion silently missed.
	room["annex_walls"] = walls
	return true


## Cell caches on the high route. Chosen from the decks the BFS can already
## reach at least two tiers above their room's slab, so a cache is always
## "optional route, real reward" and never a collectible in a wall.
##
## Deterministic per (floor, seed): the trim used to be a global-RNG shuffle, so
## the same seed placed its caches differently on every load - which contradicts
## the whole "generated from (floor, seed)" contract and made a seeded replay
## unreproducible. The slice is now taken from a seeded rng instead.
static func _caches(rooms: Array, floor_index: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	# Annex caches are kept first and unconditionally: the annex exists to reward
	# the climb, and the trim below used to be able to drop exactly that one.
	var annex_caches: Array = []
	var value := 4 + floor_index * 2
	for room in rooms:
		var slab: Rect2 = room["rect"]
		var best := Rect2()
		for entry in (room["platforms"] as Array):
			var r: Rect2 = entry
			if r.size.x < 60.0 or r.size.y > DECK_H + 0.5:
				continue
			if r.position.y > slab.position.y - TIER * 2.0 + 6.0:
				continue
			if r.position.y < best.position.y or best.size.x <= 0.0:
				best = r
		if best.size.x <= 0.0:
			continue
		# An annex is the floor's real detour, so its cache pays double. Compared
		# by position: the chamber rect is stored on the room, and Variant equality
		# on two Rect2s is not something to depend on.
		var worth := value
		var in_annex := false
		if room.has("annex"):
			var annex: Rect2 = room["annex"]
			if absf(best.position.y - annex.position.y) < 1.0 and absf(best.position.x - annex.position.x) < 1.0:
				worth = value * 2
				in_annex = true
		var entry_cache := {
			"pos": Vector2(best.get_center().x, best.position.y - 12.0),
			"value": worth,
		}
		if in_annex:
			annex_caches.append(entry_cache)
		else:
			out.append(entry_cache)
	# Two annex caches on a 5+ room floor is the ceiling: more than that and the
	# high route stops being the exception.
	if annex_caches.size() > 2:
		annex_caches = annex_caches.slice(0, 2)
	out = annex_caches + out
	if out.size() > 3:
		var keep: Array = []
		# Every annex cache is kept; the rest is a seeded pick from the others.
		var fixed := mini(annex_caches.size(), 3)
		for i in fixed:
			keep.append(i)
		while keep.size() < 3:
			var pick := rng.randi_range(fixed, out.size() - 1)
			if not keep.has(pick):
				keep.append(pick)
		keep.sort()
		var trimmed: Array = []
		for index in keep:
			trimmed.append(out[index])
		out = trimmed
	return out


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

		# The slot between the pillar and the next room must fit a body, or the
		# player lands in a 23 px crack after climbing over and can never reach
		# the next slab (audit_a3 walk cases caught it). Leaving SLOT on the
		# approach side and letting the pillar sit FLUSH against the next room
		# turns that crack into the landing pad it was meant to be.
		var pw := clampf(gap_width - SLOT, 56.0, 96.0)
		if gap_width - pw < SLOT - 4.0:
			continue
		# Capped at 176: from the step deck at TIER (92) the climb to the top is
		# 84 px, inside MAX_UP (100). A taller pillar could not be climbed at
		# all and would wall the floor off.
		var height := lerpf(126.0, 176.0, rng.randf())
		var left := gap_start + (gap_width - pw)
		# The step deck must TOUCH the pillar. With a gap between them the
		# player drops into it, and from the ledge the pillar top is out of
		# reach (apex is 110, the top is 126-176 up) - a guaranteed softlock.
		var step_w := 120.0
		# Anchored to the LEDGE, not to the room: this deck exists so a player who
		# fell to the bottom can get back up, so it has to be within one jump of
		# BASE_Y. (A room-relative anchor would put it above MAX_UP from the ledge
		# and the fall would be final.) When it overlaps an authored mass the mass
		# is drawn over it - see Level._draw().
		(rooms[i - 1]["platforms"] as Array).append(
			Rect2(left - step_w, BASE_Y - TIER, step_w, DECK_H))
		(rooms[i - 1]["oneway"] as Array).append(true)
		(rooms[i - 1]["platforms"] as Array).append(
			Rect2(left, BASE_Y - height, pw, height + 40.0))
		(rooms[i - 1]["oneway"] as Array).append(false)


# --- layout helpers ---------------------------------------------------------

static func _pick_kinds(count: int, rng: RandomNumberGenerator, floor_index := 0) -> Dictionary:
	var cfg := _floor_config(floor_index)
	var beats: Array = cfg.get("beats", [])
	var roles: Array = []
	for i in count:
		if i < beats.size():
			roles.append(str(beats[i]))
		else:
			roles.append("combat")
	if count == 1:
		# A single room is the boss arena: wide, open, and it owns the gate.
		roles = ["exit"]
	# The two ends are fixed whatever the data says: the first room is where the
	# player lands and the last one holds the gate.
	roles[0] = "entry"
	roles[count - 1] = "exit"

	var kinds: Array = []
	var previous := ""
	for i in count:
		var role := str(roles[i])
		var pool: Array = ROLE_KINDS.get(role, ["gate"])
		# No two rooms in a row may share a layout kind: a floor that alternates
		# gate/gate reads as one long corridor however different the tiles are.
		var fits: Array = []
		for kind in pool:
			if kind != previous:
				fits.append(kind)
		if fits.is_empty():
			fits = pool
		var pick := str(fits[rng.randi_range(0, fits.size() - 1)])
		kinds.append(pick)
		previous = pick
	return {"kinds": kinds, "roles": roles}


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


static func _rooms_table() -> Dictionary:
	var node := Engine.get_main_loop() as SceneTree
	if node == null:
		return {}
	var data := node.root.get_node_or_null("Data")
	if data != null and "rooms" in data:
		return data.rooms
	return {}


# --- spawns -----------------------------------------------------------------

## Spawn points live on every surface, not just the slab, so upper decks are
## populated and the player has a reason to climb.
## Spawn points live on every surface, not just the slab, so upper decks are
## populated and the player has a reason to climb. The annex chamber and its
## landing are excluded: the annex is the reward for the climb, and a body up
## there would turn an optional detour into a mandatory one (the gate needs
## every body dead).
static func _spawns_for(rect: Rect2, platforms: Array, half: float, skip: Array = []) -> Array:
	# The skip list is removed from the surface set used to place and settle
	# bodies, not only from the loop below: _settle() lifts a candidate onto
	# whatever surface is above it, so a lower point near the annex column was
	# being re-anchored INTO the chamber and the exclusion was cosmetic.
	var usable: Array = []
	for pr in platforms:
		if not _in_list(pr, skip):
			usable.append(pr)
	var out: Array = []
	var span := maxf(60.0, rect.size.x - 80.0)
	for i in 4:
		var t := fposmod(float(i) * MathArt.INV_PHI, 1.0)
		var x := rect.position.x + 40.0 + span * t
		_offer(out, x, rect.position.y - SPAWN_LIFT, usable, half)
	for pr in usable:
		var r: Rect2 = pr
		_offer(out, r.get_center().x, r.position.y - SPAWN_LIFT, usable, half)
	# A room with every point rejected (a pillar filled the gap) still needs one
	# landing pad: the slab centre, lifted, is the widest clear lane there is.
	if out.is_empty():
		_offer(out, rect.get_center().x, rect.position.y - SPAWN_LIFT, usable, half)
	if out.is_empty():
		out.append(Vector2(rect.get_center().x, rect.position.y - SPAWN_LIFT))
	return out


## What the generator promises about a room it filled with an authored tile:
## every surface within one jump of the surface it is climbed from, no surface
## less than a body's worth of air over another, and the annex reserved for the
## cache.
static func _in_list(r: Rect2, list: Array) -> bool:
	for entry in list:
		var other: Rect2 = entry
		if absf(other.position.x - r.position.x) < 0.5 and absf(other.position.y - r.position.y) < 0.5:
			return true
	return false


## Settle one candidate and only keep it if the body is provably out of stone.
## The old code trusted _settle() unconditionally; once the macro layer added
## surfaces at arbitrary heights, a point could be re-anchored INSIDE a pillar
## and the audit would find a body born in a wall.
static func _offer(out: Array, x: float, y: float, platforms: Array, half: float) -> void:
	var p := _settle(x, y, platforms, half)
	if _inside_any(p, platforms, half):
		return
	out.append(p)


## Does the box a body would occupy at `p` intersect terrain? The same rule the
## audits use: half-width SPAWN_RADIUS, half-height from the tallest body.
static func _inside_any(p: Vector2, platforms: Array, half: float) -> bool:
	for pr in platforms:
		var r: Rect2 = pr
		if p.x + SPAWN_RADIUS < r.position.x or p.x - SPAWN_RADIUS > r.end.x:
			continue
		if p.y + half > r.position.y and p.y - half < r.end.y:
			return true
	return false


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
	# The floor of 25 px is the audits' FALLBACK_BOX.y, and it has to be the
	# SAME number: generation used the room's own tallest body (21 px for a
	# room of grunts) while the audits check every point against 25 px, so a
	# point 24 px under a deck passed generation and failed the audit.
	var half := SPAWN_HALF_MIN
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


static func _plan_enemies(cfg: Dictionary, roles: Array, widths: Array, boss: String) -> Array:
	var n := roles.size()
	var plan: Array = []
	for i in n:
		plan.append([])
	var boss_room := -1
	if not boss.is_empty():
		boss_room = n - 1

	# The flat list from data/floors.json is the floor's TOTAL; this function only
	# decides where each body goes. Totals are what the audits assert, so nothing
	# here may add or drop one.
	var flat: Array = []
	for group in cfg.get("enemies", []):
		for i in int(group[1]):
			flat.append(str(group[0]))
	# Heaviest first: the elite rooms fill before the climbing rooms do, so a
	# bulwark lands where there is floor to fight it on.
	flat.sort_custom(func(a, b): return _enemy_cost(str(a)) > _enemy_cost(str(b)))

	# Which rooms may receive enemies. The entry room is always excluded (the
	# player has to be able to read the floor) and so is the boss room.
	var slots: Array = []
	for i in n:
		if i == boss_room:
			continue
		var weight := float(ROLE_ENEMY_WEIGHT.get(str(roles[i]), 1.0))
		if weight <= 0.0:
			continue
		slots.append({"room": i, "w": weight, "count": 0, "cap": 0})
	if slots.is_empty():
		# Every room refused the budget (a one-room floor). Fall back to the last.
		slots.append({"room": maxi(0, n - 1), "w": 1.0, "count": 0, "cap": 0})

	var total := 0.0
	for slot in slots:
		total += float(slot["w"]) * float(widths[int(slot["room"])])
	for slot in slots:
		var share := float(slot["w"]) * float(widths[int(slot["room"])]) / maxf(total, 1.0)
		slot["cap"] = maxi(1, int(round(float(flat.size()) * share)))

	for kind in flat:
		var pick := -1
		var best := -1.0
		for si in slots.size():
			var slot: Dictionary = slots[si]
			if int(slot["count"]) >= int(slot["cap"]):
				continue
			# One heavy body per room: two bulwarks in one room is not a harder
			# fight, it is an unreadable one.
			if kind in HEAVY_KINDS and _has_kind(plan[int(slot["room"])], kind):
				continue
			var score := float(slot["w"]) / float(int(slot["count"]) + 1)
			if score > best:
				best = score
				pick = si
		if pick < 0:
			# Every room is at capacity: the least-overfull room takes it.
			for si in slots.size():
				var slot: Dictionary = slots[si]
				if pick < 0 or int(slot["count"]) - int(slot["cap"]) < int(slots[pick]["count"]) - int(slots[pick]["cap"]):
					pick = si
		var room_index := int(slots[pick]["room"])
		plan[room_index].append(kind)
		slots[pick]["count"] = int(slots[pick]["count"]) + 1

	for i in n:
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
	if boss_room >= 0:
		plan[boss_room].append([boss, 1])
	return plan


## How much floor a body needs. Used only to decide WHICH room it lands in.
static func _enemy_cost(kind: String) -> float:
	if kind in HEAVY_KINDS:
		return 3.0
	match kind:
		"archer", "spitter", "leaper":
			return 2.0
	return 1.0


static func _has_kind(groups: Array, kind: String) -> bool:
	for entry in groups:
		if str(entry) == kind:
			return true
	return false


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
