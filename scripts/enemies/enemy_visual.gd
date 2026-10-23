class_name EnemyVisual
extends Node2D
## Enemies are pure geometric sigils. Side count is the threat tier:
##   Husk 3 (triangle) · Ram 4 (square) · Warden 5 (pentagon)
##   Bulwark 6 (hexagon) · Watcher 0 (circle + orbit)
## Detail is carried by rim light, a pulsing core and pixel particles.

const MASK := MathArt.PALE

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
	var tint: Color = Color(e.cfg.get("color", "#d94a4a"))
	var moving := absf(e.velocity.x) > 10.0 and e.state == Enemy.EState.CHASE
	var bob := 0.0
	if moving:
		bob = roundf(sin(_t * 10.0) * 1.5)
	else:
		bob = roundf(sin(_t * 2.0))
	var lean := 0.0
	if e.state == Enemy.EState.WINDUP:
		lean = -0.18
	elif e.state == Enemy.EState.HURT:
		lean = -0.24
	elif moving:
		lean = 0.12
	# Impact frame: pure white for 2 frames, then the normal tint plus a
	# white 1px outline that fades out over the remaining hit flash.
	var flash := e.impact > 0.0
	var outline := e.flash > 0.0 and e.impact <= 0.0
	draw_set_transform(Vector2(0, bob), lean * float(e.facing), Vector2(float(e.facing), 1.0))

	_draw_shadow(half_h)
	_draw_ground_sigil(half_h, tint)
	match e.kind:
		"archer":
			_draw_watcher(tint, flash)
		"charger":
			_draw_ram(tint, flash)
		"bulwark":
			_draw_bulwark(tint, flash)
		"warden":
			_draw_warden(tint, flash)
		_:
			_draw_husk(tint, flash)

	if e.state == Enemy.EState.WINDUP:
		_draw_telegraph(tint)
	if outline:
		_draw_hit_outline(tint, half_h)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_health_bar(half_h)
	_draw_spawn_flash(half_h)


func _c(color: Color, flash: bool, alpha: float = 1.0) -> Color:
	var out := MathArt.WHITE if flash else color
	out.a *= alpha
	return out


func _draw_shadow(half_h: float) -> void:
	var width := roundf(float(e.cfg.get("body_radius", 12.0)) * 0.9 + 6.0)
	MathArt.px_rect(self, Rect2(-width, half_h + 1.0, width * 2.0, 3.0), Color(0.0, 0.0, 0.0, 0.34))
	MathArt.px_rect(self, Rect2(-width * 0.6, half_h, width * 1.2, 1.0), Color(0.0, 0.0, 0.0, 0.22))


func _draw_ground_sigil(half_h: float, tint: Color) -> void:
	var radius := float(e.cfg.get("body_radius", 12.0)) + 10.0
	var alpha := 0.16 + 0.06 * sin(_t * 2.0)
	var sides := _sides()
	if sides == 0:
		MathArt.px_ring(self, Vector2(0, half_h + 2.0), radius * 1.15, Color(tint, alpha), 1.0)
		MathArt.px_ring(self, Vector2(0, half_h + 2.0), radius * 0.8, Color(tint, alpha * 0.6), 1.0)
		return
	var flat := PackedVector2Array()
	for point in MathArt.ngon(sides, radius, -_t * 0.25):
		flat.append(Vector2(point.x, half_h + 2.0 + point.y * 0.22))
	MathArt.px_poly(self, flat, Color(0, 0, 0, 0), Color(tint, alpha), 1.0)


func _sides() -> int:
	match e.kind:
		"charger":
			return 4
		"bulwark":
			return 6
		"warden":
			return 5
		"archer":
			return 0
		_:
			return 3


