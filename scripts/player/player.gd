class_name Player
extends CharacterBody2D
## Movement and combat feel. Everything is tuned for motion first: asymmetric
## gravity, apex hang, a square that tumbles one face per jump, and generous
## input forgiveness. No colour is used for feedback anywhere.

signal died
signal landed(strength: float)
signal took_off

enum State { IDLE, RUN, AIR, ROLL, ATTACK, HURT, DEAD }

@export_group("Movement")
@export var max_speed := 300.0
@export var ground_accel := 3200.0
@export var ground_friction := 3600.0
@export var air_accel := 2100.0
@export var air_drag := 620.0
@export var gravity_rise := 1800.0
@export var gravity_fall := 2500.0
@export var max_fall_speed := 1000.0
@export var jump_velocity := -630.0
@export var jump_cut := 0.48
@export var coyote_time := 0.10
@export var jump_buffer_time := 0.12
@export var apex_threshold := 80.0
@export var apex_gravity_scale := 0.45
@export var apex_max_time := 0.07

@export_group("Roll")
@export var roll_speed := 640.0
@export var roll_end_speed := 200.0
@export var roll_time := 0.30
@export var roll_iframe_start := 0.03
@export var roll_iframe_end := 0.24
@export var roll_cooldown := 0.08

@export_group("Combat")
@export var max_hp := 120.0
@export var invuln_time := 0.55
@export var hurt_time := 0.26
@export var hurt_knockback := 300.0

@export_group("Kunai")
@export var knife_max := 2
@export var knife_regen_time := 1.5
@export var knife_damage := 12.0
@export var knife_speed := 820.0

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

# Tumble state: the square turns 90 degrees per jump and lands on a new face.
var face := 0
var tumble := 0.0
var tumble_from := 0.0
var tumble_to := 0.0
var tumble_settle := 0.0
var tumbling := false
var airborne_t := 0.0
var apex_t := 0.0

var crit_bonus := 0.0
var character_id := "square"
var passive_id := "none"
var armor_hp := 0.0
var armor_taken := 1.0
var permanent_damage_mult := 1.0
var aegis_cooldown_scale := 1.0
var perfect_dodge_scale := 1.0
var echo_every := 0
var _swing_count := 0
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
	_apply_loadout()
	weapon_combo = weapon.get("combo", [])
	knife_charges = knife_max
	_build_nodes()
	Game.player = self
	add_to_group("player")


## Reads the persistent loadout (character, armour, weapon) and permanent
## upgrades. Everything the hub sells funnels through here, so gameplay never
## has to know about Profile directly.
func _apply_loadout() -> void:
	var character: Dictionary = Data.characters.get(Profile.selected_character, {})
	if character.is_empty():
		character = Data.characters.get("square", {})

	max_hp = float(character.get("hp", max_hp))
	max_speed = float(character.get("speed", max_speed))
	jump_velocity = float(character.get("jump", jump_velocity))
	knife_max = int(character.get("knives", knife_max))
	character_id = Profile.selected_character
	passive_id = str(character.get("passive", "none"))

	var armor: Dictionary = Data.armor.get(Profile.selected_armor, {})
	armor_hp = float(armor.get("hp", 0.0))
	armor_taken = float(armor.get("damage_taken", 1.0))
	max_hp += armor_hp
	max_speed += float(armor.get("speed", 0.0))
	knife_max += int(armor.get("knives", 0))
	roll_iframe_end += float(armor.get("iframe", 0.0))

	# Permanent progression.
	max_hp += Profile.bonus("hp")
	max_speed += Profile.bonus("speed")
	knife_max += int(Profile.bonus("knives"))
	roll_iframe_end += Profile.bonus("iframe")
	crit_bonus += Profile.bonus("crit")
	permanent_damage_mult = 1.0 + Profile.bonus("damage")

	_apply_passive()

	weapon = Data.weapons.get(Profile.selected_weapon, {})
	if weapon.is_empty():
		weapon = Data.weapons.get("rusty_sword", {})


func _apply_passive() -> void:
	match passive_id:
		"glass":
			roll_iframe_end += 0.08
		"hunter":
			crit_bonus += 0.35
		"bulwark":
			armor_taken *= 0.80
			aegis_cooldown_scale = 0.65
		"dancer":
			perfect_dodge_scale = 2.0
		"echo":
			echo_every = 3
		_:
			pass


