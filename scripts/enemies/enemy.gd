class_name Enemy
extends CharacterBody2D
## Data-driven enemy. Three behaviours share one state machine so tuning stays
## in data/enemies.json.

signal died(enemy: Enemy)

enum EState { IDLE, CHASE, WINDUP, ATTACK, RECOVER, HURT, DEAD }

const GRAVITY := 1750.0
## Bodies closer than this (plus both radii) push each other apart, so five
## husks cannot stack into one silhouette in a corner.
const SEPARATION := 6.0
## Deadband for turning around. Without it `facing` flips every frame whenever
## the player stands at the enemy's own x, the acceleration cancels itself, and
## the body vibrates in place for the whole floor - on a deck that reads as an
## enemy that never comes down.
const TURN_DEADBAND := 6.0
## One horizontal acceleration for every chase, in px/s^2.
const ACCEL := 900.0


## The spitter's glob leaves this behind: a short-lived damaging pool. A plain
## distance check instead of an Area2D, because the pool must outlive the
## spitter that made it.
class GlobPool extends Node2D:
	var radius := 30.0
	var damage := 6.0
	var life := 2.4
	var source: Node2D = null
	var _t := 0.0
	var _tick := 0.0

	func _physics_process(delta: float) -> void:
		_t += delta
		_tick -= delta
		queue_redraw()
		if _t >= life:
			queue_free()
			return
		var player := Game.player
		if player == null or _tick > 0.0:
			return
		if player.global_position.distance_to(global_position) < radius:
			_tick = 0.45
			player.take_hit({
				"damage": damage,
				"source_pos": source.global_position if is_instance_valid(source) else global_position,
			})

	func _draw() -> void:
		# A flattened 7-point star: the spitter's own geometry, pooled on the
		# floor. Dark fill, bright edge, five phyllotaxis bubbles.
		var fade := clampf((life - _t) / 0.5, 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(_t * 11.0)
		var ring := MathArt.star(7, radius, radius * 0.82, _t * 0.6)
		for i in ring.size():
			ring[i].y *= 0.34
		MathArt.px_poly(self, ring, Color(MathArt.INK, 0.62 * fade),
			Color(MathArt.DANGER, (0.30 + 0.35 * pulse) * fade), 2.0)
		for i in 5:
			var bubble := MathArt.phyllotaxis(i + 1, radius * 0.26)
			MathArt.disc(self, Vector2(bubble.x, bubble.y * 0.34), 2.0,
				Color(MathArt.DANGER, (0.25 + 0.4 * pulse) * fade))

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
## The tier of the hit that killed this body, so a finisher kill can read
## heavier than a chip kill. take_hit() resolves the tier; _die() is the only
## place that needs to know it afterwards.
var last_tier := 0
var _spawn_t := 0.0
var _was_on_floor := true
var _pending_attack := "cleave"
var _pattern := 0
var _slam_done := false
var _slam_at := 0.0
var _stuck := 0.0
var _climb_cd := 0.0
var _recover_cd := 0.0
var _glob: Projectile = null
var _glob_fired := false
var _glob_at := Vector2.ZERO


var poison_left := 0.0
var poison_tick := 0.0
var poison_attr := 0


func configure(kind_id: String, config: Dictionary, hp_scale: float = 1.0) -> void:
	kind = kind_id
	cfg = config
	max_hp = float(cfg.get("hp", 40.0)) * hp_scale
	hp = max_hp


func _ready() -> void:
	collision_layer = Layers.ENEMY
	collision_mask = Layers.WORLD | Layers.ONEWAY | Layers.PLAYER
	add_to_group("enemies")
	z_index = 1
	_build_nodes()
	state_t = 0.0
	_spawn_t = randf_range(0.1, 0.4)
	_deembed.call_deferred()
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
	if poison_left > 0 and not _dead:
		poison_left = maxf(0, poison_left - delta)
		poison_tick -= delta
		if poison_tick <= 0:
			var status: Dictionary = Data.gear["statuses"]["poison"]
			poison_tick += float(status["interval"])
			var amount := Damage.compute(float(status["damage"]), poison_attr, false, 1)
			hp -= amount
			Combat.damage_number(global_position + Vector2(0, -50), amount, false)
			if hp <= 0:
				_die()
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
	_recover_cd = maxf(0.0, _recover_cd - delta)
	_climb_cd = maxf(0.0, _climb_cd - delta)
	_track_glob()

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

	# A body pressed into a wall has to give up on that direction, or it stands
	# in the corner for the rest of the floor. Reverse, then hop: a step deck or
	# a low lip is cleared by the hop, a tall pillar is not, so this cannot
	# launch a body into geometry it could not walk to.
	# IDLE *is* chasing: the state match below falls through to _tick_chase() for
	# anything that is not HURT/WINDUP/ATTACK/RECOVER, so a body only reaches
	# EState.CHASE after its first attack. Testing `state == EState.CHASE` here
	# meant this anti-stuck hop and the climb hop below were dead code for every
	# untouched enemy - which is exactly the common case.
	if _is_walking() and is_on_wall() and absf(velocity.x) < 20.0:
		_stuck += delta
	else:
		_stuck = 0.0
	if _stuck > 0.30 and _recover_cd <= 0.0:
		_stuck = 0.0
		_recover_cd = 0.9
		facing = -facing
		velocity.x = facing * float(cfg.get("speed", 80.0))
		velocity.y = -340.0

	# A melee body must climb. The generator rewards the upper route with cell
	# caches, and before this a grunt simply walked to the player's x and idled
	# under a 92 px deck, so the gallery was a free safe zone against four of the
	# six kinds - and the door needs every body dead, so the fight stalled until
	# the player came back down. A hop only when the target is genuinely above,
	# so a body never bounces on flat ground.
	if _climb_cd <= 0.0 and _is_walking() and is_on_floor():
		var above := global_position.y - player.global_position.y
		if above > 40.0 and absf(player.global_position.x - global_position.x) < 220.0:
			_climb_cd = 0.7
			velocity.y = -560.0
			velocity.x = _gate(facing, player) * float(cfg.get("speed", 80.0)) * 1.4

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


## True in the states that mean "walking at the player": the state machine's
## default branch, plus CHASE, which the body takes after its first recovery.
func _is_walking() -> bool:
	return state == EState.IDLE or state == EState.CHASE


func _tick_chase(player: Player, delta: float) -> void:
	if _spawn_t > 0.0:
		velocity.x = 0.0
		return
	var delta_pos := player.global_position - global_position
	var distance := delta_pos.length()
	# Deadband: the player standing on the enemy's own x used to flip `facing`
	# every frame, which cancelled the acceleration and left the body vibrating
	# in place for the whole floor.
	# A melee body whose target is a deck lower is not walking to the player's x,
	# it is walking to the edge: widen the deadband to infinity so it commits to
	# one direction and actually drops, instead of shuffling on the deck.
	var deadband := TURN_DEADBAND
	if delta_pos.y > 56.0 and not kind in ["archer", "spitter", "leaper"]:
		deadband = 1.0e9
	if absf(delta_pos.x) > deadband:
		facing = 1 if delta_pos.x > 0.0 else -1
	var speed := float(cfg.get("speed", 80.0))
	var attack_range := float(cfg.get("attack_range", 60.0))
	# A crowd must never pin a body in place: two enemies sharing a spot pushed
	# each other with a force larger than their own speed, so neither moved and
	# the fight stalled. The push is capped relative to speed.
	var push := clampf(_separation(), -speed * 0.6, speed * 0.6)

	match kind:
		"warden":
			if attack_cd <= 0.0:
				if distance < 150.0:
					_pending_attack = "cleave"
				else:
					_pattern += 1
					_pending_attack = "charge" if _pattern % 2 == 1 else "slam"
				_enter_windup()
				return
			velocity.x = move_toward(velocity.x, _gate(facing, player) * speed + push, ACCEL * delta)
		"archer", "spitter":
			# No line of fire means no shot, and walking at the player is the only
			# way an archer ever gets around the pillar it is hiding behind.
			if not _clear_shot(player.global_position):
				velocity.x = move_toward(velocity.x, _gate(facing, player) * speed + push, ACCEL * delta)
				return
			if attack_cd <= 0.0 and distance < attack_range and absf(delta_pos.y) < 200.0:
				_enter_windup()
				return
			var hold := 0.0
			if distance < 170.0:
				# Backing off goes through the ledge gate like every other intent:
				# a retreat that steps off a deck drops the archer out of the fight
				# instead of holding the ledge.
				hold = float(_gate(-facing, player)) * speed
			elif distance > 360.0:
				hold = _gate(facing, player) * speed
			velocity.x = move_toward(velocity.x, hold + push, 1200.0 * delta)
		"leaper":
			# The hop is the whole threat: it fires whenever the player is above
			# it, which is exactly the high deck it punishes.
			if attack_cd <= 0.0 and distance < attack_range and absf(delta_pos.y) < 280.0:
				_enter_windup()
				return
			velocity.x = move_toward(velocity.x, _gate(facing, player) * speed + push, ACCEL * delta)
		"charger":
			if attack_cd <= 0.0 and distance < attack_range and absf(delta_pos.y) < 120.0:
				_enter_windup()
				return
			velocity.x = move_toward(velocity.x, _gate(facing, player) * speed + push, ACCEL * delta)
		_:
			if distance < attack_range and absf(delta_pos.y) < 56.0:
				_enter_windup()
				return
			velocity.x = move_toward(velocity.x, _gate(facing, player) * speed + push, ACCEL * delta)


## The direction to actually move in: `dir` when the ground holds, 0 when the
## body would walk off a deck it has no reason to leave.
func _gate(dir: int, player: Player) -> int:
	return dir if _may_walk(dir, player) else 0


## True when there is solid ground within `reach` px ahead of `dir`.
## Uses a short downward ray from just in front of the body.
func _ground_ahead(dir: int, reach := 16.0) -> bool:
	if not is_inside_tree():
		return true
	var from := global_position + Vector2(float(dir) * reach, -6.0)
	var query := PhysicsRayQueryParameters2D.create(
		from, from + Vector2(0.0, 40.0), Layers.WORLD | Layers.ONEWAY)
	query.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return not hit.is_empty()


## A ground body must not walk off a deck unless dropping is the way to reach
## the player. Returns true when it is safe to keep moving in `dir`.
func _may_walk(dir: int, player: Player) -> bool:
	if not is_on_floor():
		return true
	if _ground_ahead(dir):
		return true
	# No ground ahead. Step off only if the player is genuinely below: an enemy
	# that drops to chase must not then walk off into the void on the flat.
	# There is no height cap - enemies take no fall damage, and a cap stopped a
	# body on a high deck from ever reaching a player on the bottom ledge.
	if player == null:
		return false
	var below := player.global_position.y - global_position.y
	return below > 24.0


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
	elif kind == "leaper":
		Sfx.play("jump", -18, 0.7)
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
	if kind == "spitter":
		_spit()
		Sfx.play("throw", -9, 0.8)
		return
	if kind == "leaper":
		_hop()
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
	if kind == "leaper":
		# The hitbox only opens on the frame the body lands: the arc above is the
		# telegraph, so a slam that never lands never deals damage.
		if not _slam_done and state_t > 0.06 and is_on_floor():
			_slam_done = true
			_slam_at = state_t
			velocity.x = 0.0
			# Centred and tall: the slam has to connect whether the body came
			# down on the slab next to the player or on the player itself.
			_enable_hitbox(Vector2(104.0, 76.0), 0.0, 6.0, float(cfg.get("damage", 12.0)))
			Combat.shake(0.30)
			Combat.dust(global_position + Vector2(0, 20), 12, Vector2(0, 1))
			Juice.land_dust(get_parent(), global_position + Vector2(0, 22), 1.0)
			Sfx.play("land", -8, 0.75)
		# A hop spends ~0.9 s in the air, so the normal `active` window would
		# expire before the body ever lands and the slam could not happen.
		if _slam_done and state_t >= _slam_at + float(cfg.get("active", 0.12)):
			hitbox.disable()
			state = EState.RECOVER
			state_t = 0.0
		elif state_t > 2.5:
			hitbox.disable()
			state = EState.RECOVER
			state_t = 0.0
		return
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


## A deliberate hop to the player's x. Flight time is fixed (2*v/g), so the
## horizontal speed that lands on the player is dx / flight, clamped: the
## leaper commits to a spot, it does not track mid-air.
## Only as much lift as the player's deck needs: a fixed lift overshoots and
## lands the body on a deck it was never aiming for.
func _hop_lift_for(player: Player) -> float:
	var rise := float(cfg.get("hop_rise", 260.0))
	if player == null:
		return sqrt(2.0 * GRAVITY * rise * 0.5)
	var dy := (player.global_position.y - 22.0) - global_position.y
	# The floor of this clamp is a REAL hop, not a nudge: at 24 the leaper rose
	# 30 px when the player was level with it, which reads as a stumble rather
	# than a pounce and never clears a deck edge.
	return sqrt(2.0 * GRAVITY * clampf(-dy + 30.0, 74.0, rise))


func _hop() -> void:
	var player := Game.player
	var lift := _hop_lift_for(player)
	var dx := 0.0
	var dy := 0.0
	if player != null:
		dx = player.global_position.x - global_position.x
		dy = (player.global_position.y - 22.0) - global_position.y
	# Later root of -lift*t + g*t^2/2 = dy: when the body falls back to the
	# player's feet, it must be at the player's x.
	var flight := (lift + sqrt(maxf(lift * lift + 2.0 * GRAVITY * dy, 1.0))) / GRAVITY
	velocity.x = clampf(dx / maxf(flight, 0.2), -float(cfg.get("hop_speed", 420.0)),
		float(cfg.get("hop_speed", 420.0)))
	velocity.y = -lift
	facing = 1 if velocity.x > 0.0 else -1
	Juice.jump_burst(get_parent(), global_position + Vector2(0, 18))
	Sfx.play("jump", -12, 0.85)


func _spit() -> void:
	var player := Game.player
	if player == null:
		return
	var spawn := global_position + Vector2(facing * _bow_offset(), -12.0)
	var target := player.global_position + Vector2(0, -10)
	var velocity := MathArt.ballistic_velocity(spawn, target,
		float(cfg.get("projectile_speed", 250.0)), 700.0)
	var glob := Projectile.new()
	glob.position = spawn
	glob.setup_ballistic(velocity, float(cfg.get("damage", 8.0)), MathArt.DANGER, self)
	var root := Game.fx_root
	if is_instance_valid(root):
		root.add_child(glob)
		_glob = glob
		_glob_fired = true
		_glob_at = spawn
	Combat.burst(spawn, 4)


## The glob is a shared Projectile, so its landing point is not reported: poll
## it and drop the pool where it was last seen. shortcut: a glob that expires
## in mid air would pool there; the floors all have a continuous bottom ledge,
## so it always lands first.
func _track_glob() -> void:
	# A freed Object compares EQUAL to null in GDScript, so `if _glob == null`
	# returned early on exactly the frame the glob died and the pool was never
	# created. Track "did we fire" with a flag instead of the reference.
	if not _glob_fired:
		return
	if is_instance_valid(_glob):
		_glob_at = _glob.global_position
		return
	_glob = null
	_glob_fired = false
	_spawn_pool(_glob_at)


func _spawn_pool(at: Vector2) -> void:
	var root := Game.fx_root
	if not is_instance_valid(root):
		return
	var pool := GlobPool.new()
	pool.name = "GlobPool"
	pool.position = at
	pool.radius = float(cfg.get("pool_radius", 30.0))
	pool.damage = float(cfg.get("pool_damage", 6.0))
	pool.life = float(cfg.get("pool_time", 2.4))
	pool.source = self
	# Group, not a type check: GlobPool is an inner class, so Main cannot name it
	# to purge it. Without this a glob outlives its floor and follows the player
	# into the hub (it is parented to fx_root/world, not to the level).
	pool.add_to_group("hazard_pool")
	root.add_child(pool)
	Juice.shatter(root, at, MathArt.DANGER, 6)
	Sfx.play("land", -14, 1.4)


## Anything solid between the eye and the target cancels the shot.
func _clear_shot(target: Vector2) -> bool:
	if not is_inside_tree():
		return true
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position + Vector2(0.0, -10.0), target + Vector2(0.0, -14.0), Layers.WORLD)
	return space.intersect_ray(query).is_empty()