func _draw_husk(tint: Color, flash: bool) -> void:
	var dark := tint.darkened(0.55)
	var rim := tint.lightened(0.35)
	# Legs: two 3x7 blocks.
	MathArt.px_rect(self, Rect2(-6, 4, 3, 8), _c(dark, flash))
	MathArt.px_rect(self, Rect2(3, 4, 3, 8), _c(dark, flash))
	# Body: one triangle, one inner triangle.
	var body := PackedVector2Array([Vector2(0, -13), Vector2(12, 11), Vector2(-12, 11)])
	MathArt.px_poly(self, body, _c(tint, flash), _c(rim, flash, 0.6), 1.0)
	var inner := PackedVector2Array([Vector2(0, -5), Vector2(6, 7), Vector2(-6, 7)])
	MathArt.px_poly(self, inner, _c(dark, flash, 0.55))
	# Two 1px eyes: the only "face".
	MathArt.px_rect(self, Rect2(-3, -1, 2, 2), _c(MathArt.RED_HI, flash))
	MathArt.px_rect(self, Rect2(2, -1, 2, 2), _c(MathArt.RED_HI, flash))
	# Shoulder spikes.
	MathArt.px_poly(self, PackedVector2Array([Vector2(9, -7), Vector2(15, -13), Vector2(11, -3)]),
		_c(dark, flash), _c(rim, flash, 0.4), 1.0)
	# Claw arm.
	MathArt.px_line(self, Vector2(9, 2), Vector2(16, 8), _c(rim, flash, 0.8), 2.0)
	MathArt.px_rect(self, Rect2(16, 8, 2, 2), _c(MASK, flash, 0.9))


func _draw_watcher(tint: Color, flash: bool) -> void:
	var dark := tint.darkened(0.55)
	var rim := tint.lightened(0.35)
	# Robe: a tall triangle under the orb.
	MathArt.px_poly(self, PackedVector2Array([Vector2(-10, 18), Vector2(10, 18), Vector2(5, -6), Vector2(-5, -6)]),
		_c(dark, flash), _c(rim, flash, 0.45), 1.0)
	MathArt.px_rect(self, Rect2(-10, 17, 20, 2), _c(tint, flash, 0.5))
	# Head orb.
	MathArt.px_circle(self, Vector2(1, -15), 7.0, _c(tint, flash))
	MathArt.px_circle(self, Vector2(1, -15), 5.0, _c(dark, flash, 0.7))
	MathArt.px_rect(self, Rect2(2, -16, 2, 2), _c(MathArt.AMBER_HI, flash))
	# Orbit: an ellipse of 1px dots, with one travelling bead.
	var orbit_rotation := 0.22 + sin(_t * 1.1) * 0.06
	for i in 18:
		var theta := TAU * float(i) / 18.0
		var point := Vector2(cos(theta) * 15.0, sin(theta) * 4.0).rotated(orbit_rotation)
		MathArt.px_rect(self, Rect2(roundf(point.x), roundf(point.y - 15.0), 1, 1), _c(rim, flash, 0.55))
	var bead_angle := _t * 2.4
	var bead := Vector2(cos(bead_angle) * 15.0, sin(bead_angle) * 4.0).rotated(orbit_rotation)
	MathArt.px_rect(self, Rect2(roundf(bead.x) - 1.0, roundf(bead.y - 15.0) - 1.0, 3, 3), _c(MathArt.AMBER_HI, flash))
	# Bow: a 1px arc plus a taut string.
	MathArt.px_arc(self, Vector2(11, 0), 12.0, -1.2, 1.2, _c(MathArt.AMBER_DIM, flash), 1.0)
	MathArt.px_line(self, Vector2(15, -11), Vector2(15, 10), _c(MASK, flash, 0.4), 1.0)
	if e.state == Enemy.EState.WINDUP:
		var pull := clampf(e.state_t / float(e.cfg.get("windup", 0.5)), 0.0, 1.0)
		var notch := Vector2(15.0 - 9.0 * pull, 0)
		MathArt.px_line(self, Vector2(15, 10), notch, _c(MASK, flash, 0.5), 1.0)
		MathArt.px_line(self, Vector2(15, -11), notch, _c(MASK, flash, 0.5), 1.0)
		MathArt.px_line(self, notch, Vector2(28, 0), _c(MASK, flash), 1.0)


