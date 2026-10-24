class_name Level
extends Node2D
## One generated floor: builds the collision and the stone for a LevelGen
## layout, then runs it (room-by-room spawning, the exit gate, death).
##
## The class is self-contained: everything comes from build(), so the
## foundation can create it, drop it in the tree and connect two signals.

signal cleared
signal player_died
## One room's last enemy died. The boon budget in data/floors.json is spent
## here, room by room: a reward handed out at the exit gate would land after
## the run is already over.
signal room_cleared(index: int)

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")

const WALL_W := 24.0
const WALL_TOP := -560.0
const WALL_H := 760.0
const DOOR_REACH := 62.0
const DOOR_HEIGHT := 260.0
const SAFE_DISTANCE := 160.0

# Palette 0-4 varies density and crack lean, never hue. Edge stays a lighter
# value than the STONE fill so the walkable line is always readable.
const PALETTE := [
	{"speck": 0.13, "crack": 0.020, "column": 2, "fog": 3, "edge": MathArt.STONE_HI, "seam": 48.0},
	{"speck": 0.22, "crack": 0.034, "column": 3, "fog": 4, "edge": MathArt.STONE_HI, "seam": 40.0},
	{"speck": 0.10, "crack": 0.014, "column": 4, "fog": 2, "edge": MathArt.MID_DIM, "seam": 56.0},
	{"speck": 0.26, "crack": 0.042, "column": 3, "fog": 5, "edge": MathArt.STONE_HI, "seam": 36.0},
	{"speck": 0.07, "crack": 0.008, "column": 2, "fog": 1, "edge": MathArt.PALE_DIM, "seam": 64.0},
]


## The exit gate. Closed it turns slowly and dim; open it spins faster and
## burns white. That difference is the only state cue the player needs.
class Door extends Node2D:
	var open := false
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var h := 108.0
		var half := 30.0
		var edge := MathArt.PALE if open else MathArt.STONE_HI
		MathArt.px_rect(self, Rect2(-half - 7.0, -h, 7.0, h), MathArt.STONE)
		MathArt.px_rect(self, Rect2(half, -h, 7.0, h), MathArt.STONE)
		MathArt.px_rect(self, Rect2(-half - 7.0, -h - 7.0, half * 2.0 + 14.0, 7.0), MathArt.STONE)
		MathArt.px_rect(self, Rect2(-half - 7.0, -h - 7.0, half * 2.0 + 14.0, 2.0), edge)
		MathArt.px_rect(self, Rect2(-half - 7.0, -3.0, half * 2.0 + 14.0, 3.0), MathArt.STONE_HI)

		var center := Vector2(0.0, -h * 0.5)
		var spin := t * (1.6 if open else 0.4)
		var tint := MathArt.WHITE if open else MathArt.MID_DIM
		MathArt.px_poly(self, MathArt.ngon(6, 17.0, spin, center),
			Color(0, 0, 0, 0), Color(tint, 0.85 if open else 0.35), 1.5)
		MathArt.px_poly(self, MathArt.ngon(3, 17.0 * MathArt.INV_PHI, -spin * MathArt.PHI, center),
			Color(0, 0, 0, 0), Color(tint, 0.55 if open else 0.20), 1.0)
		if open:
			MathArt.glow(self, center, 34.0, Color(MathArt.WHITE, 0.5))


var data: Dictionary = {}
var _seed := 0
var _rooms: Array = []
var _ground_sorted: Array = []
var _room_pending: Array = []
var _room_entered: Array = []
var _room_cleared: Array = []
var _room_alive: Array = []
var _alive: Array = []
var _pending_total := 0
var _seen: Dictionary = {}
var _dead := false
var _cleared_emitted := false
var _door: Door

var _specks: Array = []
var _cracks: Array = []
var _columns: Array = []


