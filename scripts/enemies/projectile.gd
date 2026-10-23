class_name Projectile
extends Area2D
## Simple aimed bolt used by the Watcher enemy.

var direction := Vector2.RIGHT
var speed := 320.0
var damage := 7.0
var knockback := 150.0
var tint := Color("#b76bd6")
var _t := 0.0
var _life := 2.6
var _trail: Array[Vector2] = []


func setup(aim: Vector2, p_speed: float, p_damage: float, p_tint: Color) -> void:
	direction = aim.normalized()
	speed = p_speed
	damage = p_damage
	tint = p_tint
	rotation = direction.angle()


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.WORLD | Layers.PLAYER
	monitoring = true
	monitorable = false
	z_index = 6
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 6.0
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	position += direction * speed * delta
	_trail.push_front(global_position)
	if _trail.size() > 6:
		_trail.pop_back()
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if body.has_method("take_hit"):
		body.take_hit({
			"damage": int(damage),
			"crit": false,
			"knockback": knockback,
			"hitstop": 0.05,
			"source_pos": global_position - direction * 20.0,
			"point": global_position,
		})
		Combat.spark(global_position, -direction, false, tint)
		queue_free()
		return
	Combat.burst(global_position, tint, 6, 120.0)
	queue_free()


func _draw() -> void:
	var local_previous := Vector2.ZERO
	var has_previous := false
	for index in _trail.size():
		var point := to_local(_trail[index])
		if has_previous:
			draw_line(local_previous, point, Color(tint, 0.30 * (1.0 - float(index) / 7.0)), 3.0)
		local_previous = point
		has_previous = true
	draw_circle(Vector2.ZERO, 5.0, Color(tint, 0.9))
	draw_circle(Vector2.ZERO, 9.0, Color(tint, 0.18))
	draw_line(Vector2(-6, 0), Vector2(4, 0), Color(1, 1, 1, 0.85), 1.4)
