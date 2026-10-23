class_name ParticleFx
extends Node2D
## Chunky pixel particles. Positions are snapped to whole pixels so they stay
## crisp after the integer upscale.

var _particles: Array[Dictionary] = []
var _t := 0.0
var _life := 0.6
var _gravity := 420.0
var _drag := 1.4


func burst(count: int, tint: Color, speed: float, spread: float, direction: Vector2, size_range: Vector2) -> void:
	for i in count:
		var angle := direction.angle() + randf_range(-spread, spread)
		var velocity := Vector2.from_angle(angle) * randf_range(speed * 0.35, speed)
		_particles.append({
			"pos": Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0)),
			"vel": velocity,
			"size": roundf(randf_range(size_range.x, size_range.y)),
			"color": tint,
		})
	z_index = 6


func setup_dust(count: int, direction: Vector2) -> void:
	for i in count:
		_particles.append({
			"pos": Vector2(randf_range(-7.0, 7.0), randf_range(-2.0, 2.0)),
			"vel": Vector2(randf_range(-70.0, 70.0) - direction.x * 40.0, randf_range(-44.0, -8.0)),
			"size": roundf(randf_range(1.0, 2.0)),
			"color": Color(MathArt.STEEL_DIM, 0.55),
		})
	_gravity = 110.0
	_life = 0.42
	z_index = 5


func _process(delta: float) -> void:
	_t += delta
	var alive: Array[Dictionary] = []
	for particle in _particles:
		particle["vel"] += Vector2(0.0, _gravity * delta)
		particle["vel"] *= (1.0 - _drag * delta)
		particle["pos"] += particle["vel"] * delta
		if _t < _life:
			alive.append(particle)
	_particles = alive
	queue_redraw()
	if _t >= _life:
		queue_free()


func _draw() -> void:
	var fade := clampf(1.0 - _t / _life, 0.0, 1.0)
	for particle in _particles:
		var tint: Color = particle["color"]
		tint.a *= fade
		var pos: Vector2 = particle["pos"]
		var size: float = particle["size"]
		MathArt.px_rect(self, Rect2(roundf(pos.x), roundf(pos.y), size, size), tint)
