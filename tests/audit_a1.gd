extends Node
## Audit A1 probe: player / combat / weapon layer.
## Every check runs against a bare world (floor + a recording dummy) so the
## result does not depend on wave spawning, encounters or the hub.
##
## Run: godot --headless --path . tests/audit_a1.tscn

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const WEAPONS := ["rusty_sword", "arc_saber", "kiss_precision", "fractal_edge", "chain_lash", "orbit_rings"]
const CHARACTERS := ["square", "octa", "star", "torus", "helix", "gyro"]

var _failures := 0
var _world: Node2D
var _player: Player
var _dummy: Dummy
var _saved := {}
var _died := false


## Records what it is hit with. No AI, no movement, no death: a swing either
## lands on it or it does not, which is exactly what the audit needs to know.
class Dummy extends CharacterBody2D:
	var total := 0.0
	var hits := 0

	func _ready() -> void:
		collision_layer = Layers.ENEMY
		collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(24.0, 60.0)
		shape.shape = rect
		add_child(shape)

	func take_hit(info: Dictionary) -> void:
		total += float(info.get("damage", 0.0))
		hits += 1

	func reset() -> void:
		total = 0.0
		hits = 0


func _ready() -> void:
	await get_tree().process_frame
	_save_profile()
	_build_world()
	await _test_weapons()
	await _test_characters()
	await _test_armor()
	await _test_death_and_dodge()
	await _test_weapon_visual()
	_restore_profile()
	_finish()


# --- Harness ----------------------------------------------------------------

func _build_world() -> void:
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	Game.fx_root = _world
	var body := StaticBody2D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(4000.0, 60.0)
	shape.shape = rect
	shape.position = Vector2(0, 60)
	body.add_child(shape)
	_world.add_child(body)
	_dummy = Dummy.new()
	# Parked off-stage until a test places it: a body at the origin is what the
	# player would land on, and then every hitbox is aimed at empty air.
	_dummy.position = Vector2(6000.0, 6000.0)
	_world.add_child(_dummy)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## One physics frame of a real input press, so `is_action_just_pressed` sees it.
func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


func _spawn_player() -> void:
	if is_instance_valid(_player):
		_player.queue_free()
		await get_tree().process_frame
	Game.damage_mult = 1.0
	Game.edge_timer = 0.0
	Game.run_over = false
	Game.perfect_dodges = 0
	Engine.time_scale = 1.0
	Combat.cancel_hitstop()
	_died = false
	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = Vector2(0, -40)
	_world.add_child(_player)
	_player.died.connect(_on_died)
	# The first spawn can report a bogus floor contact before the static body is
	# registered, so wait for a real, settled landing before placing the dummy.
	var guard := 0
	while guard < 240:
		await get_tree().physics_frame
		guard += 1
		if _player.is_on_floor() and _player.global_position.y > 0.0 and absf(_player.velocity.y) < 1.0:
			break
	_player.velocity = Vector2.ZERO
	_dummy.position = _player.global_position + Vector2(44.0, 0.0)
	_dummy.reset()


func _on_died() -> void:
	_died = true


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL: ", message)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _save_profile() -> void:
	_saved = {
		"cells": Profile.cells,
		"souls": Profile.souls,
		"upgrades": Profile.upgrades.duplicate(true),
		"characters": Profile.unlocked_characters.duplicate(),
		"weapons": Profile.unlocked_weapons.duplicate(),
		"armor": Profile.unlocked_armor.duplicate(),
		"sel_character": Profile.selected_character,
		"sel_weapon": Profile.selected_weapon,
		"sel_armor": Profile.selected_armor,
		"runs": Profile.runs,
		"deaths": Profile.deaths,
		"total_kills": Profile.total_kills,
	}


func _restore_profile() -> void:
	Profile.cells = int(_saved["cells"])
	Profile.souls = int(_saved["souls"])
	Profile.upgrades = _saved["upgrades"]
	Profile.unlocked_characters = _saved["characters"]
	Profile.unlocked_weapons = _saved["weapons"]
	Profile.unlocked_armor = _saved["armor"]
	Profile.selected_character = str(_saved["sel_character"])
	Profile.selected_weapon = str(_saved["sel_weapon"])
	Profile.selected_armor = str(_saved["sel_armor"])
	Profile.runs = int(_saved["runs"])
	Profile.deaths = int(_saved["deaths"])
	Profile.total_kills = int(_saved["total_kills"])
	Profile.save()


