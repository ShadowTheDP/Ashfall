class_name VortexFx
extends Node2D
## Gathering vortex: dots spiral inward and snap into a point. This is the
## windup / telegraph read -- the opposite of a burst, so it must never expand.

var _dots: Array[Dictionary] = []
var _t := 0.0
var _life := 0.5
var _spin := 6.0
var _radius := 60.0
var _tint := MathArt.WHITE


func setup(at: Vector2, radius: float, tint: Color, dots: int = 16,
		spin: float = 6.0, life: float = 0.5) -> void:
	position = at
	_radius = maxf(4.0, radius)
	_tint = tint
	_spin = spin
	_life = maxf(0.05, life)
	# Phyllotaxis start radii so the ring of dots is a spiral, not a circle.
	for i in maxi(1, dots):
		_dots.append({
			"theta": float(i) * MathArt.GOLDEN_ANGLE,
			"r": _radius * sqrt(float(i + 1) / float(maxi(1, dots))),
		})
	z_index = 7


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / _life, 0.0, 1.0)
	# r(t) = R * (1 - t)^1.7: the contraction is back-loaded, so the last third
	# is where the pull becomes visible. That is the telegraph window.
	var pull := pow(1.0 - k, 1.7)
	var dot_radius := lerpf(2.2, 1.0, k)
	for dot in _dots:
		var r: float = float(dot["r"]) * pull
		var theta: float = float(dot["theta"]) + _spin * k
		var at := Vector2.from_angle(theta) * r
		# Brighten as it converges: the gather is what the player must read.
		var alpha := lerpf(0.45, 1.0, k)
		MathArt.px_circle(self, at, dot_radius, Color(_tint, alpha))
		if r > 6.0:
			# Short arc trailing each dot so the rotation is legible.
			MathArt.px_line(self, at, at + Vector2.from_angle(theta - _spin * 0.08) * (r * 0.16),
				Color(_tint, alpha * 0.5), 1.0)
	# The snap: a hard 2-frame flash plus a tiny ring once everything collapses.
	if k > 0.88:
		var s := (k - 0.88) / 0.12
		MathArt.px_circle(self, Vector2.ZERO, lerpf(3.0, 0.5, s), Color(MathArt.WHITE, 1.0 - s))
		MathArt.px_ring(self, Vector2.ZERO, lerpf(1.0, 13.0, s), Color(MathArt.WHITE, (1.0 - s) * 0.7), 1.0)
