class_name EnemyVisual
extends Node2D
## Enemies are plain polygons: no legs, no arms, no faces, no eyes.
## A "hand" is one dot; the only interior detail is a hollow inner shape.
## Readability comes from silhouette + motion + value, never from colour.
##
##   Husk    3  triangle   fast, twitchy, points at you
##   Ram     4  square     heavy, slow to turn, commits to a charge
##   Bulwark 6  hexagon    slow, always presents a flat face
##   Warden  5  pentagon   ritual pacing, fixed rhythm
##   Watcher 0  circle     keeps distance, orbits

const OUTLINE := MathArt.BLACK

var e: Enemy
var _t := 0.0
var _warden_points: PackedVector3Array = PackedVector3Array()
var _warden_faces_cache: Array = []


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
	var moving := absf(e.velocity.x) > 10.0 and e.state == Enemy.EState.CHASE
	var bob := 0.0
	if moving:
		bob = absf(sin(_t * 10.0)) * -2.0
	else:
		bob = sin(_t * 2.0) * 1.0
	var lean := 0.0
	if e.state == Enemy.EState.WINDUP:
		lean = -0.10
	elif e.state == Enemy.EState.HURT:
		lean = -0.12
	elif moving:
		lean = 0.06
	var flash := e.impact > 0.0
	var outline := e.flash > 0.0 and e.impact <= 0.0

	# Pure flat 2D: rotation and translation only. No squash, no stretch, no
	# scaling - the shapes stay rigid so they never look deformed.
	draw_set_transform(Vector2(0, bob), lean * float(e.facing), Vector2(float(e.facing), 1.0))
	_draw_shadow(half_h)
	_draw_ground_sigil(half_h)
	match e.kind:
		"archer":
			_draw_watcher(flash)
		"charger":
			_draw_ram(flash)
		"bulwark":
			_draw_bulwark(flash)
		"warden":
			_draw_warden(flash)
		_:
			_draw_husk(flash)

	if e.state == Enemy.EState.WINDUP:
		_draw_telegraph()
	if outline:
		_draw_hit_outline(half_h)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_health_bar(half_h)
	_draw_spawn_flash(half_h)


func _c(color: Color, flash: bool, alpha: float = 1.0) -> Color:
	var out := MathArt.WHITE if flash else color
	out.a *= alpha
	return out


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


func _radius() -> float:
	return float(e.cfg.get("body_radius", 12.0)) + 4.0


func _draw_shadow(half_h: float) -> void:
	var center := Vector2(0, half_h + 2.0)
	var rx := _radius() * 0.95
	var ry := 3.2
	for layer in [Vector2(1.0, 0.14), Vector2(0.72, 0.16), Vector2(0.42, 0.18)]:
		var points := PackedVector2Array()
		for p in MathArt.ngon(20, 1.0):
			points.append(Vector2(p.x * rx * layer.x, p.y * ry * layer.x) + center)
		MathArt.px_poly(self, points, Color(0.0, 0.0, 0.0, layer.y))


func _draw_ground_sigil(half_h: float) -> void:
	# A soft ring under the enemy: cheap grounding, no colour needed.
	var radius := _radius() + 8.0
	var alpha := 0.10 + 0.05 * sin(_t * 2.0)
	var sides := _sides()
	if sides == 0:
		MathArt.ring(self, Vector2(0, half_h + 2.0), radius, Color(MathArt.MID, alpha), 1.0)
		return
	var flat := PackedVector2Array()
	for point in MathArt.ngon(sides, radius, -_t * 0.25):
		flat.append(Vector2(point.x, half_h + 2.0 + point.y * 0.20))
	MathArt.px_poly(self, flat, Color(0, 0, 0, 0), Color(MathArt.MID, alpha), 1.0)


func _body_fill() -> Color:
	return MathArt.ENEMY


