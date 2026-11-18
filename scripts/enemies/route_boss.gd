class_name RouteBoss
extends Enemy
## Three route encounters on Enemy's damage, poison, physics and death lifecycle.
## Choose committed geometry so movement, jumping and counterattacks answer different threats.
## Reject homing attacks and permanent armour: a read must stay valid through its windup.

const KINDS := ["bridge_sentinel", "clock_warden", "silent_regent"]
const MAX_HAZARDS := 12
const MAX_HAZARD_TTL := 6.0

class OwnedProjectile extends Projectile:
	func _physics_process(delta: float) -> void:
		if not is_instance_valid(source) or source._dead or source.is_queued_for_deletion() or Game.run_over:
			queue_free()
			return
		super._physics_process(delta)

	func _on_body_entered(body: Node) -> void:
		if is_instance_valid(source) and not source._dead and not source.is_queued_for_deletion() and not is_queued_for_deletion() and not Game.run_over:
			super._on_body_entered(body)


var phase := 1
var attack_phase := 1
var zones: Array[Rect2] = []
var floor_y := 0.0
var leap_target := Vector2.ZERO
var _leap_velocity := Vector2.ZERO
var _leap_landed := false
var _lane_index := 0
var _lane_at := 0.0
var _hazards: Array[Node2D] = []


static func required_fields(kind_id: String) -> Array[String]:
	var fields: Array[String] = ["hp", "body_radius", "body_height", "speed", "damage",
		"windup", "recovery", "active", "cooldown", "attack_range", "knockback"]
	match kind_id:
		"bridge_sentinel":
			fields.append_array(["charge_speed", "shockwave_speed", "shockwave_damage", "wave_life"])
		"clock_warden":
			fields.append_array(["leap_time", "leap_speed", "lane_speed", "lane_damage",
				"lane_interval", "lane_life", "lane_lower_height", "lane_upper_height"])
		"silent_regent":
			fields.append_array(["column_width", "column_height", "column_spacing",
				"column_delay", "column_active", "column_damage"])
	return fields


func configure(kind_id: String, config: Dictionary, hp_scale: float = 1.0) -> void:
	assert(kind_id in KINDS, "Unknown route boss: " + kind_id)
	for field in required_fields(kind_id):
		assert(config.has(field) and float(config[field]) > 0.0, kind_id + " requires positive " + field)
	var owned := config.duplicate(true)
	owned["boss"] = true
	owned["shield"] = false
	super.configure(kind_id, owned, hp_scale)


func _build_nodes() -> void:
	super._build_nodes()
	remove_child(visual)
	visual.free()
	visual = RouteBossVisual.new()
	visual.name = "Visual"
	add_child(visual)


func _physics_process(delta: float) -> void:
	if not _dead and phase == 1 and hp < max_hp * 0.5:
		phase = 2
		_pattern = 0
	super._physics_process(delta)


func _tick_chase(player: Player, delta: float) -> void:
	if _spawn_t > 0.0:
		velocity.x = 0.0
		return
	var dx := player.global_position.x - global_position.x
	if absf(dx) > TURN_DEADBAND:
		facing = 1 if dx > 0.0 else -1
	if attack_cd <= 0.0 and is_on_floor() and absf(dx) <= float(cfg["attack_range"]):
		var pattern: Array
		match kind:
			"bridge_sentinel":
				pattern = ["cleave", "charge", "floor_wave"] if phase == 1 else ["charge", "floor_wave", "cleave", "floor_wave"]
			"clock_warden":
				pattern = ["leap", "lanes"] if phase == 1 else ["lanes", "leap", "lanes"]
			_:
				pattern = ["columns", "sweep"] if phase == 1 else ["columns", "guard", "sweep"]
		_pending_attack = pattern[_pattern % pattern.size()]
		_pattern += 1
		_enter_windup()
		return
	velocity.x = move_toward(velocity.x, float(_gate(facing, player)) * float(cfg["speed"]), ACCEL * delta)


## Ray from body height down; no floor means no floor hazard at that x.
func _floor_at(x: float) -> Variant:
	var from := Vector2(x, global_position.y)
	var query := PhysicsRayQueryParameters2D.create(from,
		from + Vector2(0.0, float(cfg["body_height"]) * MathArt.PHI * MathArt.PHI), Layers.WORLD | Layers.ONEWAY)
	query.exclude = [get_rid()]
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	return null if result.is_empty() else result["position"]


