class_name Geom3D
extends RefCounted
## Minimal 3D → 2D projection so characters can be pseudo-3D without any
## texture or model asset. Everything stays inside MathArt's visual language:
## a body is a set of 3D points, projected with a weak perspective, then drawn
## as filled polygons sorted back-to-front.
##
## Usage:
##   var mesh := Geom3D.box(Vector3(10, 10, 10))
##   mesh = Geom3D.rotate_y(mesh, angle)
##   var projected := Geom3D.project(mesh, focal)
##   Geom3D.draw_solid(canvas, projected, MathArt.PALE, MathArt.WHITE)

const NEAR := 1.0


# ------------------------------------------------------------------ transforms

static func rotate_x(points: PackedVector3Array, angle: float) -> PackedVector3Array:
	var c := cos(angle)
	var s := sin(angle)
	var out := PackedVector3Array()
	for p in points:
		out.append(Vector3(p.x, p.y * c - p.z * s, p.y * s + p.z * c))
	return out


static func rotate_y(points: PackedVector3Array, angle: float) -> PackedVector3Array:
	var c := cos(angle)
	var s := sin(angle)
	var out := PackedVector3Array()
	for p in points:
		out.append(Vector3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c))
	return out


static func rotate_z(points: PackedVector3Array, angle: float) -> PackedVector3Array:
	var c := cos(angle)
	var s := sin(angle)
	var out := PackedVector3Array()
	for p in points:
		out.append(Vector3(p.x * c - p.y * s, p.x * s + p.y * c, p.z))
	return out


static func translate(points: PackedVector3Array, offset: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in points:
		out.append(p + offset)
	return out


static func scale(points: PackedVector3Array, factor: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in points:
		out.append(Vector3(p.x * factor.x, p.y * factor.y, p.z * factor.z))
	return out


# ------------------------------------------------------------------- primitives

## Axis-aligned box, 8 vertices, index order:
## 0..3 bottom (z-, x+, z+, x-), 4..7 top (same order).
static func box(size: Vector3) -> PackedVector3Array:
	var h := size * 0.5
	return PackedVector3Array([
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z),
		Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	])


## Prism: a regular n-gon extruded along z. 2n vertices, bottom ring first.
static func prism(sides: int, radius: float, depth: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var hz := depth * 0.5
	for i in sides:
		var a := TAU * float(i) / float(maxi(3, sides))
		out.append(Vector3(cos(a) * radius, sin(a) * radius, -hz))
	for i in sides:
		var a := TAU * float(i) / float(maxi(3, sides))
		out.append(Vector3(cos(a) * radius, sin(a) * radius, hz))
	return out


## Octahedron: 6 vertices.
static func octahedron(radius: float) -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(0, -radius, 0), Vector3(radius, 0, 0), Vector3(0, 0, -radius),
		Vector3(-radius, 0, 0), Vector3(0, 0, radius), Vector3(0, radius, 0),
	])