func _draw_husk(flash: bool) -> void:
	var r := _radius()
	var body := MathArt.ngon(3, r, -PI * 0.5, Vector2(0, -2))
	MathArt.px_poly(self, body, _c(_body_fill(), flash), Color(OUTLINE, 0.9), 2.0)
	# Inner hollow triangle: the "face" of the shape.
	MathArt.px_poly(self, MathArt.ngon(3, r * MathArt.INV_PHI, -PI * 0.5, Vector2(0, 0)),
		_c(MathArt.STONE, flash, 0.9))
	# Claw: one dot, extended during the attack.
	var hand := Vector2(11, 4)
	if e.state == Enemy.EState.ATTACK:
		hand = Vector2(18, 4)
	elif e.state == Enemy.EState.WINDUP:
		hand = Vector2(6, 2)
	MathArt.disc(self, hand, 3.0, _c(MathArt.WHITE, flash, 0.95))
	MathArt.line(self, Vector2(5, 1), hand, _c(MathArt.LIGHT_DIM, flash, 0.55), 1.5)


func _draw_watcher(flash: bool) -> void:
	var r := _radius()
	MathArt.disc(self, Vector2(0, -2), r, _c(_body_fill(), flash))
	MathArt.ring(self, Vector2(0, -2), r, Color(OUTLINE, 0.9), 2.0)
	MathArt.disc(self, Vector2(0, -2), r * 0.55, _c(MathArt.STONE, flash, 0.92))
	# Orbit: a dashed ellipse plus one travelling bead.
	var orbit_rotation := 0.24 + sin(_t * 1.1) * 0.06
	for i in 16:
		var theta := TAU * float(i) / 16.0
		var point := Vector2(cos(theta) * (r + 9.0), sin(theta) * 4.5).rotated(orbit_rotation)
		MathArt.px_rect(self, Rect2(point.x - 1.0, point.y - 2.0 - 2.0, 2.0, 2.0), _c(MathArt.MID, flash, 0.7))
	var bead_angle := _t * 2.4
	var bead := Vector2(cos(bead_angle) * (r + 9.0), sin(bead_angle) * 4.5).rotated(orbit_rotation)
	MathArt.disc(self, bead + Vector2(0, -2), 2.2, _c(MathArt.WHITE, flash))
	# No bow: the circle attacks directly. During windup a ring contracts onto
	# the edge, which is both a telegraph and a mathematical element.
	var pull := 0.0
	if e.state == Enemy.EState.WINDUP:
		pull = clampf(e.state_t / maxf(0.001, float(e.cfg.get("windup", 0.5))), 0.0, 1.0)
		MathArt.ring(self, Vector2(0, -2), lerpf(r + 16.0, r + 2.0, pull),
			_c(MathArt.WHITE, flash, 0.25 + 0.55 * pull), 2.0)
	# Firing point: a dot on the edge, brightest right before the shot.
	var hand := Vector2(r, -2)
	MathArt.disc(self, hand, lerpf(2.4, 4.2, pull), _c(MathArt.WHITE, flash))
	# Orbiting satellites: pure geometry, no weapon.
	for i in 3:
		var a := _t * 2.0 + TAU * float(i) / 3.0
		MathArt.disc(self, Vector2(cos(a) * (r + 7.0), -2.0 + sin(a) * 7.0), 1.4,
			_c(MathArt.PALE, flash, 0.7))


func _draw_ram(flash: bool) -> void:
	var r := _radius()
	var body := MathArt.ngon(4, r * 1.15, PI * 0.25, Vector2(0, -2))
	MathArt.px_poly(self, body, _c(_body_fill(), flash), Color(OUTLINE, 0.9), 2.0)
	MathArt.px_poly(self, MathArt.ngon(4, r * 0.65, PI * 0.25, Vector2(0, -2)), _c(MathArt.STONE, flash, 0.92))
	# Horns: two short ticks that lead the charge.
	var horn := 8.0 if e.state == Enemy.EState.ATTACK else 5.0
	MathArt.line(self, Vector2(-r * 0.6, -r * 0.9), Vector2(-r * 0.6 - horn * 0.4, -r * 0.9 - horn),
		_c(MathArt.WHITE, flash, 0.9), 2.0)
	MathArt.line(self, Vector2(r * 0.6, -r * 0.9), Vector2(r * 0.6 + horn * 0.4, -r * 0.9 - horn),
		_c(MathArt.WHITE, flash, 0.9), 2.0)


