class_name ArchiveScreen
extends CanvasLayer
## The codex: bestiary, weapons, armour. Three tabs, one list, one card.
## Read-only except Enter, which equips an unlocked entry or pays to unlock a
## record the player has not met yet.

signal closed

const TABS: Array[String] = ["enemy", "weapon", "armor"]
const LABEL := {"enemy": "BESTIARY", "weapon": "WEAPONS", "armor": "ARMOUR"}
const ROWS := 10
const ROW_H := 33.0
const LIST_RECT := Rect2(40.0, 68.0, 300.0, 344.0)
const CARD_RECT := Rect2(352.0, 68.0, 376.0, 344.0)
# Enemies are drawn at one shared zoom so their relative sizes stay true.
const ZOOM := 2.6
# One fixed magnification for every weapon, so a 50px blade looks longer than
# a 38px one. Bigger than 1:1 only because 38px reads as a doodle on a card.
const BLADE_ZOOM := 1.9

const BG := Color(0.024, 0.024, 0.024, 0.97)
const PANEL := Color(0.047, 0.047, 0.047, 0.94)
const ROW_SEL := Color(0.086, 0.086, 0.086, 0.97)

var _canvas: Control
var _tab := "enemy"
var _ids: Array[String] = []
var _index := 0
var _scroll := 0
var _open := false
var _t := 0.0
var _flash_row := -1
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
	# CanvasLayer cannot draw, so one full-rect Control carries the painting and
	# hands itself to us through its `draw` signal.
	_canvas = Control.new()
	_canvas.name = "Paint"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_paint.bind(_canvas))
	add_child(_canvas)


# ------------------------------------------------------------------ public API

