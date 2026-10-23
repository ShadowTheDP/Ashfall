class_name Player
extends CharacterBody2D
## Movement and combat feel live here. Tuning values are exported so the
## prototype can be iterated in the inspector without touching logic.

signal died

enum State { IDLE, RUN, AIR, ROLL, ATTACK, HURT, DEAD }

@export_group("Movement")
@export var max_speed := 250.0
@export var ground_accel := 2400.0
@export var ground_friction := 3000.0
@export var air_accel := 1550.0
@export var air_drag := 520.0
@export var gravity := 1900.0
@export var max_fall_speed := 900.0
@export var jump_velocity := -640.0
@export var jump_cut := 0.45
@export var coyote_time := 0.10
@export var jump_buffer_time := 0.12

@export_group("Roll")
@export var roll_speed := 540.0
@export var roll_end_speed := 170.0
@export var roll_time := 0.30
@export var roll_iframe_start := 0.03
@export var roll_iframe_end := 0.24
@export var roll_cooldown := 0.10

@export_group("Combat")
@export var max_hp := 120.0
@export var invuln_time := 0.55
@export var hurt_time := 0.28
@export var hurt_knockback := 260.0

@export_group("Kunai")
@export var knife_max := 2
@export var knife_regen_time := 1.5
@export var knife_damage := 12.0
@export var knife_speed := 780.0

@export_group("Aegis")
@export var aegis_time := 0.45
@export var aegis_cooldown := 3.0

var state: State = State.IDLE
var facing := 1
var hp := 0.0
var invuln := 0.0
var flash := 0.0
var squash := 1.0

var coyote := 0.0
var jump_buffer := 0.0
var roll_t := 0.0
var roll_cd := 0.0
var attack_t := 0.0
var attack_total := 0.0
var attack_index := 0
var attack_queued := false
var hurt_t := 0.0

var crit_bonus := 0.0
var knife_charges := 2
var _knife_regen := 0.0
var aegis_t := 0.0
var aegis_cd := 0.0

var weapon: Dictionary = {}
var weapon_combo: Array = []
var attack_cfg: Dictionary = {}
var hitbox: Hitbox
var visual: PlayerVisual
var camera: PlayerCamera

var _trail_t := 0.0
var _dust_t := 0.0
var _was_on_floor := true


func _ready() -> void:
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD | Layers.ENEMY
	hp = max_hp
	weapon = Data.weapons.get("rusty_sword", {})
	weapon_combo = weapon.get("combo", [])
	knife_charges = knife_max
	_build_nodes()
	Game.player = self
	add_to_group("player")


func _build_nodes() -> void:
	var body_shape := CollisionShape2D.new()
	body_shape.name = "BodyShape"
	var capsule := CapsuleShape2D.new()
	capsule.radius = 13.0
	capsule.height = 46.0
	body_shape.shape = capsule
	add_child(body_shape)

	hitbox = Hitbox.new()
	hitbox.name = "Hitbox"
	hitbox.collision_mask = Layers.ENEMY
	var hit_shape := CollisionShape2D.new()
	hit_shape.name = "Shape"
	hit_shape.position = Vector2(38.0, -12.0)
	var rect := RectangleShape2D.new()
	rect.size = Vector2(68.0, 46.0)
	hit_shape.shape = rect
	hitbox.add_child(hit_shape)
	add_child(hitbox)

	visual = PlayerVisual.new()
	visual.name = "Visual"
	add_child(visual)

	camera = PlayerCamera.new()
	camera.name = "Camera"
	add_child(camera)
	camera.make_current()


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
		move_and_slide()
		return

	_tick_timers(delta)

	if Input.is_action_just_pressed("throw") and state != State.HURT:
		_throw_knife()
	if Input.is_action_just_pressed("aegis") and state != State.HURT:
		_cast_aegis()

	var dir := Input.get_axis("move_left", "move_right")
	if Input.is_action_just_pressed("jump"):
		jump_buffer = jump_buffer_time
	if is_on_floor():
		coyote = coyote_time
	else:
		coyote = maxf(0.0, coyote - delta)

	match state:
		State.HURT:
			_tick_hurt(delta)
		State.ROLL:
			_tick_roll(delta)
		State.ATTACK:
			_tick_attack(delta)
		_:
			_tick_free(dir, delta)

	_apply_gravity(delta)
	var fall_speed := velocity.y
	move_and_slide()
	_post_move(fall_speed, delta)


