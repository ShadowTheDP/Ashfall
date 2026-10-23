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
# The sword rests pointing UP and slightly forward. Godot's +y is down, so an
# upward angle is negative. Facing right: -1.30 rad is up-and-forward.
const REST_ANGLE := -1.30

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
	# Pure flat 2D: the square never deforms. Weight is carried by rotation,
	# shadow size, particles and camera, not by scaling the silhouette.
	return Vector2.ONE


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
	# Angles are authored facing right; -PI/2 points straight up.
	match p.attack_index:
		1:
			return -2.55
		2:
			return -2.95
		_:
			return -2.30


func _end_angle() -> float:
	match p.attack_index:
		1:
			return 0.35
		2:
			return 0.95
		_:
			return 0.20


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
	# Grip sits in the LOWER half of the square, on the front edge.
	var hand := Vector2(float(p.facing) * HALF, 4.0)
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
	var side := direction.orthogonal()
	var tip := hand + direction * length

	# The hand is a DOT, not a limb.
	MathArt.disc(self, hand, 3.2, _tint(HAND, alpha))

	# Blade: ONE tapered quad. Two offset lines read as two parallel rods and
	# together with the guard they form an "L" at this scale - never do that.
	var base := hand + direction * 3.0
	var base_half := 2.1
	var tip_half := 0.35
	var blade := PackedVector2Array([
		base + side * base_half,
		tip + side * tip_half,
		tip - side * tip_half,
		base - side * base_half,
	])
	MathArt.px_poly(self, blade, _tint(BLADE, alpha), _tint(MathArt.WHITE, alpha * 0.35), 1.0)

	# A single bright edge along ONE side only, so it reads as a bevel rather
	# than a second blade.
	MathArt.line(self, base + side * (base_half - 0.4), tip, _tint(MathArt.WHITE, alpha * 0.75), 1.0)

	# Guard: a short bar perpendicular to the blade, centred on the grip and
	# kept SHORT so it cannot form an "L" with the blade.
	MathArt.line(self, hand + side * 3.0, hand - side * 3.0, _tint(MathArt.MID, alpha), 2.0)
	# Pommel: a 1px dot behind the grip.
	MathArt.disc(self, hand - direction * 3.0, 1.6, _tint(MathArt.MID, alpha))

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
	var swing := signf(current - coil)
	var travelled := absf(current - coil)
	var trail := clampf(travelled * 0.40, 0.30, 1.20)
	var from_angle := current - swing * trail
	if absf(current - from_angle) < 0.15:
		return
	var radius := length
	var fade := 1.0 - k * 0.30

	# There is deliberately NO continuous arc. Any unbroken curve at this
	# radius reads as a crescent "mooncake". Instead the swing is drawn as a
	# set of DISCONNECTED straight streaks at different radii, each tangent to
	# the blade's path. Disconnected straight lines cannot form a shape; they
	# only read as motion.
	#
	# Each streak: start on the arc, run along the tangent, taper, fade.
	var tangent := Vector2.from_angle(current + swing * PI * 0.5)
	var rows := 4
	for row in rows:
		var radius_k := lerpf(0.55, 1.02, float(row) / float(rows - 1))
		var row_radius := radius * radius_k
		# Inner rows lag further behind the tip.
		var row_lag := lerpf(0.72, 0.0, float(row) / float(rows - 1))
		var anchor_angle := current - swing * trail * row_lag
		var pieces := 3
		for piece in pieces:
			var piece_k := float(piece) / float(pieces - 1)
			var a := anchor_angle - swing * trail * 0.22 * piece_k
			var start_p := hand + Vector2.from_angle(a) * row_radius
			var seg := lerpf(20.0, 7.0, piece_k) * lerpf(0.55, 1.0, radius_k)
			var end_p := start_p + tangent * seg * swing
			var strength := alpha * fade * lerpf(0.75, 0.25, piece_k) * lerpf(0.55, 1.0, radius_k)
			MathArt.line(self, start_p, end_p, Color(MathArt.WHITE, strength),
				lerpf(2.4, 1.0, piece_k))
			if piece == 0:
				MathArt.px_rect(self, Rect2(end_p.x - 1.0, end_p.y - 1.0, 2.0, 2.0),
					Color(MathArt.WHITE, strength))

	# The leading tip streak: longest, brightest, exactly along the blade.
	var tip_dir := Vector2.from_angle(current)
	var tip_start := hand + tip_dir * radius
	var tip_end := tip_start + tangent * 26.0 * swing
	MathArt.line(self, tip_start, tip_end, Color(MathArt.WHITE, alpha * 0.95), 3.0)
	MathArt.line(self, tip_start, tip_end, Color(MathArt.WHITE, alpha), 1.0)

	# Golden-angle dots sampled along the blade path: the math accent.
	for i in 3:
		var t := 0.20 + float(i) * 0.30
		if t > 1.0:
			continue
		var a := lerpf(from_angle, current, t)
		var point := hand + Vector2.from_angle(a) * (radius * 0.60)
		MathArt.disc(self, point, 1.5, Color(MathArt.WHITE, alpha * fade * 0.55))

	# Tip lag dot: the blade tip trails the body by one frame.
	var lag_dir := Vector2.from_angle(_blade_lag_angle)
	MathArt.disc(self, hand + lag_dir * (radius - 2.0), 2.0, Color(MathArt.LIGHT, alpha * 0.45))


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
