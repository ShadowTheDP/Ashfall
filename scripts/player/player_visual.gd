class_name PlayerVisual
extends Node2D
## The player is a SQUARE. No legs. No arms. The hand is a single dot.
##
## All character is carried by motion:
##   run      lean + footfall squash (2 frames on contact)
##   jump     takeoff squash, one 90-degree tumble, apex hang
##   land     squash 2 frames, then a 4-frame settle
##   roll     360-degree spin with afterimages
##   attack   anticipation coil, solid smear, overshoot, one-frame lag
##   hurt     12-degree tilt + squash
##
## The square is deliberately plain: no notch, no pip, no eyes. The tumble
## itself is what communicates the face change.

const BODY := MathArt.WHITE
const FACE := MathArt.INK
const RIM := MathArt.BLACK
const HAND := MathArt.WHITE
const BLADE := MathArt.WHITE

const HALF := 13.0
const REST_ANGLE := 0.62

var p: Player
var _t := 0.0
var _shadow_y := 24.0
var _shadow_alpha := 0.0
var _shadow_scale := 1.0
var _prev_blade_angle := REST_ANGLE
var _blade_lag_angle := REST_ANGLE
var _body_lag := Vector2.ZERO
var _body_lag_target := Vector2.ZERO


func _ready() -> void:
	p = get_parent() as Player
	z_index = 2


func _process(delta: float) -> void:
	_t += delta
	_update_shadow()
	_body_lag = _body_lag.lerp(_body_lag_target, 1.0 - exp(-24.0 * delta))
	_blade_lag_angle = lerp_angle(_blade_lag_angle, _prev_blade_angle, 1.0 - exp(-28.0 * delta))
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
	var falloff := clampf(1.0 - maxf(0.0, distance - 28.0) / 300.0, 0.0, 1.0)
	_shadow_alpha = 0.16 + 0.34 * falloff
	_shadow_scale = 0.45 + 0.55 * falloff


func _draw() -> void:
	if p == null:
		return
	if _shadow_alpha > 0.0:
		# The shadow is the only ground reference: it shrinks with height.
		var w := 15.0 * _shadow_scale
		MathArt.px_rect(self, Rect2(-w, _shadow_y, w * 2.0, 4.0), Color(0.0, 0.0, 0.0, _shadow_alpha))
		MathArt.px_rect(self, Rect2(-w * 0.6, _shadow_y - 1.0, w * 1.2, 2.0), Color(0.0, 0.0, 0.0, _shadow_alpha * 0.6))

	if p.state == Player.State.DEAD:
		_draw_dead()
		return

	var alpha := 1.0
	if p.invuln > 0.0 and fmod(_t * 26.0, 2.0) < 0.85:
		alpha = 0.45

	if p.state == Player.State.ROLL:
		_draw_roll(alpha)
		return

	_draw_body(alpha)
	_draw_hand_and_blade(alpha)


# --- Body -------------------------------------------------------------------

func _body_rotation() -> float:
	if p.state == Player.State.ATTACK:
		# Slight wind-up twist, released during the swing.
		var phase := _attack_phase()
		if phase["name"] == "windup":
			return -0.22 * float(p.facing) * clampf(float(phase["k"]) * 2.0, 0.0, 1.0)
		return 0.16 * float(p.facing)
	var angle := lerpf(p.tumble_from, p.tumble_to, smoothstep(0.0, 1.0, clampf(p.tumble, 0.0, 1.0)))
	if p.state == Player.State.RUN:
		# Footfall rotation: the square rocks on its corners.
		angle += sin(_t * 15.0) * 0.10
	return angle


func _body_scale() -> Vector2:
	var s := p.squash
	# Preserve area: wide means short.
	var sx := 1.0 + (s - 1.0) * 0.85
	var sy := 1.0 - (s - 1.0) * 0.85
	if not p.is_on_floor():
		# Stretch with vertical speed while airborne.
		var stretch := clampf(absf(p.velocity.y) / 900.0, 0.0, 1.0) * 0.12
		sy += stretch
		sx -= stretch * 0.6
	return Vector2(sx, sy)


