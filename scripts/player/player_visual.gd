class_name PlayerVisual
extends Node2D
## The player is a pure geometric sigil: a rotating diamond body, a square
## core and a blade that is literally a line.
##
## Animation follows the action-game read, in this order of importance:
##   1. anticipation — the blade stops for 2 frames before the swing
##   2. smear        — one solid wedge frame on the swing arc
##   3. impact       — handled by the target (white silhouette + hitstop)
##   4. follow-through — the blade overshoots 10-14 degrees, then eases back
##   5. secondary motion — body lags the blade by one frame

const BODY := MathArt.STONE_3
const BODY_DARK := MathArt.STONE_2
const RIM := MathArt.STEEL_HI
const CORE := MathArt.CYAN
const CORE_HI := MathArt.WHITE
const CYAN := MathArt.CYAN
const BLADE := MathArt.STEEL_HI
const GRIP := MathArt.AMBER_DIM

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
var _smear_start := 0.0
var _smear_fired := false


func _ready() -> void:
	p = get_parent() as Player
	z_index = 2


func _process(delta: float) -> void:
	_t += delta
	_update_shadow()
	_update_lag(delta)
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
	_shadow_y = roundf(distance - 2.0)
	var falloff := clampf(1.0 - maxf(0.0, distance - 26.0) / 240.0, 0.0, 1.0)
	_shadow_alpha = 0.14 + 0.34 * falloff
	_shadow_scale = 0.45 + 0.55 * falloff


func _update_lag(delta: float) -> void:
	# Secondary motion: the body reaches its target one frame later than the
	# blade, so the swing reads as weight rather than as a rigid rotation.
	_body_lag = _body_lag.lerp(_body_lag_target, 1.0 - exp(-22.0 * delta))
	_blade_lag_angle = lerp_angle(_blade_lag_angle, _prev_blade_angle, 1.0 - exp(-26.0 * delta))


func _draw() -> void:
	if p == null:
		return
	if _shadow_alpha > 0.0:
		var width := roundf(14.0 * _shadow_scale)
		MathArt.px_rect(self, Rect2(-width, _shadow_y, width * 2.0, 3.0), Color(0.0, 0.0, 0.0, _shadow_alpha))
		MathArt.px_rect(self, Rect2(-width * 0.55, _shadow_y - 1.0, width * 1.1, 1.0), Color(0.0, 0.0, 0.0, _shadow_alpha * 0.7))

	if p.state == Player.State.DEAD:
		_draw_dead()
		return

	var alpha := 1.0
	if p.invuln > 0.0 and fmod(_t * 26.0, 2.0) < 0.85:
		alpha = 0.4

	if p.state == Player.State.ROLL:
		_draw_roll(alpha)
		return

	var speed_ratio := clampf(absf(p.velocity.x) / p.max_speed, 0.0, 1.0)
	var air := not p.is_on_floor()
	var bob := 0.0
	if p.state == Player.State.IDLE:
		bob = roundf(sin(_t * 2.6))
	elif p.state == Player.State.RUN:
		bob = roundf(sin(_t * 16.0) * 1.5 * speed_ratio)

	var lean := 0.0
	if p.state == Player.State.RUN:
		lean = 0.16 * speed_ratio
	elif p.state == Player.State.ATTACK:
		lean = _anticipation_lean()

	draw_set_transform(
		Vector2(roundf(_body_lag.x), roundf(bob + _body_lag.y)),
		lean * float(p.facing),
		Vector2(float(p.facing), 1.0)
	)
	_draw_aegis(alpha)
	_draw_legs(alpha, speed_ratio, air)
	_draw_body(alpha)
	_draw_core(alpha)
	_draw_blade(alpha)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _tint(color: Color, alpha: float) -> Color:
	var out := MathArt.WHITE if p.flash > 0.0 else color
	out.a *= alpha
	return out


# --- Attack phases -----------------------------------------------------------

