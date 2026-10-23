extends Node
## Dev-only capture harness. Drives the real game and saves screenshots to
## output/screenshots/. Run:
##   godot --path . tests/capture_scene.tscn
## Requires a rendering display (not --headless).

var _dir := "res://output/screenshots"
var _main: Node


func _ready() -> void:
	_main = $Main
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout

	# Controlled stage: no random wave pressure during the art pass.
	_main.encounter.started = false
	for enemy in _main.encounter.alive:
		enemy.queue_free()
	_main.encounter.alive.clear()
	Game.enemies_left = 0
	Game.wave = 1
	Game.wave_total = 4
	Game.announce_t = 0.0

	var dummy := _spawn_enemy("grunt", Vector2(72.0, 0.0), 999.0)
	await get_tree().create_timer(0.5).timeout
	await _shot("01_idle")
	_report("idle")

	Input.action_press("move_right")
	await get_tree().create_timer(0.45).timeout
	await _shot("02_run")

	Input.action_press("jump")
	await get_tree().create_timer(0.04).timeout
	Input.action_release("jump")
	await get_tree().create_timer(0.18).timeout
	await _shot("03_air")
	Input.action_release("move_right")

	await get_tree().create_timer(0.3).timeout
	Input.action_press("attack")
	await get_tree().create_timer(0.03).timeout
	Input.action_release("attack")
	await get_tree().create_timer(0.12).timeout
	await _shot("04_attack")

	await get_tree().create_timer(0.14).timeout
	Input.action_press("attack")
	await get_tree().create_timer(0.03).timeout
	Input.action_release("attack")
	await get_tree().create_timer(0.20).timeout
	await _shot("05_combo")

	Input.action_press("attack")
	await get_tree().create_timer(0.03).timeout
	Input.action_release("attack")
	await get_tree().create_timer(0.18).timeout
	await _shot("06_finisher")

	await get_tree().create_timer(0.45).timeout
	Game.player._start_attack(2)
	await get_tree().create_timer(0.21).timeout
	await _shot("06b_function_wave")

	Input.action_press("roll")
	await get_tree().create_timer(0.03).timeout
	Input.action_release("roll")
	await get_tree().create_timer(0.10).timeout
	await _shot("07_roll")
	_report("after attacks")

	await get_tree().create_timer(0.5).timeout
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().create_timer(0.15).timeout
	_spawn_enemy("grunt", Vector2(330.0, -10.0), 999.0)
	await get_tree().create_timer(0.2).timeout
	Input.action_press("throw")
	await get_tree().create_timer(0.03).timeout
	Input.action_release("throw")
	await get_tree().create_timer(0.13).timeout
	await _shot("08_kunai")

	Input.action_press("aegis")
	await get_tree().create_timer(0.03).timeout
	Input.action_release("aegis")
	await get_tree().create_timer(0.10).timeout
	await _shot("09_aegis")

	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().create_timer(0.2).timeout
	_spawn_enemy("grunt", Vector2(90.0, -10.0))
	_spawn_enemy("archer", Vector2(210.0, -150.0))
	_spawn_enemy("charger", Vector2(-170.0, -10.0))
	_spawn_enemy("bulwark", Vector2(-300.0, -10.0))
	_spawn_enemy("warden", Vector2(360.0, -30.0))
	await get_tree().create_timer(0.45).timeout
	await _shot("10_bestiary")
	_report("bestiary")

	_main.reward_screen.open(["vitality", "edge", "armory"])
	await get_tree().create_timer(0.2).timeout
	await _shot("11_reward")
	_main.reward_screen._pick(0)
	await get_tree().create_timer(0.1).timeout

	_main.hud._set_paused(true)
	await get_tree().create_timer(0.15).timeout
	await _shot("12_pause")
	_main.hud._set_paused(false)
	await get_tree().create_timer(0.1).timeout

	get_tree().quit()


func _spawn_enemy(kind: String, offset: Vector2, hp_override: float = 0.0) -> Enemy:
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	var enemy := scene.instantiate() as Enemy
	enemy.configure(kind, Data.enemies.get(kind, {}), 1.0)
	if hp_override > 0.0:
		enemy.max_hp = hp_override
		enemy.hp = hp_override
	enemy.position = Game.player.global_position + offset
	_main.world.add_child(enemy)
	enemy._spawn_t = 999.0
	return enemy


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_dir, name]
	image.save_png(ProjectSettings.globalize_path(path))
	print("saved ", path)


func _report(label: String) -> void:
	var player := Game.player
	var hp := -1.0
	var max_hp := -1.0
	if player != null:
		hp = player.hp
		max_hp = player.max_hp
	print(
		"[%s] hp=%.0f/%.0f cells=%d kills=%d combo=%d wave=%d enemies=%d over=%s" % [
			label, hp, max_hp, Game.cells, Game.kills, Game.combo,
			Game.wave, Game.enemies_left, str(Game.run_over)
		]
	)