## Soft body separation. Physics cannot do it: enemies do not collide with each
## other, and 13 bodies that all want the player's exact x would stack.
func _separation() -> float:
	var push := 0.0
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other):
			continue
		var delta_pos: Vector2 = global_position - (other as Node2D).global_position
		if absf(delta_pos.y) > 30.0:
			continue
		var reach := float(cfg.get("body_radius", 12.0)) + float(other.cfg.get("body_radius", 12.0)) + SEPARATION
		if absf(delta_pos.x) >= reach:
			continue
		var dir := signf(delta_pos.x)
		if dir == 0.0:
			dir = 1.0 if get_instance_id() > other.get_instance_id() else -1.0
		push += dir * (reach - absf(delta_pos.x)) * 4.0
	return clampf(push, -180.0, 180.0)


## level.gd's last-resort spawn point is the room centre, which is exactly where
## a "well" room stands its wall. Lift the body out of solid stone before the
## first physics step, or it never leaves it. One-way decks are ignored on
## purpose: a body under a deck is legal, it just jumps up through it.
func _deembed() -> void:
	if not is_inside_tree() or _dead:
		return
	var space := get_world_2d().direct_space_state
	var offsets: Array = []
	for step in 14:
		offsets.append(Vector2(0.0, -8.0 * float(step)))
	for side in [1.0, -1.0]:
		for step in 4:
			offsets.append(Vector2(side * (14.0 + 12.0 * float(step)), 0.0))
	for offset in offsets:
		if not _buried(space, global_position + offset):
			global_position += offset
			return


