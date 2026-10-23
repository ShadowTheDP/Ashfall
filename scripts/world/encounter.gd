class_name Encounter
extends Node
## Wave director for the prototype. Hand-authored waves keep early balance
## readable; room generation is a later pillar.

const WAVES := [
	[["grunt", 3]],
	[["grunt", 2], ["archer", 1]],
	[["grunt", 2], ["archer", 1], ["charger", 1]],
]

var world: Node2D
var alive: Array[Enemy] = []
var wave_index := -1
var waiting := -1.0
var started := false
var finished := false

var _enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")


func start() -> void:
	started = true
	_next_wave()


func _process(delta: float) -> void:
	if not started or finished or Game.run_over:
		return
	if waiting > 0.0:
		waiting -= delta
		if waiting <= 0.0:
			waiting = -1.0
			_next_wave()


func _next_wave() -> void:
	wave_index += 1
	if wave_index >= WAVES.size():
		finished = true
		Game.end_run(true)
		return

	Game.wave = wave_index + 1
	Game.wave_total = WAVES.size()
	if wave_index > 0 and Game.player != null:
		Game.player.heal(25.0)
	Game.announce("WAVE %d" % (wave_index + 1), 1.4)
	Sfx.play("wave", -11)

	var ground_points: Array = Arena.GROUND_SPAWNS.duplicate()
	var platform_points: Array = Arena.PLATFORM_SPAWNS.duplicate()
	ground_points.shuffle()
	platform_points.shuffle()
	var hp_scale := 1.0 + 0.10 * float(wave_index)

	for group in WAVES[wave_index]:
		var kind: String = group[0]
		var count: int = group[1]
		for i in count:
			var enemy := _enemy_scene.instantiate() as Enemy
			enemy.configure(kind, Data.enemies.get(kind, {}), hp_scale)
			var pool := platform_points if kind == "archer" and not platform_points.is_empty() else ground_points
			enemy.position = _take_spawn_point(pool)
			world.add_child(enemy)
			enemy.died.connect(_on_enemy_died)
			alive.append(enemy)

	Game.enemies_left = alive.size()


func _take_spawn_point(points: Array) -> Vector2:
	var fallback := Vector2(1200.0, -42.0)
	while not points.is_empty():
		var point: Vector2 = points.pop_back()
		if Game.player == null:
			return point
		if point.distance_to(Game.player.global_position) > 190.0:
			return point
		fallback = point
	return fallback


func _on_enemy_died(enemy: Enemy) -> void:
	alive.erase(enemy)
	Game.enemies_left = alive.size()
	if not alive.is_empty() or finished or Game.run_over:
		return
	if wave_index >= WAVES.size() - 1:
		finished = true
		Game.announce("FLOOR CLEARED", 2.0)
		Game.end_run(true)
	else:
		waiting = 1.5
		Game.announce("WAVE CLEARED", 1.2)
