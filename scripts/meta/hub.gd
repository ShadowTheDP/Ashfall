class_name Hub
extends Node2D
## The lobby: a walkable floor, four stations and a descent door. Interaction is
## proximity + J so the hub never becomes a menu; the panels live in HubUi.
##
## The drawing is built as three value planes so the hall reads as a room with
## depth rather than a platform with panels on it:
##   far   -- a dark vault, an arcade of piers and a rose window (MathArt.INK /
##            BG_0), plus hanging chains and braziers;
##   mid   -- a lit wall band carrying the monument row (BG_1 against STONE_HI
##            and PALE: the player square must still be the first thing seen);
##   near  -- black columns standing in the gaps between stations and a floor
##            that falls to black toward the camera.
## Every static shape is built once in _build_vault(); _draw() only iterates.

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

# --- Composition -------------------------------------------------------------
# The hub camera (zoom 0.86, limits set in _build_player) shows y = -358..200, so
# the vault owns the top 60% of the frame. Every band below is placed against
# that window; y = 0 is the walkable line.
const VAULT_TOP := -420.0
const BEAM_BOTTOM := -336.0
const ARCADE_BASE := -156.0
const PIER_TOP := -300.0
const CHAIN_TOP := -410.0
const CHAIN_SAMPLES := 8
const CHAIN_X := [395.0, 700.0, 1010.0, 1345.0]
## Rose window: sits in the wide bay above the ARCHIVES monument, so the beam it
## throws lands on the floor in the middle of the hall.
const ROSE_AT := Vector2(818.0, -286.0)
const ROSE_R := 50.0
## Near-plane columns, placed in the gaps between stations so no label is cut.
const FOREGROUND_X := [30.0, 366.0, 675.0, 985.0, 1310.0]

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
var _ember_t := 0.0
var _ember_slot := 0

# Static geometry. _draw() reads these; only the chains are written in place.
var _motes: Array[Vector3] = []
var _pier: PackedFloat32Array = []
var _bay: PackedVector2Array = []          # (mid x, half width) per arcade bay
var _chain_x: PackedFloat32Array = []
var _chain_len: PackedFloat32Array = []
var _chain_pts := PackedVector2Array()     # every chain concatenated, CHAIN_SAMPLES each
var _joint: PackedFloat32Array = []        # floor joints, φ-spaced toward the camera
var _paving: PackedVector2Array = []       # paving tick (x, y)
var _medallion: Array[PackedVector2Array] = []  # floor inlay: 2 rings per station
var _beam: Array[PackedVector2Array] = []       # light shaft trapezoids, 3 per shaft
var _beam_alpha: PackedFloat32Array = []
var _pool_x: PackedFloat32Array = []
var _pool_half: PackedFloat32Array = []
var _scratch := PackedVector2Array()       # 41 points, reused by the animated figures


func _ready() -> void:
	_build_walls()
	_build_vault()
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
	_spawn_ambience()


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


