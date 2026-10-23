class_name Hub
extends Node2D
## The lobby: a walkable floor, six stations and a descent door. Interaction is
## proximity + J so the hub never becomes a menu; the panels live in HubUi.

signal station_opened(id: String)
signal station_closed
signal descend_requested(floor_index: int)

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const WIDTH := 1600.0
const DOOR_X := 1560.0
const REACH := 70.0

# One row per station: a new station is data, not a new draw function.
# One station per screen. BESTIARY / WEAPONS / ARMOR are tabs inside a single
# ARCHIVES screen: three separate doors into one three-tab panel meant every
# door could reach all three, which made the hub look broken.
const STATIONS := [
	{"id": "upgrade", "name": "UPGRADES", "x": 210.0, "sides": 6, "inner": "star"},
	{"id": "skill", "name": "SKILLS", "x": 520.0, "sides": 3, "inner": "spiral"},
	{"id": "archive", "name": "ARCHIVES", "x": 830.0, "sides": 5, "inner": "rose"},
	{"id": "character", "name": "CHARACTER", "x": 1140.0, "sides": 10, "inner": "lissajous"},
]

## Highest floor the player has unlocked (0 = nothing cleared yet).
var floor_available := 0
## Which floor the door will send them to. Starts at the NEXT unvisited floor,
## not the last one reached: sending the player back to floor 1 forever was the
## bug that made every run "floor 1 again".
var floor_target := 1
var ui: HubUi
var player: Player

var _near := -1
var _near_door := false
var _t := 0.0
var _motes: Array[Vector3] = []


func _ready() -> void:
	_build_walls()
	_build_player()
	ui = HubUi.new()
	ui.name = "HubUi"
	add_child(ui)
	ui.closed.connect(_on_panel_closed)
	for i in 46:
		var spot := MathArt.phyllotaxis(i + 1, 40.0)
		_motes.append(Vector3(
			clampf(800.0 + spot.x * 2.2, -30.0, WIDTH + 30.0),
			clampf(-130.0 + spot.y * 1.1, -410.0, -14.0),
			float(i) * 0.63))


## How far the player may descend; 0 means a fresh profile (first floor).
func setup(available: int) -> void:
	floor_available = maxi(0, available)
	# best_floor is the deepest floor REACHED, so the next one is +1.
	floor_target = clampi(floor_available + 1, 1, maxi(1, Data.floors.size()))
	queue_redraw()


## The door is also a floor picker: left/right steps through every floor the
## player has already unlocked, so a late-game player can farm an earlier one.
func _step_floor(delta: int) -> void:
	var top := clampi(floor_available + 1, 1, maxi(1, Data.floors.size()))
	var next := clampi(floor_target + delta, 1, top)
	if next == floor_target:
		return
	floor_target = next
	Sfx.play("ui", -16)
	queue_redraw()


func is_open() -> bool:
	return ui != null and ui.is_open()


# ------------------------------------------------------------------- building

func _build_walls() -> void:
	for rect: Rect2 in [
		Rect2(-60.0, 0.0, WIDTH + 120.0, 160.0),
		Rect2(-60.0, -700.0, 40.0, 700.0),
		Rect2(WIDTH + 20.0, -700.0, 40.0, 700.0),
	]:
		var body := StaticBody2D.new()
		body.collision_layer = Layers.WORLD
		body.collision_mask = 0
		body.position = rect.position + rect.size * 0.5
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		body.add_child(shape)
		add_child(body)


func _build_player() -> void:
	player = PLAYER_SCENE.instantiate() as Player
	player.position = Vector2(110.0, -40.0)
	add_child(player)
	Game.fx_root = self
	# The arena camera is framed for combat; the hub is one long flat floor with
	# a tall vault above it, so the limits are wider than 768x480 on purpose.
	player.camera.limit_left = -20
	player.camera.limit_right = int(WIDTH + 20.0)
	player.camera.limit_top = -420
	player.camera.limit_bottom = 200