func build(floor_index: int, seed_value: int) -> void:
	data = LevelGen.generate(floor_index, seed_value)
	_seed = seed_value
	_rooms = data["rooms"]
	for room in _rooms:
		_room_pending.append((room["enemies"] as Array).duplicate())
		_room_entered.append(false)
		_room_cleared.append(false)
		_room_alive.append(0)
		_pending_total += _count(room["enemies"])
		for rect in room["ground"]:
			_ground_sorted.append(rect)
	# Deepest face first so a slab is never painted over by its own ledge.
	_ground_sorted.sort_custom(func(a, b): return a.position.y > b.position.y)

	for rect in _ground_sorted:
		_make_body(rect)
	for room in _rooms:
		var platforms: Array = room["platforms"]
		var oneway: Array = room["oneway"]
		for i in platforms.size():
			_make_body(platforms[i], bool(oneway[i]))
	_make_body(Rect2(-WALL_W, WALL_TOP, WALL_W, WALL_H))
	_make_body(Rect2(float(data["width"]), WALL_TOP, WALL_W, WALL_H))

	_build_decoration()

	_door = Door.new()
	_door.position = data["exit"]
	add_child(_door)

	var player := _player()
	if player != null:
		player.global_position = data["start"]
	queue_redraw()


func floor_name() -> String:
	return str(data.get("name", ""))


func start_point() -> Vector2:
	return data.get("start", Vector2.ZERO)


func progress() -> Vector2:
	var done := 0
	for room_cleared in _room_cleared:
		if room_cleared:
			done += 1
	return Vector2(float(done), float(_rooms.size()))


func enemies_remaining() -> int:
	return _alive.size() + _pending_total


func _count(groups: Array) -> int:
	var total := 0
	for group in groups:
		total += int(group[1])
	return total


func _player() -> Player:
	if Game.player != null and is_instance_valid(Game.player):
		return Game.player
	return null


func _make_body(rect: Rect2, oneway := false) -> void:
	var body := StaticBody2D.new()
	# One-way decks sit on their own layer so the player can ignore them while
	# rising; everything else is ordinary world geometry.
	body.collision_layer = Layers.ONEWAY if oneway else Layers.WORLD
	body.collision_mask = 0
	body.position = rect.position + rect.size * 0.5
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	if oneway:
		# Godot's own one-way collision: solid from above, open from below.
		# Far more reliable than toggling the player's collision mask, which
		# can re-enable mid-jump and shove the body sideways.
		collision.one_way_collision = true
		collision.one_way_collision_margin = 6.0
	body.add_child(collision)
	add_child(body)


# --- run --------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	var player := _player()
	if player == null:
		return
	if not _dead and player.hp <= 0.0:
		_dead = true
		player_died.emit()
		return

	var x := player.global_position.x
	for i in _rooms.size():
		if _room_entered[i]:
			continue
		var rect: Rect2 = _rooms[i]["rect"]
		if x >= rect.position.x and x < rect.end.x:
			_enter_room(i)
	_update_door(player)


func _enter_room(index: int) -> void:
	_room_entered[index] = true
	var groups: Array = _room_pending[index]
	_room_pending[index] = []
	if groups.is_empty():
		_room_cleared[index] = true
		return

	var player := _player()
	var from := player.global_position if player != null else Vector2.ZERO
	var points: Array = (_rooms[index]["spawns"] as Array).duplicate()
	points.sort_custom(func(a, b): return a.distance_squared_to(from) > b.distance_squared_to(from))
	var rect: Rect2 = _rooms[index]["rect"]
	# The boss ignores the generic spawn points: they are placed for a 42 px
	# husk, which leaves a 64 px boss embedded in the slab and facing a
	# platform. boss_at is a clear lane chosen by the generator.
	var boss_at: Variant = data.get("boss_at")
	var boss_kind := str(data.get("boss", ""))
	for group in groups:
		var kind := str(group[0])
		for i in int(group[1]):
			var at := _take_point(points, from, rect)
			if not boss_kind.is_empty() and kind == boss_kind and boss_at != null:
				at = boss_at
			_spawn(kind, at, index)


func _take_point(points: Array, from: Vector2, room: Rect2) -> Vector2:
	# Never materialise inside the player; the list is sorted farthest first.
	# The fallback is the room slab: the floor table never asks for more
	# enemies than a room has points, but a spot in mid air would be a spawn
	# no player could ever reach.
	var farthest := Vector2(room.get_center().x, room.position.y - LevelGen.SPAWN_LIFT)
	for point in points:
		if point.distance_to(from) >= SAFE_DISTANCE:
			points.erase(point)
			return point
		farthest = point
	if not points.is_empty():
		points.pop_back()
	return farthest


