class_name WeaponVisual
extends Node2D
## Draws the blade for whichever weapon is equipped. Cheap and stateless
## apart from a time counter: no children, no tweens, no textures, no state
## machine. The player visual owns the pose; this node only owns the shape.
##
## Why every shape is ONE silhouette: the old blade read as an "L" because it
## was two parallel lines plus a perpendicular guard. A tapered quad, a curved
## sliver, a lens, a jagged quad and a chain of short quads all read as a
## single object. Two parallel strokes never do.
##
## Why the pose is cached: Godot only allows draw_* during an item's own draw
## pass, so draw_blade() stores the frame's pose and the geometry is emitted in
## _draw(). A parent draws before its children in the same frame, so calling
## this from the player visual's _draw() still shows the current pose.

const GRIP := 3.0          # the blade starts this far from the hand centre
const BASE_HALF := 2.1     # half-width at the grip (matches the old sword)
const TIP_HALF := 0.35
const GUARD_HALF := 3.0
const POMMEL := 1.6
const CURVE_ARC := 0.45    # radians of spine curvature for "curve"
const CHAIN_LINKS := 5
const CHAIN_SAG := 0.28    # px of droop per link^2
const CHAIN_GAP := 1.6     # px of dark joint either side of a link
const ORBIT_RATE := 3.0    # rad/s

var _t := 0.0
var _shape := "edge"
var _hand := Vector2.ZERO
var _angle := 0.0
var _length := 38.0
var _alpha := 1.0
var _posed := false


## Picks the silhouette from the weapon table. Unknown ids fall back to the
## sword, so a data typo shows a blade instead of nothing.
func setup(weapon_id: String) -> void:
	var cfg: Dictionary = Data.weapons.get(weapon_id, {})
	_shape = str(cfg.get("shape", "edge"))
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	# Only the player visual's _draw() poses the blade, and it stops posing while
	# rolling or dead. Without this the cached pose keeps rendering and the blade
	# hangs in mid-air next to the spinning square.
	if _posed:
		_posed = false
		queue_redraw()


func draw_blade(hand: Vector2, angle: float, length: float, alpha: float) -> void:
	_hand = hand
	_angle = angle
	_length = maxf(GRIP + 1.0, length)
	_alpha = alpha
	_posed = true
	queue_redraw()


func _draw() -> void:
	if not _posed or _alpha <= 0.0:
		return
	match _shape:
		"curve":
			_draw_curve()
		"lens":
			_draw_lens()
		"fractal":
			_draw_fractal()
		"chain":
			_draw_chain()
		"orbit":
			_draw_orbit()
		_:
			_draw_edge()


## Where the blade actually ends. Same math as the draw pass, so the tip marker
## and the drawn blade can never drift apart.
func blade_tip(hand: Vector2, angle: float, length: float) -> Vector2:
	var dir := Vector2.from_angle(angle)
	match _shape:
		"curve":
			var side := dir.orthogonal()
			var radius := (length - GRIP) / CURVE_ARC
			return hand + dir * GRIP - side * radius + (side * radius).rotated(CURVE_ARC)
		"chain":
			var sag := CHAIN_SAG * float(CHAIN_LINKS * CHAIN_LINKS)
			return hand + dir * length - dir.orthogonal() * sag
		"orbit":
			return hand + Vector2.from_angle(angle + _t * ORBIT_RATE + PI) * length
		_:
			return hand + dir * length


# --- Shapes -----------------------------------------------------------------

## The sword that already works: one tapered quad, one bevel, a short guard.
func _draw_edge() -> void:
	var dir := Vector2.from_angle(_angle)
	var side := dir.orthogonal()
	var base := _hand + dir * GRIP
	var tip := _hand + dir * _length
	MathArt.poly(self, _taper(base, tip, side, BASE_HALF, TIP_HALF),
		_tone(1.0), _tone(0.35), 1.0)
	MathArt.line(self, base + side * (BASE_HALF - 0.4), tip, _tone(0.75), 1.0)
	_draw_fittings(dir, side)


## Same taper, but the spine is a circular arc, so the sliver is bent.
func _draw_curve() -> void:
	var dir := Vector2.from_angle(_angle)
	var side := dir.orthogonal()
	var radius := (_length - GRIP) / CURVE_ARC
	# Centre on the far side of the blade, so the arc sweeps FORWARD from the
	# grip and the tip leads the swing instead of trailing it.
	var center := _hand + dir * GRIP - side * radius
	var mid := center + (side * radius).rotated(CURVE_ARC * 0.5)
	var tip := center + (side * radius).rotated(CURVE_ARC)
	var n_mid := side.rotated(CURVE_ARC * 0.5)
	var w_mid := lerpf(BASE_HALF, TIP_HALF, 0.5) * 1.4
	var points := PackedVector2Array([
		_hand + dir * GRIP + side * BASE_HALF,
		mid + n_mid * w_mid,
		tip,
		mid - n_mid * w_mid,
		_hand + dir * GRIP - side * BASE_HALF,
	])
	MathArt.poly(self, points, _tone(1.0), _tone(0.35), 1.0)
	# The bevel follows the spine instead of chording across the bend.
	var bevel_mid := mid + n_mid * (w_mid - 0.4)
	MathArt.line(self, _hand + dir * GRIP + side * (BASE_HALF - 0.4), bevel_mid, _tone(0.7), 1.0)
	MathArt.line(self, bevel_mid, tip, _tone(0.7), 1.0)
	_draw_fittings(dir, side)


