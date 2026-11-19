class_name Level
extends Node2D
## A playable biome from authored modules, or a legacy generator fixture.
## layout, then runs it (room-by-room spawning, the exit gate, death).
##
## The class is self-contained: everything comes from build(), so the
## foundation can create it, drop it in the tree and connect two signals.

signal cleared
signal exit_chosen(destination: String)
signal map_requested(teleport_mode: bool)
signal player_died
## One room's last enemy died. The boon budget in data/floors.json is spent
## here, room by room: a reward handed out at the exit gate would land after
## the run is already over.
signal room_cleared(index: int)

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const BIOME_GEN := preload("res://scripts/world/biome_gen.gd")
const REACH_CHECK := preload("res://scripts/systems/surface_reach.gd")
const GATE_SCRIPT := preload("res://scripts/world/traversal_gate.gd")
const PICKUP_SCRIPT := preload("res://scripts/world/progress_pickup.gd")

## English display content for traversal ids that no canonical table names. The
## CSV row replaces it once loaded; it is a fallback, never a translation.
const KEY_NAME_EN := {
	"cask_key": "Cask Key", "clock_key": "Clock Key", "foundry_key": "Foundry Key",
	"grave_key": "Grave Key", "rampart_key": "Rampart Key",
}
const RUNE_NAME_EN := {
	"canopy_rune": "Canopy Rune", "climb_rune": "Climb Rune", "clock_rune": "Clock Rune",
	"ground_rune": "Ground Rune", "homunculus_rune": "Homunculus Rune",
	"lens_rune": "Lens Rune", "pathfinder_rune": "Pathfinder Rune", "phase_rune": "Phase Rune",
}

const WALL_W := 24.0
const WALL_TOP := -560.0
const WALL_H := 760.0
const DOOR_REACH := 62.0
const DOOR_HEIGHT := 260.0
const SAFE_DISTANCE := 160.0

# Geometry density remains legacy-compatible; color comes only from MathArt.
#
#   vault   far-wall base value        course  first course offset on a terrace
#   niche   recessed niches per room   shaft   light-shaft alpha on the gallery
#   chain   hanging chains per room    near    near-plane parapet value
#   panel   recessed vault-panel alpha (0 leaves the arcade bare)
const PALETTE := [
	{"speck": 0.13, "crack": 0.020, "column": 2, "fog": 3, "edge": MathArt.STONE_HI, "seam": 48.0,
		"vault": MathArt.STONE_DIM, "course": 15.0, "niche": 2, "shaft": 0.075, "chain": 1,
		"near": MathArt.BG_1, "panel": 0.40},
	{"speck": 0.22, "crack": 0.034, "column": 3, "fog": 4, "edge": MathArt.STONE_HI, "seam": 40.0,
		"vault": MathArt.BG_2, "course": 12.0, "niche": 3, "shaft": 0.055, "chain": 2,
		"near": MathArt.BG_2, "panel": 0.22},
	{"speck": 0.10, "crack": 0.014, "column": 4, "fog": 2, "edge": MathArt.MID_DIM, "seam": 56.0,
		"vault": MathArt.STONE, "course": 21.0, "niche": 1, "shaft": 0.095, "chain": 1,
		"near": MathArt.INK, "panel": 0.55},
	{"speck": 0.26, "crack": 0.042, "column": 3, "fog": 5, "edge": MathArt.STONE_HI, "seam": 36.0,
		"vault": MathArt.BG_2, "course": 11.0, "niche": 3, "shaft": 0.060, "chain": 2,
		"near": MathArt.BG_2, "panel": 0.16},
	{"speck": 0.07, "crack": 0.008, "column": 2, "fog": 1, "edge": MathArt.PALE_DIM, "seam": 64.0,
		"vault": MathArt.STONE_DIM, "course": 26.0, "niche": 1, "shaft": 0.110, "chain": 1,
		"near": MathArt.BG_1, "panel": 0.60},
]

## Hanging chains and their braziers, in their own node so the sway redraws a
## dozen short polylines instead of the whole floor: Level's own _draw() only
## runs when something asks for it.
class VaultHang extends Node2D:
	const SAMPLES := 10
	var chains: Array = []   # { x, top, len, phase }
	var niches: Array = []   # Vector2: ember sources in the wall recesses
	var t := 0.0
	var ember_t := 1.4
	var _slot := 0
	var _niche_index := 0
	var _chain_index := 0

	func _process(delta: float) -> void:
		t += delta
		# Ambience pulses on a timer: one small burst at a time, never per frame.
		ember_t -= delta
		if ember_t <= 0.0:
			ember_t = 1.2
			_burst()
		queue_redraw()

	func _burst() -> void:
		_slot += 1
		if _slot % 2 == 0 and not niches.is_empty():
			_niche_index = (_niche_index + 1) % niches.size()
			Juice.ember_drift(self, niches[_niche_index], MathArt.FIRE, 3, 2.2)
		elif not chains.is_empty():
			_chain_index = (_chain_index + 1) % chains.size()
			Juice.ember_drift(self, _sample(chains[_chain_index], 1.0), MathArt.FIRE, 3, 2.4)

	## Pendulum sway off the node's own clock: the tip circles on a Lissajous
	## instead of sliding sideways, and k² keeps the anchor perfectly still.
	func _sample(chain: Dictionary, k: float) -> Vector2:
		var s := MathArt.lissajous(t * 0.55 + float(chain["phase"]), 1.0, 1.0, PI * 0.5)
		return Vector2(float(chain["x"]) + s.x * 15.0 * k * k,
			float(chain["top"]) + float(chain["len"]) * k + s.y * 3.0 * k * k)

	func _draw() -> void:
		for chain in chains:
			var prev := Vector2(float(chain["x"]), float(chain["top"]))
			for j in range(1, SAMPLES):
				var point := _sample(chain, float(j) / float(SAMPLES - 1))
				MathArt.line(self, prev, point, Color(MathArt.STONE_HI, 0.8), 1.0)
				prev = point
			_draw_brazier(prev, float(chain["phase"]))

	func _draw_brazier(at: Vector2, phase: float) -> void:
		var flicker := 0.5 + 0.5 * sin(t * 6.0 + phase)
		MathArt.glow(self, at + Vector2(0.0, -7.0), 10.0 + 3.0 * flicker, MathArt.FIRE, 2)
		MathArt.arc(self, at + Vector2(0.0, -5.0), 5.0, 0.0, PI, Color(MathArt.STONE_HI, 0.9), 1.5)
		MathArt.px_rect(self, Rect2(at.x - 2.0, at.y - 12.0, 4.0, 6.0),
			Color(MathArt.FIRE, 0.45 + 0.35 * flicker))


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
		var edge := MathArt.ACCENT if open else MathArt.STONE_HI
		MathArt.px_rect(self, Rect2(-half - 7.0, -h, 7.0, h), MathArt.STONE)
		MathArt.px_rect(self, Rect2(half, -h, 7.0, h), MathArt.STONE)
		MathArt.px_rect(self, Rect2(-half - 7.0, -h - 7.0, half * 2.0 + 14.0, 7.0), MathArt.STONE)
		MathArt.px_rect(self, Rect2(-half - 7.0, -h - 7.0, half * 2.0 + 14.0, 2.0), edge)
		MathArt.px_rect(self, Rect2(-half - 7.0, -3.0, half * 2.0 + 14.0, 3.0), MathArt.STONE_HI)

		var center := Vector2(0.0, -h * 0.5)
		var spin := t * (1.6 if open else 0.4)
		var tint := MathArt.ACCENT if open else MathArt.MID_DIM
		MathArt.px_poly(self, MathArt.ngon(6, 17.0, spin, center),
			Color(0, 0, 0, 0), Color(tint, 0.85 if open else 0.35), 1.5)
		MathArt.px_poly(self, MathArt.ngon(3, 17.0 * MathArt.INV_PHI, -spin * MathArt.PHI, center),
			Color(0, 0, 0, 0), Color(tint, 0.55 if open else 0.20), 1.0)
		if open:
			MathArt.glow(self, center, 34.0, Color(MathArt.ACCENT, 0.5))