func _draw_bulwark(flash: bool) -> void:
	var r := _radius()
	var body := MathArt.ngon(6, r * 1.05, PI / 6.0, Vector2(0, -2))
	MathArt.px_poly(self, body, _c(_body_fill(), flash), Color(OUTLINE, 0.9), 2.0)
	MathArt.px_poly(self, MathArt.ngon(6, r * 0.62, PI / 6.0, Vector2(0, -2)), _c(MathArt.STONE, flash, 0.92))
	# Front shield: a flat face presented to the player.
	var shield_center := Vector2(r * 1.05, -2)
	for i in 3:
		var radius := 13.0 * pow(MathArt.INV_PHI, float(i))
		var points := MathArt.ngon(6, radius, PI / 6.0 + _t * 0.10 * float(i + 1), shield_center)
		MathArt.px_poly(self, points, Color(0, 0, 0, 0) if i > 0 else _c(MathArt.STONE_HI, flash, 0.5),
			_c(MathArt.WHITE, flash, 0.55 - float(i) * 0.12), 1.5)
	MathArt.line(self, shield_center + Vector2(0, -11), shield_center + Vector2(0, 11), _c(MathArt.WHITE, flash, 0.45), 1.0)


## The boss is the ONLY pseudo-3D body in the game. Everyone else stays a flat
## polygon, so the Warden reads as a different order of thing: a solid that
## turns in space instead of a shape that slides across the screen.
func _draw_warden(flash: bool) -> void:
	var r := _radius()
	var spin := _t * 0.42
	var points := Geom3D.rotate_y(_warden_mesh(r), spin)
	# A slight pitch so the top cap is visible: without it the prism reads as a
	# flat pentagon that merely changes width.
	var pitch := 0.22
	var projected := Geom3D.project(points, 260.0, Vector2.ZERO, pitch)
	var depths := Geom3D.depths(points, pitch)
	# Pre-darken: draw_solid lightens a face by up to +0.275, so a PALE base
	# would clamp every face to the same value and the solid would go flat.
	var tone := _c(MathArt.shade(MathArt.PALE, -0.18), flash)
	# contrast 1.15 is nearly twice the default: five facets on a 40 px body
	# need a wide value spread or the solid flattens into one grey mass.
	Geom3D.draw_solid(self, projected, _warden_faces(), tone,
		_c(MathArt.WHITE, flash), pitch, depths, 1.15)

	# The pentagram is inscribed on whichever cap faces the camera. Picking by
	# depth matters: drawing it on a fixed cap puts the lines behind the solid
	# half the time, and it reads as a wire cage instead of a sigil on a face.
	var front_cap := 5 if _cap_depth(depths, 5) > _cap_depth(depths, 0) else 0
	var sigil := PackedVector2Array()
	for i in 5:
		sigil.append(projected[front_cap + i])
	# INK, not white: the cap is the LIGHTEST face, so a bright sigil vanishes
	# into it. A dark inscription reads as carved.
	for i in 5:
		MathArt.line(self, sigil[i], sigil[(i + 2) % 5],
			_c(MathArt.INK, flash, 0.62), 1.5)

	# Cleaver hand: a dot on the leading edge, mirrored by facing so the blade
	# never crosses the body.
	var hand := Vector2(float(-e.facing) * -1.0 * r * 0.98, 2)
	var angle := 0.85
	if e.state == Enemy.EState.WINDUP:
		angle = -1.05
	elif e.state == Enemy.EState.ATTACK:
		angle = 1.05
	MathArt.disc(self, hand, 3.4, _c(MathArt.WHITE, flash))
	var direction := Vector2.from_angle(angle)
	MathArt.line(self, hand, hand + direction * 32.0, _c(MathArt.WHITE, flash), 3.0)
	MathArt.line(self, hand, hand + direction * 32.0, _c(MathArt.PALE, flash, 0.6), 1.0)
	if e.state == Enemy.EState.ATTACK:
		MathArt.arc(self, hand, 28.0, angle - 1.5, angle, Color(MathArt.WHITE, 0.35), 3.0)


## Pentagon column, cached: the mesh never changes, only its rotation.
func _warden_mesh(r: float) -> PackedVector3Array:
	if _warden_points.is_empty():
		var raw := Geom3D.prism(5, r * 1.15, r * 1.15)
		# A vertex must point UP. Geom3D.prism starts at +x, so turn it -90 deg.
		_warden_points = Geom3D.rotate_z(raw, -PI * 0.5)
	return _warden_points


func _cap_depth(depths: PackedFloat32Array, offset: int) -> float:
	var total := 0.0
	for i in 5:
		total += depths[offset + i]
	return total / 5.0


