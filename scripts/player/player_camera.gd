class_name PlayerCamera
extends Camera2D
## Follows the player with a little look-ahead and trauma-based shake.

var trauma := 0.0
var trauma_decay := 1.9
var max_offset := Vector2(16.0, 11.0)
var max_roll := 0.03

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	zoom = Vector2(1.4, 1.4)
	position_smoothing_enabled = true
	position_smoothing_speed = 9.0
	limit_left = -150
	limit_right = 1600
	limit_top = -480
	limit_bottom = 110
	ignore_rotation = false


func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)


func _process(delta: float) -> void:
	var parent := get_parent() as Player
	var real_delta := clampf(delta / maxf(Engine.time_scale, 0.05), 0.0, 0.08)
	if parent != null:
		var target_x := float(parent.facing) * 24.0
		var target_y := clampf(parent.velocity.y * 0.05, -18.0, 26.0) - 6.0
		position.x = lerpf(position.x, target_x, 1.0 - exp(-6.0 * real_delta))
		position.y = lerpf(position.y, target_y, 1.0 - exp(-4.0 * real_delta))

	trauma = maxf(0.0, trauma - real_delta * trauma_decay)
	var amount := trauma * trauma
	offset = Vector2(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)
	) * max_offset * amount
	rotation = _rng.randf_range(-1.0, 1.0) * max_roll * amount