## Builds every static shape once. _draw() runs every frame, so it must never
## construct geometry: this is the only place arrays are appended to.
func _build_vault() -> void:
	_scratch.resize(41)
	# Arcade bays alternate 104 / 168 (φ apart) so the rhythm never metronomes.
	var x := -50.0
	var bay := 104.0
	while x < WIDTH + 80.0:
		_pier.append(x)
		_bay.append(Vector2(x + bay * 0.5, bay * 0.5))
		x += bay
		bay = 168.0 if bay < 130.0 else 104.0
	# Chains hang over the gaps between stations, at two lengths a φ apart.
	for i in CHAIN_X.size():
		_chain_x.append(CHAIN_X[i])
		_chain_len.append(146.0 if i % 2 == 0 else 196.0)
	_chain_pts.resize(CHAIN_X.size() * CHAIN_SAMPLES)
	for i in _chain_x.size():
		for j in CHAIN_SAMPLES:
			_chain_pts[i * CHAIN_SAMPLES + j] = Vector2(_chain_x[i], CHAIN_TOP)
	# Floor joints open up toward the camera by φ: a perspective, not a grid.
	var y := 9.0
	var step := 7.0
	var spacing := 96.0
	while y < 190.0:
		_joint.append(y)
		if _joint.size() <= 3:
			var tick := fmod(float(_joint.size()) * 31.0, spacing)
			while tick < WIDTH + 40.0:
				_paving.append(Vector2(tick, y))
				tick += spacing
		y += step
		step *= MathArt.PHI
		spacing *= MathArt.PHI
	# One inlaid medallion per monument, seen edge-on: an ellipse, not a circle.
	for station: Dictionary in STATIONS:
		var cx := float(station["x"])
		for ring_index in 2:
			var scale := pow(MathArt.INV_PHI, float(ring_index))
			var ring := PackedVector2Array()
			for i in 25:
				var angle := TAU * float(i) / 24.0
				ring.append(Vector2(cx + cos(angle) * 34.0 * scale, 14.0 + sin(angle) * 11.0 * scale))
			_medallion.append(ring)
	# Three beams: one from the rose window, two through clerestory arches (they
	# start at the arch apex, so the light reads as coming through the opening).
	_add_beam(ROSE_AT.x, ROSE_AT.y + ROSE_R * MathArt.INV_PHI, 34.0)
	for target: float in [360.0, 1250.0]:
		var opening := _bay_near(target)
		_add_beam(opening.x, ARCADE_BASE - opening.y, opening.y * MathArt.INV_PHI * MathArt.INV_PHI)


## A shaft of light: three nested trapezoids a 1/φ apart, which is what gives a
## hard-edged polygon a soft horizontal falloff.
func _add_beam(x: float, top: float, half_top: float) -> void:
	for tier in 3:
		var half := half_top * pow(MathArt.INV_PHI, float(tier))
		var bottom := half * MathArt.PHI
		_beam.append(PackedVector2Array([
			Vector2(x - half, top), Vector2(x + half, top),
			Vector2(x + bottom, 0.0), Vector2(x - bottom, 0.0)]))
		_beam_alpha.append(0.03 + float(tier) * 0.012)
	_pool_x.append(x)
	_pool_half.append(half_top * MathArt.PHI)


func _bay_near(target: float) -> Vector2:
	var best := Vector2.ZERO
	var best_distance := INF
	for bay in _bay:
		var distance := absf(bay.x - target)
		if distance < best_distance:
			best_distance = distance
			best = bay
	return best


## Ambient particles live for the whole session, so they are spawned exactly
## once: shaft_motes is a permanent emitter, and ember_drift bursts are pulsed
## from _process (never from _draw, which would leak a node per frame).
func _spawn_ambience() -> void:
	for i in _pool_x.size():
		Juice.shaft_motes(self, Vector2(_pool_x[i], -2.0), _pool_half[i] * 0.75, 240.0,
			MathArt.PALE if i == 0 else MathArt.PALE_DIM, 12 if i == 0 else 8, 3.6)


func _build_player() -> void:
	# A floor's projectiles are parented to the persistent world (Game.fx_root),
	# not to the level, so freeing the level does not free them. One still in
	# flight would keep flying in the hub and could hit the new player.
	for node in get_parent().get_children():
		if node is Projectile or node is FunctionWave:
			node.set_physics_process(false)
			node.monitoring = false
			node.queue_free()
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
	# Brazier embers feed the vault even while a panel is open.
	_ember_t -= delta
	if _ember_t <= 0.0:
		_ember_t = 0.8
		_ember_slot = (_ember_slot + 1) % _chain_x.size()
		Juice.ember_drift(self, _chain_tip(_ember_slot), MathArt.PALE_DIM, 4, 2.4)
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
	_draw_vault()
	_draw_ceiling()
	_draw_beams()
	_draw_motes()
	_draw_floor()
	_draw_floor_inlay()
	_draw_pools()
	for i in STATIONS.size():
		_draw_station(i)
	_draw_door()
	_draw_foreground()