func _build_nodes() -> void:
	var body_shape := CollisionShape2D.new()
	body_shape.name = "BodyShape"
	var capsule := CapsuleShape2D.new()
	capsule.radius = 14.0
	capsule.height = 46.0
	body_shape.shape = capsule
	add_child(body_shape)

	hitbox = Hitbox.new()
	hitbox.name = "Hitbox"
	hitbox.collision_mask = Layers.ENEMY
	var hit_shape := CollisionShape2D.new()
	hit_shape.name = "Shape"
	hit_shape.position = Vector2(42.0, -12.0)
	var rect := RectangleShape2D.new()
	rect.size = Vector2(76.0, 50.0)
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
		velocity.y = minf(velocity.y + gravity_fall * delta, max_fall_speed)
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
	squash = move_toward(squash, 1.0, delta * 5.0)
	aegis_t = maxf(0.0, aegis_t - delta)
	aegis_cd = maxf(0.0, aegis_cd - delta)
	if not is_on_floor():
		airborne_t += delta
		if tumbling:
			# The tumble completes in ~0.42 s, a little faster than the airtime,
			# so the square is already square again before it lands.
			tumble = minf(1.0, tumble + delta / 0.42)
	elif tumbling:
		# Short hop: finish the remaining quarter-turn in ~70 ms instead of
		# snapping, so the landing still reads as a face change.
		tumble_settle += delta
		tumble = minf(1.0, tumble + delta / 0.07)
		if tumble >= 1.0:
			tumbling = false
	if knife_charges < knife_max:
		_knife_regen += delta
		if _knife_regen >= knife_regen_time:
			_knife_regen = 0.0
			knife_charges += 1
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
		_jump(on_floor)

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
		if absf(velocity.x) > 220.0 and _dust_t <= 0.0:
			_dust_t = 0.09
			Juice.dust(get_parent(), global_position + Vector2(0, 22), signf(velocity.x), 0.6)
	else:
		set_state(State.AIR)


func _jump(on_floor: bool) -> void:
	velocity.y = jump_velocity
	jump_buffer = 0.0
	coyote = 0.0
	apex_t = 0.0
	airborne_t = 0.0
	# One jump = one face turn.
	face = (face + 1) % 4
	tumble_from = tumble_to
	tumble_to = tumble_from + float(facing) * (PI * 0.5)
	tumble = 0.0
	tumble_settle = 0.0
	tumbling = true
	squash = 0.86
	if on_floor:
		Juice.jump_burst(get_parent(), global_position + Vector2(0, 22))
	Sfx.play("jump", -11)
	took_off.emit()
	set_state(State.AIR)


func _tick_roll(delta: float) -> void:
	roll_t += delta
	var k := clampf(roll_t / roll_time, 0.0, 1.0)
	velocity.x = facing * lerpf(roll_speed, roll_end_speed, ease(k, 2.0))
	_trail_t -= delta
	if _trail_t <= 0.0:
		_trail_t = 0.03
		Combat.afterimage(global_position + Vector2(0, 8), facing)

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
		velocity.x = move_toward(velocity.x, facing * float(attack_cfg.get("lunge", 180.0)), 3000.0 * delta)
	elif is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, 1600.0 * delta)

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
	velocity.x = move_toward(velocity.x, 0.0, 1500.0 * delta)
	if hurt_t <= 0.0:
		set_state(State.AIR if not is_on_floor() else State.IDLE)


func _apply_gravity(delta: float) -> void:
	if state == State.ROLL and is_on_floor():
		velocity.y = 0.0
		return
	var g := gravity_rise if velocity.y < 0.0 else gravity_fall
	# Apex hang: soften gravity while almost weightless, for a short window.
	if absf(velocity.y) < apex_threshold and apex_t < apex_max_time:
		g *= apex_gravity_scale
		apex_t += delta
	velocity.y = minf(velocity.y + g * delta, max_fall_speed)


