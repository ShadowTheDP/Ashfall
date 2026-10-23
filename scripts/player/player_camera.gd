class_name PlayerCamera
extends Camera2D
## Follows the player with look-ahead and trauma shake.
##
## Pixel-art rules: zoom is 1.0 (one world unit = one pixel), the camera
## position is rounded every frame, and there is NO rotation. Sub-pixel camera
## motion or roll would shimmer the whole upscaled image.

var trauma := 0.0
var trauma_decay := 2.1
var max_offset := Vector2(9.0, 6.0)

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	zoom = Vector2.ONE
	position_smoothing_enabled = false
	ignore_rotation = true
	rotation = 0.0
	limit_left = -150
	limit_right = 1600
	limit_top = -470
	limit_bottom = 100


func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)


func _process(delta: float) -> void:
	var parent := get_parent() as Player
	var real_delta := clampf(delta / maxf(Engine.time_scale, 0.05), 0.0, 0.08)
	var target := Vector2.ZERO
	if parent != null:
		target.x = float(parent.facing) * 18.0
		target.y = clampf(parent.velocity.y * 0.045, -14.0, 20.0) - 4.0
	position = position.lerp(target, 1.0 - exp(-7.0 * real_delta))

	trauma = maxf(0.0, trauma - real_delta * trauma_decay)
	var amount := trauma * trauma
	var shake := Vector2(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)
	) * max_offset * amount
	offset = Vector2(roundf(shake.x), roundf(shake.y))
	rotation = 0.0
