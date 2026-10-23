extends Node
## Captures the exact frames around a hit so impact feedback can be reviewed.
## Run: godot --path . tests/impact_capture.tscn

var _main: Node


func _ready() -> void:
	_main = $Main
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/screenshots"))
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout

	_main.encounter.started = false
	for enemy in _main.encounter.alive:
		enemy.queue_free()
	_main.encounter.alive.clear()
	Game.enemies_left = 0

	var scene: PackedScene = load("res://scenes/enemy.tscn")
	var enemy := scene.instantiate() as Enemy
	enemy.configure("grunt", Data.enemies.get("grunt", {}), 1.0)
	enemy.max_hp = 9999.0
	enemy.hp = 9999.0
	enemy.position = Game.player.global_position + Vector2(46.0, 0.0)
	_main.world.add_child(enemy)
	enemy._spawn_t = 999.0

	await get_tree().create_timer(0.25).timeout

	# Drive the three combo steps and capture every 25 ms around the contact.
	Input.action_press("attack")
	await get_tree().create_timer(0.03).timeout
	Input.action_release("attack")

	for i in 10:
		await get_tree().create_timer(0.025).timeout
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png(ProjectSettings.globalize_path("res://output/screenshots/hit_%02d.png" % i))
	print("captured 10 hit frames")

	# Finisher for the heavy impact.
	await get_tree().create_timer(0.5).timeout
	Game.player._start_attack(2)
	for i in 10:
		await get_tree().create_timer(0.03).timeout
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png(ProjectSettings.globalize_path("res://output/screenshots/fin_%02d.png" % i))
	print("captured 10 finisher frames")
	get_tree().quit()
