class_name Player
extends CharacterBody2D
## Movement and combat feel. Everything is tuned for motion first: asymmetric
## gravity, apex hang, a square that tumbles one face per jump, and generous
## input forgiveness. Semantic colors keep player attacks and threats distinct.

signal died
signal landed(strength: float)
signal took_off

enum State { IDLE, RUN, AIR, ROLL, ATTACK, HURT, DEAD, CLIMB, DIVE }

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
## Stays in sync with BASE_ROLL_IFRAME_END: _apply_loadout() rebuilds every
## accumulator from these, so a second call cannot compound them.
## The window is measured from the START of the roll and is allowed to outlast
## the ROLL state (0.30 s): armour, GHOST and the GLASS passive all add to it,
## and before this the gate was `state == ROLL and roll_t <= roll_iframe_end`,
## so every value above 0.30 was silently unreachable - a paid upgrade that
## provably did nothing.
@export var roll_iframe_end := BASE_ROLL_IFRAME_END
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

# Echo passive: the swing repeats a beat later for 60% (data/characters.json).
const ECHO_DELAY := 0.12
const ECHO_ACTIVE := 0.08
const ECHO_SCALE := 0.6

# Defaults for the values _apply_loadout() adds to. Kept as constants so the
# reset is one assignment and cannot drift from the exported default.
const BASE_ROLL_IFRAME_END := 0.24
const BASE_CRIT_BONUS := 0.0

var state: State = State.IDLE
var _action_lock := 0.0
var traversal_world: Node
var _climb_vine := Rect2()
var _wall_jump_t := 0.0
var facing := 1
var hp := 0.0
var invuln := 0.0
var flash := 0.0
var squash := 1.0

var coyote := 0.0
var jump_buffer := 0.0
var drop_through_t := 0.0
var roll_t := 0.0
## Counts up from the start of a roll and keeps counting through the recovery,
## so i-frames bought past roll_time (up to 0.43 s) actually exist.
var roll_iframe_t := 999.0
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
var weapon_slot := 0
var guard_item: Dictionary = {}
var guard_t := 0.0
var aegis_item: Dictionary = {}
var _air_roll_used := false
var weapon_combo: Array = []
var attack_cfg: Dictionary = {}
var hitbox: Hitbox
var echo_box: Hitbox
var visual: PlayerVisual
var camera: PlayerCamera

var _trail_t := 0.0
var _dust_t := 0.0
var _was_on_floor := true
var _echo_t := -1.0
var _echo_cfg: Dictionary = {}


func _ready() -> void:
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD | Layers.ONEWAY | Layers.ENEMY
	_apply_loadout()
	# After the loadout: hp starts at the BODY's max, not at the base 120, or a
	# 96 hp body spawns over-healed and a 150 hp body spawns wounded.
	hp = max_hp
	weapon_combo = weapon.get("combo", [])
	knife_charges = knife_max
	_build_nodes()
	Game.player = self
	add_to_group("player")


## Route projection reads RunBuild only; Hub/legacy fixtures retain Profile power.
## Reapplying must not refill instances, heal, or compound derived values.
func _apply_loadout() -> void:
	if Game.build != null:
		max_hp = Game.build.health()
		hp = minf(hp, max_hp)
		max_speed = float(Data.characters["square"]["speed"])
		jump_velocity = float(Data.characters["square"]["jump"])
		roll_iframe_end = BASE_ROLL_IFRAME_END
		crit_bonus = BASE_CRIT_BONUS
		armor_taken = 1.0 + Game.build.effect("damage_taken")
		armor_hp = 0.0
		character_id = "square"
		passive_id = "none"
		echo_every = 0
		perfect_dodge_scale = 1.0
		aegis_cooldown_scale = 1.0
		_select_weapon(weapon_slot)
		_sync_skills()
		return
	# Idempotent on purpose: armour, skill nodes and the passive all ADD to
	# these, so without the reset a second call would compound every one of
	# them. Nothing here may use `+=` without a matching default above.
	roll_iframe_end = BASE_ROLL_IFRAME_END
	crit_bonus = BASE_CRIT_BONUS
	armor_taken = 1.0
	aegis_cooldown_scale = 1.0
	perfect_dodge_scale = 1.0
	echo_every = 0

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


