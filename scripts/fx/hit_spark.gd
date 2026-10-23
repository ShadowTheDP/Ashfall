class_name HitSpark
extends Node2D
## Impact frame. The classic action-game read:
##   frame 0-1  a white pixel cross + a filled core
##   frame 2-6  rays shrink, shards fly out
## Everything is snapped to whole pixels.

var color := Color.WHITE
var direction := Vector2.RIGHT
var crit := false
var _t := 0.0
var _life := 0.18
var _rays: Array[Dictionary] = []
var _shards: Array[Dictionary] = []


func setup(hit_direction: Vector2, is_crit: bool, tint: Color) -> void:
	direction = hit_direction.normalized() if hit_direction.length() > 0.01 else Vector2.RIGHT
	crit = is_crit
	color = tint
	var count := 10 if crit else 6
	for i in count:
		_rays.append({
			"angle": direction.angle() + float(i) * MathArt.GOLDEN_ANGLE,
			"length": float(MathArt.fibonacci(4 + i % 4)) * (1.5 if crit else 1.1),
		})
	for i in (4 if crit else 2):
		_shards.append({
			"angle": direction.angle() + float(i) * TAU / float(4 if crit else 2) + randf_range(-0.3, 0.3),
			"speed": randf_range(90.0, 190.0),
		})
	z_index = 9


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / _life, 0.0, 1.0)
	var alpha := 1.0 - k
	var flash := clampf(1.0 - _t / 0.05, 0.0, 1.0)

	# Rays: 1px lines with a bright cap.
	for ray in _rays:
		var angle: float = ray["angle"]
		var start := Vector2.from_angle(angle) * (2.0 + 10.0 * k)
		var length := float(ray["length"]) * (1.0 - k * 0.45)
		var end := start + Vector2.from_angle(angle) * length
		MathArt.px_line(self, start, end, Color(color, alpha * 0.85), 1.0)
		MathArt.px_rect(self, Rect2(roundf(end.x), roundf(end.y), 2, 2), Color(MathArt.WHITE, alpha * 0.7))

	# Shards.
	for shard in _shards:
		var angle: float = float(shard["angle"])
		var distance := float(shard["speed"]) * _t
		var point := Vector2.from_angle(angle) * distance
		var size := 3.0 if crit else 2.0
		MathArt.px_rect(self, Rect2(roundf(point.x), roundf(point.y), size, size), Color(color, alpha * 0.8))

	# Core: white flash then a shrinking coloured square.
	if flash > 0.0:
		var size := (14.0 if crit else 10.0) * (1.0 + flash * 0.6)
		MathArt.px_rect(self, Rect2(-size * 0.5, -size * 0.5, size, size), Color(MathArt.WHITE, flash))
		MathArt.px_line(self, Vector2(-size * 1.4, 0), Vector2(size * 1.4, 0), Color(MathArt.WHITE, flash * 0.9), 1.0)
		MathArt.px_line(self, Vector2(0, -size * 1.4), Vector2(0, size * 1.4), Color(MathArt.WHITE, flash * 0.9), 1.0)
	var core := (6.0 if crit else 4.0) * (1.0 - k)
	if core >= 1.0:
		MathArt.px_rect(self, Rect2(-roundf(core * 0.5), -roundf(core * 0.5), roundf(core), roundf(core)), Color(color, alpha))
	if crit:
		# A tiny 5-point star for crits only.
		MathArt.px_poly(self, MathArt.star(5, 13.0 * (1.0 - k * 0.5), 5.0 * (1.0 - k * 0.5), _t * 3.0),
			Color(0, 0, 0, 0), Color(MathArt.WHITE, alpha * 0.7), 1.0)
