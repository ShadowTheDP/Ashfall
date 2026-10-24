class_name HubUi
extends CanvasLayer
## Station panels. One card/row renderer serves every list; only the skill tree
## needs its own geometry. Keyboard only, hints always on screen.

signal closed

const CARD := Rect2(44.0, 48.0, 680.0, 404.0)
const ROW_H := 40.0
const ROWS_PER_PAGE := 7

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
		_canvas.draw_string(font, Vector2(CARD.position.x, CARD.position.y + CARD.size.y - 32.0),
			"PAGE %d/%d" % [_page + 1, pages], HORIZONTAL_ALIGNMENT_CENTER, CARD.size.x, 8, MathArt.MID)
	_draw_hints(font, "UP/DOWN MOVE     LEFT/RIGHT PAGE     ENTER CONFIRM     ESC CLOSE")


func _draw_card(font: Font, title: String, subtitle: String) -> void:
	var size := _canvas.get_viewport_rect().size
	MathArt.px_rect(_canvas, Rect2(0.0, 0.0, size.x, size.y), Color(MathArt.INK, 0.74))
	MathArt.px_rect(_canvas, CARD, Color(MathArt.BG_0, 0.99))
	MathArt.px_rect(_canvas, Rect2(CARD.position, Vector2(CARD.size.x, 1.0)), Color(MathArt.PALE, 0.8))
	MathArt.px_rect(_canvas, Rect2(CARD.position + Vector2(0.0, CARD.size.y - 1.0), Vector2(CARD.size.x, 1.0)), Color(MathArt.PALE, 0.45))
	MathArt.px_rect(_canvas, Rect2(CARD.position, Vector2(1.0, CARD.size.y)), Color(MathArt.PALE, 0.45))
	MathArt.px_rect(_canvas, Rect2(CARD.position + Vector2(CARD.size.x - 1.0, 0.0), Vector2(1.0, CARD.size.y)), Color(MathArt.PALE, 0.45))
	_canvas.draw_string(font, CARD.position + Vector2(16.0, 26.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MathArt.PALE)
	if not subtitle.is_empty():
		_canvas.draw_string(font, CARD.position + Vector2(0.0, 25.0), subtitle,
			HORIZONTAL_ALIGNMENT_RIGHT, CARD.size.x - 16.0, 10, MathArt.LIGHT)
	MathArt.px_rect(_canvas, Rect2(CARD.position.x + 16.0, CARD.position.y + 34.0, CARD.size.x - 32.0, 1.0),
		Color(MathArt.STONE, 0.85))


func _draw_row(font: Font, row: Dictionary, slot: int, selected: bool) -> void:
	var rect := Rect2(CARD.position.x + 12.0, CARD.position.y + 46.0 + float(slot) * ROW_H,
		CARD.size.x - 24.0, ROW_H - 4.0)
	var dim := int(row.get("state", 1)) == 0
	# Blink the row that FAILED, not the row under the cursor: the cursor may
	# have moved before the sound landed, and blinking the wrong row misreports
	# which purchase was refused.
	var flashing := _flash > 0.0 and _flash_row == slot + _page * ROWS_PER_PAGE
	# A failed purchase blinks the row itself, so the eye catches it even if the
	# cursor moved on before the sound landed.
	var lit := selected
	if flashing:
		lit = int(_flash * 26.0) % 2 == 0
	MathArt.px_rect(_canvas, rect, Color(MathArt.BG_2, 0.92) if lit else Color(MathArt.BG_1, 0.55))
	MathArt.px_rect(_canvas, Rect2(rect.position, Vector2(2.0, rect.size.y)),
		MathArt.WHITE if lit else Color(MathArt.STONE, 0.9))
	if selected:
		MathArt.px_poly(_canvas, MathArt.ngon(3, 4.0, PI * 0.5, rect.position + Vector2(-7.0, rect.size.y * 0.5)),
			MathArt.WHITE)

	var name_color := MathArt.WHITE if selected else (MathArt.MID_DIM if dim else MathArt.PALE)
	_canvas.draw_string(font, rect.position + Vector2(8.0, 15.0), str(row.get("name", "")),
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 150.0, 12, name_color)
	_canvas.draw_string(font, rect.position + Vector2(8.0, 30.0), str(row.get("info", "")),
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 116.0, 8, MathArt.MID_DIM if dim else MathArt.LIGHT_DIM)
	if row.has("level"):
		_draw_level(rect, int(row["level"]), int(row["max"]))
	else:
		# A locked row ends its label before the padlock instead of under it.
		var pad := 24.0 if bool(row.get("lock", false)) else 8.0
		_canvas.draw_string(font, rect.position + Vector2(0.0, 15.0), str(row.get("right", "")),
			HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - pad, 9, MathArt.STONE_HI if dim else MathArt.PALE)
	if row.has("price"):
		_canvas.draw_string(font, rect.position + Vector2(0.0, 30.0), str(row.get("price", "")),
			HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8.0, 9, MathArt.LIGHT)
	if bool(row.get("lock", false)):
		_draw_lock(Vector2(rect.position.x + rect.size.x - 16.0, rect.position.y + 11.0))


## One square per level: filled = owned, outline = still to buy.
func _draw_level(rect: Rect2, level: int, max_level: int) -> void:
	var box := 7.0
	var gap := 3.0
	var start := rect.position.x + rect.size.x - 8.0 - float(max_level) * (box + gap) + gap
	for i in max_level:
		var cell := Rect2(start + float(i) * (box + gap), rect.position.y + 7.0, box, box)
		if i < level:
			MathArt.px_rect(_canvas, cell, MathArt.WHITE)
		else:
			_canvas.draw_rect(cell, Color(MathArt.STONE_HI, 0.85), false, 1.0)


func _draw_lock(at: Vector2) -> void:
	MathArt.px_rect(_canvas, Rect2(at.x, at.y + 4.0, 9.0, 7.0), MathArt.STONE_HI)
	MathArt.arc(_canvas, Vector2(at.x + 4.5, at.y + 4.0), 3.0, PI, TAU, MathArt.STONE_HI, 1.0)


func _draw_hints(font: Font, text: String) -> void:
	var y := CARD.position.y + CARD.size.y - 12.0
	MathArt.px_rect(_canvas, Rect2(CARD.position.x + 16.0, y - 18.0, CARD.size.x - 32.0, 1.0),
		Color(MathArt.STONE, 0.85))
	_canvas.draw_string(font, Vector2(CARD.position.x, y), text, HORIZONTAL_ALIGNMENT_CENTER, CARD.size.x, 9, MathArt.LIGHT)


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
