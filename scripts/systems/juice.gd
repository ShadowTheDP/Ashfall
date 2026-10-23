class_name Juice
## Particle presets built on Godot's own CPUParticles2D.
##
## We do not simulate particles ourselves any more: the engine already has
## emission shapes, curves, damping, scale curves and one-shot bursts. This
## file only supplies the numbers and one shared runtime texture, so the
## project still ships zero image assets.
##
## Sizes and speeds are in 768x480 logical pixels.

static var _tex: Texture2D = null


static func square_texture() -> Texture2D:
	if _tex != null:
		return _tex
	# A 6x6 soft-edged white square, generated once at runtime.
	var size := 6
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var edge := minf(minf(float(x) + 0.5, float(size) - float(x) - 0.5), minf(float(y) + 0.5, float(size) - float(y) - 0.5))
			var alpha := clampf(edge / 1.5, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	_tex = ImageTexture.create_from_image(image)
	return _tex


static func make(count: int, lifetime: float, tint: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = square_texture()
	p.amount = maxi(1, count)
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.92
	p.randomness = 0.55
	p.emitting = false
	p.local_coords = false
	p.z_index = 6
	p.color = tint
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	return p


static func _finish(p: CPUParticles2D, duration: float) -> CPUParticles2D:
	# The node frees itself once the last particle has died.
	p.finished.connect(p.queue_free)
	p.emitting = true
	return p


# --- World events -----------------------------------------------------------

static func dust(host: Node, at: Vector2, direction: float, strength: float = 1.0) -> void:
	var p := make(int(round(4.0 * strength)) + 3, 0.24, MathArt.with_alpha(MathArt.LIGHT, 0.55))
	p.position = at
	p.direction = Vector2(-direction * 0.4, -1.0)
	p.spread = 55.0
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 90.0 * strength
	p.gravity = Vector2(0, 240)
	p.damping_min = 40.0
	p.damping_max = 120.0
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.9
	host.add_child(_finish(p, 0.24))


static func land_dust(host: Node, at: Vector2, strength: float = 1.0) -> void:
	var p := make(int(round(9.0 * strength)) + 4, 0.3, MathArt.with_alpha(MathArt.LIGHT, 0.6))
	p.position = at
	p.direction = Vector2(0, -1)
	p.spread = 78.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 175.0 * strength
	p.gravity = Vector2(0, 420)
	p.damping_min = 90.0
	p.damping_max = 200.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.6
	host.add_child(_finish(p, 0.3))


static func jump_burst(host: Node, at: Vector2) -> void:
	var p := make(7, 0.22, MathArt.with_alpha(MathArt.LIGHT, 0.55))
	p.position = at
	p.direction = Vector2(0, -1)
	p.spread = 40.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 115.0
	p.gravity = Vector2(0, 380)
	p.scale_amount_min = 0.35
	p.scale_amount_max = 1.0
	host.add_child(_finish(p, 0.22))


static func hit_sparks(host: Node, at: Vector2, direction: Vector2, strength: float = 1.0) -> void:
	var p := make(int(round(8.0 * strength)) + 2, 0.16, MathArt.WHITE)
	p.position = at
	p.direction = direction.normalized()
	p.spread = 42.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 270.0 * strength
	p.gravity = Vector2(0, 190)
	p.damping_min = 120.0
	p.damping_max = 260.0
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.8
	host.add_child(_finish(p, 0.16))


static func shatter(host: Node, at: Vector2, tint: Color, count: int = 14) -> void:
	var p := make(count, 0.5, tint)
	p.position = at
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 70.0
	p.initial_velocity_max = 250.0
	p.gravity = Vector2(0, 520)
	p.damping_min = 20.0
	p.damping_max = 80.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.8
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	host.add_child(_finish(p, 0.5))


static func pickup(host: Node, at: Vector2) -> void:
	var p := make(6, 0.26, MathArt.WHITE)
	p.position = at
	p.direction = Vector2(0, -1)
	p.spread = 60.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 100.0
	p.gravity = Vector2(0, -90)
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.8
	host.add_child(_finish(p, 0.26))


static func block(host: Node, at: Vector2, facing: int) -> void:
	var p := make(9, 0.24, MathArt.WHITE)
	p.position = at
	p.direction = Vector2(float(facing), 0)
	p.spread = 70.0
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 210.0
	p.gravity = Vector2(0, 60)
	p.damping_min = 150.0
	p.damping_max = 300.0
	p.scale_amount_min = 0.3
	p.scale_amount_max = 1.0
	host.add_child(_finish(p, 0.24))


static func dodge(host: Node, at: Vector2) -> void:
	var p := make(10, 0.2, MathArt.WHITE)
	p.position = at
	p.direction = Vector2(0, 0)
	p.spread = 180.0
	p.initial_velocity_min = 100.0
	p.initial_velocity_max = 200.0
	p.gravity = Vector2.ZERO
	p.damping_min = 220.0
	p.damping_max = 380.0
	p.scale_amount_min = 0.3
	p.scale_amount_max = 1.1
	host.add_child(_finish(p, 0.2))


static func telegraph(host: Node, at: Vector2) -> void:
	# A short inward-sucking puff so a windup reads even with no colour.
	var p := make(5, 0.2, MathArt.with_alpha(MathArt.WHITE, 0.5))
	p.position = at
	p.direction = Vector2(0, 0)
	p.spread = 180.0
	p.initial_velocity_min = -90.0
	p.initial_velocity_max = -40.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	host.add_child(_finish(p, 0.2))