func _post_move(fall_speed: float, delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		var strength := clampf((fall_speed - 180.0) / 700.0, 0.0, 1.6)
		if fall_speed > 200.0:
			squash = 1.0 + 0.30 * strength
			Juice.land_dust(get_parent(), global_position + Vector2(0, 22), 0.6 + strength)
			Combat.shake(0.10 + 0.12 * strength)
			Sfx.play("land", -9, 1.0 - 0.1 * strength)
		# Keep the target on an exact quarter turn so faces stay aligned.
		tumble_to = snappedf(tumble_to, PI * 0.5)
		landed.emit(strength)
	elif not on_floor and _was_on_floor:
		airborne_t = 0.0
	_was_on_floor = on_floor


func _start_roll(dir: float) -> void:
	if absf(dir) > 0.01:
		facing = 1 if dir > 0.0 else -1
	hitbox.disable()
	roll_t = 0.0
	_trail_t = 0.0
	velocity.x = facing * roll_speed
	velocity.y = 0.0
	squash = 0.82
	set_state(State.ROLL)
	Sfx.play("roll", -13, randf_range(0.95, 1.05))
	Juice.dust(get_parent(), global_position + Vector2(0, 22), signf(velocity.x), 0.8)


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
		float(attack_cfg.get("damage", 10.0)) * Game.total_damage_mult() * permanent_damage_mult,
		float(attack_cfg.get("knockback", 180.0)),
		float(attack_cfg.get("hitstop", 0.05)),
		self,
		crit_multiplier(),
		int(attack_cfg.get("tier", 0))
	)
	# The arc is drawn around the grip, not the body centre.
	var blade := float(attack_cfg.get("blade", 38.0))
	Combat.slash(
		global_position + Vector2(float(facing) * 13.0, 4.0),
		facing,
		attack_index,
		MathArt.WHITE,
		blade
	)
	if attack_index == weapon_combo.size() - 1 and not weapon_combo.is_empty():
		var wave := FunctionWave.new()
		wave.position = global_position + Vector2(facing * 26.0, -10.0)
		wave.setup(facing, 8.0 * Game.total_damage_mult() * permanent_damage_mult, MathArt.WHITE, self, crit_multiplier())
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
	var damage := float(info.get("damage", 1)) * armor_taken
	hp = maxf(0.0, hp - damage)
	invuln = invuln_time
	flash = 0.14
	squash = 1.24
	hurt_t = hurt_time
	hitbox.disable()

	var source_pos: Vector2 = info.get("source_pos", global_position)
	var dir := signf(global_position.x - source_pos.x)
	if dir == 0.0:
		dir = -facing
	velocity = Vector2(dir * hurt_knockback, -150.0)
	set_state(State.HURT)

	Combat.hitstop(0.09)
	Combat.shake(0.6)
	Combat.damage_number(global_position + Vector2(0, -46), int(damage), false)
	Combat.spark(global_position + Vector2(0, -14), Vector2(dir, 0), false, MathArt.WHITE)
	Combat.hurt_burst(global_position + Vector2(float(dir) * 10.0, -10.0), int(dir))
	Juice.hit_sparks(get_parent(), global_position + Vector2(float(dir) * 8.0, -10.0), Vector2(dir, 0), 1.2)
	Sfx.play("hurt", -6)
	Game.hurt_flash = 0.32
	Game.combo_break()

	if hp <= 0.0:
		_die()


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)
	Juice.pickup(get_parent(), global_position + Vector2(0, -10))


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
	var spawn := global_position + Vector2(float(facing) * 8.0, -16.0)
	var target := _nearest_enemy(540.0)
	var aim_point := spawn + Vector2(float(facing) * 360.0, -70.0)
	if target != null:
		aim_point = target.global_position + Vector2(0, -16)
	var velocity := MathArt.ballistic_velocity(spawn, aim_point, knife_speed, Projectile.KUNAI_GRAVITY)
	var projectile := Projectile.new()
	projectile.position = spawn
	projectile.setup_player(
		velocity,
		knife_damage * Game.total_damage_mult() * permanent_damage_mult,
		MathArt.WHITE,
		self,
		crit_multiplier()
	)
	var root: Node = Game.fx_root
	if is_instance_valid(root):
		root.add_child(projectile)
	Combat.parabola_preview(spawn, velocity, Projectile.KUNAI_GRAVITY)
	Combat.burst(spawn, MathArt.WHITE, 4, 90.0)
	Sfx.play("throw", -9, randf_range(0.95, 1.05))


func _cast_aegis() -> void:
	if aegis_cd > 0.0 or state == State.DEAD:
		return
	aegis_t = aegis_time
	aegis_cd = aegis_time + aegis_cooldown * aegis_cooldown_scale
	Combat.ring(global_position + Vector2(0, -6), MathArt.WHITE, 52.0)
	Combat.burst(global_position + Vector2(0, -8), MathArt.WHITE, 10, 150.0)
	Sfx.play("dodge", -10, 0.8)


func _aegis_block() -> void:
	aegis_t = 0.0
	Combat.block_number(global_position + Vector2(0, -50))
	var block_point := global_position + Vector2(float(facing) * 14.0, -8.0)
	Combat.spark(block_point, Vector2(float(facing), 0.0), false, MathArt.WHITE)
	Combat.block_burst(block_point, facing)
	Combat.impact(block_point, Vector2(float(facing), 0.0), 1, MathArt.WHITE)
	Combat.ring(global_position + Vector2(0, -8), MathArt.WHITE, 46.0)
	Juice.block(get_parent(), block_point, facing)
	Combat.shake(0.22)
	Sfx.play("block", -6, 1.1)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy._dead:
			continue
		if global_position.distance_to(enemy.global_position) <= 118.0:
			enemy.take_hit({
				"damage": Damage.compute(10.0 * Game.total_damage_mult() * permanent_damage_mult, 0, false, 1.0),
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
	velocity = Vector2(-facing * 140.0, -300.0)
	Combat.burst(global_position + Vector2(0, -16), MathArt.WHITE, 20, 280.0)
	Juice.shatter(get_parent(), global_position + Vector2(0, -14), MathArt.WHITE, 18)
	Combat.shake(0.85)
	Sfx.play("death", -5)
	Game.end_run(false)
	died.emit()
