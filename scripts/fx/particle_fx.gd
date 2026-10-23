class_name ParticleFx
extends Node2D
## Tiny procedural particle node used for dust, death bursts and pickups.

var _particles: Array[Dictionary] = []
var _t := 0.0
var _life := 0.6
var _gravity := 420.0
var _drag := 1.4


func burst(count: int, tint: Color, speed: float, spread: float, direction: Vector2, size_range: Vector2) -> void:
	for i in count:
		var angle := direction.angle() + randf_range(-spread, spread)
		var vel := Vector2.from_angle(angle) * randf_range(speed * 0.35, speed)
		_particles.append({
			"pos": Vector2(randf_range(-4, 4), randf_range(-4, 4)),
			"vel": vel,
			"size": randf_range(size_range.x, size_range.y),
			"color": tint,
		})
	z_index = 6


func setup_dust(count: int, direction: Vector2) -> void:
	for i in count:
		_particles.append({
			"pos": Vector2(randf_range(-8, 8), randf_range(-2, 2)),
			"vel": Vector2(randf_range(-70, 70) - direction.x * 40.0, randf_range(-46, -8)),
			"size": randf_range(2.0, 5.0),
			"color": Color(0.55, 0.58, 0.62, 0.5),
		})
	_gravity = 120.0
	_life = 0.4
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
		draw_circle(particle["pos"], float(particle["size"]) * (0.4 + 0.6 * fade), tint)
