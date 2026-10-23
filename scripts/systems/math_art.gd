class_name MathArt
## Shared visual language. Every decorative shape in the game comes from a
## small set of parametric curves and integer ratios so the art reads as one
## system instead of unrelated programmer shapes.
##
## Reference: phi = 1.618..., golden angle = 2.399963..., log spiral
## r = a * e^(b*theta), Lissajous curves, regular n-gons, superellipses.

const PHI := 1.618033988749895
const INV_PHI := 0.6180339887498949
const GOLDEN_ANGLE := 2.399963229728653
const SQRT2 := 1.4142135623730951
const SQRT3 := 1.7320508075688772


static func ngon(sides: int, radius: float, rotation := 0.0, center := Vector2.ZERO) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in sides:
		points.append(center + Vector2.from_angle(rotation + TAU * float(i) / float(sides)) * radius)
	return points


static func star(points_count: int, outer: float, inner: float, rotation := 0.0, center := Vector2.ZERO) -> PackedVector2Array:
	var points := PackedVector2Array()
	var total := points_count * 2
	for i in total:
		var radius := outer if i % 2 == 0 else inner
		points.append(center + Vector2.from_angle(rotation + PI * float(i) / float(points_count)) * radius)
	return points


static func superellipse(rx: float, ry: float, exponent: float, segments: int = 40, rotation := 0.0, center := Vector2.ZERO) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var theta := TAU * float(i) / float(segments)
		var ct := cos(theta)
		var st := sin(theta)
		var x := signf(ct) * pow(absf(ct), 2.0 / exponent) * rx
		var y := signf(st) * pow(absf(st), 2.0 / exponent) * ry
		points.append(center + Vector2(x, y).rotated(rotation))
	return points


static func lissajous(t: float, a: float, b: float, delta: float) -> Vector2:
	return Vector2(sin(a * t + delta), sin(b * t))


static func rose(t: float, k: float, radius: float) -> Vector2:
	var r := radius * cos(k * t)
	return Vector2.from_angle(t) * r


static func phyllotaxis(index: int, spacing: float) -> Vector2:
	var radius := spacing * sqrt(float(index))
	var angle := float(index) * GOLDEN_ANGLE
	return Vector2.from_angle(angle) * radius


static func fibonacci(index: int) -> int:
	var a := 0
	var b := 1
	for i in index:
		var next := a + b
		a = b
		b = next
	return a


static func spiral(radius: float, turns: float, samples: int = 64, rotation := 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	var max_theta := TAU * turns
	var b := log(PHI) / (PI * 0.5)
	for i in samples:
		var theta := max_theta * float(i) / float(samples - 1)
		var r := radius * exp(-b * (max_theta - theta))
		points.append(Vector2.from_angle(theta + rotation) * r)
	return points


static func harmonic_wave(start: Vector2, length: float, amplitude: float, cycles: float, phase: float, samples: int = 32) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in samples:
		var k := float(i) / float(samples - 1)
		var x := start.x + length * k
		var y := start.y + sin(k * TAU * cycles + phase) * amplitude
		points.append(Vector2(x, y))
	return points


static func ballistic_velocity(origin: Vector2, target: Vector2, speed: float, gravity: float) -> Vector2:
	var delta := target - origin
	if absf(delta.x) < 4.0:
		return delta.normalized() * speed
	var dx := absf(delta.x)
	var y_up := -delta.y
	var v2 := speed * speed
	var disc := v2 * v2 - gravity * (gravity * dx * dx + 2.0 * y_up * v2)
	if disc < 0.0:
		return delta.normalized() * speed
	var root := sqrt(disc)
	var tan_theta := (v2 - root) / (gravity * dx)
	var theta := atan(tan_theta)
	var dir_x := signf(delta.x)
	return Vector2(cos(theta) * dir_x, -sin(theta)) * speed


static func draw_poly(canvas: CanvasItem, points: PackedVector2Array, fill: Color, outline := Color.TRANSPARENT, width := 1.0) -> void:
	if points.size() < 3:
		return
	if fill.a > 0.0:
		canvas.draw_colored_polygon(points, fill)
	if outline.a > 0.0:
		var closed := points.duplicate()
		closed.append(points[0])
		canvas.draw_polyline(closed, outline, width, true)


static func draw_ring(canvas: CanvasItem, center: Vector2, radius: float, color: Color, width := 1.0, segments: int = 48, from_angle := 0.0, to_angle := TAU) -> void:
	canvas.draw_arc(center, radius, from_angle, to_angle, segments, color, width, true)


static func draw_glow(canvas: CanvasItem, center: Vector2, radius: float, color: Color, layers: int = 5) -> void:
	for i in layers:
		var k := 1.0 - float(i) / float(layers)
		canvas.draw_circle(center, radius * (0.25 + 0.75 * k), Color(color, color.a * 0.16 * (1.0 - k + 0.25)))


static func draw_spiral(canvas: CanvasItem, center: Vector2, radius: float, turns: float, color: Color, width := 1.4, samples := 64, rotation := 0.0) -> void:
	var points := spiral(radius, turns, samples, rotation)
	for i in points.size():
		points[i] += center
	canvas.draw_polyline(points, color, width, true)


static func draw_sigil(canvas: CanvasItem, center: Vector2, radius: float, sides: int, rotation: float, color: Color, width := 1.0) -> void:
	var outer := ngon(sides, radius, rotation, center)
	var inner := ngon(sides, radius * INV_PHI, -rotation, center)
	var fill := Color(color, color.a * 0.10)
	draw_poly(canvas, outer, fill, color, width)
	draw_poly(canvas, inner, Color.TRANSPARENT, Color(color, color.a * 0.55), width * 0.7)
	canvas.draw_circle(center, radius * 0.06, color)


static func with_alpha(color: Color, alpha: float) -> Color:
	var out := color
	out.a = alpha
	return out
