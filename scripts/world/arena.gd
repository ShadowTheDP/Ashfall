class_name Arena
extends Node2D
## Handcrafted arena, drawn as pixel blocks. Collision and art share the same
## rects; the decoration is precomputed once so the static draw stays cheap.

const GROUND := Rect2(-150.0, 0.0, 1750.0, 160.0)
const PLATFORMS := [
	Rect2(120.0, -90.0, 240.0, 14.0),
	Rect2(470.0, -150.0, 300.0, 14.0),
	Rect2(880.0, -90.0, 240.0, 14.0),
	Rect2(1180.0, -170.0, 280.0, 14.0),
	Rect2(690.0, -52.0, 150.0, 12.0),
]
const WALLS := [
	Rect2(-170.0, -520.0, 20.0, 680.0),
	Rect2(1600.0, -520.0, 20.0, 680.0),
]
const GROUND_SPAWNS := [
	Vector2(470.0, -42.0),
	Vector2(650.0, -42.0),
	Vector2(820.0, -42.0),
	Vector2(1010.0, -42.0),
	Vector2(1230.0, -42.0),
	Vector2(1430.0, -42.0),
]
const PLATFORM_SPAWNS := [
	Vector2(240.0, -128.0),
	Vector2(620.0, -188.0),
	Vector2(1000.0, -128.0),
	Vector2(1320.0, -196.0),
]

const STONE := MathArt.STONE
const STONE_2 := MathArt.STONE_2
const STONE_3 := MathArt.STONE_3
const EDGE := MathArt.EDGE
const AMBER := MathArt.AMBER

var _specks: Array[Vector3] = []
var _cracks: Array[Vector4] = []
var _columns: Array[Dictionary] = []


func _ready() -> void:
	z_index = 0
	var rects: Array = [GROUND]
	rects.append_array(PLATFORMS)
	rects.append_array(WALLS)
	for rect in rects:
		_make_body(rect)
	_build_decoration()


