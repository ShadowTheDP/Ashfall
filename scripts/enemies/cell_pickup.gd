class_name CellPickup
extends Area2D
## Currency drop: a 3px rotating diamond with a pixel glint.

var value := 1
## A cache is placed, not dropped: it rests where the generator put it and never
## expires. A killed enemy's drop keeps the pop-up arc and the 14 s timeout.
var resting := false
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
	if _t > 14.0 and not resting:
		queue_free()
		return

	var player := Game.player
	if player != null and not Game.run_over:
		var target := player.global_position + Vector2(0, -8)
		var to_player := target - global_position
		var distance := to_player.length()
		if distance < 150.0:
			_velocity = _velocity.lerp(to_player.normalized() * 560.0, clampf(delta * 10.0, 0.0, 1.0))
			if randf() < delta * 14.0:
				Combat.burst(global_position, MathArt.WHITE, 1, 40.0)
		else:
			_velocity = _velocity.lerp(Vector2(0.0, 22.0), delta * 1.5)
		if distance < 16.0:
			_collect()
			return
	elif resting:
		_velocity = Vector2.ZERO
	else:
		_velocity = _velocity.lerp(Vector2(0.0, 18.0), delta)

	if resting:
		queue_redraw()
		return

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
	Combat.spark(global_position, Vector2.UP, false, MathArt.PALE_DIM)
	queue_free()


func _draw() -> void:
	var bob := roundf(sin(_t * 8.0) * 1.5)
	var pulse := 0.65 + 0.35 * sin(_t * 9.0)
	# Glow.
	MathArt.px_rect(self, Rect2(-4, -4 + bob, 9, 9), Color(MathArt.PALE_DIM, 0.10 * pulse))
	# Diamond.
	var points := PackedVector2Array([
		Vector2(0, -5 + bob), Vector2(4, bob), Vector2(0, 5 + bob), Vector2(-4, bob),
	])
	MathArt.px_poly(self, points, MathArt.PALE_DIM, MathArt.WHITE, 1.0)
	MathArt.px_rect(self, Rect2(-1, -2 + bob, 2, 3), MathArt.WHITE)
