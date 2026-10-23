class_name Enemy
extends CharacterBody2D
## Data-driven enemy. Three behaviours share one state machine so tuning stays
## in data/enemies.json.

signal died(enemy: Enemy)

enum EState { IDLE, CHASE, WINDUP, ATTACK, RECOVER, HURT, DEAD }

const GRAVITY := 1750.0

var kind := "grunt"
var cfg: Dictionary = {}
var hp := 40.0
var max_hp := 40.0
var state: EState = EState.IDLE
var state_t := 0.0
var facing := -1
var flash := 0.0
var impact := 0.0
var attack_cd := 0.0
var hitbox: Hitbox
var visual: EnemyVisual
var fade := 1.0

var _dead := false
var _spawn_t := 0.0
var _was_on_floor := true
var _pending_attack := "cleave"
var _pattern := 0
var _slam_done := false


func configure(kind_id: String, config: Dictionary, hp_scale: float = 1.0) -> void:
	kind = kind_id
	cfg = config
	max_hp = float(cfg.get("hp", 40.0)) * hp_scale
	hp = max_hp


func _ready() -> void:
	collision_layer = Layers.ENEMY
	collision_mask = Layers.WORLD | Layers.PLAYER
	add_to_group("enemies")
	z_index = 1
	_build_nodes()
	state_t = 0.0
	_spawn_t = randf_range(0.1, 0.4)
	if bool(cfg.get("boss", false)):
		z_index = 2
		Game.boss = self
		Game.boss_defeated = false


func _build_nodes() -> void:
	var radius := float(cfg.get("body_radius", 12.0))
	var height := float(cfg.get("body_height", 42.0))
	var body_shape := CollisionShape2D.new()
	body_shape.name = "BodyShape"
	var capsule := CapsuleShape2D.new()
	capsule.radius = radius
	capsule.height = height
	body_shape.shape = capsule
	add_child(body_shape)

	hitbox = Hitbox.new()
	hitbox.name = "Hitbox"
	hitbox.collision_mask = Layers.PLAYER
	var hit_shape := CollisionShape2D.new()
	hit_shape.name = "Shape"
	hit_shape.position = Vector2(30.0, -8.0)
	var rect := RectangleShape2D.new()
	rect.size = Vector2(44.0, 36.0)
	hit_shape.shape = rect
	hitbox.add_child(hit_shape)
	add_child(hitbox)

	visual = EnemyVisual.new()
	visual.name = "Visual"
	add_child(visual)


func _physics_process(delta: float) -> void:
	if _dead:
		velocity.y = minf(velocity.y + GRAVITY * delta, 900.0)
		velocity.x = move_toward(velocity.x, 0.0, 700.0 * delta)
		move_and_slide()
		return

	state_t += delta
	flash = maxf(0.0, flash - delta)
	impact = maxf(0.0, impact - delta)
	attack_cd = maxf(0.0, attack_cd - delta)
	_spawn_t = maxf(0.0, _spawn_t - delta)

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y = minf(velocity.y + GRAVITY * delta, 900.0)

	var player := Game.player
	if player == null or Game.run_over or player.state == Player.State.DEAD:
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		move_and_slide()
		return

	# Landing dust so every body feels like it has weight.
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor and absf(velocity.y) > 120.0:
		Juice.land_dust(get_parent(), global_position + Vector2(0, 22), 0.45)
	_was_on_floor = on_floor

	match state:
		EState.HURT:
			_tick_hurt(delta)
		EState.WINDUP:
			_tick_windup()
		EState.ATTACK:
			_tick_attack(delta)
		EState.RECOVER:
			_tick_recover()
		_:
			_tick_chase(player, delta)

	move_and_slide()


