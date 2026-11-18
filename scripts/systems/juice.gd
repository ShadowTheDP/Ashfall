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
static var _fade: Gradient = null


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
			image.set_pixel(x, y, Color(MathArt.WHITE, alpha))
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


static func _finish(p: CPUParticles2D) -> CPUParticles2D:
	# The node frees itself once the last particle has died.
	p.finished.connect(p.queue_free)
	p.emitting = true
	return p

static func fade_ramp() -> Gradient:
	# Hold full value, then die. A linear 1->0 ramp makes a short burst read as
	# "thin" for its whole life instead of bright and then gone.
	if _fade != null:
		return _fade
	_fade = Gradient.new()
	_fade.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	_fade.colors = PackedColorArray([MathArt.WHITE, Color(MathArt.WHITE, 0.9), Color(MathArt.WHITE, 0)])
	return _fade


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
	host.add_child(_finish(p))


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
	host.add_child(_finish(p))


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
	host.add_child(_finish(p))


static func hit_sparks(host: Node, at: Vector2, direction: Vector2, strength: float = 1.0) -> void:
	var p := make(int(round(8.0 * strength)) + 2, 0.16, MathArt.FIRE)
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
	host.add_child(_finish(p))


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
	host.add_child(_finish(p))


static func pickup(host: Node, at: Vector2, tint: Color = MathArt.PICKUP) -> void:
	var p := make(6, 0.26, tint)
	p.position = at
	p.direction = Vector2(0, -1)
	p.spread = 60.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 100.0
	p.gravity = Vector2(0, -90)
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.8
	host.add_child(_finish(p))


static func block(host: Node, at: Vector2, facing: int) -> void:
	var p := make(9, 0.24, MathArt.FIRE)
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
	host.add_child(_finish(p))


static func dodge(host: Node, at: Vector2) -> void:
	var p := make(10, 0.2, MathArt.PLAYER)
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
	host.add_child(_finish(p))


# --- Mathematical presets ----------------------------------------------------
# CPUParticles2D has no per-particle velocity array, so a *structured* burst is
# built from `emission_points` (the curve itself) plus a radial acceleration:
# each particle keeps the direction it spawned at, which is exactly the curve's
# direction for that index. randomness is pinned to 0 or the geometry shears.

static func _structured(host: Node, at: Vector2, points: PackedVector2Array,
		tint: Color, lifetime: float, accel: float) -> CPUParticles2D:
	var p := make(points.size(), lifetime, tint)
	p.position = at
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = points
	p.explosiveness = 1.0
	p.randomness = 0.0
	p.spread = 0.0
	p.direction = Vector2.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.0
	p.radial_accel_min = accel
	p.radial_accel_max = accel
	p.color_ramp = fade_ramp()
	p.z_index = 7
	host.add_child(_finish(p))
	return p


