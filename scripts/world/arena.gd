class_name Arena
extends Node2D
## Handcrafted combat arena drawn from the project's math language:
## hexagonal monoliths, a rose window, harmonic platform edges, golden-ratio
## tick marks and phyllotaxis debris. Collision and art share the same rects.

const GROUND := Rect2(-150.0, 0.0, 1750.0, 160.0)
const PLATFORMS := [
	Rect2(120.0, -100.0, 240.0, 18.0),
	Rect2(470.0, -170.0, 300.0, 18.0),
	Rect2(880.0, -100.0, 240.0, 18.0),
	Rect2(1180.0, -190.0, 280.0, 18.0),
	Rect2(690.0, -60.0, 150.0, 16.0),
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
	Vector2(240.0, -142.0),
	Vector2(620.0, -212.0),
	Vector2(1000.0, -142.0),
	Vector2(1320.0, -232.0),
]

const STONE := Color("#121822")
const STONE_LIGHT := Color("#1d2835")
const EDGE := Color("#3b5065")
const EDGE_WARM := Color("#6b5636")
const AMBER := Color("#e8a33d")


func _ready() -> void:
	z_index = 0
	var rects: Array = [GROUND]
	rects.append_array(PLATFORMS)
	rects.append_array(WALLS)
	for rect in rects:
		_make_body(rect)


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


func _draw() -> void:
	_draw_rose_window()
	_draw_monoliths()
	_draw_banners()
	_draw_ground()
	for rect in PLATFORMS:
		_draw_platform(rect)
	for wall in WALLS:
		draw_rect(wall, STONE)
		draw_rect(Rect2(wall.position, Vector2(3.0, wall.size.y)), Color(EDGE, 0.25))
	_draw_debris()
	_draw_fog()


func _draw_rose_window() -> void:
	var center := Vector2(720, -190)
	var color := Color(0.30, 0.42, 0.58, 0.10)
	for i in 3:
		var radius := 260.0 - float(i) * 56.0
		MathArt.draw_ring(self, center, radius, Color(color, 0.10 + float(i) * 0.02), 1.0, 96)
	var spokes := 12
	for i in spokes:
		var angle := TAU * float(i) / float(spokes) - PI * 0.5
		var inner := center + Vector2.from_angle(angle) * 148.0
		var outer := center + Vector2.from_angle(angle) * 260.0
		draw_line(inner, outer, Color(color, 0.08), 1.0)
		var tip := center + Vector2.from_angle(angle) * 230.0
		var left := center + Vector2.from_angle(angle - 0.06) * 200.0
		var right := center + Vector2.from_angle(angle + 0.06) * 200.0
		draw_line(left, tip, Color(color, 0.06), 1.0)
		draw_line(tip, right, Color(color, 0.06), 1.0)
	MathArt.draw_poly(self, MathArt.star(12, 150.0, 118.0, -PI * 0.5, center),
		Color(0, 0, 0, 0), Color(color, 0.055), 1.0)


func _draw_monoliths() -> void:
	var positions := [-110.0, 340.0, 760.0, 1160.0, 1520.0]
	for index in positions.size():
		var x: float = positions[index]
		var width := 46.0 if index % 2 == 0 else 34.0
		var top := -470.0
		var front := PackedVector2Array([
			Vector2(x, top), Vector2(x + width, top),
			Vector2(x + width, 0), Vector2(x, 0),
		])
		draw_colored_polygon(front, Color(0.075, 0.09, 0.125, 0.55))
		var side := PackedVector2Array([
			Vector2(x + width, top), Vector2(x + width + 9.0, top - 8.0),
			Vector2(x + width + 9.0, 0), Vector2(x + width, 0),
		])
		draw_colored_polygon(side, Color(0.045, 0.055, 0.08, 0.55))
		var cap := MathArt.ngon(6, width * 0.5, 0.0, Vector2(x + width * 0.5, top))
		MathArt.draw_poly(self, cap, Color(0.10, 0.12, 0.16, 0.55), Color(0.16, 0.19, 0.24, 0.35), 1.0)
		draw_line(Vector2(x + 4, top + 20), Vector2(x + 4, 0), Color(0.16, 0.19, 0.24, 0.25), 1.0)
		# A carved sigil every other column.
		if index % 2 == 0:
			var sigil := MathArt.ngon(6, width * 0.34, PI / 6.0, Vector2(x + width * 0.5, top + 120.0))
			MathArt.draw_poly(self, sigil, Color(0, 0, 0, 0), Color(0.55, 0.40, 0.18, 0.16), 1.0)
			MathArt.draw_ring(self, Vector2(x + width * 0.5, top + 120.0), width * 0.5,
				Color(0.55, 0.40, 0.18, 0.10), 1.0, 24)


