class_name SlashFx
extends Node2D
## The arc the blade TIP swept, drawn as disconnected dashes on a single
## radius. No filled band, no concentric rings: at 38-50 px any band reads as
## a "mooncake" instead of speed. Dashes can only read as motion.
##
## The trail deliberately stops short of the blade and lives BEHIND it, so
## blade + trail can never fuse into an L.

var facing := 1
var color := MathArt.WHITE
var radius := 38.0
var arc := 1.05
var _t := 0.0
var _life := 0.13


func setup(attack_index: int, is_facing: int, tint: Color, blade_length: float = 38.0) -> void:
	facing = is_facing
	color = tint
	scale.x = float(facing)
	radius = blade_length
	match attack_index:
		0:
			arc = 0.95
		1:
			arc = 1.05
		_:
			arc = 1.35
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
	# The whole trail drifts forward and thins out.
	var a0 := -arc + k * 0.55
	var a1 := -0.30 + k * 0.55
	if a1 <= a0:
		return
	var span := a1 - a0
	var dashes := 4
	for i in dashes:
		var t0 := float(i) / float(dashes)
		var t1 := t0 + 0.58 / float(dashes)
		var near := 1.0 - t0
		var width := lerpf(1.2, 2.6, near)
		var tone := alpha * lerpf(0.42, 1.0, near * near)
		MathArt.arc(self, Vector2.ZERO, radius, a0 + span * t0, a0 + span * t1,
			Color(color, tone), width)
	# Two shed sparks behind the trail, well clear of the dashes.
	for i in 2:
		var a := a0 - 0.10 - float(i) * 0.16
		var dir := Vector2.from_angle(a)
		var from := dir * (radius + 2.0)
		MathArt.line(self, from, from + dir * 5.0,
			Color(MathArt.WHITE, alpha * (0.45 - float(i) * 0.15)), 1.0)
