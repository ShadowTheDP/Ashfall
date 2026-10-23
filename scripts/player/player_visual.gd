class_name PlayerVisual
extends Node2D
## Procedural character art. No sprite assets: silhouette, scarf and sword are
## drawn so the whole prototype stays license-clean and instantly tweakable.

const CLOAK := Color("#2b3d50")
const CLOAK_DARK := Color("#1a2734")
const CLOAK_LIGHT := Color("#3d5873")
const TRIM := Color("#e8a33d")
const TRIM_DIM := Color("#8a5a1f")
const MASK := Color("#e9e2d2")
const EYE := Color("#8fe3ff")
const STEEL := Color("#c6d4e2")
const STEEL_DARK := Color("#7c8fa3")
const GRIP := Color("#3a2a1a")

var p: Player
var _t := 0.0
var _shadow_y := 24.0
var _shadow_alpha := 0.0
var _shadow_scale := 1.0


func _ready() -> void:
	p = get_parent() as Player
	z_index = 2


func _process(delta: float) -> void:
	_t += delta
	_update_shadow()
	queue_redraw()


func _update_shadow() -> void:
	_shadow_alpha = 0.0
	if p == null or p.state == Player.State.DEAD:
		return
	var query := PhysicsRayQueryParameters2D.create(
		p.global_position,
		p.global_position + Vector2(0, 600),
		Layers.WORLD
	)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var distance: float = hit["position"].y - p.global_position.y
	_shadow_y = distance - 2.0
	var falloff := clampf(1.0 - maxf(0.0, distance - 26.0) / 260.0, 0.0, 1.0)
	_shadow_alpha = 0.10 + 0.30 * falloff
	_shadow_scale = 0.45 + 0.55 * falloff


