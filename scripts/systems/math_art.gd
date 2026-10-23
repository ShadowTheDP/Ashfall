class_name MathArt
## The single visual language of the game: pixel-quantised geometry.
##
## Every shape is snapped to whole pixels and drawn with hard edges so the
## upscaled viewport reads as true pixel art. Colours come from one palette.
##
## Reference: phi = 1.618..., golden angle = 2.399963..., log spiral
## r = a * e^(b*theta), Lissajous curves, regular n-gons, superellipses.

const PHI := 1.618033988749895
const INV_PHI := 0.6180339887498949
const GOLDEN_ANGLE := 2.399963229728653
const SQRT2 := 1.4142135623730951
const SQRT3 := 1.7320508075688772

# --- Palette ----------------------------------------------------------------
# A fixed ramp keeps the art coherent. Do not invent new colours per file.
const INK := Color("#07090d")
const INK_2 := Color("#0d1218")
const STONE := Color("#131a22")
const STONE_2 := Color("#1d2733")
const STONE_3 := Color("#2b3a4a")
const EDGE := Color("#3d5165")
const STEEL_DIM := Color("#5a6f85")
const STEEL := Color("#7c8fa3")
const STEEL_HI := Color("#a8b8c8")
const PALE := Color("#e9e2d2")
const WHITE := Color("#fff6e0")
const AMBER_DIM := Color("#8a5a1f")
const AMBER := Color("#e8a33d")
const AMBER_HI := Color("#ffd166")
const RED_DIM := Color("#7a2436")
const RED := Color("#d94a4a")
const RED_HI := Color("#ff6b6b")
const CYAN_DIM := Color("#2a4a5a")
const CYAN_MID := Color("#4a90a8")
const CYAN := Color("#8fe3ff")
const VIOLET_DIM := Color("#3a2a5a")
const VIOLET_MID := Color("#6b4a9e")
const VIOLET := Color("#9b6bff")
const GREEN := Color("#7fd6a0")
const BROWN := Color("#2b1f14")


# --- Pixel helpers ----------------------------------------------------------

static func px(value: float) -> float:
	return roundf(value)


static func snapv(point: Vector2) -> Vector2:
	return Vector2(roundf(point.x), roundf(point.y))


static func px_rect(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	var snapped := Rect2(
		Vector2(roundf(rect.position.x), roundf(rect.position.y)),
		Vector2(roundf(rect.size.x), roundf(rect.size.y))
	)
	canvas.draw_rect(snapped, color)


static func px_circle(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	var c := snapv(center)
	var r := int(roundf(radius))
	if r <= 0:
		return
	for dy in range(-r, r + 1):
		var dx := int(floor(sqrt(maxf(0.0, float(r * r - dy * dy)))))
		canvas.draw_rect(Rect2(c.x - float(dx), c.y + float(dy), float(dx * 2 + 1), 1.0), color)


static func px_ring(canvas: CanvasItem, center: Vector2, radius: float, color: Color, thickness := 1.0, segments := 0) -> void:
	var c := snapv(center)
	var r := int(roundf(radius))
	var t := maxi(1, int(roundf(thickness)))
	var inner := maxi(0, r - t)
	if r <= 0:
		return
	for dy in range(-r, r + 1):
		var dxo := int(floor(sqrt(maxf(0.0, float(r * r - dy * dy)))))
		var dxi := 0
		if absi(dy) <= inner:
			dxi = int(floor(sqrt(maxf(0.0, float(inner * inner - dy * dy)))))
		if dxo <= dxi:
			continue
		canvas.draw_rect(Rect2(c.x - float(dxo), c.y + float(dy), float(dxo - dxi), 1.0), color)
		canvas.draw_rect(Rect2(c.x + float(dxi) + 1.0, c.y + float(dy), float(dxo - dxi), 1.0), color)


static func px_arc(canvas: CanvasItem, center: Vector2, radius: float, from_angle: float, to_angle: float, color: Color, thickness := 1.0) -> void:
	var c := snapv(center)
	var r := roundf(radius)
	var t := maxf(1.0, roundf(thickness))
	var steps := maxi(6, int(absf(to_angle - from_angle) * r * 0.9))
	for i in steps + 1:
		var angle := lerpf(from_angle, to_angle, float(i) / float(steps))
		var point := snapv(c + Vector2.from_angle(angle) * r)
		canvas.draw_rect(Rect2(point.x, point.y, t, t), color)


static func px_line(canvas: CanvasItem, from_point: Vector2, to_point: Vector2, color: Color, thickness := 1.0) -> void:
	canvas.draw_line(snapv(from_point), snapv(to_point), color, maxf(1.0, roundf(thickness)))


static func px_poly(canvas: CanvasItem, points: PackedVector2Array, fill: Color, outline := Color.TRANSPARENT, width := 1.0) -> void:
	var snapped := PackedVector2Array()
	for point in points:
		snapped.append(snapv(point))
	draw_poly(canvas, snapped, fill, outline, width)


# --- Geometry ---------------------------------------------------------------

static func ngon(sides: int, radius: float, rotation := 0.0, center := Vector2.ZERO) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in sides:
		points.append(center + Vector2.from_angle(rotation + TAU * float(i) / float(sides)) * radius)
	return points


static func star(points_count: int, outer: float, inner: float, rotation := 0.0, center := Vector2.ZERO) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in points_count * 2:
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
	return Vector2.from_angle(t) * (radius * cos(k * t))


static func phyllotaxis(index: int, spacing: float) -> Vector2:
	return Vector2.from_angle(float(index) * GOLDEN_ANGLE) * (spacing * sqrt(float(index)))


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
		points.append(Vector2(start.x + length * k, start.y + sin(k * TAU * cycles + phase) * amplitude))
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
	var tan_theta := (v2 - sqrt(disc)) / (gravity * dx)
	var theta := atan(tan_theta)
	return Vector2(cos(theta) * signf(delta.x), -sin(theta)) * speed


# --- Legacy drawing helpers (kept for UI code) ------------------------------

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


static func with_alpha(color: Color, alpha: float) -> Color:
	var out := color
	out.a = alpha
	return out