# --------------------------------------------------------------------- update

func _process(delta: float) -> void:
	_t += delta
	if is_open():
		return
	var best := REACH
	_near = -1
	for i in STATIONS.size():
		var distance := absf(player.position.x - float(STATIONS[i]["x"]))
		if distance < best:
			best = distance
			_near = i
	_near_door = absf(player.position.x - DOOR_X) < REACH
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if is_open():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _near_door and event.physical_keycode in [KEY_LEFT, KEY_A]:
		_step_floor(-1)
		get_viewport().set_input_as_handled()
		return
	if _near_door and event.physical_keycode in [KEY_RIGHT, KEY_D]:
		_step_floor(1)
		get_viewport().set_input_as_handled()
		return
	if not (event.physical_keycode in [KEY_J, KEY_ENTER, KEY_KP_ENTER]):
		return
	if _near_door:
		Sfx.play("wave", -12)
		descend_requested.emit(floor_target)
	elif _near >= 0:
		_open_station(_near)
	else:
		return
	get_viewport().set_input_as_handled()


func _open_station(index: int) -> void:
	# J is also the attack button: freeze the body and clear the swing so the
	# player is not frozen mid-windup behind the panel.
	player.set_physics_process(false)
	player.state = Player.State.IDLE
	player.velocity = Vector2.ZERO
	# The station emits and lets the owner decide which screen to raise. Some
	# panels live in HubUi, the archives and the skill tree are their own
	# layers, so routing here would raise two panels at once.
	var id := str(STATIONS[index]["id"])
	station_opened.emit(id)
	queue_redraw()


## Called by the owner when an external screen (archive, skill tree) closes.
func close_station() -> void:
	_on_panel_closed()


func _on_panel_closed() -> void:
	player.set_physics_process(true)
	station_closed.emit()
	queue_redraw()


# ---------------------------------------------------------------------- draw

func _draw() -> void:
	if ThemeDB.fallback_font == null:
		return

	MathArt.px_rect(self, Rect2(-400.0, -900.0, WIDTH + 800.0, 1020.0), MathArt.BG_0)
	# The vault above the hub: same value range as the arena vignette.
	for i in 6:
		MathArt.px_rect(self, Rect2(-400.0, -420.0 + float(i) * 46.0, WIDTH + 800.0, 46.0),
			Color(MathArt.INK, 0.34 - float(i) * 0.055))

	for i in _motes.size():
		var mote := _motes[i]
		var alpha := 0.10 + 0.16 * (0.5 + 0.5 * sin(_t * 1.1 + mote.z))
		var point := Vector2(mote.x, mote.y + sin(_t * 0.6 + mote.z) * 4.0)
		MathArt.px_rect(self, Rect2(point.x, point.y, 1.0, 1.0), Color(MathArt.PALE, alpha))

	_draw_floor()

	for i in STATIONS.size():
		_draw_station(i)
	_draw_door()


func _draw_floor() -> void:
	MathArt.px_rect(self, Rect2(-60.0, 0.0, WIDTH + 120.0, 320.0), MathArt.BG_2)
	MathArt.px_rect(self, Rect2(-60.0, 0.0, WIDTH + 120.0, 3.0), MathArt.STONE_HI)
	MathArt.px_rect(self, Rect2(-60.0, 3.0, WIDTH + 120.0, 1.0), Color(MathArt.BG_0, 0.9))
	var x := 0.0
	while x < WIDTH:
		var long := int(x / 72.0) % 3 == 0
		MathArt.px_line(self, Vector2(x, 4.0), Vector2(x, 4.0 + (11.0 if long else 6.0)),
			Color(MathArt.STONE, 0.9), 1.0)
		if long:
			MathArt.px_rect(self, Rect2(x - 1.0, 20.0, 2.0, 2.0), Color(MathArt.STONE_HI, 0.7))
		x += 72.0
	# Strata: flat value steps give the floor depth without a texture.
	for i in 5:
		MathArt.px_rect(self, Rect2(-60.0, 26.0 + float(i) * 24.0, WIDTH + 120.0, 1.0),
			Color(MathArt.STONE, 0.62 - float(i) * 0.11))
	# Debris is phyllotaxis, not random: same floor every visit.
	for i in 40:
		var spot := MathArt.phyllotaxis(i + 1, 30.0)
		var point := Vector2(780.0 + spot.x * 1.7, 6.0 + absf(spot.y) * 0.8)
		if point.x > 0.0 and point.x < WIDTH:
			MathArt.px_rect(self, Rect2(point.x, fmod(point.y, 116.0), 1.0, 1.0),
				Color(MathArt.STONE_HI, 0.30))