## Two arcs meeting at a point: fat in the middle, sharp at BOTH ends.
func _draw_lens() -> void:
	var dir := Vector2.from_angle(_angle)
	var side := dir.orthogonal()
	var base := _hand + dir * GRIP
	var tip := _hand + dir * _length
	var fat := BASE_HALF * 1.5
	var segments := 8
	var points := PackedVector2Array([base])
	for i in range(1, segments):
		var k := float(i) / float(segments)
		points.append(base.lerp(tip, k) + side * _lens_width(fat, k))
	points.append(tip)
	for i in range(segments - 1, 0, -1):
		var k := float(i) / float(segments)
		points.append(base.lerp(tip, k) - side * _lens_width(fat, k))
	MathArt.poly(self, points, _tone(1.0), _tone(0.45), 1.0)
	_draw_fittings(dir, side)


## A tapered quad whose two edges are themselves subdivided and jittered.
func _draw_fractal() -> void:
	var dir := Vector2.from_angle(_angle)
	var side := dir.orthogonal()
	var base := _hand + dir * GRIP
	var tip := _hand + dir * _length
	var segments := 5
	var points := PackedVector2Array()
	for i in range(segments + 1):
		var k := float(i) / float(segments)
		var jag := 0.0 if i == segments else (0.7 if i % 2 == 1 else -0.7)
		points.append(base.lerp(tip, k) + side * (lerpf(BASE_HALF, TIP_HALF, k) + jag))
	for i in range(segments, -1, -1):
		var k := float(i) / float(segments)
		var jag := 0.0 if i == segments else (0.7 if i % 2 == 1 else -0.7)
		points.append(base.lerp(tip, k) - side * (lerpf(BASE_HALF, TIP_HALF, k) + jag))
	MathArt.poly(self, points, _tone(1.0), _tone(0.4), 1.0)
	_draw_fittings(dir, side)


## Five short tapered quads, each sagging further than the last, joined by dots.
func _draw_chain() -> void:
	var dir := Vector2.from_angle(_angle)
	var side := dir.orthogonal()
	var span := _length - GRIP
	var joints := PackedVector2Array()
	for i in range(CHAIN_LINKS + 1):
		var k := float(i) / float(CHAIN_LINKS)
		var sag := CHAIN_SAG * float(i * i)
		joints.append(_hand + dir * (GRIP + span * k) - side * sag)
	for i in CHAIN_LINKS:
		var w0 := lerpf(BASE_HALF, 0.5, float(i) / float(CHAIN_LINKS))
		var w1 := lerpf(BASE_HALF, 0.5, float(i + 1) / float(CHAIN_LINKS))
		# The gap is what makes the chain read as links instead of one blade.
		var from_point := joints[i] + dir * CHAIN_GAP
		var to_point := joints[i + 1] - dir * CHAIN_GAP
		MathArt.poly(self, _taper(from_point, to_point, side, w0, w1),
			_tone(1.0), _tone(0.3), 1.0)
	for i in range(1, CHAIN_LINKS):
		MathArt.disc(self, joints[i], 1.5, _tone(0.85))
	_draw_fittings(dir, side)


## Two small blades on opposite phases. The trailing one is dimmer, which is
## the only "behind the hand" cue available when the hand is drawn by the body.
func _draw_orbit() -> void:
	var phase := _t * ORBIT_RATE
	for i in 2:
		var dir := Vector2.from_angle(_angle + phase + PI * float(i))
		var side := dir.orthogonal()
		var inner := _hand + dir * (_length * 0.12)
		var tip := _hand + dir * _length
		var tone := 1.0 if i == 1 else 0.45
		MathArt.poly(self, _taper(inner, tip, side, 1.8, 0.3),
			_tone(tone), _tone(tone * 0.3), 1.0)


# --- Helpers ----------------------------------------------------------------

func _taper(from_point: Vector2, to_point: Vector2, side: Vector2, w0: float, w1: float) -> PackedVector2Array:
	return PackedVector2Array([
		from_point + side * w0,
		to_point + side * w1,
		to_point - side * w1,
		from_point - side * w0,
	])


func _lens_width(fat: float, k: float) -> float:
	# Sharper than a sine so the middle stays fat and the points stay sharp.
	return fat * pow(sin(PI * k), 0.62)


func _draw_fittings(dir: Vector2, side: Vector2) -> void:
	# Short guard + 1px pommel. Both stay small so neither can form an "L"
	# with the blade the way two parallel strokes did.
	MathArt.line(self, _hand + side * GUARD_HALF, _hand - side * GUARD_HALF, _metal(), 2.0)
	MathArt.disc(self, _hand - dir * GRIP, POMMEL, _metal())


func _tone(amount: float) -> Color:
	return Color(MathArt.WHITE, _alpha * amount)


func _metal() -> Color:
	return Color(MathArt.MID, _alpha)
