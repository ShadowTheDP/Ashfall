class_name PlayerVisual
extends Node2D
## The player is drawn as a small set of mathematical primitives:
## a superellipse-derived torso, harmonic two-segment legs, a Lissajous scarf,
## a golden-ratio sword and a rotating hexagon for the roll. No sprite assets.

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
		draw_circle(Vector2.ZERO, 18.0, Color(0, 0, 0, _shadow_alpha))
		MathArt.draw_ring(self, Vector2.ZERO, 18.0, Color(0.91, 0.64, 0.24, _shadow_alpha * 0.25), 1.0, 32)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if p.state == Player.State.DEAD:
		_draw_dead()
		return

	var alpha := 1.0
	if p.invuln > 0.0 and fmod(_t * 26.0, 2.0) < 0.85:
		alpha = 0.38

	_draw_aegis(alpha)
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

	_draw_edge_aura(alpha)
	_draw_scarf(alpha, speed_ratio, air)
	_draw_leg(alpha, -1, speed_ratio, air)
	_draw_cape(alpha)
	_draw_torso(alpha)
	_draw_leg(alpha, 1, speed_ratio, air)
	_draw_head(alpha)
	_draw_arm(alpha, -1)
	_draw_sword_arm(alpha)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _tint(color: Color, alpha: float) -> Color:
	var out := Color(1, 1, 1, 1) if p.flash > 0.0 else color
	out.a *= alpha
	return out


func _draw_edge_aura(alpha: float) -> void:
	if Game.edge_timer <= 0.0:
		return
	var count := 5
	var rotation := _t * 2.4
	for i in count:
		var angle := rotation + TAU * float(i) / float(count)
		var point := Vector2.from_angle(angle) * 27.0
		draw_circle(point, 1.7, Color(EYE, alpha * 0.75))
	MathArt.draw_ring(self, Vector2.ZERO, 29.0, Color(EYE, alpha * 0.18), 1.0, 40)


func _draw_scarf(alpha: float, speed_ratio: float, air: bool) -> void:
	# Lissajous ribbon: x is the length axis, y is a 3:2 harmonic.
	var base := Vector2(-5, -13)
	var length := 23.0 + speed_ratio * 6.0
	var phase := _t * 8.5
	var lift := 4.0 if air else 0.0
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	var samples := 7
	for i in samples:
		var k := float(i) / float(samples - 1)
		var x := -length * k
		var y := sin(k * TAU * 1.5 + phase) * (2.2 + 3.2 * k) - lift * k
		var width := lerpf(3.0, 0.6, k)
		top.append(base + Vector2(x, y - width))
		bottom.append(base + Vector2(x, y + width))
	var ribbon := PackedVector2Array()
	ribbon.append_array(top)
	for i in range(bottom.size() - 1, -1, -1):
		ribbon.append(bottom[i])
	MathArt.draw_poly(self, ribbon, _tint(TRIM, alpha * 0.9), Color(TRIM_DIM, alpha * 0.4), 1.0)
	var centerline := PackedVector2Array()
	for i in samples:
		var k := float(i) / float(samples - 1)
		centerline.append(base + Vector2(-length * k, sin(k * TAU * 1.5 + phase) * (2.2 + 3.2 * k) - lift * k))
	draw_polyline(centerline, _tint(TRIM_DIM, alpha * 0.5), 1.0, true)

	# A second, shorter ribbon at 1/phi length.
	var short_length := length * MathArt.INV_PHI
	var short := PackedVector2Array([
		base + Vector2(0, -2),
		base + Vector2(-short_length * 0.5, sin(phase + 1.0) * 2.0 + 2.0),
		base + Vector2(-short_length, sin(phase + 2.2) * 3.0 + 4.0),
		base + Vector2(-short_length, sin(phase + 2.2) * 3.0 + 5.5),
		base + Vector2(-short_length * 0.5, sin(phase + 1.0) * 2.0 + 3.5),
		base + Vector2(0, 2),
	])
	MathArt.draw_poly(self, short, _tint(CLOAK_LIGHT, alpha * 0.55))


