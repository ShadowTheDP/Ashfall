class_name RingFx
extends Node2D
## Expanding mathematical ring used for blocks, slams and boss deaths.

var tint := Color("#8fe3ff")
var radius := 60.0
var _t := 0.0
var _life := 0.38
var _sides := 0


func setup(color: Color, max_radius: float, sides: int = 0) -> void:
	tint = color
	radius = max_radius
	_sides = sides
	z_index = 7


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / _life, 0.0, 1.0)
	var current := radius * ease(k, 2.2)
	var alpha := 1.0 - k
	if _sides > 2:
		MathArt.draw_poly(self, MathArt.ngon(_sides, current, k * 1.2),
			Color(0, 0, 0, 0), Color(tint, alpha * 0.55), 1.4)
	MathArt.draw_ring(self, Vector2.ZERO, current, Color(tint, alpha * 0.8), 2.0 * (1.0 - k * 0.5), 48)
	MathArt.draw_ring(self, Vector2.ZERO, current * MathArt.INV_PHI, Color(tint, alpha * 0.30), 1.0, 40)
	for i in 8:
		var angle := TAU * float(i) / 8.0 + k
		draw_line(Vector2.from_angle(angle) * current * 0.85,
			Vector2.from_angle(angle) * current, Color(tint, alpha * 0.35), 1.0)
