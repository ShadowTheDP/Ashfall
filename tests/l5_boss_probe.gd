extends Node2D
## L5 FIXTURES: real Player/Hitbox/Projectile damage with controlled placement.
## These fixtures do not prove full-route play, balance, human feel or rendering.

var _checks := 0
var _fails := 0
var _arena: Node2D
var _boss: RouteBoss
var _player: Player


func _ready() -> void:
	if not Profile.require_test_profile():
		get_tree().quit(1)
		return
	Game.reset_run()
	Game.in_hub = false
	Game.run_phase = "arena"
	Game.build = RunBuild.new()
	Game.build.start("rusty_sword", ["rusty_sword"])
	Game.fx_root = self
	for kind_id in RouteBoss.KINDS:
		await _fixture(kind_id, 260.0)
		await _incoming_hit()
		await _patterns()
		await _floor_invariance()
		if kind_id in ["bridge_sentinel", "clock_warden"]:
			await _commitment()
		var attacks: Array
		match kind_id:
			"bridge_sentinel": attacks = ["cleave", "charge", "floor_wave"]
			"clock_warden": attacks = ["leap", "lanes"]
			_: attacks = ["columns", "sweep", "guard"]
		for attack: String in attacks:
			await _attack_damage(attack)
		if kind_id == "clock_warden":
			await _upper_lane()
		if kind_id == "silent_regent":
			await _guard_sides()
		await _hazard_limits()
		await _cleanup()
		_arena.queue_free()
		await _frames(2)
	Game.player = null
	Game.boss = null
	Game.fx_root = null
	Combat.cancel_hitstop()
	print("L5 BOSS FIXTURES: %d checks, %d failures; NOT full-play acceptance" % [_checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


## Explicit fixture values, not shipped content or a substitute for balance approval.
func _config() -> Dictionary:
	return {"hp": 500.0, "body_radius": 22.0, "body_height": 60.0, "speed": 70.0,
		"damage": 16.0, "windup": 0.45, "active": 0.28, "recovery": 0.55,
		"cooldown": 0.7, "attack_range": 600.0, "knockback": 220.0, "cells": 1,
		"charge_speed": 480.0, "shockwave_speed": 320.0, "shockwave_damage": 12.0,
		"wave_life": 1.25, "leap_time": 0.65, "leap_speed": 420.0,
		"lane_speed": 280.0, "lane_damage": 10.0, "lane_interval": 0.4,
		"lane_life": 1.6, "lane_lower_height": 16.0, "lane_upper_height": 64.0,
		"column_width": 36.0, "column_height": 110.0, "column_spacing": 80.0,
		"column_delay": 0.5, "column_active": 0.3, "column_damage": 14.0}


func _fixture(kind_id: String, top: float) -> void:
	Combat.cancel_hitstop()
	_arena = Node2D.new()
	add_child(_arena)
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = Layers.WORLD
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(2400.0, 40.0)
	shape.shape = rect
	shape.position = Vector2(0.0, top + 20.0)
	floor_body.add_child(shape)
	_arena.add_child(floor_body)
	_player = Player.new()
	_player.position = Vector2(160.0, top - 23.0)
	_arena.add_child(_player)
	_boss = RouteBoss.new()
	_boss.configure(kind_id, _config())
	_boss.position = Vector2(0.0, top - 31.0)
	_arena.add_child(_boss)
	_boss._spawn_t = 999.0
	await _frames(10)
	_check(_boss.is_on_floor(), kind_id + " fixture grounded")
	_player.set_physics_process(false)
	_boss.set_physics_process(false)


func _incoming_hit() -> void:
	# The player's actual Hitbox supplies Damage.compute and Enemy.take_hit.
	_player.position = _boss.position + Vector2(-42.0, 7.0)
	_player.facing = 1
	var before := _boss.hp
	_player.hitbox.shape_node.position = Vector2(42.0, -7.0)
	(_player.hitbox.shape_node.shape as RectangleShape2D).size = Vector2(44.0, 60.0)
	_player.hitbox.attr = 0
	_player.hitbox.enable(11.0, 180.0, 0.0, _player, 1.0, 0)
	await _frames(5)
	_player.hitbox.disable()
	_check(is_equal_approx(before - _boss.hp, 11.0), _boss.kind + " real player hitbox damages boss")
	_check(_boss.state != Enemy.EState.HURT, "boss damage cannot enter stun-lock state")
	Combat.cancel_hitstop()


func _patterns() -> void:
	var phase_one: Array[String] = []
	var phase_two: Array[String] = []
	_player.position = Vector2(160.0, 237.0)
	for phase_id in [1, 2]:
		_boss.phase = phase_id
		_boss._pattern = 0
		for index in 6:
			_boss.state = Enemy.EState.CHASE
			_boss.attack_cd = 0.0
			_boss._spawn_t = 0.0
			_boss._tick_chase(_player, 1.0 / 120.0)
			if phase_id == 1:
				phase_one.append(_boss._pending_attack)
			else:
				phase_two.append(_boss._pending_attack)
	_check(phase_one != phase_two, _boss.kind + " second phase changes attack pattern")
	_boss.phase = 1
	_boss.hp = _boss.max_hp * 0.5
	_boss._physics_process(0.0)
	_check(_boss.phase == 1, "half HP is still first phase")
	_boss.hp -= 1.0
	_boss._physics_process(0.0)
	_check(_boss.phase == 2, "strictly below half HP enters second phase")
	_boss.phase = 1
	_boss.hp = _boss.max_hp


func _floor_invariance() -> void:
	var expected: Array[Rect2] = []
	var attack := "floor_wave" if _boss.kind == "bridge_sentinel" else ("lanes" if _boss.kind == "clock_warden" else "columns")
	for shift in [0.0, -440.0, 310.0]:
		_arena.position.y = shift
		await _frames(2)
		_boss._pending_attack = attack
		_boss._enter_windup()
		var relative: Array[Rect2] = []
		for zone in _boss.zones:
			relative.append(Rect2(zone.position - Vector2(0.0, shift), zone.size))
		if shift == 0.0:
			expected = relative
		else:
			_check(relative == expected, _boss.kind + " floor-relative zones translate at y=" + str(shift))
		await _frames(2)
	_arena.position.y = 0.0
	await _frames(2)


func _reset_attack() -> void:
	_boss.set_physics_process(false)
	_boss._recover()
	for hazard in _boss._hazards:
		_boss._disarm(hazard)
	_boss._hazards.clear()
	_boss.position = Vector2(0.0, 230.0)
	_boss.velocity = Vector2.ZERO
	_boss.phase = 1
	_boss.facing = 1
	_player.hp = _player.max_hp
	_player.invuln = 0.0
	_player.roll_iframe_t = -1.0
	_player.guard_t = 0.0
	_player.aegis_t = 0.0
	_player.state = Player.State.IDLE
	Combat.cancel_hitstop()


func _commitment() -> void:
	_reset_attack()
	_player.position = Vector2(160.0, 237.0)
	_boss._pending_attack = "charge" if _boss.kind == "bridge_sentinel" else "leap"
	_boss._enter_windup()
	var marked := _boss.zones.duplicate()
	var target := _boss.leap_target
	var flight_velocity := _boss._leap_velocity
	_player.position.x = -180.0
	_boss._begin_attack()
	_check(_boss.facing == 1 and _boss.zones == marked, "crossing behind cannot turn charge/leap or move its telegraph")
	if _boss.kind == "clock_warden":
		_check(_boss.leap_target == target and _boss.velocity == flight_velocity, "leap does not track a moving player after commitment")
	else:
		_check(_boss.velocity.x == float(_boss.cfg["charge_speed"]), "charge keeps committed direction and configured speed")
	_reset_attack()
	await _frames(2)


func _attack_damage(attack: String) -> void:
	_reset_attack()
	var target_x := 100.0
	if attack in ["cleave", "guard"]:
		target_x = 42.0
	elif attack == "sweep":
		target_x = -42.0
	_player.position = Vector2(target_x, 237.0)
	_boss._pending_attack = attack
	_boss._enter_windup()
	var before := _player.hp
	await _frames(3)
	_check(_player.hp == before, attack + " cannot damage during windup")
	var committed := _boss.velocity
	_boss.take_hit({"damage": 1.0, "knockback": 900.0, "source_pos": _player.global_position})
	_check(_boss.state == Enemy.EState.WINDUP and _boss.velocity == committed, attack + " hit does not cancel commitment")
	Combat.cancel_hitstop()
	_boss.set_physics_process(true)
	var attack_hit_checked := false
	for frame in 480:
		await get_tree().physics_frame
		if _boss.state == Enemy.EState.ATTACK and not attack_hit_checked:
			var attack_velocity := _boss.velocity
			for hit in 3:
				_boss.take_hit({"damage": 1.0, "knockback": 900.0, "source_pos": _player.global_position})
			_check(_boss.state == Enemy.EState.ATTACK and _boss.velocity == attack_velocity,
				attack + " repeated hits cannot stun-lock or deflect active attack")
			attack_hit_checked = true
			Combat.cancel_hitstop()
		if _player.hp < before:
			break
		if _boss.state == Enemy.EState.CHASE:
			break
	_check(attack_hit_checked, attack + " reached active state")
	_boss.set_physics_process(false)
	var damage_key := "damage"
	if attack == "floor_wave": damage_key = "shockwave_damage"
	if attack == "lanes": damage_key = "lane_damage"
	if attack == "columns": damage_key = "column_damage"
	_check(is_equal_approx(before - _player.hp, float(_boss.cfg[damage_key]) * _player.armor_taken),
		_boss.kind + " " + attack + " real collision damage actual=%s expected=%s" % [before - _player.hp, float(_boss.cfg[damage_key]) * _player.armor_taken])
	if attack == "charge":
		_check(_boss.facing == 1, "charge does not retarget when player is behind")
	if attack == "leap":
		_check(absf(_boss.global_position.x - _boss.leap_target.x) < 22.0, "committed leap reaches marked landing")
	Combat.cancel_hitstop()


func _upper_lane() -> void:
	_reset_attack()
	_player.position = Vector2(130.0, 196.0)
	_boss._pending_attack = "lanes"
	_boss._enter_windup()
	_boss._begin_attack()
	_check(_boss._hazards.size() == 1 and is_equal_approx(_boss._hazards[0].global_position.y, 244.0), "first lane is floor minus lower height")
	# Place player at the upper lane; the lower shot must pass underneath.
	var before := _player.hp
	_boss.set_physics_process(true)
	for frame in 240:
		await get_tree().physics_frame
		if _player.hp < before: break
	_boss.set_physics_process(false)
	_check(is_equal_approx(before - _player.hp, float(_boss.cfg["lane_damage"])), "alternating upper projectile lane hits airborne player")
	_reset_attack()
	_boss.phase = 2
	_boss._pending_attack = "lanes"
	_boss._enter_windup()
	_check(_boss.zones.size() == 4, "phase two advertises four alternating lanes")
	_boss.phase = 1
	_check(_boss._lane_count() == 4, "current volley keeps committed phase geometry")


func _guard_sides() -> void:
	_reset_attack()
	_boss._pending_attack = "guard"
	_boss._enter_windup()
	var before := _boss.hp
	_player.position = _boss.position + Vector2(42.0, 7.0)
	_player.facing = -1
	_player.hitbox.shape_node.position = Vector2(-42.0, -7.0)
	_player.hitbox.enable(10.0, 180.0, 0.0, _player, 1.0, 0)
	await _frames(5)
	_player.hitbox.disable()
	_check(_boss.hp == before - 1.0, "Regent guard chips a real front player hit without exposure crit")
	before = _boss.hp
	_player.position = _boss.position + Vector2(-42.0, 7.0)
	_player.facing = 1
	_player.hitbox.shape_node.position = Vector2(42.0, -7.0)
	_player.hitbox.enable(10.0, 180.0, 0.0, _player, 1.0, 0)
	await _frames(5)
	_player.hitbox.disable()
	_check(_boss.hp == before - 10.0, "Regent guard leaves a real rear player hit punishable")
	_boss._recover()
	before = _boss.hp
	_boss.take_hit({"damage": 10.0, "source_pos": _boss.global_position + Vector2(50.0, 0.0)})
	_check(_boss.hp == before - 10.0, "Regent recovery is not armoured")
	Combat.cancel_hitstop()


func _hazard_limits() -> void:
	_reset_attack()
	if _boss.kind == "bridge_sentinel":
		_boss.cfg["wave_life"] = 999.0
	elif _boss.kind == "clock_warden":
		_boss.cfg["lane_life"] = 999.0
	else:
		_boss.cfg["column_delay"] = 999.0
		_boss.cfg["column_active"] = 999.0
	_boss._pending_attack = "floor_wave" if _boss.kind == "bridge_sentinel" else ("lanes" if _boss.kind == "clock_warden" else "columns")
	_boss._enter_windup()
	for index in 14:
		_boss._begin_attack()
	_check(_boss._hazards.size() == RouteBoss.MAX_HAZARDS, "live hazard references are capped")
	for hazard in _boss._hazards:
		if hazard is Projectile:
			_check(hazard._life <= RouteBoss.MAX_HAZARD_TTL, "projectile TTL bounded")
			hazard._physics_process(hazard._life + 0.01)
		else:
			_check(hazard.delay + hazard.duration <= RouteBoss.MAX_HAZARD_TTL, "column TTL bounded")
			hazard._physics_process(hazard.delay + hazard.duration + 0.01)
	await _frames(2)
	for hazard in _boss._hazards:
		_check(not is_instance_valid(hazard), "TTL expiration frees owned hazard")
	_boss._hazards.clear()
	for key in ["wave_life", "lane_life", "column_delay", "column_active"]:
		_boss.cfg[key] = _config()[key]


func _cleanup() -> void:
	_reset_attack()
	_boss._pending_attack = "floor_wave" if _boss.kind == "bridge_sentinel" else ("lanes" if _boss.kind == "clock_warden" else "columns")
	_boss._enter_windup()
	_boss._begin_attack()
	var hazards := _boss._hazards.duplicate()
	_check(not hazards.is_empty(), "cleanup fixture has real owned hazards")
	for hazard in hazards:
		_check(hazard.get_parent() == _boss and hazard.top_level, "hazard owned by boss in world coordinates")
	# A mixed list of live and already-expired hazards occurs in ordinary long fights.
	hazards[0].queue_free()
	await _frames(2)
	_check(not is_instance_valid(hazards[0]), "expired hazard retained until owner cleanup")
	_boss.take_hit({"damage": _boss.hp + 1.0, "source_pos": _player.global_position})
	var after_death := _player.hp
	_check(_boss._dead and _boss._hazards.is_empty(), "lethal real damage clears boss hazards immediately")
	await _frames(5)
	for hazard in hazards:
		_check(not is_instance_valid(hazard), "owner death frees hazard")
	_check(_player.hp == after_death, "dead owner cannot deal lingering hazard damage")
	# Scene removal, separate from death, must also destroy hazards.
	var replacement := RouteBoss.new()
	replacement.configure(_boss.kind, _config())
	replacement.position = Vector2(0.0, 230.0)
	_arena.add_child(replacement)
	replacement.set_physics_process(false)
	replacement._pending_attack = _boss._pending_attack
	replacement._enter_windup()
	replacement._begin_attack()
	var scene_hazards := replacement._hazards.duplicate()
	replacement.queue_free()
	await _frames(3)
	for hazard in scene_hazards:
		_check(not is_instance_valid(hazard), "scene owner removal frees hazard")


func _frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("L5 FIXTURE FAIL: " + message)