func _draw_station(index: int) -> void:
	var station: Dictionary = STATIONS[index]
	var x := float(station["x"])
	var bright := index == _near
	var tint := MathArt.PALE if bright else MathArt.STONE_HI
	var base := Vector2(x, 0.0)
	if bright:
		MathArt.glow(self, base + Vector2(0.0, -34.0), 54.0, MathArt.PALE, 5)

	# Plinth: a prism pedestal, wider than the column it carries.
	var plinth := PackedVector2Array([
		base + Vector2(-22.0, 0.0), base + Vector2(-15.0, -8.0),
		base + Vector2(15.0, -8.0), base + Vector2(22.0, 0.0),
	])
	MathArt.px_poly(self, plinth, Color(MathArt.BG_2, 0.9), tint, 1.0)

	# Column: cap polygon plus the two extreme verticals, so any n reads as a prism.
	var cap := MathArt.ngon(int(station["sides"]), 13.0, 0.0, base + Vector2(0.0, -60.0))
	MathArt.px_poly(self, cap, Color(MathArt.BG_1, 0.85), tint, 1.0)
	var left := 0
	var right := 0
	for i in cap.size():
		if cap[i].x < cap[left].x:
			left = i
		if cap[i].x > cap[right].x:
			right = i
	MathArt.px_line(self, cap[left], Vector2(cap[left].x, -8.0), tint, 1.0)
	MathArt.px_line(self, cap[right], Vector2(cap[right].x, -8.0), tint, 1.0)
	MathArt.px_line(self, Vector2(cap[left].x, -8.0), Vector2(cap[right].x, -8.0), Color(tint, 0.5), 1.0)

	_draw_inner(str(station["inner"]), base + Vector2(0.0, -32.0), tint, bright)

	draw_string(ThemeDB.fallback_font, Vector2(x - 70.0, -84.0), str(station["name"]),
		HORIZONTAL_ALIGNMENT_CENTER, 140.0, 9, tint)
	if bright:
		draw_string(ThemeDB.fallback_font, Vector2(x - 20.0, 22.0), "[J]",
			HORIZONTAL_ALIGNMENT_CENTER, 40.0, 9, Color(MathArt.WHITE, 0.55 + 0.45 * sin(_t * 4.0)))


## The slowly rotating figure inside each monolith: this is what makes a
## station read as alive from across the floor.
func _draw_inner(kind: String, pivot: Vector2, tint: Color, bright: bool) -> void:
	var ink := Color(tint, 0.95 if bright else 0.8)
	match kind:
		"star":
			MathArt.px_poly(self, MathArt.star(5, 11.0, 4.4, _t * 0.4 - PI * 0.5, pivot), Color(0, 0, 0, 0), ink, 1.0)
		"spiral":
			MathArt.spiral_line(self, pivot, 11.0, 1.5, ink, 1.0, 32, _t * 0.3)
		"blade":
			MathArt.px_poly(self, MathArt.ngon(3, 11.0, _t * 0.7 - PI * 0.5, pivot), Color(0, 0, 0, 0), ink, 1.0)
		"ring":
			MathArt.px_ring(self, pivot, 10.0, ink, 1.0, 20)
			MathArt.px_ring(self, pivot, 10.0 * MathArt.INV_PHI, Color(ink, 0.6), 1.0, 16)
			for i in 6:
				var angle := _t * 0.6 + TAU * float(i) / 6.0
				MathArt.px_rect(self, Rect2(pivot + Vector2.from_angle(angle) * 10.0, Vector2(1.0, 1.0)), ink)
		"rose":
			var rose := PackedVector2Array()
			for i in 41:
				rose.append(pivot + MathArt.rose(TAU * float(i) / 40.0 + _t * 0.25, 3.0, 11.0))
			MathArt.px_poly(self, rose, Color(0, 0, 0, 0), ink, 1.0)
		_:
			var loop := PackedVector2Array()
			for i in 41:
				loop.append(pivot + MathArt.lissajous(TAU * float(i) / 40.0 + _t * 0.5, 3.0, 2.0, PI * 0.5) * 9.0)
			MathArt.px_poly(self, loop, Color(0, 0, 0, 0), ink, 1.0)


