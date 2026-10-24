class_name SkillTree
extends CanvasLayer
## The permanent skill tree. Nodes are placed by normalised "at" coordinates in
## data/skill_nodes.json, so the layout lives in data, not in this file.
## The cursor jumps to the NEAREST node in the pressed direction: with a tree
## this shape, index-stepping would be unusable.

signal closed

const TREE_RECT := Rect2(40.0, 56.0, 688.0, 312.0)
const CARD_RECT := Rect2(40.0, 380.0, 688.0, 66.0)
const NODE_R := 14.0
const PAD := 26.0

const BG := Color(0.024, 0.024, 0.024, 0.97)
const PANEL := Color(0.047, 0.047, 0.047, 0.94)

var _canvas: Control
var _ids: Array[String] = []
var _pos: Dictionary = {}
var _index := 0
var _open := false
var _t := 0.0
var _flash_t := 0.0
var _note := ""
var _note_t := 0.0


func _ready() -> void:
	layer = 60
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_canvas()


func _ensure_canvas() -> void:
	if _canvas != null:
		return
	# CanvasLayer cannot draw; one full-rect Control paints and calls back.
	_canvas = Control.new()
	_canvas.name = "Paint"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_paint.bind(_canvas))
	add_child(_canvas)


# ------------------------------------------------------------------ public API

func open() -> void:
	_ensure_canvas()
	_ids.clear()
	for key in Data.skill_nodes.keys():
		_ids.append(str(key))
	_ids.sort()
	_layout()
	_index = _first_available()
	_open = true
	visible = true
	_note = ""
	_note_t = 0.0
	_flash_t = 0.0
	Sfx.play("ui", -10)
	_canvas.queue_redraw()


func is_open() -> bool:
	return _open


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	Sfx.play("ui", -12)
	closed.emit()


# ---------------------------------------------------------------------- input

func _process(delta: float) -> void:
	if not _open:
		return
	_t += delta
	_flash_t = maxf(0.0, _flash_t - delta)
	_note_t = maxf(0.0, _note_t - delta)
	_canvas.queue_redraw()


## _input, not _unhandled_input: the HUD also listens for Esc and it is
## later in the tree, so unhandled input reaches it first. A modal panel
## has to claim the key before the HUD can pause the game under it.
func _input(event: InputEvent) -> void:
	if not _open:
		return
	if not (event is InputEventKey) or not event.pressed:
		return
	# A modal owns every key while it is up. A key it does not use would
	# otherwise reach the hub's proximity handler and raise a second panel
	# (J) or start a floor (Enter) underneath this one.
	get_viewport().set_input_as_handled()
	if event.echo:
		return
	match event.physical_keycode:
		KEY_ESCAPE:
			close()
		KEY_LEFT, KEY_A:
			_move(Vector2.LEFT)
		KEY_RIGHT, KEY_D:
			_move(Vector2.RIGHT)
		KEY_UP, KEY_W:
			_move(Vector2.UP)
		KEY_DOWN, KEY_S:
			_move(Vector2.DOWN)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_buy()


func _move(direction: Vector2) -> void:
	if _ids.size() < 2 or not _pos.has(_ids[_index]):
		return
	var from: Vector2 = _pos[_ids[_index]]
	var best := -1
	var best_score := INF
	for i in _ids.size():
		if i == _index or not _pos.has(_ids[i]):
			continue
		var delta: Vector2 = _pos[_ids[i]] - from
		var along := delta.dot(direction)
		if along <= 2.0:
			continue
		# Off-axis distance is penalised, not forbidden: a strict cone would
		# dead-end on a wide row.
		var score := along + absf(delta.cross(direction)) * 2.0
		if score < best_score:
			best_score = score
			best = i
	if best >= 0:
		_index = best
		Sfx.play("ui", -14)
		_canvas.queue_redraw()


