class_name HubUi
extends CanvasLayer
## Upgrade and character station panels. Keyboard or gamepad; hints show the
## active device's keys.

signal closed

const ROWS_PER_PAGE := 5

## Panel heading per station: [translation key, English text]. Arena-only scope
## is stated in UI_HUBUI_SCOPE: these permanent upgrades and bodies are not
## route-run content.
const TITLES := {
	"upgrade": ["UI_HUBUI_TITLE_UPGRADE", "Upgrades"],
	"character": ["UI_HUBUI_TITLE_CHARACTER", "Character"],
}

var _open_id := ""
var _note := ""
var _index := 0
var _page := 0
var _flash := 0.0
var _flash_row := -1
var _t := 0.0
var _opened_frame := -1
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
	Interface.presentation_changed.connect(_refresh)


## Device/locale switch refreshes key labels only: focus and page stay put.
func _refresh() -> void:
	if is_instance_valid(_canvas):
		_canvas.queue_redraw()


# ------------------------------------------------------------------ public API

func open_station(id: String) -> void:
	if not TITLES.has(id):
		push_error("HubUi: unsupported station " + id)
		closed.emit()
		return
	_open_id = id
	_note = ""
	_index = 0
	_page = 0
	_flash = 0.0
	_flash_row = -1
	# J opens a station and also confirms; ignore keys from the opening frame so
	# the player never buys the first row by accident.
	MathArt.ui_reveal(_canvas)
	_opened_frame = Engine.get_process_frames()
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
	if Engine.get_process_frames() == _opened_frame:
		return
	if Interface.pressed(event, &"ui_back"):
		_close()
	elif Interface.pressed(event, &"ui_nav_up"):
		_move(-1)
	elif Interface.pressed(event, &"ui_nav_down"):
		_move(1)
	elif Interface.pressed(event, &"ui_nav_left") or Interface.pressed(event, &"ui_tab_prev"):
		_side(-1)
	elif Interface.pressed(event, &"ui_nav_right") or Interface.pressed(event, &"ui_tab_next"):
		_side(1)
	elif Interface.pressed(event, &"ui_accept"):
		_confirm()
	else:
		return
	get_viewport().set_input_as_handled()


func _move(direction: int) -> void:
	var rows := _rows()
	if rows.is_empty():
		return
	_index = wrapi(_index + direction, 0, rows.size())
	MathArt.ui_select(_canvas)
	_page = int(float(_index) / float(ROWS_PER_PAGE))
	Sfx.play("ui", -16)


func _side(direction: int) -> void:
	var rows := _rows()
	var pages := maxi(1, ceili(float(rows.size()) / float(ROWS_PER_PAGE)))
	if pages <= 1:
		return
	_page = wrapi(_page + direction, 0, pages)
	_index = mini(_page * ROWS_PER_PAGE, rows.size() - 1)
	Sfx.play("ui", -16)


func _confirm() -> void:
	var rows := _rows()
	if rows.is_empty():
		return
	_activate(rows[_index])


func _activate(row: Dictionary) -> void:
	var id := str(row["id"])
	var kind := str(row["kind"])
	var label := str(row.get("name", id))
	if kind == "enemy":
		return
	# `unlock_floor` is content gating, not a price: a body from a deeper floor
	# stays locked however many cells the player has banked.
	if bool(row.get("lock", false)):
		_fail(_index)
		return
	if kind == "upgrade":
		if Profile.buy_upgrade(id):
			_note = ContentText.of("UI_HUBUI_NOTE_SAVED", "Saved: {name}").format({"name": label})
			Sfx.play("reward", -10)
		else:
			_fail(_index)
		return
	if Profile.is_unlocked(kind, id):
		if Profile.select(kind, id):
			_note = ContentText.of("UI_HUBUI_NOTE_SELECTED", "Selected for Arena: {name}").format({"name": label})
			Sfx.play("reward", -10)
		else:
			_fail(_index)
	elif Profile.unlock(kind, id):
		_note = ContentText.of("UI_HUBUI_NOTE_UNLOCKED", "Unlocked: {name}").format({"name": label})
		Sfx.play("reward", -10)
	else:
		_fail(_index)