## Called by Hitbox when this player's hit crits. HUNTER turns crits into
## knife economy; every other passive ignores it.
func on_crit() -> void:
	if passive_id == "hunter":
		refund_knife()


## Routes use Scroll axes; only legacy fixtures add boons and Profile upgrades.
func attribute_level(colour: String) -> int:
	if Game.build != null:
		return int(Game.build.attributes.get(colour, 0))
	if colour.is_empty():
		return 0
	return int(Game.attr.get(colour, 0)) + int(Profile.bonus(colour))

func weapon_attr_level() -> int:
	return attribute_level(str(weapon.get("attribute", "")))


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

	# Echo needs a second box: a Hitbox clears its hit list only in enable(), so
	# re-opening the same box inside one swing would be swallowed as a duplicate.
	echo_box = Hitbox.new()
	echo_box.name = "EchoBox"
	echo_box.collision_mask = Layers.ENEMY
	var echo_shape := CollisionShape2D.new()
	echo_shape.name = "Shape"
	echo_shape.shape = RectangleShape2D.new()
	echo_box.add_child(echo_shape)
	add_child(echo_box)

	visual = PlayerVisual.new()
	visual.name = "Visual"
	add_child(visual)

	camera = PlayerCamera.new()
	camera.name = "Camera"
	add_child(camera)
	camera.make_current()


func suppress_actions() -> void:
	_action_lock = 0.12
	jump_buffer = 0.0
	guard_t = 0.0
	aegis_t = 0.0
	_cancel_swing()
	if state == State.ATTACK:
		set_state(State.IDLE)


func _action_pressed(action: String) -> bool:
	return _action_lock <= 0.0 and Input.is_action_just_pressed(action)


func _physics_process(delta: float) -> void:
	_action_lock = maxf(0.0, _action_lock - delta)
	if state == State.DEAD:
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		velocity.y = minf(velocity.y + gravity_fall * delta, max_fall_speed)
		move_and_slide()
		return

	if Game.build != null:
		Game.build.tick(delta)
		_sync_skills()
	guard_t = maxf(0, guard_t - delta)
	_tick_timers(delta)
	if drop_through_t > 0.0:
		drop_through_t = maxf(0.0, drop_through_t - delta)
		if drop_through_t == 0.0:
			set_collision_mask_value(4, true)

	if _action_pressed("weapon_two") and state not in [State.HURT, State.ROLL, State.ATTACK]:
		_use_weapon(1)
	if _action_pressed("throw") and state != State.HURT:
		_use_skill(2)
	if _action_pressed("aegis") and state != State.HURT:
		_use_skill(3)

	var dir := Input.get_axis("move_left", "move_right")
	if _traversal_step(dir, delta):
		return
	if _action_pressed("jump") and Input.is_action_pressed("drop") and is_on_floor():
		# Layer 4 is the one-way deck only; solid world collision remains active.
		set_collision_mask_value(4, false)
		drop_through_t = 0.18
		velocity.y = 120.0
		jump_buffer = 0.0
	elif _action_pressed("jump"):
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


func relocate(at: Vector2) -> void:
	_climb_vine = Rect2()
	_wall_jump_t = 0.0
	jump_buffer = 0.0
	coyote = 0.0
	drop_through_t = 0.0
	set_collision_mask_value(4, true)
	velocity = Vector2.ZERO
	if state not in [State.DEAD, State.HURT]:
		set_state(State.AIR)
	suppress_actions()
	global_position = at
	reset_physics_interpolation()
	if is_instance_valid(camera):
		camera.global_position = at
		camera.reset_physics_interpolation()


func _space_jump() -> bool:
	return _action_pressed("jump") and (Input.is_action_pressed("jump_explicit") or not Input.is_action_pressed("climb_up"))


