class_name MathArt
## The single visual language of the game.
##
## Two rules, in priority order:
##   1. MOTION FIRST. Nothing is pixel-snapped. Characters and camera use
##      float positions so motion is smooth at any refresh rate.
##   2. MONOCHROME. There is no hue anywhere. Readability comes from value
##      contrast (see the ramp below), outline weight and motion.
##
## Geometry comes from a small set of parametric curves so the whole game
## reads as one system: polygons, stars, superellipses, Lissajous, rose curves,
## phyllotaxis, logarithmic spirals, harmonic waves and ballistic arcs.

const PHI := 1.618033988749895
const INV_PHI := 0.6180339887498949
const GOLDEN_ANGLE := 2.399963229728653
const SQRT2 := 1.4142135623730951
const SQRT3 := 1.7320508075688772

# --- Greyscale ramp ---------------------------------------------------------
# Values are chosen for contrast ratio, not for beauty. Do not add hue.
const BLACK := Color("#000000")
const INK := Color("#0a0a0a")
const BG_0 := Color("#111111")
const BG_1 := Color("#1b1b1b")
const BG_2 := Color("#252525")
const STONE_DIM := Color("#333333")
const STONE := Color("#404040")
const STONE_HI := Color("#5b5b5b")
const MID_DIM := Color("#707070")
const MID := Color("#808080")
const LIGHT_DIM := Color("#a0a0a0")
const LIGHT := Color("#bdbdbd")
const PALE_DIM := Color("#d5d5d5")
const PALE := Color("#e3e3e3")
const WHITE_DIM := Color("#f2f2f2")
const WHITE := Color("#ffffff")

# Semantic aliases. Gameplay code reads these, not raw ramp values.
const PLAYER := WHITE
const PLAYER_CORE := INK
const ENEMY := LIGHT
const ENEMY_RIM := PALE_DIM
const BOSS := PALE
const PICKUP := WHITE
const DANGER := WHITE
const SHIELD := PALE_DIM
const OUTLINE_DARK := BLACK
const OUTLINE_LIGHT := WHITE


# --- Value helpers ----------------------------------------------------------

static func with_alpha(color: Color, alpha: float) -> Color:
	var out := color
	out.a = alpha
	return out


static func shade(color: Color, amount: float) -> Color:
	# amount > 0 lightens toward white, < 0 darkens toward black.
	if amount >= 0.0:
		return color.lerp(WHITE, clampf(amount, 0.0, 1.0))
	return color.lerp(BLACK, clampf(-amount, 0.0, 1.0))


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


# --- Drawing (smooth, never snapped) ----------------------------------------

static func poly(canvas: CanvasItem, points: PackedVector2Array, fill: Color, outline := Color.TRANSPARENT, width := 1.0) -> void:
	if points.size() < 3:
		return
	if fill.a > 0.0:
		canvas.draw_colored_polygon(points, fill)
	if outline.a > 0.0:
		var closed := points.duplicate()
		closed.append(points[0])
		canvas.draw_polyline(closed, outline, width, true)


static func ring(canvas: CanvasItem, center: Vector2, radius: float, color: Color, width := 1.0, segments := 48, from_angle := 0.0, to_angle := TAU) -> void:
	if radius <= 0.0:
		return
	canvas.draw_arc(center, radius, from_angle, to_angle, maxi(6, segments), color, width, true)


static func arc(canvas: CanvasItem, center: Vector2, radius: float, from_angle: float, to_angle: float, color: Color, width := 1.0) -> void:
	if radius <= 0.0:
		return
	var steps := maxi(6, int(absf(to_angle - from_angle) * radius * 0.5))
	canvas.draw_arc(center, radius, from_angle, to_angle, steps, color, width, true)


static func line(canvas: CanvasItem, from_point: Vector2, to_point: Vector2, color: Color, width := 1.0) -> void:
	canvas.draw_line(from_point, to_point, color, width)


static func disc(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	if radius > 0.0:
		canvas.draw_circle(center, radius, color)


static func glow(canvas: CanvasItem, center: Vector2, radius: float, color: Color, layers: int = 4) -> void:
	# Cheap radial falloff: a few translucent discs. No shader, no texture.
	for i in layers:
		var k := 1.0 - float(i) / float(layers)
		canvas.draw_circle(center, radius * (0.3 + 0.7 * k), Color(color, color.a * 0.12 * k))


static func spiral_line(canvas: CanvasItem, center: Vector2, radius: float, turns: float, color: Color, width := 1.2, samples := 48, rotation := 0.0) -> void:
	var points := spiral(radius, turns, samples, rotation)
	for i in points.size():
		points[i] += center
	canvas.draw_polyline(points, color, width, true)


# --- Legacy aliases ---------------------------------------------------------
# Older call sites use the px_ prefix. These now draw SMOOTHLY on purpose:
# the project traded pixel snapping for motion fluidity.

static func px(value: float) -> float:
	return value


static func snapv(point: Vector2) -> Vector2:
	return point


static func px_rect(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	canvas.draw_rect(rect, color)


static func px_circle(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	disc(canvas, center, radius, color)


static func px_ring(canvas: CanvasItem, center: Vector2, radius: float, color: Color, thickness := 1.0, segments := 0) -> void:
	ring(canvas, center, radius, color, thickness, segments if segments > 0 else 48)


static func px_arc(canvas: CanvasItem, center: Vector2, radius: float, from_angle: float, to_angle: float, color: Color, thickness := 1.0) -> void:
	arc(canvas, center, radius, from_angle, to_angle, color, thickness)


static func px_line(canvas: CanvasItem, from_point: Vector2, to_point: Vector2, color: Color, thickness := 1.0) -> void:
	line(canvas, from_point, to_point, color, thickness)


static func px_poly(canvas: CanvasItem, points: PackedVector2Array, fill: Color, outline := Color.TRANSPARENT, width := 1.0) -> void:
	poly(canvas, points, fill, outline, width)
