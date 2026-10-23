class_name ImpactFx
extends Node2D
## The complete hit-feedback package, tiered by attack weight.
##
## Order of reading, strongest first:
##   1. directional line sparks from the real contact point (never the centre)
##   2. expanding ring
##   3. a 1-frame white flash on the contact
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


func setup(hit_direction: Vector2, p_tier: int, p_tint: Color = MathArt.WHITE) -> void:
	tier = clampi(p_tier, 0, 3)
	direction = hit_direction.normalized() if hit_direction.length() > 0.01 else Vector2.RIGHT
	tint = p_tint
	_life = maxf(float(SPARK_LIFE[tier]), float(RING_LIFE[tier])) + 0.02

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
		})
	z_index = 12


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	_draw_flash()
	_draw_ring()
	_draw_polygon()
	_draw_sparks()


func _draw_polygon() -> void:
	# A rotating regular polygon inscribed in the expanding ring. This is the
	# mathematical element: the hit is a geometric event, not a puff of smoke.
	if tier < 2:
		return
	var sides := 3 + tier          # 5 for heavy, 6 for finisher
	var life: float = float(RING_LIFE[tier]) * 1.4
	if _t > life:
		return
	var k := clampf(_t / life, 0.0, 1.0)
	var radius: float = float(RING_RADIUS[tier]) * lerpf(0.35, 0.85, ease(k, 2.0))
	var alpha := (1.0 - k) * 0.55
	var spin := direction.angle() + k * 1.6
	var points := MathArt.ngon(sides, radius, spin)
	MathArt.px_poly(self, points, Color(0, 0, 0, 0), Color(MathArt.WHITE, alpha), 2.0)
	var inner := MathArt.ngon(sides, radius * MathArt.INV_PHI, -spin)
	MathArt.px_poly(self, inner, Color(0, 0, 0, 0), Color(MathArt.PALE, alpha * 0.6), 1.0)


func _draw_flash() -> void:
	# 1-2 frame white core, then a hard shrink. This is the impact frame.
	var flash_time := 0.033
	if _t > flash_time:
		return
	var k := _t / flash_time
	var size: float = float(FLASH_SIZE[tier]) * (1.0 + 0.5 * k)
	# A plus-shaped burst reads better than a square at small sizes.
	MathArt.px_rect(self, Rect2(-size * 0.5, -size * 0.5, size, size), Color(MathArt.WHITE, 1.0 - k))
	MathArt.line(self, Vector2(-size, 0), Vector2(size, 0), Color(MathArt.WHITE, 1.0 - k), 2.0)
	MathArt.line(self, Vector2(0, -size), Vector2(0, size), Color(MathArt.WHITE, 1.0 - k), 2.0)


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
		var width: float = float(spark["width"]) * (1.0 - k * 0.5)
		MathArt.line(self, tail, head, Color(tint, alpha), width)
		# Bright tip: one 2px dot at the head.
		if k < 0.6:
			MathArt.px_rect(self, Rect2(head.x - 1.0, head.y - 1.0, 2.0, 2.0), Color(MathArt.WHITE, alpha))