func _phase() -> Dictionary:
	var cfg := p.attack_cfg
	var windup := maxf(0.001, float(cfg.get("windup", 0.08)))
	var active := maxf(0.001, float(cfg.get("active", 0.07)))
	var recovery := maxf(0.001, float(cfg.get("recovery", 0.2)))
	var t := p.attack_t
	if t < windup:
		return {"name": "windup", "k": t / windup, "windup": windup, "active": active, "recovery": recovery}
	if t < windup + active:
		return {"name": "active", "k": (t - windup) / active, "windup": windup, "active": active, "recovery": recovery}
	return {"name": "recovery", "k": (t - windup - active) / recovery, "windup": windup, "active": active, "recovery": recovery}


func _start_angle() -> float:
	match p.attack_index:
		1:
			return 0.95
		2:
			return -2.95
		_:
			return -2.05


func _end_angle() -> float:
	match p.attack_index:
		1:
			return -2.05
		2:
			return 1.05
		_:
			return 0.80


func _overshoot() -> float:
	return 0.24 if p.attack_index == 2 else 0.17


func _anticipation_angle() -> float:
	# Pull back past the start angle: the extra 0.35 rad is the "coil".
	return _start_angle() - 0.35 * float(p.facing)


func _anticipation_lean() -> float:
	var phase := _phase()
	if phase["name"] == "windup":
		return -0.20 * clampf(float(phase["k"]) * 2.0, 0.0, 1.0)
	return 0.10


func _attack_angle() -> float:
	var phase := _phase()
	var from_angle := _anticipation_angle()
	var to_angle := _end_angle() + _overshoot() * float(p.facing)
	match phase["name"]:
		"windup":
			# Reach the coil in the first 60% of the windup, then HOLD. The hold
			# is what makes the attack readable at 640x360.
			var k := clampf(float(phase["k"]) / 0.6, 0.0, 1.0)
			return lerpf(REST_ANGLE, from_angle, ease(k, 0.6))
		"active":
			# The blade travels during the active window, not during recovery.
			return lerpf(from_angle, to_angle, ease(float(phase["k"]), 0.45))
		_:
			# Overshoot holds for the first ~2 frames, then eases back in three
			# uneven steps (55 / 30 / 15) so it never reads as a linear return.
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
			return lerpf(to_angle, REST_ANGLE, ease(weight, 1.6))


func _smear_window() -> bool:
	var phase := _phase()
	if phase["name"] != "active":
		return false
	# One smear frame for hits 1-2, two for the finisher.
	var limit := 0.55 if p.attack_index == 2 else 0.34
	return float(phase["k"]) <= limit


# --- Body -------------------------------------------------------------------

func _draw_legs(alpha: float, speed_ratio: float, air: bool) -> void:
	var swing := 0.0
	if p.state == Player.State.RUN:
		swing = roundf(sin(_t * 16.0) * 4.0 * speed_ratio)
	var left := Vector2(-4, 8 + swing)
	var right := Vector2(2, 8 - swing)
	if air:
		left = Vector2(-5, 6)
		right = Vector2(3, 9)
	MathArt.px_rect(self, Rect2(left.x, left.y, 3, 8), _tint(BODY_DARK, alpha))
	MathArt.px_rect(self, Rect2(right.x, right.y, 3, 8), _tint(BODY_DARK, alpha))
	MathArt.px_rect(self, Rect2(left.x - 1, left.y + 8, 5, 1), _tint(MathArt.STEEL_DIM, alpha))
	MathArt.px_rect(self, Rect2(right.x - 1, right.y + 8, 5, 1), _tint(MathArt.STEEL_DIM, alpha))


func _draw_body(alpha: float) -> void:
	# Anticipation squash: the diamond compresses along the swing axis.
	var squash := 1.0
	if p.state == Player.State.ATTACK and _phase()["name"] == "windup":
		squash = 0.86
	var half_w := roundf(11.0 * squash)
	var diamond := PackedVector2Array([
		Vector2(0, -20), Vector2(half_w, -4), Vector2(0, 12), Vector2(-half_w, -4),
	])
	MathArt.px_poly(self, diamond, _tint(BODY, alpha), _tint(RIM, alpha * 0.45), 1.0)
	var facet := PackedVector2Array([
		Vector2(0, -14), Vector2(roundf(half_w * 0.55), -4), Vector2(0, 6), Vector2(-roundf(half_w * 0.55), -4),
	])
	MathArt.px_poly(self, facet, _tint(BODY_DARK, alpha * 0.85))
	MathArt.px_line(self, Vector2(-half_w, -4), Vector2(0, 12), _tint(MathArt.INK, alpha * 0.5), 1.0)
	MathArt.px_rect(self, Rect2(7, -9, 2, 2), _tint(MathArt.AMBER, alpha * 0.9))
	MathArt.px_rect(self, Rect2(-9, -9, 2, 2), _tint(MathArt.AMBER, alpha * 0.45))


