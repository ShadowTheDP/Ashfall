class_name LevelGen
extends RefCounted
## Pure-data floor layout. No nodes, no drawing: the layout is generated from a
## seed and validated here, so a room that cannot be crossed never reaches the
## screen.
##
## WHY a continuous bottom ledge (BASE_Y): rooms step 0-90 px above it, so a
## missed jump lands on stone instead of falling out of the world, and every
## step back up is <= 90 px, inside the 100 px climb budget. Rooms read as
## shelves over one shared floor rather than islands over a void.

# Jump budget measured from player.gd: v0=630, gravity_rise=1800 -> 110 px
# apex; ~0.42 s of air at 300 px/s -> ~180 px of travel.
const JUMP_HEIGHT := 110.0
const JUMP_LENGTH := 180.0
const MAX_UP := 100.0
const MAX_SPAN := 170.0

const BASE_Y := 150.0
const LEDGE_H := 300.0
const SLAB_H := 120.0
const GAP_MIN := 40.0
const GAP_MAX := 120.0
const SPAWN_LIFT := 42.0

const KIND_WEIGHT := {"gate": 1.25, "hall": 1.4, "shaft": 0.7, "vault": 0.85}
const KIND_MIN := {"gate": 360.0, "hall": 400.0, "shaft": 240.0, "vault": 280.0}
const MIDDLE_KINDS := ["shaft", "vault", "gate", "hall"]


static func generate(floor_index: int, seed_value: int) -> Dictionary:
	var cfg := _floor_config(floor_index)
	var rng := RandomNumberGenerator.new()
	# The floor index is folded in so one run seed does not produce five
	# identical room orders; (floor, seed) is still fully deterministic.
	rng.seed = seed_value * 7919 + floor_index * 131 + 17
	var room_count := maxi(1, int(cfg.get("rooms", 3)))
	var target := float(cfg.get("width", 2400.0))
	var boss := str(cfg.get("boss", ""))
	assert(room_count >= 1, "a floor needs at least one room")

	var kinds := _pick_kinds(room_count, rng)

	var gaps: Array = []
	var gap_total := 0.0
	for i in room_count - 1:
		# Golden-ratio spacing: gaps vary without ever looking random.
		var t := fposmod(float(i + 1) * MathArt.INV_PHI * MathArt.INV_PHI + rng.randf() * 0.18, 1.0)
		var gap := lerpf(GAP_MIN, GAP_MAX, t)
		gaps.append(gap)
		gap_total += gap
	var widths := _fit_widths(kinds, maxf(720.0, target - gap_total))

	var plan := _plan_enemies(cfg, room_count, boss)

	var rooms: Array = []
	var cursor := 0.0
	for i in room_count:
		var w: float = widths[i]
		assert(w > 0.0, "room width must be positive")
		var offset := 8.0 + 82.0 * fposmod(float(i) * MathArt.INV_PHI + rng.randf() * 0.12, 1.0)
		var rect := Rect2(cursor, BASE_Y - offset, w, SLAB_H)
		var platforms := _platforms_for(kinds[i], rect)
		var gap_after: float = gaps[i] if i < gaps.size() else 0.0
		# Ledge first: the ground array is draw order, deepest face first.
		var ground: Array = [Rect2(cursor, BASE_Y, w + gap_after, LEDGE_H), rect]
		var room := {
			"rect": rect,
			"kind": kinds[i],
			"platforms": platforms,
			"ground": ground,
			"spawns": _spawns_for(rect, platforms),
			"enemies": plan[i],
		}
		rooms.append(room)
		_check_room(i, room)
		cursor += w + gap_after

	var first: Rect2 = rooms[0]["rect"]
	var last: Rect2 = rooms[room_count - 1]["rect"]
	return {
		"seed": seed_value,
		"name": str(cfg.get("name", "FLOOR %d" % floor_index)),
		"palette": int(cfg.get("palette", 0)),
		"width": cursor,
		"rooms": rooms,
		"start": Vector2(first.position.x + 70.0, first.position.y - 44.0),
		"exit": Vector2(last.end.x - 90.0, last.position.y),
		"boss": boss,
	}


# --- data -------------------------------------------------------------------

static func _floor_config(floor_index: int) -> Dictionary:
	var table := _floors()
	var cfg: Dictionary = table.get(str(floor_index), {})
	if cfg.is_empty():
		# Foundation may run the generator before the tables exist (tests).
		push_warning("LevelGen: no floor %d in data/floors.json, using defaults" % floor_index)
		cfg = {
			"name": "FLOOR %d" % floor_index, "rooms": 3, "width": 2400.0,
			"enemies": [["grunt", 3]], "boss": "", "palette": (floor_index - 1) % 5,
		}
	return cfg