func _traversal_step(dir: float, delta: float) -> bool:
	if state in [State.CLIMB, State.DIVE] and _action_pressed("roll") and _can_roll() and roll_cd <= 0:
		_start_roll(dir)
		return false
	if not is_instance_valid(traversal_world) or Game.run_phase != "biome" or state in [State.HURT, State.ROLL, State.ATTACK]:
		_climb_vine = Rect2()
		if state in [State.CLIMB, State.DIVE]:
			set_state(State.AIR)
		return false
	if _space_jump() and Input.is_action_pressed("drop") and not is_on_floor():
		_cancel_swing()
		_climb_vine = Rect2()
		jump_buffer = 0.0
		set_state(State.DIVE)
	if state == State.DIVE:
		velocity.x = move_toward(velocity.x, dir * max_speed, air_accel * delta)
		velocity.y = float(Data.traversal["dive_speed"])
		var speed := velocity.y
		move_and_slide()
		if is_on_floor():
			var broken := false
			for n in get_slide_collision_count():
				var contact := get_slide_collision(n)
				var collider := contact.get_collider()
				if contact.get_normal().y < -0.5 and collider != null and collider.has_method("try_break"):
					broken = collider.try_break(self) or broken
			if not broken:
				set_state(State.IDLE)
		_post_move(speed, delta)
		return true
	var climb_axis := Input.get_axis("climb_up", "climb_down")
	if not _climb_vine.has_area() and absf(climb_axis) > 0 and Profile.unlocked_runes.has("canopy_rune"):
		_climb_vine = traversal_world.vine_at(global_position, climb_axis > 0)
	if _climb_vine.has_area():
		if _space_jump():
			_climb_vine = Rect2()
			_jump(false)
			velocity.x = dir * max_speed
			return false
		if not _climb_vine.grow(12).has_point(global_position):
			_climb_vine = Rect2()
			set_state(State.AIR)
			return false
		set_state(State.CLIMB)
		tumbling = false
		if climb_axis > 0:
			# Bypass intervening decks, then catch the vine's lower landing.
			var through_deck := global_position.y < _climb_vine.end.y - 48
			set_collision_mask_value(4, not through_deck)
			drop_through_t = 0.18 if through_deck else 0.0
		velocity = Vector2(clampf((_climb_vine.get_center().x - global_position.x) * 8.0, -120, 120), climb_axis * float(Data.traversal["climb_speed"]))
		move_and_slide()
		if climb_axis > 0 and is_on_floor():
			_climb_vine = Rect2()
			set_state(State.IDLE)
		elif climb_axis < 0 and global_position.y <= _climb_vine.position.y + 24:
			_climb_vine = Rect2()
			set_state(State.AIR)
		return true
	if is_on_wall() and Profile.unlocked_runes.has("climb_rune"):
		var normal := get_wall_normal()
		if _space_jump():
			_jump(false)
			velocity.x = normal.x * max_speed
			_wall_jump_t = float(Data.traversal["wall_jump_lock"])
			move_and_slide()
			return true
		if dir * normal.x < 0 and absf(climb_axis) > 0:
			set_state(State.CLIMB)
			velocity = Vector2(dir * max_speed, climb_axis * float(Data.traversal["climb_speed"]))
			move_and_slide()
			return true
		if velocity.y > 0 and dir * normal.x < 0:
			velocity.y = minf(velocity.y, float(Data.traversal["wall_slide_speed"]))
	if state == State.CLIMB:
		set_state(State.AIR)
	return false