func _enter_windup() -> void:
	super._enter_windup()
	attack_phase = phase
	zones.clear()
	var ground: Variant = _floor_at(global_position.x)
	floor_y = global_position.y + float(cfg["body_height"]) * 0.5 if ground == null else ground.y
	_leap_landed = false
	_lane_index = 0
	_lane_at = 0.0
	match _pending_attack:
		"cleave", "sweep", "guard":
			zones.append(_melee_rect(_pending_attack == "sweep"))
		"charge":
			var box := _charge_rect()
			zones.append(_swept(box, Vector2(float(facing) * float(cfg["charge_speed"]) * float(cfg["active"]), 0.0)))
		"floor_wave":
			_plan_waves()
		"leap":
			_plan_leap()
		"lanes":
			for index in _lane_count():
				var origin := _lane_origin(index)
				zones.append(_swept(Rect2(origin - Vector2.ONE * 4.0, Vector2.ONE * 8.0),
					Vector2(float(facing) * float(cfg["lane_speed"]) * _lane_life(), 0.0)))
		"columns":
			_plan_columns()


func _tick_windup() -> void:
	velocity.x = 0.0
	if state_t >= float(cfg["windup"]):
		_begin_attack()


func _melee_rect(sweep: bool) -> Rect2:
	var size := Vector2(float(cfg["body_radius"]) * MathArt.PHI * MathArt.PHI, float(cfg["body_height"]))
	var center := global_position + Vector2(float(facing) * size.x * 0.5, 0.0)
	if sweep:
		size.x *= 2.0
		center = global_position
	return Rect2(center - size * 0.5, size)


func _charge_rect() -> Rect2:
	# Attack must extend beyond the physical capsule, which stops before body overlap.
	var size := Vector2(float(cfg["body_radius"]) * MathArt.PHI * MathArt.PHI, float(cfg["body_height"]))
	return Rect2(global_position - size * 0.5, size)


func _swept(rect: Rect2, travel: Vector2) -> Rect2:
	return rect.merge(Rect2(rect.position + travel, rect.size))


func _plan_waves() -> void:
	for dir in [-1.0, 1.0]:
		var origin := _wave_origin(dir)
		zones.append(_swept(Rect2(origin - Vector2.ONE * 14.0, Vector2.ONE * 28.0),
			Vector2(dir * float(cfg["shockwave_speed"]) * _wave_life(), 0.0)))


func _wave_origin(dir: float) -> Vector2:
	return Vector2(global_position.x + dir * (float(cfg["body_radius"]) + 14.0), floor_y - 14.0)


func _wave_life() -> float:
	return minf(float(cfg["wave_life"]), MAX_HAZARD_TTL)


func _lane_life() -> float:
	return minf(float(cfg["lane_life"]), MAX_HAZARD_TTL)


func _lane_count() -> int:
	return 2 if attack_phase == 1 else 4


func _lane_origin(index: int) -> Vector2:
	var height := float(cfg["lane_lower_height"] if index % 2 == 0 else cfg["lane_upper_height"])
	return Vector2(global_position.x + float(facing) * (float(cfg["body_radius"]) + 4.0), floor_y - height)


func _plan_leap() -> void:
	var flight := float(cfg["leap_time"])
	var max_dx := float(cfg["leap_speed"]) * flight
	var target_x := global_position.x
	if is_instance_valid(Game.player):
		target_x += clampf(Game.player.global_position.x - global_position.x, -max_dx, max_dx)
	var ground: Variant = _floor_at(target_x)
	if ground == null:
		ground = Vector2(global_position.x, floor_y)
	leap_target = ground - Vector2(0.0, float(cfg["body_height"]) * 0.5)
	_leap_velocity = Vector2((leap_target.x - global_position.x) / flight,
		(leap_target.y - global_position.y) / flight - GRAVITY * flight * 0.5)
	var size := Vector2(float(cfg["body_radius"]) * MathArt.PHI * MathArt.PHI, float(cfg["body_height"]))
	zones.append(Rect2(leap_target - size * 0.5, size))


func _plan_columns() -> void:
	var center_x := global_position.x
	if is_instance_valid(Game.player):
		center_x = Game.player.global_position.x
	var count := 3 if attack_phase == 1 else 5
	for index in count:
		var x := center_x + (float(index) - float(count - 1) * 0.5) * float(cfg["column_spacing"])
		var ground: Variant = _floor_at(x)
		if ground == null:
			continue
		var size := Vector2(float(cfg["column_width"]), float(cfg["column_height"]))
		zones.append(Rect2(Vector2(x - size.x * 0.5, ground.y - size.y), size))


func _begin_attack() -> void:
	state = EState.ATTACK
	state_t = 0.0
	velocity.x = 0.0
	match _pending_attack:
		"cleave", "sweep", "guard":
			_arm_rect(zones[0])
		"charge":
			_arm_rect(_charge_rect())
			velocity.x = float(facing) * float(cfg["charge_speed"])
		"floor_wave":
			_spawn_route_waves()
		"leap":
			# Only the marked landing hitbox hurts; the body must not land on the player.
			collision_mask &= ~Layers.PLAYER
			velocity = _leap_velocity
			Juice.jump_burst(get_parent(), Vector2(global_position.x, floor_y))
		"lanes":
			_fire_lane()
		"columns":
			for rect in zones:
				var column := RouteBossColumn.new()
				column.top_level = true
				column.position = rect.get_center()
				column.size = rect.size
				column.source = self
				column.damage = float(cfg["column_damage"])
				column.knockback = float(cfg["knockback"])
				column.delay = minf(float(cfg["column_delay"]), MAX_HAZARD_TTL * MathArt.INV_PHI)
				column.duration = minf(float(cfg["column_active"]), MAX_HAZARD_TTL - column.delay)
				_own_hazard(column)
	Sfx.play("boss", -14)