var data: Dictionary = {}
var route_node := ""
var rune_pickup: Node2D = null
var _rune_room := -1
var _gates: Dictionary = {}
var _active_pads: Dictionary = {}
var _near_hint := ""
var _hint_label: Label
var _seed := 0
# Floor number this layout was built for: used only to name a legacy floor at
# display time, never to change generation.
var _floor_index := 0
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
# Foundation detailing per ground rect, indexed like _specks: _draw() walks it,
# it is never built there.
var _strata: Array = []
var _shafts: Array = []
var _niches: Array = []
# y where the near plane starts: below every terrace, so the foreground mass can
# never cover a walkable edge.
var _near_y := 0.0
var _stone := MathArt.STONE
var _edge := MathArt.STONE_HI
var _far := MathArt.BG_1
var _near := MathArt.BG_2
var _accent := MathArt.FIRE
var _visual_palette: Dictionary = {}


static func route_layout(id: String, seed_value: int, revision: String = BIOME_GEN.LATEST_REVISION) -> Dictionary:
	var generated := BIOME_GEN.generate_checked(id, seed_value, Data.biomes, Data.room_modules, Data.route_graph, revision, Data.generation_spatial)
	var layout: Dictionary = generated.layout
	if layout.is_empty():
		print("ROUTE GENERATION REJECTED ", JSON.stringify({"biome": id, "seed": seed_value, "revision": revision, "variant": generated.variant, "attempts": generated.attempts, "errors": generated.errors}))
	if layout.is_empty():
		return {}
	layout["reachable"] = REACH_CHECK.verify(layout, Profile.unlocked_runes, Data.enemies)
	if not bool(layout["reachable"]["ok"]):
		print("ROUTE REACH REJECTED ", JSON.stringify({"biome": id, "seed": seed_value, "revision": revision, "result": layout["reachable"]}))
		return {}
	return layout


func build(floor_index: int, seed_value: int, prepared: Dictionary = {}) -> void:
	data = prepared if not prepared.is_empty() else (LevelGen.generate(floor_index, seed_value) if route_node.is_empty() else route_layout(route_node, seed_value, Game.generator_revision))
	if data.is_empty():
		push_error("Level: no verified layout: " + route_node)
		return
	_seed = int(data.get("seed", seed_value))
	_floor_index = floor_index
	var palette_id := route_node if not route_node.is_empty() else "legacy_%d" % floor_index
	_stone = MathArt.biome_color(palette_id, "stone")
	_edge = MathArt.biome_color(palette_id, "edge")
	_far = MathArt.biome_color(palette_id, "far")
	_near = MathArt.biome_color(palette_id, "near")
	_accent = MathArt.biome_color(palette_id, "accent")
	_visual_palette = PALETTE[clampi(int(data.get("palette", 0)), 0, PALETTE.size() - 1)].duplicate()
	_visual_palette["edge"] = _edge
	_visual_palette["vault"] = _far
	_visual_palette["near"] = _near
	_rooms = data["rooms"]
	if not route_node.is_empty():
		Profile.runes_changed.connect(queue_redraw)
		if not str(data["rune"]).is_empty() and not Profile.unlocked_runes.has(str(data["rune"])):
			_rune_room = int(data["rune_room"])
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
	if route_node.is_empty():
		_make_body(Rect2(-WALL_W, WALL_TOP, WALL_W, WALL_H))
		_make_body(Rect2(float(data["width"]), WALL_TOP, WALL_W, WALL_H))
		_build_decoration()
		_door = Door.new()
		_door.position = data["exit"]
		add_child(_door)
	else:
		var bounds: Rect2 = data["bounds"]
		_make_body(Rect2(-WALL_W, bounds.position.y - 120, WALL_W, bounds.size.y + 280))
		_make_body(Rect2(bounds.end.x, bounds.position.y - 120, WALL_W, bounds.size.y + 280))
		_make_body(Rect2(0, bounds.position.y - 120, bounds.size.x, WALL_W))
		for spec: Dictionary in data["gates"]:
			var gate := GATE_SCRIPT.new()
			gate.spec = spec
			gate.opened.connect(queue_redraw)
			add_child(gate)
			_gates[str(spec["id"])] = gate
		for key: Dictionary in data["keys"]:
			var pickup := PICKUP_SCRIPT.new()
			pickup.tree_exiting.connect(queue_redraw)
			pickup.item_type = "key"
			pickup.item_id = str(key["id"])
			pickup.position = key["pos"]
			add_child(pickup)
		_hint_label = Label.new()
		_hint_label.size = Vector2(400, 20)
		_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hint_label.z_index = 4
		_hint_label.add_theme_font_override("font", MathArt.ui_font())
		_hint_label.add_theme_font_size_override("font_size", 11)
		_hint_label.add_theme_color_override("font_color", MathArt.WHITE)
		_hint_label.add_theme_color_override("font_outline_color", MathArt.INK)
		_hint_label.add_theme_constant_override("outline_size", 2)
		_hint_label.visible = false
		add_child(_hint_label)
	_spawn_caches()
	_spawn_run_loot()
	var player := _player()
	if player != null:
		player.traversal_world = self if not route_node.is_empty() else null
		player.relocate(data["start"])
	queue_redraw()


func _spawn_run_loot() -> void:
	if Game.build == null:
		return
	for id in Data.passage.blueprints:
		var cfg: Dictionary = Data.passage.blueprints[id]
		if cfg.biome != route_node or not data.get("room_ids", {}).has(cfg.room) or Profile.delivered_blueprints.has(id) or Game.carried_blueprints.has(id):
			continue
		var pickup := PICKUP_SCRIPT.new()
		pickup.item_type = "blueprint"
		pickup.item_id = str(id)
		pickup.position = data.rooms[data.room_ids[cfg.room]].rect.position + Vector2(float(cfg.at[0]), float(cfg.at[1]))
		add_child(pickup)
	for spec: Dictionary in Data.gear["placements"]:
		if not data.get("room_ids", {}).has(spec["room"]):
			continue
		var room: Dictionary = data["rooms"][data["room_ids"][spec["room"]]]
		var loot := RunLoot.new()
		loot.kind = str(spec["kind"])
		loot.amount = int(spec.get("amount", 0))
		loot.position = room["rect"].position + Vector2(float(spec["offset"][0]), float(spec["offset"][1]))
		if spec.has("pool"):
			loot.item = Game.create_loot(str(spec["pool"]), int(data.get("seed", 0)) + str(spec["room"]).hash())
			if loot.kind == "shop":
				loot.cost = Game.build.price(loot.item)
		add_child(loot)


## Route floors name their biome; the legacy arena floor keeps its own label,
## which belongs to the arena fixture and is not a route name.
func floor_name() -> String:
	if not route_node.is_empty():
		var node: Dictionary = Data.route_graph["nodes"].get(route_node, {})
		return ContentText.name("biome", route_node, str(node.get("name", route_node))).to_upper()
	var canonical := str(data.get("name", ""))
	if _floor_index <= 0:
		return canonical
	return ContentText.of("FLOOR_%d_NAME" % _floor_index, canonical)


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