## Far plane: the vault, its arcade and the rose window.
func _draw_vault() -> void:
	MathArt.px_rect(self, Rect2(-400.0, -900.0, WIDTH + 800.0, 1020.0), MathArt.BG_0)
	# Value falls off with height: the vault is the darkest plane on screen.
	for i in 4:
		MathArt.px_rect(self, Rect2(-400.0, VAULT_TOP + float(i) * 62.0, WIDTH + 800.0, 62.0),
			Color(MathArt.INK, 0.55 - float(i) * 0.13))
	# The wall band the monuments stand against: one lit value between the dark
	# vault and the lit floor, so the monument row is a plane and not a layer.
	MathArt.px_rect(self, Rect2(-400.0, ARCADE_BASE, WIDTH + 800.0, -ARCADE_BASE), MathArt.BG_1)
	MathArt.px_rect(self, Rect2(-400.0, ARCADE_BASE, WIDTH + 800.0, 2.0), Color(MathArt.STONE_DIM, 0.7))
	# Gallery above it: a black recess with lit piers and arch rims, so the dead
	# 300 px of vault carries a colonnade instead of a flat wash.
	MathArt.px_rect(self, Rect2(-400.0, PIER_TOP, WIDTH + 800.0, ARCADE_BASE - PIER_TOP), MathArt.INK)
	for i in _bay.size():
		var bay := _bay[i]
		MathArt.ring(self, Vector2(bay.x, ARCADE_BASE), bay.y, Color(MathArt.STONE_DIM, 0.6), 1.0, 20, PI, TAU)
		MathArt.ring(self, Vector2(bay.x, ARCADE_BASE), bay.y - 6.0, Color(MathArt.BG_0, 0.95), 1.0, 20, PI, TAU)
	for i in _pier.size():
		MathArt.px_rect(self, Rect2(_pier[i] - 5.0, PIER_TOP, 10.0, ARCADE_BASE - PIER_TOP), Color(MathArt.STONE_DIM, 0.4))
		MathArt.px_rect(self, Rect2(_pier[i] - 5.0, PIER_TOP, 2.0, ARCADE_BASE - PIER_TOP), Color(MathArt.MID_DIM, 0.4))
	_draw_rose()


func _draw_rose() -> void:
	# The one focal point above the monuments, and the source of the main beam.
	var breathe := 0.5 + 0.5 * sin(_t * 0.5)
	MathArt.glow(self, ROSE_AT, ROSE_R * MathArt.PHI, Color(MathArt.LIGHT_DIM, 0.7 + 0.3 * breathe), 3)
	MathArt.ring(self, ROSE_AT, ROSE_R, Color(MathArt.STONE_HI, 0.8), 2.0, 40)
	MathArt.ring(self, ROSE_AT, ROSE_R * MathArt.INV_PHI, Color(MathArt.MID_DIM, 0.6), 1.0, 32)
	MathArt.ring(self, ROSE_AT, ROSE_R * MathArt.INV_PHI * MathArt.INV_PHI, Color(MathArt.LIGHT_DIM, 0.5), 1.0, 24)
	for i in 12:
		var angle := _t * 0.1 + TAU * float(i) / 12.0
		MathArt.line(self, ROSE_AT + Vector2.from_angle(angle) * 10.0,
			ROSE_AT + Vector2.from_angle(angle) * (ROSE_R - 2.0), Color(MathArt.STONE, 0.45), 1.0)


## Near-plane ceiling beam plus everything that hangs from it.
func _draw_ceiling() -> void:
	MathArt.px_rect(self, Rect2(-400.0, VAULT_TOP, WIDTH + 800.0, BEAM_BOTTOM - VAULT_TOP), MathArt.INK)
	MathArt.px_rect(self, Rect2(-400.0, BEAM_BOTTOM, WIDTH + 800.0, 2.0), Color(MathArt.STONE_DIM, 0.55))
	for i in 9:
		MathArt.px_rect(self, Rect2(-60.0 + float(i) * 200.0, BEAM_BOTTOM - 4.0, 22.0, 4.0), MathArt.STONE_DIM)
	for i in _chain_x.size():
		_draw_chain(i)