func _draw_body(alpha: float) -> void:
	var bob := 0.0
	if p.state == Player.State.IDLE:
		bob = sin(_t * 2.6) * 1.2
	elif p.state == Player.State.RUN:
		bob = absf(sin(_t * 15.0)) * -2.0

	var lean := 0.0
	if p.state == Player.State.RUN:
		lean = 0.14 * clampf(absf(p.velocity.x) / p.max_speed, 0.0, 1.0) * float(p.facing)

	draw_set_transform(
		Vector2(_body_lag.x, bob + _body_lag.y),
		_body_rotation() + lean,
		_body_scale() * Vector2(float(p.facing), 1.0)
	)

	# Outer square: the whole silhouette.
	var outer := Rect2(-HALF, -HALF, HALF * 2.0, HALF * 2.0)
	MathArt.px_rect(self, outer, _tint(BODY, alpha))
	# Hard 2px keyline so it stays readable over any background.
	draw_rect(outer, Color(RIM, alpha * 0.9), false, 2.0)

	# Inner face: a black inset square. This is the "hollow cube" read.
	var inset := 5.5
	MathArt.px_rect(self, Rect2(-HALF + inset, -HALF + inset, (HALF - inset) * 2.0, (HALF - inset) * 2.0),
		Color(FACE, alpha * 0.92))

	# The core: a white dot in the black face, pulsing.
	var pulse := 0.72 + 0.28 * sin(_t * 6.0)
	MathArt.disc(self, Vector2.ZERO, 2.6 * pulse, _tint(MathArt.WHITE, alpha))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_aegis(alpha)


func _tint(color: Color, alpha: float) -> Color:
	var out := MathArt.WHITE if p.flash > 0.0 else color
	out.a *= alpha
	return out


# --- Hand and blade ---------------------------------------------------------

func _attack_phase() -> Dictionary:
	var cfg := p.attack_cfg
	var windup := maxf(0.001, float(cfg.get("windup", 0.08)))
	var active := maxf(0.001, float(cfg.get("active", 0.07)))
	var recovery := maxf(0.001, float(cfg.get("recovery", 0.2)))
	var t := p.attack_t
	if t < windup:
		return {"name": "windup", "k": t / windup}
	if t < windup + active:
		return {"name": "active", "k": (t - windup) / active}
	return {"name": "recovery", "k": (t - windup - active) / recovery}


func _start_angle() -> float:
	match p.attack_index:
		1:
			return 1.05
		2:
			return -3.05
		_:
			return -2.15


func _end_angle() -> float:
	match p.attack_index:
		1:
			return -2.15
		2:
			return 1.15
		_:
			return 0.85


func _overshoot() -> float:
	return 0.26 if p.attack_index == 2 else 0.18


func _coil_angle() -> float:
	return _start_angle() - 0.38 * float(p.facing)


func _mirror(angle: float) -> float:
	# Angles are authored facing right; mirror around the vertical axis.
	return angle if p.facing > 0 else (PI - angle)


func _blade_angle() -> float:
	var phase := _attack_phase()
	var rest := REST_ANGLE if p.facing > 0 else PI - REST_ANGLE
	var coil := _coil_angle()
	var to_angle := _end_angle() + _overshoot() * float(p.facing)
	if p.facing < 0:
		to_angle = PI - (_end_angle() - _overshoot())
	match phase["name"]:
		"windup":
			var k := clampf(float(phase["k"]) / 0.55, 0.0, 1.0)
			return lerpf(rest, coil, ease(k, 0.55))
		"active":
			return lerpf(coil, to_angle, ease(float(phase["k"]), 0.42))
		_:
			var k := clampf(float(phase["k"]), 0.0, 1.0)
			if k < 0.08:
				return to_angle
			var stepped := k - 0.08
			var weight := 0.0
			if stepped < 0.18:
				weight = lerpf(0.0, 0.55, stepped / 0.18)
			elif stepped < 0.55:
				weight = lerpf(0.55, 0.85, (stepped - 0.18) / 0.37)
			else:
				weight = lerpf(0.85, 1.0, clampf((stepped - 0.55) / 0.45, 0.0, 1.0))
			return lerpf(to_angle, rest, ease(weight, 1.6))


