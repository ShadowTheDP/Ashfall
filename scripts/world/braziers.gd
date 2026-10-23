class_name Braziers
extends Node2D
## Math-art torches: hexagonal plinths, rose-curve flames and phyllotaxis
## embers. Purely decorative; no collision.

const AMBER := Color("#e8a33d")
const FLAME := Color("#ffcf7a")
const EMBER := Color("#ff8a3d")

var _t := 0.0
var _positions := [Vector2(40, 0), Vector2(420, 0), Vector2(820, 0), Vector2(1210, 0), Vector2(1540, 0)]


func _ready() -> void:
	z_index = 0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	for index in _positions.size():
		_draw_brazier(_positions[index], float(index) * 1.7)


func _draw_brazier(base: Vector2, phase: float) -> void:
	var flicker := 1.0 + 0.08 * sin(_t * 7.0 + phase) + 0.04 * sin(_t * 13.0 + phase * 2.0)

	# Light pool on the ground.
	draw_set_transform(base + Vector2(0, -2), 0.0, Vector2(2.2, 0.32))
	MathArt.draw_glow(self, Vector2.ZERO, 46.0, Color(AMBER, 0.10 * flicker), 4)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Hexagonal plinth and bowl.
	var plinth := MathArt.ngon(6, 17.0, PI / 6.0, base + Vector2(0, -8))
	MathArt.draw_poly(self, plinth, Color("#1a2028"), Color(0.35, 0.28, 0.16, 0.7), 1.2)
	draw_rect(Rect2(base + Vector2(-15, -12), Vector2(30, 10)), Color("#121820"))
	draw_line(base + Vector2(-15, -12), base + Vector2(15, -12), Color(0.55, 0.42, 0.22, 0.55), 1.0)

	# Flame: three rose-curve lobes stacked by height.
	for layer in 3:
		var radius := (13.0 - float(layer) * 3.0) * flicker
		var height := 30.0 + float(layer) * 10.0
		var points := PackedVector2Array()
		var segments := 22
		for i in segments:
			var theta := TAU * float(i) / float(segments)
			var r := radius * (0.62 + 0.38 * cos(3.0 * theta + _t * 1.6 + phase))
			points.append(base + Vector2(cos(theta) * r * 0.55, -22.0 - sin(theta) * r - height * 0.45))
		var tint := Color(EMBER, 0.25 + 0.15 * float(layer))
		MathArt.draw_poly(self, points, tint, Color(FLAME, 0.35 + 0.1 * float(layer)), 1.0)

	# Bright core.
	MathArt.draw_glow(self, base + Vector2(0, -26), 16.0 * flicker, Color(FLAME, 0.18), 3)
	draw_circle(base + Vector2(0, -24), 3.2 * flicker, Color(1.0, 0.94, 0.72, 0.85))

	# Phyllotaxis embers rising.
	for i in 5:
		var p := MathArt.phyllotaxis(i + 1, 5.0)
		var rise := fmod(_t * (9.0 + float(i)) + phase * 8.0, 38.0)
		var pos := base + Vector2(p.x * 0.55, -30.0 - rise + p.y * 0.25)
		var alpha := (1.0 - rise / 38.0) * 0.6
		draw_circle(pos, 1.3, Color(FLAME, alpha))