func _make_body(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = rect.position + rect.size * 0.5
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _build_decoration() -> void:
	# Deterministic pixel noise: one pass at load, never per frame.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261023
	for i in 260:
		var x := roundf(rng.randf_range(GROUND.position.x, GROUND.position.x + GROUND.size.x))
		var y := roundf(rng.randf_range(6.0, 120.0))
		var shade := rng.randf()
		_specks.append(Vector3(x, y, shade))
	for i in 46:
		var x := roundf(rng.randf_range(GROUND.position.x + 20.0, GROUND.position.x + GROUND.size.x - 20.0))
		_cracks.append(Vector4(x, rng.randf_range(8.0, 40.0), rng.randf_range(4.0, 12.0), rng.randf()))
	for i in 5:
		_columns.append({
			"x": [-110.0, 340.0, 760.0, 1160.0, 1520.0][i],
			"w": 44.0 if i % 2 == 0 else 32.0,
			"sigil": i % 2 == 0,
		})


func _draw() -> void:
	_draw_monoliths()
	_draw_banners()
	_draw_rose_window()
	_draw_ground()
	for rect in PLATFORMS:
		_draw_platform(rect)
	for wall in WALLS:
		MathArt.px_rect(self, wall, STONE)
		MathArt.px_rect(self, Rect2(wall.position, Vector2(2.0, wall.size.y)), Color(EDGE, 0.22))
	_draw_fog()


func _draw_rose_window() -> void:
	var center := Vector2(720, -170)
	for i in 3:
		var radius := 210.0 - float(i) * 46.0
		MathArt.px_ring(self, center, radius, Color(0.30, 0.42, 0.58, 0.10 + float(i) * 0.02), 1.0)
	for i in 12:
		var angle := TAU * float(i) / 12.0 - PI * 0.5
		var inner := center + Vector2.from_angle(angle) * 120.0
		var outer := center + Vector2.from_angle(angle) * 210.0
		MathArt.px_line(self, inner, outer, Color(0.30, 0.42, 0.58, 0.07), 1.0)
	MathArt.px_poly(self, MathArt.star(12, 122.0, 96.0, -PI * 0.5, center),
		Color(0, 0, 0, 0), Color(0.30, 0.42, 0.58, 0.06), 1.0)


func _draw_monoliths() -> void:
	for column in _columns:
		var x: float = column["x"]
		var width: float = column["w"]
		var top := -470.0
		MathArt.px_rect(self, Rect2(x, top, width, 470.0), Color(0.070, 0.086, 0.118, 0.60))
		MathArt.px_rect(self, Rect2(x + width - 3.0, top, 3.0, 470.0), Color(0.045, 0.055, 0.078, 0.60))
		MathArt.px_rect(self, Rect2(x + 2.0, top, 1.0, 470.0), Color(0.16, 0.19, 0.24, 0.22))
		# Hex capital.
		var cap := MathArt.ngon(6, width * 0.5, 0.0, Vector2(x + width * 0.5, top))
		MathArt.px_poly(self, cap, Color(0.10, 0.12, 0.16, 0.6), Color(0.18, 0.21, 0.26, 0.4), 1.0)
		if bool(column["sigil"]):
			var sigil := MathArt.ngon(6, width * 0.30, PI / 6.0, Vector2(x + width * 0.5, top + 110.0))
			MathArt.px_poly(self, sigil, Color(0, 0, 0, 0), Color(AMBER, 0.16), 1.0)
			MathArt.px_ring(self, Vector2(x + width * 0.5, top + 110.0), width * 0.46, Color(AMBER, 0.09), 1.0)


func _draw_banners() -> void:
	for spec in [[80.0, 0.9], [600.0, 1.2], [1120.0, 0.75], [1480.0, 1.05]]:
		var x: float = spec[0]
		var width := roundf(22.0 * float(spec[1]))
		var top := -290.0
		var bottom := -180.0
		MathArt.px_rect(self, Rect2(x - width * 0.5, top, width, bottom - top), Color(0.15, 0.07, 0.08, 0.55))
		MathArt.px_rect(self, Rect2(x - width * 0.5, top, width, 2.0), Color(0.42, 0.30, 0.15, 0.55))
		# Pennant point.
		for i in 4:
			var w := width * (1.0 - float(i) / 4.0)
			MathArt.px_rect(self, Rect2(x - w * 0.5, bottom + float(i) * 3.0, w, 3.0), Color(0.15, 0.07, 0.08, 0.55))
		MathArt.px_poly(self, MathArt.ngon(3, width * 0.24, -PI * 0.5, Vector2(x, top + 40.0)),
			Color(AMBER, 0.18), Color(AMBER, 0.30), 1.0)


func _draw_ground() -> void:
	MathArt.px_rect(self, GROUND, STONE)
	MathArt.px_rect(self, Rect2(GROUND.position, Vector2(GROUND.size.x, 3.0)), EDGE)
	MathArt.px_rect(self, Rect2(GROUND.position + Vector2(0, 3), Vector2(GROUND.size.x, 1.0)), Color(MathArt.AMBER_DIM, 0.35))

	# Pixel noise.
	for speck in _specks:
		var shade: float = speck.z
		if shade > 0.80:
			MathArt.px_rect(self, Rect2(speck.x, speck.y, 1, 1), Color(STONE_3, 0.45))
		elif shade > 0.55:
			MathArt.px_rect(self, Rect2(speck.x, speck.y, 1, 1), Color(MathArt.INK, 0.35))
		elif shade > 0.30:
			MathArt.px_rect(self, Rect2(speck.x, speck.y, 1, 1), Color(MathArt.AMBER_DIM, 0.07))

	# Cracks.
	for crack in _cracks:
		var depth: float = crack.y
		var lean: float = crack.z
		var shade: float = crack.w
		var color := Color(MathArt.INK, 0.55) if shade > 0.4 else Color(MathArt.STEEL_DIM, 0.10)
		MathArt.px_line(self, Vector2(crack.x, 4.0), Vector2(crack.x + lean, depth), color, 1.0)
		if shade > 0.7:
			MathArt.px_line(self, Vector2(crack.x + lean, depth), Vector2(crack.x + lean + 3.0, depth + 6.0), color, 1.0)

	# A 1px amber rule just under the surface.
	MathArt.px_rect(self, Rect2(GROUND.position.x, 5.0, GROUND.size.x, 1.0), Color(AMBER, 0.10))


func _draw_platform(rect: Rect2) -> void:
	MathArt.px_rect(self, rect, STONE_2)
	MathArt.px_rect(self, Rect2(rect.position, Vector2(rect.size.x, 2.0)), EDGE)
	MathArt.px_rect(self, Rect2(rect.position + Vector2(0, 2), Vector2(rect.size.x, 1.0)), Color(MathArt.AMBER_DIM, 0.25))
	MathArt.px_rect(self, Rect2(rect.position + Vector2(0, rect.size.y - 2.0), Vector2(rect.size.x, 2.0)), Color(MathArt.INK, 0.8))
	# Phi tick marks.
	for fraction in [0.0, MathArt.INV_PHI * MathArt.INV_PHI, MathArt.INV_PHI, 1.0]:
		var tx := rect.position.x + rect.size.x * float(fraction)
		MathArt.px_rect(self, Rect2(roundf(tx), rect.position.y + 2.0, 1, 4.0), Color(AMBER, 0.16))
	# Block seams.
	var seam := rect.position.x + 24.0
	while seam < rect.position.x + rect.size.x - 10.0:
		MathArt.px_rect(self, Rect2(roundf(seam), rect.position.y + 3.0, 1, rect.size.y - 5.0), Color(MathArt.INK, 0.35))
		seam += 48.0


func _draw_fog() -> void:
	for i in 4:
		var x := -80.0 + float(i) * 420.0
		for band in 3:
			var width := 90.0 - float(band) * 22.0
			MathArt.px_rect(self, Rect2(roundf(x - width * 0.5), -20.0 + float(band) * 5.0, width, 3.0),
				Color(0.16, 0.2, 0.28, 0.05))