func _blade_length() -> float:
	# The blade length is authored in data/weapons.json next to the hitbox, so
	# the drawn blade and the damage box can never drift apart.
	if p.attack_cfg.has("blade"):
		return float(p.attack_cfg["blade"])
	return 38.0


func _draw_hand_and_blade(alpha: float) -> void:
	# The grip sits on the FRONT EDGE of the square, mirrored by facing, so the
	# sword never appears to start inside the body.
	var hand := Vector2(float(p.facing) * HALF, -7.0)
	var angle := REST_ANGLE
	if p.state == Player.State.ATTACK:
		angle = _blade_angle()
	elif p.state == Player.State.RUN:
		angle = REST_ANGLE + sin(_t * 15.0) * 0.10
	else:
		angle = REST_ANGLE + sin(_t * 2.6) * 0.06
	_prev_blade_angle = angle

	var length := _blade_length()
	var direction := Vector2.from_angle(angle)
	var tip := hand + direction * length
	var side := direction.orthogonal()

	# The hand is a DOT, not a limb.
	MathArt.disc(self, hand, 3.2, _tint(HAND, alpha))

	# Blade: a 2px core with a 1px highlight, tapering to a point.
	MathArt.line(self, hand + direction * 3.0, tip, _tint(BLADE, alpha), 2.0)
	MathArt.line(self, hand + direction * 3.0 + side, tip, _tint(MathArt.WHITE, alpha * 0.5), 1.0)
	# Cross guard: two 1px ticks.
	MathArt.line(self, hand + side * 4.0, hand - side * 4.0, _tint(MathArt.MID, alpha), 2.0)

	if p.state == Player.State.ATTACK:
		_draw_smear(alpha, hand, length)


func _draw_smear(alpha: float, hand: Vector2, length: float) -> void:
	var phase := _attack_phase()
	if phase["name"] != "active":
		return
	var limit := 0.55 if p.attack_index == 2 else 0.34
	var k := clampf(float(phase["k"]) / limit, 0.0, 1.0)
	if k > 1.0:
		return
	var current := _blade_angle()
	var coil := _coil_angle()
	# The smear is a TRAIL, not the whole swing. It spans the last ~35% of the
	# arc travelled so far, which keeps it to roughly 60-90 degrees instead of
	# wrapping into a full ring.
	var travelled := absf(current - coil)
	var trail := clampf(travelled * 0.38, 0.25, 1.15)
	var from_angle := current - signf(current - coil) * trail
	if absf(current - from_angle) < 0.12:
		return
	var radius := length
	var fade := 1.0 - k * 0.35

	# A CRESCENT, not a pie wedge. The inner edge sits at 55% of the blade
	# length, so the smear reads as the path of the blade rather than as a
	# filled disc. Three nested crescents build volume without a gradient.
	_draw_crescent(hand, from_angle, current, radius, radius * 0.42,
		Color(MathArt.WHITE, alpha * 0.20 * fade))
	_draw_crescent(hand, from_angle, current, radius, radius * 0.66,
		Color(MathArt.WHITE, alpha * 0.30 * fade))
	_draw_crescent(hand, from_angle, current, radius, radius * 0.86,
		Color(MathArt.WHITE, alpha * 0.40 * fade))

	# Leading edge: the blade's own path, bright and thin.
	MathArt.arc(self, hand, radius, from_angle, current, Color(MathArt.WHITE, alpha * 0.95), 3.0)
	MathArt.arc(self, hand, radius, from_angle, current, Color(MathArt.WHITE, alpha), 1.0)

	# The blade's previous position, one frame behind: a 35% ghost.
	var ghost_from := lerpf(from_angle, current, -0.45)
	MathArt.arc(self, hand, radius - 3.0, ghost_from, from_angle,
		Color(MathArt.LIGHT, alpha * 0.40), 2.0)

	# Motion lines behind the tip: the cheapest, clearest "speed" cue.
	for i in 3:
		var back := lerpf(0.16, 0.44, float(i) / 2.0)
		var a := lerpf(current, from_angle, back)
		var from_p := hand + Vector2.from_angle(a) * radius
		var to_p := hand + Vector2.from_angle(a) * (radius + 7.0 + float(i) * 4.0)
		MathArt.line(self, from_p, to_p, Color(MathArt.WHITE, alpha * (0.6 - float(i) * 0.16)), 1.0)

	# Tip lag dot: the blade tip trails the body by one frame.
	var lag_dir := Vector2.from_angle(_blade_lag_angle)
	MathArt.disc(self, hand + lag_dir * (radius - 3.0), 2.0, Color(MathArt.LIGHT, alpha * 0.4))