## Read-only snapshot of the room states, for the HUD's route strip. The strip
## is the only thing that tells a player on an 8200 px floor how far the gate
## is and which rooms are already behind them.
func room_flags() -> Array:
	return _room_cleared.duplicate()


## Reward for taking the high route. The generator places these on decks at
## least two tiers above a room slab and the BFS has already proven those decks
## reachable, so a cache is always a real detour and never bait in a wall.
func _spawn_caches() -> void:
	for entry in (data.get("caches", []) as Array):
		var spot: Dictionary = entry
		var pickup := CellPickup.new()
		pickup.resting = true
		pickup.value = int(spot.get("value", 6))
		pickup.position = spot.get("pos", Vector2.ZERO)
		add_child(pickup)


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
	# Main settles every death, including one during the clear transition.
	if not _dead and player.hp <= 0.0:
		_dead = true
		player_died.emit()
		return

	var x := player.global_position.x
	for i in _rooms.size():
		if _room_entered[i]:
			continue
		var rect: Rect2 = _rooms[i]["rect"]
		if (route_node.is_empty() and x >= rect.position.x and x < rect.end.x) or (not route_node.is_empty() and (_rooms[i]["bounds"] as Rect2).has_point(player.global_position)):
			_enter_room(i)
	if not route_node.is_empty():
		for pad: Dictionary in data["pads"]:
			if str(pad["kind"]) == "checkpoint" and player.global_position.distance_to(pad["pos"]) < float(Data.traversal["interact_reach"]) and not _active_pads.has(str(pad["id"])):
				_active_pads[str(pad["id"])] = true
				queue_redraw()
		var hint := _interaction_hint(player.global_position)
		if hint != _near_hint:
			_near_hint = hint
			_hint_label.text = hint
			_hint_label.visible = not hint.is_empty()
		_hint_label.global_position = player.global_position + Vector2(-200, -76)
	_update_door(player)


func _enter_room(index: int) -> void:
	_room_entered[index] = true
	var groups: Array = _room_pending[index]
	_room_pending[index] = []
	if groups.is_empty():
		# Deliberately NO room_cleared.emit(): that signal is the reward trigger
		# (_on_room_cleared spends one boon), and the entrance room is always
		# empty, so emitting would hand out a free boon the moment a floor loads.
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
	var fallback := Vector2(room.get_center().x, room.position.y - LevelGen.SPAWN_LIFT)
	for i in points.size():
		if (points[i] as Vector2).distance_to(from) >= SAFE_DISTANCE:
			return points.pop_at(i)
	if points.is_empty():
		return fallback
	# Every candidate is inside SAFE_DISTANCE (a cramped room, or the player
	# standing in the middle of it). The list is sorted farthest-first, so the
	# head is the least-bad pick. The old code reassigned its answer on every
	# iteration of the scan and therefore returned the NEAREST point - it
	# materialised the enemy on top of the player, which is the one outcome the
	# whole function exists to prevent.
	return points.pop_front()


func _spawn(kind: String, at: Vector2, room_index: int) -> void:
	var enemy: Enemy = RouteBoss.new() if kind in RouteBoss.KINDS else ENEMY_SCENE.instantiate() as Enemy
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
	queue_redraw()
	_alive.erase(enemy)
	var index := int(enemy.get_meta("room", 0))
	_room_alive[index] = maxi(0, _room_alive[index] - 1)
	if _room_alive[index] == 0 and (_room_pending[index] as Array).is_empty():
		_room_cleared[index] = true
		room_cleared.emit(index)
		if index == _rune_room and not Game.run_over and not Profile.unlocked_runes.has(str(data["rune"])) and not is_instance_valid(rune_pickup):
			rune_pickup = PICKUP_SCRIPT.new()
			rune_pickup.item_id = str(data["rune"])
			# A fixed landing prevents an airborne kill leaving the Rune in stone.
			rune_pickup.position = (_rooms[index]["rect"] as Rect2).position + Vector2(320, -24)
			add_child(rune_pickup)


func _unhandled_input(event: InputEvent) -> void:
	if route_node.is_empty() or _cleared_emitted or Game.run_over or Game.run_phase != "biome":
		return
	if not Interface.pressed(event, &"interact"):
		return
	var player := _player()
	if player == null or player.hp <= 0.0:
		return
	var at := player.global_position
	var reach := float(Data.traversal["interact_reach"])
	for gate: Node in _gates.values():
		var rect: Rect2 = gate.spec["rect"]
		if not gate.unlocked and str(gate.spec["kind"]) == "key" and absf(at.x - rect.get_center().x) < reach and at.y >= rect.position.y and at.y < rect.end.y:
			get_viewport().set_input_as_handled()
			player.suppress_actions()
			if not gate.try_open():
				Game.announce(ContentText.of("UI_WORLD_NEED_KEY", "Need {key}").format({"key": key_name(str(gate.spec["key"]))}), 1.2)
			return
	for pad: Dictionary in data["pads"]:
		if at.distance_to(pad["pos"]) < reach:
			get_viewport().set_input_as_handled()
			player.suppress_actions()
			if str(pad["kind"]) == "checkpoint":
				map_requested.emit(true)
			else:
				if not teleport_to(str(pad["pair"]), str(pad["id"])):
					Game.announce(ContentText.of("UI_WORLD_PHASE_LANDING", "Phase Rune / safe landing required"), 1.2)
			return
	for exit: Dictionary in data["exits"]:
		if at.distance_to(exit["pos"]) < reach:
			get_viewport().set_input_as_handled()
			player.suppress_actions()
			var reason := Game.exit_reason(str(exit["to"]))
			if not reason.is_empty():
				Game.announce(ContentText.of("UI_WORLD_EXIT_LOCKED", "Locked") + ": " + ContentText.lock_reason(reason), 1.2)
				return
			_cleared_emitted = true
			exit_chosen.emit(str(exit["to"]))
			return


func _update_door(player: Player) -> void:
	if not route_node.is_empty():
		return
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


func vine_at(at: Vector2, descending := false) -> Rect2:
	for vine: Dictionary in data.get("vines", []):
		var rect: Rect2 = vine["rect"]
		if rect.has_point(at) and ((descending and at.y < rect.end.y - 24) or (not descending and at.y > rect.position.y + 36)):
			return rect
	return Rect2()


func checkpoint_near_player() -> String:
	var player := _player()
	if player == null:
		return ""
	for pad: Dictionary in data.get("pads", []):
		if str(pad["kind"]) == "checkpoint" and _active_pads.has(str(pad["id"])) and player.global_position.distance_to(pad["pos"]) < float(Data.traversal["interact_reach"]):
			return str(pad["id"])
	return ""


func safe_landing(at: Vector2) -> bool:
	var player := _player()
	if player == null:
		return false
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius = 14
	shape.height = 46
	query.shape = shape
	query.transform = Transform2D(0, at)
	query.collision_mask = Layers.WORLD | Layers.ONEWAY
	query.exclude = [player.get_rid()]
	if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	var ray := PhysicsRayQueryParameters2D.create(at + Vector2(0, 23), at + Vector2(0, 42), Layers.WORLD | Layers.ONEWAY, [player.get_rid()])
	return not get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