func _draw_leg(alpha: float, side: int, speed_ratio: float, air: bool) -> void:
	var hip := Vector2(4.5 * float(side), 7.0)
	var phase := _t * 15.0 + (0.0 if side > 0 else PI)
	var swing := sin(phase) * 8.0 * speed_ratio
	var knee := Vector2(4.5 * float(side) + swing * 0.45, 15.0)
	var foot := Vector2(4.5 * float(side) + swing, 23.0)
	if air:
		knee = Vector2(4.5 * float(side), 13.0)
		foot = Vector2(7.0 * float(side), 18.0)
	var dark := CLOAK_DARK if side > 0 else CLOAK_DARK.darkened(0.25)
	draw_line(hip, knee, _tint(dark, alpha), 5.0)
	draw_line(knee, foot, _tint(dark, alpha), 4.0)
	draw_circle(knee, 2.0, _tint(TRIM_DIM, alpha * 0.7))
	draw_line(foot, foot + Vector2(3.0 * float(side), 2.0), _tint(STEEL_DARK, alpha), 3.0)


func _draw_cape(alpha: float) -> void:
	var cape := PackedVector2Array([
		Vector2(-8, -14), Vector2(-13, 0), Vector2(-11, 14),
		Vector2(-6, 9), Vector2(-4, -6),
	])
	MathArt.draw_poly(self, cape, _tint(CLOAK_DARK, alpha * 0.95), Color(CLOAK_LIGHT, alpha * 0.25), 1.0)
	# Golden ratio seam on the cloak.
	draw_line(Vector2(-8, -12), Vector2(-9, 10), _tint(TRIM_DIM, alpha * 0.4), 1.0)


func _draw_torso(alpha: float) -> void:
	# A superellipse torso with a pentagonal belt line.
	var torso := MathArt.superellipse(10.0, 14.0, 2.6, 18, 0.0, Vector2(0, -2))
	var shifted := PackedVector2Array()
	for point in torso:
		shifted.append(point + Vector2(0, -2))
	MathArt.draw_poly(self, shifted, _tint(CLOAK, alpha), Color(CLOAK_LIGHT, alpha * 0.45), 1.0)
	draw_line(Vector2(-8, 4), Vector2(8, 3), _tint(TRIM_DIM, alpha), 3.0)
	draw_circle(Vector2(6.5, 3.2), 2.0, _tint(TRIM, alpha))
	draw_line(Vector2(1, -14), Vector2(4, -2), _tint(CLOAK_LIGHT, alpha), 1.6)
	# Defensive sigil: a small triangle at the chest.
	MathArt.draw_poly(self, MathArt.ngon(3, 4.2, -PI * 0.5, Vector2(0, -3)),
		Color(TRIM, alpha * 0.18), Color(TRIM, alpha * 0.55), 0.8)


func _draw_head(alpha: float) -> void:
	draw_circle(Vector2(2, -23), 8.2, _tint(CLOAK_DARK, alpha))
	MathArt.draw_ring(self, Vector2(2, -23), 10.0, Color(TRIM, alpha * 0.16), 1.0, 24, -2.4, 0.2)
	draw_circle(Vector2(3, -22.5), 5.6, _tint(MASK, alpha))
	draw_line(Vector2(0.0, -24), Vector2(9.0, -22), _tint(Color("#242a33"), alpha), 1.6)
	draw_circle(Vector2(7.2, -22), 1.5, _tint(EYE, alpha))
	# A short halo arc, aligned with the head's golden angle.
	draw_arc(Vector2(2, -23), 11.5, -2.2 + sin(_t) * 0.08, -1.0 + sin(_t) * 0.08, 10,
		Color(EYE, alpha * 0.18), 1.0, true)


func _draw_arm(alpha: float, side: int) -> void:
	if side > 0:
		return
	var shoulder := Vector2(-5, -13)
	var elbow := Vector2(-11, -4)
	var hand := Vector2(-9, 3)
	draw_line(shoulder, elbow, _tint(CLOAK_DARK, alpha), 4.0)
	draw_line(elbow, hand, _tint(CLOAK_DARK, alpha), 3.0)
	draw_circle(hand, 2.0, _tint(MASK, alpha * 0.8))


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
	var amplitude := 1.2 + (1.4 if p.state == Player.State.ATTACK else 0.0)
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	var samples := 9
	for i in samples:
		var k := float(i) / float(samples - 1)
		var along := 4.0 + 28.0 * k
		var wave := sin(k * TAU * 1.25 + _t * 6.0) * amplitude * k
		var half := lerpf(2.4, 0.7, k)
		top.append(hand + direction * along + side * (half + wave))
		bottom.append(hand + direction * along - side * (half - wave))
	var blade := PackedVector2Array()
	blade.append_array(top)
	for i in range(bottom.size() - 1, -1, -1):
		blade.append(bottom[i])
	MathArt.draw_poly(self, blade, _tint(STEEL, alpha), Color(1.0, 1.0, 1.0, alpha * 0.55), 1.0)
	draw_line(hand + side * 4.5, hand - side * 4.5, _tint(TRIM_DIM, alpha), 3.0)
	draw_line(hand - direction * 5.0, hand, _tint(GRIP, alpha), 3.0)
	# A thin bright centerline makes the sine function readable at speed.
	draw_polyline(top, Color(1.0, 1.0, 1.0, alpha * 0.20), 0.8, true)

	if p.state == Player.State.ATTACK:
		_draw_attack_trail(alpha, hand)


