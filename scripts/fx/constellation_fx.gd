class_name ConstellationFx
extends Node2D
## Points placed by phyllotaxis inside a disc, joined to their nearest
## neighbours by thin lines. The even golden-angle spread is what makes the
## links look drawn rather than random; a random point cloud reads as noise.

var _points := PackedVector2Array()
var _links := PackedInt32Array()   # flat pairs of point indices
var _t := 0.0
var _life := 0.7
var _tint := MathArt.WHITE


func setup(at: Vector2, radius: float, tint: Color, points: int = 9,
		life: float = 0.7) -> void:
	position = at
	_tint = tint
	_life = maxf(0.05, life)
	var n := maxi(2, points)
	var spacing := radius / sqrt(float(n))
	for i in n:
		_points.append(MathArt.phyllotaxis(i + 1, spacing))
	_links = _nearest_pairs(n)
	z_index = 7


func _nearest_pairs(n: int) -> PackedInt32Array:
	# Two nearest neighbours per point, deduplicated. O(n^2) on <= 16 points is
	# cheaper than any spatial structure and runs once, in setup.
	var out := PackedInt32Array()
	var seen := {}
	for i in n:
		for pass_index in 2:
			var best := -1
			var best_d := INF
			for j in n:
				if i == j:
					continue
				var d := _points[i].distance_squared_to(_points[j])
				if d < best_d and not seen.has(mini(i, j) * 1000 + maxi(i, j)):
					best_d = d
					best = j
			if best < 0:
				continue
			seen[mini(i, best) * 1000 + maxi(i, best)] = true
			out.append(i)
			out.append(best)
	return out


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / _life, 0.0, 1.0)
	# Form quickly, hold, dissolve: lines draw in before the dots brighten.
	var line_alpha := minf(1.0, k / 0.3) * minf(1.0, (1.0 - k) / 0.3)
	var dot_alpha := minf(1.0, k / 0.18) * minf(1.0, (1.0 - k) / 0.22)
	if line_alpha > 0.0:
		for i in range(0, _links.size(), 2):
			MathArt.px_line(self, _points[_links[i]], _points[_links[i + 1]],
				Color(_tint, line_alpha * 0.35), 1.0)
	if dot_alpha > 0.0:
		for point in _points:
			MathArt.px_circle(self, point, 1.8, Color(MathArt.WHITE, dot_alpha * 0.85))
			MathArt.px_ring(self, point, 3.6, Color(_tint, dot_alpha * 0.3), 1.0)
