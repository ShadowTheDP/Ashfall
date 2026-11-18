class_name ArchiveScreen
extends CanvasLayer
## The codex: bestiary, weapons, armour. Three tabs, one list, one card.
## Read-only except accept, which equips an unlocked entry or pays to unlock a
## record the player has not met yet.

signal closed

const TABS: Array[String] = ["enemy", "weapon", "armor"]
const ROWS := 5
const ROW_H := 44.0
const DETAIL_ROWS := 6

var _canvas: Control
var _tab := "enemy"
var _ids: Array[String] = []
var _index := 0
var _scroll := 0
var _detail_scroll := 0
var _detail_focus := false
var _open := false
var _open_frame := -1
var _t := 0.0
var _flash_row := -1
var _flash_t := 0.0
var _note := ""
var _note_t := 0.0
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
	_detail_scroll = 0
	_detail_focus = false
	_note = ""
	_note_t = 0.0
	_flash_row = -1
	_flash_t = 0.0
	_reload()
	_open = true
	_open_frame = Engine.get_process_frames()
	visible = true
	MathArt.ui_reveal(_canvas)
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
	# would otherwise reach the hub's proximity handler: J re-opened this
	# screen and reset the cursor, and J by the door started a floor under it.
	get_viewport().set_input_as_handled()
	# Hub may open this page during the same input dispatch that selected the
	# station. Ignore that frame so the opening/held confirm cannot also buy or
	# switch a record; the next real press needs its own edge.
	if Engine.get_process_frames() == _open_frame:
		return
	if Interface.pressed(event, &"ui_back"):
		close()
		return
	if Interface.pressed(event, &"ui_tab_prev"):
		_switch_tab(-1)
		return
	if Interface.pressed(event, &"ui_tab_next"):
		_switch_tab(1)
		return
	if Interface.pressed(event, &"ui_secondary"):
		_toggle_detail_focus()
		return
	if event is InputEventJoypadMotion:
		# The right stick owns the record detail; the left stick still navigates
		# the list below, so only a matched detail axis returns early.
		if Interface.pressed(event, &"ui_detail_up"):
			_scroll_detail(-1)
			return
		if Interface.pressed(event, &"ui_detail_down"):
			_scroll_detail(1)
			return
	if _detail_focus:
		# X moved focus into the detail pane. Up/Down now scroll it; the native
		# detail pair covers keyboard and right stick, while ui_nav covers the
		# gamepad D-pad. Without focus the same keys keep moving the record list.
		if Interface.pressed(event, &"ui_detail_up") or Interface.pressed(event, &"ui_nav_up"):
			_scroll_detail(-1)
			return
		if Interface.pressed(event, &"ui_detail_down") or Interface.pressed(event, &"ui_nav_down"):
			_scroll_detail(1)
			return
	if Interface.pressed(event, &"ui_nav_left"):
		_switch_tab(-1)
	elif Interface.pressed(event, &"ui_nav_right"):
		_switch_tab(1)
	elif Interface.pressed(event, &"ui_nav_up"):
		_move(-1)
	elif Interface.pressed(event, &"ui_nav_down"):
		_move(1)
	elif _tab != "enemy" and Interface.pressed(event, &"ui_accept"):
		_activate()