func _arm_rect(rect: Rect2) -> void:
	var offset := rect.get_center() - global_position
	_enable_hitbox(rect.size, offset.x * float(facing), offset.y, float(cfg["damage"]))


func _tick_attack(_delta: float) -> void:
	match _pending_attack:
		"charge":
			velocity.x = float(facing) * float(cfg["charge_speed"])
			if is_on_wall() or state_t >= float(cfg["active"]):
				_recover()
			return
		"leap":
			if not _leap_landed and state_t >= float(cfg["leap_time"]) * 0.5 and is_on_floor():
				_leap_landed = true
				_slam_at = state_t
				velocity.x = 0.0
				# Walls/raised decks can abort a leap; never damage an unmarked landing.
				if global_position.distance_to(leap_target) <= float(cfg["body_radius"]):
					_arm_rect(zones[0])
					Juice.land_dust(get_parent(), Vector2(global_position.x,
						global_position.y + float(cfg["body_height"]) * 0.5), 1.4)
			if (_leap_landed and state_t >= _slam_at + float(cfg["active"])) or state_t >= MAX_HAZARD_TTL:
				_recover()
			return
		"lanes":
			if _lane_index < _lane_count() and state_t >= _lane_at:
				_fire_lane()
			if _lane_index >= _lane_count() and state_t >= _lane_at:
				_recover()
			return
	if state_t >= float(cfg["active"]):
		_recover()


func _recover() -> void:
	hitbox.disable()
	collision_mask |= Layers.PLAYER
	velocity.x = 0.0
	state = EState.RECOVER
	state_t = 0.0
	zones.clear()


func _tick_recover() -> void:
	velocity.x = 0.0
	if state_t >= float(cfg["recovery"]):
		state = EState.CHASE
		state_t = 0.0
		attack_cd = float(cfg["cooldown"])


func _spawn_route_waves() -> void:
	for dir in [-1.0, 1.0]:
		var wave := OwnedProjectile.new()
		wave.top_level = true
		wave.position = _wave_origin(dir)
		wave.setup_wave(Vector2(dir, 0.0), float(cfg["shockwave_speed"]), float(cfg["shockwave_damage"]), MathArt.DANGER, self)
		wave._life = _wave_life()
		_own_hazard(wave)
	Juice.land_dust(get_parent(), Vector2(global_position.x, floor_y), 1.4)


func _fire_lane() -> void:
	var bolt := OwnedProjectile.new()
	bolt.top_level = true
	bolt.position = _lane_origin(_lane_index)
	bolt.setup(Vector2(float(facing), 0.0), float(cfg["lane_speed"]), float(cfg["lane_damage"]), MathArt.DANGER)
	bolt.source = self
	bolt.knockback = float(cfg["knockback"])
	bolt._life = _lane_life()
	_own_hazard(bolt)
	_lane_index += 1
	_lane_at = float(_lane_index) * float(cfg["lane_interval"])


func _own_hazard(hazard: Node2D) -> void:
	for index in range(_hazards.size() - 1, -1, -1):
		if not is_instance_valid(_hazards[index]) or _hazards[index].is_queued_for_deletion():
			_hazards.remove_at(index)
	if _hazards.size() >= MAX_HAZARDS:
		_disarm(_hazards.pop_front())
	_hazards.append(hazard)
	add_child(hazard)


func _disarm(hazard) -> void:
	# Expired hazards remain in the owner list until spawn/death; validate before casting.
	if not is_instance_valid(hazard):
		return
	hazard.set_physics_process(false)
	if hazard is Hitbox:
		hazard.disable()
	if hazard is Area2D:
		hazard.set_deferred("monitoring", false)
		hazard.collision_mask = 0
		hazard.collision_layer = 0
	hazard.queue_free()


func _guarding() -> bool:
	return kind == "silent_regent" and _pending_attack == "guard" and state in [EState.WINDUP, EState.ATTACK]


func is_exposed() -> bool:
	return false if _guarding() else super.is_exposed()


func take_hit(info: Dictionary) -> void:
	var committed := velocity
	cfg["shield"] = _guarding()
	super.take_hit(info)
	cfg["shield"] = false
	if not _dead:
		velocity = committed


func _die() -> void:
	if _dead:
		return
	for hazard in _hazards:
		_disarm(hazard)
	_hazards.clear()
	zones.clear()
	super._die()