func open(tab: String) -> void:
	_ensure_canvas()
	_tab = tab if TABS.has(tab) else "enemy"
	_index = 0
	_scroll = 0
	_note = ""
	_note_t = 0.0
	_flash_row = -1
	_flash_t = 0.0
	_reload()
	_open = true
	visible = true
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
	# otherwise reach the hub's proximity handler: J re-opened this screen and
	# reset the cursor, and J by the door started a floor under the panel.
	get_viewport().set_input_as_handled()
	if event.echo:
		return
	match event.physical_keycode:
		KEY_ESCAPE:
			close()
		KEY_LEFT, KEY_A:
			_switch_tab(-1)
		KEY_RIGHT, KEY_D:
			_switch_tab(1)
		KEY_UP, KEY_W:
			_move(-1)
		KEY_DOWN, KEY_S:
			_move(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate()


func _switch_tab(delta_index: int) -> void:
	var next := wrapi(TABS.find(_tab) + delta_index, 0, TABS.size())
	_tab = TABS[next]
	_index = 0
	_scroll = 0
	_flash_row = -1
	_note = ""
	_note_t = 0.0
	_reload()
	Sfx.play("ui", -12)
	_canvas.queue_redraw()


func _move(delta_index: int) -> void:
	if _ids.is_empty():
		return
	_index = clampi(_index + delta_index, 0, _ids.size() - 1)
	if _index < _scroll:
		_scroll = _index
	elif _index >= _scroll + ROWS:
		_scroll = _index - ROWS + 1
	Sfx.play("ui", -14)
	_canvas.queue_redraw()


func _activate() -> void:
	if _ids.is_empty() or _tab == "enemy":
		return
	var id := _ids[_index]
	if Profile.is_unlocked(_tab, id):
		Profile.select(_tab, id)
		_note = "EQUIPPED: " + _name_of(id)
		_note_t = 1.6
		Sfx.play("pickup", -10)
		return
	if Profile.unlock(_tab, id):
		Profile.see(_tab, id)
		_note = "UNLOCKED: " + _name_of(id)
		_note_t = 1.8
		Sfx.play("reward", -8)
		return
	# Failure is reported by flashing the row, never by a silent no-op.
	_flash_row = _index
	_flash_t = 0.45
	_note = "NEED %d CELLS" % _cost_of(id)
	_note_t = 1.8
	Sfx.play("block", -10)
	_canvas.queue_redraw()


# ---------------------------------------------------------------------- data

func _reload() -> void:
	# JSON order, not alphabetical: the tables are authored as a threat/cost
	# ladder and that order is the information the list is conveying.
	_ids.clear()
	for key in _table().keys():
		_ids.append(str(key))
	_index = clampi(_index, 0, maxi(0, _ids.size() - 1))
	_scroll = clampi(_scroll, 0, maxi(0, _ids.size() - ROWS))


func _table() -> Dictionary:
	match _tab:
		"weapon":
			return Data.weapons
		"armor":
			return Data.armor
	return Data.enemies


func _cfg(id: String) -> Dictionary:
	var out: Variant = _table().get(id, {})
	return out if typeof(out) == TYPE_DICTIONARY else {}


func _name_of(id: String) -> String:
	return str(_cfg(id).get("name", id))


## Weapons price the unlock as `unlock_cost`, armour and characters as `cost`.
## Reading only `cost` advertised every weapon as free.
func _cost_of(id: String) -> int:
	var cfg := _cfg(id)
	return int(cfg.get("cost", cfg.get("unlock_cost", 0)))


## A weapon prices its unlock as `unlock_cost`, armour and characters as
## `cost`; _cost_of() reads both, so this line always quotes the real price.
## A free entry says so instead of printing "FOR 0 CELLS".
func _unlock_line(id: String) -> String:
	var cost := _cost_of(id)
	return "ENTER TO UNLOCK FOR %d CELLS" % cost if cost > 0 else "ENTER TO UNLOCK"


## A record is readable once it has been met in the field or bought.
func _known(id: String) -> bool:
	return Profile.has_seen(_tab, id) or Profile.is_unlocked(_tab, id)


func _equipped(id: String) -> bool:
	if _tab == "weapon":
		return Profile.selected_weapon == id
	if _tab == "armor":
		return Profile.selected_armor == id
	return false


# -------------------------------------------------------------------- painting

func _paint(canvas: Control) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var size := canvas.get_viewport_rect().size
	MathArt.px_rect(canvas, Rect2(Vector2.ZERO, size), BG)
	_draw_header(canvas, font, size)
	_draw_list(canvas, font)
	_draw_card(canvas, font)
	_draw_footer(canvas, font, size)


func _draw_header(canvas: CanvasItem, font: Font, size: Vector2) -> void:
	_text(canvas, font, Vector2(40.0, 38.0), "ARCHIVES", 11, MathArt.MID_DIM)
	_text(canvas, font, Vector2(size.x - 168.0, 38.0), "CELLS %d" % Profile.cells,
		11, MathArt.PALE, 128.0, HORIZONTAL_ALIGNMENT_RIGHT)

	var slot := 132.0
	var start := size.x * 0.5 - slot * 1.5
	for i in TABS.size():
		var active := TABS[i] == _tab
		var x := start + float(i) * slot
		_text(canvas, font, Vector2(x, 38.0), str(LABEL[TABS[i]]), 11,
			MathArt.WHITE if active else MathArt.STONE_HI, slot, HORIZONTAL_ALIGNMENT_CENTER)
		if active:
			MathArt.px_rect(canvas, Rect2(x + slot * 0.5 - 26.0, 44.0, 52.0, 2.0), MathArt.WHITE)

	MathArt.px_rect(canvas, Rect2(40.0, 54.0, size.x - 80.0, 1.0), Color(MathArt.STONE, 0.8))


func _draw_list(canvas: CanvasItem, font: Font) -> void:
	var rect := LIST_RECT
	MathArt.px_rect(canvas, rect, PANEL)
	canvas.draw_rect(rect, Color(MathArt.STONE_DIM, 0.9), false, 1.0)

	if _ids.is_empty():
		_text(canvas, font, Vector2(rect.position.x, rect.position.y + 34.0),
			"NO RECORDS", 10, MathArt.MID_DIM, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		return

	for row in ROWS:
		var index := _scroll + row
		var y := rect.position.y + 4.0 + float(row) * ROW_H
		var row_rect := Rect2(rect.position.x + 1.0, y, rect.size.x - 2.0, ROW_H - 2.0)
		if index >= _ids.size():
			# Keep the empty slots visible: the list length is information.
			MathArt.px_rect(canvas, Rect2(row_rect.position.x + 10.0, y + ROW_H * 0.5,
				row_rect.size.x - 20.0, 1.0), Color(MathArt.STONE_DIM, 0.35))
			continue

		var id := _ids[index]
		var known := _known(id)
		var selected := index == _index
		if selected:
			MathArt.px_rect(canvas, row_rect, ROW_SEL)
			MathArt.px_rect(canvas, Rect2(row_rect.position.x, y + 2.0, 2.0, ROW_H - 6.0), MathArt.WHITE)
		if index == _flash_row and _flash_t > 0.0:
			MathArt.px_rect(canvas, row_rect, Color(MathArt.WHITE, 0.16 * (_flash_t / 0.45)))

		_text(canvas, font, Vector2(row_rect.position.x + 12.0, y + 21.0),
			"%02d" % (index + 1), 8, MathArt.STONE_HI)
		_text(canvas, font, Vector2(row_rect.position.x + 34.0, y + 22.0),
			_name_of(id) if known else "???", 12,
			MathArt.WHITE if selected else (MathArt.PALE if known else MathArt.MID_DIM))

		var right := row_rect.position.x + row_rect.size.x - 12.0
		if not known:
			_draw_lock(canvas, Vector2(right - 8.0, y + ROW_H * 0.5), 8.0, MathArt.STONE_HI)
		elif _equipped(id):
			_text(canvas, font, Vector2(right - 60.0, y + 21.0), "WORN", 8, MathArt.WHITE, 60.0,
				HORIZONTAL_ALIGNMENT_RIGHT)
		elif Profile.is_unlocked(_tab, id) and _tab != "enemy":
			_draw_gem(canvas, Vector2(right - 16.0, y + ROW_H * 0.5), 4.0, MathArt.PALE_DIM)
		elif _tab != "enemy":
			_draw_gem(canvas, Vector2(right - 16.0, y + ROW_H * 0.5), 4.0, MathArt.STONE)


func _draw_card(canvas: CanvasItem, font: Font) -> void:
	var rect := CARD_RECT
	MathArt.px_rect(canvas, rect, PANEL)
	canvas.draw_rect(rect, Color(MathArt.STONE_DIM, 0.9), false, 1.0)

	if _ids.is_empty():
		_text(canvas, font, Vector2(rect.position.x, rect.position.y + 168.0), "NOTHING RECORDED",
			10, MathArt.STONE_HI, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var id := _ids[_index]
	var cfg := _cfg(id)
	if not _known(id):
		_draw_unknown(canvas, font, rect, id)
		return
	match _tab:
		"weapon":
			_draw_weapon(canvas, font, rect, id, cfg)
		"armor":
			_draw_armor(canvas, font, rect, id, cfg)
		_:
			_draw_enemy(canvas, font, rect, id, cfg)


func _draw_footer(canvas: CanvasItem, font: Font, size: Vector2) -> void:
	if _note_t > 0.0:
		_text(canvas, font, Vector2(0.0, 432.0), _note, 10,
			Color(MathArt.WHITE, clampf(_note_t * 2.0, 0.0, 1.0)), size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var equip := "ENTER NOTHING" if _tab == "enemy" else "ENTER EQUIP / UNLOCK"
	_text(canvas, font, Vector2(0.0, 454.0),
		"LEFT/RIGHT TAB      UP/DOWN SCROLL      %s      ESC CLOSE" % equip,
		8, MathArt.MID, size.x, HORIZONTAL_ALIGNMENT_CENTER)


# ---------------------------------------------------------------- detail cards

func _draw_unknown(canvas: CanvasItem, font: Font, rect: Rect2, id: String) -> void:
	var center := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + 130.0)
	_draw_lock(canvas, center, 34.0, MathArt.STONE_HI)
	_text(canvas, font, Vector2(rect.position.x, rect.position.y + 214.0), "???", 24,
		MathArt.MID, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_text(canvas, font, Vector2(rect.position.x, rect.position.y + 240.0),
		"NO RECORD. MEET IT IN THE FIELD.", 9, MathArt.STONE_HI, rect.size.x,
		HORIZONTAL_ALIGNMENT_CENTER)
	if _tab != "enemy":
		_text(canvas, font, Vector2(rect.position.x, rect.position.y + 330.0),
			_unlock_line(id), 9, MathArt.PALE, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_enemy(canvas: CanvasItem, font: Font, rect: Rect2, id: String, cfg: Dictionary) -> void:
	var center := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + 80.0)
	_draw_enemy_body(canvas, id, cfg, center)

	_text(canvas, font, Vector2(rect.position.x + 16.0, rect.position.y + 170.0),
		str(cfg.get("name", id)), 16, MathArt.PALE)
	var tag := "BOSS" if bool(cfg.get("boss", false)) else "HOSTILE"
	_text(canvas, font, Vector2(rect.position.x + 16.0, rect.position.y + 184.0), tag, 8, MathArt.MID_DIM)
	MathArt.px_rect(canvas, Rect2(rect.position.x + 16.0, rect.position.y + 190.0,
		rect.size.x - 32.0, 1.0), Color(MathArt.STONE, 0.7))

	var lx := rect.position.x + 16.0
	var rx := rect.position.x + 196.0
	var y := rect.position.y + 206.0
	_stat(canvas, font, lx, y, "HP", "%.0f" % float(cfg.get("hp", 0.0)))
	_stat(canvas, font, rx, y, "WINDUP", "%.2fs" % float(cfg.get("windup", 0.0)))
	y += 20.0
	_stat(canvas, font, lx, y, "SPEED", "%.0f" % float(cfg.get("speed", 0.0)))
	_stat(canvas, font, rx, y, "ACTIVE", "%.2fs" % float(cfg.get("active", 0.0)))
	y += 20.0
	_stat(canvas, font, lx, y, "DAMAGE", "%.0f" % float(cfg.get("damage", 0.0)))
	_stat(canvas, font, rx, y, "RECOVER", "%.2fs" % float(cfg.get("recovery", 0.0)))
	y += 20.0
	_stat(canvas, font, lx, y, "RANGE", "%.0f" % float(cfg.get("attack_range", 0.0)))
	_stat(canvas, font, rx, y, "CELLS", "%d" % int(cfg.get("cells", 0)))

	_draw_timing(canvas, font, rect, cfg)


func _draw_timing(canvas: CanvasItem, font: Font, rect: Rect2, cfg: Dictionary) -> void:
	var parts: Array[float] = [
		maxf(0.001, float(cfg.get("windup", 0.0))),
		maxf(0.001, float(cfg.get("active", 0.0))),
		maxf(0.001, float(cfg.get("recovery", 0.0))),
	]
	var tints: Array[Color] = [Color(MathArt.PALE, 0.45), MathArt.WHITE, Color(MathArt.STONE, 0.95)]
	var total := parts[0] + parts[1] + parts[2]
	var x := rect.position.x + 16.0
	var width := rect.size.x - 32.0
	var y := rect.position.y + 288.0
	_text(canvas, font, Vector2(x, y), "TELEGRAPH / HIT / RECOVER", 8, MathArt.MID_DIM)
	var bar := Rect2(x, y + 6.0, width, 9.0)
	var cursor := bar.position.x
	for i in parts.size():
		var segment := width * parts[i] / total
		MathArt.px_rect(canvas, Rect2(cursor, bar.position.y, segment - 1.0, bar.size.y), tints[i])
		if segment > 30.0:
			_text(canvas, font, Vector2(cursor, bar.position.y + bar.size.y + 11.0),
				"%.2f" % parts[i], 8, MathArt.MID)
		cursor += segment
	canvas.draw_rect(bar, Color(MathArt.BLACK, 0.8), false, 1.0)


func _draw_weapon(canvas: CanvasItem, font: Font, rect: Rect2, id: String, cfg: Dictionary) -> void:
	var center := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + 92.0)
	_draw_blade(canvas, cfg, center)
	_text(canvas, font, Vector2(rect.position.x + rect.size.x - 136.0, rect.position.y + 20.0),
		"BLADE x%.1f" % BLADE_ZOOM, 8, MathArt.STONE_HI, 120.0, HORIZONTAL_ALIGNMENT_RIGHT)

	_text(canvas, font, Vector2(rect.position.x + 16.0, rect.position.y + 170.0),
		str(cfg.get("name", id)), 16, MathArt.PALE)
	_text(canvas, font, Vector2(rect.position.x + 16.0, rect.position.y + 184.0),
		str(cfg.get("attribute", "melee")).to_upper() + " / " + str(cfg.get("slot", "melee")).to_upper(),
		8, MathArt.MID_DIM)
	MathArt.px_rect(canvas, Rect2(rect.position.x + 16.0, rect.position.y + 190.0,
		rect.size.x - 32.0, 1.0), Color(MathArt.STONE, 0.7))

	var steps: Array = cfg.get("combo", [])
	var top := 1.0
	for step in steps:
		if typeof(step) == TYPE_DICTIONARY:
			top = maxf(top, float((step as Dictionary).get("damage", 0.0)))
	var y := rect.position.y + 208.0
	_text(canvas, font, Vector2(rect.position.x + 16.0, y), "DAMAGE PER COMBO STEP", 8, MathArt.MID_DIM)
	for i in mini(steps.size(), 4):
		var step: Dictionary = steps[i]
		var row_y := y + 16.0 + float(i) * 19.0
		var damage := float(step.get("damage", 0.0))
		_text(canvas, font, Vector2(rect.position.x + 16.0, row_y), "STEP %d" % (i + 1), 9, MathArt.MID)
		_text(canvas, font, Vector2(rect.position.x + 96.0, row_y), "%.0f" % damage, 11,
			MathArt.PALE, 40.0, HORIZONTAL_ALIGNMENT_RIGHT)
		var bar_w := 130.0 * damage / top
		MathArt.px_rect(canvas, Rect2(rect.position.x + 146.0, row_y - 8.0, 130.0, 8.0),
			Color(MathArt.BG_2, 0.9))
		MathArt.px_rect(canvas, Rect2(rect.position.x + 146.0, row_y - 8.0, bar_w, 8.0),
			MathArt.WHITE if i == steps.size() - 1 else MathArt.PALE_DIM)

	var stat_y := y + 16.0 + float(mini(steps.size(), 4)) * 19.0 + 12.0
	var blade := 38.0
	var lunge := 0.0
	if not steps.is_empty() and typeof(steps[0]) == TYPE_DICTIONARY:
		blade = float((steps[0] as Dictionary).get("blade", 38.0))
		lunge = float((steps[0] as Dictionary).get("lunge", 0.0))
	_stat(canvas, font, rect.position.x + 16.0, stat_y, "BLADE LENGTH", "%.0f" % blade)
	_stat(canvas, font, rect.position.x + 196.0, stat_y, "CRIT", "x%.2f" % float(cfg.get("crit_multiplier", 1.0)))
	_stat(canvas, font, rect.position.x + 16.0, stat_y + 20.0, "STEPS", "%d" % steps.size())
	_stat(canvas, font, rect.position.x + 196.0, stat_y + 20.0, "LUNGE", "%.0f" % lunge)

	var note := _unlock_line(id)
	if _equipped(id):
		note = "EQUIPPED"
	elif Profile.is_unlocked(_tab, id):
		note = "OWNED"
	_text(canvas, font, Vector2(rect.position.x, rect.position.y + 330.0), note, 9,
		MathArt.WHITE if _equipped(id) else MathArt.MID, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_armor(canvas: CanvasItem, font: Font, rect: Rect2, id: String, cfg: Dictionary) -> void:
	var center := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + 96.0)
	_draw_shell(canvas, id, cfg, center)

	_text(canvas, font, Vector2(rect.position.x + 16.0, rect.position.y + 170.0),
		str(cfg.get("name", id)), 16, MathArt.PALE)
	_text(canvas, font, Vector2(rect.position.x + 16.0, rect.position.y + 184.0),
		"ARMOUR", 8, MathArt.MID_DIM)
	MathArt.px_rect(canvas, Rect2(rect.position.x + 16.0, rect.position.y + 190.0,
		rect.size.x - 32.0, 1.0), Color(MathArt.STONE, 0.7))

	var y := rect.position.y + 208.0
	_stat(canvas, font, rect.position.x + 16.0, y, "HP BONUS", "%+.0f" % float(cfg.get("hp", 0.0)))
	_stat(canvas, font, rect.position.x + 196.0, y, "I-FRAMES", "%+.0f ms" % (float(cfg.get("iframe", 0.0)) * 1000.0))
	y += 22.0
	_stat(canvas, font, rect.position.x + 16.0, y, "DAMAGE TAKEN", "x%.2f" % float(cfg.get("damage_taken", 1.0)))
	_stat(canvas, font, rect.position.x + 196.0, y, "KUNAI", "%+d" % int(cfg.get("knives", 0)))
	y += 22.0
	_stat(canvas, font, rect.position.x + 16.0, y, "SPEED", "%+.0f" % float(cfg.get("speed", 0.0)))

	var note := _unlock_line(id)
	if _equipped(id):
		note = "WORN"
	elif Profile.is_unlocked(_tab, id):
		note = "OWNED"
	_text(canvas, font, Vector2(rect.position.x, rect.position.y + 330.0), note, 9,
		MathArt.WHITE if _equipped(id) else MathArt.MID, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)


# --------------------------------------------------------------- shared bits

func _text(canvas: CanvasItem, font: Font, at: Vector2, text: String, size: int, color: Color,
		width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	canvas.draw_string(font, at, text, align, width, size, color)


func _stat(canvas: CanvasItem, font: Font, x: float, y: float, label: String, value: String) -> void:
	# Two fixed 152px columns: label left, number right-aligned to the column
	# edge, so a long label can never run into the next column.
	_text(canvas, font, Vector2(x, y), label, 8, MathArt.MID_DIM)
	_text(canvas, font, Vector2(x + 62.0, y), value, 11, MathArt.PALE, 90.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_lock(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	# A hexagon with a slot cut through it: the shape language says "sealed".
	# The slot is painted in the page colour so it reads as a hole, not a line.
	MathArt.px_poly(canvas, MathArt.ngon(6, radius, PI / 6.0, center), color)
	MathArt.px_rect(canvas, Rect2(center.x - 1.5, center.y - radius * 0.8, 3.0, radius * 1.6), BG)
	MathArt.disc(canvas, center + Vector2(0.0, radius * 0.22), radius * 0.26, BG)
	MathArt.ring(canvas, center, radius, Color(MathArt.BLACK, 0.85), 2.0, 6)


func _draw_gem(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	MathArt.px_poly(canvas, MathArt.ngon(4, radius, PI * 0.25, center), color)


func _draw_enemy_body(canvas: CanvasItem, kind: String, cfg: Dictionary, center: Vector2) -> void:
	var z := ZOOM
	var r := (float(cfg.get("body_radius", 12.0)) + 4.0) * z
	var body := center + Vector2(0.0, -2.0 * z)
	var edge := Color(MathArt.BLACK, 0.9)
	match kind:
		"archer":
			MathArt.disc(canvas, body, r, MathArt.ENEMY)
			MathArt.ring(canvas, body, r, edge, 2.0)
			MathArt.disc(canvas, body, r * 0.55, MathArt.STONE)
			for i in 16:
				var theta := TAU * float(i) / 16.0
				var p := Vector2(cos(theta) * (r + 9.0 * z), sin(theta) * 4.5 * z).rotated(0.24)
				MathArt.disc(canvas, body + p, 1.4, Color(MathArt.MID, 0.85))
			MathArt.disc(canvas, body + Vector2(cos(0.7) * (r + 9.0 * z), sin(0.7) * 4.5 * z).rotated(0.24),
				2.4, MathArt.WHITE)
			for i in 3:
				var a := TAU * float(i) / 3.0
				MathArt.disc(canvas, body + Vector2(cos(a) * (r + 7.0 * z), sin(a) * 7.0 * z),
					1.6, MathArt.PALE)
			MathArt.disc(canvas, body + Vector2(r, 0.0), 3.0, MathArt.WHITE)
		"charger":
			MathArt.px_poly(canvas, MathArt.ngon(4, r * 1.15, PI * 0.25, body), MathArt.ENEMY, edge, 2.0)
			MathArt.px_poly(canvas, MathArt.ngon(4, r * 0.65, PI * 0.25, body), MathArt.STONE)
			for side_sign in [-1.0, 1.0]:
				var from := body + Vector2(side_sign * r * 0.6, -r * 0.9)
				MathArt.line(canvas, from,
					from + Vector2(side_sign * 3.2 * z, -8.0 * z), MathArt.WHITE, 2.0)
		"bulwark":
			MathArt.px_poly(canvas, MathArt.ngon(6, r * 1.05, PI / 6.0, body), MathArt.ENEMY, edge, 2.0)
			MathArt.px_poly(canvas, MathArt.ngon(6, r * 0.62, PI / 6.0, body), MathArt.STONE)
			var shield := body + Vector2(r * 1.05, 0.0)
			for i in 3:
				var radius := 13.0 * z * pow(MathArt.INV_PHI, float(i))
				MathArt.px_poly(canvas, MathArt.ngon(6, radius, PI / 6.0, shield),
					Color(MathArt.STONE_HI, 0.5) if i == 0 else Color(0, 0, 0, 0),
					Color(MathArt.WHITE, 0.55 - float(i) * 0.12), 1.5)
			MathArt.line(canvas, shield + Vector2(0.0, -11.0 * z), shield + Vector2(0.0, 11.0 * z),
				Color(MathArt.WHITE, 0.45), 1.0)
		"warden":
			var vertices := MathArt.ngon(5, r * 1.15, -PI * 0.5, body)
			MathArt.px_poly(canvas, vertices, MathArt.BOSS, edge, 2.0)
			MathArt.px_poly(canvas, MathArt.ngon(5, r * 0.70, -PI * 0.5, body), MathArt.STONE)
			for i in 5:
				MathArt.line(canvas, vertices[i], vertices[(i + 2) % 5],
					Color(MathArt.WHITE, 0.42), 1.0)
			var hand := body + Vector2(r * 0.965, 2.0 * z)
			var aim := Vector2.from_angle(0.85)
			MathArt.disc(canvas, hand, 3.4 * z * 0.8, MathArt.WHITE)
			MathArt.line(canvas, hand, hand + aim * 32.0 * z, MathArt.WHITE, 3.0)
			MathArt.line(canvas, hand, hand + aim * 32.0 * z, Color(MathArt.PALE, 0.6), 1.0)
		_:
			MathArt.px_poly(canvas, MathArt.ngon(3, r, -PI * 0.5, body), MathArt.ENEMY, edge, 2.0)
			MathArt.px_poly(canvas, MathArt.ngon(3, r * MathArt.INV_PHI, -PI * 0.5, body), MathArt.STONE)
			var hand := body + Vector2(11.0, 4.0) * z
			MathArt.line(canvas, body + Vector2(5.0, 1.0) * z, hand, Color(MathArt.LIGHT_DIM, 0.55), 1.5)
			MathArt.disc(canvas, hand, 3.0 * z * 0.85, MathArt.WHITE)


func _draw_blade(canvas: CanvasItem, cfg: Dictionary, center: Vector2) -> void:
	var steps: Array = cfg.get("combo", [])
	var length := 38.0
	if not steps.is_empty() and typeof(steps[0]) == TYPE_DICTIONARY:
		length = float((steps[0] as Dictionary).get("blade", 38.0))
	# One fixed magnification for every weapon, so a 50px blade looks longer
	# than a 38px one. The grip sits where the player's hand sits: front edge.
	var scale := BLADE_ZOOM
	var shape := str(cfg.get("shape", ""))
	var direction := Vector2.from_angle(-1.30)
	var side := direction.orthogonal()
	var reach := length * scale
	# Centre the blade's bounding box horizontally; the grip stays at y=148 so
	# every weapon hangs from the same baseline and the lengths compare.
	var hand := Vector2(center.x - 8.0 - direction.x * reach * 0.5, 148.0)
	var tip := hand + direction * reach
	var base := hand + direction * 4.0

	# The grip: hand dot, guard bar, pommel. Same vocabulary as player_visual.
	MathArt.line(canvas, hand + side * 7.0, hand - side * 7.0, MathArt.MID, 2.0)
	MathArt.disc(canvas, hand - direction * 5.0, 2.6, MathArt.MID)
	MathArt.disc(canvas, hand, 4.6, MathArt.WHITE)

	# One tapered quad, never two parallel lines. "shape" only bends the spine.
	var bow := 6.0 * scale if shape == "curve" else 0.0
	var mid := (base + tip) * 0.5 + side * bow
	if shape == "lens":
		mid = (base + tip) * 0.5 - side * 2.0
	var tip_half := 0.6
	if shape == "fractal":
		tip_half = 3.0
	elif shape == "orbit":
		tip_half = 0.0
	var base_half := 2.1 * scale
	var blade := PackedVector2Array([
		base + side * base_half,
		mid + side * tip_half,
		tip,
		mid - side * tip_half,
		base - side * base_half,
	])
	MathArt.px_poly(canvas, blade, MathArt.WHITE, Color(MathArt.WHITE, 0.35), 1.0)
	# A single bright edge along ONE side, so it reads as a bevel.
	MathArt.line(canvas, base + side * (base_half - 1.0), mid + side * maxf(tip_half, 0.3),
		Color(MathArt.WHITE, 0.75), 1.0)
	MathArt.line(canvas, mid + side * maxf(tip_half, 0.3), tip, Color(MathArt.WHITE, 0.75), 1.0)
	if shape == "fractal":
		# Teeth along the spine: still one silhouette, no second blade.
		for i in 3:
			var at := base.lerp(tip, 0.3 + float(i) * 0.22)
			MathArt.line(canvas, at, at + side * 5.0, MathArt.WHITE, 1.5)
	elif shape == "chain":
		for i in 6:
			MathArt.ring(canvas, base.lerp(tip, 0.12 + float(i) * 0.15), 2.6, MathArt.PALE, 1.0)
	elif shape == "orbit":
		for i in 3:
			MathArt.ring(canvas, tip, 4.0 + float(i) * 4.0, Color(MathArt.PALE, 0.6 - float(i) * 0.15), 1.0)


func _draw_shell(canvas: CanvasItem, id: String, cfg: Dictionary, center: Vector2) -> void:
	var half := 15.0
	var square := Rect2(center - Vector2(half, half), Vector2(half * 2.0, half * 2.0))
	MathArt.px_rect(canvas, square, MathArt.WHITE)
	canvas.draw_rect(square, Color(MathArt.BLACK, 0.9), false, 2.0)
	MathArt.px_rect(canvas, square.grow(-6.0), MathArt.INK)
	MathArt.disc(canvas, center, 2.8, MathArt.WHITE)

	var tone := _tone(str(cfg.get("tone", "pale")))
	match id:
		"none":
			for i in 12:
				if i % 2 == 0:
					var from := center + Vector2.from_angle(TAU * float(i) / 12.0) * 32.0
					MathArt.line(canvas, from, from + Vector2.from_angle(TAU * float(i) / 12.0) * 8.0,
						Color(MathArt.STONE_HI, 0.8), 1.0)
		"plate":
			MathArt.px_poly(canvas, MathArt.ngon(4, 44.0, PI * 0.25, center),
				Color(tone, 0.14), tone, 2.0)
			MathArt.px_poly(canvas, MathArt.ngon(4, 44.0 * MathArt.INV_PHI, PI * 0.25, center),
				Color(0, 0, 0, 0), Color(tone, 0.45), 1.0)
		"lattice":
			MathArt.ring(canvas, center, 42.0, tone, 1.5)
			MathArt.px_poly(canvas, MathArt.ngon(6, 42.0, 0.0, center), Color(0, 0, 0, 0),
				Color(tone, 0.45), 1.0)
			for i in 8:
				var angle := TAU * float(i) / 8.0
				MathArt.line(canvas, center + Vector2.from_angle(angle) * 20.0,
					center + Vector2.from_angle(angle) * 42.0, Color(tone, 0.6), 1.0)
		"mantle":
			MathArt.px_poly(canvas, MathArt.star(5, 50.0, 30.0, -PI * 0.5, center),
				Color(tone, 0.12), tone, 1.5)
			MathArt.ring(canvas, center, 30.0, Color(tone, 0.5), 1.0)
		"aegis":
			MathArt.px_poly(canvas, MathArt.ngon(6, 46.0, PI / 6.0, center),
				Color(MathArt.STONE_HI, 0.35), tone, 2.0)
			for i in 3:
				MathArt.ring(canvas, center, 30.0 + float(i) * 7.0, Color(tone, 0.55 - float(i) * 0.14), 1.0)
			for i in 6:
				var angle := TAU * float(i) / 6.0 + _t * 0.4
				MathArt.disc(canvas, center + Vector2.from_angle(angle) * 46.0, 2.0, tone)
		_:
			MathArt.px_poly(canvas, MathArt.ngon(6, 42.0, 0.0, center), Color(0, 0, 0, 0), tone, 1.5)


func _tone(name: String) -> Color:
	match name:
		"stone":
			return MathArt.STONE_HI
		"light":
			return MathArt.LIGHT
		"white":
			return MathArt.WHITE
	return MathArt.PALE