func _is_menu_event(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventAction


## A gamepad maps both directions of a pair to the same prompt; show it once.
func _prompt_pair(first: StringName, second: StringName) -> String:
	var a := Interface.prompt(first)
	var b := Interface.prompt(second)
	return a if a == b else a + "/" + b


func _switch_tab(delta_index: int) -> void:
	var next := wrapi(TABS.find(_tab) + delta_index, 0, TABS.size())
	_tab = TABS[next]
	_index = 0
	_scroll = 0
	_detail_scroll = 0
	_detail_focus = false
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
	_detail_scroll = 0
	MathArt.ui_select(_canvas)
	if _index < _scroll:
		_scroll = _index
	elif _index >= _scroll + ROWS:
		_scroll = _index - ROWS + 1
	Sfx.play("ui", -14)
	_canvas.queue_redraw()


func _scroll_detail(direction: int) -> void:
	if _ids.is_empty():
		return
	var info := _record_copy(_ids[_index])
	var details: Array = info.details
	var limit := maxi(0, details.size() - DETAIL_ROWS)
	if limit <= 0:
		return
	var next := clampi(_detail_scroll + direction, 0, limit)
	if next == _detail_scroll:
		return
	_detail_scroll = next
	Sfx.play("ui", -14)
	_canvas.queue_redraw()


## X moves the visual focus between the record list and its detail pane. The
## page stays one modal: no stack, no extra layer, and back still closes it.
func _toggle_detail_focus() -> void:
	if _ids.is_empty():
		return
	_detail_focus = not _detail_focus
	MathArt.ui_select(_canvas)
	Sfx.play("ui", -14)
	_canvas.queue_redraw()


func _activate() -> void:
	if _ids.is_empty() or _tab == "enemy":
		return
	var id := _ids[_index]
	if Profile.is_unlocked(_tab, id):
		if Profile.select(_tab, id):
			_note = "EQUIPPED: " + id
			_note_t = 1.6
			Sfx.play("pickup", -10)
			return
	elif _tab == "weapon" and not Profile.gear_blueprint(id).is_empty():
		_note = "BLUEPRINT: " + id
		_note_t = 2.5
		Sfx.play("block", -10)
		return
	elif Profile.unlock(_tab, id):
		Profile.see(_tab, id)
		_note = "UNLOCKED: " + id
		_note_t = 1.8
		Sfx.play("reward", -8)
		return
	# Failure is reported by flashing the row, never by a silent no-op.
	_flash_row = _index
	_flash_t = 0.45
	_note = "SAVE FAILED: " + Profile.last_save_error if not Profile.last_save_error.is_empty() else "NEED %d CELLS" % _cost_of(id)
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


## Raw data-name accessor used by state/bookkeeping paths. Drawing goes through
## _name_display() so a player never sees an English name in zh_TW.
func _name_of(id: String) -> String:
	return str(_cfg(id).get("name", id))


func _name_display(id: String) -> String:
	var english := _name_of(id)
	match _tab:
		"weapon":
			return ContentText.name("weapon", id, english)
		"armor":
			return ContentText.name("armor", id, english)
	return ContentText.name("enemy", id, english)


## Weapons price the unlock as `unlock_cost`, armour and characters as `cost`.
## Reading only `cost` advertised every weapon as free.
func _cost_of(id: String) -> int:
	var cfg := _cfg(id)
	return int(cfg.get("cost", cfg.get("unlock_cost", 0)))


## A weapon priced by a carried blueprint names the Collector plan instead of
## pretending the cells can be paid here. Display only: the note keeps the raw
## "BLUEPRINT: <id>" payload that existing fixtures compare.
func _unlock_display(id: String) -> String:
	var blueprint := Profile.gear_blueprint(id) if _tab == "weapon" else ""
	if not blueprint.is_empty():
		var cfg: Dictionary = Data.passage.blueprints[blueprint]
		var biome_id := str(cfg.get("biome", ""))
		var biome := ContentText.name("biome", biome_id, str(Data.route_graph.nodes.get(biome_id, {}).get("name", biome_id)))
		return ContentText.of("UI_ARCHIVE_BLUEPRINT", "BLUEPRINT: {biome} / COLLECTOR {cost} C").format({"biome": biome, "cost": cfg.get("cost", 0)})
	var cost := _cost_of(id)
	var accept := Interface.prompt(&"ui_accept")
	return ContentText.of("UI_ARCHIVE_UNLOCK_FOR", "{accept} TO UNLOCK FOR {cost} CELLS").format({"accept": accept, "cost": cost}) if cost > 0 else ContentText.of("UI_ARCHIVE_UNLOCK_FREE", "{accept} TO UNLOCK").format({"accept": accept})


func _note_display() -> String:
	if _note.begins_with("EQUIPPED: "):
		return ContentText.of("UI_ARCHIVE_EQUIPPED", "EQUIPPED: {name}").format({"name": _name_display(_note.substr(10))})
	if _note.begins_with("UNLOCKED: "):
		return ContentText.of("UI_ARCHIVE_UNLOCKED", "UNLOCKED: {name}").format({"name": _name_display(_note.substr(10))})
	if _note.begins_with("BLUEPRINT: "):
		return _unlock_display(_note.substr(11))
	if _note.begins_with("SAVE FAILED: "):
		return Hud.save_failed_display(_note.substr(13))
	if _note.begins_with("NEED ") and _note.ends_with(" CELLS"):
		return ContentText.of("UI_ARCHIVE_NEED_CELLS", "NEED {cost} CELLS").format({"cost": _note.trim_prefix("NEED ").trim_suffix(" CELLS")})
	return _note


## A record is readable once it has been met in the field or bought.
func _known(id: String) -> bool:
	return Profile.has_seen(_tab, id) or Profile.is_unlocked(_tab, id)


func _equipped(id: String) -> bool:
	if _tab == "weapon":
		return Profile.selected_weapon == id
	if _tab == "armor":
		return Profile.selected_armor == id
	return false


func _status_display(id: String) -> String:
	if _tab == "enemy":
		return ContentText.of("UI_ARCHIVE_RECORDED", "Recorded")
	if not Profile.is_unlocked(_tab, id):
		return _unlock_display(id)
	if _tab == "weapon":
		# selected_weapon replaces the formal run's first weapon (game.gd:379);
		# only armour below stays arena/legacy-only.
		return ContentText.of("UI_ARCHIVE_WEAPON_EQUIPPED", "Equipped / first weapon in runs") if _equipped(id) else ContentText.of("UI_ARCHIVE_WEAPON_OWNED", "Owned / equip to use in runs")
	return ContentText.of("UI_ARCHIVE_ARMOR_EQUIPPED", "Equipped / Arena only") if _equipped(id) else ContentText.of("UI_ARCHIVE_ARMOR_OWNED", "Owned / Arena only")


func _tab_label(tab: String) -> String:
	match tab:
		"weapon": return ContentText.of("UI_ARCHIVE_TAB_WEAPONS", "WEAPONS")
		"armor": return ContentText.of("UI_ARCHIVE_TAB_ARMOR", "ARMOUR")
	return ContentText.of("UI_ARCHIVE_TAB_BESTIARY", "BESTIARY")


# -------------------------------------------------------------------- painting

func _paint(canvas: Control) -> void:
	MathArt.px_rect(canvas, Rect2(0, 0, 768, 480), MathArt.INK)
	MathArt.ui_panel(canvas, MathArt.UI_PAGE)
	MathArt.ui_heading(canvas,
		ContentText.of("UI_ARCHIVE_TITLE", "Archives"),
		ContentText.of("UI_ARCHIVE_CONTEXT", "Collection / weapons carry into runs · armour is Arena only"),
		ContentText.of("UI_ARCHIVE_WALLET", "{cells} banked Cells").format({"cells": Profile.cells}))
	for i in TABS.size():
		var rect := Rect2(52 + i * 226, 110, 212, 28)
		if TABS[i] == _tab: MathArt.ui_focus(canvas, rect)
		MathArt.ui_text(canvas, rect.position + Vector2(24, 19), _tab_label(TABS[i]), 13, MathArt.WHITE if TABS[i] == _tab else MathArt.PALE)
	for row in ROWS:
		var index := _scroll + row
		if index >= _ids.size(): break
		var id := _ids[index]
		var rect := Rect2(52, 150 + row * ROW_H, 246, ROW_H - 2)
		if index == _index:
			if _detail_focus: MathArt.ui_surface(canvas, rect, false, true)
			else: MathArt.ui_focus(canvas, rect)
		var names := MathArt.ui_wrap(_name_display(id) if _known(id) else ContentText.of("UI_ARCHIVE_UNKNOWN", "Unknown record"), 210, 13)
		for n in mini(2, names.size()): MathArt.ui_text(canvas, rect.position + Vector2(24, 17 + n * MathArt.ui_line_height(13)), names[n], 13, MathArt.WHITE if index == _index else MathArt.PALE)
	MathArt.line(canvas, Vector2(310, 150), Vector2(310, 362), MathArt.STONE, 1)
	MathArt.ui_text(canvas, Vector2(52, 390), ContentText.of("UI_ARCHIVE_COUNT", "{index} / {total} · {nav} more records").format({"index": _index + 1 if not _ids.is_empty() else 0, "total": _ids.size(), "nav": _prompt_pair(&"ui_nav_up", &"ui_nav_down")}), 11)
	if not _ids.is_empty() and _detail_focus:
		MathArt.ui_surface(canvas, Rect2(322, 166, 378, 196), true, false)
	if not _ids.is_empty(): _draw_record(canvas, _ids[_index])
	var lines := MathArt.ui_wrap(_note_display(), 664, 11)
	for i in mini(2, lines.size()): MathArt.ui_text(canvas, Vector2(52, 407 + i * MathArt.ui_line_height(11)), lines[i], 11, MathArt.WHITE)
	var x := 52.0
	x += MathArt.ui_key(canvas, Vector2(x, 432), _prompt_pair(&"ui_tab_prev", &"ui_tab_next"), ContentText.of("UI_ARCHIVE_KEY_CATEGORY", "Category"))
	x += MathArt.ui_key(canvas, Vector2(x, 432), _prompt_pair(&"ui_nav_up", &"ui_nav_down"), ContentText.of("UI_ARCHIVE_KEY_RECORD", "Record"))
	if _tab != "enemy": x += MathArt.ui_key(canvas, Vector2(x, 432), Interface.prompt(&"ui_accept"), ContentText.of("UI_ARCHIVE_KEY_EQUIP", "Equip / unlock"))
	# X enters/leaves the detail pane. Once inside, the same chip shows the real
	# scroll pair so keyboard (Up/Down) and gamepad (RS) never see a false hint.
	var detail_key := Interface.prompt(&"ui_secondary")
	if _detail_focus:
		detail_key += " / " + _prompt_pair(&"ui_detail_up", &"ui_detail_down")
	MathArt.ui_key(canvas, Vector2(x, 432), detail_key, ContentText.of("UI_ARCHIVE_KEY_DETAIL", "Details"))
	MathArt.ui_key(canvas, Vector2(636, 432), Interface.prompt(&"ui_back"), ContentText.of("UI_ARCHIVE_KEY_BACK", "Back"))


## Data-only half of the record pane. Drawing the icon and the copy are split so
## the right-stick scroll can measure the same wrapped copy without duplicating
## the per-tab text rules.
func _record_copy(id: String) -> Dictionary:
	var known := _known(id)
	var cfg := _cfg(id)
	var status := _status_display(id)
	var lines: Array[String] = []
	if known:
		match _tab:
			"enemy":
				lines = [
					ContentText.of("UI_ARCHIVE_ENEMY_HP", "HP {hp} · damage {damage}").format({"hp": "%.0f" % float(cfg.get("hp", 0)), "damage": "%.0f" % float(cfg.get("damage", 0))}),
					ContentText.of("UI_ARCHIVE_ENEMY_SPEED", "Speed {speed} · range {range}").format({"speed": "%.0f" % float(cfg.get("speed", 0)), "range": "%.0f" % float(cfg.get("attack_range", 0))}),
					ContentText.of("UI_ARCHIVE_ENEMY_TIMING", "Windup {windup}s · active {active}s").format({"windup": "%.2f" % float(cfg.get("windup", 0)), "active": "%.2f" % float(cfg.get("active", 0))}),
					ContentText.of("UI_ARCHIVE_ENEMY_RECOVERY", "Recovery {recovery}s · {cells} Cells").format({"recovery": "%.2f" % float(cfg.get("recovery", 0)), "cells": cfg.get("cells", 0)}),
				]
			"weapon":
				var steps: Array = cfg.get("combo", [])
				var damage: Array[String] = []
				for step: Dictionary in steps: damage.append(str(step.get("damage", 0)))
				lines = [
					ContentText.of("UI_ARCHIVE_WEAPON_COMBO", "Combo damage: {damage}").format({"damage": " → ".join(damage)}),
					ContentText.of("UI_ARCHIVE_WEAPON_CRIT", "Critical multiplier x{mult}").format({"mult": "%.2f" % float(cfg.get("crit_multiplier", 1))}),
					ContentText.of("UI_ARCHIVE_WEAPON_STEPS", "{count} combo steps").format({"count": steps.size()}),
				]
				if not steps.is_empty():
					lines.append(ContentText.of("UI_ARCHIVE_WEAPON_BLADE", "Blade {blade} · first lunge {lunge}").format({"blade": "%.0f" % float(steps[0].get("blade", 38)), "lunge": "%.0f" % float(steps[0].get("lunge", 0))}))
			"armor":
				lines = [
					ContentText.of("UI_ARCHIVE_ARMOR_HP", "HP {hp} · speed {speed}").format({"hp": "%+.0f" % float(cfg.get("hp", 0)), "speed": "%+.0f" % float(cfg.get("speed", 0))}),
					ContentText.of("UI_ARCHIVE_ARMOR_IFRAME", "Invulnerability {ms} ms").format({"ms": "%+.0f" % (float(cfg.get("iframe", 0)) * 1000)}),
					ContentText.of("UI_ARCHIVE_ARMOR_TAKEN", "Damage taken x{taken}").format({"taken": "%.2f" % float(cfg.get("damage_taken", 1))}),
					ContentText.of("UI_ARCHIVE_ARMOR_KNIVES", "Kunai capacity {knives}").format({"knives": "%+d" % int(cfg.get("knives", 0))}),
				]
	else:
		status = ContentText.of("UI_ARCHIVE_LOCKED", "Locked / not yet recorded")
		lines = [ContentText.of("UI_ARCHIVE_MEET", "Meet this entry in the field to reveal its details.")]
	if not known and _tab != "enemy":
		lines.append(_unlock_display(id))
	return {"status": status, "details": MathArt.ui_wrap("\n".join(lines), 372, 13)}


func _draw_record(canvas: CanvasItem, id: String) -> void:
	var known := _known(id)
	var cfg := _cfg(id)
	var display_name := ContentText.of("UI_ARCHIVE_UNKNOWN", "Unknown record") if not known else _name_display(id)
	var names := MathArt.ui_wrap(display_name, 298, 16)
	for i in mini(2, names.size()): MathArt.ui_text(canvas, Vector2(408, 178 + i * MathArt.ui_line_height(16)), names[i], 16, MathArt.WHITE)
	if not known:
		MathArt.ui_service(canvas, Vector2(364, 198), "collector", 28)
	elif _tab == "enemy":
		MathArt.poly(canvas, MathArt.ngon(5 if cfg.get("boss", false) else (3 if id == "grunt" else 4 if id == "charger" else 6), 32, -PI * 0.5, Vector2(364, 198)), MathArt.BOSS if cfg.get("boss", false) else MathArt.ENEMY, MathArt.INK, 2)
	elif _tab == "weapon":
		MathArt.ui_gear(canvas, Vector2(364, 198), "melee", 32, MathArt.WHITE, id)
	else:
		MathArt.ui_gear(canvas, Vector2(364, 198), "shield", 32)
	var info := _record_copy(id)
	var status := str(info.status)
	var details: Array = info.details
	var states := MathArt.ui_wrap(status, 372, 13)
	for i in mini(2, states.size()): MathArt.ui_text(canvas, Vector2(328, 246 + i * MathArt.ui_line_height(13)), states[i], 13, MathArt.WHITE)
	var limit := maxi(0, details.size() - DETAIL_ROWS)
	_detail_scroll = clampi(_detail_scroll, 0, limit)
	for i in mini(DETAIL_ROWS, details.size() - _detail_scroll):
		MathArt.ui_text(canvas, Vector2(328, 286 + i * MathArt.ui_line_height(13)), str(details[_detail_scroll + i]), 13)
