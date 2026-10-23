class_name CellPickup
extends Area2D
## Currency drop: a 3px rotating diamond with a pixel glint.

var value := 1
var _t := 0.0
var _velocity := Vector2(randf_range(-60.0, 60.0), -170.0)
var _collected := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitoring = true
	monitorable = false
	z_index = 4
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 9.0
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
		var target := player.global_position + Vector2(0, -8)
		var to_player := target - global_position
		var distance := to_player.length()
		if distance < 130.0:
			_velocity = _velocity.lerp(to_player.normalized() * 520.0, clampf(delta * 10.0, 0.0, 1.0))
		else:
			_velocity = _velocity.lerp(Vector2(0.0, 22.0), delta * 1.5)
		if distance < 16.0:
			_collect()
			return
	else:
		_velocity = _velocity.lerp(Vector2(0.0, 18.0), delta)

	global_position += _velocity * delta
	_velocity *= (1.0 - delta * 1.2)
	if _t < 0.32:
		_velocity.y -= 460.0 * delta
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
	Combat.spark(global_position, Vector2.UP, false, MathArt.AMBER)
	queue_free()


func _draw() -> void:
	var bob := roundf(sin(_t * 8.0) * 1.5)
	var pulse := 0.65 + 0.35 * sin(_t * 9.0)
	# Glow.
	MathArt.px_rect(self, Rect2(-4, -4 + bob, 9, 9), Color(MathArt.AMBER, 0.10 * pulse))
	# Diamond.
	var points := PackedVector2Array([
		Vector2(0, -5 + bob), Vector2(4, bob), Vector2(0, 5 + bob), Vector2(-4, bob),
	])
	MathArt.px_poly(self, points, MathArt.AMBER, MathArt.AMBER_HI, 1.0)
	MathArt.px_rect(self, Rect2(-1, -2 + bob, 2, 3), MathArt.WHITE)