func _draw_banners() -> void:
	for spec in [[80.0, 0.9], [600.0, 1.2], [1120.0, 0.75], [1480.0, 1.05]]:
		var x: float = spec[0]
		var width := 26.0 * float(spec[1])
		var top := -300.0
		var bottom := -190.0 + sin(x) * 14.0
		var cloth := PackedVector2Array([
			Vector2(x - width * 0.5, top),
			Vector2(x + width * 0.5, top),
			Vector2(x + width * 0.42, bottom),
			Vector2(x, bottom + 18.0),
			Vector2(x - width * 0.42, bottom),
		])
		MathArt.draw_poly(self, cloth, Color(0.16, 0.07, 0.08, 0.55), Color(0.35, 0.20, 0.12, 0.35), 1.0)
		MathArt.draw_poly(self, MathArt.ngon(3, width * 0.28, -PI * 0.5, Vector2(x, top + 52.0)),
			Color(0.91, 0.64, 0.24, 0.16), Color(0.91, 0.64, 0.24, 0.30), 1.0)
		draw_line(Vector2(x - width * 0.5, top), Vector2(x + width * 0.5, top), Color(0.5, 0.36, 0.18, 0.5), 1.5)


func _draw_ground() -> void:
	draw_rect(GROUND, STONE)
	draw_rect(Rect2(GROUND.position, Vector2(GROUND.size.x, 4.0)), EDGE)
	draw_rect(Rect2(GROUND.position + Vector2(0, 4), Vector2(GROUND.size.x, 2.0)), Color(EDGE_WARM, 0.25))

	# Golden grid: every 72 px, with phi-spaced stronger lines.
	var x := GROUND.position.x
	var index := 0
	while x < GROUND.position.x + GROUND.size.x:
		var major := index % 5 == 0
		draw_line(Vector2(x, 4.0), Vector2(x, 30.0 if major else 18.0),
			Color(0.55, 0.42, 0.22, 0.10 if major else 0.045), 1.0)
		x += 72.0
		index += 1

	# Harmonic top edge.
	var wave := MathArt.harmonic_wave(Vector2(GROUND.position.x, 5.5), GROUND.size.x, 1.2, 24.0,
		Time.get_ticks_msec() / 1800.0, 160)
	draw_polyline(wave, Color(AMBER, 0.22), 1.0, true)

	# Cracks and moss.
	var crack_x := GROUND.position.x + 30.0
	while crack_x < GROUND.position.x + GROUND.size.x - 10.0:
		var depth := 18.0 + fmod(crack_x * 7.3, 44.0)
		draw_line(Vector2(crack_x, 6.0), Vector2(crack_x + 9.0, depth), Color(0.03, 0.04, 0.055, 0.9), 1.5)
		if fmod(crack_x, 3.0) < 1.0:
			MathArt.draw_poly(self, MathArt.ngon(3, 2.4, crack_x * 0.1, Vector2(crack_x + 20.0, 8.0)),
				Color(0.35, 0.26, 0.12, 0.22))
		crack_x += 74.0


func _draw_platform(rect: Rect2) -> void:
	draw_rect(rect, STONE_LIGHT)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3.0)), EDGE)
	draw_rect(Rect2(rect.position + Vector2(0, 3), Vector2(rect.size.x, 2.0)), Color(0.08, 0.1, 0.13, 1.0))
	draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 3.0), Vector2(rect.size.x, 3.0)), Color(0.02, 0.03, 0.04, 0.9))

	# Harmonic decoration along the top edge (does not affect collision).
	var wave := MathArt.harmonic_wave(rect.position + Vector2(0, 0.5), rect.size.x, 1.0,
		maxf(2.0, rect.size.x / 44.0), rect.position.x * 0.01, 40)
	draw_polyline(wave, Color(EDGE_WARM, 0.35), 1.0, true)

	# Golden-ratio tick marks.
	for fraction in [0.0, MathArt.INV_PHI * MathArt.INV_PHI, MathArt.INV_PHI, 1.0]:
		var tx := rect.position.x + rect.size.x * float(fraction)
		draw_line(Vector2(tx, rect.position.y + 3.0), Vector2(tx, rect.position.y + 11.0),
			Color(AMBER, 0.18), 1.0)
	var lock := rect.position.x + 18.0
	while lock < rect.position.x + rect.size.x - 12.0:
		draw_line(Vector2(lock, rect.position.y + 4.0), Vector2(lock + 6.0, rect.position.y + 12.0),
			Color(0.03, 0.04, 0.05, 0.8), 1.2)
		lock += 42.0
	draw_line(Vector2(rect.position.x + 8.0, rect.position.y + 1.0),
		Vector2(rect.position.x + rect.size.x * MathArt.INV_PHI, rect.position.y + 1.0),
		Color(EDGE_WARM, 0.5), 1.0)


func _draw_debris() -> void:
	for i in 14:
		var point := MathArt.phyllotaxis(i + 1, 56.0) + Vector2(700.0, 8.0)
		if point.y > 28.0:
			point.y = 10.0 + fmod(point.x * 0.07, 18.0)
		var sides := 3 + i % 3
		var shard := MathArt.ngon(sides, 3.0 + fmod(float(i) * 1.7, 4.0), float(i) * 0.7, point)
		MathArt.draw_poly(self, shard, Color(0.10, 0.12, 0.16, 0.7), Color(0.3, 0.25, 0.18, 0.25), 0.8)


func _draw_fog() -> void:
	for i in 4:
		var x := -80.0 + i * 420.0
		draw_set_transform(Vector2(x, -18.0), 0.0, Vector2(7.0, 0.7))
		draw_circle(Vector2.ZERO, 42.0, Color(0.16, 0.2, 0.28, 0.06))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
