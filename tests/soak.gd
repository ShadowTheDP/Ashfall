extends Node
## Soak test: runs the real scene, lets ranged/charging enemies attack an
## effectively invincible player, then clears waves to verify the whole
## encounter -> victory path.
##
## Run: godot --headless --path . tests/soak.tscn

var _failures := 0
var _main: Node


func _ready() -> void:
	_main = $Main
	await get_tree().process_frame

	var player := Game.player
	if player == null:
		_fail("player missing")
		_finish()
		return
	player.max_hp = 9999.0
	player.hp = 9999.0
	Game.auto_choose_rewards = true

	# Force one of each tricky enemy into the fight.
	_spawn("archer", player.global_position + Vector2(240.0, -100.0))
	_spawn("charger", player.global_position + Vector2(-220.0, -20.0))
	var shield_enemy := _spawn("bulwark", player.global_position + Vector2(380.0, -20.0))

	# Shield rule: front non-crit chips, back non-crit connects.
	await get_tree().create_timer(0.25).timeout
	var shield_hp := shield_enemy.hp
	shield_enemy.take_hit({
		"damage": 10, "crit": false, "knockback": 100.0, "hitstop": 0.0,
		"source_pos": shield_enemy.global_position + Vector2(float(shield_enemy.facing) * 40.0, 0),
	})
	if not is_equal_approx(shield_enemy.hp, shield_hp - 1.0):
		_fail("bulwark front hit should chip 1 hp, got %.1f" % shield_enemy.hp)
	shield_hp = shield_enemy.hp
	shield_enemy.take_hit({
		"damage": 10, "crit": false, "knockback": 100.0, "hitstop": 0.0,
		"source_pos": shield_enemy.global_position - Vector2(float(shield_enemy.facing) * 40.0, 0),
	})
	if not is_equal_approx(shield_enemy.hp, shield_hp - 10.0):
		_fail("bulwark back hit should connect, got %.1f" % shield_enemy.hp)

	await get_tree().create_timer(6.0).timeout
	print("soak: after enemy pressure hp=%.0f wave=%d enemies=%d" % [player.hp, Game.wave, Game.enemies_left])
	if player.hp >= 9999.0:
		_fail("ranged/charge enemies never damaged the player")

	var elapsed := 0.0
	while not Game.run_over and elapsed < 25.0:
		var target := _first_live_enemy()
		if target != null:
			target.take_hit({
				"damage": 999,
				"crit": false,
				"knockback": 120.0,
				"hitstop": 0.0,
				"source_pos": player.global_position,
				"point": target.global_position,
			})
		await get_tree().create_timer(0.20).timeout
		elapsed += 0.20

	if not Game.run_over:
		_fail("run did not finish within 25s")
	if not Game.victory:
		_fail("run ended without victory")
	if Game.kills < 10:
		_fail("expected at least 10 wave kills, got %d" % Game.kills)
	if not Game.boss_defeated:
		_fail("warden boss was never defeated")
	if Game.reward_counts.is_empty():
		_fail("auto reward path never granted a boon")

	print("soak: victory=%s kills=%d cells=%d max_combo=%d rewards=%d time=%.1fs" % [
		str(Game.victory), Game.kills, Game.cells, Game.max_combo,
		Game.reward_counts.size(), Game.run_time
	])
	_finish()


func _spawn(kind: String, at: Vector2) -> Enemy:
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	var enemy := scene.instantiate() as Enemy
	enemy.configure(kind, Data.enemies.get(kind, {}), 1.0)
	enemy.position = at
	_main.world.add_child(enemy)
	enemy._spawn_t = 0.0
	return enemy


func _first_live_enemy() -> Enemy:
	for enemy in _main.encounter.alive:
		if is_instance_valid(enemy) and not enemy._dead:
			return enemy
	return null


func _fail(message: String) -> void:
	_failures += 1
	push_error("SOAK FAIL: " + message)
	print("SOAK FAIL: ", message)


func _finish() -> void:
	if _failures == 0:
		print("SOAK OK")
	else:
		print("SOAK FAILED (%d)" % _failures)
	await get_tree().create_timer(0.4).timeout
	get_tree().quit(0 if _failures == 0 else 1)