func _tick_timers(delta: float) -> void:
	invuln = maxf(0.0, invuln - delta)
	roll_cd = maxf(0.0, roll_cd - delta)
	jump_buffer = maxf(0.0, jump_buffer - delta)
	flash = maxf(0.0, flash - delta)
	squash = move_toward(squash, 1.0, delta * 4.0)
	aegis_t = maxf(0.0, aegis_t - delta)
	aegis_cd = maxf(0.0, aegis_cd - delta)
	if knife_charges < knife_max:
		_knife_regen += delta
		if _knife_regen >= knife_regen_time:
			_knife_regen = 0.0
			knife_charges += 1
			Sfx.play("ui", -20, 1.5)
	else:
		_knife_regen = 0.0


func _tick_free(dir: float, delta: float) -> void:
	var on_floor := is_on_floor()
	var rate := ground_accel if on_floor else air_accel
	if absf(dir) < 0.01:
		rate = ground_friction if on_floor else air_drag
	velocity.x = move_toward(velocity.x, dir * max_speed, rate * delta)
	if absf(dir) > 0.01:
		facing = 1 if dir > 0.0 else -1

	if jump_buffer > 0.0 and coyote > 0.0:
		velocity.y = jump_velocity
		jump_buffer = 0.0
		coyote = 0.0
		if on_floor:
			Combat.dust(global_position + Vector2(0, 22), 5, Vector2.ZERO)
		Sfx.play("jump", -11)
		set_state(State.AIR)

	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut

	if Input.is_action_just_pressed("roll") and on_floor and roll_cd <= 0.0:
		_start_roll(dir)
		return

	if Input.is_action_just_pressed("attack"):
		_start_attack(0)
		return

	if on_floor:
		set_state(State.RUN if absf(velocity.x) > 12.0 else State.IDLE)
		_dust_t -= delta
		if absf(velocity.x) > 200.0 and _dust_t <= 0.0:
			_dust_t = 0.11
			Combat.dust(global_position + Vector2(0, 22), 1, Vector2(signf(velocity.x), 0))
	else:
		set_state(State.AIR)


func _tick_roll(delta: float) -> void:
	roll_t += delta
	var k := clampf(roll_t / roll_time, 0.0, 1.0)
	velocity.x = facing * lerpf(roll_speed, roll_end_speed, ease(k, 2.0))
	_trail_t -= delta
	if _trail_t <= 0.0:
		_trail_t = 0.045
		Combat.afterimage(global_position + Vector2(0, 10), facing)

	if roll_t >= roll_time:
		roll_cd = roll_cooldown
		velocity.x *= 0.35
		set_state(State.AIR if not is_on_floor() else State.IDLE)
		return

	if roll_t > roll_time * 0.55 and Input.is_action_just_pressed("attack"):
		_start_attack(0)


func _tick_attack(delta: float) -> void:
	attack_t += delta
	var windup := float(attack_cfg.get("windup", 0.08))
	var active := float(attack_cfg.get("active", 0.07))
	var active_end := windup + active

	if attack_t >= windup and attack_t < active_end and not hitbox.active:
		_open_hitbox()
	if hitbox.active and attack_t >= active_end:
		hitbox.disable()

	if attack_t < windup:
		velocity.x = move_toward(velocity.x, facing * float(attack_cfg.get("lunge", 180.0)), 2600.0 * delta)
	elif is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, 1500.0 * delta)

	if Input.is_action_just_pressed("attack") and attack_index < weapon_combo.size() - 1:
		attack_queued = true

	var cancel_at := float(attack_cfg.get("cancel_at", 0.6))
	if Input.is_action_just_pressed("roll") and is_on_floor() and roll_cd <= 0.0 and attack_t >= attack_total * cancel_at:
		_start_roll(Input.get_axis("move_left", "move_right"))
		return

	if attack_t >= attack_total:
		hitbox.disable()
		if attack_queued and attack_index < weapon_combo.size() - 1:
			_start_attack(attack_index + 1)
		else:
			set_state(State.AIR if not is_on_floor() else State.IDLE)