func _draw_chain(index: int) -> void:
	var base := index * CHAIN_SAMPLES
	var anchor := _chain_x[index]
	var phase := float(index) * MathArt.GOLDEN_ANGLE
	# A chain is a harmonic wave sampled in y and pinned at the ceiling: the sway
	# grows with k² so the anchor never moves and the brazier swings.
	for j in CHAIN_SAMPLES:
		var k := float(j) / float(CHAIN_SAMPLES - 1)
		_chain_pts[base + j] = Vector2(anchor + sin(_t * 0.7 + phase) * 16.0 * k * k, CHAIN_TOP + _chain_len[index] * k)
	for j in CHAIN_SAMPLES - 1:
		MathArt.line(self, _chain_pts[base + j], _chain_pts[base + j + 1], Color(MathArt.STONE_HI, 0.8), 1.0)
	_draw_brazier(_chain_tip(index), phase)


func _draw_brazier(at: Vector2, phase: float) -> void:
	var flicker := 0.5 + 0.5 * sin(_t * 6.0 + phase)
	MathArt.glow(self, at + Vector2(0.0, -9.0), 11.0 + 3.0 * flicker, MathArt.PALE_DIM, 2)
	MathArt.arc(self, at + Vector2(0.0, -6.0), 6.0, 0.0, PI, Color(MathArt.STONE_HI, 0.9), 1.5)
	MathArt.line(self, at + Vector2(-6.0, -6.0), at + Vector2(6.0, -6.0), MathArt.MID_DIM, 1.0)
	for i in 3:
		var width := 4.5 - float(i) * 1.2
		var sway := sin(_t * 4.0 + phase + float(i) * 0.9) * 1.4
		MathArt.px_rect(self, Rect2(at.x - width * 0.5 + sway, at.y - 13.0 - float(i) * 4.0, width, 3.0 + flicker),
			Color(MathArt.PALE, 0.45 + 0.16 * float(i)))


func _chain_tip(index: int) -> Vector2:
	var phase := float(index) * MathArt.GOLDEN_ANGLE
	return Vector2(_chain_x[index] + sin(_t * 0.7 + phase) * 16.0, CHAIN_TOP + _chain_len[index])


func _draw_beams() -> void:
	for i in _beam.size():
		var pulse := 0.85 + 0.15 * sin(_t * 0.5 + float(i / 3) * 1.9)
		MathArt.poly(self, _beam[i], Color(MathArt.PALE, _beam_alpha[i] * pulse))


func _draw_motes() -> void:
	for i in _motes.size():
		var mote := _motes[i]
		var alpha := 0.10 + 0.16 * (0.5 + 0.5 * sin(_t * 1.1 + mote.z))
		var point := Vector2(mote.x, mote.y + sin(_t * 0.6 + mote.z) * 4.0)
		MathArt.px_rect(self, Rect2(point.x, point.y, 1.0, 1.0), Color(MathArt.PALE, alpha))


func _draw_floor() -> void:
	# Four value bands falling toward the camera: the near floor is dark, which
	# is what separates it from the lit strip at the walkable line.
	MathArt.px_rect(self, Rect2(-60.0, 0.0, WIDTH + 120.0, 40.0), MathArt.BG_2)
	MathArt.px_rect(self, Rect2(-60.0, 40.0, WIDTH + 120.0, 48.0), MathArt.BG_1)
	MathArt.px_rect(self, Rect2(-60.0, 88.0, WIDTH + 120.0, 76.0), MathArt.BG_0)
	MathArt.px_rect(self, Rect2(-60.0, 164.0, WIDTH + 120.0, 200.0), MathArt.INK)
	# The walkable line: the only hard edge in the frame, so it stays crisp.
	MathArt.px_rect(self, Rect2(-60.0, 0.0, WIDTH + 120.0, 3.0), MathArt.STONE_HI)
	MathArt.px_rect(self, Rect2(-60.0, 3.0, WIDTH + 120.0, 1.0), Color(MathArt.BG_0, 0.9))
	for i in _joint.size():
		MathArt.px_rect(self, Rect2(-60.0, _joint[i], WIDTH + 120.0, 1.0),
			Color(MathArt.STONE, 0.5 - float(i) * 0.07))
	for i in _paving.size():
		MathArt.px_rect(self, Rect2(_paving[i].x, _paving[i].y, 1.0, 3.0), Color(MathArt.STONE, 0.45))


