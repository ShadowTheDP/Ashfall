class_name SkillTree
extends CanvasLayer
## The permanent skill tree. Nodes are placed by normalised "at" coordinates in
## data/skill_nodes.json, so the layout lives in data, not in this file.
## The cursor jumps to the NEAREST node in the pressed direction: with a tree
## this shape, index-stepping would be unusable.

signal closed

const TREE_RECT := Rect2(52, 112, 410, 264)
const NODE_R := 12.0
const PAD := 26.0

var _canvas: Control
var _ids: Array[String] = []
var _pos: Dictionary = {}
var _index := 0
var _open := false
var _open_frame := -1
var _t := 0.0
var _flash_t := 0.0
var _note := ""
var _note_t := 0.0
## Save failure is state, not a prefix parsed back out of display text. The raw
## diagnostic scrolls in the detail column; the receipt stays bounded.
var _failed := false
var _fail_reason := ""
var _fail_scroll := 0
var _fail_count := 0
var _locale := ""


func _ready() -> void:
	layer = 60
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_locale = TranslationServer.get_locale()
	if not Interface.presentation_changed.is_connected(_on_presentation_changed):
		Interface.presentation_changed.connect(_on_presentation_changed)
	_ensure_canvas()


func _on_presentation_changed() -> void:
	_canvas.queue_redraw()


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
	_open_frame = Engine.get_process_frames()
	visible = true
	MathArt.ui_reveal(_canvas)
	_note = ""
	_note_t = 0.0
	_flash_t = 0.0
	_failed = false
	_fail_reason = ""
	_fail_scroll = 0
	_fail_count = 0
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
	if TranslationServer.get_locale() != _locale:
		_locale = TranslationServer.get_locale()
		_canvas.queue_redraw()
	_canvas.queue_redraw()


## _input, not _unhandled_input: the HUD also listens for Esc and it is
## later in the tree, so unhandled input reaches it first. A modal panel
## has to claim the event before the HUD can pause the game under it.
func _input(event: InputEvent) -> void:
	if not _open:
		return
	if not _is_menu_event(event):
		return
	# A modal owns every menu event while it is up. An event it does not use
	# would otherwise reach the hub's proximity handler and raise a second panel
	# (J) or start a floor (Enter) underneath this one.
	get_viewport().set_input_as_handled()
	# Hub may open this page during the same input dispatch that selected the
	# station; do not let that press also learn a node.
	if Engine.get_process_frames() == _open_frame:
		return
	if Interface.pressed(event, &"ui_back"):
		close()
		return
	if _failed and Interface.pressed(event, &"ui_detail_up"):
		_scroll_fail(-1)
		return
	if _failed and Interface.pressed(event, &"ui_detail_down"):
		_scroll_fail(1)
		return
	if Interface.pressed(event, &"ui_accept"):
		_buy()
		return
	if Interface.pressed(event, &"ui_nav_up"):
		_move(Vector2.UP)
	elif Interface.pressed(event, &"ui_nav_down"):
		_move(Vector2.DOWN)
	elif Interface.pressed(event, &"ui_nav_left"):
		_move(Vector2.LEFT)
	elif Interface.pressed(event, &"ui_nav_right"):
		_move(Vector2.RIGHT)


