class_name EnemyVisual
extends Node2D
## Enemies are geometric archetypes:
##   Husk    -> triangle (3)
##   Watcher -> circle / orbit
##   Ram     -> square (4)
##   Bulwark -> hexagon (6)
##   Warden  -> pentagon + pentagram (5)
## The same primitives drive telegraphs, sigils and death shards.

const MASK := Color("#e9e2d2")

var e: Enemy
var _t := 0.0


func _ready() -> void:
	e = get_parent() as Enemy
	_t = randf() * 10.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if e == null or e.cfg.is_empty():
		return
	var half_h := float(e.cfg.get("body_height", 42.0)) * 0.5
	var tint: Color = Color(e.cfg.get("color", "#b23a48"))
	var moving := absf(e.velocity.x) > 10.0 and e.state == Enemy.EState.CHASE
	var bob := sin(_t * 9.0) * 2.0 if moving else sin(_t * 2.0) * 1.0
	var lean := 0.12 if moving else 0.0
	if e.state == Enemy.EState.WINDUP:
		lean = -0.16
	elif e.state == Enemy.EState.HURT:
		lean = -0.22
	var flash := e.flash > 0.0
	draw_set_transform(Vector2(0, bob), lean * float(e.facing), Vector2(float(e.facing), 1.0))

	_draw_shadow(half_h)
	_draw_sigil(half_h)
	match e.kind:
		"archer":
			_draw_archer(tint, flash, half_h)
		"charger":
			_draw_charger(tint, flash, half_h)
		"bulwark":
			_draw_bulwark(tint, flash, half_h)
		"warden":
			_draw_warden(tint, flash, half_h)
		_:
			_draw_grunt(tint, flash, half_h)

	if e.state == Enemy.EState.WINDUP:
		_draw_telegraph(tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_health_bar(half_h)
	_draw_spawn_flash(half_h)


func _c(color: Color, flash: bool, alpha: float = 1.0) -> Color:
	var out := Color(1, 1, 1, 1) if flash else color
	out.a *= alpha
	return out


func _draw_shadow(half_h: float) -> void:
	draw_set_transform(Vector2(0, half_h + 1.0), 0.0, Vector2(1.0, 0.24))
	draw_circle(Vector2.ZERO, float(e.cfg.get("body_radius", 12.0)) + 4.0, Color(0, 0, 0, 0.30))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(float(e.facing), 1.0))


func _draw_sigil(half_h: float) -> void:
	var sides := 3
	match e.kind:
		"charger":
			sides = 4
		"bulwark":
			sides = 6
		"warden":
			sides = 5
		"archer":
			sides = 0
	var tint: Color = Color(e.cfg.get("color", "#b23a48"))
	draw_set_transform(Vector2(0, half_h + 2.0), 0.0, Vector2(1.0, 0.26))
	if sides == 0:
		MathArt.draw_ring(self, Vector2.ZERO, float(e.cfg.get("body_radius", 10.0)) + 8.0,
			Color(tint, 0.18), 1.0, 28)
	else:
		MathArt.draw_poly(self, MathArt.ngon(sides, float(e.cfg.get("body_radius", 12.0)) + 12.0, -_t * 0.35),
			Color(tint, 0.10), Color(tint, 0.30), 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(float(e.facing), 1.0))


