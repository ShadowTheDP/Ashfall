class_name Projectile
extends Area2D
## Shared projectile for bolts, kunai and shockwaves.
## Kunai and arrows are true ballistic functions: p(t) = p0 + v0*t + 1/2*g*t^2.

const KUNAI_GRAVITY := 900.0

var direction := Vector2.RIGHT
var speed := 320.0
var damage := 7.0
var knockback := 150.0
var tint := MathArt.PALE
var source: Node2D = null
var crit_mult := 1.0
## Colour-scaling level, set by the owner before setup_player().
var attr := 0
var spin := false
var ballistic := false
var gravity_accel := 0.0
var visual := "bolt"
var ignore_world := false
var hitstop_time := 0.05

var _t := 0.0
var _life := 2.6
var _radius := 4.0
var _velocity := Vector2.ZERO
var _trail: Array[Vector2] = []
var _hit_bodies: Array[Node] = []


func setup(aim: Vector2, p_speed: float, p_damage: float, p_tint: Color) -> void:
	direction = aim.normalized()
	speed = p_speed
	damage = p_damage
	tint = p_tint
	rotation = direction.angle()


func setup_ballistic(velocity: Vector2, p_damage: float, p_tint: Color, p_source: Node2D, p_visual := "bolt") -> void:
	ballistic = true
	_velocity = velocity
	direction = velocity.normalized()
	speed = velocity.length()
	damage = p_damage
	tint = p_tint
	source = p_source
	visual = p_visual
	gravity_accel = 700.0
	_life = 2.2
	rotation = direction.angle()


func setup_player(velocity: Vector2, p_damage: float, p_tint: Color, p_source: Node2D, p_crit: float) -> void:
	setup_ballistic(velocity, p_damage, p_tint, p_source, "kunai")
	crit_mult = p_crit
	spin = true
	gravity_accel = KUNAI_GRAVITY
	_radius = 3.0
	_life = 1.1
	knockback = 160.0
	hitstop_time = 0.035
	z_index = 8


func setup_wave(aim: Vector2, p_speed: float, p_damage: float, p_tint: Color, p_source: Node2D) -> void:
	setup(aim, p_speed, p_damage, p_tint)
	source = p_source
	visual = "wave"
	ignore_world = true
	_radius = 14.0
	_life = 1.25
	knockback = 260.0
	hitstop_time = 0.02
	position.y = -16.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYER if ignore_world else (Layers.WORLD | Layers.PLAYER)
	if visual == "kunai":
		collision_mask = Layers.ENEMY | Layers.WORLD
	monitoring = true
	# `monitorable = false` also stopped this Area from registering body
	# overlaps in 4.7, so every arrow, glob and shockwave flew through walls
	# and players. Nothing needs the projectile to be un-monitorable: no other
	# area in the game has a mask that would pick it up.
	monitorable = true
	z_index = 8 if visual == "kunai" else 6
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = _radius
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		Combat.burst(global_position, MathArt.LIGHT, 4, 80.0)
		queue_free()
		return
	if ballistic:
		_velocity.y += gravity_accel * delta
		position += _velocity * delta
		if _velocity.length_squared() > 1.0:
			direction = _velocity.normalized()
	else:
		position += direction * speed * delta
	if spin:
		rotation += 22.0 * delta
	elif ballistic:
		rotation = direction.angle()
	if visual != "wave":
		_trail.push_front(global_position)
		if _trail.size() > 6:
			_trail.pop_back()
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if body == source:
		return
	if body.has_method("take_hit"):
		var crit := false
		if source != null and source.has_method("is_crit_against"):
			crit = source.is_crit_against(body)
		body.take_hit({
			"damage": Damage.compute(damage, attr, crit, crit_mult),
			"crit": crit,
			"knockback": knockback,
			"hitstop": hitstop_time,
			"source_pos": global_position - direction * 20.0,
			"point": global_position,
		})
		Combat.spark(global_position, -direction, crit, tint)
		queue_free()
		return
	Combat.burst(global_position, tint, 5, 110.0)
	queue_free()


func _draw() -> void:
	if visual == "wave":
		_draw_wave()
		return
	if visual == "kunai":
		_draw_kunai()
		return
	_draw_bolt()


func _draw_bolt() -> void:
	for index in _trail.size():
		var point := to_local(_trail[index])
		var alpha := 0.35 * (1.0 - float(index) / 7.0)
		MathArt.px_rect(self, Rect2(roundf(point.x), roundf(point.y), 1, 1), Color(tint, alpha))
	MathArt.px_rect(self, Rect2(-2, -2, 4, 4), Color(tint, 0.95))
	MathArt.px_rect(self, Rect2(-1, -1, 2, 2), Color(MathArt.WHITE, 0.9))


func _draw_kunai() -> void:
	for index in _trail.size():
		var point := to_local(_trail[index])
		MathArt.px_rect(self, Rect2(roundf(point.x), roundf(point.y), 1, 1), Color(tint, 0.30 * (1.0 - float(index) / 7.0)))
	# A 4px diamond blade on a 1px grip.
	MathArt.px_poly(self, PackedVector2Array([Vector2(6, 0), Vector2(0, -3), Vector2(-3, 0), Vector2(0, 3)]),
		Color(tint, 0.95), Color(MathArt.WHITE, 0.8), 1.0)
	MathArt.px_rect(self, Rect2(-6, -1, 4, 1), MathArt.PALE_DIM)
	MathArt.px_rect(self, Rect2(-7, -1, 1, 2), MathArt.MID_DIM)


func _draw_wave() -> void:
	var phase := fmod(_t * 7.0, TAU)
	for i in 16:
		var k := float(i) / 15.0
		var x := roundf(lerpf(-20.0, 20.0, k))
		var y := roundf(sin(k * TAU * 1.6 + phase) * 5.0)
		MathArt.px_rect(self, Rect2(x, y - 3, 1, 7), Color(tint, 0.45))
		MathArt.px_rect(self, Rect2(x, y - 1, 1, 2), Color(MathArt.WHITE, 0.5))