func _tick_chase(player: Player, delta: float) -> void:
	if _spawn_t > 0.0:
		velocity.x = 0.0
		return
	var delta_pos := player.global_position - global_position
	var distance := delta_pos.length()
	facing = 1 if delta_pos.x > 0.0 else -1
	var speed := float(cfg.get("speed", 80.0))
	var attack_range := float(cfg.get("attack_range", 60.0))

	match kind:
		"warden":
			if attack_cd <= 0.0 and _spawn_t <= 0.0:
				if distance < 150.0:
					_pending_attack = "cleave"
				else:
					_pattern += 1
					_pending_attack = "charge" if _pattern % 2 == 1 else "slam"
				_enter_windup()
				return
			velocity.x = move_toward(velocity.x, facing * speed, 520.0 * delta)
		"archer":
			if attack_cd <= 0.0 and distance < attack_range and absf(delta_pos.y) < 180.0:
				_enter_windup()
				return
			if distance < 170.0:
				velocity.x = move_toward(velocity.x, -facing * speed, 900.0 * delta)
			elif distance > 360.0:
				velocity.x = move_toward(velocity.x, facing * speed, 900.0 * delta)
			else:
				velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)
		"charger":
			if attack_cd <= 0.0 and distance < attack_range and absf(delta_pos.y) < 120.0:
				_enter_windup()
				return
			velocity.x = move_toward(velocity.x, facing * speed, 700.0 * delta)
		_:
			if distance < attack_range and absf(delta_pos.y) < 56.0:
				_enter_windup()
				return
			velocity.x = move_toward(velocity.x, facing * speed, 900.0 * delta)


func _enter_windup() -> void:
	state = EState.WINDUP
	state_t = 0.0
	velocity.x = 0.0
	_slam_done = false
	Juice.telegraph(get_parent(), global_position + Vector2(0, -12))
	if kind == "charger":
		Sfx.play("swing", -18, 0.55)
	elif kind == "warden":
		Sfx.play("boss", -14, 0.9 if _pending_attack == "slam" else 1.0)
	else:
		Sfx.play("swing", -20, 1.35)


func _tick_windup() -> void:
	velocity.x = move_toward(velocity.x, 0.0, 1400.0 * get_physics_process_delta_time())
	if state_t >= float(cfg.get("windup", 0.4)):
		_begin_attack()


func _begin_attack() -> void:
	state = EState.ATTACK
	state_t = 0.0
	var damage := float(cfg.get("damage", 8.0))
	if kind == "archer":
		_shoot()
		Sfx.play("shoot", -8)
		return
	if kind == "warden":
		match _pending_attack:
			"cleave":
				_enable_hitbox(Vector2(96.0, 68.0), 50.0, -10.0, damage)
				velocity.x = facing * 180.0
				Sfx.play("swing", -10, 0.65)
			"charge":
				_enable_hitbox(Vector2(62.0, 52.0), 34.0, -8.0, damage + 2.0)
				velocity.x = facing * float(cfg.get("charge_speed", 520.0))
				Sfx.play("swing", -12, 0.55)
			"slam":
				velocity.x = 0.0
				Sfx.play("slam", -8)
		return

	var size := Vector2(48.0, 38.0)
	if kind == "charger":
		size = Vector2(58.0, 44.0)
	elif kind == "bulwark":
		size = Vector2(58.0, 42.0)
	_enable_hitbox(size, 30.0, -8.0, damage)
	velocity.x = facing * float(cfg.get("lunge", 140.0))
	Sfx.play("swing", -14, 0.8 if kind in ["charger", "bulwark"] else 1.1)


func _enable_hitbox(size: Vector2, offset_x: float, offset_y: float, damage: float) -> void:
	hitbox.shape_node.position = Vector2(facing * offset_x, offset_y)
	var rect := hitbox.shape_node.shape as RectangleShape2D
	rect.size = size
	hitbox.enable(damage, float(cfg.get("knockback", 220.0)), 0.0, self)