func _draw_grunt(tint: Color, flash: bool, half_h: float) -> void:
	var dark := tint.darkened(0.62)
	var hide := tint.darkened(0.30)
	var rim := tint.lightened(0.30)
	# Wide stance
	draw_line(Vector2(-6, 5), Vector2(-9, half_h), _c(dark, flash), 5.5)
	draw_line(Vector2(6, 5), Vector2(9, half_h), _c(dark, flash), 5.5)
	# Back arm
	draw_line(Vector2(-7, -5), Vector2(-14, 4), _c(dark, flash), 3.2)
	for i in 2:
		draw_line(Vector2(-14, 4), Vector2(-18.0 - float(i) * 1.5, 1.5 + float(i) * 3.0), _c(rim, flash, 0.55), 1.0)
	# Triangle torso with a golden-ratio inner triangle and shoulder spikes.
	var body := PackedVector2Array([Vector2(-13, 12), Vector2(13, 12), Vector2(0, -13)])
	MathArt.draw_poly(self, body, _c(hide, flash), _c(rim, flash, 0.55), 1.2)
	var inner := PackedVector2Array([Vector2(-6.2, 8), Vector2(6.2, 8), Vector2(0, -5.2)])
	MathArt.draw_poly(self, inner, Color(0, 0, 0, 0.18), _c(rim, flash, 0.35), 1.0)
	for side in [-1, 1]:
		var spike := PackedVector2Array([
			Vector2(9.0 * float(side), -9), Vector2(15.0 * float(side), -16),
			Vector2(12.0 * float(side), -5),
		])
		MathArt.draw_poly(self, spike, _c(dark, flash), _c(rim, flash, 0.55), 0.9)
	# Three orbiting shards.
	for i in 3:
		var angle := _t * 1.4 + TAU * float(i) / 3.0
		var shard := MathArt.ngon(3, 3.2, angle, Vector2.from_angle(angle) * 20.0 + Vector2(0, -2))
		MathArt.draw_poly(self, shard, _c(rim, flash, 0.30), _c(rim, flash, 0.55), 0.8)
	# Head: inverted triangle hood, two horns, bone mask and jaw.
	var hood := PackedVector2Array([Vector2(-1, -26), Vector2(10, -13), Vector2(-8, -13)])
	MathArt.draw_poly(self, hood, _c(dark, flash), _c(rim, flash, 0.35), 1.0)
	MathArt.draw_poly(self, PackedVector2Array([Vector2(-4, -24), Vector2(0, -32), Vector2(-7, -22)]),
		_c(MASK, flash, 0.75))
	MathArt.draw_poly(self, PackedVector2Array([Vector2(5, -24), Vector2(11, -31), Vector2(9, -21)]),
		_c(MASK, flash, 0.75))
	draw_circle(Vector2(3, -17), 4.8, _c(MASK, flash))
	draw_line(Vector2(0.5, -18.5), Vector2(7, -16.5), _c(Color("#20242c"), flash), 1.6)
	draw_circle(Vector2(6, -16.8), 1.3, _c(Color("#ff5b5b"), flash))
	MathArt.draw_poly(self, PackedVector2Array([Vector2(-1, -15), Vector2(7, -15), Vector2(3, -10)]),
		_c(dark, flash, 0.75), _c(rim, flash, 0.25), 0.8)
	# Three-claw arm.
	draw_line(Vector2(7, -1), Vector2(16, 7), _c(rim, flash, 0.85), 3.4)
	for i in 3:
		draw_line(Vector2(16, 7), Vector2(20.0 + float(i) * 1.2, 3.0 + float(i) * 3.0),
			_c(MASK, flash, 0.85), 1.1)