func _draw() -> void:
	if p == null:
		return
	if _shadow_alpha > 0.0:
		draw_set_transform(Vector2(0, _shadow_y), 0.0, Vector2(_shadow_scale, 0.22))
		draw_circle(Vector2.ZERO, 17.0, Color(0, 0, 0, _shadow_alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if p.state == Player.State.DEAD:
		_draw_dead()
		return

	var alpha := 1.0
	if p.invuln > 0.0 and fmod(_t * 26.0, 2.0) < 0.85:
		alpha = 0.38

	if p.state == Player.State.ROLL:
		_draw_roll(alpha)
		return

	var speed_ratio := clampf(absf(p.velocity.x) / p.max_speed, 0.0, 1.0)
	var air := not p.is_on_floor()
	var bob := 0.0
	if p.state == Player.State.IDLE:
		bob = sin(_t * 2.4) * 1.1
	elif p.state == Player.State.RUN:
		bob = sin(_t * 15.0) * 1.4 * speed_ratio
	var lean := 0.0
	if p.state == Player.State.RUN:
		lean = 0.14 * speed_ratio
	elif p.state == Player.State.ATTACK:
		lean = 0.10
	var squash_x := 1.0 + (p.squash - 1.0) * 0.45
	var squash_y := 1.0 - (p.squash - 1.0) * 0.35
	draw_set_transform(
		Vector2(0, bob),
		lean * float(p.facing),
		Vector2(float(p.facing) * squash_x, squash_y)
	)

	_draw_scarf(alpha, speed_ratio, air)
	_draw_legs(alpha, speed_ratio, air)
	_draw_body(alpha)
	_draw_head(alpha)
	_draw_sword_arm(alpha)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _tint(color: Color, alpha: float) -> Color:
	var out := Color(1, 1, 1, 1) if p.flash > 0.0 else color
	out.a *= alpha
	return out


func _draw_scarf(alpha: float, speed_ratio: float, air: bool) -> void:
	var wave := sin(_t * 8.5) * 2.4 + speed_ratio * 4.2
	var lift := 4.0 if air else 0.0
	var base := Vector2(-5, -13)
	var mid := base + Vector2(-12.0, wave * 0.5 - 1.5)
	var tip := base + Vector2(-24.0 - speed_ratio * 5.0, wave + lift)
	var ribbon := PackedVector2Array([
		base + Vector2(0, -2.8),
		mid + Vector2(0, -2.2),
		tip + Vector2(0, -0.7),
		tip + Vector2(0, 0.7),
		mid + Vector2(0, 2.2),
		base + Vector2(0, 2.8),
	])
	draw_colored_polygon(ribbon, _tint(TRIM, alpha * 0.92))
	draw_polyline(PackedVector2Array([base, mid, tip]), _tint(TRIM_DIM, alpha * 0.75), 1.2, true)
	# A second, shorter tail reads as cloth rather than a single wing.
	var base2 := Vector2(-4, -11)
	var tip2 := base2 + Vector2(-16.0, wave * 0.75 + 3.0 + lift)
	var ribbon2 := PackedVector2Array([
		base2 + Vector2(0, -2.0),
		tip2 + Vector2(0, -0.6),
		tip2 + Vector2(0, 0.6),
		base2 + Vector2(0, 2.0),
	])
	draw_colored_polygon(ribbon2, _tint(CLOAK_LIGHT, alpha * 0.55))


func _draw_legs(alpha: float, speed_ratio: float, air: bool) -> void:
	var swing := 0.0
	if p.state == Player.State.RUN:
		swing = sin(_t * 15.0) * 7.5 * speed_ratio
	elif p.state == Player.State.IDLE:
		swing = 0.0
	var hip_l := Vector2(-4.5, 7)
	var hip_r := Vector2(4.5, 7)
	var foot_l := Vector2(-8.0 + swing, 22.0)
	var foot_r := Vector2(7.0 - swing, 22.0)
	if air:
		foot_l = Vector2(-10.0, 16.0)
		foot_r = Vector2(9.0, 19.0)
	draw_line(hip_l, foot_l, _tint(CLOAK_DARK, alpha), 6.0)
	draw_line(hip_r, foot_r, _tint(CLOAK_DARK, alpha), 6.0)
	draw_line(foot_l, foot_l + Vector2(-3.0, 2.0), _tint(STEEL_DARK, alpha), 3.0)
	draw_line(foot_r, foot_r + Vector2(3.0, 2.0), _tint(STEEL_DARK, alpha), 3.0)


func _draw_body(alpha: float) -> void:
	var torso := PackedVector2Array([
		Vector2(-8, -16), Vector2(8, -16), Vector2(10, 1),
		Vector2(6, 12), Vector2(-6, 12), Vector2(-10, 1),
	])
	draw_colored_polygon(torso, _tint(CLOAK, alpha))
	var cape := PackedVector2Array([
		Vector2(-8, -14), Vector2(-12, 2), Vector2(-9, 14),
		Vector2(-3, 8), Vector2(-4, -8),
	])
	draw_colored_polygon(cape, _tint(CLOAK_DARK, alpha * 0.95))
	draw_line(Vector2(-7, 4), Vector2(8, 3), _tint(TRIM_DIM, alpha), 3.0)
	draw_circle(Vector2(6, 3), 2.2, _tint(TRIM, alpha))
	draw_line(Vector2(1, -14), Vector2(4, -2), _tint(CLOAK_LIGHT, alpha), 2.0)
	draw_line(Vector2(-9, -10), Vector2(-6, 6), _tint(CLOAK_LIGHT, alpha * 0.7), 1.5)


func _draw_head(alpha: float) -> void:
	draw_circle(Vector2(2, -23), 8.2, _tint(CLOAK_DARK, alpha))
	draw_circle(Vector2(3, -22.5), 5.6, _tint(MASK, alpha))
	draw_line(Vector2(0.0, -24), Vector2(9.0, -22), _tint(Color("#242a33"), alpha), 1.6)
	draw_circle(Vector2(7.1, -22), 1.5, _tint(EYE, alpha))


func _draw_sword_arm(alpha: float) -> void:
	var hand := Vector2(8.0, -8.0)
	var angle := 0.55
	if p.state == Player.State.ATTACK:
		hand = Vector2(10.0, -12.0)
		angle = _attack_angle()
	elif p.state == Player.State.RUN:
		angle = 0.55 + sin(_t * 15.0) * 0.08
	else:
		angle = 0.55 + sin(_t * 2.4) * 0.04

	draw_line(Vector2(4, -13), hand, _tint(CLOAK_DARK, alpha), 5.0)
	draw_circle(hand, 2.6, _tint(MASK, alpha))

	var direction := Vector2.from_angle(angle)
	var side := direction.orthogonal()
	var blade_start := hand + direction * 5.0
	var blade_end := hand + direction * 30.0
	draw_line(blade_start, blade_end, _tint(STEEL, alpha), 3.0)
	draw_line(blade_start + side * 1.6, blade_end + side * 1.2, _tint(STEEL_DARK, alpha * 0.9), 1.0)
	draw_line(hand + side * 4.5, hand - side * 4.5, _tint(TRIM_DIM, alpha), 3.0)
	draw_line(hand - direction * 5.0, hand, _tint(GRIP, alpha), 3.0)


func _attack_angle() -> float:
	var progress := clampf(p.attack_t / maxf(p.attack_total, 0.001), 0.0, 1.0)
	var from_angle := -1.95
	var to_angle := 0.72
	match p.attack_index:
		1:
			from_angle = 0.85
			to_angle = -1.95
		2:
			from_angle = -2.85
			to_angle = 0.95
	var sweep_start := 0.20
	var sweep_end := 0.58
	if p.attack_index == 2:
		sweep_start = 0.26
		sweep_end = 0.62
	return lerpf(from_angle, to_angle, smoothstep(sweep_start, sweep_end, progress))


func _draw_roll(alpha: float) -> void:
	var k := clampf(p.roll_t / p.roll_time, 0.0, 1.0)
	draw_set_transform(
		Vector2(0, 2),
		-float(p.facing) * k * TAU * 1.1,
		Vector2(float(p.facing), 1.0)
	)
	draw_circle(Vector2.ZERO, 15.0, _tint(CLOAK, alpha))
	draw_circle(Vector2(3, -2), 8.0, _tint(MASK, alpha))
	draw_line(Vector2(-10, 6), Vector2(8, 6), _tint(TRIM, alpha), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in 3:
		var offset := Vector2(-p.facing * (18.0 + i * 6.0), -4.0 + i * 4.0)
		draw_line(offset, offset - Vector2(p.facing * 10.0, 0), _tint(CLOAK_LIGHT, alpha * 0.35), 1.5)


func _draw_dead() -> void:
	draw_set_transform(Vector2(0, 22), float(p.facing) * 1.4, Vector2.ONE)
	draw_rect(Rect2(-14, -8, 28, 10), CLOAK_DARK)
	draw_circle(Vector2(-17, -4), 6.5, MASK)
	draw_line(Vector2(-17, -4), Vector2(-11, -3), Color("#242a33"), 1.5)
	draw_line(Vector2(4, 2), Vector2(28, 6), STEEL_DARK, 2.5)
	draw_line(Vector2(4, 2), Vector2(28, 6), TRIM_DIM, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