## Canonical travel gate. The map asks this before confirming and teleport_to
## asks it before moving, so the reason and the action cannot drift apart.
func teleport_refusal(id: String, source_id: String) -> String:
	var player := _player()
	if player == null or player.hp <= 0 or Game.run_over or Game.run_phase != "biome" or _cleared_emitted:
		return "RUN UNAVAILABLE"
	var source: Dictionary = {}
	var target: Dictionary = {}
	for pad: Dictionary in data.get("pads", []):
		if str(pad["id"]) == source_id:
			source = pad
		if str(pad["id"]) == id:
			target = pad
	if source.is_empty() or target.is_empty():
		return "UNKNOWN PAD"
	if source_id == id:
		return "SAME CHECKPOINT"
	if player.global_position.distance_to(source["pos"]) >= float(Data.traversal["interact_reach"]):
		return "TOO FAR"
	if str(source["kind"]) == "phase":
		if not Profile.unlocked_runes.has("phase_rune") or str(source["pair"]) != id:
			return "PHASE RUNE REQUIRED"
	else:
		if not _active_pads.has(source_id) or not _active_pads.has(id):
			return "TARGET NOT REACHED"
		if str(target["kind"]) != "checkpoint":
			return "TARGET NOT A TELEPORTER"
	if not safe_landing(target["pos"]):
		return "LANDING BLOCKED"
	return ""


func teleport_to(id: String, source_id: String) -> bool:
	var refusal := teleport_refusal(id, source_id)
	if not refusal.is_empty():
		return false
	var player := _player()
	for pad: Dictionary in data.get("pads", []):
		if str(pad["id"]) == id:
			player.relocate(pad["pos"])
			return true
	return false


func map_snapshot() -> Dictionary:
	var rooms: Array = []
	var ids: Array = []
	for i in _rooms.size():
		if _room_entered[i]:
			rooms.append({"id": str(_rooms[i]["id"]), "bounds": _rooms[i]["bounds"], "cleared": bool(_room_cleared[i])})
			ids.append(str(_rooms[i]["id"]))
	var edges: Array = []
	for edge: Dictionary in data.get("graph", []):
		if ids.has(str(edge["from"])) and ids.has(str(edge["to"])):
			edges.append({"from": str(edge["from"]), "to": str(edge["to"])})
	var pads: Array = []
	for pad: Dictionary in data.get("pads", []):
		if str(pad["kind"]) == "checkpoint" and _active_pads.has(str(pad["id"])):
			pads.append(pad.duplicate(true))
	var markers: Array = []
	for exit: Dictionary in data.get("exits", []):
		if ids.has(str(exit["room"])):
			markers.append({"pos": exit["pos"], "kind": "exit", "label": _exit_label(exit), "reason": Game.exit_reason(str(exit["to"]))})
	for pad: Dictionary in data.get("pads", []):
		if ids.has(str(pad["room"])) and (str(pad["kind"]) == "phase" or _active_pads.has(str(pad["id"]))):
			markers.append({"pos": pad["pos"], "kind": "phase" if str(pad["kind"]) == "phase" else "teleport", "label": _pad_label(str(pad["kind"])), "reason": ""})
	for gate: Node in _gates.values():
		if not gate.unlocked and ids.has(str(gate.spec["room"])):
			markers.append({"pos": (gate.spec["rect"] as Rect2).get_center(), "kind": "gate", "label": _gate_label(str(gate.spec["kind"])), "reason": _gate_reason(gate.spec)})
	if is_instance_valid(rune_pickup):
		markers.append({"pos": rune_pickup.position, "kind": "rune", "label": ContentText.of("UI_WORLD_MARK_RUNE_PICKUP", "Rune pickup").to_upper(), "reason": ""})
	return {"rooms": rooms, "edges": edges, "pads": pads, "markers": markers, "player": _player().global_position if _player() != null else Vector2.ZERO, "name": floor_name()}


## Display name of a world key, never its id. Shared with the pickup prompt.
static func key_name(id: String) -> String:
	return ContentText.name("key", id, str(KEY_NAME_EN.get(id, "")))


## Display name of a Rune, never its id.
static func rune_name(id: String) -> String:
	return ContentText.name("rune", id, str(RUNE_NAME_EN.get(id, "")))


## Map legend for a traversal pad.
func _pad_label(kind: String) -> String:
	return ContentText.of("UI_WORLD_MARK_PHASE", "Phase").to_upper() if kind == "phase" else ContentText.of("UI_WORLD_MARK_TELEPORT", "Teleport").to_upper()


## Map legend for a locked traversal gate.
func _gate_label(kind: String) -> String:
	return ContentText.of("UI_WORLD_MARK_KEY_DOOR", "Key door").to_upper() if kind == "key" else ContentText.of("UI_WORLD_MARK_BREAK_FLOOR", "Break floor").to_upper()


## The gate's reason is the Rune or key it wants, named for the player. A gate
## with neither stays empty rather than showing an id.
func _gate_reason(spec: Dictionary) -> String:
	var id := str(spec.get("key", spec.get("rune", "")))
	if id.is_empty():
		return ""
	return (key_name(id) if str(spec.get("kind")) == "key" else rune_name(id)).to_upper()


func _exit_label(exit: Dictionary) -> String:
	var id := str(exit["to"])
	if id.is_empty():
		return ContentText.of("UI_WORLD_MARK_VICTORY", "Victory").to_upper()
	var node: Dictionary = Data.route_graph["nodes"][id]
	return ContentText.name("biome", id, str(node["name"])).to_upper()


func _interaction_hint(at: Vector2) -> String:
	for gate: Node in _gates.values():
		if gate.unlocked or not (gate.spec["rect"] as Rect2).grow(float(Data.traversal["interact_reach"])).has_point(at):
			continue
		if str(gate.spec["kind"]) == "key":
			var key := str(gate.spec["key"])
			var key_label := key_name(key)
			return ContentText.of("UI_WORLD_HINT_OPEN_KEY", "{action} open / {key}").format({"action": Interface.prompt(&"interact"), "key": key_label}) if Game.run_keys.has(key) else ContentText.of("UI_WORLD_HINT_LOCKED_KEY", "Locked / {key}").format({"key": key_label})
		return ContentText.of("UI_WORLD_HINT_BREAK_FLOOR", "{jump}, then {drop} + {jump} to break").format({"jump": Interface.prompt(&"jump"), "drop": Interface.prompt(&"drop")}) if Profile.unlocked_runes.has(str(gate.spec["rune"])) else ContentText.of("UI_WORLD_HINT_GROUND_RUNE", "Ground Rune required")
	for exit: Dictionary in data.get("exits", []):
		if at.distance_to(exit["pos"]) < float(Data.traversal["interact_reach"]):
			var reason := Game.exit_reason(str(exit["to"]))
			return ContentText.of("UI_WORLD_HINT_ENTER_EXIT", "{action} to {target}").format({"action": Interface.prompt(&"interact"), "target": _exit_label(exit)}) if reason.is_empty() else ContentText.of("UI_WORLD_EXIT_LOCKED", "Locked") + ": " + ContentText.lock_reason(reason)
	for pad: Dictionary in data.get("pads", []):
		if at.distance_to(pad["pos"]) < float(Data.traversal["interact_reach"]):
			return ContentText.of("UI_WORLD_HINT_MAP", "{action} teleport map").format({"action": Interface.prompt(&"interact")}) if str(pad["kind"]) == "checkpoint" else ContentText.of("UI_WORLD_HINT_PHASE", "{action} phase / Phase Rune").format({"action": Interface.prompt(&"interact")})
	for vine: Dictionary in data.get("vines", []):
		if (vine["rect"] as Rect2).has_point(at):
			return ContentText.of("UI_WORLD_HINT_CLIMB", "{up} / {down} climb, {jump} leave").format({"up": Interface.prompt(&"climb_up"), "down": Interface.prompt(&"climb_down"), "jump": Interface.prompt(&"jump")}) if Profile.unlocked_runes.has("canopy_rune") else ContentText.of("UI_WORLD_HINT_CANOPY_RUNE", "Canopy Rune required")
	return ""