# --- 1. Weapons -------------------------------------------------------------

func _test_weapons() -> void:
	print("\n--- 1. WEAPONS (3-step combo) ---")
	print("%-16s %-6s %-24s %s" % ["weapon", "result", "step damage", "hitbox reach / blade tip"])
	for id in WEAPONS:
		Profile.unlock_free("weapon", id)
		_check(Profile.select("weapon", id), "weapon selection saved: " + id)
		await _spawn_player()
		var cfg: Dictionary = Data.weapons.get(id, {})
		var combo: Array = cfg.get("combo", [])
		if not _check(combo.size() == 3, "%s: combo has %d steps" % [id, combo.size()]):
			continue
		if not _check(_player.weapon_combo.size() == 3, "%s: player combo not loaded" % id):
			continue

		var damage := await _drive_combo()
		var indices: Array = _last_indices

		var ok := true
		var text := ""
		for step in 3:
			var cfg_step: Dictionary = combo[step]
			var reach := float(cfg_step.get("offset", [0, 0])[0]) + float(cfg_step.get("size", [0, 0])[0]) * 0.5
			var tip := 13.0 + float(cfg_step.get("blade", 0.0))
			text += "%.0f/%.0f " % [float(damage[step]), float(cfg_step.get("damage", 0.0))]
			if not _check(reach >= tip, "%s step %d: box reaches %.0f but blade tip is %.0f" % [id, step, reach, tip]):
				ok = false
			if not _check(float(damage[step]) >= float(cfg_step.get("damage", 0.0)) - 0.01,
					"%s step %d: dealt %.1f, expected at least %.1f" % [id, step, float(damage[step]), float(cfg_step.get("damage", 0.0))]):
				ok = false
		if not _check(indices == [0, 1, 2], "%s: attack_index sequence was %s" % [id, str(indices)]):
			ok = false

		# The combo must return to the first step once it has finished.
		await _frames(40)
		await _tap("attack")
		await _frames(4)
		if not _check(_player.attack_index == 0, "%s: attack_index did not reset (got %d)" % [id, _player.attack_index]):
			ok = false
		print("%-16s %-6s %-24s %s" % [id, "PASS" if ok else "FAIL", text.strip_edges(), "ok" if ok else "see FAIL lines"])


var _last_indices: Array = []


## Drives a real 3-step combo through the input map. Returns the damage each
## step dealt, and records the attack_index that was live when it landed.
func _drive_combo() -> Array:
	var damage: Array = []
	var indices: Array = []
	for step in 3:
		_dummy.reset()
		if _player.state != Player.State.ATTACK:
			await _tap("attack")
		var guard := 0
		while _dummy.hits == 0 and guard < 160:
			await get_tree().physics_frame
			guard += 1
		damage.append(_dummy.total)
		indices.append(_player.attack_index)
		# Queue the next step while the current swing is still in flight.
		if step < 2:
			await _tap("attack")
	# The finisher wave and the echo repeat land a beat after the box opens, so
	# the last step's total is only final once they have all connected.
	await _frames(30)
	damage[2] = _dummy.total
	_last_indices = indices
	return damage


# --- 2. Character passives --------------------------------------------------