func _spawn(kind: String, at: Vector2, room_index: int) -> void:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.configure(kind, Data.enemies.get(kind, {}), 1.0)
	enemy.position = at
	enemy.set_meta("room", room_index)
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	_alive.append(enemy)
	_room_alive[room_index] += 1
	_pending_total -= 1
	if not _seen.has(kind):
		_seen[kind] = true
		Profile.see("enemy", kind)


func _on_enemy_died(enemy: Enemy) -> void:
	_alive.erase(enemy)
	var index := int(enemy.get_meta("room", 0))
	_room_alive[index] = maxi(0, _room_alive[index] - 1)
	if _room_alive[index] == 0 and (_room_pending[index] as Array).is_empty():
		_room_cleared[index] = true
		room_cleared.emit(index)


func _update_door(player: Player) -> void:
	if not _door.open:
		_door.open = enemies_remaining() == 0
	if not _door.open or _cleared_emitted:
		return
	# The gate is a column, not a point. Multi-deck rooms put the player on a
	# gallery directly above the door, and a point test would never fire there;
	# a player standing over the exit has clearly arrived.
	var gate: Vector2 = data["exit"]
	var dx := absf(player.global_position.x - gate.x)
	var dy := gate.y - player.global_position.y
	if dx < DOOR_REACH and absf(dy) < DOOR_HEIGHT:
		_cleared_emitted = true
		cleared.emit()


# --- decoration -------------------------------------------------------------

func _palette() -> Dictionary:
	return PALETTE[clampi(int(data.get("palette", 0)), 0, PALETTE.size() - 1)]


func _build_decoration() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed * 7919 + int(data.get("palette", 0)) * 131 + 17
	var pal := _palette()
	for rect in _ground_sorted:
		var specks: Array = []
		for i in int(rect.size.x * float(pal["speck"])):
			specks.append(Vector3(
				rng.randf_range(rect.position.x + 2.0, rect.end.x - 2.0),
				rng.randf_range(rect.position.y + 6.0, rect.position.y + 96.0),
				rng.randf()))
		_specks.append(specks)
		var cracks: Array = []
		for i in int(rect.size.x * float(pal["crack"])):
			cracks.append(Vector4(
				rng.randf_range(rect.position.x + 12.0, rect.end.x - 12.0),
				rng.randf_range(8.0, 40.0),
				rng.randf_range(4.0, 12.0),
				rng.randf()))
		_cracks.append(cracks)

	for i in _rooms.size():
		var room: Dictionary = _rooms[i]
		var rect: Rect2 = room["rect"]
		if str(room["kind"]) == "hall":
			# In a hall the platforms are column capitals, not floating slabs.
			var platforms: Array = room["platforms"]
			var oneway: Array = room["oneway"]
			for j in platforms.size():
				if bool(oneway[j]):
					continue
				var pr: Rect2 = platforms[j]
				_columns.append({
					"x": pr.get_center().x, "w": minf(pr.size.x * 0.5, 44.0),
					"top": pr.position.y, "bottom": rect.position.y, "sigil": true,
				})
		for c in int(pal["column"]):
			var t := fposmod(float(c) * MathArt.INV_PHI + 0.17 * float(i), 1.0)
			_columns.append({
				"x": rect.position.x + rect.size.x * t,
				"w": 30.0 + 14.0 * fposmod(t * MathArt.PHI, 1.0),
				"top": rect.position.y - 470.0, "bottom": rect.position.y,
				"sigil": c % 2 == 0,
			})


func _draw() -> void:
	_draw_vault()
	_draw_monoliths()
	_draw_rose_window()
	for i in _ground_sorted.size():
		_draw_ground(_ground_sorted[i], _specks[i], _cracks[i])
	for room in _rooms:
		var platforms: Array = room["platforms"]
		var oneway: Array = room["oneway"]
		for i in platforms.size():
			var pr: Rect2 = platforms[i]
			if bool(oneway[i]):
				_draw_deck(pr)
			elif pr.size.y > 40.0:
				_draw_mass(pr)
			else:
				_draw_platform(pr)
	_draw_bounds()
	_draw_fog()


