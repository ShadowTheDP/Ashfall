extends Node
## Dev-only capture harness. Instantiates the real game, drives input and saves
## screenshots to output/screenshots/. Run:
##   godot --path . tests/capture_scene.tscn
## Requires a rendering display (not --headless).

var _dir := "res://output/screenshots"
var _main: Node


func _ready() -> void:
	_main = $Main
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	await get_tree().process_frame
	await get_tree().create_timer(0.55).timeout
	await _shot("01_idle")
	_report("idle")

	Input.action_press("move_right")
	await get_tree().create_timer(0.65).timeout
	await _shot("02_run")

	Input.action_press("jump")
	await get_tree().create_timer(0.04).timeout
	Input.action_release("jump")
	await get_tree().create_timer(0.18).timeout
	await _shot("03_air")
	Input.action_release("move_right")

	await get_tree().create_timer(0.35).timeout
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
	await get_tree().create_timer(0.16).timeout
	await _shot("06_finisher")
	_report("after attacks")

	Input.action_press("roll")
	await get_tree().create_timer(0.03).timeout
	Input.action_release("roll")
	await get_tree().create_timer(0.10).timeout
	await _shot("07_roll")

	await get_tree().create_timer(0.7).timeout
	_spawn_bestiary()
	await get_tree().create_timer(0.35).timeout
	await _shot("08_bestiary")
	_report("bestiary")

	_main.hud._set_paused(true)
	await get_tree().create_timer(0.15).timeout
	await _shot("09_pause")
	_main.hud._set_paused(false)
	await get_tree().create_timer(0.10).timeout

	get_tree().quit()


func _spawn_bestiary() -> void:
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	var player := Game.player
	var specs := [
		["grunt", Vector2(90.0, -10.0)],
		["archer", Vector2(210.0, -80.0)],
		["charger", Vector2(-190.0, -10.0)],
	]
	for spec in specs:
		var enemy := scene.instantiate() as Enemy
		enemy.configure(spec[0], Data.enemies.get(spec[0], {}), 1.0)
		enemy.position = player.global_position + spec[1]
		enemy._spawn_t = 999.0
		_main.world.add_child(enemy)


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