func _draw_ram(tint: Color, flash: bool) -> void:
	var dark := tint.darkened(0.55)
	var rim := tint.lightened(0.35)
	# Legs.
	MathArt.px_rect(self, Rect2(-7, 8, 4, 10), _c(dark, flash))
	MathArt.px_rect(self, Rect2(4, 8, 4, 10), _c(dark, flash))
	# Square body with a 1px inner frame.
	MathArt.px_rect(self, Rect2(-14, -14, 28, 24), _c(tint, flash))
	MathArt.px_rect(self, Rect2(-12, -12, 24, 20), _c(dark, flash, 0.65))
	MathArt.px_rect(self, Rect2(-12, -12, 24, 1), _c(rim, flash, 0.8))
	MathArt.px_rect(self, Rect2(-12, 7, 24, 1), _c(MathArt.INK, flash, 0.5))
	# Cross brace.
	MathArt.px_line(self, Vector2(-12, -12), Vector2(12, 8), _c(rim, flash, 0.28), 1.0)
	MathArt.px_line(self, Vector2(12, -12), Vector2(-12, 8), _c(rim, flash, 0.28), 1.0)
	# Horns: two short spirals read as curled horns.
	MathArt.px_arc(self, Vector2(-6, -17), 5.0, -2.6, 0.2, _c(MASK, flash, 0.85), 1.0)
	MathArt.px_arc(self, Vector2(8, -17), 5.0, -2.6, 0.2, _c(MASK, flash, 0.85), 1.0)
	# Eye slit.
	MathArt.px_rect(self, Rect2(-4, -6, 12, 2), _c(MathArt.AMBER_HI, flash))
	if e.state == Enemy.EState.ATTACK:
		for i in 3:
			var x := -float(i + 1) * 10.0 - 12.0
			MathArt.px_rect(self, Rect2(x, 2, 6, 1), Color(MathArt.AMBER, 0.45))


func _draw_bulwark(tint: Color, flash: bool) -> void:
	var dark := tint.darkened(0.55)
	var rim := tint.lightened(0.35)
	MathArt.px_rect(self, Rect2(-7, 8, 4, 10), _c(dark, flash))
	MathArt.px_rect(self, Rect2(4, 8, 4, 10), _c(dark, flash))
	# Hexagonal body, nested at 1/phi.
	var body := MathArt.ngon(6, 15.0, PI / 6.0, Vector2(0, -2))
	MathArt.px_poly(self, body, _c(tint, flash), _c(rim, flash, 0.65), 1.0)
	var inner := MathArt.ngon(6, 15.0 * MathArt.INV_PHI, PI / 6.0, Vector2(0, -2))
	MathArt.px_poly(self, inner, _c(dark, flash, 0.6))
	# Eye.
	MathArt.px_rect(self, Rect2(-2, -6, 5, 2), _c(MathArt.CYAN, flash))
	# Front shield: three concentric hex outlines, rotating slightly.
	var shield_center := Vector2(15, -2)
	for i in 3:
		var radius := 13.0 * pow(MathArt.INV_PHI, float(i))
		var points := MathArt.ngon(6, radius, PI / 6.0 + _t * 0.12 * float(i + 1), shield_center)
		MathArt.px_poly(self, points, Color(tint, 0.22) if i == 0 else Color(0, 0, 0, 0),
			_c(MASK, flash, 0.55 - float(i) * 0.12), 1.0)
	MathArt.px_line(self, shield_center + Vector2(0, -11), shield_center + Vector2(0, 11), _c(MASK, flash, 0.4), 1.0)
	if e.state == Enemy.EState.WINDUP:
		var pulse := 0.4 + 0.5 * clampf(e.state_t / 0.55, 0.0, 1.0)
		MathArt.px_ring(self, shield_center, 16.0 + 4.0 * pulse, Color(MathArt.CYAN, pulse * 0.55), 1.0)