func _buy() -> void:
	if _ids.is_empty():
		return
	var id := _ids[_index]
	if Profile.has_skill(id):
		_note = "ALREADY OWNED"
		_note_t = 1.4
		_canvas.queue_redraw()
		return
	if Profile.buy_skill(id):
		_note = "LEARNED " + _name_of(id)
		_note_t = 1.6
		Sfx.play("reward", -8)
		_canvas.queue_redraw()
		return
	_flash_t = 0.45
	_note = _blocked_reason(id)
	_note_t = 1.8
	Sfx.play("block", -10)
	_canvas.queue_redraw()


# ---------------------------------------------------------------------- data

func _layout() -> void:
	_pos.clear()
	var inner := TREE_RECT.grow(-PAD)
	for id in _ids:
		var at: Array = _node(id).get("at", [0.5, 0.5])
		var nx := float(at[0]) if at.size() > 0 else 0.5
		var ny := float(at[1]) if at.size() > 1 else 0.5
		_pos[id] = Vector2(
			inner.position.x + inner.size.x * clampf(nx, 0.0, 1.0),
			inner.position.y + inner.size.y * clampf(ny, 0.0, 1.0)
		)


func _node(id: String) -> Dictionary:
	var out: Variant = Data.skill_nodes.get(id, {})
	return out if typeof(out) == TYPE_DICTIONARY else {}


func _name_of(id: String) -> String:
	return str(_node(id).get("name", id))


func _requires(id: String) -> Array:
	var out: Variant = _node(id).get("requires", [])
	return out if typeof(out) == TYPE_ARRAY else []


func _cost(id: String) -> int:
	return int(_node(id).get("cost", 0))


func _first_available() -> int:
	for i in _ids.size():
		if Profile.skill_available(_ids[i]):
			return i
	return 0


func _blocked_reason(id: String) -> String:
	if Profile.cells < _cost(id):
		return "NEED %d CELLS" % _cost(id)
	var missing: Array[String] = []
	for parent in _requires(id):
		if not Profile.has_skill(str(parent)):
			missing.append(_name_of(str(parent)))
	if missing.is_empty():
		return "CANNOT LEARN"
	return "REQUIRES " + ", ".join(missing)


# -------------------------------------------------------------------- painting