func _buried(space: PhysicsDirectSpaceState2D, at: Vector2) -> bool:
	var params := PhysicsShapeQueryParameters2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = float(cfg.get("body_radius", 12.0))
	capsule.height = float(cfg.get("body_height", 42.0))
	params.shape = capsule
	params.transform = Transform2D(0.0, at)
	params.collision_mask = Layers.WORLD
	params.collide_with_bodies = true
	return not space.intersect_shape(params, 1).is_empty()


## Cells were dropped at the death point and sank through the slab into stone,
## 300 px under a player who was standing right on top of them. Settle the drop
## onto the first surface below instead. Deferred because a ray query is not
## legal while the physics space is flushing (death happens in a signal).
func _settle_pickup(pickup: CellPickup) -> void:
	if not is_instance_valid(pickup) or not is_inside_tree():
		return
	var space := get_world_2d().direct_space_state
	for lift in [48.0, 150.0, 300.0]:
		var from := global_position + Vector2(0.0, -lift)
		var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, lift + 260.0),
			Layers.WORLD | Layers.ONEWAY)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var point: Vector2 = hit["position"]
		if point.distance_to(from) < 4.0:
			continue
		pickup.global_position = point + Vector2(0.0, -12.0)
		return


func _spawn_shockwaves() -> void:
	Combat.shake(0.5)
	Sfx.play("slam", -7, 0.85)
	Combat.dust(global_position + Vector2(0, 28), 16, Vector2(0, 1))
	# The feet take the hit, not the body: a ring on the ground line is what makes
	# the slam read as "the floor moved" rather than "the boss stopped".
	var feet := global_position + Vector2(0.0, float(cfg.get("body_height", 64.0)) * 0.5)
	Combat.ring(feet, MathArt.DANGER, 62.0)
	Juice.land_dust(get_parent(), feet, 1.4)
	for direction in [-1.0, 1.0]:
		var wave := Projectile.new()
		# Relative to the boss, 16 px above its feet: the wave has to travel
		# along the floor the player is standing on, whatever y that floor is.
		wave.position = global_position + Vector2(direction * 34.0, -16.0)
		wave.setup_wave(
			Vector2(direction, 0),
			float(cfg.get("shockwave_speed", 430.0)),
			float(cfg.get("shockwave_damage", 13.0)),
			MathArt.DANGER,
			self
		)
		var root := Game.fx_root
		if is_instance_valid(root):
			root.add_child(wave)