func _draw_biome() -> void:
	var font := MathArt.ui_font()
	for room: Dictionary in _rooms:
		var bounds: Rect2 = room["bounds"]
		MathArt.px_rect(self, bounds, _far)
		for i in 5:
			var x := bounds.position.x + float(i + 1) * bounds.size.x / (5.0 + MathArt.INV_PHI)
			MathArt.line(self, Vector2(x, bounds.position.y + 24), Vector2(x, bounds.end.y - 16), _near, 3)
		MathArt.line(self, bounds.position, Vector2(bounds.end.x, bounds.position.y), Color(_accent, 0.45), 2)
		for rect: Rect2 in room["ground"]:
			MathArt.px_rect(self, rect, _stone.darkened(0.20))
			MathArt.line(self, rect.position, Vector2(rect.end.x, rect.position.y), _edge, 3)
		var oneway: Array = room["oneway"]
		for i in (room["platforms"] as Array).size():
			_draw_platform(room["platforms"][i], bool(oneway[i]))
	for vine: Dictionary in data["vines"]:
		var rect: Rect2 = vine["rect"]
		var x := rect.get_center().x
		MathArt.line(self, Vector2(x, rect.position.y), Vector2(x, rect.end.y), MathArt.SURVIVAL, 2)
		for n in int(rect.size.y / (12.0 * MathArt.PHI)):
			var y := rect.position.y + float(n) * 12.0 * MathArt.PHI
			MathArt.line(self, Vector2(x - 10, y - 5), Vector2(x + 10, y + 5), MathArt.SURVIVAL, 2)
	for pad: Dictionary in data["pads"]:
		var at: Vector2 = pad["pos"]
		var shade := MathArt.TACTICS if str(pad["kind"]) == "phase" else (MathArt.CELL if _active_pads.has(str(pad["id"])) else MathArt.CELL.darkened(0.40))
		MathArt.ring(self, at, 24, shade, 2)
		MathArt.poly(self, MathArt.ngon(4 if str(pad["kind"]) == "phase" else 6, 24 * MathArt.INV_PHI, -PI * 0.5, at), Color.TRANSPARENT, shade, 2)
		draw_string(font, at + Vector2(-80, -42), _pad_label(str(pad["kind"])), HORIZONTAL_ALIGNMENT_CENTER, 160, 11, shade)
	for exit: Dictionary in data["exits"]:
		var at: Vector2 = exit["pos"]
		var reason := Game.exit_reason(str(exit["to"]))
		var shade := MathArt.ACCENT if reason.is_empty() else MathArt.DANGER
		MathArt.poly(self, MathArt.superellipse(24, 44, 4, 24, 0.0, at + Vector2(0, -20)), MathArt.INK, shade, 2)
		MathArt.line(self, at + Vector2(-18, -16), at + Vector2(18, -16), shade, 2)
		draw_string(font, at + Vector2(-150, -82), _exit_label(exit), HORIZONTAL_ALIGNMENT_CENTER, 300, 11, shade)
		if not reason.is_empty():
			draw_string(font, at + Vector2(-150, -64), ContentText.lock_reason(reason), HORIZONTAL_ALIGNMENT_CENTER, 300, 11, MathArt.MID)


# --- decoration -------------------------------------------------------------

func _palette() -> Dictionary:
	return _visual_palette


func _build_decoration() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed * 7919 + int(data.get("palette", 0)) * 131 + 17
	var pal := _palette()

	# Mass boundaries - room edges and the faces of every solid pillar or wall -
	# are where stress collects. Cracks are anchored to them (see below) so they
	# read as structure failing instead of as more noise.
	var edges: Array = []
	var lowest := 0.0
	for room in _rooms:
		var rr: Rect2 = room["rect"]
		edges.append(rr.position.x)
		edges.append(rr.end.x)
		lowest = maxf(lowest, rr.end.y)
		var platforms: Array = room["platforms"]
		var oneway: Array = room["oneway"]
		for j in platforms.size():
			if bool(oneway[j]):
				continue
			var pr: Rect2 = platforms[j]
			edges.append(pr.position.x)
			edges.append(pr.end.x)
	edges.sort()
	_near_y = lowest - 30.0

	for rect in _ground_sorted:
		var specks: Array = []
		for i in int(rect.size.x * float(pal["speck"])):
			specks.append(Vector3(
				rng.randf_range(rect.position.x + 2.0, rect.end.x - 2.0),
				rng.randf_range(rect.position.y + 6.0, rect.position.y + 96.0),
				rng.randf()))
		_specks.append(specks)
		var bounds: Array = []
		for edge in edges:
			if float(edge) > rect.position.x + 8.0 and float(edge) < rect.end.x - 8.0:
				bounds.append(edge)
		var cracks: Array = []
		for i in int(rect.size.x * float(pal["crack"])):
			var x := rng.randf_range(rect.position.x + 12.0, rect.end.x - 12.0)
			if not bounds.is_empty() and rng.randf() < 0.66:
				x = clampf(float(bounds[rng.randi_range(0, bounds.size() - 1)]) + rng.randf_range(-9.0, 9.0),
					rect.position.x + 8.0, rect.end.x - 8.0)
			cracks.append(Vector4(x, rng.randf_range(8.0, 40.0),
				rng.randf_range(4.0, 12.0), rng.randf()))
		_cracks.append(cracks)
		_strata.append(_foundation(rect, _is_terrace(rect), pal, rng))

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

	_build_shafts()
	_build_chains()


## A room's own terrace slab, as opposed to the continuous ledge under it. Only
## terraces get foundation detailing: the ledge is either covered by the slab or
## below the near plane.
func _is_terrace(rect: Rect2) -> bool:
	for room in _rooms:
		if (room["rect"] as Rect2) == rect:
			return true
	return false