## Phyllotaxis burst: 22 shards leave on golden-angle directions, so the blast
## has visible spiral structure instead of a grey cloud.
static func prism_burst(host: Node, at: Vector2, tint: Color, count: int = 22,
		speed: float = 320.0) -> CPUParticles2D:
	var points := PackedVector2Array()
	for i in count:
		points.append(MathArt.phyllotaxis(i + 1, 2.4))
	var p := _structured(host, at, points, tint, 0.34, speed * 3.0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	p.angular_velocity_min = -420.0
	p.angular_velocity_max = 420.0
	return p


## Rose curve: emission points sit on r = R*cos(k*theta), so the petals are a
## real rose curve rather than N directions.
## shortcut: r = cos(k*theta) only closes with integer k, and gives k lobes for
## odd k / 2k for even k, so an exact 6 is not representable -- `petals` is
## halved to k=3 (a 3-lobe rose). Upgrade if a true 6-lobe rosette is required:
## use k=3 and mirror the sample set instead.
static func rose_bloom(host: Node, at: Vector2, tint: Color, petals: int = 6) -> CPUParticles2D:
	var k := float(petals) * 0.5 if petals % 2 == 0 else float(petals)
	var samples := maxi(petals * 8, 24)
	var points := PackedVector2Array()
	for i in samples:
		points.append(MathArt.rose(TAU * float(i) / float(samples), k, 22.0))
	var p := _structured(host, at, points, tint, 0.85, 320.0)
	p.scale_amount_min = 0.45
	p.scale_amount_max = 0.9
	p.angular_velocity_min = -90.0
	p.angular_velocity_max = 90.0
	return p


## Critical halo: 12 particles on an exact circle, identical speed, no spread.
## Uniformity is the whole point -- any randomness turns it back into sparks.
static func critical_halo(host: Node, at: Vector2, tint: Color) -> CPUParticles2D:
	var p := _structured(host, at, MathArt.ngon(12, 9.0), tint, 0.42, 900.0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 0.6
	p.z_index = 8
	return p


static func telegraph(host: Node, at: Vector2) -> void:
	# A short inward-sucking puff reinforces the hostile windup outline.
	var p := make(5, 0.2, MathArt.with_alpha(MathArt.DANGER, 0.5))
	p.position = at
	p.direction = Vector2(0, 0)
	p.spread = 180.0
	p.initial_velocity_min = -90.0
	p.initial_velocity_max = -40.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	host.add_child(_finish(p))


# --- Ambience and weight -----------------------------------------------------
# Added for the map / impact / hub pass. Everything here is additive: the
# presets above must keep their names and their behaviour, they are referenced
# from combat code.

## Slow rising embers. The hub's air has to move even when nothing happens.
static func ember_drift(host: Node, at: Vector2, tint: Color, count: int = 10,
		life: float = 2.6) -> CPUParticles2D:
	var p := make(count, life, MathArt.with_alpha(tint, 0.5))
	p.position = at
	p.direction = Vector2(0, -1)
	p.spread = 26.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 22.0
	p.gravity = Vector2(0, -10)
	p.tangential_accel_min = -22.0
	p.tangential_accel_max = 22.0
	p.damping_min = 2.0
	p.damping_max = 6.0
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	p.scale_amount_min = 0.22
	p.scale_amount_max = 0.5
	p.color_ramp = fade_ramp()
	p.z_index = 5
	host.add_child(_finish(p))
	return p


## A standing column of drifting motes, i.e. a light shaft with volume. The
## emission box is the shaft's footprint at the floor, so the particles read as
## dust caught in the beam rather than as a fire.
static func shaft_motes(host: Node, at: Vector2, half_width: float,
		tint: Color, count: int = 16, life: float = 3.2) -> CPUParticles2D:
	var p := make(count, life, MathArt.with_alpha(tint, 0.30))
	p.position = at
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(half_width, 6.0)
	p.direction = Vector2(0, -1)
	p.spread = 8.0
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 26.0
	p.gravity = Vector2(0, -4)
	p.tangential_accel_min = -16.0
	p.tangential_accel_max = 16.0
	p.damping_min = 1.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.18
	p.scale_amount_max = 0.42
	p.color_ramp = fade_ramp()
	p.z_index = 4
	# Permanent ambience: NOT one_shot, and never wired to _finish(), which is
	# what frees a node after one burst.
	p.one_shot = false
	p.explosiveness = 0.0
	p.emitting = true
	host.add_child(p)
	return p


## Floor debris thrown up by a body landing hard, drawn as rotating shards.
static func debris_poly(host: Node, at: Vector2, direction: float, tint: Color,
		count: int = 10, speed: float = 200.0) -> CPUParticles2D:
	var p := make(count, 0.55, tint)
	p.position = at
	p.direction = Vector2(signf(direction) * 0.35, -1.0)
	p.spread = 62.0
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 620)
	p.damping_min = 12.0
	p.damping_max = 60.0
	p.angular_velocity_min = -700.0
	p.angular_velocity_max = 700.0
	p.scale_amount_min = 0.35
	p.scale_amount_max = 1.1
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(9.0, 2.0)
	p.z_index = 6
	host.add_child(_finish(p))
	return p


## Inward collapse, then outward rejection: negative initial velocity with a
## large positive radial accel. That one inversion is what a kill needs to read
## as "taken apart" instead of "exploded".
static func kill_implosion(host: Node, at: Vector2, tint: Color, count: int = 14) -> CPUParticles2D:
	var p := make(count, 0.42, tint)
	p.position = at
	p.direction = Vector2.ZERO
	p.spread = 180.0
	p.initial_velocity_min = -190.0
	p.initial_velocity_max = -90.0
	p.radial_accel_min = 900.0
	p.radial_accel_max = 900.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.2
	p.angular_velocity_min = -300.0
	p.angular_velocity_max = 300.0
	p.color_ramp = fade_ramp()
	p.z_index = 7
	host.add_child(_finish(p))
	return p


## Directional streaks that leave the blade's line. Used for tier-3 so the
## finisher has motion the lighter tiers cannot fake.
static func speed_lines(host: Node, at: Vector2, direction: Vector2, tint: Color,
		count: int = 12, speed: float = 620.0) -> CPUParticles2D:
	var dir := direction.normalized() if direction.length() > 0.01 else Vector2.RIGHT
	var p := make(count, 0.18, tint)
	p.position = at
	p.direction = dir
	p.spread = 11.0
	p.initial_velocity_min = speed * 0.6
	p.initial_velocity_max = speed
	p.gravity = Vector2.ZERO
	p.damping_min = 260.0
	p.damping_max = 520.0
	p.scale_amount_min = 0.2
	p.scale_amount_max = 0.55
	p.color_ramp = fade_ramp()
	p.z_index = 8
	host.add_child(_finish(p))
	return p


## Aegis: the shell takes the blow. Emission points sit on the arc the shield
## actually covers, so the burst is directional information, not decoration.
static func block_shell(host: Node, at: Vector2, facing: int, tint: Color) -> CPUParticles2D:
	var points := PackedVector2Array()
	for i in 11:
		var angle := lerpf(-1.15, 1.15, float(i) / 10.0)
		points.append(Vector2.from_angle(angle) * 26.0)
	var p := _structured(host, at, points, tint, 0.26, 460.0)
	p.scale_amount_min = 0.45
	p.scale_amount_max = 0.45
	p.scale.x = float(facing)
	p.z_index = 8
	return p


## Boss wind-up ground crack: wide, slow, low. A heavy attack has to own the
## floor before it lands, or the player cannot read where it will go.
static func boss_slam(host: Node, at: Vector2, tint: Color, radius: float = 46.0) -> CPUParticles2D:
	var p := _structured(host, at, MathArt.ngon(16, radius), tint, 0.5, 260.0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.5
	p.angular_velocity_min = -60.0
	p.angular_velocity_max = 60.0
	p.z_index = 6
	return p