func _tick_recover() -> void:
	# Recovery drifts onto the separation push instead of onto zero: a body that
	# has just attacked is the one the others were queued behind.
	velocity.x = move_toward(velocity.x, _separation(), 1000.0 * get_physics_process_delta_time())
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
	projectile.setup_ballistic(velocity, float(cfg.get("damage", 7.0)), MathArt.DANGER, self)
	var root := Game.fx_root
	if is_instance_valid(root):
		root.add_child(projectile)
	Combat.burst(spawn, 5)
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
		# A chip kill must pop quietly: last_tier still holds the tier of the last
		# UNSHIELDED hit, so without this a bulwark finished by a 1-damage front
		# chip inherited the finisher's 133 ms freeze and screen punch.
		last_tier = 0
		Combat.block_number(global_position + Vector2(0, -54))
		var shield_point := global_position + Vector2(float(facing) * 18.0, -10.0)
		Combat.spark(shield_point, Vector2(float(facing), 0.0), false, MathArt.FIRE)
		Combat.block_burst(shield_point, facing)
		Combat.impact(shield_point, Vector2(float(facing), 0.0), 0, MathArt.FIRE)
		Juice.block(get_parent(), shield_point, facing)
		Sfx.play("block", -8)
		Combat.shake(0.10)
		if hp <= 0.0:
			_die()
		return

	hp -= damage
	if str(info.get("status", "")) == "poison":
		poison_left = float(Data.gear["statuses"]["poison"]["duration"])
		poison_tick = float(Data.gear["statuses"]["poison"]["interval"])
		poison_attr = int(info.get("status_attr", 0))
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
	last_tier = tier
	Combat.impact(contact, Vector2(float(dir), 0.0), tier, MathArt.FIRE)
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
	if Game.build != null and not Game.run_over:
		Game.build.gold += int(Data.gear["economy"]["kill_gold"])
	state = EState.DEAD
	hitbox.disable()
	collision_layer = 0
	collision_mask = 0
	velocity = Vector2(randf_range(-60.0, 60.0), -160.0)
	var tint := MathArt.BOSS if bool(cfg.get("boss", false)) else MathArt.ENEMY
	var sides := 3
	match kind:
		"archer":
			sides = 8
		"spitter":
			sides = 7
		"leaper":
			sides = 3
		"charger":
			sides = 4
		"bulwark":
			sides = 6
		"warden":
			sides = 5
	var is_boss := bool(cfg.get("boss", false))
	# Kill feedback: the silhouette itself breaks into 12-24 shards, plus a
	# directional spark burst and a heavy screen punch. The pop is the tier of
	# the hit that landed it, so killing with the finisher is the loudest thing
	# in a fight and chipping a husk to death stays quiet.
	var kill_tier := clampi(maxi(1, last_tier), 1, 3)
	Combat.shatter(global_position + Vector2(0, -14), tint, sides,
		24 if is_boss else 12, 420.0 if is_boss else 320.0)
	Combat.impact(global_position + Vector2(0, -16), Vector2(0, -1), 3 if is_boss else kill_tier, MathArt.FIRE)
	Juice.shatter(get_parent(), global_position + Vector2(0, -14), tint, 24 if is_boss else 12)
	if is_boss:
		Combat.screen_punch(0.9)
	elif kill_tier >= 3:
		Combat.screen_punch(0.55)
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
		_settle_pickup.call_deferred(pickup)

	if Game.boss == self:
		Game.boss_defeated = true
	# Record the dead boss identity before clearing the live HUD pointer.
	Game.add_kill(is_boss)
	if Game.boss == self:
		Game.boss = null
	died.emit(self)
	var tween := create_tween()
	tween.tween_property(visual, "modulate:a", 0.0, 0.35)
	tween.tween_callback(queue_free)