## How one ground rect is built: courses that open up by φ, mortar joints
## staggered by the golden angle, a pilaster under each room edge and arched
## niches in the face. Everything is precomputed; _draw() only paints.
func _foundation(rect: Rect2, terrace: bool, pal: Dictionary, rng: RandomNumberGenerator) -> Array:
	var ops: Array = []
	var top := rect.position.y + 9.0
	var bottom := rect.end.y - 3.0
	var left := rect.position.x + 3.0
	var width := rect.size.x - 6.0
	var joint := float(pal["seam"]) * MathArt.PHI
	var step := maxf(float(pal["course"]), 8.0)
	var prev := top
	var y := top + step
	var row := 0
	while y < bottom - 6.0:
		ops.append({"k": "course", "r": Rect2(left, y, width, 1.0)})
		var x := left + 3.0 + joint * fposmod(float(row) * MathArt.GOLDEN_ANGLE, 1.0)
		while x < rect.end.x - 6.0:
			ops.append({"k": "joint", "r": Rect2(roundf(x), prev + 1.0, 1.0, maxf(y - prev - 2.0, 2.0))})
			x += joint
		prev = y
		step *= MathArt.PHI
		y += step
		row += 1

	if not terrace:
		return ops

	var face := bottom - top
	# Pilasters under the room edges: the corner the terrace is founded on.
	for side in 2:
		var px := rect.position.x + 2.0 if side == 0 else rect.end.x - 14.0
		ops.append({"k": "recess", "r": Rect2(px, top, 12.0, face)})
		ops.append({"k": "lit", "r": Rect2(px + (11.0 if side == 0 else 0.0), top, 1.0, face)})
		ops.append({"k": "lit", "r": Rect2(px - 1.0, top, 14.0, 2.0)})

	# Arched niches, keyed off the palette: the ember sources of the floor.
	var count := int(pal["niche"])
	for n in count:
		var nx := rect.position.x + rect.size.x * (0.34 + 0.32 * (float(n) + 0.5) / float(count))
		var nw := 30.0 + 10.0 * fposmod(float(n) * MathArt.INV_PHI, 1.0)
		var nh := 46.0 + 18.0 * fposmod(float(n) * MathArt.PHI, 1.0)
		var ny := rect.position.y + 30.0 + rng.randf_range(0.0, 22.0)
		var niche := PackedVector2Array()
		for i in 9:
			var angle := PI + PI * float(i) / 8.0
			niche.append(Vector2(nx + cos(angle) * nw * 0.5, ny + sin(angle) * nw * 0.5))
		niche.append(Vector2(nx + nw * 0.5, ny + nh))
		niche.append(Vector2(nx - nw * 0.5, ny + nh))
		ops.append({"k": "poly", "p": niche, "r": Rect2(nx, ny, nw, nh)})
		_niches.append(Vector2(nx, ny + nh * 0.5))
	return ops


## One light shaft per room that has a wide gallery deck: it starts at the vault
## ceiling and lands on that deck, so the upper route is lit from above instead
## of being a dark band nobody looks at.
func _build_shafts() -> void:
	for room in _rooms:
		var platforms: Array = room["platforms"]
		var oneway: Array = room["oneway"]
		var best := -1
		for j in platforms.size():
			if not bool(oneway[j]):
				continue
			var pr: Rect2 = platforms[j]
			if pr.size.x < 90.0:
				continue
			if best < 0 or pr.position.y < (platforms[best] as Rect2).position.y:
				best = j
		if best < 0:
			continue
		var deck: Rect2 = platforms[best]
		var shaft := {
			"x": deck.get_center().x, "half": minf(deck.size.x * 0.32, 44.0),
			"top": -620.0, "bottom": deck.position.y,
		}
		_shafts.append(shaft)
		# Permanent emitter, spawned once with the level, never from _draw().
		Juice.shaft_motes(self, Vector2(float(shaft["x"]), float(shaft["bottom"]) - 2.0),
			float(shaft["half"]) * 0.85,
			MathArt.PALE if _shafts.size() == 1 else MathArt.PALE_DIM,
			10 if _shafts.size() == 1 else 7, 3.4)


## Chains hang in the vault over each room, but only as far as that room's
## highest deck allows: a chain across a walkable edge would be the only thing
## on the floor competing with the bright line the player reads the route from.
func _build_chains() -> void:
	var hang := VaultHang.new()
	hang.name = "VaultHang"
	hang.niches = _niches
	for i in _rooms.size():
		var rect: Rect2 = _rooms[i]["rect"]
		var top_surface := rect.position.y
		for pr in (_rooms[i]["platforms"] as Array):
			top_surface = minf(top_surface, (pr as Rect2).position.y)
		# The chain must END INSIDE the frame. It used to be a fraction of the
		# whole vault height (55-77% of 406 px from y=-620), which put every
		# chain bottom at y=-397..-308 - above the top of the 480 px view at the
		# player's height, so the entire mid-ground ambience was drawn where
		# nobody could see it and the vault read as an empty black box.
		var top := -620.0
		for c in int(_palette()["chain"]):
			var bottom := top_surface - (96.0 + 44.0 * float(c))
			var len := bottom - top
			if len < 120.0:
				continue
			hang.chains.append({
				"x": rect.position.x + rect.size.x * (0.30 + 0.36 * float(c)),
				"top": top,
				"len": len,
				"phase": float(i) * MathArt.GOLDEN_ANGLE + float(c) * 1.7,
			})
	add_child(hang)


func _draw() -> void:
	if not route_node.is_empty():
		_draw_biome()
		return
	_draw_vault()
	_draw_monoliths()
	_draw_rose_window()
	for i in _ground_sorted.size():
		_draw_ground(_ground_sorted[i], _specks[i], _cracks[i])
		# In the same pass, so a later (raised) slab paints over the ledge's
		# detailing exactly where it stands on it.
		_draw_strata(i)
	# Two passes, not one: every pass-through deck first, then every solid mass.
	# The macro layer appends a pillar's step deck to the PREVIOUS room after that
	# room's authored tile is already in the list, so a single in-order pass drew
	# a bright plank on top of an authored mass it overlaps. Solids are what the
	# player reads as "you cannot pass", so they own the last word.
	for room in _rooms:
		var platforms: Array = room["platforms"]
		var oneway: Array = room["oneway"]
		for i in platforms.size():
			if not bool(oneway[i]):
				continue
			var pr: Rect2 = platforms[i]
			_draw_deck(pr)
			if _is_annex(pr):
				_draw_annex_floor(pr)
	for room in _rooms:
		var platforms: Array = room["platforms"]
		var oneway: Array = room["oneway"]
		for i in platforms.size():
			if bool(oneway[i]):
				continue
			var pr: Rect2 = platforms[i]
			if pr.size.y > 40.0:
				_draw_mass(pr)
			else:
				_draw_platform(pr)
	_draw_shaft_pools()
	_draw_near_plane()
	_draw_bounds()
	_draw_fog()


## The stone between the walkable line and the near plane: courses that open up
## by φ, mortar joints staggered off the golden angle, a pilaster under each
## room edge, arched niches.
func _draw_strata(index: int) -> void:
	for op in _strata[index]:
		match str(op["k"]):
			"course":
				MathArt.px_rect(self, op["r"], Color(MathArt.INK, 0.30))
			"joint":
				MathArt.px_rect(self, op["r"], Color(_stone.darkened(0.20), 0.55))
			"recess":
				MathArt.px_rect(self, op["r"], Color(MathArt.BLACK, 0.42))
			"lit":
				MathArt.px_rect(self, op["r"], Color(_edge, 0.22))
			"poly":
				MathArt.px_poly(self, op["p"], Color(MathArt.BLACK, 0.42),
					Color(_stone.darkened(0.20), 0.5), 1.0)


## Where a shaft meets its gallery deck. Drawn after the decks so the light
## lands on the stone instead of being buried behind it.
func _draw_shaft_pools() -> void:
	var alpha := float(_palette()["shaft"])
	for shaft in _shafts:
		var at := Vector2(float(shaft["x"]), float(shaft["bottom"]))
		var half: float = shaft["half"]
		MathArt.px_rect(self, Rect2(at.x - half * 1.5, at.y + 1.0, half * 3.0, 2.0),
			Color(_accent, alpha * 0.6))
		MathArt.glow(self, at - Vector2(0.0, 2.0), half * 1.3, Color(_accent, alpha), 3)


