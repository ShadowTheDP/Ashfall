class_name CellPickup
extends Area2D
## Currency drop. Magnets toward the player once close.

var value := 1
var _t := 0.0
var _velocity := Vector2(randf_range(-70.0, 70.0), -180.0)
var _collected := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitoring = true
	monitorable = false
	z_index = 4
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 11.0
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_t += delta
	if _collected:
		return
	if _t > 14.0:
		queue_free()
		return

	var player := Game.player
	if player != null and not Game.run_over:
		var target := player.global_position + Vector2(0, -10)
		var to_player := target - global_position
		var distance := to_player.length()
		if distance < 150.0:
			_velocity = _velocity.lerp(to_player.normalized() * 560.0, clampf(delta * 9.0, 0.0, 1.0))
		else:
			_velocity = _velocity.lerp(Vector2(0.0, 24.0), delta * 1.5)
		if distance < 20.0:
			_collect()
			return
	else:
		_velocity = _velocity.lerp(Vector2(0.0, 20.0), delta)

	global_position += _velocity * delta
	_velocity *= (1.0 - delta * 1.2)
	if _t < 0.35:
		_velocity.y -= 480.0 * delta
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if body is Player:
		_collect()


func _collect() -> void:
	if _collected:
		return
	_collected = true
	Game.add_cells(value)
	Sfx.play("pickup", -10)
	Combat.spark(global_position, Vector2.UP, false, Color("#e8a33d"))
	queue_free()


func _draw() -> void:
	var bob := sin(_t * 7.0) * 2.0
	var pulse := 0.7 + 0.3 * sin(_t * 9.0)
	draw_set_transform(Vector2(0, bob), 0.0, Vector2.ONE)
	draw_circle(Vector2.ZERO, 9.0 * pulse, Color(0.91, 0.64, 0.24, 0.16))
	var diamond := PackedVector2Array([
		Vector2(0, -7), Vector2(5, 0), Vector2(0, 7), Vector2(-5, 0),
	])
	draw_colored_polygon(diamond, Color("#e8a33d"))
	var inner := PackedVector2Array([
		Vector2(0, -3.5), Vector2(2.5, 0), Vector2(0, 3.5), Vector2(-2.5, 0),
	])
	draw_colored_polygon(inner, Color("#fff2d6"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