func _draw_warden(tint: Color, flash: bool) -> void:
	var dark := tint.darkened(0.6)
	var rim := tint.lightened(0.4)
	# Aura: pentagram outline, 1px, slowly turning.
	var aura := MathArt.star(5, 34.0, 14.0, -PI * 0.5 + _t * 0.10)
	MathArt.px_poly(self, aura, Color(0, 0, 0, 0), Color(tint, 0.20), 1.0)
	MathArt.px_ring(self, Vector2.ZERO, 36.0, Color(tint, 0.10), 1.0)
	for i in 5:
		var angle := _t * 0.8 + TAU * float(i) / 5.0
		var point := Vector2.from_angle(angle) * 30.0
		MathArt.px_rect(self, Rect2(roundf(point.x), roundf(point.y), 2, 2), Color(rim, 0.7))
	# Body: nested pentagons.
	MathArt.px_poly(self, MathArt.ngon(5, 19.0, -PI * 0.5, Vector2(0, 3)),
		_c(dark, flash), _c(rim, flash, 0.5), 1.0)
	MathArt.px_poly(self, MathArt.ngon(5, 19.0 * MathArt.INV_PHI, -PI * 0.5, Vector2(0, 3)),
		_c(tint, flash, 0.85), _c(rim, flash, 0.55), 1.0)
	# Crown: five 1px spikes.
	for i in 5:
		var angle := -PI * 0.5 + TAU * float(i) / 5.0
		var base := Vector2.from_angle(angle) * 10.0 + Vector2(0, -18)
		var tip := Vector2.from_angle(angle) * 17.0 + Vector2(0, -18)
		MathArt.px_line(self, base, tip, _c(MathArt.AMBER_HI, flash, 0.8), 1.0)
	# Eye.
	MathArt.px_rect(self, Rect2(-2, -10, 5, 2), _c(MathArt.VIOLET, flash))
	MathArt.px_rect(self, Rect2(0, -10, 1, 1), _c(MathArt.WHITE, flash))
	# Cleaver: a long 2px blade on a 1px grip.
	var hand := Vector2(14, -6)
	var angle := 0.8
	if e.state == Enemy.EState.WINDUP:
		angle = -1.0
	elif e.state == Enemy.EState.ATTACK:
		angle = 1.0
	var direction := Vector2.from_angle(angle)
	MathArt.px_line(self, hand, hand + direction * 30.0, _c(MathArt.STEEL_HI, flash), 3.0)
	MathArt.px_line(self, hand, hand + direction * 30.0, _c(MathArt.WHITE, flash, 0.55), 1.0)
	MathArt.px_line(self, hand - direction * 4.0, hand, _c(MathArt.AMBER_DIM, flash), 2.0)
	if e.state == Enemy.EState.ATTACK:
		MathArt.px_arc(self, hand, 26.0, angle - 1.4, angle, Color(MathArt.VIOLET, 0.35), 3.0)