func _draw_archer(tint: Color, flash: bool, half_h: float) -> void:
	var dark := tint.darkened(0.62)
	var robe := tint.darkened(0.30)
	# Layered robe: a tall cone with a phi-spaced trim.
	var body := PackedVector2Array([Vector2(-13, half_h), Vector2(13, half_h), Vector2(7, -14), Vector2(-7, -14)])
	MathArt.draw_poly(self, body, _c(robe, flash), _c(tint.lightened(0.28), flash, 0.55), 1.2)
	var hem := PackedVector2Array([
		Vector2(-13, half_h), Vector2(13, half_h), Vector2(11, half_h - 5.0), Vector2(-11, half_h - 5.0),
	])
	MathArt.draw_poly(self, hem, _c(dark, flash, 0.85), _c(tint.lightened(0.35), flash, 0.35), 0.8)
	draw_line(Vector2(-9, 4), Vector2(-11, half_h - 4), _c(tint.lightened(0.15), flash, 0.35), 1.0)
	draw_line(Vector2(9, 4), Vector2(11, half_h - 4), _c(tint.lightened(0.15), flash, 0.35), 1.0)
	# Tall hood with a crescent brim.
	var hood := PackedVector2Array([
		Vector2(-8, -13), Vector2(-6, -27), Vector2(4, -30), Vector2(11, -20), Vector2(9, -11),
	])
	MathArt.draw_poly(self, hood, _c(dark, flash), _c(tint.lightened(0.3), flash, 0.4), 1.0)
	draw_arc(Vector2(3, -19), 11.0, -2.5, 0.6, 12, _c(tint.lightened(0.45), flash, 0.55), 1.2, true)
	draw_circle(Vector2(4, -17), 5.2, _c(MASK, flash))
	draw_line(Vector2(1, -18), Vector2(8.5, -16), _c(Color("#20242c"), flash), 1.5)
	draw_circle(Vector2(7.6, -16), 1.5, _c(Color("#ffd166"), flash))
	# Orbiting ellipse: a circle read as an orbit in 2D.
	var orbit := PackedVector2Array()
	var orbit_rotation := 0.28 + sin(_t * 1.2) * 0.05
	for i in 28:
		var theta := TAU * float(i) / 28.0
		var point := Vector2(cos(theta) * 17.0, sin(theta) * 4.6).rotated(orbit_rotation)
		orbit.append(point + Vector2(2, -17))
	draw_polyline(orbit, _c(tint.lightened(0.35), flash, 0.55), 1.0, true)
	# Bow: a circular arc plus string.
	draw_arc(Vector2(13, -2), 15.0, -1.25, 1.25, 14, _c(Color("#d8c08a"), flash), 2.0, true)
	draw_line(Vector2(17, -15), Vector2(17, 11), _c(Color(0.85, 0.85, 0.8), flash, 0.5), 1.0)
	if e.state == Enemy.EState.WINDUP:
		var pull := clampf(e.state_t / float(e.cfg.get("windup", 0.5)), 0.0, 1.0)
		var arrow_tip := Vector2(17, -14).lerp(Vector2(17 - 12.0 * pull, 0), pull)
		draw_line(Vector2(17, 11), arrow_tip, _c(MASK, flash, 0.5), 1.0)
		draw_line(arrow_tip, Vector2(32, 0), _c(MASK, flash), 1.1)
		MathArt.draw_ring(self, Vector2(13, -2), 19.0, Color(1.0, 0.45, 0.35, 0.35 + 0.35 * pull), 1.2, 20)


func _draw_charger(tint: Color, flash: bool, half_h: float) -> void:
	var dark := tint.darkened(0.62)
	var hide := tint.darkened(0.20)
	# Legs
	draw_line(Vector2(-7, 8), Vector2(-9, half_h), _c(dark, flash), 6.0)
	draw_line(Vector2(7, 8), Vector2(9, half_h), _c(dark, flash), 6.0)
	# Rotating square torso.
	var body := MathArt.ngon(4, 17.0, PI * 0.25 + sin(_t * 0.6) * 0.03, Vector2(0, 1))
	MathArt.draw_poly(self, body, _c(hide, flash), _c(tint.lightened(0.25), flash, 0.5), 1.2)
	var inner := MathArt.ngon(4, 9.0, PI * 0.25, Vector2(0, 1))
	MathArt.draw_poly(self, inner, Color(0, 0, 0, 0.18), _c(tint.lightened(0.1), flash, 0.4), 0.9)
	# Shoulders and helmet.
	MathArt.draw_poly(self, MathArt.ngon(4, 5.0, 0.0, Vector2(-13, -10)), _c(dark, flash))
	MathArt.draw_poly(self, MathArt.ngon(4, 5.0, 0.0, Vector2(13, -10)), _c(dark, flash))
	draw_rect(Rect2(-6, -26, 18, 11), _c(dark, flash))
	draw_line(Vector2(-6, -21), Vector2(12, -21), _c(Color("#ff8a3d"), flash), 2.0)
	# Logarithmic horns.
	MathArt.draw_spiral(self, Vector2(-6, -26), 9.0, 1.2, _c(MASK, flash, 0.85), 1.4, 20, -PI * 0.5)
	MathArt.draw_spiral(self, Vector2(12, -26), 9.0, 1.2, _c(MASK, flash, 0.85), 1.4, 20, -PI * 0.5)
	# Square shield.
	MathArt.draw_poly(self, MathArt.ngon(4, 7.0, PI * 0.25, Vector2(20, 7)), _c(Color("#5a4634"), flash), _c(MASK, flash, 0.3), 1.0)
	# Charge dust hints.
	if e.state == Enemy.EState.ATTACK:
		for i in 3:
			var x := -float(i + 1) * 12.0
			draw_line(Vector2(x, 10), Vector2(x - 8, 10), Color(1.0, 0.55, 0.25, 0.35), 1.4)


