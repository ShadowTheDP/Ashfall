class_name Arena
extends Node2D
## Handcrafted combat arena. Rooms stay handmade on purpose; generation is a
## later pillar. Collision and visuals are built from the same rect data.

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
	_draw_backdrop()
	_draw_ground()
	for rect in PLATFORMS:
		_draw_platform(rect)
	for wall in WALLS:
		draw_rect(wall, STONE)
		draw_rect(Rect2(wall.position, Vector2(3.0, wall.size.y)), Color(EDGE, 0.25))
	_draw_fog()


func _draw_backdrop() -> void:
	# Distant pillars. Slightly lighter than the sky and low contrast so they
	# read as architecture behind combat instead of black monoliths.
	var pillar_x := [-110.0, 340.0, 760.0, 1160.0, 1520.0]
	for index in pillar_x.size():
		var x: float = pillar_x[index]
		var width := 46.0 if index % 2 == 0 else 32.0
		draw_rect(Rect2(x, -470.0, width, 470.0), Color(0.085, 0.10, 0.135, 0.42))
		draw_rect(Rect2(x - 6.0, -470.0, width + 12.0, 10.0), Color(0.11, 0.13, 0.17, 0.5))
		draw_rect(Rect2(x + width - 3.0, -440.0, 2.0, 420.0), Color(0.16, 0.19, 0.24, 0.35))
		draw_rect(Rect2(x + 6.0, -440.0, 1.0, 420.0), Color(0.02, 0.03, 0.04, 0.35))
	# Faint warning runes.
	for x in [-40.0, 420.0, 900.0, 1360.0]:
		draw_line(Vector2(x, -60.0), Vector2(x + 26.0, -120.0), Color(0.55, 0.4, 0.18, 0.14), 2.0)
		draw_line(Vector2(x + 26.0, -120.0), Vector2(x + 52.0, -60.0), Color(0.55, 0.4, 0.18, 0.14), 2.0)


func _draw_ground() -> void:
	draw_rect(GROUND, STONE)
	draw_rect(Rect2(GROUND.position, Vector2(GROUND.size.x, 4.0)), EDGE)
	draw_rect(Rect2(GROUND.position + Vector2(0, 4), Vector2(GROUND.size.x, 2.0)), Color(EDGE_WARM, 0.25))
	# Deterministic cracks and moss so the ground does not read as flat.
	var x := GROUND.position.x + 30.0
	var step := 74.0
	while x < GROUND.position.x + GROUND.size.x - 10.0:
		var depth := 18.0 + fmod(x * 7.3, 44.0)
		draw_line(Vector2(x, 6.0), Vector2(x + 9.0, depth), Color(0.03, 0.04, 0.055, 0.9), 1.5)
		if fmod(x, 3.0) < 1.0:
			draw_circle(Vector2(x + 20.0, 8.0), 3.0, Color(0.35, 0.26, 0.12, 0.22))
		x += step


func _draw_platform(rect: Rect2) -> void:
	draw_rect(rect, STONE_LIGHT)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3.0)), EDGE)
	draw_rect(Rect2(rect.position + Vector2(0, 3), Vector2(rect.size.x, 2.0)), Color(0.08, 0.1, 0.13, 1.0))
	draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 3.0), Vector2(rect.size.x, 3.0)), Color(0.02, 0.03, 0.04, 0.9))
	var lock := rect.position.x + 18.0
	while lock < rect.position.x + rect.size.x - 12.0:
		draw_line(Vector2(lock, rect.position.y + 4.0), Vector2(lock + 6.0, rect.position.y + 12.0), Color(0.03, 0.04, 0.05, 0.8), 1.2)
		lock += 42.0
	# warm edge glints
	draw_line(
		Vector2(rect.position.x + 8.0, rect.position.y + 1.0),
		Vector2(rect.position.x + rect.size.x * 0.42, rect.position.y + 1.0),
		Color(EDGE_WARM, 0.5),
		1.0
	)


func _draw_fog() -> void:
	for i in 4:
		var x := -80.0 + i * 420.0
		draw_set_transform(Vector2(x, -18.0), 0.0, Vector2(7.0, 0.7))
		draw_circle(Vector2.ZERO, 42.0, Color(0.16, 0.2, 0.28, 0.06))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
