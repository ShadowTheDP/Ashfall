class_name Geom3D
extends RefCounted
## The Warden's prism projection and depth-sorted MathArt faces.

const NEAR := 1.0


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


## Wireframe face list for a prism with `sides` sides (2*sides vertices).
static func prism_faces(sides: int) -> Array:
	var faces := []
	for i in sides:
		var j := (i + 1) % sides
		faces.append([i, j, sides + j, sides + i])
	return faces


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