func _tick_timers(delta: float) -> void:
	_wall_jump_t = maxf(0.0, _wall_jump_t - delta)
	invuln = maxf(0.0, invuln - delta)
	roll_iframe_t += delta
	roll_cd = maxf(0.0, roll_cd - delta)
	jump_buffer = maxf(0.0, jump_buffer - delta)
	flash = maxf(0.0, flash - delta)
	squash = move_toward(squash, 1.0, delta * 5.0)
	aegis_t = maxf(0.0, aegis_t - delta)
	aegis_cd = maxf(0.0, aegis_cd - delta)
	_tick_echo(delta)
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
	if Game.build == null and knife_charges < knife_max:
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
	if _wall_jump_t <= 0.0:
		velocity.x = move_toward(velocity.x, dir * max_speed, rate * delta)
	if absf(dir) > 0.01:
		facing = 1 if dir > 0.0 else -1

	if jump_buffer > 0.0 and coyote > 0.0:
		_jump(on_floor)

	if _action_lock <= 0.0 and Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut

	if _action_pressed("roll") and _can_roll() and roll_cd <= 0.0:
		_start_roll(dir)
		return

	if _action_pressed("attack"):
		_use_weapon(0)
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

	if roll_t > roll_time * 0.55 and (_action_pressed("attack") or _action_pressed("weapon_two")):
		roll_cd = roll_cooldown
		set_state(State.AIR if not is_on_floor() else State.IDLE)
		_use_weapon(1 if _action_pressed("weapon_two") else 0)


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

	if _action_pressed("attack" if weapon_slot == 0 else "weapon_two") and attack_index < weapon_combo.size() - 1:
		attack_queued = true

	var cancel_at := float(attack_cfg.get("cancel_at", 0.6))
	if _action_pressed("roll") and _can_roll() and roll_cd <= 0.0 and attack_t >= attack_total * cancel_at:
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
	if on_floor:
		_air_roll_used = false
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
	if not is_on_floor():
		_air_roll_used = true
	_climb_vine = Rect2()
	if absf(dir) > 0.01:
		facing = 1 if dir > 0.0 else -1
	_cancel_swing()
	roll_t = 0.0
	roll_iframe_t = 0.0
	_trail_t = 0.0
	velocity.x = facing * roll_speed
	velocity.y = 0.0
	squash = 0.82
	set_state(State.ROLL)
	Sfx.play("roll", -13, randf_range(0.95, 1.05))
	Juice.dust(get_parent(), global_position + Vector2(0, 22), signf(velocity.x), 0.8)


func _can_roll() -> bool:
	return is_on_floor() or not _air_roll_used


func _select_weapon(slot: int) -> void:
	if Game.build == null:
		return
	weapon_slot = slot
	var item := Game.build.slots[slot]
	var cfg := Game.build.definition(item)
	weapon = Data.weapons.get(str(cfg.get("weapon", "")), {}).duplicate(true)
	weapon["attribute"] = cfg.get("attribute", "")
	weapon_combo = weapon.get("combo", [])
	permanent_damage_mult = Game.build.power(item)
	if is_instance_valid(visual) and is_instance_valid(visual.weapon_visual):
		visual.weapon_visual.setup(str(item["id"]))


func _use_weapon(slot: int) -> void:
	if Game.build == null:
		if slot == 0:
			_start_attack(0)
		return
	_select_weapon(slot)
	var item := Game.build.slots[slot]
	var cfg := Game.build.definition(item)
	if cfg["action"] == "melee":
		_start_attack(0)
	elif Game.build.use(slot):
		guard_item = item
		guard_t = float(cfg["duration"])
		Combat.ring(global_position, MathArt.PICKUP, 26)


func _use_skill(slot: int) -> void:
	var action := "kunai" if slot == 2 else "aegis"
	if Game.build != null:
		action = str(Game.build.definition(Game.build.slots[slot])["action"])
	if action == "kunai":
		_throw_knife(slot)
	elif action == "aegis":
		_cast_aegis(slot)


func _sync_skills() -> void:
	if Game.build == null:
		return
	knife_max = 0
	knife_charges = 0
	aegis_cd = 0
	for item in Game.build.slots:
		var cfg := Game.build.definition(item)
		if cfg.get("action") == "kunai":
			knife_max += int(cfg["charges"])
			knife_charges += int(item["charges"])
			knife_regen_time = Game.build.cooldown(item)
		elif cfg.get("action") == "aegis":
			aegis_cd = float(item["cooldown"])