static func _floors() -> Dictionary:
	# Looked up through the tree instead of the `Data` global so the generator
	# also runs from a bare --script harness where autoloads are absent.
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var node := (loop as SceneTree).root.get_node_or_null("Data")
		if node != null and "floors" in node:
			return node.floors
	return {}


# --- layout -----------------------------------------------------------------

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
	var sum := 0.0
	for kind in kinds:
		var w := maxf(float(KIND_MIN.get(kind, 240.0)), span * float(KIND_WEIGHT.get(kind, 1.0)) / total)
		widths.append(w)
		sum += w
	# Keep the floor close to its authored width by nudging the widest room.
	var widest := 0
	for i in widths.size():
		if widths[i] > widths[widest]:
			widest = i
	var floor_w: float = KIND_MIN.get(kinds[widest], 240.0)
	widths[widest] = maxf(floor_w, float(widths[widest]) + (span - sum))
	return widths


static func _platforms_for(kind: String, rect: Rect2) -> Array:
	# Every platform is placed over the surface that reaches it, so the check
	# below is a verification of intent, not a search for a solution.
	var x := rect.position.x
	var w := rect.size.x
	var top := rect.position.y
	var out: Array = []
	match kind:
		"gate":
			var pw := clampf(w * 0.42, 140.0, 300.0)
			out.append(Rect2(x + w * 0.10, top - 74.0, pw, 14.0))
			out.append(Rect2(x + w * 0.55, top - 96.0, pw, 14.0))
		"hall":
			var pw := clampf(w * 0.20, 90.0, 150.0)
			for i in 3:
				out.append(Rect2(x + w * (0.14 + 0.28 * float(i)), top - (84.0 + 7.0 * float(i)), pw, 14.0))
		"shaft":
			var pw := clampf(w * 0.52, 120.0, 200.0)
			for i in 3:
				# Alternate sides so the climb zigzags instead of stacking.
				out.append(Rect2(x + (w - pw) * (0.0 if i % 2 == 0 else 1.0), top - 72.0 * float(i + 1), pw, 14.0))
		"vault":
			var pw := clampf(w * 0.40, 110.0, 190.0)
			out.append(Rect2(x + w * 0.06, top - 64.0, pw, 14.0))
			out.append(Rect2(x + w * 0.54, top - 64.0, pw, 14.0))
			out.append(Rect2(x + w * 0.28, top - 124.0, pw, 14.0))
	return out


static func _spawns_for(rect: Rect2, platforms: Array) -> Array:
	var out: Array = []
	var span := maxf(60.0, rect.size.x - 80.0)
	for i in 5:
		var t := fposmod(float(i) * MathArt.INV_PHI, 1.0)
		out.append(Vector2(rect.position.x + 40.0 + span * t, rect.position.y - SPAWN_LIFT))
	for p in platforms:
		var pr: Rect2 = p
		out.append(Vector2(pr.get_center().x, pr.position.y - SPAWN_LIFT))
	return out


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

static func _reach(from: Rect2, to: Rect2) -> bool:
	var up := from.position.y - to.position.y
	if up > MAX_UP:
		return false
	var dx := maxf(0.0, maxf(to.position.x - from.end.x, from.position.x - to.end.x))
	# Climbing costs horizontal range: the arc is only 110 px up when it is
	# almost vertical, so a high platform must sit nearly on top of its parent.
	var budget := minf(MAX_SPAN, JUMP_LENGTH * (1.0 - 0.45 * maxf(up, 0.0) / JUMP_HEIGHT))
	return dx <= budget


static func _check_room(index: int, room: Dictionary) -> void:
	var slab: Rect2 = room["rect"]
	assert(BASE_Y - slab.position.y <= MAX_UP, "room slab must be climbable from the bottom ledge")
	var reached: Array = [slab]
	var pending: Array = (room["platforms"] as Array).duplicate()
	var moved := true
	while moved and not pending.is_empty():
		moved = false
		var i := 0
		while i < pending.size():
			var p: Rect2 = pending[i]
			var hit := false
			for from in reached:
				if _reach(from, p):
					hit = true
					break
			if hit:
				reached.append(p)
				pending.remove_at(i)
				moved = true
			else:
				i += 1
	if not pending.is_empty():
		push_warning("LevelGen: room %d (%s) has %d unreachable platform(s)" % [index, room["kind"], pending.size()])