func _fail(row: int) -> void:
	_flash = 1.8 if not Profile.last_save_error.is_empty() else 0.45
	_flash_row = row
	var selected: Dictionary = _rows()[row]
	if bool(selected.get("lock", false)):
		_note = ContentText.of("UI_HUBUI_NOTE_LOCKED", "Locked: {value}").format({"value": str(selected.get("right", ContentText.of("UI_HUBUI_REQUIREMENT", "Requirement not met")))})
	elif not Profile.last_save_error.is_empty():
		# Actionable prefix, raw diagnostic reason.
		_note = ContentText.of("UI_HUBUI_SAVE_FAILED", "Save failed: {reason}").format({"reason": Profile.last_save_error})
	elif str(selected.get("price", "")) == "MAX":
		_note = ContentText.of("UI_HUBUI_MAX_LEVEL", "Maximum level")
	else:
		_note = ContentText.of("UI_HUBUI_NOT_COMMITTED", "Not committed / insufficient banked currency")
	Sfx.play("ui", -8)


# ----------------------------------------------------------------- row content

func _rows() -> Array:
	match _open_id:
		"upgrade":
			var upgrades: Array = []
			for id in Data.upgrades:
				var cfg: Dictionary = Data.upgrades[id]
				var cost := Profile.upgrade_cost(id)
				var maxed := cost < 0
				# A soul-priced row must never read as a cell price: the header
				# shows both currencies and the list is the only place that says
				# which one a row spends.
				var currency := Profile.upgrade_currency(id)
				var cost_now := Profile.upgrade_cost(id)
				var shortfall := maxi(0, cost_now - (Profile.souls if currency == "souls" else Profile.cells))
				upgrades.append({
					"id": id, "kind": "upgrade",
					"name": ContentText.name("upgrade", str(id), str(cfg.get("name", id))),
					"info": ContentText.of("UI_HUBUI_LEVEL", "LV {level}/{max}   {text}").format({"level": Profile.upgrade_level(id), "max": int(cfg.get("max", 1)), "text": ContentText.text("upgrade", str(id), str(cfg.get("text", "")))}),
					# Purpose then acquisition: the detail pane answers "what is
					# this for" and "how do I get it" before any price ladder.
					"purpose": ContentText.text("upgrade", str(id), str(cfg.get("text", ""))),
					"acq": ContentText.of("UI_S6_HUB_ACQ_UPGRADE_SOULS", "Permanent Arena upgrade · pay banked Souls in this panel") if currency == "souls" else ContentText.of("UI_S6_HUB_ACQ_UPGRADE_CELLS", "Permanent Arena upgrade · pay banked Cells in this panel"),
					"short": shortfall, "currency": currency,
					"state_name": "completed" if maxed else ("available" if Profile.can_afford_upgrade(id) else "insufficient"),
					# `price` stays the machine value `_fail()` compares.
					"price": "MAX" if maxed else "%d %s" % [cost, "S" if currency == "souls" else "C"],
					"price_text": ContentText.of("UI_COMMON_MAX", "MAX") if maxed else _price(cost, currency),
					"level": Profile.upgrade_level(id), "max": int(cfg.get("max", 1)),
					"state": 2 if maxed else (1 if Profile.can_afford_upgrade(id) else 0),
				})
			return upgrades
		"character":
			var bodies: Array = []
			for id in Data.characters:
				var cfg: Dictionary = Data.characters[id]
				var gate := int(cfg.get("unlock_floor", 0))
				var locked := gate > Profile.best_floor
				bodies.append({
					"id": id, "kind": "character",
					"name": ContentText.name("character", str(id), str(cfg.get("name", id))),
					"info": ContentText.of("UI_HUBUI_STATS", "HP {hp}   SPD {spd}   KNIVES {knives}   {passive}").format({"hp": int(cfg.get("hp", 0.0)), "spd": int(cfg.get("speed", 0.0)), "knives": int(cfg.get("knives", 0)), "passive": ContentText.text("character", str(id), str(cfg.get("passive_text", "")))}),
					"purpose": ContentText.text("character", str(id), str(cfg.get("passive_text", ""))),
					"acq": ContentText.of("UI_S6_HUB_ACQ_FLOOR", "Reach Arena floor {floor} to unlock, then equip here").format({"floor": gate}) if locked else ContentText.of("UI_S6_HUB_ACQ_CHARACTER", "Unlock with Cells here, then equip for Arena"),
					"right": ContentText.of("UI_HUBUI_FLOOR_LOCK", "Floor {floor}").format({"floor": gate}) if locked else _status(
						"character", id, int(cfg.get("cost", 0)), Profile.selected_character),
					"lock": locked,
					"state_name": "locked" if locked else ("owned" if Profile.selected_character == id or Profile.is_unlocked("character", id) else "available"),
					"state": 0 if locked else (
						2 if Profile.selected_character == id else (
							1 if Profile.is_unlocked("character", id) else 0)),
				})
			return bodies
	return []