func _draw_bulwark(tint: Color, flash: bool, half_h: float) -> void:
	var dark := tint.darkened(0.62)
	var hide := tint.darkened(0.15)
	# Legs.
	draw_line(Vector2(-6, 8), Vector2(-8, half_h), _c(dark, flash), 5.0)
	draw_line(Vector2(6, 8), Vector2(8, half_h), _c(dark, flash), 5.0)
	# Hexagonal body: nest three hexagons at phi ratios.
	MathArt.draw_poly(self, MathArt.ngon(6, 15.0, PI / 6.0, Vector2(0, 1)),
		_c(hide, flash), _c(tint.lightened(0.25), flash, 0.45), 1.1)
	MathArt.draw_poly(self, MathArt.ngon(6, 15.0 * MathArt.INV_PHI, PI / 6.0, Vector2(0, 1)),
		Color(0, 0, 0, 0.16), _c(tint.lightened(0.2), flash, 0.35), 0.9)
	# Big front shield: three concentric hexagons.
	var shield_center := Vector2(15, -2)
	for i in 3:
		var radius := 16.0 * pow(MathArt.INV_PHI, float(i))
		var shield := MathArt.ngon(6, radius, PI / 6.0 + _t * 0.15 * float(i + 1), shield_center)
		var fill := Color(tint, 0.30 + 0.1 * float(i)) if i == 0 else Color(0, 0, 0, 0.12)
		MathArt.draw_poly(self, shield, _c(fill, flash, 0.9), _c(MASK, flash, 0.55), 1.0)
	draw_line(shield_center + Vector2(0, -13), shield_center + Vector2(0, 13), _c(MASK, flash, 0.55), 1.2)
	# Mask and eye.
	draw_circle(Vector2(2, -16), 8.5, _c(dark, flash))
	draw_circle(Vector2(3.5, -15.5), 5.0, _c(MASK, flash))
	draw_line(Vector2(0.5, -17), Vector2(8, -15), _c(Color("#20242c"), flash), 1.5)
	draw_circle(Vector2(6.2, -15.2), 1.3, _c(Color("#8fe3ff"), flash))
	if e.state == Enemy.EState.WINDUP:
		MathArt.draw_ring(self, shield_center, 18.0 + 4.0 * (e.state_t / 0.55),
			Color(tint.lightened(0.3), 0.55), 1.5, 24)