func _counter(item: Dictionary) -> void:
	if Game.build == null or item.is_empty():
		return
	var cfg := Game.build.definition(item)
	var point := global_position + Vector2(facing * 14, -8)
	Combat.block_number(global_position + Vector2(0, -50))
	Combat.impact(point, Vector2(facing, 0), 1)
	Juice.block(get_parent(), point, facing)
	Sfx.play("block", -6)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy._dead and global_position.distance_to(enemy.global_position) <= float(cfg["radius"]):
			enemy.take_hit({"damage":Damage.compute(float(cfg["damage"]) * Game.build.power(item) * Game.total_damage_mult(), Game.build.level(item), false, 1), "source_pos":global_position, "point":enemy.global_position, "knockback":260, "tier":1, "status":str(Data.gear["affixes"][item["affix"]].get("status", "")), "status_attr":Game.build.level(item)})


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
	hitbox.attr = weapon_attr_level()
	hitbox.status_id = str(Data.gear["affixes"][Game.build.slots[weapon_slot]["affix"]].get("status", "")) if Game.build != null else ""
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
		MathArt.PICKUP,
		blade
	)
	if attack_index == weapon_combo.size() - 1 and not weapon_combo.is_empty():
		var wave := FunctionWave.new()
		wave.position = global_position + Vector2(facing * 26.0, -18.0)
		wave.attr = weapon_attr_level()
		wave.status_id = hitbox.status_id
		# The wave used to carry a literal 8.0, so a Fractal Edge finisher released
		# the same wave as a Rusty Sword. It is content: data/weapons.json.
		wave.setup(facing, float(weapon.get("wave_damage", 8.0)) * Game.total_damage_mult() * permanent_damage_mult,
			MathArt.TACTICS, self, crit_multiplier())
		var root := Game.fx_root
		if is_instance_valid(root):
			root.add_child(wave)

	_swing_count += 1
	if echo_every > 0 and _swing_count % echo_every == 0:
		_echo_t = 0.0
		_echo_cfg = {
			"size": size,
			"offset": offset,
			"damage": float(attack_cfg.get("damage", 10.0)) * ECHO_SCALE,
			"knockback": float(attack_cfg.get("knockback", 180.0)) * 0.5,
			"hitstop": float(attack_cfg.get("hitstop", 0.05)) * 0.5,
			"tier": int(attack_cfg.get("tier", 0)),
		}


func take_hit(info: Dictionary) -> void:
	if state == State.DEAD:
		return
	# Reward only the roll window: rolling out of a hit's
	# 0.55 s tail paid EDGE + a knife + an announce for a hit that was stopped by
	# hurt frames, not by the dodge. And the window now runs past roll_time (up to
	# 0.43 s with armour + GHOST + GLASS), so the state check had to go too.
	if is_roll_invulnerable():
		Game.perfect_dodge()
		return
	if invuln > 0.0:
		return
	var source_pos: Vector2 = info.get("source_pos", global_position)
	if guard_t > 0 and (source_pos.x - global_position.x) * facing >= 0:
		guard_t = 0
		_counter(guard_item)
		return
	if aegis_t > 0.0:
		_aegis_block()
		return
	var damage := float(info.get("damage", 1)) * armor_taken
	var lost := minf(hp, damage)
	hp = maxf(0.0, hp - damage)
	Game.note_damage_taken(lost)
	invuln = invuln_time
	flash = 0.14
	squash = 1.24
	hurt_t = hurt_time
	guard_t = 0.0
	_cancel_swing()

	var dir := signf(global_position.x - source_pos.x)
	if dir == 0.0:
		dir = -facing
	velocity = Vector2(dir * hurt_knockback, -150.0)
	set_state(State.HURT)

	# Feedback scales with what was taken. A spitter glob (6) and the Warden's
	# cleave (18) used to land as the same fixed 0.09 s freeze and 0.6 shake,
	# so the fight never told the player which hit had just happened. Every
	# value here stays inside the impact doc's ceilings: the freeze tops out at
	# 0.12 s and the flash never exceeds the 12% play-area budget.
	var weight := clampf(damage / 20.0, 0.0, 1.0)
	Combat.hitstop(0.06 + 0.06 * weight)
	Combat.shake(0.34 + 0.48 * weight)
	Combat.damage_number(global_position + Vector2(0, -46), int(damage), false)
	# The spark belongs at the contact EDGE, not on the body centre: a hit that
	# explodes in the middle of the square reads as the square hurting itself.
	var contact := global_position + Vector2(-dir * 14.0, -8.0)
	Combat.spark(contact, Vector2(dir, 0), false, MathArt.FIRE)
	Combat.hurt_burst(contact, int(dir))
	Juice.hit_sparks(get_parent(), contact, Vector2(dir, 0), 1.2)
	if weight > 0.6:
		# Only a genuinely heavy hit punches the frame; a chip hit must never
		# take the player's eyes off the telegraph that is still coming.
		Combat.screen_punch(0.5 * weight)
		Combat.ring(global_position + Vector2(0, -12), MathArt.DANGER, 40.0)
	Sfx.play("hurt", -6)
	Game.hurt_flash = 0.22 + 0.20 * weight
	Game.combo_break()

	if hp <= 0.0:
		_die()


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)
	Juice.pickup(get_parent(), global_position + Vector2(0, -10), MathArt.HEAL)