func _tick_hurt(delta: float) -> void:
	hurt_t -= delta
	velocity.x = move_toward(velocity.x, 0.0, 1400.0 * delta)
	if hurt_t <= 0.0:
		set_state(State.AIR if not is_on_floor() else State.IDLE)


func _apply_gravity(delta: float) -> void:
	if state == State.ROLL and is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)


func _post_move(fall_speed: float, delta: float) -> void:
	if is_on_floor():
		if not _was_on_floor and fall_speed > 320.0:
			squash = 1.35
			Combat.dust(global_position + Vector2(0, 22), 8, Vector2(0, 1))
			Combat.shake(0.08)
			Sfx.play("land", -9)
	else:
		pass
	_was_on_floor = is_on_floor()


func _start_roll(dir: float) -> void:
	if absf(dir) > 0.01:
		facing = 1 if dir > 0.0 else -1
	hitbox.disable()
	roll_t = 0.0
	_trail_t = 0.0
	velocity.x = facing * roll_speed
	velocity.y = 0.0
	set_state(State.ROLL)
	Sfx.play("roll", -13, randf_range(0.95, 1.05))
	Combat.dust(global_position + Vector2(0, 22), 4, Vector2.ZERO)


func _start_attack(index: int) -> void:
	if weapon_combo.is_empty():
		return
	attack_index = clampi(index, 0, weapon_combo.size() - 1)
	attack_cfg = weapon_combo[attack_index]
	attack_total = float(attack_cfg.get("windup", 0.08)) + float(attack_cfg.get("active", 0.07)) + float(attack_cfg.get("recovery", 0.2))
	attack_t = 0.0
	attack_queued = false
	hitbox.disable()
	var dir := Input.get_axis("move_left", "move_right")
	if absf(dir) > 0.1:
		facing = 1 if dir > 0.0 else -1
	velocity.x = facing * float(attack_cfg.get("lunge", 180.0)) * 0.55
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	set_state(State.ATTACK)
	Sfx.play("swing", -12, randf_range(0.94, 1.06))


func _open_hitbox() -> void:
	var size: Array = attack_cfg.get("size", [68.0, 46.0])
	var offset: Array = attack_cfg.get("offset", [38.0, -12.0])
	hitbox.shape_node.position = Vector2(facing * float(offset[0]), float(offset[1]))
	var rect := hitbox.shape_node.shape as RectangleShape2D
	rect.size = Vector2(float(size[0]), float(size[1]))
	hitbox.enable(
		float(attack_cfg.get("damage", 10.0)) * Game.total_damage_mult(),
		float(attack_cfg.get("knockback", 180.0)),
		float(attack_cfg.get("hitstop", 0.05)),
		self,
		crit_multiplier()
	)
	Combat.slash(
		global_position + Vector2(facing * float(offset[0]) * 0.55, 0),
		facing,
		attack_index,
		Color("#cfe8ff")
	)
	if attack_index == weapon_combo.size() - 1 and not weapon_combo.is_empty():
		# The finisher releases the blade's sine function as a travelling wave.
		var wave := FunctionWave.new()
		wave.position = global_position + Vector2(facing * 26.0, -10.0)
		wave.setup(facing, 8.0 * Game.total_damage_mult(), Color("#8fe3ff"), self, crit_multiplier())
		var root := Game.fx_root
		if is_instance_valid(root):
			root.add_child(wave)


func take_hit(info: Dictionary) -> void:
	if state == State.DEAD:
		return
	if state == State.ROLL and roll_t >= roll_iframe_start and roll_t <= roll_iframe_end:
		Game.perfect_dodge()
		return
	if invuln > 0.0:
		return
	if aegis_t > 0.0:
		_aegis_block()
		return
	var damage := float(info.get("damage", 1))
	hp = maxf(0.0, hp - damage)
	invuln = invuln_time
	flash = 0.14
	squash = 1.22
	hurt_t = hurt_time
	hitbox.disable()

	var source_pos: Vector2 = info.get("source_pos", global_position)
	var dir := signf(global_position.x - source_pos.x)
	if dir == 0.0:
		dir = -facing
	velocity = Vector2(dir * hurt_knockback, -130.0)
	set_state(State.HURT)

	Combat.hitstop(0.10)
	Combat.shake(0.6)
	Combat.damage_number(global_position + Vector2(0, -46), int(damage), false)
	Combat.spark(global_position + Vector2(0, -16), Vector2(dir, 0), false, Color("#ff6b6b"))
	Sfx.play("hurt", -6)
	Game.hurt_flash = 0.32
	Game.combo_break()

	if hp <= 0.0:
		_die()


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)
	Combat.burst(global_position + Vector2(0, -10), Color("#7fd6a0"), 10, 130.0)


