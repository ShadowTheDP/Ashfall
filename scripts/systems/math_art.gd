class_name MathArt
## The single visual language of the game.
##
## Motion stays smooth at floating-point positions. Cool layered environments,
## warm light and small semantic accents preserve the geometry's readability.
##
## Geometry comes from a small set of parametric curves so the whole game
## reads as one system: polygons, stars, superellipses, Lissajous, rose curves,
## phyllotaxis, logarithmic spirals, harmonic waves and ballistic arcs.

const PHI := 1.618033988749895
const INV_PHI := 0.6180339887498949
const GOLDEN_ANGLE := 2.399963229728653


# --- Chromatic tonal ramp ---------------------------------------------------
# Stable names keep geometry callers on one navy/slate/cream value scale.
const BLACK := Color("#000000")
const INK := Color("#080f20")
const BG_0 := Color("#101a2d")
const BG_1 := Color("#17253a")
const BG_2 := Color("#22344a")
const STONE_DIM := Color("#30455a")
const STONE := Color("#405a6d")
const STONE_HI := Color("#5b7888")
const MID_DIM := Color("#718c9a")
const MID := Color("#879eaa")
const LIGHT_DIM := Color("#a5b7bd")
const LIGHT := Color("#c0cdca")
const PALE_DIM := Color("#dadbd0")
const PALE := Color("#f0e8d5")
const WHITE := Color("#ffffff")

# Small semantic accents complement the pale text and quiet surfaces.
const PLAYER := Color("#79ead0")
const ENEMY := Color("#f38a7e")
const BOSS := Color("#f2c56e")
const PICKUP := Color("#73ddeb")
const ACCENT := Color("#efc779")
const DANGER := Color("#f38a7e")
const HEAL := Color("#87dba5")
const BRUTALITY := Color("#f38a7e")
const TACTICS := Color("#bc9ded")
const SURVIVAL := Color("#87dba5")
const FIRE := Color("#f4ae62")
const CELL := Color("#73ddeb")
const GOLD := Color("#efc779")

# Columns: sky, middle, depth, stone, edge, light, far plane, near plane.
# Immutable colors belong here; callers never recolor actors with a world tint.
const BIOME_PALETTES := {
	"ash_gate": [Color("#091426"), Color("#123044"), Color("#091522"), Color("#355365"), Color("#668c99"), Color("#f2ad65"), Color("#1d4052"), Color("#172335")],
	"hanging_gallery": [Color("#102637"), Color("#1c535b"), Color("#15182e"), Color("#3b626a"), Color("#76acaa"), Color("#ebbe78"), Color("#2b6c71"), Color("#251e3c")],
	"silt_cistern": [Color("#081d29"), Color("#103e49"), Color("#0b2029"), Color("#30575c"), Color("#6b9894"), Color("#a9d89a"), Color("#20515a"), Color("#142f38")],
	"stone_ramparts": [Color("#162137"), Color("#344963"), Color("#121b30"), Color("#4a6077"), Color("#91a5b7"), Color("#f0c183"), Color("#425c78"), Color("#222c44")],
	"bridge_sentinel": [Color("#141a31"), Color("#293b54"), Color("#111629"), Color("#46546d"), Color("#899bb2"), Color("#f1be6a"), Color("#354b65"), Color("#25233d")],
	"stilt_foundry": [Color("#20192c"), Color("#393044"), Color("#181827"), Color("#554b60"), Color("#9e8997"), Color("#f2a35e"), Color("#4a3b51"), Color("#291f35")],
	"clock_spire": [Color("#151c35"), Color("#2f385c"), Color("#11182c"), Color("#4e5778"), Color("#929fc4"), Color("#e8c87c"), Color("#404970"), Color("#25253f")],
	"high_keep": [Color("#192439"), Color("#304961"), Color("#151d30"), Color("#536575"), Color("#a1b3bb"), Color("#f1d399"), Color("#405e77"), Color("#292b43")],
	"clock_warden": [Color("#191830"), Color("#383354"), Color("#131426"), Color("#554c6e"), Color("#a296bd"), Color("#f1c36e"), Color("#494164"), Color("#29213d")],
	"silent_regent": [Color("#111a2d"), Color("#293d53"), Color("#0c1425"), Color("#465b70"), Color("#8eacbb"), Color("#f4d89d"), Color("#344d65"), Color("#20253c")],
	"hub": [Color("#0e1b2c"), Color("#203c49"), Color("#0d1928"), Color("#3d5b65"), Color("#82a4aa"), Color("#f2c17b"), Color("#2b4b58"), Color("#1d293b")],
	"passage": [Color("#10192c"), Color("#23374c"), Color("#0d1625"), Color("#3c5368"), Color("#7d9bad"), Color("#88d8df"), Color("#2b435a"), Color("#1b263b")],
	"arena": [Color("#161a30"), Color("#303650"), Color("#101426"), Color("#4e536b"), Color("#9499b2"), Color("#f2c56e"), Color("#3a4260"), Color("#24233b")],
}

