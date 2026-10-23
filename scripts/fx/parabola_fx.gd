class_name ParabolaFx
extends Node2D
## Dotted preview of a ballistic function: p(t) = v0*t + 1/2*g*t^2.

var _velocity := Vector2.ZERO
var _gravity := 900.0
var _t := 0.0
var _life := 0.38


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
	for i in 24:
		var time := 0.52 * (float(i) / 23.0)
		var point := _velocity * time + Vector2(0.0, 0.5 * _gravity * time * time)
		var alpha := fade * (1.0 - float(i) / 26.0)
		draw_circle(point, 1.4, Color(0.56, 0.89, 1.0, alpha * 0.75))
		if i % 4 == 0:
			draw_circle(point, 3.4, Color(0.56, 0.89, 1.0, alpha * 0.12))
