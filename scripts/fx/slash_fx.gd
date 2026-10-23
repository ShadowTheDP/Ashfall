class_name SlashFx
extends Node2D
## Pixel smear arc for a swing. Three bands of decreasing width give the arc
## volume without blurring the sprite.

var facing := 1
var color := MathArt.CYAN
var radius := 21.0
var arc := 2.2
var _t := 0.0
var _life := 0.15


func setup(attack_index: int, is_facing: int, tint: Color) -> void:
	facing = is_facing
	color = tint
	scale.x = float(facing)
	match attack_index:
		0:
			arc = 2.1
			radius = 20.0
		1:
			arc = 2.2
			radius = 21.0
		_:
			arc = 2.9
			radius = 26.0
	z_index = 7


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / _life, 0.0, 1.0)
	var alpha := 1.0 - k
	var a0 := -arc * 0.5 + k * 0.9
	var a1 := arc * 0.5 + k * 0.9
	var outer := radius * (0.95 + 0.10 * k)
	MathArt.px_arc(self, Vector2.ZERO, outer, a0, a1, Color(color, alpha * 0.20), 4.0)
	MathArt.px_arc(self, Vector2.ZERO, outer - 3.0, a0, a1, Color(color, alpha * 0.40), 3.0)
	MathArt.px_arc(self, Vector2.ZERO, outer - 6.0, a0, a1, Color(MathArt.WHITE, alpha * 0.65), 1.0)
	# Leading edge cap.
	var edge := Vector2.from_angle(a1) * outer
	MathArt.px_rect(self, Rect2(roundf(edge.x) - 1.0, roundf(edge.y) - 1.0, 3, 3), Color(MathArt.WHITE, alpha * 0.9))
