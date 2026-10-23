class_name ShatterFx
extends Node2D
## Death shatter: an enemy breaks into its own polygon archetype.

var _shards: Array[Dictionary] = []
var _t := 0.0
var _life := 0.55


func setup(tint: Color, sides: int, count: int, speed: float) -> void:
	for i in count:
		var angle := randf() * TAU
		var velocity := Vector2.from_angle(angle) * randf_range(speed * 0.25, speed)
		_shards.append({
			"pos": Vector2(randf_range(-6.0, 6.0), randf_range(-24.0, 4.0)),
			"vel": velocity + Vector2(0, -120.0),
			"spin": randf_range(-7.0, 7.0),
			"angle": randf() * TAU,
			"size": randf_range(3.0, 7.5),
			"sides": maxi(3, sides if sides > 2 else 3 + i % 3),
			"tint": tint,
		})
	z_index = 7


func _process(delta: float) -> void:
	_t += delta
	var alive: Array[Dictionary] = []
	for shard in _shards:
		shard["vel"] += Vector2(0, 760.0 * delta)
		shard["pos"] += shard["vel"] * delta
		shard["angle"] = float(shard["angle"]) + float(shard["spin"]) * delta
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
		var points := MathArt.ngon(int(shard["sides"]), float(shard["size"]) * (0.5 + 0.5 * fade),
			float(shard["angle"]), shard["pos"])
		MathArt.draw_poly(self, points, Color(tint, 0.55 * fade), Color(tint, 0.85 * fade), 1.0)
