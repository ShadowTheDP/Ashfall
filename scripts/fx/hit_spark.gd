class_name HitSpark
extends Node2D
## Impact burst built from golden-angle rays and Fibonacci lengths.

var color := Color.WHITE
var direction := Vector2.RIGHT
var crit := false
var _t := 0.0
var _life := 0.17
var _rays: Array[Dictionary] = []
var _shards: Array[Dictionary] = []


func setup(hit_direction: Vector2, is_crit: bool, tint: Color) -> void:
	direction = hit_direction.normalized() if hit_direction.length() > 0.01 else Vector2.RIGHT
	crit = is_crit
	color = tint
	var count := 13 if crit else 8
	for i in count:
		_rays.append({
			"angle": direction.angle() + float(i) * MathArt.GOLDEN_ANGLE,
			"length": float(MathArt.fibonacci(4 + i % 4)) * (1.6 if crit else 1.2),
			"width": 1.0 + float(i % 3) * 0.5,
		})
	for i in (5 if crit else 3):
		_shards.append({
			"angle": direction.angle() + float(i) * TAU / float(5 if crit else 3),
			"radius": 10.0 + float(i) * 3.0,
			"spin": randf_range(-6.0, 6.0),
		})
	z_index = 8


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / _life, 0.0, 1.0)
	var alpha := 1.0 - k
	for ray in _rays:
		var angle: float = ray["angle"]
		var start := Vector2.from_angle(angle) * (3.0 + 18.0 * k)
		var end := start + Vector2.from_angle(angle) * float(ray["length"]) * (1.0 - k * 0.35)
		draw_line(start, end, Color(color, alpha), float(ray["width"]))
	for shard in _shards:
		var angle: float = float(shard["angle"])
		var center := Vector2.from_angle(angle) * float(shard["radius"]) * (1.0 + k * 1.5)
		var points := MathArt.ngon(3, 3.6 * (1.0 - k * 0.4), float(shard["spin"]) * _t, center)
		MathArt.draw_poly(self, points, Color(color, alpha * 0.55))
	draw_circle(Vector2.ZERO, (7.0 if crit else 4.5) * (1.0 - k), Color(1.0, 1.0, 1.0, alpha * 0.9))
	draw_circle(Vector2.ZERO, (14.0 if crit else 8.0) * (1.0 - k), Color(color, alpha * 0.20))
	if crit:
		MathArt.draw_poly(self, MathArt.star(5, 20.0 * (1.0 - k * 0.3), 8.0 * (1.0 - k * 0.3), _t * 2.0),
			Color(0, 0, 0, 0), Color(color, alpha * 0.55), 1.2)
