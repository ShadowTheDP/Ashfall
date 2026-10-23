class_name PrismFx
extends Node2D
## A burst of 3D-looking shards. Each shard is a tapered quad: wide at the
## base, narrow at the tip, so it reads as a facet catching light rather than
## as confetti. Taper + spin + shrink is what sells depth with no texture.

const LIFE := 0.35

var _shards: Array[Dictionary] = []
var _t := 0.0
var _tint := MathArt.WHITE
var _dir := Vector2.UP
var _count := 10


func setup(at: Vector2, direction: Vector2, tint: Color, count: int = 10) -> void:
	position = at
	_dir = direction.normalized() if direction.length() > 0.01 else Vector2.UP
	_tint = tint
	_count = maxi(1, count)
	z_index = 8


func _ready() -> void:
	# Precomputed here (not in _draw) so the draw loop is pure arithmetic.
	if not _shards.is_empty():
		return
	var base := _dir.angle()
	for i in _count:
		# Golden angle inside a +-70 degree fan: even spacing, never symmetric.
		var spread := (float(i) * MathArt.GOLDEN_ANGLE) - float(i / 2) * TAU
		var angle := base + clampf(spread, -1.22, 1.22)
		_shards.append({
			"angle": angle,
			"spin": randf_range(-9.0, 9.0),
			"length": randf_range(13.0, 22.0) * (1.0 - 0.25 * float(i) / float(_count)),
			"speed": randf_range(140.0, 300.0),
			"life": randf_range(0.24, LIFE),
		})


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	for shard in _shards:
		var life: float = shard["life"]
		if _t >= life:
			continue
		var k := _t / life
		var angle: float = shard["angle"]
		var length: float = shard["length"]
		# Decelerating travel: most of the distance in the first frames.
		var travel: float = float(shard["speed"]) * (1.0 - pow(1.0 - k, 2.2)) * life * 0.8
		var center := Vector2.from_angle(angle) * travel
		var shrink := 1.0 - k * 0.75
		var half := length * 0.34 * shrink
		var tip := length * shrink
		var rot: float = angle + float(shard["spin"]) * k * life
		var axis := Vector2.from_angle(rot)
		var side := Vector2(-axis.y, axis.x)
		# Tapered quad: base 2*half wide, tip 2*half*0.18 wide.
		var quad := PackedVector2Array([
			center + side * half,
			center + axis * tip + side * half * 0.18,
			center + axis * tip - side * half * 0.18,
			center - side * half,
		])
		var alpha := 1.0 - k * k
		MathArt.px_poly(self, quad, Color(_tint, alpha * 0.55), Color(MathArt.WHITE, alpha * 0.9), 1.0)
		# One bright edge: the lit facet of the shard.
		MathArt.px_line(self, center + side * half, center + axis * tip, Color(MathArt.WHITE, alpha), 1.0)