func _draw_door() -> void:
	var bright := _near_door
	var tint := MathArt.WHITE if bright else MathArt.STONE_HI
	var foot := Vector2(DOOR_X, 0.0)
	if bright:
		MathArt.glow(self, foot + Vector2(0.0, -46.0), 62.0, MathArt.PALE, 5)

	MathArt.px_rect(self, Rect2(DOOR_X - 21.0, -84.0, 7.0, 84.0), Color(MathArt.BG_2, 0.95))
	MathArt.px_rect(self, Rect2(DOOR_X + 14.0, -84.0, 7.0, 84.0), Color(MathArt.BG_2, 0.95))
	MathArt.px_poly(self, PackedVector2Array([
		Vector2(DOOR_X - 21.0, -84.0), Vector2(DOOR_X - 14.0, -84.0),
		Vector2(DOOR_X - 14.0, 0.0), Vector2(DOOR_X - 21.0, 0.0),
	]), Color(0, 0, 0, 0), tint, 1.0)
	MathArt.px_poly(self, PackedVector2Array([
		Vector2(DOOR_X + 14.0, -84.0), Vector2(DOOR_X + 21.0, -84.0),
		Vector2(DOOR_X + 21.0, 0.0), Vector2(DOOR_X + 14.0, 0.0),
	]), Color(0, 0, 0, 0), tint, 1.0)
	MathArt.arc(self, Vector2(DOOR_X, -84.0), 17.5, PI, TAU, tint, 1.5)

	# Light in the doorway is the only thing on the door that moves.
	var pulse := 0.5 + 0.5 * sin(_t * 2.2)
	MathArt.px_rect(self, Rect2(DOOR_X - 3.0, -80.0, 6.0, 80.0), Color(MathArt.PALE, 0.08 + pulse * 0.16))

	var font := ThemeDB.fallback_font
	var top := clampi(floor_available + 1, 1, maxi(1, Data.floors.size()))
	var floor_data: Dictionary = Data.floors.get(str(floor_target), {})
	draw_string(font, Vector2(DOOR_X - 70.0, -120.0), "FLOOR %d / %d" % [floor_target, top],
		HORIZONTAL_ALIGNMENT_CENTER, 140.0, 8, Color(tint, 0.75))
	draw_string(font, Vector2(DOOR_X - 90.0, -105.0), str(floor_data.get("name", "")),
		HORIZONTAL_ALIGNMENT_CENTER, 180.0, 9, tint)
	if bright:
		draw_string(font, Vector2(DOOR_X - 20.0, 22.0), "[J]",
			HORIZONTAL_ALIGNMENT_CENTER, 40.0, 9, Color(MathArt.WHITE, 0.55 + 0.45 * sin(_t * 4.0)))
		if top > 1:
			draw_string(font, Vector2(DOOR_X - 70.0, 36.0), "< A    D >",
				HORIZONTAL_ALIGNMENT_CENTER, 140.0, 8, Color(MathArt.LIGHT, 0.6))
