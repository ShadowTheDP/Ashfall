class_name CharacterVisual
extends Node2D
## The player is a rotating SOLID, projected from 3D to 2D with Geom3D.
## No texture, no model, no Sprite2D: every pixel is a projected polygon.
##
## Motion carries the identity (docs/design/math-art.md):
##   idle   the body turns slowly on y, so the form always reads as 3D
##   run    leans into travel and spins faster
##   jump   exactly one quarter turn about the requested axis, so the
##          existing "one jump = one new face" rule survives the upgrade
##   hit    tone goes to WHITE for a few frames
##
## Faces are drawn back to front and back faces are culled by their 3D normal,
## which keeps the torus (96 quads) near ~48 drawn faces per frame.

const R := 21.0                  # body radius; height lands at ~43 px
const DEPTH_RATIO := 0.55        # a slab, not a cube
const PITCH := 0.30              # look slightly down so y-rotation reads
const FOCAL := 260.0
const IDLE_SPIN := 0.5           # rad/s
const RUN_SPIN := 1.6
const LEAN_MAX := 0.10           # rad
const CORE_R := 2.8

# Octahedron winding, outward. Vertex order from Geom3D.octahedron().
const OCTA_FACES := [
	[0, 2, 1], [0, 3, 2], [0, 4, 3], [0, 1, 4],
	[5, 1, 2], [5, 2, 3], [5, 3, 4], [5, 4, 1],
]

var _parts: Array = []
var _id := "square"
var _built := false
var _tone := MathArt.WHITE
var _t := 0.0
var _spin := 0.0
var _run := 0.0
var _lean := 0.0
var _tumble := 0.0
var _tumble_axis := 2
var _flash := 0.0


func _ready() -> void:
	if not _built:
		_build()  # Data may not have been reachable when setup() ran


func _process(delta: float) -> void:
	_t += delta
	_spin += lerpf(IDLE_SPIN, RUN_SPIN, absf(_run)) * delta
	queue_redraw()


# --- API --------------------------------------------------------------------

## Reads body/sides/spokes/tone from data/characters.json. Unknown id = prism.
func setup(character_id: String) -> void:
	_id = character_id
	_build()


func _build() -> void:
	var table := _table()
	if table.is_empty():
		return
	var def: Dictionary = table.get(_id, {})
	var body := str(def.get("body", "prism"))
	var sides := maxi(3, int(def.get("sides", 4)))
	var spokes := int(def.get("spokes", 0))
	_tone = _tone_for(str(def.get("tone", "white")))
	_parts.clear()
	match body:
		"octa":
			_parts.append(_part(Geom3D.octahedron(R), OCTA_FACES.duplicate(true), 1.0))
		"star":
			var n := maxi(3, spokes if spokes > 0 else 5)
			_parts.append(_part(_star_prism(n, R, R * 0.55, R * DEPTH_RATIO), _star_faces(n), 1.0))
		"torus":
			var ring := Geom3D.torus_faces(12, 8)
			ring.reverse()  # Geom3D winds the tube inward; flip so culling keeps the outside
			# A torus flat in the XZ plane projects to a thin bar and reads as a
			# smudge. Stood up in XY it is a 41 px ring with a real hole, and the
			# y-spin sweeps it like a coin: the clearest 3D tell of the six.
			var t := Geom3D.rotate_x(Geom3D.torus(R * 0.72, R * 0.26, 12, 8), PI * 0.5)
			_parts.append(_part(t, ring, 1.0))
		"helix":
			var strands := maxi(1, spokes)
			var samples := 20
			_parts.append(_part(Geom3D.helix(R * 0.8, R * 1.6, 1.75, samples, strands),
				[], 1.0, PITCH, samples + 1, strands))
			_parts.append(_part(Geom3D.prism(3, R * 0.30, R * 0.30), _prism_faces(3), 1.0))
		"gyro":
			# A flat slab pierced by a vertical column that turns the other way.
			# Two slabs on the same axis just fuse into one lumpy prism.
			var slab := _upright(Geom3D.prism(4, R * 0.95, R * 0.95 * DEPTH_RATIO))
			_parts.append(_part(slab, _prism_faces(4), 1.0))
			# Tilted across the slab, so the column visibly passes through it and
			# the two counter-rotating solids never fuse into one box.
			var tower := Geom3D.rotate_z(
				Geom3D.rotate_x(_upright(Geom3D.prism(4, R * 0.5, R * 1.8)), PI * 0.5), 0.38)
			_parts.append(_part(tower, _prism_faces(4), -1.0, PITCH, 0, 1, -0.25))
		_:
			_parts.append(_part(_upright(Geom3D.prism(sides, R, R * DEPTH_RATIO)),
				_prism_faces(sides), 1.0))
	_built = true
	queue_redraw()