## The space behind the geometry. Without it the multi-deck floors read as
## slabs floating in a void: the fullscreen background shader is a spiral
## field, not architecture, and the eye needs a wall to judge height against.
## A far wall, then a nearer band, then a row of arch silhouettes, each a
## slightly lighter value than the one behind it.
func _draw_vault() -> void:
	var width := float(data.get("width", 0.0))
	if width <= 0.0:
		return
	var pal := _palette()
	var depth := 640.0
	# Far wall: one flat value, darker than any stone.
	MathArt.px_rect(self, Rect2(-40.0, -depth, width + 80.0, depth + 60.0),
		Color(MathArt.INK, 0.95))
	# Courses 22 px apart. This is the only thing that gives the wall scale.
	var y := -depth
	var row := 0
	while y < 40.0:
		MathArt.px_rect(self, Rect2(-40.0, y, width + 80.0, 1.0),
			Color(MathArt.MID, 0.055 if row % 2 == 0 else 0.03))
		y += 22.0
		row += 1

	# Pilasters + arches, anchored so the arch FOOT sits on the floor line and
	# the apex is 300 px above it. Anchoring to the top of the wall put every
	# arch below the camera, which is why the background read as a black band.
	var step := 250.0 + 26.0 * float(int(pal["column"]))
	var foot := float(_rooms[0]["rect"].position.y) if not _rooms.is_empty() else 0.0
	var rise := 300.0
	var x := 30.0
	while x < width:
		MathArt.px_rect(self, Rect2(x, foot - depth, 11.0, depth),
			Color(MathArt.BG_2, 0.62))
		MathArt.px_rect(self, Rect2(x, foot - depth, 1.0, depth),
			Color(MathArt.STONE_HI, 0.12))
		MathArt.px_rect(self, Rect2(x + 10.0, foot - depth, 1.0, depth),
			Color(MathArt.INK, 0.5))
		var half := (step - 11.0) * 0.5
		var cx := x + 11.0 + half
		var top := foot - rise
		# Two quarter-arcs meeting at the apex, then the jambs down to the floor.
		MathArt.arc(self, Vector2(cx - half, top + half), half, -PI * 0.5, 0.0,
			Color(MathArt.MID, 0.10), 1.0)
		MathArt.arc(self, Vector2(cx + half, top + half), half, PI, PI * 1.5,
			Color(MathArt.MID, 0.10), 1.0)
		MathArt.px_rect(self, Rect2(cx - half, top + half, 1.0, foot - top - half),
			Color(MathArt.MID, 0.075))
		MathArt.px_rect(self, Rect2(cx + half, top + half, 1.0, foot - top - half),
			Color(MathArt.MID, 0.075))
		x += step

	# One landmark per floor, keyed off the palette, so no two floors read alike.
	var center := Vector2(width * 0.5, foot - rise - 150.0)
	match int(data.get("palette", 0)) % 4:
		0:
			for i in 3:
				MathArt.px_ring(self, center, 132.0 - float(i) * 34.0,
					Color(MathArt.MID, 0.07 + float(i) * 0.02), 1.0)
		1:
			MathArt.px_poly(self, MathArt.star(14, 140.0, 108.0, -PI * 0.5, center),
				Color(0, 0, 0, 0), Color(MathArt.MID, 0.09), 1.0)
		2:
			MathArt.px_poly(self, MathArt.ngon(8, 120.0, PI / 8.0, center),
				Color(0, 0, 0, 0), Color(MathArt.MID, 0.09), 1.0)
			MathArt.px_poly(self, MathArt.ngon(8, 120.0 * MathArt.INV_PHI, 0.0, center),
				Color(0, 0, 0, 0), Color(MathArt.MID, 0.06), 1.0)
		_:
			var loop := PackedVector2Array()
			for i in 61:
				loop.append(center + MathArt.lissajous(TAU * float(i) / 60.0, 3.0, 2.0, PI * 0.5) * 120.0)
			MathArt.px_poly(self, loop, Color(0, 0, 0, 0), Color(MathArt.MID, 0.08), 1.0)


