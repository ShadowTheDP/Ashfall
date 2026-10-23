class_name SlashFx
extends Node2D
## Crescent used to sell the reach of a swing.

var facing := 1
var color := Color("#cfe8ff")
var radius := 62.0
var arc := 2.1
var _t := 0.0
var _life := 0.14


func setup(attack_index: int, is_facing: int, tint: Color) -> void:
	facing = is_facing
	color = tint
	scale.x = float(facing)
	match attack_index:
		0:
			arc = 2.0
			radius = 60.0
		1:
			arc = 2.1
			radius = 62.0
		_:
			arc = 2.7
			radius = 74.0
	z_index = 7


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / _life, 0.0, 1.0)
	var a0 := -arc * 0.5 + k * 0.7
	var a1 := arc * 0.5 + k * 0.7
	var outer := radius * (0.92 + 0.12 * k)
	var inner := radius * 0.52
	var points := PackedVector2Array()
	for i in 11:
		var a := lerpf(a0, a1, float(i) / 10.0)
		points.append(Vector2.from_angle(a) * outer)
	for i in 11:
		var a := lerpf(a1, a0, float(i) / 10.0)
		points.append(Vector2.from_angle(a) * inner)
	draw_colored_polygon(points, Color(color, 0.22 * (1.0 - k)))
	draw_arc(Vector2.ZERO, outer, a0, a1, 18, Color(color, 0.9 * (1.0 - k)), 3.0, true)
	draw_arc(Vector2.ZERO, inner, a0, a1, 18, Color(color, 0.45 * (1.0 - k)), 1.5, true)
