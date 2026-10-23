class_name Afterimage
extends Node2D
## Pixel ghost of the player's diamond, used during rolls and dodges.

var _t := 0.0
var _life := 0.2
var _facing := 1
var _color := MathArt.CYAN


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
	var a := (1.0 - _t / _life) * 0.30
	var diamond := PackedVector2Array([
		Vector2(0, -13), Vector2(9, -2), Vector2(0, 11), Vector2(-9, -2),
	])
	MathArt.px_poly(self, diamond, Color(_color, a * 0.7), Color(_color, a), 1.0)
	MathArt.px_rect(self, Rect2(-1, -4, 2, 2), Color(_color, a * 1.4))
