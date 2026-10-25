extends Node
## Deterministic combat probe. Spawns one passive enemy in front of the player
## and drives real input so hit detection, damage and death are verified without
## relying on wave position randomness.
##
## Run: godot --headless --path . tests/combat_probe.tscn

var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout

	var main := $Main
	var player := Game.player
	if player == null:
		_fail("player was not created")
		_finish()
		return

	# Isolate the probe from wave spawns so timings are deterministic.
	main.encounter.started = false
	for wave_enemy in main.encounter.alive:
		wave_enemy.queue_free()
	main.encounter.alive.clear()
	Game.enemies_left = 0

	var enemy_scene: PackedScene = load("res://scenes/enemy.tscn")
	var enemy := enemy_scene.instantiate() as Enemy
	enemy.configure("grunt", Data.enemies.get("grunt", {}), 1.0)
	enemy.position = player.global_position + Vector2(52.0, 0.0)
	main.world.add_child(enemy)
	enemy._spawn_t = 999.0

	await get_tree().create_timer(0.30).timeout
	var start_hp := enemy.hp
	print("probe: enemy hp=%.0f state=%d" % [enemy.hp, enemy.state])

	var killed := false
	for swing in 4:
		Input.action_press("attack")
		await get_tree().create_timer(0.03).timeout
		Input.action_release("attack")
		await get_tree().create_timer(0.42).timeout
		if not is_instance_valid(enemy):
			print("probe: swing %d -> enemy freed, combo=%d" % [swing + 1, Game.combo])
			killed = true
			break
		print("probe: swing %d -> enemy hp=%.0f dead=%s combo=%d" % [
			swing + 1, enemy.hp, str(enemy._dead), Game.combo
		])
		if enemy._dead:
			killed = true
			break

	if start_hp <= 0.0:
		_fail("enemy started dead")
	if Game.combo < 1:
		_fail("player attacks never registered a hit (combo stayed 0)")
	if is_instance_valid(enemy) and not enemy._dead and enemy.hp >= start_hp:
		_fail("enemy hp did not decrease")
	if not killed:
		_fail("four combo swings did not kill a 42 hp husk")

	await get_tree().create_timer(1.2).timeout
	if Game.cells < 1:
		_fail("killed enemy did not grant cells")
	if Game.kills < 1:
		_fail("kill was not counted")

	# Feel rules: hurt i-frames and roll i-frames must actually block damage.
	await get_tree().create_timer(0.7).timeout
	player.hp = player.max_hp
	player.invuln = 0.0
	player.state = Player.State.IDLE
	player.velocity = Vector2.ZERO
	var hp_before := player.hp
	player.take_hit({"damage": 10, "knockback": 200.0, "source_pos": player.global_position - Vector2(40, 0)})
	if player.hp >= hp_before:
		_fail("taking a hit did not reduce player hp")
	var hp_after_hit := player.hp
	player.take_hit({"damage": 10, "knockback": 200.0, "source_pos": player.global_position - Vector2(40, 0)})
	if player.hp != hp_after_hit:
		_fail("post-hit invulnerability did not block a second hit")

	await get_tree().create_timer(0.8).timeout
	player._start_roll(1.0)
	await get_tree().create_timer(0.08).timeout
	var hp_before_roll := player.hp
	player.take_hit({"damage": 10, "knockback": 200.0, "source_pos": player.global_position - Vector2(40, 0)})
	if player.hp != hp_before_roll:
		_fail("roll i-frames did not block damage")

	await get_tree().create_timer(0.5).timeout
	var hp_after_roll := player.hp
	player.take_hit({"damage": 10, "knockback": 200.0, "source_pos": player.global_position - Vector2(40, 0)})
	if player.hp >= hp_after_roll:
		_fail("damage did not land after roll i-frames ended")

	# A roll window LONGER than the roll itself. Armour + GHOST + GLASS can reach
	# 0.43 s against a 0.30 s roll; before this was fixed the gate required
	# `state == ROLL`, so the last 0.13 s of a purchased upgrade simply did not
	# exist and a hit landed while the player was told they were untouchable.
	await get_tree().create_timer(0.8).timeout
	player.roll_iframe_end = 0.40
	player.invuln = 0.0
	var dodges_before := Game.perfect_dodges
	player._start_roll(1.0)
	await get_tree().create_timer(0.34).timeout
	if player.state == Player.State.ROLL:
		_fail("the roll was still running at 0.34 s; the probe tests the tail")
	var hp_before_tail := player.hp
	player.take_hit({"damage": 10, "knockback": 200.0, "source_pos": player.global_position - Vector2(40, 0)})
	if player.hp != hp_before_tail:
		_fail("a hit landed inside the roll window's tail (0.34 s of 0.40 s)")
	if Game.perfect_dodges != dodges_before + 1:
		_fail("the tail of the window did not pay a perfect dodge")
	# And it must NOT pay once the window is over.
	player.roll_iframe_end = Player.BASE_ROLL_IFRAME_END
	await get_tree().create_timer(0.4).timeout
	player.invuln = 0.0
	player._start_roll(1.0)
	await get_tree().create_timer(0.40).timeout
	var dodges_after := Game.perfect_dodges
	player.take_hit({"damage": 10, "knockback": 200.0, "source_pos": player.global_position - Vector2(40, 0)})
	if Game.perfect_dodges != dodges_after:
		_fail("a hit outside the roll window still counted as a perfect dodge")

	_finish()


func _fail(message: String) -> void:
	_failures += 1
	push_error("PROBE FAIL: " + message)
	print("PROBE FAIL: ", message)


func _finish() -> void:
	if _failures == 0:
		print("PROBE OK")
	else:
		print("PROBE FAILED (%d)" % _failures)
	await get_tree().create_timer(0.9).timeout
	get_tree().quit(0 if _failures == 0 else 1)