func _draw_crescent(hand: Vector2, from_angle: float, to_angle: float, outer: float, inner: float, color: Color) -> void:
	var steps := 12
	var points := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		var a := lerpf(from_angle, to_angle, t)
		# Taper the outer radius at both ends so the crescent has points.
		var taper := sin(t * PI)
		points.append(hand + Vector2.from_angle(a) * lerpf(inner + (outer - inner) * 0.35, outer, taper))
	for i in range(steps, -1, -1):
		var t := float(i) / float(steps)
		var a := lerpf(from_angle, to_angle, t)
		points.append(hand + Vector2.from_angle(a) * inner)
	MathArt.px_poly(self, points, color)


func _draw_aegis(alpha: float) -> void:
	if p.aegis_t <= 0.0:
		return
	var life_k := clampf(p.aegis_t / p.aegis_time, 0.0, 1.0)
	for ring_index in 3:
		var radius := 30.0 + float(ring_index) * 5.0
		var wobble := sin(_t * 7.0 + float(ring_index) * 0.8) * 1.8
		MathArt.ring(self, Vector2.ZERO, radius + wobble,
			Color(MathArt.WHITE, alpha * life_k * (0.55 - float(ring_index) * 0.14)), 1.5)
	for i in 6:
		var a := _t * 2.6 + TAU * float(i) / 6.0
		MathArt.disc(self, Vector2.from_angle(a) * (34.0 + float(i % 2) * 5.0), 1.8,
			Color(MathArt.WHITE, alpha * life_k * 0.85))


# --- Roll / death -----------------------------------------------------------

func _draw_roll(alpha: float) -> void:
	var k := clampf(p.roll_t / p.roll_time, 0.0, 1.0)
	var spin := -k * TAU * 1.35
	draw_set_transform(Vector2.ZERO, spin * float(p.facing), Vector2(float(p.facing), 1.0))
	var outer := Rect2(-HALF + 2.0, -HALF + 2.0, (HALF - 2.0) * 2.0, (HALF - 2.0) * 2.0)
	MathArt.px_rect(self, outer, _tint(BODY, alpha))
	draw_rect(outer, Color(RIM, alpha * 0.9), false, 2.0)
	MathArt.px_rect(self, Rect2(-4.0, -4.0, 8.0, 8.0), Color(FACE, alpha * 0.9))
	MathArt.disc(self, Vector2.ZERO, 2.0, Color(MathArt.WHITE, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# i-frame cue: only on the first and last frame of the window.
	if p.roll_t >= p.roll_iframe_start and p.roll_t <= p.roll_iframe_end:
		var since := p.roll_t - p.roll_iframe_start
		var until := p.roll_iframe_end - p.roll_t
		if since < 0.030 or until < 0.030:
			MathArt.ring(self, Vector2.ZERO, 19.0, Color(MathArt.WHITE, alpha * 0.95), 2.0)


func _draw_dead() -> void:
	# The square breaks into four quarter-squares.
	for i in 4:
		var ox := -HALF * 0.5 if i % 2 == 0 else HALF * 0.5
		var oy := -HALF * 0.5 if i < 2 else HALF * 0.5
		var drift := Vector2(ox, oy) * 1.6 + Vector2(0, float(i) * 2.0)
		MathArt.px_rect(self, Rect2(drift.x - HALF * 0.45, drift.y - HALF * 0.45, HALF * 0.9, HALF * 0.9),
			Color(MathArt.MID, 0.85))
