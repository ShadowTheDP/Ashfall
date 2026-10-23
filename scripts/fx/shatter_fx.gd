class_name ShatterFx
extends Node2D
## Death shatter: the enemy's own polygon breaks into pixel chunks.

var _shards: Array[Dictionary] = []
var _t := 0.0
var _life := 0.55


func setup(tint: Color, sides: int, count: int, speed: float) -> void:
	for i in count:
		var angle := randf() * TAU
		var velocity := Vector2.from_angle(angle) * randf_range(speed * 0.25, speed)
		_shards.append({
			"pos": Vector2(randf_range(-5.0, 5.0), randf_range(-20.0, 4.0)),
			"vel": velocity + Vector2(0, -110.0),
			"angle": randf() * TAU,
			"size": roundf(randf_range(2.0, 4.0)),
			"sides": maxi(3, sides if sides > 2 else 3 + i % 3),
			"tint": tint,
		})
	z_index = 7


func _process(delta: float) -> void:
	_t += delta
	var alive: Array[Dictionary] = []
	for shard in _shards:
		shard["vel"] += Vector2(0, 720.0 * delta)
		shard["pos"] += shard["vel"] * delta
		shard["angle"] = float(shard["angle"]) + delta * 6.0
		if _t < _life:
			alive.append(shard)
	_shards = alive
	queue_redraw()
	if _t >= _life:
		queue_free()


func _draw() -> void:
	var fade := clampf(1.0 - _t / _life, 0.0, 1.0)
	for shard in _shards:
		var tint: Color = shard["tint"]
		var pos: Vector2 = shard["pos"]
		var size: float = shard["size"]
		if int(shard["sides"]) == 4:
			MathArt.px_rect(self, Rect2(roundf(pos.x), roundf(pos.y), size, size), Color(tint, 0.85 * fade))
		else:
			MathArt.px_poly(self, MathArt.ngon(int(shard["sides"]), size, float(shard["angle"]), pos),
				Color(tint, 0.6 * fade), Color(tint, 0.9 * fade), 1.0)