## The roll's own window, measured from the start of the roll and independent of
## the ROLL state: an i-frame window longer than the roll (armour + GHOST +
## GLASS reach 0.43 s against a 0.30 s roll) is still a dodge, and it still has
## to pay.
func is_roll_invulnerable() -> bool:
	return roll_iframe_t >= roll_iframe_start and roll_iframe_t <= roll_iframe_end


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
	if Game.build != null:
		for item in Game.build.slots:
			var cfg := Game.build.definition(item)
			if cfg.get("action") == "kunai":
				item["charges"] = mini(int(cfg["charges"]), int(item["charges"]) + 1)
				break
		_sync_skills()
		return
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


func _throw_knife(slot := 2) -> void:
	if not is_instance_valid(Game.fx_root):
		return
	var item: Dictionary = {}
	if Game.build != null:
		item = Game.build.slots[slot]
		if not Game.build.use(slot):
			return
	elif knife_charges <= 0:
		Sfx.play("ui", -20, 1.4)
		return
	else:
		knife_charges -= 1
	var spawn := global_position + Vector2(float(facing) * 8.0, -16.0)
	var target := _nearest_enemy(540.0)
	var aim_point := spawn + Vector2(float(facing) * 360.0, -70.0)
	if target != null:
		aim_point = target.global_position + Vector2(0, -16)
	var speed := float(Game.build.definition(item)["speed"]) if Game.build != null else knife_speed
	var velocity := MathArt.ballistic_velocity(spawn, aim_point, speed, Projectile.KUNAI_GRAVITY)
	var projectile := Projectile.new()
	projectile.position = spawn
	# A kunai is a tactics weapon whatever the blade is.
	projectile.attr = attribute_level("tactics")
	projectile.setup_player(
		velocity,
		knife_damage * Game.total_damage_mult() * permanent_damage_mult,
		MathArt.TACTICS,
		self,
		crit_multiplier()
	)
	if Game.build != null:
		projectile.damage = float(Game.build.definition(item)["damage"]) * Game.build.power(item) * Game.total_damage_mult()
		projectile.attr = Game.build.level(item)
		projectile.crit_mult = float(Game.build.definition(item).get("crit_multiplier", 1.5))
		projectile.status_id = str(Data.gear["affixes"][item["affix"]].get("status", ""))
	var root: Node = Game.fx_root
	if is_instance_valid(root):
		root.add_child(projectile)
	Combat.parabola_preview(spawn, velocity, Projectile.KUNAI_GRAVITY)
	Combat.burst(spawn, 4)
	Sfx.play("throw", -9, randf_range(0.95, 1.05))