## Half-extent in px, for the ground shadow.
func body_size() -> float:
	return R


## amount 0..1 = 0..90 degrees. Axis: 0=x, 1=y, 2=z. Default is z, which is
## the in-plane face turn the flat square used to do.
func set_tumble(amount: float, axis: int = 2) -> void:
	_tumble = clampf(amount, 0.0, 1.0)
	_tumble_axis = clampi(axis, 0, 2)


## Signed -1..1, sign = travel direction. Also drives the spin rate.
func set_run_lean(amount: float) -> void:
	_run = clampf(amount, -1.0, 1.0)
	_lean = _run * LEAN_MAX


func set_flash(amount: float) -> void:
	_flash = clampf(amount, 0.0, 1.0)


# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	if _parts.is_empty():
		return
	var bob := 0.0
	if _run > 0.35:
		bob = absf(sin(_t * 15.0)) * -2.0 * _run
	else:
		bob = sin(_t * 2.6) * 1.2
	var origin := Vector2(0.0, bob)
	var tone := _tone.lerp(MathArt.WHITE, _flash)
	# draw_solid lightens a face by up to +0.275, so a WHITE base flattens the
	# whole body to one value. Pre-darkening keeps headroom: front faces land at
	# the character's tone, edge-on faces stay dark, and the form reads.
	var base := MathArt.shade(tone, -0.15)
	var quarter := _tumble * PI * 0.5

	for part in _parts:
		var points: PackedVector3Array = part["points"]
		var sign_spin: float = float(part["spin"])
		points = Geom3D.rotate_y(points, _spin * sign_spin)
		match _tumble_axis:
			0:
				points = Geom3D.rotate_x(points, quarter)
			1:
				points = Geom3D.rotate_y(points, quarter * sign_spin)
			_:
				points = Geom3D.rotate_z(points, quarter)
		if absf(_lean) > 0.0001:
			points = Geom3D.rotate_z(points, _lean)

		var pitch: float = float(part["pitch"])
		var projected := Geom3D.project(points, FOCAL, origin, pitch)
		var depths := Geom3D.depths(points, pitch)
		var faces: Array = part["faces"]
		if faces.is_empty():
			_draw_tube(projected, depths, part, tone)
		else:
			_draw_body(points, projected, depths, faces,
				MathArt.shade(base, float(part["tint"])), pitch)

	# The core: a solid dot so the body never reads as a wireframe cage.
	MathArt.disc(self, origin, CORE_R * (0.72 + 0.28 * sin(_t * 6.0)), MathArt.INK)


func _draw_body(points: PackedVector3Array, projected: PackedVector2Array,
		depths: PackedFloat32Array, faces: Array, tone: Color, pitch: float) -> void:
	var sp := sin(pitch)
	var cp := cos(pitch)
	var visible := []
	var front: Array = []
	var front_depth := -INF
	for face in faces:
		var normal := _normal(points, face)
		if normal.y * sp + normal.z * cp <= 0.0:
			continue
		visible.append(face)
		var d := 0.0
		for index in face:
			d += depths[index]
		d /= float(face.size())
		if d > front_depth:
			front_depth = d
			front = face
	if visible.is_empty():
		return
	Geom3D.draw_solid(self, projected, visible, tone, MathArt.WHITE, pitch, depths)
	# One bright edge on the front-most face only, so the silhouette holds.
	var loop := PackedVector2Array()
	for index in front:
		loop.append(projected[index])
	loop.append(loop[0])
	draw_polyline(loop, Color(MathArt.WHITE, 0.85), 1.0, true)