static func axis_color(axis: String) -> Color:
	match axis:
		"brutality": return BRUTALITY
		"tactics": return TACTICS
		"survival": return SURVIVAL
		_: return PALE

static func biome_color(id: String, role: String) -> Color:
	var palette: Array = BIOME_PALETTES.get(id, BIOME_PALETTES["ash_gate"])
	match role:
		"background_top": return palette[0]
		"background_mid": return palette[1]
		"background_bottom": return palette[2]
		"stone": return palette[3]
		"edge": return palette[4]
		"accent": return palette[5]
		"far": return palette[6]
		"near": return palette[7]
		_: return palette[3]


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


## Gielis superformula: one equation that produces every rounded/starred shape
## the game needs (petals, gear teeth, shields, blobs) without a per-shape
## function. m = symmetry count, n1..n3 = roundness/spike blend.
##   r(θ) = (|cos(mθ/4)/a|^n2 + |sin(mθ/4)/b|^n3)^(-1/n1)
## m=6,n1=8,n2=12,n3=12 is a soft hexagon; m=6,n1=2,n2=7,n3=7 is a spiked star.
static func superformula(m: float, n1: float, n2: float, n3: float, radius: float,
		segments := 64, rotation := 0.0, center := Vector2.ZERO, a := 1.0, b := 1.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var theta := TAU * float(i) / float(segments)
		var t1 := pow(absf(cos(m * theta * 0.25) / a), n2)
		var t2 := pow(absf(sin(m * theta * 0.25) / b), n3)
		var sum := t1 + t2
		var r := radius if sum <= 0.0 else radius * pow(sum, -1.0 / n1)
		# The formula is unbounded at the lobes; clamp so a bad parameter set can
		# never draw a shape that swallows the screen.
		r = minf(r, radius * 2.2)
		points.append(center + Vector2.from_angle(theta + rotation) * r)
	return points


## Spirograph: a circle of radius r rolling inside a circle of radius big_r,
## with the pen at distance d. Closed, symmetric, and it reads as machinery.
static func hypotrochoid(big_r: float, r: float, d: float, turns: float,
		samples := 96, rotation := 0.0, center := Vector2.ZERO) -> PackedVector2Array:
	var points := PackedVector2Array()
	if absf(r) < 0.001:
		return points
	for i in samples:
		var theta := TAU * turns * float(i) / float(samples - 1)
		var x := (big_r - r) * cos(theta) + d * cos((big_r - r) / r * theta)
		var y := (big_r - r) * sin(theta) - d * sin((big_r - r) / r * theta)
		points.append(center + Vector2(x, y).rotated(rotation))
	return points


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


# UI uses the same primitives as the world; only its layout is in logical pixels.
const UI_GAP := 16.0 * INV_PHI
const UI_PAGE := Rect2(32, 24, 704, 432)

## The project's one external asset, and it is text only: a pinned Noto Sans CJK
## TC face so Chinese is readable on every player machine instead of depending on
## an OS font. Geometry, icons and art below are still the only visual language.
## Provenance and SIL OFL licence: assets/fonts/PROVENANCE.md.
const UI_FONT_PATH := "res://assets/fonts/NotoSansCJKtc-Regular.otf"
## Text layout only changes with content, width, size or locale, so a bounded
## cache keeps a redraw from reshaping every paragraph every frame.
const UI_LAYOUT_CACHE_LIMIT := 256

static var _ui_font: Font = null
static var _ui_wrap_cache: Dictionary = {}
static var _ui_short_cache: Dictionary = {}

## Single entry point for drawing and measuring text, so a missing face fails in
## one place instead of per call site.
static func ui_font() -> Font:
	if _ui_font == null:
		var found: Font = null
		if ResourceLoader.exists(UI_FONT_PATH):
			found = load(UI_FONT_PATH) as Font
		if found == null:
			# The fallback keeps the game readable, but it is not a CJK face and
			# must never pass as the bundled one: this error fails the text check.
			push_error("MathArt: %s is missing or unreadable; UI text is NOT the bundled CJK face" % UI_FONT_PATH)
			found = ThemeDB.fallback_font
		_ui_font = found
	return _ui_font

## Real line height of the shared face at `size`. Callers space multi-line text
## with this instead of guessing a smaller pitch than the glyphs need.
static func ui_line_height(size := 13) -> float:
	return maxf(float(size), ceilf(ui_font().get_height(size)))

static func ui_reveal(canvas: Control) -> void:
	var previous: Tween = canvas.get_meta("ui_reveal") if canvas.has_meta("ui_reveal") else null
	if previous != null and previous.is_valid(): previous.kill()
	canvas.position = Vector2(0, UI_GAP * INV_PHI)
	var tween := canvas.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(canvas, "position", Vector2.ZERO, 0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	canvas.set_meta("ui_reveal", tween)

# One quiet page frame. The surface is 94% ink so a modal reads over the world
# without hiding it; only the focused page earns a full-brightness edge.
static func ui_panel(canvas: CanvasItem, rect: Rect2, selected := false) -> void:
	var cut := 10.0 * INV_PHI
	poly(canvas, PackedVector2Array([rect.position + Vector2(cut, 0), Vector2(rect.end.x, rect.position.y), rect.end - Vector2(0, cut), rect.end - Vector2(cut, 0), Vector2(rect.position.x, rect.end.y), rect.position + Vector2(0, cut)]), Color(BG_0, 0.94), Color(ACCENT if selected else STONE_DIM, 1.0 if selected else 0.45), 1)
	if selected:
		line(canvas, rect.position + Vector2(cut, 0), Vector2(rect.end.x - cut, rect.position.y), ACCENT, 1)
		px_rect(canvas, Rect2(rect.position + Vector2(0, cut), Vector2(2, rect.size.y - cut * 2)), ACCENT)

# Selection state changes first; the short edge settle never owns input.
static func ui_select(canvas: Control) -> void:
	var previous: Tween = canvas.get_meta("ui_select") if canvas.has_meta("ui_select") else null
	if previous != null and previous.is_valid(): previous.kill()
	canvas.set_meta("ui_focus_progress", 0.0)
	var tween := canvas.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(func(value: float) -> void:
		canvas.set_meta("ui_focus_progress", value)
		canvas.queue_redraw(), 0.0, 1.0, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	canvas.set_meta("ui_select", tween)

# Quiet surfaces let the object carry identity; focus adds one edge, not a second frame.
static func ui_surface(canvas: CanvasItem, rect: Rect2, focused := false, opaque := false) -> void:
	px_rect(canvas, rect, (BG_2 if focused else BG_0) if opaque else Color(BG_2 if focused else BG_0, 0.94))
	line(canvas, Vector2(rect.position.x, rect.end.y), rect.end, Color(STONE_HI if focused else STONE_DIM, 1.0 if focused else 0.45), 1)
	if focused:
		px_rect(canvas, Rect2(rect.position, Vector2(rect.size.x * lerpf(INV_PHI * INV_PHI, INV_PHI, float(canvas.get_meta("ui_focus_progress", 1.0))), 2)), ACCENT)
		px_rect(canvas, Rect2(rect.position, Vector2(2, rect.size.y)), ACCENT)

static func ui_axis_emblem(canvas: CanvasItem, at: Vector2, axis: String, radius: float, tone := PALE) -> void:
	if tone == PALE: tone = axis_color(axis)
	match axis:
		"brutality":
			poly(canvas, ngon(3, radius, -PI * 0.5, at), tone)
			poly(canvas, ngon(3, radius * INV_PHI, -PI * 0.5, at + Vector2(0, radius * INV_PHI * INV_PHI)), BG_1)
			line(canvas, at + Vector2(0, -radius * INV_PHI), at + Vector2(0, radius * INV_PHI), tone, 2)
		"tactics":
			var inner := radius * INV_PHI * INV_PHI
			for i in 4:
				var angle := i * PI * 0.5
				poly(canvas, PackedVector2Array([at + Vector2.from_angle(angle) * radius, at + Vector2.from_angle(angle + PI * 0.5) * inner, at, at + Vector2.from_angle(angle - PI * 0.5) * inner]), tone)
			poly(canvas, ngon(4, inner * INV_PHI, 0, at), BG_1)
		"survival":
			poly(canvas, ngon(6, radius, -PI * 0.5, at), tone)
			poly(canvas, ngon(6, radius * INV_PHI, -PI * 0.5, at), BG_1)
			poly(canvas, ngon(6, radius * INV_PHI * INV_PHI * INV_PHI, -PI * 0.5, at), tone)

static func ui_focus(canvas: CanvasItem, rect: Rect2) -> void:
	px_rect(canvas, rect, BG_1.lerp(BG_2, float(canvas.get_meta("ui_focus_progress", 1.0))))
	px_rect(canvas, Rect2(rect.position, Vector2(3, rect.size.y)), ACCENT)
	poly(canvas, ngon(4, 3.0, 0.0, rect.position + Vector2(12, rect.size.y * 0.5)), ACCENT)

static func ui_text(canvas: CanvasItem, at: Vector2, value: String, size := 13, tone := PALE, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	canvas.draw_string(ui_font(), at, value, align, width, size, PALE if tone == WHITE else tone)

## Break `value` into lines that fit `width` using TextServer's native rules: the
## locale's punctuation and word rules apply, so Chinese breaks between
## characters and English between words. Line starts come back on grapheme
## boundaries, and the lines are cut start-to-start, so no character is dropped:
## joining the result reproduces `value` apart from the explicit newlines.
## Cache key includes the locale because the same sentence breaks differently.
static func ui_wrap(value: String, width: float, size := 13) -> Array[String]:
	var key := "%d|%.2f|%s|%s" % [size, width, TranslationServer.get_locale(), value]
	var hit: Variant = _ui_wrap_cache.get(key)
	if hit != null:
		return hit
	var lines: Array[String] = []
	if value.is_empty():
		lines.append("")
	else:
		var paragraph := TextParagraph.new()
		paragraph.width = maxf(width, 1.0)
		paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		paragraph.add_string(value, ui_font(), size, TranslationServer.get_locale())
		var starts: Array[int] = []
		for index in paragraph.get_line_count():
			starts.append(paragraph.get_line_range(index).x)
		for index in starts.size():
			var start := starts[index]
			var end := starts[index + 1] if index + 1 < starts.size() else value.length()
			var text := value.substr(start, end - start)
			# A line break belongs to the previous range; drop the CR/LF pair or
			# the lone terminator so a blank line stays blank instead of drawing
			# a control glyph.
			if text.ends_with("\r\n"):
				text = text.substr(0, text.length() - 2)
			elif text.ends_with("\n") or text.ends_with("\r"):
				text = text.substr(0, text.length() - 1)
			lines.append(text)
		# TextParagraph may omit the empty line after a terminal hard break.
		if (value.ends_with("\n") or value.ends_with("\r")) and not starts.is_empty() and starts[-1] < value.length():
			lines.append("")
	if _ui_wrap_cache.size() >= UI_LAYOUT_CACHE_LIMIT:
		_ui_wrap_cache.clear()
	_ui_wrap_cache[key] = lines
	return lines

## Fit a single line into `width`, ending in an ellipsis when it does not fit.
## Callers must not pass a clipped width to draw_string instead: a hard clip cuts
## a glyph with no signal that text is missing. Truncation walks grapheme
## boundaries, so it cannot leave half a character on screen.
static func ui_short(value: String, width: float, size := 13) -> String:
	if width <= 0.0:
		return value
	var key := "%d|%.2f|%s|%s" % [size, width, TranslationServer.get_locale(), value]
	var hit: Variant = _ui_short_cache.get(key)
	if hit != null:
		return hit
	var font := ui_font()
	if font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
		if _ui_short_cache.size() >= UI_LAYOUT_CACHE_LIMIT:
			_ui_short_cache.clear()
		_ui_short_cache[key] = value
		return value
	var cuts: Array[int] = []
	for offset in TextServerManager.get_primary_interface().string_get_character_breaks(value):
		if offset > 0 and offset < value.length():
			cuts.append(offset)
	var fitted := ""
	var low := 0
	var high := cuts.size() - 1
	while low <= high:
		var middle := (low + high) / 2
		var candidate := value.substr(0, cuts[middle])
		if font.get_string_size(candidate + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			fitted = candidate
			low = middle + 1
		else:
			high = middle - 1
	var short := fitted.rstrip(" ") + "…"
	if _ui_short_cache.size() >= UI_LAYOUT_CACHE_LIMIT:
		_ui_short_cache.clear()
	_ui_short_cache[key] = short
	return short


static func ui_key(canvas: CanvasItem, at: Vector2, key: String, label: String, tone := PALE) -> float:
	var font := ui_font()
	var width := maxf(18, font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 10)
	px_rect(canvas, Rect2(at, Vector2(width, 19)), BG_2)
	line(canvas, at + Vector2(0, 19), at + Vector2(width, 19), STONE_HI, 1)
	ui_text(canvas, at + Vector2(0, 14), key, 11, PALE, width, HORIZONTAL_ALIGNMENT_CENTER)
	ui_text(canvas, at + Vector2(width + 6, 14), label, 11, tone)
	return width + 6 + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + UI_GAP

static func ui_axis(canvas: CanvasItem, at: Vector2, axis: String, radius := 8.0, tone := PALE) -> void:
	if tone == PALE: tone = axis_color(axis)
	var sides := 3 if axis == "brutality" else (4 if axis == "tactics" else 6)
	poly(canvas, ngon(sides, radius, -PI * 0.5, at), Color.TRANSPARENT, tone, 1.5)
	if axis == "survival":
		disc(canvas, at, radius * INV_PHI * INV_PHI, tone)

static func ui_quality(canvas: CanvasItem, at: Vector2, quality: String) -> void:
	var count := 1 if quality == "plain" else (2 if quality == "etched" else 3)
	for i in count:
		line(canvas, at + Vector2(i * 5, 0), at + Vector2(i * 5, -7), ACCENT if count > 1 else LIGHT_DIM, 1.5)

static func ui_service(canvas: CanvasItem, at: Vector2, service: String, radius := 14.0) -> void:
	var tone := CELL if service == "collector" else FIRE if service == "forge" else TACTICS if service == "mutation" else HEAL if service == "fountain" else DANGER if service in ["death", "abandon"] else PLAYER if service == "character" else ACCENT
	match service:
		"collector":
			var edge := radius * INV_PHI
			poly(canvas, PackedVector2Array([at + Vector2(-edge, -radius), at + Vector2(edge * INV_PHI, -radius), at + Vector2(edge, -radius * INV_PHI), at + Vector2(edge, radius), at + Vector2(-edge, radius)]), Color.TRANSPARENT, tone, 1.5)
			line(canvas, at + Vector2(edge * INV_PHI, -radius), at + Vector2(edge * INV_PHI, -radius * INV_PHI), tone, 1.5)
			line(canvas, at + Vector2(edge * INV_PHI, -radius * INV_PHI), at + Vector2(edge, -radius * INV_PHI), tone, 1.5)
			for i in 3: line(canvas, at + Vector2(-edge * INV_PHI, -radius * 0.25 + i * 5), at + Vector2(edge * INV_PHI, -radius * 0.25 + i * 5), tone, 1)
		"forge":
			poly(canvas, PackedVector2Array([at + Vector2(-radius, -radius * INV_PHI), at + Vector2(radius, -radius * INV_PHI), at + Vector2(radius * INV_PHI, 0), at + Vector2(2, 0), at + Vector2(2, radius * INV_PHI), at + Vector2(radius * INV_PHI, radius), at + Vector2(-radius * INV_PHI, radius), at + Vector2(-2, radius * INV_PHI), at + Vector2(-2, 0), at + Vector2(-radius * INV_PHI, 0)]), tone)
		"mutation":
			var points := ngon(3, radius, -PI * 0.5, at)
			poly(canvas, points, Color.TRANSPARENT, STONE_HI, 1)
			for point in points: disc(canvas, point, radius * INV_PHI * INV_PHI, tone)
			disc(canvas, at, 2, PALE)
		"challenge":
			poly(canvas, PackedVector2Array([at + Vector2(-radius, -radius), at + Vector2(radius, -radius), at + Vector2(radius * INV_PHI, 0), at + Vector2(0, radius * INV_PHI), at + Vector2(-radius * INV_PHI, 0)]), Color.TRANSPARENT, tone, 1.5)
			line(canvas, at + Vector2(0, radius * INV_PHI), at + Vector2(0, radius), tone, 1.5)
			line(canvas, at + Vector2(-radius * INV_PHI, radius), at + Vector2(radius * INV_PHI, radius), tone, 1.5)

		"fountain":
			poly(canvas, PackedVector2Array([at + Vector2(-radius * INV_PHI * INV_PHI, -radius), at + Vector2(radius * INV_PHI * INV_PHI, -radius), at + Vector2(radius * INV_PHI * INV_PHI, -radius * INV_PHI * INV_PHI), at + Vector2(radius * INV_PHI, radius * INV_PHI), at + Vector2(radius * INV_PHI * INV_PHI, radius), at + Vector2(-radius * INV_PHI * INV_PHI, radius), at + Vector2(-radius * INV_PHI, radius * INV_PHI), at + Vector2(-radius * INV_PHI * INV_PHI, -radius * INV_PHI * INV_PHI)]), tone)
			line(canvas, at + Vector2(-radius * INV_PHI * INV_PHI, radius * INV_PHI), at + Vector2(radius * INV_PHI * INV_PHI, radius * INV_PHI), INK, maxf(1.5, radius * 0.08))
		"continue", "abandon":
			var edge := radius * INV_PHI
			poly(canvas, PackedVector2Array([at + Vector2(-edge, radius), at + Vector2(-edge, -radius), at + Vector2(edge, -radius), at + Vector2(edge, radius)]), Color.TRANSPARENT, tone, maxf(2, radius * 0.06))
			line(canvas, at + Vector2(-edge * INV_PHI, radius), at + Vector2(edge * INV_PHI, radius), STONE_HI, 1)
			if service == "abandon":
				line(canvas, at + Vector2(-radius, 0), at + Vector2(radius, 0), tone, 2)
				poly(canvas, ngon(3, radius * INV_PHI * INV_PHI, 0, at + Vector2(radius, 0)), tone)
		"victory":
			poly(canvas, star(5, radius, radius * INV_PHI, -PI * 0.5, at), tone)
			poly(canvas, ngon(5, radius * INV_PHI * INV_PHI, -PI * 0.5, at), INK)
		"death":
			var edge := radius * INV_PHI
			poly(canvas, PackedVector2Array([at + Vector2(-edge, -radius), at + Vector2(-2, -radius), at + Vector2(-edge * INV_PHI, 0), at + Vector2(-2, radius), at + Vector2(-edge, radius)]), LIGHT_DIM)
			poly(canvas, PackedVector2Array([at + Vector2(2, -radius), at + Vector2(edge, -radius), at + Vector2(edge, radius), at + Vector2(2, radius), at + Vector2(edge * INV_PHI, 0)]), tone)
		"character":
			px_rect(canvas, Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2), tone)
			px_rect(canvas, Rect2(at - Vector2.ONE * radius * INV_PHI, Vector2.ONE * radius * INV_PHI * 2), INK)


static func ui_gear(canvas: CanvasItem, at: Vector2, action: String, radius := 12.0, tone := WHITE, identity := "") -> void:
	if tone == WHITE: tone = gear_color(action, identity)
	if identity == "chain_lash":
		for i in 4:
			var point := at + Vector2((i - 1.5) * radius * INV_PHI, sin(i * PI * INV_PHI) * radius * INV_PHI * INV_PHI * INV_PHI)
			ring(canvas, point, radius * INV_PHI * INV_PHI, tone, maxf(1.5, radius * 0.06), 16)
		return
	if identity == "fractal_edge":
		poly(canvas, ngon(3, radius, -PI * 0.5, at), tone)
		poly(canvas, ngon(3, radius * INV_PHI, PI * 0.5, at), BG_1)
		line(canvas, at + Vector2(0, radius * INV_PHI), at + Vector2(0, radius), tone, maxf(2, radius * 0.08))
		return
	match action:
		"melee":
			poly(canvas, PackedVector2Array([at + Vector2(-radius * 0.6, radius * 0.5), at + Vector2(radius * 0.65, -radius), at + Vector2(radius, -radius * 0.9), at + Vector2(-radius * 0.4, radius * 0.7)]), tone)
			line(canvas, at + Vector2(-radius * 0.9, radius * 0.2), at + Vector2(-radius * 0.2, radius * 0.9), tone, 2)
			line(canvas, at + Vector2(-radius * 0.55, radius * 0.55), at + Vector2(-radius, radius), tone, 2)
		"shield":
			poly(canvas, PackedVector2Array([at + Vector2(-radius * 0.8, -radius * 0.8), at + Vector2(radius * 0.8, -radius * 0.8), at + Vector2(radius * 0.65, radius * 0.3), at + Vector2(0, radius), at + Vector2(-radius * 0.65, radius * 0.3)]), Color.TRANSPARENT, tone, 2)
			line(canvas, at + Vector2(0, -radius * INV_PHI), at + Vector2(0, radius * INV_PHI), tone, 1)
		"kunai":
			poly(canvas, PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius * 0.45, radius * 0.4), at + Vector2(0, radius * 0.2), at + Vector2(-radius * 0.45, radius * 0.4)]), tone)
			ring(canvas, at + Vector2(0, radius * 0.8), radius * 0.2, tone, 1.5)
		"aegis":
			ring(canvas, at, radius, tone, 1.5, 32, -PI * INV_PHI, PI * INV_PHI)
			ring(canvas, at, radius * INV_PHI, tone, 2)
			disc(canvas, at, radius * INV_PHI * INV_PHI * INV_PHI, tone)
		_:
			ring(canvas, at + Vector2(0, -radius * 0.8), radius * 0.25, tone, 1.5)
			poly(canvas, ngon(4, radius * INV_PHI, -PI * 0.5, at + Vector2(0, radius * 0.2)), Color.TRANSPARENT, tone, 2)
			disc(canvas, at + Vector2(0, radius * 0.2), 1.5, tone)

static func gear_color(action: String, identity := "") -> Color:
	if Data.gear.items.has(identity):
		return axis_color(str(Data.gear.items[identity].get("attribute", "survival")))
	match action:
		"melee": return BRUTALITY
		"kunai": return TACTICS
		"shield", "aegis", "amulet": return SURVIVAL
		_: return PALE

static func ui_brand(canvas: CanvasItem, at: Vector2, radius: float) -> void:
	var outer := ngon(4, radius, -PI * 0.5, at)
	poly(canvas, outer, STONE_DIM)
	poly(canvas, ngon(4, radius * INV_PHI, -PI * 0.5, at), INK)
	poly(canvas, ngon(3, radius * INV_PHI, -PI * 0.5, at), ACCENT)
	poly(canvas, ngon(3, radius * INV_PHI * INV_PHI, -PI * 0.5, at + Vector2(0, radius * INV_PHI * INV_PHI)), INK)
	line(canvas, at + Vector2(0, radius * INV_PHI), at + Vector2(0, radius * PHI), STONE_HI, 1)

static func ui_heading(canvas: CanvasItem, title: String, context: String, wallet := "", wallet_tone := Color.TRANSPARENT) -> void:
	ui_text(canvas, Vector2(52, 53), context, 11, LIGHT_DIM)
	ui_text(canvas, Vector2(52, 84), title, 24, PALE)
	line(canvas, Vector2(52, 98), Vector2(52.0 + 96.0, 98), STONE, 1)
	if not wallet.is_empty():
		var tone := wallet_tone
		if tone.a <= 0.0:
			# Callers that do not pass a tone keep the old gold/cell distinction,
			# matched against both the English word and its translated form.
			var gold := TranslationServer.translate("UI_UNIT_GOLD")
			tone = GOLD if "Gold" in wallet or (not gold.is_empty() and gold in wallet) else CELL
		ui_text(canvas, Vector2(496, 80), wallet, 13, tone, 220, HORIZONTAL_ALIGNMENT_RIGHT)
