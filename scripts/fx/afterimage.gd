class_name Afterimage
extends Node2D
## Fading silhouette used during rolls.

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
	var a := (1.0 - _t / _life) * 0.30
	draw_circle(Vector2(1, -18), 13.0, Color(_color, a))
	draw_rect(Rect2(-9, -8, 20, 28), Color(_color, a))
	draw_line(Vector2(-7, 18), Vector2(-7, 24), Color(_color, a), 4.0)
	draw_line(Vector2(8, 18), Vector2(8, 24), Color(_color, a), 4.0)
