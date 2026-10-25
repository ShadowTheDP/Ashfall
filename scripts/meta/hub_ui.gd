class_name HubUi
extends CanvasLayer
## Station panels. One card/row renderer serves every list; only the skill tree
## needs its own geometry. Keyboard only, hints always on screen.

signal closed

const CARD := Rect2(44.0, 48.0, 680.0, 404.0)
const ROW_H := 40.0
const ROWS_PER_PAGE := 7
# The card is a stack, not a rect: band on top, body, hint strip at the bottom.
# Every row and every rule is measured off these three, so the version stays
# aligned with the hub room behind it.
const HEADER_H := 36.0
const FOOTER_H := 28.0
const GUTTER_W := 30.0

const TITLES := {
	"upgrade": "UPGRADES",
	"skill": "SKILLS",
	"character": "CHARACTER",
}

var _open_id := ""
var _index := 0
var _page := 0
var _flash := 0.0
var _flash_row := -1
var _t := 0.0
var _opened_frame := -1
var _nodes: Array = []
var _canvas: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_ui)


# ------------------------------------------------------------------ public API

func open_station(id: String) -> void:
	_open_id = id
	_index = 0
	_page = 0
	_flash = 0.0
	_flash_row = -1
	# J opens a station and also confirms; ignore keys from the opening frame so
	# the player never buys the first row by accident.
	_opened_frame = Engine.get_process_frames()
	if id == "skill":
		_nodes = Data.skill_nodes.keys()
	Sfx.play("ui", -12)
	_canvas.queue_redraw()


func is_open() -> bool:
	return not _open_id.is_empty()


func _close() -> void:
	if _open_id.is_empty():
		return
	_open_id = ""
	Sfx.play("ui", -14)
	_canvas.queue_redraw()
	closed.emit()


# ---------------------------------------------------------------------- input

func _process(delta: float) -> void:
	_t += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	if is_open() or _flash > 0.0:
		_canvas.queue_redraw()