func _draw_monoliths() -> void:
	for column in _columns:
		var x: float = column["x"]
		var width: float = column["w"]
		var top: float = column["top"]
		var bottom: float = column["bottom"]
		var height := bottom - top
		if height <= 4.0:
			continue
		MathArt.px_rect(self, Rect2(x, top, width, height), Color(MathArt.BG_2, 0.72))
		MathArt.px_rect(self, Rect2(x + width - 3.0, top, 3.0, height), Color(MathArt.INK, 0.72))
		MathArt.px_rect(self, Rect2(x + 2.0, top, 1.0, height), Color(MathArt.STONE_HI, 0.24))
		var cap := MathArt.ngon(6, width * 0.5, 0.0, Vector2(x + width * 0.5, top))
		MathArt.px_poly(self, cap, Color(MathArt.BG_1, 0.85), Color(MathArt.STONE_HI, 0.45), 1.0)
		if bool(column["sigil"]):
			var center := Vector2(x + width * 0.5, top + 110.0)
			MathArt.px_poly(self, MathArt.ngon(6, width * 0.30, PI / 6.0, center),
				Color(0, 0, 0, 0), Color(MathArt.PALE_DIM, 0.16), 1.0)
			MathArt.px_ring(self, center, width * 0.46, Color(MathArt.PALE_DIM, 0.09), 1.0)


func _draw_rose_window() -> void:
	if _rooms.is_empty():
		return
	var last: Rect2 = _rooms[_rooms.size() - 1]["rect"]
	var center := Vector2(last.end.x - 90.0, last.position.y - 200.0)
	var bright := 0.06 + 0.02 * float(int(data.get("palette", 0)))
	for i in 3:
		MathArt.px_ring(self, center, 210.0 - float(i) * 46.0, Color(MathArt.MID, bright + float(i) * 0.02), 1.0)
	for i in 12:
		var angle := TAU * float(i) / 12.0 - PI * 0.5
		MathArt.px_line(self, center + Vector2.from_angle(angle) * 120.0,
			center + Vector2.from_angle(angle) * 210.0, Color(MathArt.MID, bright), 1.0)
	MathArt.px_poly(self, MathArt.star(12, 122.0, 96.0, -PI * 0.5, center),
		Color(0, 0, 0, 0), Color(MathArt.MID, bright), 1.0)


func _draw_ground(rect: Rect2, specks: Array, cracks: Array) -> void:
	var pal := _palette()
	var edge: Color = pal["edge"]
	MathArt.px_rect(self, rect, MathArt.STONE)
	MathArt.px_rect(self, Rect2(rect.position, Vector2(rect.size.x, 3.0)), edge)
	MathArt.px_rect(self, Rect2(rect.position + Vector2(0, 3), Vector2(rect.size.x, 1.0)),
		Color(MathArt.MID_DIM, 0.35))

	for speck in specks:
		var shade: float = speck.z
		if shade > 0.80:
			MathArt.px_rect(self, Rect2(speck.x, speck.y, 1, 1), Color(MathArt.STONE_HI, 0.45))
		elif shade > 0.55:
			MathArt.px_rect(self, Rect2(speck.x, speck.y, 1, 1), Color(MathArt.INK, 0.35))
		elif shade > 0.30:
			MathArt.px_rect(self, Rect2(speck.x, speck.y, 1, 1), Color(MathArt.MID_DIM, 0.07))

	for crack in cracks:
		var color := Color(MathArt.INK, 0.55) if float(crack.w) > 0.4 else Color(MathArt.LIGHT_DIM, 0.10)
		MathArt.px_line(self, Vector2(crack.x, rect.position.y + 4.0),
			Vector2(crack.x + crack.z, rect.position.y + crack.y), color, 1.0)
		if float(crack.w) > 0.7:
			MathArt.px_line(self, Vector2(crack.x + crack.z, rect.position.y + crack.y),
				Vector2(crack.x + crack.z + 3.0, rect.position.y + crack.y + 6.0), color, 1.0)

	MathArt.px_rect(self, Rect2(rect.position.x, rect.position.y + 5.0, rect.size.x, 1.0),
		Color(MathArt.PALE_DIM, 0.10))