func _draw_floor_inlay() -> void:
	# One medallion per monument. The focused one warms up: that is the "press J
	# here" cue, and it lives on the floor rather than in a UI box.
	for i in STATIONS.size():
		var near := i == _near
		var pulse := 0.5 + 0.5 * sin(_t * 2.6)
		var tint := MathArt.MID_DIM
		if near:
			tint = MathArt.LIGHT_DIM.lerp(MathArt.PALE, 0.4 + 0.4 * pulse)
		MathArt.poly(self, _medallion[i * 2], Color(tint, 0.05 + (0.06 * pulse if near else 0.0)),
			Color(tint, 0.35 + (0.35 * pulse if near else 0.0)), 1.0)
		MathArt.poly(self, _medallion[i * 2 + 1], Color(MathArt.BG_0, 0.35), Color(tint, 0.22), 1.0)


func _draw_pools() -> void:
	# Where each beam lands: a pool on the paving with one bright rim.
	for i in _pool_x.size():
		var x := _pool_x[i]
		var half := _pool_half[i]
		var pulse := 0.85 + 0.15 * sin(_t * 0.6 + float(i))
		MathArt.px_rect(self, Rect2(x - half, 1.0, half * 2.0, 6.0), Color(MathArt.PALE, 0.06 * pulse))
		MathArt.px_rect(self, Rect2(x - half * MathArt.INV_PHI, 7.0, half * 2.0 * MathArt.INV_PHI, 4.0),
			Color(MathArt.PALE, 0.04 * pulse))
		MathArt.line(self, Vector2(x - half, 1.0), Vector2(x + half, 1.0), Color(MathArt.PALE_DIM, 0.16), 1.0)
	# Sheen: the main beam reflects off the stone under it.
	MathArt.px_rect(self, Rect2(_pool_x[0] - 9.0, 16.0, 18.0, 22.0), Color(MathArt.PALE, 0.03))


func _draw_foreground() -> void:
	# Near plane: black columns in the gaps between stations. They carry the
	# darkest value in the frame, which is what pushes the monument row back.
	for x: float in FOREGROUND_X:
		# Nearer than the monument row, so: wider, darkest, cropped by the top of
		# the frame, and its foot runs DOWN INTO the floor band instead of
		# standing on the walkable line. A footer that sits on y=0 reads as an
		# obstacle in the play plane (the first hub screenshot did exactly that);
		# one that overlaps the floor reads as being in front of it.
		MathArt.px_rect(self, Rect2(x - 8.0, -168.0, 16.0, 168.0), MathArt.BLACK)
		MathArt.px_rect(self, Rect2(x + 5.0, -168.0, 3.0, 168.0), Color(MathArt.STONE_DIM, 0.45))
		MathArt.px_rect(self, Rect2(x - 12.0, -176.0, 24.0, 9.0), MathArt.BLACK)
		MathArt.px_rect(self, Rect2(x - 12.0, -176.0, 24.0, 1.0), Color(MathArt.STONE_DIM, 0.55))
		MathArt.px_rect(self, Rect2(x - 13.0, -12.0, 26.0, 34.0), MathArt.BLACK)
		# Contact shadow in front of the foot, so the column is clearly nearer
		# than the floor it overlaps.
		MathArt.px_rect(self, Rect2(x - 22.0, 22.0, 44.0, 2.0), Color(MathArt.BLACK, 0.5))


