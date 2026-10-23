class_name Projectile
extends Area2D
## Shared projectile for bolts, kunai and shockwaves.
## Kunai and arrows are true ballistic functions: p(t) = p0 + v0*t + 1/2*g*t^2.

const KUNAI_GRAVITY := 900.0

var direction := Vector2.RIGHT
var speed := 320.0
var damage := 7.0
var knockback := 150.0
var tint := Color("#b76bd6")
var source: Node2D = null
var crit_mult := 1.0
var spin := false
var ballistic := false
var gravity_accel := 0.0
var pierce := false
var visual := "bolt"
var ignore_world := false
var hitstop_time := 0.05

var _t := 0.0
var _life := 2.6
var _radius := 6.0
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
	_radius = 5.0
	_life = 1.1
	knockback = 160.0
	hitstop_time = 0.035
	z_index = 8


func setup_wave(aim: Vector2, p_speed: float, p_damage: float, p_tint: Color, p_source: Node2D) -> void:
	setup(aim, p_speed, p_damage, p_tint)
	source = p_source
	visual = "wave"
	ignore_world = true
	_radius = 20.0
	_life = 1.25
	knockback = 260.0
	hitstop_time = 0.02
	position.y = -18.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYER if ignore_world else (Layers.WORLD | Layers.PLAYER)
	if visual == "kunai":
		collision_mask = Layers.ENEMY | Layers.WORLD
	monitoring = true
	monitorable = false
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
		if _trail.size() > 7:
			_trail.pop_back()
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if body == source:
		return
	if pierce and _hit_bodies.has(body):
		return
	if body.has_method("take_hit"):
		if pierce:
			_hit_bodies.append(body)
		var crit := false
		if source != null and source.has_method("is_crit_against"):
			crit = source.is_crit_against(body)
		var final_damage := Damage.compute(damage, 0, crit, crit_mult)
		body.take_hit({
			"damage": final_damage,
			"crit": crit,
			"knockback": knockback,
			"hitstop": hitstop_time,
			"source_pos": global_position - direction * 20.0,
			"point": global_position,
		})
		Combat.spark(global_position, -direction, crit, tint)
		if not pierce:
			queue_free()
		return
	Combat.burst(global_position, tint, 6, 120.0)
	if not pierce:
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
	var previous := Vector2.ZERO
	var has_previous := false
	for index in _trail.size():
		var point := to_local(_trail[index])
		if has_previous:
			draw_line(previous, point, Color(tint, 0.30 * (1.0 - float(index) / 8.0)), 2.5)
		previous = point
		has_previous = true
	draw_circle(Vector2.ZERO, 5.0, Color(tint, 0.9))
	draw_circle(Vector2.ZERO, 9.0, Color(tint, 0.18))
	draw_line(Vector2(-6, 0), Vector2(4, 0), Color(1, 1, 1, 0.85), 1.4)


func _draw_kunai() -> void:
	for index in _trail.size():
		var point := to_local(_trail[index])
		draw_circle(point, 2.2 * (1.0 - float(index) / 8.0), Color(tint, 0.22))
	var blade := PackedVector2Array([
		Vector2(11, 0), Vector2(2, -4), Vector2(-3, 0), Vector2(2, 4),
	])
	MathArt.draw_poly(self, blade, Color(tint, 0.95), Color(1, 1, 1, 0.8), 1.0)
	draw_line(Vector2(-3, 0), Vector2(-9, 0), Color("#e8a33d"), 2.0)
	draw_circle(Vector2(-9, 0), 2.0, Color("#e8a33d"))
	draw_circle(Vector2.ZERO, 8.0, Color(tint, 0.10))


func _draw_wave() -> void:
	var phase := fmod(_t * 6.0, TAU)
	for ring in 3:
		var offset := phase * 0.4 + float(ring) * 0.6
		var alpha := 0.55 - float(ring) * 0.14
		var points := PackedVector2Array()
		for i in 9:
			var x := -24.0 + float(i) * 6.0
			var y := -sin(float(i) * 0.8 + offset) * (7.0 + float(ring) * 3.0)
			points.append(Vector2(x, y))
		for i in range(8, -1, -1):
			var x := -24.0 + float(i) * 6.0
			var y := -sin(float(i) * 0.8 + offset) * (7.0 + float(ring) * 3.0) + 5.0
			points.append(Vector2(x, y))
		MathArt.draw_poly(self, points, Color(tint, alpha * 0.35), Color(tint, alpha * 0.5), 1.0)
	draw_circle(Vector2.ZERO, 18.0, Color(tint, 0.10))