func _is_menu_event(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventAction


func _scroll_fail(direction: int) -> void:
	var limit := maxi(0, _fail_count - 7)
	var next := clampi(_fail_scroll + direction, 0, limit)
	if next == _fail_scroll:
		return
	_fail_scroll = next
	_canvas.queue_redraw()


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
		# A save failure belongs to the node that produced it. Moving the cursor
		# clears the raw payload too, so the receipt never outlives its owner.
		_failed = false
		_fail_reason = ""
		_fail_scroll = 0
		_note = ""
		_note_t = 0.0
		MathArt.ui_select(_canvas)
		Sfx.play("ui", -14)
		_canvas.queue_redraw()


func _buy() -> void:
	if _ids.is_empty():
		return
	var id := _ids[_index]
	if Profile.has_skill(id):
		_failed = false
		_fail_reason = ""
		_fail_scroll = 0
		_note = "ALREADY OWNED"
		_note_t = 1.4
		_canvas.queue_redraw()
		return
	if Profile.buy_skill(id):
		_failed = false
		_fail_reason = ""
		_fail_scroll = 0
		_note = "LEARNED: " + id
		_note_t = 1.6
		Sfx.play("reward", -8)
		_canvas.queue_redraw()
		return
	# Raw `_note` stays the machine payload external fixtures compare; the
	# receipt and the raw reason are separate display state, never parsed back.
	_flash_t = 0.45
	_failed = not Profile.last_save_error.is_empty()
	_fail_reason = Profile.last_save_error if _failed else ""
	_fail_scroll = 0
	_note = "SAVE FAILED: " + Profile.last_save_error if _failed else "BLOCKED: " + id
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


## Raw data-name accessor; drawing uses _name_display() so zh_TW never shows an
## ID-derived English label.
func _name_of(id: String) -> String:
	return str(_node(id).get("name", id))


func _name_display(id: String) -> String:
	return ContentText.name("skill", id, _name_of(id))


func _text_display(id: String) -> String:
	return ContentText.text("skill", id, str(_node(id).get("text", "")))


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


## Display-side reason; the raw machine form never reaches the screen.
func _blocked_display(id: String) -> String:
	# Prerequisites FIRST: a player who cannot learn a node for a structural
	# reason must not be told to grind cells for it.
	var missing: Array[String] = []
	for parent in _requires(id):
		if not Profile.has_skill(str(parent)):
			missing.append(_name_display(str(parent)))
	if not missing.is_empty():
		return ContentText.of("UI_TREE_REQUIRES", "REQUIRES {names}").format({"names": ", ".join(missing)})
	if Profile.cells < _cost(id):
		return ContentText.of("UI_TREE_NEED_CELLS", "NEED {cost} CELLS").format({"cost": _cost(id)})
	return ContentText.of("UI_TREE_CANNOT_LEARN", "CANNOT LEARN")


func _note_display() -> String:
	if _failed and not _fail_reason.is_empty():
		return ContentText.of("UI_S6_SAVE_FAILED_FIXED", "NOT SAVED / {action} RETRY / reason in detail pane").format({"action": Interface.prompt(&"ui_accept")})
	if _note.begins_with("LEARNED: "):
		return ContentText.of("UI_TREE_LEARNED", "LEARNED {name}").format({"name": _name_display(_note.substr(9))})
	if _note.begins_with("BLOCKED: "):
		return _blocked_display(_note.substr(9))
	if _note == "ALREADY OWNED":
		return ContentText.of("UI_TREE_ALREADY_OWNED", "ALREADY OWNED")
	return _note


# -------------------------------------------------------------------- painting

func _paint(canvas: Control) -> void:
	MathArt.px_rect(canvas, Rect2(0, 0, 768, 480), MathArt.INK)
	MathArt.ui_panel(canvas, MathArt.UI_PAGE)
	MathArt.ui_heading(canvas,
		ContentText.of("UI_TREE_TITLE", "Skill tree"),
		ContentText.of("UI_TREE_CONTEXT", "Permanent upgrades / effects apply to Arena only"),
		ContentText.of("UI_TREE_WALLET", "{cells} banked Cells").format({"cells": Profile.cells}))
	for id in _ids:
		for parent in _requires(id):
			if _pos.has(str(parent)):
				MathArt.line(canvas, _pos[str(parent)], _pos[id], MathArt.PALE if Profile.has_skill(id) else MathArt.STONE, 2 if Profile.has_skill(id) else 1)
	for i in _ids.size():
		var id := _ids[i]
		var at: Vector2 = _pos[id]
		var owned := Profile.has_skill(id)
		var available := Profile.skill_available(id)
		var tone := MathArt.PALE if owned or i == _index else (MathArt.PALE if available else MathArt.LIGHT_DIM)
		MathArt.poly(canvas, MathArt.ngon(6, NODE_R, PI / 6, at), MathArt.HEAL if owned else MathArt.BG_2 if available else MathArt.INK, MathArt.ACCENT if i == _index else tone, 2 if available or owned else 1)
		if owned: MathArt.disc(canvas, at, 3, MathArt.INK)
		if i == _index: MathArt.ring(canvas, at, NODE_R * MathArt.PHI, MathArt.ACCENT, 2, 6)
		var central := absf(at.x - TREE_RECT.get_center().x) < NODE_R
		MathArt.ui_text(canvas, at + (Vector2(NODE_R + 14, 4) if central else Vector2(-55, 28)), _name_display(id), 11, tone, 110, HORIZONTAL_ALIGNMENT_LEFT if central else HORIZONTAL_ALIGNMENT_CENTER)
	MathArt.line(canvas, Vector2(474, 112), Vector2(474, 398), MathArt.STONE, 1)
	if not _ids.is_empty():
		var id := _ids[_index]
		var emblem := "brutality" if "edge" in id or "crit" in id else "tactics" if "swift" in id or "armory" in id else "survival"
		MathArt.ui_axis_emblem(canvas, Vector2(520, 142), emblem, 24)
		var names := MathArt.ui_wrap(_name_display(id), 156, 16)
		for i in mini(2, names.size()): MathArt.ui_text(canvas, Vector2(560, 140 + i * MathArt.ui_line_height(16)), names[i], 16, MathArt.WHITE)
		var owned := Profile.has_skill(id)
		MathArt.ui_text(canvas, Vector2(494, 198), ContentText.of("UI_TREE_OWNED", "Owned") if owned else ContentText.of("UI_TREE_PRICE", "{cells} Cells").format({"cells": _cost(id)}), 16, MathArt.HEAL if owned else MathArt.CELL)
		var detail := _text_display(id) + "\n\n" + (ContentText.of("UI_TREE_ALREADY_LEARNED", "Already learned.") if owned else _blocked_display(id) if not Profile.skill_available(id) or Profile.cells < _cost(id) else ContentText.of("UI_TREE_AVAILABLE", "Available to learn."))
		var lines: Array[String]
		if _failed and not _fail_reason.is_empty():
			# The raw diagnostic is the only unbounded string; it owns the seven
			# scrollable detail rows. The receipt below stays fixed.
			lines = MathArt.ui_wrap(ContentText.of("UI_S6_FAIL_DETAIL", "NOT SAVED / DIAGNOSTIC") + "\n" + _fail_reason, 220, 13)
			_fail_count = lines.size()
			_fail_scroll = clampi(_fail_scroll, 0, maxi(0, _fail_count - 7))
		else:
			lines = MathArt.ui_wrap(detail, 220, 13)
			_fail_count = 0
			_fail_scroll = 0
		for i in mini(7, lines.size() - _fail_scroll): MathArt.ui_text(canvas, Vector2(494, 232 + i * MathArt.ui_line_height(13)), lines[_fail_scroll + i], 13)
		if _fail_count > 7:
			var scroll_label := Interface.prompt(&"ui_detail_up") + " / " + Interface.prompt(&"ui_detail_down")
			MathArt.ui_text(canvas, Vector2(494, 359), ContentText.of("UI_S6_FAIL_SCROLL_HINT", "{scroll} scroll diagnostic").format({"scroll": scroll_label}), 11, MathArt.LIGHT_DIM)
		var notes := MathArt.ui_wrap(_note_display(), 220, 11)
		for i in mini(3, notes.size()): MathArt.ui_text(canvas, Vector2(494, 371 + i * MathArt.ui_line_height(11)), notes[i], 11, MathArt.WHITE)
	MathArt.ui_text(canvas, Vector2(52, 399), ContentText.of("UI_TREE_LEGEND", "Filled: owned · Hollow: available · Dim: locked"), 11)
	var x := 52.0
	x += MathArt.ui_key(canvas, Vector2(x, 428), _nearest_prompt(), ContentText.of("UI_TREE_KEY_NEAREST", "Nearest skill"))
	x += MathArt.ui_key(canvas, Vector2(x, 428), Interface.prompt(&"ui_accept"), ContentText.of("UI_TREE_KEY_LEARN", "Learn"))
	MathArt.ui_key(canvas, Vector2(636, 428), Interface.prompt(&"ui_back"), ContentText.of("UI_TREE_KEY_BACK", "Back"))


## The nearest-node control is directional, so show each direction once. On a
## gamepad every direction is the same D-pad/stick prompt and repeating it four
## times would only crowd the key band.
func _nearest_prompt() -> String:
	var parts: Array[String] = []
	for action: StringName in [&"ui_nav_up", &"ui_nav_left", &"ui_nav_down", &"ui_nav_right"]:
		var text := Interface.prompt(action)
		if not parts.has(text):
			parts.append(text)
	return "/".join(parts)
