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
var attack_cd := 0.0
var hitbox: Hitbox
var visual: EnemyVisual
var fade := 1.0

var _dead := false
var _spawn_t := 0.0


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
	if kind == "charger":
		Sfx.play("swing", -18, 0.55)
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

	var size := Vector2(48.0, 38.0)
	if kind == "charger":
		size = Vector2(58.0, 44.0)
	hitbox.shape_node.position = Vector2(facing * 30.0, -8.0)
	var rect := hitbox.shape_node.shape as RectangleShape2D
	rect.size = size
	hitbox.enable(damage, float(cfg.get("knockback", 220.0)), 0.0, self)
	velocity.x = facing * float(cfg.get("lunge", 140.0))
	Sfx.play("swing", -14, 0.8 if kind == "charger" else 1.1)


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
	if state_t >= float(cfg.get("active", 0.12)):
		hitbox.disable()
		state = EState.RECOVER
		state_t = 0.0
		velocity.x *= 0.25


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
	var spawn := global_position + Vector2(facing * 12.0, -18.0)
	var aim := (player.global_position + Vector2(0, -18) - spawn).normalized()
	var projectile := Projectile.new()
	projectile.position = spawn
	projectile.setup(aim, float(cfg.get("projectile_speed", 320.0)), float(cfg.get("damage", 7.0)), Color(cfg.get("color", "#b76bd6")))
	var root := Game.fx_root
	if is_instance_valid(root):
		root.add_child(projectile)
	Combat.burst(spawn, Color(cfg.get("color", "#b76bd6")), 5, 90.0)


func take_hit(info: Dictionary) -> void:
	if _dead:
		return
	var damage := float(info.get("damage", 1))
	hp -= damage
	flash = 0.10
	state = EState.HURT
	state_t = 0.0
	hitbox.disable()

	var source_pos: Vector2 = info.get("source_pos", global_position)
	var dir := signf(global_position.x - source_pos.x)
	if dir == 0.0:
		dir = 1.0
	velocity = Vector2(dir * float(info.get("knockback", 180.0)), -90.0)

	Combat.hitstop(float(info.get("hitstop", 0.05)))
	Combat.shake(0.34 if info.get("crit", false) else 0.18)
	Combat.spark(global_position + Vector2(0, -18), Vector2(dir, 0), bool(info.get("crit", false)), Color(cfg.get("color", "#b23a48")))
	Combat.damage_number(global_position + Vector2(0, -50), int(damage), bool(info.get("crit", false)))
	Game.combo_hit()
	Sfx.play("crit" if info.get("crit", false) else "hit", -7)

	if hp <= 0.0:
		_die()


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
	Combat.burst(global_position + Vector2(0, -18), Color(cfg.get("color", "#b23a48")), 18, 280.0)
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

	Game.add_kill()
	died.emit(self)
	var tween := create_tween()
	tween.tween_property(visual, "modulate:a", 0.0, 0.35)
	tween.tween_callback(queue_free)