func _tick_attack(delta: float) -> void:
	if kind == "charger":
		velocity.x = facing * float(cfg.get("lunge", 450.0))
		if is_on_wall():
			hitbox.disable()
			state = EState.RECOVER
			state_t = 0.0
			Combat.shake(0.32)
			Sfx.play("land", -10, 0.7)
			return
	if kind == "warden":
		if _pending_attack == "charge":
			velocity.x = facing * float(cfg.get("charge_speed", 520.0))
			if is_on_wall():
				hitbox.disable()
				state = EState.RECOVER
				state_t = 0.0
				Combat.shake(0.45)
				Sfx.play("slam", -6)
				return
		elif _pending_attack == "slam":
			if not _slam_done and state_t >= 0.14:
				_slam_done = true
				_spawn_shockwaves()
			if state_t >= 0.55:
				hitbox.disable()
				state = EState.RECOVER
				state_t = 0.0
				velocity.x = 0.0
			return
	if state_t >= float(cfg.get("active", 0.12)):
		hitbox.disable()
		state = EState.RECOVER
		state_t = 0.0
		velocity.x *= 0.25


func _bow_offset() -> float:
	return float(cfg.get("body_radius", 10.0)) + 4.0


func _spawn_shockwaves() -> void:
	Combat.shake(0.5)
	Sfx.play("slam", -7, 0.85)
	Combat.dust(global_position + Vector2(0, 28), 16, Vector2(0, 1))
	for direction in [-1.0, 1.0]:
		var wave := Projectile.new()
		wave.position = global_position + Vector2(direction * 34.0, 0)
		wave.setup_wave(
			Vector2(direction, 0),
			float(cfg.get("shockwave_speed", 430.0)),
			float(cfg.get("shockwave_damage", 13.0)),
			Color(cfg.get("color", "#dfe4ea")),
			self
		)
		var root := Game.fx_root
		if is_instance_valid(root):
			root.add_child(wave)


func _tick_recover() -> void:
	velocity.x = move_toward(velocity.x, 0.0, 1000.0 * get_physics_process_delta_time())
	if state_t >= float(cfg.get("recovery", 0.45)):
		state = EState.CHASE
		state_t = 0.0
		attack_cd = float(cfg.get("cooldown", 0.4))


func _tick_hurt(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 1300.0 * delta)
	if state_t >= 0.18:
		state = EState.CHASE
		state_t = 0.0
		attack_cd = maxf(attack_cd, 0.15)


func _shoot() -> void:
	var player := Game.player
	if player == null:
		return
	var spawn := global_position + Vector2(facing * _bow_offset(), -2.0)
	var target := player.global_position + Vector2(0, -14)
	var velocity := MathArt.ballistic_velocity(spawn, target, float(cfg.get("projectile_speed", 320.0)), 700.0)
	var projectile := Projectile.new()
	projectile.position = spawn
	projectile.setup_ballistic(velocity, float(cfg.get("damage", 7.0)), Color(cfg.get("color", "#b8bec8")), self)
	var root := Game.fx_root
	if is_instance_valid(root):
		root.add_child(projectile)
	Combat.burst(spawn, MathArt.WHITE, 5, 90.0)
	Juice.hit_sparks(get_parent(), spawn, Vector2(float(facing), 0), 0.5)