## Price with its currency named, not the machine `C`/`S` suffix.
func _price(amount: int, currency: String) -> String:
	var unit := ContentText.of("UI_UNIT_SOULS", "Souls") if currency == "souls" else ContentText.of("UI_UNIT_CELLS", "Cells")
	return ContentText.of("UI_PRICE_AMOUNT", "{amount} {unit}").format({"amount": amount, "unit": unit})


func _status(kind: String, id: String, cost: int, selected: String) -> String:
	if Profile.is_unlocked(kind, id):
		return ContentText.of("UI_COMMON_EQUIPPED", "Equipped") if selected == id else ContentText.of("UI_COMMON_OWNED", "Owned")
	return _price(cost, "cells")


# ---------------------------------------------------------------------- draw

func _draw_ui() -> void:
	if _open_id.is_empty():
		MathArt.px_rect(_canvas, Rect2(0, 0, 768, 27), MathArt.INK)
		MathArt.ui_text(_canvas, Vector2(16, 18), ContentText.of("UI_HUBUI_BANKED", "Banked: {cells} Cells · {souls} Souls · Best Arena floor {floor}").format({"cells": Profile.cells, "souls": Profile.souls, "floor": Profile.best_floor}), 11, MathArt.CELL)
		return
	MathArt.px_rect(_canvas, Rect2(0, 0, 768, 480), MathArt.INK)
	MathArt.ui_panel(_canvas, MathArt.UI_PAGE)
	var title: Array = TITLES.get(_open_id, TITLES["upgrade"])
	MathArt.ui_heading(_canvas, ContentText.of(str(title[0]), str(title[1])), ContentText.of("UI_HUBUI_SCOPE", "Permanent collection / effects apply to Arena only"), ContentText.of("UI_HUBUI_WALLET", "{cells} Cells · {souls} Souls").format({"cells": Profile.cells, "souls": Profile.souls}))
	var rows := _rows()
	var first := _page * ROWS_PER_PAGE
	for slot in mini(ROWS_PER_PAGE, rows.size() - first):
		var rect := Rect2(52, 112 + slot * 44, 246, 42)
		var row: Dictionary = rows[first + slot]
		if first + slot == _index: MathArt.ui_focus(_canvas, rect)
		MathArt.ui_service(_canvas, rect.position + Vector2(26, 22), "character" if _open_id == "character" else "forge", 11)
		var names := MathArt.ui_wrap(str(row.name), 184, 13)
		var pitch := MathArt.ui_line_height(13)
		for i in mini(2, names.size()): MathArt.ui_text(_canvas, rect.position + Vector2(48, 17 + i * pitch), names[i], 13, MathArt.WHITE if first + slot == _index else MathArt.PALE)
	MathArt.line(_canvas, Vector2(310, 112), Vector2(310, 354), MathArt.STONE, 1)
	if not rows.is_empty():
		var row: Dictionary = rows[_index]
		if _open_id == "character":
			MathArt.ui_service(_canvas, Vector2(364, 152), "character", 28)
		else:
			MathArt.ui_axis_emblem(_canvas, Vector2(364, 152), "brutality" if "edge" in str(row.id) or "brutality" in str(row.id) else ("tactics" if "tactics" in str(row.id) else "survival"), 30)
		var names := MathArt.ui_wrap(str(row.name), 300, 16)
		for i in mini(2, names.size()): MathArt.ui_text(_canvas, Vector2(416, 142 + i * MathArt.ui_line_height(16)), names[i], 16, MathArt.WHITE)
		var status := str(row.get("price_text", row.get("right", "")))
		if row.get("lock", false):
			status = ContentText.of("UI_HUBUI_LOCKED_STATUS", "Locked / reach {value}").format({"value": str(row.get("right", ""))})
			status += " · " + ContentText.of("UI_S6_HUB_STATE_LOCKED", "missing condition")
		elif _open_id == "upgrade":
			if int(row.state) == 2:
				status += " · " + ContentText.of("UI_S6_HUB_STATE_COMPLETED", "Completed")
			elif int(row.state) == 1:
				status += " · " + ContentText.of("UI_S6_HUB_STATE_UNLOCKABLE", "Unlockable")
			else:
				status += " · " + ContentText.of("UI_S6_HUB_STATE_INSUFFICIENT", "Need {amount}").format({"amount": _price(int(row.get("short", 0)), str(row.get("currency", "cells")))})
		MathArt.ui_state(_canvas, Vector2(332, 206), str(row.get("state_name", "available")))
		MathArt.ui_text(_canvas, Vector2(344, 211), status, 16, MathArt.CELL if int(row.state) > 0 else MathArt.LIGHT_DIM, 356)
		# Acquisition first, then what the purchase changes.
		var details := MathArt.ui_wrap(str(row.get("acq", "")) + "\n" + str(row.info), 372, 13)
		for i in mini(5, details.size()): MathArt.ui_text(_canvas, Vector2(328, 238 + i * 20), details[i], 13)
		if row.has("level"):
			var count := int(row.max)
			for i in count:
				var at := Vector2(328 + i * 14, 348)
				MathArt.poly(_canvas, MathArt.ngon(4, 4, 0, at), MathArt.ACCENT if i < int(row.level) else MathArt.INK, MathArt.PALE, 1)
	var pages := maxi(1, ceili(float(rows.size()) / ROWS_PER_PAGE))
	MathArt.ui_text(_canvas, Vector2(52, 361), ContentText.of("UI_HUBUI_PAGE", "Page {page} / {pages}").format({"page": _page + 1, "pages": pages}), 11)
	var notes := MathArt.ui_wrap(_note if not _note.is_empty() else ContentText.of("UI_HUBUI_FOOTER", "These permanent upgrades and selections do not change route runs."), 664, 12)
	var note_pitch := MathArt.ui_line_height(12)
	for i in mini(3, notes.size()): MathArt.ui_text(_canvas, Vector2(52, 383 + i * note_pitch), notes[i], 12, MathArt.WHITE if not _note.is_empty() else MathArt.PALE)
	var x := 52.0
	x += MathArt.ui_key(_canvas, Vector2(x, 432), _key_labels([&"ui_nav_up", &"ui_nav_down"]), ContentText.of("UI_KEY_SELECT", "Select"))
	if pages > 1: x += MathArt.ui_key(_canvas, Vector2(x, 432), _key_labels([&"ui_nav_left", &"ui_nav_right", &"ui_tab_prev", &"ui_tab_next"]), ContentText.of("UI_KEY_PAGE", "Page"))
	MathArt.ui_key(_canvas, Vector2(x, 432), Interface.prompt(&"ui_accept"), ContentText.of("UI_KEY_CONFIRM", "Confirm"))
	MathArt.ui_key(_canvas, Vector2(636, 432), Interface.prompt(&"ui_back"), ContentText.of("UI_KEY_BACK", "Back"))


## One neutral keycap string per device: dedupe repeated labels (D-pad, RS)
## without hiding an unbound action behind a keyboard-only literal.
func _key_labels(actions: Array) -> String:
	var parts: Array[String] = []
	for action: StringName in actions:
		var label := Interface.prompt(action)
		if label.is_empty() or label == "—" or parts.has(label):
			continue
		parts.append(label)
	return " ".join(parts) if not parts.is_empty() else "—"
