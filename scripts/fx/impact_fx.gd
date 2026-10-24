class_name ImpactFx
extends Node2D
## The complete hit-feedback package, tiered by attack weight.
##
## Order of reading, strongest first:
##   1. directional line sparks from the real contact point (never the centre)
##   2. expanding ring
##   3. a 1-frame white flash on the contact
##
## Every tier is a superset of the one below it, and each step adds a *shape*,
## not a size -- a light hit and a finisher differ in kind, not in brightness:
##   light     one clean fan + ring + flash
##   medium    + a second, offset fan (half speed, dimmer)
##   heavy     + a short tear under the contact
##   finisher  + the blade's line, broken into arcs, 2 frames
## A crit adds the rotating ngon inscribed in the ring (`mark_crit`): the crit
## bit arrives one call later than the impact, from Combat.damage_number.
##
## All numbers follow docs/design/impact.md. Monochrome only: sparks are white
## lines, the ring is a white arc, the flash is a white square.

enum Tier { LIGHT, MEDIUM, HEAVY, FINISHER }

# Per-tier tables. Index by Tier.
const SPARK_COUNT := [8, 10, 12, 16]
const SPARK_LENGTH := [9.0, 13.0, 19.0, 27.0]
const SPARK_SPEED := [250.0, 330.0, 430.0, 560.0]
const SPARK_LIFE := [0.13, 0.15, 0.18, 0.21]
const RING_RADIUS := [18.0, 24.0, 36.0, 54.0]
const RING_LIFE := [0.083, 0.1, 0.133, 0.167]
const FLASH_SIZE := [10.0, 13.0, 18.0, 24.0]

var tier := Tier.LIGHT
var direction := Vector2.RIGHT
var tint := MathArt.WHITE
var _t := 0.0
var _life := 0.2
var _sparks: Array[Dictionary] = []
var _crack := PackedVector2Array()
var _crit_sides := 0


func setup(hit_direction: Vector2, p_tier: int, p_tint: Color = MathArt.WHITE) -> void:
	tier = clampi(p_tier, 0, 3)
	direction = hit_direction.normalized() if hit_direction.length() > 0.01 else Vector2.RIGHT
	tint = p_tint
	_life = maxf(float(SPARK_LIFE[tier]), float(RING_LIFE[tier])) + 0.02
	_sparks.clear()

	# Sparks fan out around the hit normal (not uniformly in all directions),
	# so the hit reads as directional. The fan is sampled with the golden angle
	# so the spacing is even but never obviously symmetric.
	var count: int = SPARK_COUNT[tier]
	var base_angle := direction.angle()
	var spread := deg_to_rad(80.0)
	for i in count:
		var k := 0.0 if count == 1 else float(i) / float(count - 1)
		var angle := base_angle + lerpf(-spread, spread, k) + float(i) * MathArt.GOLDEN_ANGLE * 0.06
		_sparks.append({
			"angle": angle,
			"speed": randf_range(float(SPARK_SPEED[tier]) * 0.75, float(SPARK_SPEED[tier])),
			"length": float(SPARK_LENGTH[tier]) * randf_range(0.7, 1.15),
			"width": 2.0 if tier >= Tier.HEAVY else 1.5,
			"delay": randf_range(0.0, 0.012),
			"alpha": 1.0,
			"color": tint,
		})

	# Medium and up: a second fan, offset a third of a radian and running at half
	# the speed. Widening the one fan would only read as a bigger light hit; two
	# fans at different speeds read as two things happening at the contact.
	if tier >= Tier.MEDIUM:
		var count2 := maxi(4, count / 2)
		for i in count2:
			var k2 := 0.0 if count2 == 1 else float(i) / float(count2 - 1)
			var angle2 := base_angle + 0.33 + lerpf(-spread * 0.7, spread * 0.7, k2)
			angle2 += float(i) * MathArt.GOLDEN_ANGLE * 0.05
			_sparks.append({
				"angle": angle2,
				"speed": float(SPARK_SPEED[tier]) * randf_range(0.38, 0.5),
				"length": float(SPARK_LENGTH[tier]) * randf_range(0.45, 0.7),
				"width": 1.0,
				"delay": randf_range(0.006, 0.018),
				"alpha": 0.55,
				"color": MathArt.PALE,
			})

	# Heavy and up: a short tear under the contact. The joints are drawn once
	# here -- regenerating them per frame would make the crack crawl.
	if tier >= Tier.HEAVY:
		var joint := Vector2(randf_range(-4.0, 4.0), 7.0)
		var knee := joint + Vector2(randf_range(-3.5, 3.5), 7.0)
		_crack = PackedVector2Array([Vector2.ZERO, joint, knee,
			knee + Vector2(randf_range(-2.0, 2.0), 5.0)])
	z_index = 12


## A crit is a different kind of event at the same size, so it is drawn rather
## than scaled: a rotating ngon inscribed in the ring, 5 sides heavy / 6 finisher.
## Called by Combat once the crit flag is known (the hit itself never carries it).
func mark_crit(sides: int) -> void:
	_crit_sides = sides
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	_draw_flash()
	_draw_ring()
	_draw_crack()
	_draw_blade_path()
	_draw_polygon()
	_draw_sparks()