## A pass-through deck: thin, bright top edge, and a dashed under-edge. The
## dashes are the whole point - they are the only cue that says "you can jump
## up through this one".
func _draw_deck(rect: Rect2) -> void:
	var pal := _palette()
	MathArt.px_rect(self, Rect2(rect.position, Vector2(rect.size.x, rect.size.y)),
		Color(MathArt.STONE_HI, 0.92))
	MathArt.px_rect(self, Rect2(rect.position, Vector2(rect.size.x, 2.0)), pal["edge"])
	# Dashed underside: 6 on, 5 off.
	var x := rect.position.x
	var bottom := rect.position.y + rect.size.y - 1.0
	while x < rect.end.x:
		var run := minf(6.0, rect.end.x - x)
		MathArt.px_rect(self, Rect2(roundf(x), bottom, run, 1.0), Color(MathArt.INK, 0.55))
		x += 11.0
	for fraction in [0.0, MathArt.INV_PHI * MathArt.INV_PHI, 1.0]:
		MathArt.px_rect(self, Rect2(roundf(rect.position.x + rect.size.x * float(fraction)),
			rect.position.y + 2.0, 1, 3.0), Color(MathArt.PALE_DIM, 0.20))


## A thick solid mass: a pillar, a lip or a vault floor. Reads as stone, not as
## something you can slip through.
func _draw_mass(rect: Rect2) -> void:
	var pal := _palette()
	MathArt.px_rect(self, rect, Color(MathArt.STONE, 0.96))
	MathArt.px_rect(self, Rect2(rect.position, Vector2(rect.size.x, 3.0)), pal["edge"])
	MathArt.px_rect(self, Rect2(rect.position + Vector2(rect.size.x - 3.0, 0), Vector2(3.0, rect.size.y)),
		Color(MathArt.INK, 0.55))
	MathArt.px_rect(self, Rect2(rect.position + Vector2(1.0, 3.0), Vector2(1.0, rect.size.y - 3.0)),
		Color(MathArt.STONE_HI, 0.22))
	var y := rect.position.y + 14.0
	var row := 0
	while y < rect.end.y - 6.0:
		var offset := 0.0 if row % 2 == 0 else 18.0
		var x := rect.position.x + 8.0 + offset
		while x < rect.end.x - 10.0:
			MathArt.px_rect(self, Rect2(roundf(x), roundf(y), 1.0, 1.0),
				Color(MathArt.STONE_DIM, 0.5))
			x += 36.0
		y += 16.0
		row += 1


func _draw_platform(rect: Rect2) -> void:
	var pal := _palette()
	MathArt.px_rect(self, rect, MathArt.STONE)
	MathArt.px_rect(self, Rect2(rect.position, Vector2(rect.size.x, 2.0)), pal["edge"])
	MathArt.px_rect(self, Rect2(rect.position + Vector2(0, 2), Vector2(rect.size.x, 1.0)),
		Color(MathArt.MID_DIM, 0.25))
	MathArt.px_rect(self, Rect2(rect.position + Vector2(0, rect.size.y - 2.0), Vector2(rect.size.x, 2.0)),
		Color(MathArt.INK, 0.8))
	for fraction in [0.0, MathArt.INV_PHI * MathArt.INV_PHI, MathArt.INV_PHI, 1.0]:
		MathArt.px_rect(self, Rect2(roundf(rect.position.x + rect.size.x * float(fraction)),
			rect.position.y + 2.0, 1, 4.0), Color(MathArt.PALE_DIM, 0.16))
	var seam := rect.position.x + 24.0
	while seam < rect.end.x - 10.0:
		MathArt.px_rect(self, Rect2(roundf(seam), rect.position.y + 3.0, 1, rect.size.y - 5.0),
			Color(MathArt.INK, 0.35))
		seam += float(pal["seam"])


func _draw_bounds() -> void:
	var right := float(data.get("width", 0.0))
	for x in [-WALL_W, right]:
		MathArt.px_rect(self, Rect2(x, WALL_TOP, WALL_W, WALL_H), MathArt.STONE)
		MathArt.px_rect(self, Rect2(x, WALL_TOP, 2.0, WALL_H), Color(MathArt.STONE_HI, 0.22))
		MathArt.px_rect(self, Rect2(x, WALL_TOP, WALL_W, 2.0), Color(MathArt.STONE_HI, 0.45))


func _draw_fog() -> void:
	var bands := int(_palette()["fog"])
	for room in _rooms:
		var rect: Rect2 = room["rect"]
		var x := rect.position.x + 60.0
		while x < rect.end.x - 60.0:
			for band in bands:
				var width := 90.0 - float(band) * 22.0
				MathArt.px_rect(self, Rect2(x - width * 0.5, rect.position.y - 20.0 + float(band) * 5.0, width, 3.0),
					Color(MathArt.STONE_DIM, 0.05))
			x += 420.0
