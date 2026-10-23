class_name HitSpark
extends Node2D
## Short-lived impact burst. Cheap, drawn procedurally, no texture assets.

var color := Color.WHITE
var direction := Vector2.RIGHT
var crit := false
var _t := 0.0
var _life := 0.16
var _lines: Array[Dictionary] = []
var _size := 1.0


func setup(hit_direction: Vector2, is_crit: bool, tint: Color) -> void:
	direction = hit_direction.normalized() if hit_direction.length() > 0.01 else Vector2.RIGHT
	crit = is_crit
	color = tint
	_size = 1.45 if crit else 1.0
	var count := 12 if crit else 7
	for i in count:
		_lines.append({
			"angle": direction.angle() + randf_range(-1.1, 1.1),
			"length": randf_range(9.0, 24.0) * _size,
			"width": randf_range(1.0, 2.6),
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
	for line in _lines:
		var angle: float = line["angle"]
		var start := Vector2.from_angle(angle) * (4.0 + 20.0 * k)
		var end := start + Vector2.from_angle(angle) * float(line["length"]) * (1.0 - k * 0.4)
		draw_line(start, end, Color(color, alpha), float(line["width"]) * (1.0 - k * 0.5))
	draw_circle(Vector2.ZERO, (7.0 if crit else 4.5) * (1.0 - k), Color(1.0, 1.0, 1.0, alpha * 0.9))
	draw_circle(Vector2.ZERO, (12.0 if crit else 7.0) * (1.0 - k), Color(color, alpha * 0.25))
