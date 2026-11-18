class_name ShockwaveFx
extends Node2D
## A cone of force, not a ring. RingFx is radial (it surrounds the origin);
## this one only exists in front of `facing`, so it reads as a directional
## shove -- two half-arcs plus an inscribed polygon rotating inside them.

var _facing := 1
var _radius := 60.0
var _tint := MathArt.FIRE
var _sides := 5
var _life := 0.32
var _t := 0.0


func setup(at: Vector2, facing: int, radius: float, tint: Color,
		sides: int = 0, life: float = 0.32) -> void:
	position = at
	_facing = 1 if facing >= 0 else -1
	_radius = maxf(6.0, radius)
	_tint = tint
	_sides = sides if sides > 2 else 5
	_life = maxf(0.05, life)
	z_index = 9


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / _life, 0.0, 1.0)
	var grow := ease(k, 2.0)
	var front := _radius * grow
	if front < 1.0:
		return
	var alpha := 1.0 - k
	# The cone spans +-0.85 rad around the facing direction, and the mouth
	# widens faster than the centre travels, so the front edge sweeps open.
	var center := 0.0 if _facing > 0 else PI
	var half := 0.85 + 0.5 * grow
	# Thickness tapers as the wave grows: a shock front thins out.
	var width := lerpf(3.2, 0.8, k)
	MathArt.px_arc(self, Vector2.ZERO, front, center - half, center + half,
		Color(_tint, alpha * 0.9), width)
	MathArt.px_arc(self, Vector2.ZERO, front * MathArt.INV_PHI, center - half * 0.75, center + half * 0.75,
		Color(_tint, alpha * 0.45), width * 0.6)
	# Inscribed polygon spins as it expands: the mathematical counterpoint that
	# keeps the half-ring from reading as a plain arc.
	var poly := MathArt.ngon(_sides, front * 0.82, center + k * 2.4 * float(_facing))
	MathArt.px_poly(self, poly, Color.TRANSPARENT, Color(_tint, alpha * 0.3), 1.0)
	# Front edge: a short bright chord at the cone mouth, so the direction is
	# unambiguous even in a single frame.
	var a := Vector2.from_angle(center - half * 0.6) * front
	var b := Vector2.from_angle(center + half * 0.6) * front
	MathArt.px_line(self, a, b, Color(_tint, alpha * 0.55), 1.0)