func take_hit(info: Dictionary) -> void:
	if _dead:
		return
	var damage := float(info.get("damage", 1))
	var crit := bool(info.get("crit", false))
	var source_pos: Vector2 = info.get("source_pos", global_position)
	var dir := signf(global_position.x - source_pos.x)
	if dir == 0.0:
		dir = 1.0

	# Bulwark shield: front hits are chipped unless they are crits
	# (exposed or backstab). This is the positioning lesson.
	var to_source := signf(source_pos.x - global_position.x)
	if bool(cfg.get("shield", false)) and not crit and to_source == float(facing):
		hp -= 1.0
		flash = 0.06
		Combat.block_number(global_position + Vector2(0, -54))
		var shield_point := global_position + Vector2(float(facing) * 18.0, -10.0)
		Combat.spark(shield_point, Vector2(float(facing), 0.0), false, MathArt.WHITE)
		Combat.block_burst(shield_point, facing)
		Combat.impact(shield_point, Vector2(float(facing), 0.0), 0, MathArt.WHITE)
		Juice.block(get_parent(), shield_point, facing)
		Sfx.play("block", -8)
		Combat.shake(0.10)
		if hp <= 0.0:
			_die()
		return

	hp -= damage
	# Impact frame: 2 frames of a pure white silhouette, then a fading outline.
	impact = 0.034
	flash = 0.10
	if not bool(cfg.get("boss", false)):
		state = EState.HURT
		state_t = 0.0
		hitbox.disable()

	var scale := float(cfg.get("knockback_scale", 1.0))
	velocity = Vector2(dir * float(info.get("knockback", 180.0)) * scale, -20.0 if bool(cfg.get("boss", false)) else -90.0 * scale)

	var contact: Vector2 = info.get("point", global_position + Vector2(0, -18))
	var tier: int = clampi(int(info.get("tier", 0)) + (1 if crit else 0), 0, 3)
	Combat.impact(contact, Vector2(float(dir), 0.0), tier, MathArt.WHITE)
	if tier >= 2:
		Combat.screen_punch(float(tier) / 3.0)
	Combat.damage_number(global_position + Vector2(0, -50), int(damage), crit)
	Game.combo_hit()
	Sfx.play("crit" if crit else "hit", -7)

	if hp <= 0.0:
		_die()


func is_backstabbed_by(attacker: Node2D) -> bool:
	var dx := attacker.global_position.x - global_position.x
	if absf(dx) < 1.0:
		return false
	return signf(dx) != float(facing)


func is_exposed() -> bool:
	return state == EState.WINDUP or state == EState.ATTACK or state == EState.RECOVER


func _die() -> void:
	if _dead:
		return
	_dead = true
	state = EState.DEAD
	hitbox.disable()
	collision_layer = 0
	collision_mask = 0
	velocity = Vector2(randf_range(-60.0, 60.0), -160.0)
	var tint := Color(cfg.get("color", "#b8bec8"))
	var sides := 3
	match kind:
		"archer":
			sides = 8
		"charger":
			sides = 4
		"bulwark":
			sides = 6
		"warden":
			sides = 5
	var is_boss := bool(cfg.get("boss", false))
	# Kill feedback: the silhouette itself breaks into 12-24 shards, plus a
	# directional spark burst and a heavy screen punch.
	Combat.shatter(global_position + Vector2(0, -14), tint, sides,
		24 if is_boss else 12, 420.0 if is_boss else 320.0)
	Combat.impact(global_position + Vector2(0, -16), Vector2(0, -1), 2 if is_boss else 1, MathArt.WHITE)
	Juice.shatter(get_parent(), global_position + Vector2(0, -14), MathArt.WHITE, 24 if is_boss else 12)
	if is_boss:
		Combat.screen_punch(0.9)
	else:
		Combat.punch(0.35)
	if bool(cfg.get("boss", false)):
		Combat.ring(global_position + Vector2(0, -10), tint.lightened(0.3), 180.0, 5)
		Combat.shake(0.75)
		Sfx.play("slam", -4, 0.7)
	else:
		Combat.shake(0.22)
	Sfx.play("death", -14, 1.15)

	var pickup := CellPickup.new()
	pickup.value = int(cfg.get("cells", 1))
	pickup.position = global_position
	var root := get_parent()
	if root != null:
		# Death can happen inside a physics signal flush; defer the add so the
		# pickup's Area2D setup is legal.
		root.call_deferred("add_child", pickup)

	if Game.boss == self:
		Game.boss = null
		Game.boss_defeated = true
	Game.add_kill()
	died.emit(self)
	var tween := create_tween()
	tween.tween_property(visual, "modulate:a", 0.0, 0.35)
	tween.tween_callback(queue_free)