## Star prism: alternating outer/inner radius ring, extruded. 4n vertices.
static func star_prism(points: int, outer: float, inner: float, depth: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var hz := depth * 0.5
	var count := maxi(3, points) * 2
	for i in count:
		var a := TAU * float(i) / float(count)
		var r := outer if i % 2 == 0 else inner
		out.append(Vector3(cos(a) * r, sin(a) * r, -hz))
	for i in count:
		var a := TAU * float(i) / float(count)
		var r := outer if i % 2 == 0 else inner
		out.append(Vector3(cos(a) * r, sin(a) * r, hz))
	return out


## Torus wireframe: `major` samples around the ring, `minor` around the tube.
## Returned as a flat point list; pair it with `torus_faces`.
static func torus(major: float, minor: float, ring_samples: int, tube_samples: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in ring_samples:
		var u := TAU * float(i) / float(ring_samples)
		for j in tube_samples:
			var v := TAU * float(j) / float(tube_samples)
			var r := major + minor * cos(v)
			out.append(Vector3(cos(u) * r, minor * sin(v), sin(u) * r))
	return out


static func torus_faces(ring_samples: int, tube_samples: int) -> Array:
	var faces := []
	for i in ring_samples:
		for j in tube_samples:
			var a := i * tube_samples + j
			var b := ((i + 1) % ring_samples) * tube_samples + j
			var c := ((i + 1) % ring_samples) * tube_samples + (j + 1) % tube_samples
			var d := i * tube_samples + (j + 1) % tube_samples
			faces.append([a, b, c, d])
	return faces


## Helix tube: points along a helix, `strands` interleaved.
static func helix(radius: float, height: float, turns: float, samples: int, strands: int = 1) -> PackedVector3Array:
	var out := PackedVector3Array()
	for s in maxi(1, strands):
		var phase := TAU * float(s) / float(maxi(1, strands))
		for i in samples + 1:
			var t := float(i) / float(samples)
			var a := TAU * turns * t + phase
			out.append(Vector3(cos(a) * radius, lerpf(-height * 0.5, height * 0.5, t), sin(a) * radius))
	return out


## Wireframe face list for a prism with `sides` sides (2*sides vertices).
static func prism_faces(sides: int) -> Array:
	var faces := []
	for i in sides:
		var j := (i + 1) % sides
		faces.append([i, j, sides + j, sides + i])
	return faces


static func ngon_faces(sides: int, offset: int, flip: bool) -> Array:
	var loop := []
	for i in sides:
		loop.append(offset + i)
	if flip:
		loop.reverse()
	return [loop]


# ------------------------------------------------------------------ projection

## Weak perspective. `focal` is the camera distance in the same units as the
## model; larger focal = flatter, more orthographic.
static func project(points: PackedVector3Array, focal: float = 220.0,
		origin: Vector2 = Vector2.ZERO, pitch: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cp := cos(pitch)
	var sp := sin(pitch)
	for p in points:
		# Pitch the camera: rotate around x so we look slightly down.
		var y := p.y * cp - p.z * sp
		var z := p.y * sp + p.z * cp
		var depth := maxf(NEAR, focal + z)
		var k := focal / depth
		out.append(origin + Vector2(p.x * k, y * k))
	return out


## Signed depth per point, used for back-to-front sorting of faces.
static func depths(points: PackedVector3Array, pitch: float = 0.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var cp := cos(pitch)
	var sp := sin(pitch)
	for p in points:
		out.append(p.y * sp + p.z * cp)
	return out


# --------------------------------------------------------------------- drawing

## Filled faces, sorted back to front. `faces` is an Array of index arrays.
## `tone` is the base colour; each face is shaded by its normal so the form
## reads without any outline at all.
static func draw_solid(canvas: CanvasItem, points: PackedVector2Array,
		faces: Array, tone: Color, rim: Color, pitch: float = 0.0,
		depths_in: PackedFloat32Array = PackedFloat32Array(),
		contrast: float = 0.55) -> void:
	if points.size() == 0:
		return
	var sorted := _sort_faces(faces, depths_in)
	for face in sorted:
		var poly := PackedVector2Array()
		for index in face:
			if index >= 0 and index < points.size():
				poly.append(points[index])
		if poly.size() < 3:
			continue
		var shade := _face_shade(poly, points)
		var fill := MathArt.shade(tone, (shade - 0.5) * contrast)
		MathArt.poly(canvas, poly, fill, MathArt.with_alpha(rim, 0.28), 1.0)


## Wireframe only: every edge of every face, back faces dimmed.
static func draw_wire(canvas: CanvasItem, points: PackedVector2Array,
		faces: Array, color: Color, width: float = 1.0) -> void:
	for face in faces:
		var poly := PackedVector2Array()
		for index in face:
			if index >= 0 and index < points.size():
				poly.append(points[index])
		if poly.size() < 2:
			continue
		for i in poly.size():
			MathArt.line(canvas, poly[i], poly[(i + 1) % poly.size()], color, width)


static func _sort_faces(faces: Array, depths_in: PackedFloat32Array) -> Array:
	if depths_in.size() == 0:
		return faces
	var keyed := []
	for face in faces:
		var total := 0.0
		for index in face:
			if index >= 0 and index < depths_in.size():
				total += depths_in[index]
		keyed.append([total / float(maxi(1, face.size())), face])
	keyed.sort_custom(func(a, b): return a[0] > b[0])
	var out := []
	for item in keyed:
		out.append(item[1])
	return out


static func _face_shade(poly: PackedVector2Array, all_points: PackedVector2Array) -> float:
	# Fill ratio (area / bounding box) says how "square-on" a face is, but it
	# cannot say WHICH way it faces: a pentagon cap scores ~0.7 while a side
	# quad scores ~0.95, so the sides came out brighter than the top and the
	# solid read as a dark lump.
	#
	# Instead, orient by winding. The polygon's signed area is positive for a
	# front-facing face and negative for a back-facing one in this projection.
	# Front faces get a fixed bright band, back faces a dark one, and the fill
	# ratio only modulates inside that band.
	if poly.size() < 3:
		return 0.5
	var area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	var signed_area := area * 0.5
	var bounds := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		bounds = bounds.expand(p)
	var ref := maxf(1.0, bounds.size.x * bounds.size.y)
	var fill := clampf(absf(signed_area) / ref, 0.0, 1.0)
	if signed_area >= 0.0:
		# Front: 0.62 .. 0.92, brighter the more square-on it is.
		return lerpf(0.62, 0.92, fill)
	# Back: 0.05 .. 0.30. Never competes with a front face.
	return lerpf(0.05, 0.30, fill)
