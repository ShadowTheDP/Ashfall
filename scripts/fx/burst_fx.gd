class_name BurstFx
extends Node2D
## Short, hard-edged pixel bursts. One node covers the three defensive reads:
##   "dodge"  — perfect dodge: 8 white rays fading over 3 frames
##   "block"  — Aegis: solid sector + ring, 5 frames, particles away from shield
##   "hurt"   — taking a hit: 4 red rays at the contact edge, 4 frames
## Rays and rings are sub-pixel geometry; only the small core uses whole pixels.

var mode := "dodge"
var tint := MathArt.WHITE
var facing := 1
var _t := 0.0
var _life := 0.05
var _rays: Array[Dictionary] = []


func setup(p_mode: String, p_tint: Color, p_facing: int = 1) -> void:
	mode = p_mode
	tint = p_tint
	facing = p_facing
	match mode:
		"dodge":
			_life = 0.05
			for i in 8:
				_rays.append({"angle": TAU * float(i) / 8.0, "len": 9.0})
		"block":
			_life = 0.083
			for i in 9:
				var angle := lerpf(-1.05, 1.05, float(i) / 8.0)
				_rays.append({"angle": angle, "len": 16.0})
		_:
			_life = 0.066
			for i in 4:
				_rays.append({"angle": -PI * 0.5 + float(i) * PI * 0.5, "len": 7.0})
	z_index = 9


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / _life, 0.0, 1.0)
	match mode:
		"dodge":
			_draw_dodge(k)
		"block":
			_draw_block(k)
		_:
			_draw_hurt(k)


func _draw_dodge(k: float) -> void:
	# White rays use 100% / 70% / 0% alpha over 3 frames.
	var alpha := 1.0 if k < 0.34 else (0.7 if k < 0.67 else 0.0)
	if alpha <= 0.0:
		return
	var color := MathArt.WHITE
	var radius := lerpf(4.0, 9.0, k)
	for ray in _rays:
		var angle: float = ray["angle"]
		var from_point := Vector2.from_angle(angle) * radius
		var to_point := Vector2.from_angle(angle) * (radius + float(ray["len"]) * (1.0 - k * 0.4))
		MathArt.px_line(self, from_point, to_point, Color(color, alpha), 1.0)
	MathArt.px_rect(self, Rect2(-2, -2, 4, 4), Color(MathArt.WHITE, alpha))


func _draw_block(k: float) -> void:
	# Frame 1: solid sector. Frames 2-5: ring expanding outward.
	var alpha := 1.0 if k < 0.2 else (0.85 if k < 0.4 else (0.55 if k < 0.6 else (0.2 if k < 0.8 else 0.0)))
	if alpha <= 0.0:
		return
	# Horizontal facing: a shield is held to the left or right of the body, never up.
	var base := 0.0 if facing > 0 else PI
	if k < 0.24:
		# Solid sector facing the block direction.
		var points := PackedVector2Array([Vector2.ZERO])
		for i in 7:
			var angle := base + float(facing) * lerpf(-1.05, 1.05, float(i) / 6.0)
			points.append(Vector2.from_angle(angle) * 12.0)
		MathArt.px_poly(self, points, Color(tint, 0.55 * alpha), Color(MathArt.WHITE, alpha), 1.0)
		return
	var radius := lerpf(6.0, 16.0, k)
	MathArt.px_ring(self, Vector2.ZERO, radius, Color(tint, alpha * 0.8), 2.0)
	for ray in _rays:
		var angle: float = base + float(facing) * float(ray["angle"])
		var from_point := Vector2.from_angle(angle) * (radius * 0.7)
		var to_point := Vector2.from_angle(angle) * (radius + 4.0)
		MathArt.px_line(self, from_point, to_point, Color(MathArt.WHITE, alpha * 0.7), 1.0)


func _draw_hurt(k: float) -> void:
	# 4 rays at the contact edge, never over the character's centre.
	var alpha := 1.0 - k
	for ray in _rays:
		var angle: float = float(ray["angle"]) + (0.0 if facing > 0 else PI)
		var from_point := Vector2.from_angle(angle) * 4.0
		var to_point := Vector2.from_angle(angle) * (4.0 + float(ray["len"]) * (0.4 + k))
		MathArt.px_line(self, from_point, to_point, Color(MathArt.WHITE, alpha * 0.85), 1.0)
	MathArt.px_rect(self, Rect2(-1, -1, 3, 3), Color(MathArt.WHITE, alpha))