func _draw_core(alpha: float) -> void:
	var pulse := 0.75 + 0.25 * sin(_t * 6.0)
	MathArt.px_rect(self, Rect2(-2, -6, 5, 5), _tint(MathArt.INK, alpha))
	MathArt.px_rect(self, Rect2(-1, -5, 3, 3), _tint(CORE, alpha * pulse))
	MathArt.px_rect(self, Rect2(0, -4, 1, 1), _tint(CORE_HI, alpha))
	if pulse > 0.92:
		MathArt.px_ring(self, Vector2(0, -4), 7.0, _tint(CORE, alpha * 0.20), 1.0)


# --- Blade ------------------------------------------------------------------

func _draw_blade(alpha: float) -> void:
	var hand := Vector2(6, -8)
	var angle := REST_ANGLE
	if p.state == Player.State.ATTACK:
		hand = Vector2(7, -10)
		angle = _attack_angle()
	elif p.state == Player.State.RUN:
		angle = REST_ANGLE + sin(_t * 16.0) * 0.10
	else:
		angle = REST_ANGLE + sin(_t * 2.6) * 0.05
	_prev_blade_angle = angle

	MathArt.px_line(self, Vector2(3, -12), hand, _tint(BODY_DARK, alpha), 2.0)
	MathArt.px_rect(self, Rect2(hand.x - 1, hand.y - 1, 3, 3), _tint(MathArt.PALE, alpha))

	var direction := Vector2.from_angle(angle)
	var tip := hand + direction * 21.0
	var side := direction.orthogonal() * 1.5

	# Trailing tip ghost: one frame of lag reads as weight.
	if p.state == Player.State.ATTACK:
		var lag_dir := Vector2.from_angle(_blade_lag_angle)
		var lag_tip := hand + lag_dir * 19.0
		MathArt.px_rect(self, Rect2(roundf(lag_tip.x), roundf(lag_tip.y), 1, 1), Color(BLADE, alpha * 0.35))

	MathArt.px_line(self, hand + direction * 3.0, tip, _tint(BLADE, alpha), 2.0)
	MathArt.px_line(self, hand + direction * 3.0 + side, tip, _tint(MathArt.WHITE, alpha * 0.5), 1.0)
	MathArt.px_line(self, hand + side * 3.0, hand - side * 3.0, _tint(GRIP, alpha), 2.0)
	MathArt.px_line(self, hand - direction * 4.0, hand, _tint(GRIP, alpha), 2.0)
	MathArt.px_rect(self, Rect2(tip.x - 1, tip.y - 1, 2, 2), _tint(MathArt.WHITE, alpha * 0.8))

	if p.state == Player.State.ATTACK:
		_draw_smear(alpha, hand)