func _draw_station(index: int) -> void:
	var station: Dictionary = STATIONS[index]
	var x := float(station["x"])
	var bright := index == _near
	# The stations are the only interactive things in the room, so they have to
	# carry a bigger value step than the stone around them. At STONE_HI they
	# disappeared into the vault from two screens away.
	var tint := MathArt.WHITE if bright else MathArt.MID
	var base := Vector2(x, 0.0)
	var phase := float(index) * MathArt.GOLDEN_ANGLE
	if bright:
		MathArt.glow(self, base + Vector2(0.0, -34.0), 54.0 + 4.0 * sin(_t * 2.6), MathArt.PALE, 5)

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

	# Censer: a chain off the cap, swinging on the station's own phase.
	var pivot := base + Vector2(15.0, -60.0)
	var swing := sin(_t * 1.1 + phase)
	var bob := pivot + Vector2(swing * 6.0, 13.0 + swing * swing * 1.5)
	MathArt.line(self, pivot, bob, Color(tint, 0.4), 1.0)
	MathArt.arc(self, bob, 3.0, 0.0, PI, Color(tint, 0.65), 1.0)

	_draw_inner(str(station["inner"]), base + Vector2(0.0, -32.0), tint, bright)

	# Wisp: embers climb off the plinth so the monument is alive from across the
	# floor, not only while the player stands next to it.
	for i in 3:
		var rise := fmod(_t * (13.0 + float(i) * 5.0) + phase * 4.0, 44.0)
		var drift := sin(_t * 1.3 + float(i) * 2.1 + phase) * 3.0
		MathArt.px_rect(self, Rect2(base.x + drift, -66.0 - rise, 1.0, 1.0),
			Color(tint, (1.0 - rise / 44.0) * 0.55))

	draw_string(ThemeDB.fallback_font, Vector2(x - 70.0, -84.0), str(station["name"]),
		HORIZONTAL_ALIGNMENT_CENTER, 140.0, 9, MathArt.WHITE if bright else MathArt.LIGHT)
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
			for i in 41:
				_scratch[i] = pivot + MathArt.rose(TAU * float(i) / 40.0 + _t * 0.25, 3.0, 11.0)
			MathArt.px_poly(self, _scratch, Color(0, 0, 0, 0), ink, 1.0)
		_:
			for i in 41:
				_scratch[i] = pivot + MathArt.lissajous(TAU * float(i) / 40.0 + _t * 0.5, 3.0, 2.0, PI * 0.5) * 9.0
			MathArt.px_poly(self, _scratch, Color(0, 0, 0, 0), ink, 1.0)


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
	# Spill on the floor, so the goal is legible from the far end of the hall.
	MathArt.px_rect(self, Rect2(DOOR_X - 13.0, 1.0, 26.0, 7.0), Color(MathArt.PALE, 0.09 + 0.05 * pulse))
	MathArt.line(self, Vector2(DOOR_X - 13.0, 1.0), Vector2(DOOR_X + 13.0, 1.0),
		Color(MathArt.WHITE, 0.14 + 0.06 * pulse), 1.0)

	var font := ThemeDB.fallback_font
	# The picker's ceiling is the unlocked top; the label quotes the whole game,
	# so a new player reads "FLOOR 1 / 5" and not "FLOOR 1 / 1".
	var top := maxi(1, Data.floors.size())
	var floor_data: Dictionary = Data.floors.get(str(floor_target), {})
	draw_string(font, Vector2(DOOR_X - 70.0, -120.0), "FLOOR %d / %d" % [floor_target, top],
		HORIZONTAL_ALIGNMENT_CENTER, 140.0, 8, Color(tint, 0.75))
	draw_string(font, Vector2(DOOR_X - 90.0, -105.0), str(floor_data.get("name", "")),
		HORIZONTAL_ALIGNMENT_CENTER, 180.0, 9, tint)
	if bright:
		draw_string(font, Vector2(DOOR_X - 20.0, 22.0), "[J]",
			HORIZONTAL_ALIGNMENT_CENTER, 40.0, 9, Color(MathArt.WHITE, 0.55 + 0.45 * sin(_t * 4.0)))
		if floor_available > 0:
			draw_string(font, Vector2(DOOR_X - 70.0, 36.0), "< A    D >",
				HORIZONTAL_ALIGNMENT_CENTER, 140.0, 8, Color(MathArt.LIGHT, 0.6))