func _warden_faces() -> Array:
	if _warden_faces_cache.is_empty():
		var faces: Array = Geom3D.prism_faces(5)
		faces.append([0, 1, 2, 3, 4])
		faces.append([9, 8, 7, 6, 5])
		_warden_faces_cache = faces
	return _warden_faces_cache


func _draw_telegraph() -> void:
	var windup := maxf(0.001, float(e.cfg.get("windup", 0.4)))
	var progress := clampf(e.state_t / windup, 0.0, 1.0)
	# No colour: the telegraph is a blinking high-contrast outline.
	var blink := 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * 34.0))
	var alpha := (0.35 + 0.55 * progress) * blink
	var tint := Color(MathArt.WHITE, alpha)

	if e.kind == "warden":
		match String(e._pending_attack):
			"cleave":
				MathArt.arc(self, Vector2(10, -2), 30.0 + 12.0 * progress, -1.2, 1.2, tint, 3.0)
			"charge":
				MathArt.line(self, Vector2(6, 2), Vector2(6 + 130.0 * progress, 2), tint, 3.0)
			_:
				MathArt.ring(self, Vector2(0, 28), 26.0 + 26.0 * progress, tint, 3.0)
		return
	if e.kind == "charger":
		MathArt.line(self, Vector2(6, -2), Vector2(6 + 40.0 + 70.0 * progress, -2), tint, 3.0)
	elif e.kind == "archer":
		MathArt.ring(self, Vector2(0, -2), _radius() + 8.0 + 6.0 * progress, tint, 2.0)
		_draw_arrow_prediction()
	elif e.kind == "bulwark":
		MathArt.arc(self, Vector2(6, -2), 24.0, -1.1, 1.1, tint, 3.0)
	else:
		MathArt.arc(self, Vector2(4, -2), 24.0, -1.1, 1.1, tint, 3.0)


func _draw_arrow_prediction() -> void:
	var player := Game.player
	if player == null:
		return
	var origin := e.global_position + Vector2(float(e.facing) * _radius(), -2.0)
	var target := player.global_position + Vector2(0, -14)
	var velocity := MathArt.ballistic_velocity(origin, target, float(e.cfg.get("projectile_speed", 320.0)), 700.0)
	for i in 24:
		var time := 0.9 * float(i) / 23.0
		var world := origin + velocity * time + Vector2(0.0, 0.5 * 700.0 * time * time)
		var local := to_local(world)
		local.x *= float(e.facing)
		if i % 2 == 0:
			MathArt.px_rect(self, Rect2(local.x - 1.0, local.y - 1.0, 2.0, 2.0), Color(MathArt.WHITE, 0.35))


func _draw_hit_outline(half_h: float) -> void:
	var radius := _radius() + 2.0
	var sides := _sides()
	var alpha := clampf(e.flash / 0.10, 0.0, 1.0) * 0.7
	if sides == 0:
		MathArt.ring(self, Vector2(0, -2), radius, Color(MathArt.WHITE, alpha), 2.0)
		return
	MathArt.px_poly(self, MathArt.ngon(sides, radius + 2.0, -PI * 0.5, Vector2(0, -2)),
		Color(0, 0, 0, 0), Color(MathArt.WHITE, alpha), 2.0)


func _draw_health_bar(half_h: float) -> void:
	if e.hp >= e.max_hp or e._dead or bool(e.cfg.get("boss", false)):
		return
	var width := 38.0
	var y := -(half_h + 14.0)
	MathArt.px_rect(self, Rect2(-width * 0.5 - 1.0, y - 1.0, width + 2.0, 6.0), Color(0.0, 0.0, 0.0, 0.85))
	var ratio := clampf(e.hp / maxf(e.max_hp, 1.0), 0.0, 1.0)
	MathArt.px_rect(self, Rect2(-width * 0.5, y, width * ratio, 4.0), MathArt.PALE)
	MathArt.px_rect(self, Rect2(-width * 0.5, y, width * ratio, 1.0), MathArt.WHITE)


func _draw_spawn_flash(half_h: float) -> void:
	if e._spawn_t <= 0.0 or e._spawn_t > 0.4:
		return
	var a := clampf(e._spawn_t / 0.4, 0.0, 1.0)
	var radius := 22.0 + 14.0 * (1.0 - a)
	MathArt.ring(self, Vector2(0, -2), radius, Color(MathArt.WHITE, a * 0.55), 2.0)