func is_invulnerable() -> bool:
	if invuln > 0.0:
		return true
	return state == State.ROLL and roll_t >= roll_iframe_start and roll_t <= roll_iframe_end


func is_crit_against(target: Node) -> bool:
	if target.has_method("is_exposed") and target.is_exposed():
		return true
	if target.has_method("is_backstabbed_by"):
		return target.is_backstabbed_by(self)
	return false


func crit_multiplier() -> float:
	return float(weapon.get("crit_multiplier", 1.5)) + crit_bonus


func add_knife_max() -> void:
	knife_max += 1
	knife_charges = knife_max
	_knife_regen = 0.0


func refund_knife() -> void:
	if knife_charges < knife_max:
		knife_charges += 1


func _nearest_enemy(radius: float) -> Node2D:
	var best: Node2D = null
	var best_distance := radius
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy._dead:
			continue
		var distance: float = global_position.distance_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


func _throw_knife() -> void:
	if knife_charges <= 0:
		Sfx.play("ui", -20, 1.4)
		return
	knife_charges -= 1
	var spawn := global_position + Vector2(float(facing) * 8.0, -18.0)
	var target := _nearest_enemy(520.0)
	var aim_point := spawn + Vector2(float(facing) * 340.0, -70.0)
	if target != null:
		aim_point = target.global_position + Vector2(0, -18)
	# v0 is solved from the parabola through the target, not aimed directly.
	var velocity := MathArt.ballistic_velocity(spawn, aim_point, knife_speed, Projectile.KUNAI_GRAVITY)
	var projectile := Projectile.new()
	projectile.position = spawn
	projectile.setup_player(
		velocity,
		knife_damage * Game.total_damage_mult(),
		Color("#bfe9ff"),
		self,
		crit_multiplier()
	)
	var root: Node = Game.fx_root
	if is_instance_valid(root):
		root.add_child(projectile)
	Combat.parabola_preview(spawn, velocity, Projectile.KUNAI_GRAVITY)
	Combat.burst(spawn, Color("#8fe3ff"), 4, 90.0)
	Sfx.play("throw", -9, randf_range(0.95, 1.05))


func _cast_aegis() -> void:
	if aegis_cd > 0.0 or state == State.DEAD:
		return
	aegis_t = aegis_time
	aegis_cd = aegis_time + aegis_cooldown
	Combat.ring(global_position + Vector2(0, -8), Color("#8fe3ff"), 48.0)
	Combat.burst(global_position + Vector2(0, -10), Color("#8fe3ff"), 10, 150.0)
	Sfx.play("dodge", -10, 0.8)


func _aegis_block() -> void:
	aegis_t = 0.0
	Combat.block_number(global_position + Vector2(0, -50))
	Combat.spark(global_position + Vector2(0, -12), Vector2.UP, false, Color("#8fe3ff"))
	Combat.ring(global_position + Vector2(0, -8), Color("#8fe3ff"), 58.0)
	Combat.shake(0.22)
	Sfx.play("block", -6, 1.1)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy._dead:
			continue
		if global_position.distance_to(enemy.global_position) <= 112.0:
			enemy.take_hit({
				"damage": Damage.compute(10.0 * Game.total_damage_mult(), 0, false, 1.0),
				"crit": false,
				"knockback": 260.0,
				"hitstop": 0.03,
				"source_pos": global_position,
				"point": enemy.global_position,
			})


func set_state(next: State) -> void:
	if state == next:
		return
	state = next


func _die() -> void:
	set_state(State.DEAD)
	hitbox.disable()
	velocity = Vector2(-facing * 130.0, -280.0)
	Combat.burst(global_position + Vector2(0, -18), Color("#8fe3ff"), 20, 260.0)
	Combat.shake(0.85)
	Sfx.play("death", -5)
	Game.end_run(false)
	died.emit()