## The third plane: the mass closest to the camera. It gives the terraces
## something to stand on and closes the 340 px of ledge the old floor left as
## flat fill. Everything here stays dark - nothing may compete with the lit edge
## of the walkable stone.
func _draw_near_plane() -> void:
	if _rooms.is_empty():
		return
	var left := -120.0
	var width := float(data.get("width", 0.0)) + 240.0
	MathArt.px_rect(self, Rect2(left, _near_y, width, 42.0), Color(_near, 0.35))
	MathArt.px_rect(self, Rect2(left, _near_y + 42.0, width, 52.0), Color(_far, 0.55))
	MathArt.px_rect(self, Rect2(left, _near_y + 94.0, width, 300.0), Color(MathArt.INK, 0.88))
	# Parapet: teeth on a φ walk, so the silhouette never metronomes.
	var x := left
	while x < left + width:
		var t := fposmod(x * MathArt.INV_PHI * 0.01, 1.0)
		var h := 16.0 + 20.0 * t
		MathArt.px_rect(self, Rect2(x, _near_y - h, 22.0, h + 6.0), Color(_palette()["near"], 0.85))
		MathArt.px_rect(self, Rect2(x, _near_y - h, 22.0, 1.0), Color(_stone.darkened(0.20), 0.45))
		x += 30.0 + 14.0 * fposmod(t * MathArt.PHI, 1.0)


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
	# The wall has to reach the WALKABLE LINE, not a fixed y. It used to stop at
	# y=60 while the ledge is at BASE_Y=150, which left a 90 px stripe of bare
	# background directly above the floor: the room read as a floating slab with
	# a black hole behind it, and the arches (which are anchored to the floor)
	# were the only thing poking into view.
	var floor_line := LevelGen.BASE_Y + 24.0
	MathArt.px_rect(self, Rect2(-40.0, -depth, width + 80.0, depth + floor_line),
		Color(pal["vault"], 0.95))
	# Value gradient: the vault is brightest at the top, where the light enters,
	# and falls off toward the floor. Six bands is enough to read as depth and
	# cheap enough to redraw. Without it the far wall is one flat value and the
	# eye cannot tell how deep the room is.
	var bands := 6
	var band_h := (depth + floor_line) / float(bands)
	for b in bands:
		var t := float(b) / float(bands - 1)
		MathArt.px_rect(self, Rect2(-40.0, -depth + band_h * float(b), width + 80.0, band_h + 1.0),
			Color(MathArt.BLACK, 0.16 * t * t))
	# Courses 22 px apart. This is the only thing that gives the wall scale.
	var y := -depth
	var row := 0
	while y < floor_line:
		MathArt.px_rect(self, Rect2(-40.0, y, width + 80.0, 1.0),
			Color(MathArt.MID, 0.09 if row % 2 == 0 else 0.05))
		# Staggered vertical joints: a course line alone reads as scanlines, a
		# brick offset reads as masonry.
		var bx := -40.0 + (26.0 if row % 2 == 0 else 0.0)
		while bx < width + 40.0:
			MathArt.px_rect(self, Rect2(bx, y, 1.0, 22.0), Color(MathArt.MID, 0.045))
			bx += 52.0
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
			Color(_near, 0.80))
		MathArt.px_rect(self, Rect2(x, foot - depth, 1.0, depth),
			Color(_edge, 0.20))
		MathArt.px_rect(self, Rect2(x + 10.0, foot - depth, 1.0, depth),
			Color(MathArt.INK, 0.5))
		var half := (step - 11.0) * 0.5
		var cx := x + 11.0 + half
		var top := foot - rise
		# Recessed panel in the jamb region of the bay: what makes the far wall a
		# colonnade at a distance instead of a flat plane at any distance.
		# Recessed panel in the jamb region of the bay. Now that the wall behind
		# it carries a real value, the recess must be a NICHE (a dark void with a
		# lit top lip and a shadow under the sill) and not a flat black rectangle
		# - at full strength the old panels read as holes punched through to
		# nothing, which is what made the mid-ground look unfinished.
		var panel := float(pal["panel"])
		if panel > 0.01 and foot - 26.0 - (top + half + 16.0) > 40.0:
			var ptop := top + half + 16.0
			var pw := step - 70.0
			var ph := foot - 26.0 - ptop
			MathArt.px_rect(self, Rect2(cx - pw * 0.5, ptop, pw, ph),
				Color(MathArt.BLACK, panel * 0.55))
			# Lit top lip: the surface the light in the room would catch.
			MathArt.px_rect(self, Rect2(cx - pw * 0.5, ptop, pw, 2.0),
				Color(_accent, 0.10 + panel * 0.06))
			# Inner side shadows, so the niche has a wall thickness.
			MathArt.px_rect(self, Rect2(cx - pw * 0.5, ptop, 2.0, ph), Color(MathArt.BLACK, 0.30))
			MathArt.px_rect(self, Rect2(cx + pw * 0.5 - 2.0, ptop, 2.0, ph), Color(MathArt.BLACK, 0.30))
			# Sill.
			MathArt.px_rect(self, Rect2(cx - pw * 0.5 - 2.0, foot - 27.0, pw + 4.0, 2.0),
				Color(_stone.darkened(0.20), 0.55))
			MathArt.px_rect(self, Rect2(cx - pw * 0.5 - 2.0, foot - 25.0, pw + 4.0, 1.0),
				Color(MathArt.BLACK, 0.45))
		# Two quarter-arcs meeting at the apex, then the jambs down to the floor.
		# Structure has to survive the value gradient above it: at 0.10 alpha
		# over a near-black wall the colonnade was invisible and the whole vault
		# read as flat black in the captures.
		MathArt.arc(self, Vector2(cx - half, top + half), half, -PI * 0.5, 0.0,
			Color(MathArt.MID, 0.22), 1.0)
		MathArt.arc(self, Vector2(cx + half, top + half), half, PI, PI * 1.5,
			Color(MathArt.MID, 0.22), 1.0)
		MathArt.px_rect(self, Rect2(cx - half, top + half, 1.0, foot - top - half),
			Color(MathArt.MID, 0.16))
		MathArt.px_rect(self, Rect2(cx + half, top + half, 1.0, foot - top - half),
			Color(MathArt.MID, 0.16))
		# Keystone: the one lit point per bay, so the colonnade has rhythm.
		MathArt.px_rect(self, Rect2(cx - 2.0, top - 1.0, 5.0, 3.0),
			Color(_accent, 0.14))
		x += step

	# Light shafts through the height of the room: three nested trapezoids a 1/φ
	# apart, which is what gives a hard-edged polygon a soft horizontal falloff,
	# and each lands on the gallery deck the upper route runs along.
	for shaft in _shafts:
		var sx: float = shaft["x"]
		var stop: float = shaft["top"]
		var sbot: float = shaft["bottom"]
		var shalf: float = shaft["half"]
		for tier in 3:
			var half := shalf * pow(MathArt.INV_PHI, float(tier))
			MathArt.poly(self, PackedVector2Array([
				Vector2(sx - half * MathArt.INV_PHI, stop), Vector2(sx + half * MathArt.INV_PHI, stop),
				Vector2(sx + half, sbot), Vector2(sx - half, sbot)]),
				Color(_accent, float(pal["shaft"]) * (1.0 + float(tier) * 0.5)))

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
		# A monolith runs from the vault down to its room's slab, so it cuts
		# straight through an annex chamber hanging above that slab. Skip any
		# column that would stand in one: the annex is the floor's destination and
		# a 30 px dark bar through it reads as unfinished geometry.
		if _in_annex_span(x, width):
			continue
		var top: float = column["top"]
		var bottom: float = column["bottom"]
		var height := bottom - top
		if height <= 4.0:
			continue
		MathArt.px_rect(self, Rect2(x, top, width, height), Color(_near, 0.72))
		MathArt.px_rect(self, Rect2(x + width - 3.0, top, 3.0, height), Color(MathArt.INK, 0.72))
		MathArt.px_rect(self, Rect2(x + 2.0, top, 1.0, height), Color(_edge, 0.24))
		var cap := MathArt.ngon(6, width * 0.5, 0.0, Vector2(x + width * 0.5, top))
		MathArt.px_poly(self, cap, Color(_far, 0.85), Color(_edge, 0.45), 1.0)
		if bool(column["sigil"]):
			var center := Vector2(x + width * 0.5, top + 110.0)
			MathArt.px_poly(self, MathArt.ngon(6, width * 0.30, PI / 6.0, center),
				Color(0, 0, 0, 0), Color(_accent, 0.16), 1.0)
			MathArt.px_ring(self, center, width * 0.46, Color(_accent, 0.09), 1.0)


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
	MathArt.px_rect(self, rect, _stone)
	MathArt.px_rect(self, Rect2(rect.position, Vector2(rect.size.x, 3.0)), edge)
	MathArt.px_rect(self, Rect2(rect.position + Vector2(0, 3), Vector2(rect.size.x, 1.0)),
		Color(MathArt.MID_DIM, 0.35))

	for speck in specks:
		var shade: float = speck.z
		if shade > 0.80:
			MathArt.px_rect(self, Rect2(speck.x, speck.y, 1, 1), Color(_edge, 0.45))
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
		Color(_accent, 0.10))