func _cast_aegis(slot := 3) -> void:
	if Game.build != null:
		if not Game.build.use(slot):
			return
		aegis_item = Game.build.slots[slot]
		aegis_t = float(Game.build.definition(aegis_item)["duration"])
	elif aegis_cd > 0.0 or state == State.DEAD:
		return
	else:
		aegis_t = aegis_time
		aegis_cd = aegis_time + aegis_cooldown * aegis_cooldown_scale
	Combat.ring(global_position + Vector2(0, -6), MathArt.PICKUP, 52.0)
	Combat.burst(global_position + Vector2(0, -8), 10)
	Sfx.play("dodge", -10, 0.8)


func _aegis_block() -> void:
	if Game.build != null:
		aegis_t = 0.0
		_counter(aegis_item)
		return
	aegis_t = 0.0
	Combat.block_number(global_position + Vector2(0, -50))
	var block_point := global_position + Vector2(float(facing) * 14.0, -8.0)
	Combat.spark(block_point, Vector2(float(facing), 0.0), false, MathArt.FIRE)
	Combat.block_burst(block_point, facing)
	Combat.impact(block_point, Vector2(float(facing), 0.0), 1, MathArt.FIRE)
	Combat.ring(global_position + Vector2(0, -8), MathArt.PICKUP, 46.0)
	Juice.block(get_parent(), block_point, facing)
	Combat.shake(0.22)
	Sfx.play("block", -6, 1.1)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy._dead:
			continue
		if global_position.distance_to(enemy.global_position) <= 118.0:
			enemy.take_hit({
				# The Aegis counter is a tactics strike, not an untyped one: passing
				# 0 here was the exact "attribute is a label" bug the colour system
				# was built to remove.
				"damage": Damage.compute(10.0 * Game.total_damage_mult() * permanent_damage_mult,
					attribute_level("tactics"), false, 1.0),
				"crit": false,
				"knockback": 260.0,
				"hitstop": 0.03,
				"source_pos": global_position,
				"point": enemy.global_position,
			})


## Arms, then fires, then closes the echo box. Driven by a timer rather than an
## await so a freed player can never resume into a dead tree.
func _tick_echo(delta: float) -> void:
	if _echo_t < 0.0:
		return
	_echo_t += delta
	if _echo_t >= ECHO_DELAY and not echo_box.active:
		echo_box.shape_node.position = Vector2(facing * float(_echo_cfg["offset"][0]), float(_echo_cfg["offset"][1]))
		var rect := echo_box.shape_node.shape as RectangleShape2D
		rect.size = Vector2(float(_echo_cfg["size"][0]), float(_echo_cfg["size"][1]))
		echo_box.attr = weapon_attr_level()
		echo_box.enable(
			float(_echo_cfg["damage"]) * Game.total_damage_mult() * permanent_damage_mult,
			float(_echo_cfg["knockback"]),
			float(_echo_cfg["hitstop"]),
			self,
			crit_multiplier(),
			int(_echo_cfg["tier"])
		)
	elif echo_box.active and _echo_t >= ECHO_DELAY + ECHO_ACTIVE:
		echo_box.disable()
		_echo_t = -1.0


## Interrupting the swing (roll, hurt, death) must also drop a queued echo.
func _cancel_swing() -> void:
	hitbox.disable()
	_echo_t = -1.0
	if echo_box != null:
		echo_box.disable()


func set_state(next: State) -> void:
	if state == next:
		return
	state = next


func _die() -> void:
	set_state(State.DEAD)
	_cancel_swing()
	velocity = Vector2(-facing * 140.0, -300.0)
	Combat.burst(global_position + Vector2(0, -16), 20)
	Juice.shatter(get_parent(), global_position + Vector2(0, -14), MathArt.PLAYER, 18)
	Combat.shake(0.85)
	Sfx.play("death", -5)
	Game.end_run(false)
	died.emit()