func _test_characters() -> void:
	print("\n--- 2. CHARACTER PASSIVES ---")
	var stats := {}
	for id in CHARACTERS:
		Profile.unlock_free("character", id)
		_check(Profile.select("character", id), "character selection saved: " + id)
		await _spawn_player()
		stats[id] = {
			"hp": _player.max_hp,
			"iframe": _player.roll_iframe_end,
			"crit": _player.crit_bonus,
			"taken": _player.armor_taken,
			"aegis": _player.aegis_time + _player.aegis_cooldown * _player.aegis_cooldown_scale,
			"dodge": _player.perfect_dodge_scale,
			"echo": _player.echo_every,
			"hp_now": _player.hp,
			"passive": _player.passive_id,
		}
		# A body must spawn at its own full hp, not at the previous body's.
		if not _check(is_equal_approx(_player.hp, _player.max_hp),
				"%s: hp %.0f != max_hp %.0f at spawn" % [id, _player.hp, _player.max_hp]):
			pass
		print("  %-8s passive=%-8s hp=%.0f/%.0f iframe=%.2f crit=%.2f taken=%.2f aegis=%.2f dodge=%.1f echo=%d" % [
			id, str(stats[id]["passive"]), float(stats[id]["hp_now"]), float(stats[id]["hp"]),
			float(stats[id]["iframe"]), float(stats[id]["crit"]), float(stats[id]["taken"]),
			float(stats[id]["aegis"]), float(stats[id]["dodge"]), int(stats[id]["echo"]),
		])

	var base: Dictionary = stats["square"]
	_check(float(stats["octa"]["iframe"]) > float(base["iframe"]), "glass: roll_iframe_end not longer")
	_check(float(stats["octa"]["hp"]) < float(base["hp"]), "glass: max_hp not lower")
	_check(float(stats["star"]["crit"]) > float(base["crit"]), "hunter: crit_bonus not larger")
	_check(float(stats["torus"]["taken"]) < float(base["taken"]), "bulwark: armor_taken not lower")
	_check(float(stats["torus"]["aegis"]) < float(base["aegis"]), "bulwark: aegis cooldown not shorter")
	_check(float(stats["helix"]["dodge"]) > 1.0, "dancer: perfect_dodge_scale not set")
	_check(int(stats["gyro"]["echo"]) > 0, "echo: echo_every not set")

	# Dancer: the scale has to reach the actual perfect-dodge window - EXACTLY,
	# because scaling it twice (Game.perfect_dodge() already multiplies by
	# perfect_dodge_scale, and player.take_hit used to multiply again) produced
	# 10 s from a 5 s promise and this assertion's old `> 1.5x` bound passed it.
	_check(Profile.select("character", "helix"), "dancer selection saved")
	await _spawn_player()
	Game.edge_timer = 0.0
	_player._start_roll(1.0)
	await _frames(8)
	_player.take_hit({"damage": 10.0, "source_pos": _player.global_position - Vector2(40.0, 0.0)})
	var dancer := Game.PERFECT_DODGE_TIME * 2.0
	_check(is_equal_approx(Game.edge_timer, dancer),
		"dancer: perfect dodge lasted %.2fs, expected %.2fs" % [Game.edge_timer, dancer])
	Combat.cancel_hitstop()

	# Echo: the third swing must repeat for 60% damage.
	_check(Profile.select("character", "gyro"), "echo selection saved")
	_check(Profile.select("weapon", "rusty_sword"), "echo weapon selection saved")
	await _spawn_player()
	var damage := await _drive_combo()
	var third := float(Data.weapons["rusty_sword"]["combo"][2]["damage"])
	_check(float(damage[2]) >= third * 1.5,
		"echo: third swing dealt %.1f, expected the %.1f repeat on top of %.1f" % [
			float(damage[2]), third * 0.6, third])
	print("  echo third swing damage=%.1f (base %.1f + wave 8)" % [float(damage[2]), third])
	_check(Profile.select("character", "square"), "reset character selection saved")


# --- 3. Armour --------------------------------------------------------------