func _draw_smear(alpha: float, hand: Vector2) -> void:
	if not _smear_window():
		return
	var phase := _phase()
	var current := _attack_angle()
	# The wedge spans from the angle the blade had at the start of the active
	# window to its current angle.
	var k := clampf(float(phase["k"]) / (0.55 if p.attack_index == 2 else 0.34), 0.0, 1.0)
	var from_angle := lerpf(_anticipation_angle(), _end_angle() + _overshoot() * float(p.facing), 0.0)
	var span := current - from_angle
	if absf(span) < 0.10:
		return
	var radius := 21.0
	# Solid wedge (not thin lines): this is what reads as a smear.
	var wedge := PackedVector2Array([hand])
	var steps := 9
	for i in steps + 1:
		var a := lerpf(from_angle, current, float(i) / float(steps))
		wedge.append(hand + Vector2.from_angle(a) * radius)
	MathArt.px_poly(self, wedge, Color(CYAN, alpha * 0.55 * (1.0 - k * 0.35)), Color(0, 0, 0, 0))
	# A 1px white leading edge on the wedge's outer arc.
	MathArt.px_arc(self, hand, radius, from_angle, current, Color(MathArt.WHITE, alpha * 0.85), 1.0)
	# Ghost of the previous frame at 35% alpha.
	var ghost_from := lerpf(from_angle, current, -0.35)
	MathArt.px_arc(self, hand, radius - 2.0, ghost_from, from_angle, Color(CYAN, alpha * 0.35), 2.0)
	var edge := hand + Vector2.from_angle(current) * (radius + 3.0)
	MathArt.px_rect(self, Rect2(roundf(edge.x) - 1.0, roundf(edge.y) - 1.0, 3, 3), Color(MathArt.WHITE, alpha * 0.9))


func _draw_aegis(alpha: float) -> void:
	if p.aegis_t <= 0.0:
		return
	var life_k := clampf(p.aegis_t / p.aegis_time, 0.0, 1.0)
	var center := Vector2(0, -6)
	for ring in 3:
		var radius := 26.0 + float(ring) * 5.0
		var wobble := sin(_t * 7.0 + float(ring) * 0.8) * 1.5
		MathArt.px_ring(self, center, radius + wobble, Color(CYAN, alpha * life_k * (0.42 - float(ring) * 0.10)), 1.0)
	for i in 6:
		var angle := _t * 2.6 + TAU * float(i) / 6.0
		var point := center + Vector2.from_angle(angle) * (30.0 + float(i % 2) * 4.0)
		MathArt.px_rect(self, Rect2(roundf(point.x), roundf(point.y), 2, 2), Color(CYAN, alpha * life_k * 0.9))


# --- Roll / death -----------------------------------------------------------

func _draw_roll(alpha: float) -> void:
	var k := clampf(p.roll_t / p.roll_time, 0.0, 1.0)
	var spin := -k * TAU * 1.25
	draw_set_transform(Vector2(0, 0), spin * float(p.facing), Vector2(float(p.facing), 1.0))
	var diamond := PackedVector2Array([
		Vector2(0, -13), Vector2(12, 0), Vector2(0, 13), Vector2(-12, 0),
	])
	MathArt.px_poly(self, diamond, _tint(BODY, alpha), _tint(CYAN, alpha * 0.55), 1.0)
	MathArt.px_rect(self, Rect2(-2, -2, 4, 4), _tint(CORE, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in 4:
		var offset := Vector2(-float(p.facing) * (14.0 + float(i) * 7.0), -3.0 + float(i) * 2.0)
		var size := 3 - i
		MathArt.px_rect(self, Rect2(offset.x, offset.y, size, size), Color(CYAN, alpha * 0.22 * (1.0 - float(i) * 0.22)))

	# i-frame cue: a 1px white outline only on the first and last frame of the
	# invulnerable window. A continuous glow would hide the timing.
	var in_iframes := p.roll_t >= p.roll_iframe_start and p.roll_t <= p.roll_iframe_end
	if in_iframes:
		var since := p.roll_t - p.roll_iframe_start
		var until := p.roll_iframe_end - p.roll_t
		if since < 0.034 or until < 0.034:
			MathArt.px_ring(self, Vector2(0, 0), 15.0, Color(MathArt.WHITE, alpha * 0.9), 1.0)


func _draw_dead() -> void:
	for i in 3:
		var center := Vector2(-9.0 + float(i) * 9.0, -2.0 - float(i) * 3.0)
		var points := MathArt.ngon(3, 5.0 - float(i), float(i) * 0.9, center)
		MathArt.px_poly(self, points, Color(BODY_DARK, 0.9), Color(MathArt.AMBER_DIM, 0.4), 1.0)
	MathArt.px_rect(self, Rect2(-16, -6, 3, 3), Color(CORE, 0.6))