func _draw_warden(tint: Color, flash: bool, half_h: float) -> void:
	var dark := tint.darkened(0.68)
	var hide := tint.darkened(0.25)
	# Aura: pentagram + orbit ring.
	MathArt.draw_poly(self, MathArt.star(5, 42.0, 17.0, -PI * 0.5 + _t * 0.12),
		Color(tint, 0.06), Color(tint.lightened(0.3), 0.22), 1.0)
	MathArt.draw_ring(self, Vector2.ZERO, 38.0, Color(tint.lightened(0.4), 0.18), 1.0, 48, -_t * 0.2, -_t * 0.2 + TAU)
	for i in 5:
		var angle := _t * 0.7 + TAU * float(i) / 5.0
		draw_circle(Vector2.from_angle(angle) * 34.0, 1.6, Color(tint.lightened(0.5), 0.6))
	# Cape / body: nested pentagons.
	MathArt.draw_poly(self, MathArt.ngon(5, 22.0, -PI * 0.5, Vector2(0, 2)),
		_c(dark, flash), _c(tint.lightened(0.2), flash, 0.4), 1.2)
	MathArt.draw_poly(self, MathArt.ngon(5, 22.0 * MathArt.INV_PHI, -PI * 0.5, Vector2(0, 2)),
		_c(hide, flash), _c(tint.lightened(0.35), flash, 0.5), 1.0)
	# Fivefold crown.
	for i in 5:
		var angle := -PI * 0.5 + TAU * float(i) / 5.0
		var base := Vector2.from_angle(angle) * 13.0 + Vector2(0, -26)
		var point := Vector2.from_angle(angle) * 22.0 + Vector2(0, -26)
		var crown := PackedVector2Array([base + Vector2(-2.4, 0), point, base + Vector2(2.4, 0)])
		MathArt.draw_poly(self, crown, _c(tint.lightened(0.3), flash, 0.8), _c(MASK, flash, 0.35), 0.8)
	# Head / mask.
	draw_circle(Vector2(0, -25), 9.5, _c(dark, flash))
	draw_circle(Vector2(1, -24), 5.8, _c(MASK, flash))
	draw_line(Vector2(-3, -26), Vector2(7, -23), _c(Color("#1a1420"), flash), 1.8)
	draw_circle(Vector2(5.2, -23.5), 1.7, _c(Color("#c9a7ff"), flash))
	# Cleaver: a long triangle with a golden-ratio notch.
	var hand := Vector2(17, -8)
	var angle := 0.75
	if e.state == Enemy.EState.WINDUP:
		angle = -0.9
	elif e.state == Enemy.EState.ATTACK:
		angle = 0.9
	var direction := Vector2.from_angle(angle)
	var side := direction.orthogonal()
	var blade := PackedVector2Array([
		hand + direction * 6.0 + side * 6.0,
		hand + direction * 42.0 + side * 10.0,
		hand + direction * 38.0 - side * 2.0,
		hand + direction * 6.0 - side * 4.0,
	])
	MathArt.draw_poly(self, blade, _c(Color("#b9b0c9"), flash), _c(Color("#f2e8ff"), flash, 0.55), 1.0)
	draw_line(hand, hand + direction * 6.0, _c(Color("#3a2a1a"), flash), 4.0)
	draw_circle(hand, 2.5, _c(MASK, flash))