## Helix: each strand is a tube of short segments, far ones dimmer.
func _draw_tube(projected: PackedVector2Array, depths: PackedFloat32Array,
		part: Dictionary, tone: Color) -> void:
	var stride: int = int(part["stride"])
	var strands: int = int(part["strands"])
	for front_pass in 2:
		for s in strands:
			var base := s * stride
			for i in stride - 1:
				var a := base + i
				var b := a + 1
				var z := (depths[a] + depths[b]) * 0.5
				if (z > 0.0) != (front_pass == 1):
					continue
				var k := clampf((z + R) / (R * 2.0), 0.0, 1.0)
				MathArt.line(self, projected[a], projected[b],
					MathArt.shade(tone, (k - 0.5) * 0.5), 1.3 + 1.5 * k)


# --- Mesh building (once per setup, never per frame) ------------------------

func _part(points: PackedVector3Array, faces: Array, spin: float,
		pitch: float = PITCH, stride: int = 0, strands: int = 1, tint: float = 0.0) -> Dictionary:
	return {"points": points, "faces": faces, "spin": spin,
		"pitch": pitch, "stride": stride, "strands": strands, "tint": tint}


## Geom3D puts the first prism vertex on +x, so a 4-sided prism projects as a
## diamond. A quarter turn puts the flat faces on the axes and the default body
## still reads as the plain square it replaced.
func _upright(points: PackedVector3Array) -> PackedVector3Array:
	return Geom3D.rotate_z(points, PI * 0.25)


## Geom3D.prism_faces() gives the side quads only; a solid needs its caps.
func _prism_faces(sides: int) -> Array:
	var faces := Geom3D.prism_faces(sides)
	var bottom := []
	var top := []
	for i in sides:
		bottom.append(i)
		top.append(sides + i)
	bottom.reverse()  # wind the back cap away from the camera
	faces.append(bottom)
	faces.append(top)
	return faces


## Star caps are concave, so they are fanned from two extra centre vertices
## instead of drawn as one polygon.
func _star_prism(points: int, outer: float, inner: float, depth: float) -> PackedVector3Array:
	var ring := Geom3D.star_prism(points, outer, inner, depth)
	ring.append(Vector3(0, 0, -depth * 0.5))
	ring.append(Vector3(0, 0, depth * 0.5))
	return ring


func _star_faces(points: int) -> Array:
	var n := points * 2
	var faces := []
	for i in n:
		var j := (i + 1) % n
		faces.append([i, j, n + j, n + i])
	var back := n * 2
	var front := n * 2 + 1
	for i in n:
		var j := (i + 1) % n
		faces.append([back, j, i])
		faces.append([front, n + i, n + j])
	return faces


## Newell's normal. Only the sign is used, for back-face culling.
static func _normal(points: PackedVector3Array, face: Array) -> Vector3:
	var n := Vector3.ZERO
	var count := face.size()
	for i in count:
		var a := points[face[i]]
		var b := points[face[(i + 1) % count]]
		n += Vector3((a.y - b.y) * (a.z + b.z),
			(a.z - b.z) * (a.x + b.x),
			(a.x - b.x) * (a.y + b.y))
	return n


# --- Data -------------------------------------------------------------------

## Resolved by path, not by the `Data` global, so the file also compiles under
## --check-only. Empty means "not reachable yet"; _ready() retries.
func _table() -> Dictionary:
	if not is_inside_tree():
		return {}
	var data = get_node_or_null("/root/Data")
	if data == null:
		return {}
	if not data.loaded:
		data.load_all()
	var table: Dictionary = data.characters
	return table


func _tone_for(name: String) -> Color:
	match name:
		"pale":
			return MathArt.PALE
		"light":
			return MathArt.LIGHT
		_:
			return MathArt.WHITE