func _paint(canvas: Control) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var size := canvas.get_viewport_rect().size
	MathArt.px_rect(canvas, Rect2(Vector2.ZERO, size), BG)
	# Header band, then the two framed panels. Order matters: the panels cast
	# the shadow, the band lights the top of the screen.
	MathArt.px_rect(canvas, Rect2(40.0, 20.0, size.x - 80.0, 34.0), Color(MathArt.BG_1, 0.95))
	MathArt.px_rect(canvas, Rect2(40.0, 54.0, size.x - 80.0, 1.0), Color(MathArt.STONE, 0.85))
	_panel(canvas, TREE_RECT)
	canvas.draw_string(font, Vector2(40.0, 40.0), "SKILL TREE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MathArt.PALE)
	MathArt.px_rect(canvas, Rect2(40.0, 42.0, 76.0, 1.0), MathArt.PALE_DIM)

	var owned := 0
	for id in _ids:
		if Profile.has_skill(id):
			owned += 1
	_text(canvas, font, Vector2(40.0, 52.0), "%d / %d OWNED" % [owned, _ids.size()], 8, MathArt.STONE_HI)
	_text(canvas, font, Vector2(size.x - 208.0, 40.0), "CELLS %d" % Profile.cells, 11,
		MathArt.PALE, 168.0, HORIZONTAL_ALIGNMENT_RIGHT)

	if _ids.is_empty():
		_text(canvas, font, Vector2(0.0, 220.0), "NO SKILLS RECORDED", 12, MathArt.MID,
			size.x, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_draw_edges(canvas)
		_draw_nodes(canvas, font)
	_draw_card(canvas, font)
	_draw_footer(canvas, font, size)


## Drop shadow, fill, lit top edge, dark bottom edge. One value step below the
## tree, so the graph reads as laid on top of a plate.
func _panel(canvas: CanvasItem, rect: Rect2) -> void:
	MathArt.px_rect(canvas, Rect2(rect.position + Vector2(3.0, 4.0), rect.size), Color(MathArt.BLACK, 0.55))
	MathArt.px_rect(canvas, rect, PANEL)
	MathArt.px_rect(canvas, Rect2(rect.position, Vector2(rect.size.x, 1.0)), Color(MathArt.PALE, 0.8))
	MathArt.px_rect(canvas, Rect2(rect.position + Vector2(0.0, rect.size.y - 2.0), Vector2(rect.size.x, 2.0)),
		Color(MathArt.BLACK, 0.9))
	MathArt.px_rect(canvas, Rect2(rect.position + Vector2(0.0, 1.0), Vector2(1.0, rect.size.y - 3.0)),
		Color(MathArt.STONE, 0.8))
	MathArt.px_rect(canvas, Rect2(rect.position + Vector2(rect.size.x - 1.0, 1.0), Vector2(1.0, rect.size.y - 3.0)),
		Color(MathArt.STONE, 0.8))


## Branches are tapered quads: thick at the parent, thin at the child, so a
## bought path reads as a spine rather than a hairline.
func _draw_edges(canvas: CanvasItem) -> void:
	for id in _ids:
		if not _pos.has(id):
			continue
		var child: Vector2 = _pos[id]
		var owned := Profile.has_skill(id)
		var available := Profile.skill_available(id)
		var tint := MathArt.WHITE if owned else (MathArt.PALE_DIM if available else MathArt.STONE)
		var alpha := 0.75 if owned else (0.45 if available else 0.30)
		var root_half := 2.6 if owned else (2.0 if available else 1.4)
		for parent in _requires(id):
			var parent_id := str(parent)
			if not _pos.has(parent_id):
				continue
			var from: Vector2 = _pos[parent_id]
			var direction := (child - from).normalized()
			var side := direction.orthogonal()
			var a := from + direction * NODE_R
			var b := child - direction * NODE_R
			MathArt.px_poly(canvas, PackedVector2Array([
				a + side * root_half, b + side * 0.8, b - side * 0.8, a - side * root_half,
			]), Color(tint, alpha))


func _draw_nodes(canvas: CanvasItem, font: Font) -> void:
	for i in _ids.size():
		var id := _ids[i]
		if not _pos.has(id):
			continue
		var center: Vector2 = _pos[id]
		var owned := Profile.has_skill(id)
		var available := Profile.skill_available(id)
		var selected := i == _index

		# Three states, three silhouettes: bought is a solid white plate with a
		# cut core, available is a filled cog with a lit rim, locked is a hollow
		# shell. Nothing here leans on hue.
		var fill := MathArt.INK
		var line := MathArt.STONE_HI
		var width := 1.0
		if owned:
			fill = MathArt.WHITE
			line = MathArt.BLACK
			width = 2.0
		elif available:
			fill = MathArt.BG_2
			line = MathArt.PALE
			width = 2.0
		if i == _index and _flash_t > 0.0:
			line = MathArt.WHITE
			width = 3.0

		if selected:
			# Halo under the plate, so the cursor node lifts off the tree.
			MathArt.glow(canvas, center, NODE_R + 10.0, Color(MathArt.WHITE, 0.6), 3)
		MathArt.px_poly(canvas, MathArt.ngon(6, NODE_R, PI / 6.0, center), fill, line, width)
		if owned:
			# A small hollow core keeps the solid white node from reading as a
			# filled blob and matches the player's "square inside a square".
			MathArt.px_poly(canvas, MathArt.ngon(6, NODE_R * 0.34, PI / 6.0, center), MathArt.INK)
		elif available:
			MathArt.disc(canvas, center, 3.4, MathArt.WHITE)
			MathArt.ring(canvas, center, 5.6, Color(MathArt.PALE_DIM, 0.7), 1.0, 6)
		else:
			MathArt.disc(canvas, center, 2.2, MathArt.STONE_HI)

		if selected:
			var pulse := 0.45 + 0.35 * sin(_t * 5.0)
			MathArt.ring(canvas, center, NODE_R + 6.0, Color(MathArt.WHITE, pulse), 2.0, 6)

		_text(canvas, font, Vector2(center.x - 60.0, center.y + NODE_R + 14.0), _name_of(id), 8,
			MathArt.WHITE if selected else (MathArt.PALE if owned or available else MathArt.STONE_HI),
			120.0, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_card(canvas: CanvasItem, font: Font) -> void:
	var rect := CARD_RECT
	_panel(canvas, rect)
	if _ids.is_empty():
		_text(canvas, font, Vector2(rect.position.x, rect.position.y + 34.0), "NO SKILLS RECORDED",
			9, MathArt.STONE_HI, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var id := _ids[_index]
	var node := _node(id)
	var owned := Profile.has_skill(id)
	var available := Profile.skill_available(id)

	var name_color := MathArt.WHITE if available or owned else MathArt.MID
	_text(canvas, font, Vector2(rect.position.x + 16.0, rect.position.y + 22.0), _name_of(id), 14,
		name_color)
	# Rule under the name, as wide as the name: the title block reads as a ledger.
	var name_w := font.get_string_size(_name_of(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	MathArt.px_rect(canvas, Rect2(rect.position.x + 16.0, rect.position.y + 28.0, name_w, 1.0),
		Color(name_color, 0.7))
	_text(canvas, font, Vector2(rect.position.x + 16.0, rect.position.y + 40.0),
		str(node.get("text", "")), 10, MathArt.PALE if available or owned else MathArt.STONE_HI)
	_text(canvas, font, Vector2(rect.position.x + 16.0, rect.position.y + 56.0),
		"COST %d CELLS" % _cost(id), 9, MathArt.MID)

	# The status column is a separate cell, split off by its own hairline.
	var gate_x := rect.position.x + rect.size.x - 176.0
	MathArt.px_rect(canvas, Rect2(gate_x - 10.0, rect.position.y + 8.0, 1.0, rect.size.y - 20.0),
		Color(MathArt.STONE_DIM, 0.5))
	var status := "ENTER TO BUY"
	var tint := MathArt.WHITE
	if owned:
		status = "OWNED"
		tint = MathArt.PALE_DIM
	elif not available:
		status = _blocked_reason(id)
		tint = MathArt.STONE_HI
	elif Profile.cells < _cost(id):
		status = "NEED %d CELLS" % _cost(id)
		tint = MathArt.MID
	_text(canvas, font, Vector2(gate_x, rect.position.y + 22.0), status, 10, tint, 160.0,
		HORIZONTAL_ALIGNMENT_RIGHT)
	if available and not owned:
		MathArt.px_poly(canvas, MathArt.ngon(3, 4.0, 0.0, Vector2(gate_x + 168.0, rect.position.y + 18.0)),
			MathArt.WHITE)

	if _note_t > 0.0:
		_text(canvas, font, Vector2(gate_x, rect.position.y + 40.0),
			_note, 9, Color(MathArt.WHITE, clampf(_note_t * 2.0, 0.0, 1.0)), 160.0,
			HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_footer(canvas: CanvasItem, font: Font, size: Vector2) -> void:
	MathArt.px_rect(canvas, Rect2(40.0, 450.0, size.x - 80.0, 30.0), Color(MathArt.BG_1, 0.9))
	MathArt.px_rect(canvas, Rect2(40.0, 450.0, size.x - 80.0, 1.0), Color(MathArt.STONE, 0.85))
	_text(canvas, font, Vector2(0.0, 462.0),
		"ARROWS NEAREST NODE      ENTER BUY      ESC CLOSE", 8, MathArt.LIGHT,
		size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _text(canvas: CanvasItem, font: Font, at: Vector2, text: String, size_px: int, color: Color,
		width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	canvas.draw_string(font, at, text, align, width, size_px, color)