## A pass-through deck: thin, bright top edge, and a dashed under-edge. The
## dashes are the whole point - they are the only cue that says "you can jump
## up through this one".
func _draw_deck(rect: Rect2) -> void:
	var pal := _palette()
	MathArt.px_rect(self, Rect2(rect.position, Vector2(rect.size.x, rect.size.y)),
		Color(_edge, 0.92))
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
			rect.position.y + 2.0, 1, 3.0), Color(_accent, 0.20))


## A thick solid mass: a pillar, a lip or a vault floor. Reads as stone, not as
## something you can slip through.
func _draw_mass(rect: Rect2) -> void:
	var pal := _palette()
	MathArt.px_rect(self, rect, Color(_stone, 0.96))
	MathArt.px_rect(self, Rect2(rect.position, Vector2(rect.size.x, 3.0)), pal["edge"])
	MathArt.px_rect(self, Rect2(rect.position + Vector2(rect.size.x - 3.0, 0), Vector2(3.0, rect.size.y)),
		Color(MathArt.INK, 0.55))
	MathArt.px_rect(self, Rect2(rect.position + Vector2(1.0, 3.0), Vector2(1.0, rect.size.y - 3.0)),
		Color(_edge, 0.22))
	var y := rect.position.y + 14.0
	var row := 0
	while y < rect.end.y - 6.0:
		var offset := 0.0 if row % 2 == 0 else 18.0
		var x := rect.position.x + 8.0 + offset
		while x < rect.end.x - 10.0:
			MathArt.px_rect(self, Rect2(roundf(x), roundf(y), 1.0, 1.0),
				Color(_stone.darkened(0.20), 0.5))
			x += 36.0
		y += 16.0
		row += 1


## Is this surface one of the floor's annex chambers (or the landing below one)?
## The annex is the reward for the climb, so it has to look like a place: an
## ordinary 13 px deck made it read as one more rung of scaffolding.
func _is_annex(rect: Rect2) -> bool:
	for entry in (data.get("annex_floors", []) as Array):
		var r: Rect2 = entry
		if absf(r.position.x - rect.position.x) < 0.5 and absf(r.position.y - rect.position.y) < 0.5:
			return true
	return false


func _in_annex_span(x: float, width: float) -> bool:
	for entry in (data.get("annex_floors", []) as Array):
		var r: Rect2 = entry
		if r.size.y > 40.0:
			continue
		if x + width > r.position.x - 12.0 and x < r.end.x + 12.0:
			return true
	return false


func _draw_annex_floor(rect: Rect2) -> void:
	# A lit band, a bright front lip and two braced brackets: the same value
	# language as a station plinth in the hub, so "this is somewhere" is already
	# learned before the player reaches one.
	MathArt.px_rect(self, Rect2(rect.position.x, rect.position.y + rect.size.y - 1.0,
		rect.size.x, 4.0), Color(_edge, 0.85))
	MathArt.px_rect(self, Rect2(rect.position.x, rect.position.y + 2.0, rect.size.x, 1.0),
		Color(_accent, 0.55))
	for side in 2:
		var bx := rect.position.x + 3.0 if side == 0 else rect.end.x - 5.0
		MathArt.px_rect(self, Rect2(bx, rect.position.y + rect.size.y, 2.0, 8.0),
			Color(_edge, 0.7))


func _draw_platform(rect: Rect2, oneway := false) -> void:
	var pal := _palette()
	MathArt.px_rect(self, rect, _stone)
	MathArt.px_rect(self, Rect2(rect.position, Vector2(rect.size.x, 2.0)), pal["edge"])
	MathArt.px_rect(self, Rect2(rect.position + Vector2(0, 2), Vector2(rect.size.x, 1.0)),
		Color(MathArt.MID_DIM, 0.25))
	if oneway:
		# A broken underside against a solid stone body is the shape cue; colour
		# only reinforces it. The bright top edge still reads as standable.
		var x := rect.position.x
		var bottom := rect.position.y + rect.size.y - 1.0
		while x < rect.end.x:
			var run := minf(7.0, rect.end.x - x)
			MathArt.px_rect(self, Rect2(roundf(x), bottom, run, 1.0), Color(MathArt.INK, 0.85))
			MathArt.px_rect(self, Rect2(roundf(x), rect.position.y + rect.size.y, run, 1.0),
				Color(_accent, 0.22))
			x += 13.0
	else:
		MathArt.px_rect(self, Rect2(rect.position + Vector2(0, rect.size.y - 2.0), Vector2(rect.size.x, 2.0)),
			Color(MathArt.INK, 0.8))
	for fraction in [0.0, MathArt.INV_PHI * MathArt.INV_PHI, MathArt.INV_PHI, 1.0]:
		MathArt.px_rect(self, Rect2(roundf(rect.position.x + rect.size.x * float(fraction)),
			rect.position.y + 2.0, 1, 4.0), Color(_accent, 0.16))
	var seam := rect.position.x + 24.0
	while seam < rect.end.x - 10.0:
		MathArt.px_rect(self, Rect2(roundf(seam), rect.position.y + 3.0, 1, rect.size.y - 5.0),
			Color(MathArt.INK, 0.35))
		seam += float(pal["seam"])


func _draw_bounds() -> void:
	var right := float(data.get("width", 0.0))
	for x in [-WALL_W, right]:
		MathArt.px_rect(self, Rect2(x, WALL_TOP, WALL_W, WALL_H), _stone)
		MathArt.px_rect(self, Rect2(x, WALL_TOP, 2.0, WALL_H), Color(_edge, 0.22))
		MathArt.px_rect(self, Rect2(x, WALL_TOP, WALL_W, 2.0), Color(_edge, 0.45))


func _draw_fog() -> void:
	var bands := int(_palette()["fog"])
	for room in _rooms:
		var rect: Rect2 = room["rect"]
		var x := rect.position.x + 60.0
		while x < rect.end.x - 60.0:
			for band in bands:
				var width := 90.0 - float(band) * 22.0
				MathArt.px_rect(self, Rect2(x - width * 0.5, rect.position.y - 20.0 + float(band) * 5.0, width, 3.0),
					Color(_stone.darkened(0.20), 0.05))
			x += 420.0