func _draw_telegraph(tint: Color) -> void:
	var windup := maxf(0.001, float(e.cfg.get("windup", 0.4)))
	var progress := clampf(e.state_t / windup, 0.0, 1.0)
	var pulse := 0.35 + 0.5 * progress
	var warn := Color(MathArt.RED_HI, pulse)
	if e.kind == "warden":
		match String(e._pending_attack):
			"cleave":
				MathArt.px_arc(self, Vector2(14, -4), 30.0 + 10.0 * progress, -1.2, 1.2, warn, 2.0)
				MathArt.px_line(self, Vector2(4, -4), Vector2(4 + 54.0 * progress, -4), Color(warn, pulse * 0.5), 1.0)
			"charge":
				MathArt.px_line(self, Vector2(8, 2), Vector2(8 + 110.0 * progress, 2), warn, 2.0)
			_:
				MathArt.px_ring(self, Vector2(0, 26), 24.0 + 22.0 * progress, Color(warn, pulse * 0.7), 2.0)
		return
	if e.kind == "charger":
		MathArt.px_line(self, Vector2(8, -4), Vector2(8 + 34.0 + 56.0 * progress, -4), warn, 2.0)
	elif e.kind == "archer":
		MathArt.px_ring(self, Vector2(11, 0), 15.0 + 5.0 * progress, Color(warn, pulse * 0.6), 1.0)
		_draw_arrow_prediction()
	elif e.kind == "bulwark":
		MathArt.px_arc(self, Vector2(6, -2), 22.0, -1.1, 1.1, Color(MathArt.CYAN, pulse), 2.0)
	else:
		MathArt.px_arc(self, Vector2(6, -2), 22.0, -1.1, 1.1, warn, 2.0)


func _draw_arrow_prediction() -> void:
	var player := Game.player
	if player == null:
		return
	var origin := e.global_position + Vector2(float(e.facing) * 12.0, -15.0)
	var target := player.global_position + Vector2(0, -15)
	var velocity := MathArt.ballistic_velocity(origin, target, float(e.cfg.get("projectile_speed", 320.0)), 700.0)
	for i in 20:
		var time := 0.85 * float(i) / 19.0
		var world := origin + velocity * time + Vector2(0.0, 0.5 * 700.0 * time * time)
		var local := to_local(world)
		local.x *= float(e.facing)
		if i % 2 == 0:
			MathArt.px_rect(self, Rect2(roundf(local.x), roundf(local.y), 1, 1), Color(MathArt.RED_HI, 0.30))


func _draw_hit_outline(tint: Color, half_h: float) -> void:
	# A hard white rim around the silhouette, no fill: keeps the shape readable.
	var radius := float(e.cfg.get("body_radius", 12.0)) + 2.0
	var sides := _sides()
	var alpha := clampf(e.flash / 0.10, 0.0, 1.0) * 0.55
	if sides == 0:
		MathArt.px_ring(self, Vector2(0, -14.0), radius, Color(MathArt.WHITE, alpha), 1.0)
		return
	MathArt.px_poly(self, MathArt.ngon(sides, radius + 2.0, 0.0, Vector2(0, -2)),
		Color(0, 0, 0, 0), Color(MathArt.WHITE, alpha), 1.0)


func _draw_health_bar(half_h: float) -> void:
	if e.hp >= e.max_hp or e._dead or bool(e.cfg.get("boss", false)):
		return
	var width := 34.0
	var y := -(half_h + 12.0)
	MathArt.px_rect(self, Rect2(-width * 0.5 - 1.0, y - 1.0, width + 2.0, 5.0), Color(0.0, 0.0, 0.0, 0.8))
	var ratio := clampf(e.hp / maxf(e.max_hp, 1.0), 0.0, 1.0)
	MathArt.px_rect(self, Rect2(-width * 0.5, y, width * ratio, 3.0), MathArt.RED)
	MathArt.px_rect(self, Rect2(-width * 0.5, y, width * ratio, 1.0), MathArt.RED_HI)


func _draw_spawn_flash(half_h: float) -> void:
	if e._spawn_t <= 0.0 or e._spawn_t > 0.4:
		return
	var a := clampf(e._spawn_t / 0.4, 0.0, 1.0)
	var radius := 22.0 + 12.0 * (1.0 - a)
	MathArt.px_ring(self, Vector2(0, -4), radius, Color(MathArt.WHITE, a * 0.45), 1.0)
	MathArt.px_ring(self, Vector2(0, -4), radius * 0.6, Color(MathArt.AMBER_HI, a * 0.3), 1.0)