func _draw_polygon() -> void:
	# A rotating regular polygon inscribed in the expanding ring. This is the
	# mathematical element: the hit is a geometric event, not a puff of smoke.
	# Crit only: heavy and finisher use it elsewhere, so the one shape that
	# cannot be mistaken for size (a polygon) is reserved for the crit read.
	if _crit_sides < 3:
		return
	var life: float = float(RING_LIFE[tier]) * 1.4
	if _t > life:
		return
	var k := clampf(_t / life, 0.0, 1.0)
	var radius: float = float(RING_RADIUS[tier]) * lerpf(0.35, 0.85, ease(k, 2.0))
	var alpha := (1.0 - k) * 0.55
	var spin := direction.angle() + k * 1.6
	var points := MathArt.ngon(_crit_sides, radius, spin)
	MathArt.px_poly(self, points, Color(0, 0, 0, 0), Color(MathArt.WHITE, alpha), 2.0)
	var inner := MathArt.ngon(_crit_sides, radius * MathArt.INV_PHI, -spin)
	MathArt.px_poly(self, inner, Color(0, 0, 0, 0), Color(MathArt.PALE, alpha * 0.6), 1.0)


func _draw_flash() -> void:
	# 1-2 frame white core, then a hard shrink. This is the impact frame.
	var flash_time := 0.033
	if _t > flash_time:
		return
	var k := _t / flash_time
	var size: float = float(FLASH_SIZE[tier]) * (1.0 + 0.5 * k)
	# A plus-shaped burst reads better than a square at small sizes. The arms
	# stop at half the size so the whole flash stays inside the tier's 10-24 px
	# budget: the contact never becomes a white blob over the fight.
	MathArt.px_rect(self, Rect2(-size * 0.5, -size * 0.5, size, size), Color(MathArt.WHITE, 1.0 - k))
	MathArt.line(self, Vector2(-size * 0.5, 0), Vector2(size * 0.5, 0), Color(MathArt.WHITE, 1.0 - k), 2.0)
	MathArt.line(self, Vector2(0, -size * 0.5), Vector2(0, size * 0.5), Color(MathArt.WHITE, 1.0 - k), 2.0)


func _draw_crack() -> void:
	# Heavy and up: a short tear hanging under the contact. It is anchored to the
	# contact point and not to a floor query -- an impact does not know where the
	# ground is -- but it always points at the floor, so on a low hit it lands on
	# the deck. 0.14 s = 8 frames @60.
	if _crack.size() < 4:
		return
	var life := 0.14
	if _t > life:
		return
	var k := clampf(_t / life, 0.0, 1.0)
	var alpha := (1.0 - k) * 0.8
	# The tear grows out of the contact over the first 3 frames, then holds.
	var reach := minf(1.0, k * 4.0)
	for i in _crack.size() - 1:
		MathArt.line(self, _crack[i] * reach, _crack[i + 1] * reach,
			Color(MathArt.PALE, alpha * (1.0 - float(i) * 0.22)), 1.5 - float(i) * 0.35)


func _draw_blade_path() -> void:
	# Finisher only: the line the blade took through the impact, broken into four
	# arcs so it can never fill the space around the contact. 2 frames @60.
	if tier < Tier.FINISHER:
		return
	var life := 0.033
	if _t > life:
		return
	var k := _t / life
	var alpha := (1.0 - k) * 0.6
	var radius: float = float(RING_RADIUS[tier]) * MathArt.INV_PHI
	var axis := direction.orthogonal().angle()
	for side in [-1, 1]:
		for i in 2:
			var from_angle := axis + float(side) * (0.22 + float(i) * 0.52)
			MathArt.arc(self, Vector2.ZERO, radius, from_angle, from_angle + float(side) * 0.34,
				Color(MathArt.WHITE, alpha * (0.9 - float(i) * 0.35)), 2.0 - float(i) * 0.5)


func _draw_ring() -> void:
	var life: float = float(RING_LIFE[tier])
	if _t > life:
		return
	var k := clampf(_t / life, 0.0, 1.0)
	var radius: float = float(RING_RADIUS[tier]) * ease(k, 2.2)
	var alpha := 1.0 - k
	# Ring thickness tapers from 2px to 0.75px.
	var width := lerpf(2.0, 0.75, k)
	MathArt.ring(self, Vector2.ZERO, radius, Color(MathArt.WHITE, alpha * 0.85), width)
	if tier >= Tier.HEAVY:
		MathArt.ring(self, Vector2.ZERO, radius * MathArt.INV_PHI, Color(MathArt.PALE, alpha * 0.45), 1.0)


func _draw_sparks() -> void:
	var life: float = float(SPARK_LIFE[tier])
	for spark in _sparks:
		var delay: float = spark["delay"]
		var local := _t - delay
		if local < 0.0 or local > life:
			continue
		var k := local / life
		var angle: float = spark["angle"]
		var speed: float = spark["speed"]
		var length: float = spark["length"]
		# Sparks decelerate hard: most of the travel happens in the first frames.
		var travelled := speed * (1.0 - pow(1.0 - k, 2.4)) * life
		var dir := Vector2.from_angle(angle)
		var head := dir * travelled
		var tail := head - dir * length * (1.0 - k * 0.55)
		var alpha := 1.0 if k < 0.35 else lerpf(0.55, 0.0, (k - 0.35) / 0.65)
		alpha *= float(spark["alpha"])
		var width: float = float(spark["width"]) * (1.0 - k * 0.5)
		MathArt.line(self, tail, head, Color(spark["color"], alpha), width)
		# Bright tip: one 2px dot at the head. The second fan runs dimmer, so its
		# tips stay below the primary fan's in value.
		if k < 0.6 and float(spark["alpha"]) > 0.8:
			MathArt.px_rect(self, Rect2(head.x - 1.0, head.y - 1.0, 2.0, 2.0), Color(MathArt.WHITE, alpha))
