class_name ParabolaFx
extends Node2D
## Dotted preview of the ballistic function: p(t) = v0*t + 1/2*g*t^2.
## 1px dots, drawn in a dashed pattern so it reads as a guide, not a laser.

var _velocity := Vector2.ZERO
var _gravity := 900.0
var _t := 0.0
var _life := 0.36


func setup(velocity: Vector2, gravity: float) -> void:
	_velocity = velocity
	_gravity = gravity
	z_index = 7


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var fade := 1.0 - _t / _life
	for i in 26:
		var time := 0.55 * (float(i) / 25.0)
		var point := _velocity * time + Vector2(0.0, 0.5 * _gravity * time * time)
		var alpha := fade * (1.0 - float(i) / 28.0)
		if i % 3 == 0:
			MathArt.px_rect(self, Rect2(roundf(point.x), roundf(point.y), 2, 2), Color(MathArt.CYAN, alpha * 0.75))
		else:
			MathArt.px_rect(self, Rect2(roundf(point.x), roundf(point.y), 1, 1), Color(MathArt.CYAN, alpha * 0.40))
