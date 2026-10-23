class_name Afterimage
extends Node2D
## Fading geometric echo used during rolls.

var _t := 0.0
var _life := 0.22
var _facing := 1
var _color := Color("#6fb8e8")


func setup(is_facing: int, tint: Color) -> void:
	_facing = is_facing
	_color = tint
	scale.x = float(_facing)
	z_index = 1


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var a := (1.0 - _t / _life) * 0.28
	var body := MathArt.ngon(6, 14.0, _t * 2.0, Vector2(0, -10))
	MathArt.draw_poly(self, body, Color(_color, a), Color(_color, a * 1.4), 1.0)
	draw_circle(Vector2(2, -23), 6.0, Color(_color, a * 1.2))
	MathArt.draw_poly(self, MathArt.ngon(3, 4.0, _t * 3.0, Vector2(0, 6)), Color(_color, a * 0.6))
