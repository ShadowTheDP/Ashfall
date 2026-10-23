class_name PlayerCamera
extends Camera2D
## Smooth follow with look-ahead and trauma shake.
##
## Runs in _physics_process so the engine's physics interpolation carries the
## camera along with the player: no sub-frame jitter, no snapping.

var trauma := 0.0
var trauma_decay := 2.2
var max_offset := Vector2(11.0, 8.0)
var max_roll := 0.018

var _rng := RandomNumberGenerator.new()
var _look := Vector2.ZERO


func _ready() -> void:
	_rng.randomize()
	zoom = Vector2.ONE
	position_smoothing_enabled = false
	limit_left = -180
	limit_right = 1900
	limit_top = -560
	limit_bottom = 130


func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)


func _physics_process(delta: float) -> void:
	var parent := get_parent() as Player
	var real_delta := clampf(delta / maxf(Engine.time_scale, 0.05), 0.0, 0.05)

	if parent != null:
		var target_look := Vector2(float(parent.facing) * 26.0, clampf(parent.velocity.y * 0.05, -18.0, 24.0) - 6.0)
		_look = _look.lerp(target_look, 1.0 - exp(-6.0 * real_delta))
		global_position = parent.global_position + _look

	trauma = maxf(0.0, trauma - real_delta * trauma_decay)
	var amount := trauma * trauma
	offset = Vector2(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)
	) * max_offset * amount
	rotation = _rng.randf_range(-1.0, 1.0) * max_roll * amount