func _draw_telegraph(tint: Color) -> void:
	var windup := maxf(0.001, float(e.cfg.get("windup", 0.4)))
	var progress := clampf(e.state_t / windup, 0.0, 1.0)
	var pulse := 0.35 + 0.45 * progress
	if e.kind == "warden":
		var pending: String = e._pending_attack
		if pending == "cleave":
			draw_arc(Vector2(16, -4), 36.0 + 8.0 * progress, -1.2, 1.2, 18, Color(1.0, 0.4, 0.3, pulse), 2.4, true)
			draw_line(Vector2(6, -4), Vector2(6 + 70.0 * progress, -4), Color(1.0, 0.7, 0.5, pulse * 0.5), 1.2)
		elif pending == "charge":
			draw_line(Vector2(10, 2), Vector2(10 + 130.0 * progress, 2), Color(1.0, 0.35, 0.25, pulse), 3.0)
		else:
			MathArt.draw_ring(self, Vector2(0, 30), 28.0 + 24.0 * progress, Color(1.0, 0.4, 0.3, pulse * 0.7), 2.0, 32)
			draw_line(Vector2(-40, 30), Vector2(40, 30), Color(1.0, 0.6, 0.4, pulse * 0.4), 1.0)
		return
	if e.kind == "charger":
		var length := 40.0 + 70.0 * progress
		draw_line(Vector2(10, -6), Vector2(10 + length, -6), Color(1.0, 0.35, 0.25, pulse), 3.0)
		draw_line(Vector2(10, -6), Vector2(10 + length, -6), Color(1.0, 0.8, 0.6, pulse * 0.5), 1.2)
	elif e.kind == "archer":
		draw_circle(Vector2(13, -2), 20.0 + 5.0 * progress, Color(1.0, 0.4, 0.3, pulse * 0.16))
		draw_arc(Vector2(13, -2), 21.0 + 5.0 * progress, -1.2, 1.2, 14, Color(1.0, 0.45, 0.35, pulse), 1.6)
		_draw_arrow_prediction()
	elif e.kind == "bulwark":
		draw_arc(Vector2(8, -4), 28.0, -1.15, 1.15, 12, Color(0.55, 0.8, 1.0, pulse), 2.2)
		draw_line(Vector2(8, -4), Vector2(8 + 32.0 * progress, -4), Color(0.7, 0.9, 1.0, pulse * 0.6), 1.2)
	else:
		draw_arc(Vector2(8, -4), 26.0, -1.15, 1.15, 12, Color(1.0, 0.4, 0.28, pulse), 2.0)
		draw_line(Vector2(8, -4), Vector2(8 + 30.0 * progress, -4), Color(1.0, 0.7, 0.5, pulse * 0.6), 1.0)


func _draw_arrow_prediction() -> void:
	var player := Game.player
	if player == null:
		return
	var origin := e.global_position + Vector2(float(e.facing) * 12.0, -18.0)
	var target := player.global_position + Vector2(0, -18)
	var velocity := MathArt.ballistic_velocity(origin, target, float(e.cfg.get("projectile_speed", 320.0)), 700.0)
	for i in 22:
		var time := 0.9 * float(i) / 21.0
		var world := origin + velocity * time + Vector2(0.0, 0.5 * 700.0 * time * time)
		var local := to_local(world)
		local.x *= float(e.facing)
		draw_circle(local, 1.15, Color(1.0, 0.72, 0.5, 0.28))


func _draw_health_bar(half_h: float) -> void:
	if e.hp >= e.max_hp or e._dead or bool(e.cfg.get("boss", false)):
		return
	var width := 40.0
	var y := -(half_h + 14.0)
	draw_rect(Rect2(-width * 0.5, y, width, 4.0), Color(0.02, 0.02, 0.03, 0.85))
	var ratio := clampf(e.hp / maxf(e.max_hp, 1.0), 0.0, 1.0)
	draw_rect(Rect2(-width * 0.5, y, width * ratio, 4.0), Color("#d94a4a"))
	draw_rect(Rect2(-width * 0.5, y, width * ratio, 1.0), Color(1.0, 0.55, 0.5, 0.7))
	MathArt.draw_poly(self, MathArt.ngon(3, 2.0, 0.0, Vector2(0, y + 2.0)), Color(0.9, 0.65, 0.3, 0.7))


func _draw_spawn_flash(half_h: float) -> void:
	if e._spawn_t <= 0.0 or e._spawn_t > 0.4:
		return
	var a := clampf(e._spawn_t / 0.4, 0.0, 1.0) * 0.5
	MathArt.draw_ring(self, Vector2(0, -4), 26.0 + 10.0 * (1.0 - a), Color(1.0, 0.9, 0.7, a * 0.35), 1.0, 32)
	draw_circle(Vector2(0, -4), 26.0 + 10.0 * (1.0 - a), Color(1.0, 0.9, 0.7, a * 0.08))