func _draw_aegis(alpha: float) -> void:
	if p.aegis_t <= 0.0:
		return
	var life_k := clampf(p.aegis_t / p.aegis_time, 0.0, 1.0)
	var center := Vector2(0, -8)
	for ring in 3:
		var points := PackedVector2Array()
		for i in 56:
			var theta := TAU * float(i) / 56.0
			var radius := 38.0 + 8.0 * sin(3.0 * theta + _t * 7.0 + float(ring) * 0.7)
			points.append(center + Vector2.from_angle(theta + float(ring) * 0.4) * radius)
		points.append(points[0])
		draw_polyline(points, Color(EYE, alpha * life_k * 0.48), 1.6, true)
	MathArt.draw_ring(self, center, 41.0, Color(EYE, alpha * life_k * 0.25), 1.4, 56)
	for i in 5:
		var angle := _t * 3.0 + TAU * float(i) / 5.0
		draw_circle(center + Vector2.from_angle(angle) * 44.0, 1.9, Color(EYE, alpha * life_k * 0.85))


func _draw_attack_trail(alpha: float, hand: Vector2) -> void:
	var current := _attack_angle()
	var start := _attack_start_angle()
	if absf(current - start) < 0.15:
		return
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var samples := 8
	for i in samples:
		var k := float(i) / float(samples - 1)
		var angle := lerpf(start, current, k)
		outer.append(hand + Vector2.from_angle(angle) * 30.0)
		inner.append(hand + Vector2.from_angle(angle) * 13.0)
	var trail := PackedVector2Array()
	trail.append_array(outer)
	for i in range(inner.size() - 1, -1, -1):
		trail.append(inner[i])
	MathArt.draw_poly(self, trail, Color(EYE, alpha * 0.08), Color(EYE, alpha * 0.22), 1.0)


func _attack_start_angle() -> float:
	var from_angle := -1.95
	match p.attack_index:
		1:
			from_angle = 0.85
		2:
			from_angle = -2.85
	return from_angle


func _attack_angle() -> float:
	var progress := clampf(p.attack_t / maxf(p.attack_total, 0.001), 0.0, 1.0)
	var from_angle := _attack_start_angle()
	var to_angle := 0.72
	match p.attack_index:
		1:
			to_angle = -1.95
		2:
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
	var hexagon := MathArt.ngon(6, 15.0, _t * 4.0)
	MathArt.draw_poly(self, hexagon, _tint(CLOAK, alpha), _tint(TRIM, alpha * 0.55), 1.2)
	MathArt.draw_spiral(self, Vector2.ZERO, 13.5, 1.6, Color(EYE, alpha * 0.35), 1.0, 32, _t * 2.0)
	draw_circle(Vector2(3, -2), 8.0, _tint(MASK, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in 3:
		var offset := Vector2(-float(p.facing) * (18.0 + float(i) * 6.0), -4.0 + float(i) * 4.0)
		draw_line(offset, offset - Vector2(float(p.facing) * 10.0, 0), _tint(CLOAK_LIGHT, alpha * 0.35), 1.5)
		draw_circle(offset, 1.0, Color(EYE, alpha * 0.25))


func _draw_dead() -> void:
	draw_set_transform(Vector2(0, 22), float(p.facing) * 1.4, Vector2.ONE)
	# Collapse into three golden-ratio shards.
	for i in 3:
		var center := Vector2(-12.0 + float(i) * 11.0, -3.0 - float(i) * 2.0)
		var points := MathArt.ngon(3, 6.0 - float(i), float(i) * 0.8, center)
		MathArt.draw_poly(self, points, Color(CLOAK_DARK, 0.9), Color(TRIM_DIM, 0.4), 1.0)
	draw_circle(Vector2(-16, -3), 5.5, MASK)
	draw_line(Vector2(4, 2), Vector2(28, 6), STEEL_DARK, 2.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