func _test_armor() -> void:
	print("\n--- 3. ARMOUR ---")
	_check(Profile.select("character", "square"), "armor character selection saved")
	_check(Profile.select("armor", "none"), "base armor selection saved")
	await _spawn_player()
	var base := {
		"hp": _player.max_hp,
		"speed": _player.max_speed,
		"iframe": _player.roll_iframe_end,
		"knives": _player.knife_max,
	}
	var loss := {}
	for id in Data.armor.keys():
		Profile.unlock_free("armor", str(id))
		_check(Profile.select("armor", str(id)), "armor selection saved: " + str(id))
		await _spawn_player()
		var cfg: Dictionary = Data.armor[id]
		var ok := true
		ok = _check(is_equal_approx(_player.max_hp, float(base["hp"]) + float(cfg.get("hp", 0.0))),
			"%s: max_hp %.1f, expected %.1f" % [id, _player.max_hp, float(base["hp"]) + float(cfg.get("hp", 0.0))]) and ok
		ok = _check(is_equal_approx(_player.max_speed, float(base["speed"]) + float(cfg.get("speed", 0.0))),
			"%s: max_speed %.1f, expected %.1f" % [id, _player.max_speed, float(base["speed"]) + float(cfg.get("speed", 0.0))]) and ok
		ok = _check(is_equal_approx(_player.roll_iframe_end, float(base["iframe"]) + float(cfg.get("iframe", 0.0))),
			"%s: roll_iframe_end %.3f, expected %.3f" % [id, _player.roll_iframe_end, float(base["iframe"]) + float(cfg.get("iframe", 0.0))]) and ok
		ok = _check(_player.knife_max == int(base["knives"]) + int(cfg.get("knives", 0)),
			"%s: knife_max %d, expected %d" % [id, _player.knife_max, int(base["knives"]) + int(cfg.get("knives", 0))]) and ok

		var before := _player.hp
		_player.invuln = 0.0
		_player.state = Player.State.IDLE
		_player.take_hit({"damage": 20.0, "source_pos": _player.global_position - Vector2(40.0, 0.0)})
		Combat.cancel_hitstop()
		loss[id] = before - _player.hp
		var expected := 20.0 * float(cfg.get("damage_taken", 1.0))
		ok = _check(is_equal_approx(float(loss[id]), expected),
			"%s: took %.2f damage, expected %.2f" % [id, float(loss[id]), expected]) and ok
		print("  %-8s %-5s hp+%.0f speed%+.0f iframe+%.2f knives+%d hit=%.2f" % [
			id, "PASS" if ok else "FAIL", float(cfg.get("hp", 0.0)), float(cfg.get("speed", 0.0)),
			float(cfg.get("iframe", 0.0)), int(cfg.get("knives", 0)), float(loss[id])])
	_check(float(loss["aegis"]) < float(loss["none"]), "armour: 0.85 damage_taken did not reduce the hit")
	_check(Profile.select("armor", "none"), "reset armor selection saved")


# --- 4. Death and perfect dodge --------------------------------------------

func _test_death_and_dodge() -> void:
	print("\n--- 4. DEATH / PERFECT DODGE ---")
	await _spawn_player()
	_player._start_roll(1.0)
	await _frames(8)
	var before := _player.hp
	_player.take_hit({"damage": 10.0, "source_pos": _player.global_position - Vector2(40.0, 0.0)})
	Combat.cancel_hitstop()
	_check(is_equal_approx(_player.hp, before), "roll i-frames: damage got through (%.1f -> %.1f)" % [before, _player.hp])
	_check(Game.perfect_dodges == 1, "roll i-frames: Game.perfect_dodge() was not triggered")
	_check(not _died, "roll i-frames: the player died through an i-frame window")

	await _spawn_player()
	_player.hp = 5.0
	_player.take_hit({"damage": 40.0, "source_pos": _player.global_position - Vector2(40.0, 0.0)})
	Combat.cancel_hitstop()
	_check(_player.hp <= 0.0, "death: hp did not reach 0")
	_check(_died, "death: `died` signal was not emitted")
	_check(_player.state == Player.State.DEAD, "death: state is not DEAD")
	await _frames(10)
	print("  death: died=%s state=%d hp=%.0f" % [str(_died), _player.state, _player.hp])


# --- 5. Weapon visual pose --------------------------------------------------

## The blade is only posed from PlayerVisual._draw(), which skips the roll and
## the death pose. A cached pose keeps rendering, so the blade used to hang in
## mid-air next to the spinning square.
func _test_weapon_visual() -> void:
	print("
--- 5. WEAPON VISUAL POSE ---")
	_check(Profile.select("character", "square"), "pose character selection saved")
	_check(Profile.select("weapon", "rusty_sword"), "pose weapon selection saved")
	await _spawn_player()
	var vis: Node = _player.visual.weapon_visual
	if not _check(vis != null, "player has no weapon visual"):
		return
	_check(bool(vis._posed), "weapon visual was never posed while idle")
	_player._start_roll(1.0)
	await _frames(4)
	_check(not bool(vis._posed), "blade kept its pose through the roll (it hangs in mid-air)")
	await _frames(30)
	_player.hp = 1.0
	_player.take_hit({"damage": 10.0, "source_pos": _player.global_position - Vector2(40.0, 0.0)})
	Combat.cancel_hitstop()
	await _frames(4)
	_check(not bool(vis._posed), "blade kept its pose after death")
	print("  posed idle/roll/dead = checked")


func _finish() -> void:
	if _failures == 0:
		print("\nAUDIT A1 OK")
	else:
		print("\nAUDIT A1 FAILED (%d)" % _failures)
	await _frames(20)
	get_tree().quit(0 if _failures == 0 else 1)