## _input, not _unhandled_input: the HUD also listens for Esc and it is
## later in the tree, so unhandled input reaches it first. A modal panel
## has to claim the key before the HUD can pause the game under it.
func _input(event: InputEvent) -> void:
	if _open_id.is_empty():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if Engine.get_process_frames() == _opened_frame:
		return
	match event.physical_keycode:
		KEY_ESCAPE:
			_close()
		KEY_UP, KEY_W:
			_move(-1)
		KEY_DOWN, KEY_S:
			_move(1)
		KEY_LEFT, KEY_A:
			_side(-1)
		KEY_RIGHT, KEY_D:
			_side(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_J, KEY_SPACE:
			_confirm()
		_:
			return
	get_viewport().set_input_as_handled()


func _move(direction: int) -> void:
	if _open_id == "skill":
		_move_cursor(Vector2(0.0, float(direction)))
		return
	var rows := _rows()
	if rows.is_empty():
		return
	_index = wrapi(_index + direction, 0, rows.size())
	_page = int(float(_index) / float(ROWS_PER_PAGE))
	Sfx.play("ui", -16)


func _side(direction: int) -> void:
	if _open_id == "skill":
		_move_cursor(Vector2(float(direction), 0.0))
		return
	var rows := _rows()
	var pages := maxi(1, ceili(float(rows.size()) / float(ROWS_PER_PAGE)))
	if pages <= 1:
		return
	_page = wrapi(_page + direction, 0, pages)
	_index = mini(_page * ROWS_PER_PAGE, rows.size() - 1)
	Sfx.play("ui", -16)


## Nearest node in the pressed direction: distance plus a perpendicular penalty,
## so the cursor never jumps across a branch to reach a closer-looking node.
func _move_cursor(direction: Vector2) -> void:
	if _nodes.is_empty():
		return
	var from := _node_pos(str(_nodes[_index]))
	var best := -1.0
	var pick := _index
	for i in _nodes.size():
		if i == _index:
			continue
		var delta := _node_pos(str(_nodes[i])) - from
		if delta.dot(direction) <= 4.0:
			continue
		var score := delta.length() + absf(delta.cross(direction)) * 2.0
		if best < 0.0 or score < best:
			best = score
			pick = i
	if pick != _index:
		_index = pick
		Sfx.play("ui", -16)


func _confirm() -> void:
	if _open_id == "skill":
		if _nodes.is_empty():
			return
		if Profile.buy_skill(str(_nodes[_index])):
			Sfx.play("reward", -10)
		else:
			_fail(_index)
		return
	var rows := _rows()
	if rows.is_empty():
		return
	_activate(rows[_index])


func _activate(row: Dictionary) -> void:
	var id := str(row["id"])
	var kind := str(row["kind"])
	if kind == "enemy":
		return
	# `unlock_floor` is content gating, not a price: a body from a deeper floor
	# stays locked however many cells the player has banked.
	if bool(row.get("lock", false)):
		_fail(_index)
		return
	if kind == "upgrade":
		if Profile.buy_upgrade(id):
			Sfx.play("reward", -10)
		else:
			_fail(_index)
		return
	if Profile.is_unlocked(kind, id):
		Profile.select(kind, id)
		Sfx.play("reward", -10)
	elif Profile.unlock(kind, id):
		Sfx.play("reward", -10)
	else:
		_fail(_index)


func _fail(row: int) -> void:
	_flash = 0.45
	_flash_row = row
	Sfx.play("ui", -8)


# ----------------------------------------------------------------- row content

func _rows() -> Array:
	match _open_id:
		"upgrade":
			var upgrades: Array = []
			for id in Data.upgrades:
				var cfg: Dictionary = Data.upgrades[id]
				var cost := Profile.upgrade_cost(id)
				# A soul-priced row must never read as a cell price: the header
				# shows both currencies and the list is the only place that says
				# which one a row spends.
				var suffix := "S" if Profile.upgrade_currency(id) == "souls" else "C"
				upgrades.append({
					"id": id, "kind": "upgrade", "name": str(cfg.get("name", id)),
					"info": "LV %d/%d   %s" % [Profile.upgrade_level(id), int(cfg.get("max", 1)), str(cfg.get("text", ""))],
					"price": "MAX" if cost < 0 else "%d %s" % [cost, suffix],
					"level": Profile.upgrade_level(id), "max": int(cfg.get("max", 1)),
					"state": 2 if cost < 0 else (1 if Profile.can_afford_upgrade(id) else 0),
				})
			return upgrades
		"character":
			var bodies: Array = []
			for id in Data.characters:
				var cfg: Dictionary = Data.characters[id]
				var gate := int(cfg.get("unlock_floor", 0))
				var locked := gate > Profile.best_floor
				bodies.append({
					"id": id, "kind": "character", "name": str(cfg.get("name", id)),
					"info": "HP %d   SPD %d   KNIVES %d   %s" % [
						int(cfg.get("hp", 0.0)), int(cfg.get("speed", 0.0)),
						int(cfg.get("knives", 0)), str(cfg.get("passive_text", ""))],
					"right": "FLOOR %d" % gate if locked else _status(
						"character", id, int(cfg.get("cost", 0)), Profile.selected_character),
					"lock": locked,
					"state": 0 if locked else (
						2 if Profile.selected_character == id else (
							1 if Profile.is_unlocked("character", id) else 0)),
				})
			return bodies
	return []


func _status(kind: String, id: String, cost: int, selected: String) -> String:
	if Profile.is_unlocked(kind, id):
		return "EQUIPPED" if selected == id else "OWNED"
	return "%d C" % cost


# ---------------------------------------------------------------------- draw

func _draw_ui() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	if not _open_id.is_empty():
		if _open_id == "skill":
			_draw_skill(font)
		else:
			_draw_list(font)
	_draw_header(font)


func _draw_header(font: Font) -> void:
	var size := _canvas.get_viewport_rect().size
	MathArt.px_rect(_canvas, Rect2(0.0, 0.0, size.x, 26.0), Color(MathArt.INK, 0.88))
	MathArt.px_rect(_canvas, Rect2(0.0, 26.0, size.x, 1.0), Color(MathArt.STONE, 0.9))
	_canvas.draw_string(font, Vector2(0.0, 18.0),
		"CELLS %d   SOULS %d   BEST FLOOR %d" % [Profile.cells, Profile.souls, Profile.best_floor],
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, MathArt.PALE)


func _draw_list(font: Font) -> void:
	var rows := _rows()
	_draw_card(font, str(TITLES.get(_open_id, _open_id)), "CELLS %d" % Profile.cells)
	var first := _page * ROWS_PER_PAGE
	for slot in mini(ROWS_PER_PAGE, rows.size() - first):
		var row_index := first + slot
		_draw_row(font, rows[row_index], slot, row_index == _index)
	var pages := maxi(1, ceili(float(rows.size()) / float(ROWS_PER_PAGE)))
	if pages > 1:
		_canvas.draw_string(font, Vector2(CARD.position.x, CARD.position.y + CARD.size.y - FOOTER_H - 9.0),
			"PAGE %d/%d" % [_page + 1, pages], HORIZONTAL_ALIGNMENT_CENTER, CARD.size.x, 8, MathArt.MID)
	# Only advertise paging when there is more than one page: the character list
	# fits on one, and a hint that does nothing is worse than no hint.
	var paging := "LEFT/RIGHT PAGE     " if pages > 1 else ""
	_draw_hints(font, "UP/DOWN MOVE     " + paging + "ENTER CONFIRM     ESC CLOSE")


func _body_rect() -> Rect2:
	return Rect2(CARD.position.x + 1.0, CARD.position.y + HEADER_H + 1.0,
		CARD.size.x - 2.0, CARD.size.y - HEADER_H - FOOTER_H - 2.0)


func _footer_rect() -> Rect2:
	return Rect2(CARD.position.x + 1.0, CARD.position.y + CARD.size.y - FOOTER_H,
		CARD.size.x - 2.0, FOOTER_H - 2.0)


## Four passes, back to front: dimmed room, two-step drop shadow, framed panel,
## header band. Anything else drawn on this card lands on top of the body.
func _draw_card(font: Font, title: String, subtitle: String) -> void:
	var size := _canvas.get_viewport_rect().size
	MathArt.px_rect(_canvas, Rect2(0.0, 0.0, size.x, size.y), Color(MathArt.INK, 0.74))
	MathArt.px_rect(_canvas, CARD.grow(8.0), Color(MathArt.BLACK, 0.28))
	MathArt.px_rect(_canvas, CARD.grow(3.0), Color(MathArt.BLACK, 0.52))
	MathArt.px_rect(_canvas, CARD, Color(MathArt.BG_0, 0.99))
	# Light catches the top edge, the bottom edge falls into shadow: that pair is
	# what tells the eye the card stands above the floor rather than on it.
	MathArt.px_rect(_canvas, Rect2(CARD.position, Vector2(CARD.size.x, 1.0)), Color(MathArt.PALE, 0.85))
	MathArt.px_rect(_canvas, Rect2(CARD.position + Vector2(0.0, CARD.size.y - 2.0), Vector2(CARD.size.x, 2.0)),
		Color(MathArt.BLACK, 0.9))
	MathArt.px_rect(_canvas, Rect2(CARD.position + Vector2(0.0, 1.0), Vector2(1.0, CARD.size.y - 3.0)),
		Color(MathArt.STONE, 0.85))
	MathArt.px_rect(_canvas, Rect2(CARD.position + Vector2(CARD.size.x - 1.0, 1.0), Vector2(1.0, CARD.size.y - 3.0)),
		Color(MathArt.STONE, 0.85))
	# Header band: one value above the body, closed by a rule.
	MathArt.px_rect(_canvas, Rect2(CARD.position.x + 1.0, CARD.position.y + 1.0, CARD.size.x - 2.0, HEADER_H - 1.0),
		Color(MathArt.BG_1, 0.98))
	MathArt.px_rect(_canvas, Rect2(CARD.position.x + 1.0, CARD.position.y + HEADER_H, CARD.size.x - 2.0, 1.0),
		Color(MathArt.STONE, 0.95))
	_canvas.draw_string(font, CARD.position + Vector2(16.0, 25.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MathArt.PALE)
	# Underline exactly as wide as the title, so the band reads as a ledger rule.
	var title_w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	MathArt.px_rect(_canvas, Rect2(CARD.position.x + 16.0, CARD.position.y + HEADER_H - 1.0, title_w, 1.0),
		MathArt.PALE)
	if not subtitle.is_empty():
		_canvas.draw_string(font, CARD.position + Vector2(0.0, 24.0), subtitle,
			HORIZONTAL_ALIGNMENT_RIGHT, CARD.size.x - 16.0, 10, MathArt.LIGHT)
	# Body sits one value below the band, so a selected row can rise above it.
	MathArt.px_rect(_canvas, _body_rect(), Color(MathArt.INK, 0.5))


## Proportional grid: rank gutter, name, info line, value cell. The split is
## INV_PHI cubed of the row width, so the columns keep their ratio at any
## heading length.
func _draw_row(font: Font, row: Dictionary, slot: int, selected: bool) -> void:
	var rect := Rect2(CARD.position.x + 10.0, CARD.position.y + HEADER_H + 6.0 + float(slot) * ROW_H,
		CARD.size.x - 20.0, ROW_H - 4.0)
	var dim := int(row.get("state", 1)) == 0
	# Blink the row that FAILED, not the row under the cursor: the cursor may
	# have moved before the sound landed, and blinking the wrong row misreports
	# which purchase was refused.
	var flashing := _flash > 0.0 and _flash_row == slot + _page * ROWS_PER_PAGE
	var lit := selected
	if flashing:
		lit = int(_flash * 26.0) % 2 == 0
	if lit:
		# Raised: a value above the body, a lit top edge, a dark bottom edge.
		MathArt.px_rect(_canvas, rect, Color(MathArt.BG_2, 0.98))
		MathArt.px_rect(_canvas, Rect2(rect.position, Vector2(rect.size.x, 1.0)), Color(MathArt.PALE, 0.25))
		MathArt.px_rect(_canvas, Rect2(rect.position + Vector2(0.0, rect.size.y - 1.0), Vector2(rect.size.x, 1.0)),
			Color(MathArt.BLACK, 0.65))
		MathArt.px_rect(_canvas, Rect2(rect.position, Vector2(2.0, rect.size.y)), MathArt.WHITE)
	else:
		MathArt.px_rect(_canvas, rect, Color(MathArt.BG_1, 0.5))
		MathArt.px_rect(_canvas, Rect2(rect.position.x, rect.position.y + rect.size.y - 1.0, rect.size.x, 1.0),
			Color(MathArt.STONE_DIM, 0.45))

	# Columns. The value cell is the row width over phi cubed (0.236), which
	# leaves the info line the widest share of the row without measuring text.
	var name_x := rect.position.x + GUTTER_W + 10.0
	var cell_x := rect.position.x + rect.size.x * (1.0 - pow(MathArt.INV_PHI, 3.0))
	_canvas.draw_string(font, rect.position + Vector2(9.0, 15.0),
		"%02d" % (slot + _page * ROWS_PER_PAGE + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
		MathArt.WHITE if selected else MathArt.STONE_HI)
	MathArt.px_rect(_canvas, Rect2(rect.position.x + GUTTER_W, rect.position.y + 6.0, 1.0, rect.size.y - 12.0),
		Color(MathArt.STONE_DIM, 0.55))
	MathArt.px_rect(_canvas, Rect2(cell_x - 8.0, rect.position.y + 6.0, 1.0, rect.size.y - 12.0),
		Color(MathArt.STONE_DIM, 0.35))

	var name_color := MathArt.WHITE if selected else (MathArt.MID_DIM if dim else MathArt.PALE)
	_canvas.draw_string(font, Vector2(name_x, rect.position.y + 15.0), str(row.get("name", "")),
		HORIZONTAL_ALIGNMENT_LEFT, cell_x - name_x - 10.0, 12, name_color)
	_canvas.draw_string(font, Vector2(name_x, rect.position.y + 30.0), str(row.get("info", "")),
		HORIZONTAL_ALIGNMENT_LEFT, cell_x - name_x - 10.0, 8, MathArt.MID_DIM if dim else MathArt.LIGHT_DIM)

	var value_w := rect.position.x + rect.size.x - 8.0 - cell_x
	if row.has("level"):
		_draw_level(cell_x + value_w, rect.position.y, int(row["level"]), int(row["max"]))
	else:
		# A locked row ends its label before the padlock instead of under it.
		var pad := 22.0 if bool(row.get("lock", false)) else 0.0
		_canvas.draw_string(font, Vector2(cell_x, rect.position.y + 15.0), str(row.get("right", "")),
			HORIZONTAL_ALIGNMENT_RIGHT, value_w - pad, 9, MathArt.STONE_HI if dim else MathArt.PALE)
	if row.has("price"):
		# Price is the reward line, so it carries the brightest value the row has.
		var state := int(row.get("state", 1))
		var price_tint := MathArt.MID if state == 2 else (MathArt.PALE if state == 1 else MathArt.STONE_HI)
		_canvas.draw_string(font, Vector2(cell_x, rect.position.y + 30.0), str(row.get("price", "")),
			HORIZONTAL_ALIGNMENT_RIGHT, value_w, 9, price_tint)
	if bool(row.get("lock", false)):
		_draw_lock(Vector2(rect.position.x + rect.size.x - 8.0 - 9.0, rect.position.y + 7.0))

	if selected:
		# Cursor: a chevron that breathes plus one golden-angle dot orbiting its
		# tail. Shape and motion carry it, so it survives the monochrome ramp.
		var apex := Vector2(rect.position.x - 6.0 + sin(_t * 4.0) * 1.5, rect.position.y + rect.size.y * 0.5)
		MathArt.px_poly(_canvas, MathArt.ngon(3, 4.5, PI * 0.5, apex), MathArt.WHITE)
		var orbit: Vector2 = MathArt.phyllotaxis(int(_t * 6.0) % 6, 1.6)
		MathArt.disc(_canvas, apex + Vector2(-7.0, 0.0) + orbit, 1.5, Color(MathArt.PALE, 0.85))


## One square per level: filled = owned, outline = still to buy, right-aligned
## to the value cell's edge.
func _draw_level(right: float, top: float, level: int, max_level: int) -> void:
	var box := 7.0
	var gap := 3.0
	var start := right - float(max_level) * (box + gap) + gap
	for i in max_level:
		var cell := Rect2(start + float(i) * (box + gap), top + 7.0, box, box)
		if i < level:
			MathArt.px_rect(_canvas, cell, MathArt.WHITE)
		else:
			_canvas.draw_rect(cell, Color(MathArt.STONE_HI, 0.85), false, 1.0)


## A sealed body with a hex shackle: shape says "locked", never colour.
func _draw_lock(at: Vector2) -> void:
	MathArt.px_poly(_canvas, MathArt.ngon(3, 5.0, -PI * 0.5, Vector2(at.x + 4.5, at.y + 5.0)),
		Color(0, 0, 0, 0), MathArt.STONE_HI, 1.0)
	MathArt.px_rect(_canvas, Rect2(at.x, at.y + 5.0, 9.0, 6.0), MathArt.STONE_HI)
	MathArt.px_rect(_canvas, Rect2(at.x + 4.0, at.y + 7.0, 1.0, 2.0), MathArt.INK)


func _draw_hints(font: Font, text: String) -> void:
	MathArt.px_rect(_canvas, _footer_rect(), Color(MathArt.BG_1, 0.9))
	MathArt.px_rect(_canvas, Rect2(CARD.position.x + 1.0, CARD.position.y + CARD.size.y - FOOTER_H,
		CARD.size.x - 2.0, 1.0), Color(MathArt.STONE, 0.95))
	_canvas.draw_string(font, Vector2(CARD.position.x, CARD.position.y + CARD.size.y - 10.0), text,
		HORIZONTAL_ALIGNMENT_CENTER, CARD.size.x, 9, MathArt.LIGHT)


# ---------------------------------------------------------------- skill tree

func _draw_skill(font: Font) -> void:
	_draw_card(font, "SKILL TREE", "CELLS %d" % Profile.cells)
	if _nodes.is_empty():
		_draw_hints(font, "ESC CLOSE")
		return
	for id in _nodes:
		var node: Dictionary = Data.skill_nodes[id]
		for parent in node.get("requires", []):
			var owned := Profile.has_skill(str(parent))
			MathArt.px_line(_canvas, _node_pos(str(parent)), _node_pos(str(id)),
				Color(MathArt.WHITE, 0.55) if owned else Color(MathArt.STONE, 0.8), 1.0)
	for i in _nodes.size():
		_draw_node(font, i)

	var current: Dictionary = Data.skill_nodes.get(str(_nodes[_index]), {})
	var cost_text := "LOCKED"
	if Profile.has_skill(str(_nodes[_index])):
		cost_text = "OWNED"
	elif Profile.skill_available(str(_nodes[_index])):
		cost_text = "%d C" % int(current.get("cost", 0))
	_canvas.draw_string(font, Vector2(CARD.position.x + 16.0, CARD.position.y + CARD.size.y - 34.0),
		"%s   %s   %s" % [str(current.get("name", "")), str(current.get("text", "")), cost_text],
		HORIZONTAL_ALIGNMENT_LEFT, CARD.size.x - 32.0, 9, MathArt.PALE)
	_draw_hints(font, "ARROWS MOVE     ENTER BUY     ESC CLOSE")


func _draw_node(font: Font, i: int) -> void:
	var id := str(_nodes[i])
	var node: Dictionary = Data.skill_nodes[id]
	var at := _node_pos(id)
	var owned := Profile.has_skill(id)
	var available := Profile.skill_available(id)
	var tint := MathArt.WHITE if owned else (MathArt.PALE if available else MathArt.STONE)
	MathArt.px_poly(_canvas, MathArt.ngon(6, 7.0, 0.0, at),
		Color(MathArt.WHITE) if owned else Color(MathArt.BG_1, 0.9), tint, 1.0)
	if available:
		MathArt.px_ring(_canvas, at, 11.0, Color(MathArt.PALE, 0.45), 1.0, 20)
	if i == _index:
		MathArt.px_ring(_canvas, at, 13.0, MathArt.WHITE, 1.5, 24)
		if _flash > 0.0 and _flash_row == i:
			MathArt.px_ring(_canvas, at, 16.0, Color(MathArt.WHITE, _flash * 2.0), 1.0, 24)
	_canvas.draw_string(font, Vector2(at.x - 50.0, at.y + 27.0), str(node.get("name", id)),
		HORIZONTAL_ALIGNMENT_CENTER, 100.0, 8,
		MathArt.WHITE if i == _index else (MathArt.LIGHT if owned else MathArt.MID_DIM))


func _node_pos(id: String) -> Vector2:
	var node: Dictionary = Data.skill_nodes.get(id, {})
	var at: Array = node.get("at", [0.5, 0.5])
	var box := Rect2(CARD.position.x + 40.0, CARD.position.y + 58.0, CARD.size.x - 80.0, CARD.size.y - 132.0)
	return box.position + Vector2(float(at[0]) * box.size.x, float(at[1]) * box.size.y)
