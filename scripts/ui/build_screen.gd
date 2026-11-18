extends CanvasLayer
## One owner for Scroll selection and full-slot replacement/comparison input.
## The page keeps its own focus, scroll and confirmation state; Interface only
## says whether an event is a fresh press of a menu action and how to prompt it.
## Equipment prompts have one mapping, slot_key(), shared by this page, HUD and
## the Collector.
const SLOT_ACTIONS: Array[StringName] = [&"attack", &"weapon_two", &"throw", &"aegis"]
## data/gear.json stores no display names for qualities or statuses, so the
## allowed ids get explicit English here; ids are never prettified into names.
const QUALITY_EN := {"plain": "Plain", "etched": "Etched"}
const STATUS_EN := {"poison": "Poison"}
const KIND_EN := {"weapon": "WEAPON", "skill": "SKILL", "amulet": "AMULET"}
const LINE_H := 12.0 * MathArt.PHI
const DETAIL_ROWS := 8
var offer: RunLoot
var _canvas: Control
var _index := 0
var _slots: Array[int] = []
## Machine receipt (probes compare it) plus the typed fields the renderer uses;
## display never parses English prefixes out of _note.
var _note := ""
var _note_kind := ""
var _note_gold := 0
var _detail_scroll := 0
var _detail_count := 0
var _detail_rows := DETAIL_ROWS
var _locale := ""
var _prompt_cache := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 42
	visible = false
	_locale = TranslationServer.get_locale()
	add_to_group("build_screen")
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_ui)
	add_child(_canvas)
	if not Interface.presentation_changed.is_connected(_on_presentation_changed):
		Interface.presentation_changed.connect(_on_presentation_changed)


func is_open() -> bool:
	return visible


## One equipment-slot prompt mapping. Static so the Collector can call it on
## the preloaded script without an instance; it reads Interface directly and
## never touches this page's prompt cache.
static func slot_key(slot: int) -> String:
	if slot == 4:
		return ContentText.of("UI_HUD_SLOT_PASSIVE", "PASSIVE")
	if slot < 0 or slot >= SLOT_ACTIONS.size():
		return ""
	return Interface.prompt(SLOT_ACTIONS[slot])


func _prompt(action: StringName) -> String:
	var key := String(action)
	if not _prompt_cache.has(key):
		_prompt_cache[key] = Interface.prompt(action)
	return str(_prompt_cache[key])


func _prompt_pair(first: StringName, second: StringName) -> String:
	var a := _prompt(first)
	var b := _prompt(second)
	if b.is_empty() or a == b:
		return a
	return "%s / %s" % [a, b]


func _on_presentation_changed() -> void:
	# A keyboard/pad or locale switch rewrites prompts only. Focus and the
	# detail scroll position stay exactly where the player left them.
	_prompt_cache.clear()
	_locale = TranslationServer.get_locale()
	if visible:
		_canvas.queue_redraw()


func open(value: RunLoot) -> void:
	if visible or get_tree().paused or not value.available():
		return
	offer = value
	_slots.clear()
	if offer.kind == "scroll":
		_slots.assign([0, 1, 2])
	else:
		for i in RunBuild.SLOT_KINDS.size():
			if RunBuild.SLOT_KINDS[i] == Game.build.definition(offer.item)["kind"]:
				_slots.append(i)
	_index = 0
	_detail_scroll = 0
	_detail_count = 0
	_detail_rows = 3 if offer.kind == "scroll" else 2
	_clear_note()
	visible = true
	MathArt.ui_reveal(_canvas)
	Game.player.suppress_actions()
	Combat.cancel_hitstop()
	get_tree().paused = true
	_canvas.queue_redraw()


func close() -> void:
	visible = false
	offer = null
	if is_instance_valid(Game.player):
		Game.player.suppress_actions()
	get_tree().paused = false


func _process(_delta: float) -> void:
	if visible and TranslationServer.get_locale() != _locale:
		_locale = TranslationServer.get_locale()
		_canvas.queue_redraw()
	if visible and (not is_instance_valid(offer) or not offer.available()):
		close()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventAction):
		return
	# This page is the closest layer while it is open: consume the event before
	# asking Interface so a held confirm cannot reach attack/interact and a key
	# release cannot buy twice.
	get_viewport().set_input_as_handled()
	if event is InputEventKey and (not (event as InputEventKey).pressed or (event as InputEventKey).echo):
		return
	var previous := _index
	# Back is first: a detail scroll at its clamp must never swallow the exit.
	if Interface.pressed(event, &"ui_back"):
		close()
		return
	if Interface.pressed(event, &"ui_accept"):
		_commit(false)
		_canvas.queue_redraw()
		return
	if Interface.pressed(event, &"ui_secondary"):
		if is_instance_valid(offer) and offer.kind != "scroll":
			_commit(true)
		_canvas.queue_redraw()
		return
	if Interface.pressed(event, &"ui_nav_left"):
		_index = wrapi(_index - 1, 0, _slots.size())
	elif Interface.pressed(event, &"ui_nav_right"):
		_index = wrapi(_index + 1, 0, _slots.size())
	elif Interface.pressed(event, &"ui_detail_up") or Interface.pressed(event, &"ui_nav_up"):
		_detail_scroll = maxi(0, _detail_scroll - 1)
	elif Interface.pressed(event, &"ui_detail_down") or Interface.pressed(event, &"ui_nav_down"):
		_detail_scroll = mini(maxi(0, _detail_count - _detail_rows), _detail_scroll + 1)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode in [KEY_1, KEY_2, KEY_3]:
			# Numeric preview stays as an additive keyboard shortcut, never the
			# only path: left/right (pad and keyboard) selects the same slot.
			var index := int(key.physical_keycode - KEY_1)
			if index < _slots.size():
				_index = index
	if previous != _index:
		_detail_scroll = 0
		_clear_note()
		MathArt.ui_select(_canvas)
	_canvas.queue_redraw()


func _commit(recycle: bool) -> void:
	if not is_instance_valid(offer):
		return
	if recycle and offer.cost > 0:
		_set_note("recycle")
		return
	if Game.build.gold < offer.cost:
		_set_note("need", offer.cost - Game.build.gold)
		return
	var result := ""
	if offer.kind == "scroll":
		var axis: String = Game.build.attributes.keys()[_index]
		result = ContentText.of("UI_BUILD_ANNOUNCE_SCROLL", "{axis} +1 / NO HEAL").format({"axis": Hud.axis_name(axis).to_upper()})
	elif recycle:
		result = ContentText.of("UI_BUILD_ANNOUNCE_RECYCLED", "RECYCLED / +{gold} GOLD").format({"gold": Game.build.recycle_value(offer.item)})
	else:
		var slot_tag: String = _slot_tag(_slots[_index])
		result = (ContentText.of("UI_BUILD_ANNOUNCE_BOUGHT", "BOUGHT / {slot}") if offer.cost > 0 else ContentText.of("UI_BUILD_ANNOUNCE_EQUIPPED", "EQUIPPED / {slot}")).format({"slot": slot_tag})
	if offer.claim(_slots[_index], recycle):
		Game.announce(result, 2.4)
		close()
	else:
		_set_note("unavailable")


func _clear_note() -> void:
	_note = ""
	_note_kind = ""
	_note_gold = 0


## _note stays a stable machine receipt for probes; the typed kind and amount
## are what the UI renders, so display never parses English back out of it.
func _set_note(kind: String, gold := 0) -> void:
	_note_kind = kind
	_note_gold = gold
	match kind:
		"recycle":
			_note = "CANNOT RECYCLE UNSOLD SHOP STOCK / NOTHING CHANGED"
		"need":
			_note = "NEED %d MORE GOLD UP FRONT / NOT PURCHASED" % gold
		"unavailable":
			_note = "OFFER UNAVAILABLE / NOTHING CHANGED"
		_:
			_note = ""


## Localized rendering of the typed receipt.
func _note_display() -> String:
	match _note_kind:
		"recycle":
			return ContentText.of("UI_BUILD_CANNOT_RECYCLE", "CANNOT RECYCLE UNSOLD SHOP STOCK / NOTHING CHANGED")
		"need":
			return ContentText.of("UI_BUILD_NEED_GOLD", "NEED {gold} MORE GOLD UP FRONT / NOT PURCHASED").format({"gold": _note_gold})
		"unavailable":
			return ContentText.of("UI_BUILD_OFFER_UNAVAILABLE", "OFFER UNAVAILABLE / NOTHING CHANGED")
	return ""


func _kind_label(kind: String) -> String:
	return ContentText.of("UI_GEAR_KIND_%s" % kind.to_upper(), str(KIND_EN.get(kind, kind)))


func _quality_name(quality: String) -> String:
	return ContentText.name("quality", quality, str(QUALITY_EN.get(quality, quality)))


func _affix_name(item: Dictionary) -> String:
	var affix: Dictionary = Data.gear.affixes[item.affix]
	return ContentText.name("affix", str(item.affix), str(affix.get("name", item.affix)))


func _gear_name(item: Dictionary) -> String:
	var cfg := Game.build.definition(item)
	return ContentText.name("gear", str(item.id), str(cfg.name))


## Passive is a word; every gear slot asks Interface for the action it fires.
func _slot_tag(slot: int) -> String:
	return slot_key(slot)


func _axis_display(attribute: Variant) -> String:
	if attribute == null or str(attribute).is_empty():
		return ContentText.of("UI_GEAR_PASSIVE", "PASSIVE")
	return Hud.axis_name(str(attribute)).to_upper()


func _draw_ui() -> void:
	if not visible or not is_instance_valid(offer):
		return
	# One 82% mask over the world. The Scroll page adds a single panel on top;
	# the comparison page relies on its own opaque cards so the world stays
	# legible around the choice instead of behind a full sheet.
	MathArt.px_rect(_canvas, Rect2(0, 0, 768, 480), Color(MathArt.INK, 0.82))
	if offer.kind == "scroll":
		MathArt.ui_panel(_canvas, MathArt.UI_PAGE)
		_draw_scroll()
	else:
		_draw_comparison()


func _draw_scroll() -> void:
	var build := Game.build
	var preview := build.scroll_projection(str(build.attributes.keys()[_index]), Game.player.hp)
	MathArt.ui_heading(_canvas,
		ContentText.of("UI_BUILD_SCROLL_TITLE", "Choose your growth"),
		ContentText.of("UI_BUILD_SCROLL_CONTEXT", "Scroll / one point · this run"))
	# Each card answers the whole question for its axis: level, HP growth and the
	# gear it changes. The band below is detail, not the only place to read it.
	for n in 3:
		var axis: String = build.attributes.keys()[n]
		var change := build.scroll_projection(axis, Game.player.hp)
		var rect := Rect2(52 + n * 226, 110, 212, 242)
		var focused := n == _index
		MathArt.ui_surface(_canvas, rect, focused)
		var tone := MathArt.PALE if focused else MathArt.LIGHT_DIM
		MathArt.ui_text(_canvas, rect.position + Vector2(16, 25), ContentText.of("UI_BUILD_AXIS_CARD", "{index}  {axis}").format({"index": n + 1, "axis": Hud.axis_name(axis)}), 16, tone)
		MathArt.ui_axis_emblem(_canvas, rect.position + Vector2(106, 76), axis, 32, MathArt.axis_color(axis))
		MathArt.ui_text(_canvas, rect.position + Vector2(16, 130), "%d → %d" % [change.before, change.after], 24, tone)
		MathArt.ui_text(_canvas, rect.position + Vector2(16, 164), ContentText.of("UI_BUILD_MAX_HP_GAIN", "+{hp} max HP").format({"hp": "%.1f" % (change.max_after - change.max_before)}), 16, tone)
		MathArt.ui_text(_canvas, rect.position + Vector2(16, 191), "%.1f / %.1f → %.1f / %.1f" % [Game.player.hp, Game.player.max_hp, change.hp_after, change.max_after], 11, tone, 180)
		MathArt.ui_text(_canvas, rect.position + Vector2(16, 207), ContentText.of("UI_BUILD_NO_HEAL", "NO HEAL"), 11, MathArt.LIGHT_DIM)
		var affected: Array = change.affected
		if affected.is_empty():
			MathArt.ui_text(_canvas, rect.position + Vector2(16, 228), ContentText.of("UI_BUILD_NO_GEAR", "No equipped gear"), 11, MathArt.LIGHT_DIM)
		else:
			var icon_x := 30.0
			for entry: Dictionary in affected:
				var item := build.slots[entry.slot]
				var cfg := build.definition(item)
				MathArt.ui_gear(_canvas, rect.position + Vector2(icon_x, 228), str(cfg.get("action", "amulet")), 10, MathArt.axis_color(str(cfg.get("attribute", "survival"))), str(item.id))
				MathArt.ui_text(_canvas, rect.position + Vector2(icon_x + 12, 232), _slot_tag(entry.slot), 11, MathArt.LIGHT_DIM)
				icon_x += 46.0
		if focused:
			MathArt.px_rect(_canvas, Rect2(rect.position + Vector2(0, rect.size.y - 2), Vector2(rect.size.x, 2)), MathArt.ACCENT)
	var lines: Array[String] = []
	if not _note.is_empty():
		lines.append(_note_display())
	for change: Dictionary in preview.affected:
		lines.append(ContentText.of("UI_BUILD_SCROLL_AFFECTED", "[{slot}] {name} / {label} {before} → {after} ({delta})").format({"slot": _slot_tag(change.slot), "name": _gear_name(build.slots[change.slot]), "label": ContentText.stat_label(change.before.label), "before": change.before.value, "after": change.after.value, "delta": change.after.value - change.before.value}))
	if preview.affected.is_empty():
		lines.append(ContentText.of("UI_BUILD_SCROLL_NO_AXIS", "No equipped gear uses this axis. Maximum HP still increases."))
	lines.append(ContentText.of("UI_BUILD_SCROLL_NORMAL", "Normal damage · critical hits and status effects excluded"))
	var details := MathArt.ui_wrap("\n".join(lines), 664, 13)
	_detail_count = details.size()
	MathArt.ui_text(_canvas, Vector2(52, 369), ContentText.of("UI_BUILD_DETAILS_LABEL", "Details / equipped impact"), 11, MathArt.LIGHT_DIM)
	if _detail_count > _detail_rows:
		MathArt.ui_text(_canvas, Vector2(492, 369), ContentText.of("UI_BUILD_DETAILS_SCROLL", "{detail} Details {index} / {total}").format({"detail": _prompt_pair(&"ui_detail_up", &"ui_detail_down"), "index": _detail_scroll + 1, "total": _detail_count}), 11, MathArt.LIGHT_DIM, 224, HORIZONTAL_ALIGNMENT_RIGHT)
	# 13px rows on LINE_H: clear the 369 label and end above the 440 key bar.
	_draw_detail(Vector2(52, 386), details, _detail_rows)
	var x := 52.0
	var preview_keys := _prompt_pair(&"ui_nav_left", &"ui_nav_right")
	if Interface.active_device != &"gamepad":
		# Numeric direct-select is additive and keyboard-only, never the sole path.
		preview_keys = "1 2 3 / " + preview_keys
	x += MathArt.ui_key(_canvas, Vector2(x, 440), preview_keys, ContentText.of("UI_BUILD_KEY_PREVIEW", "Preview"))
	MathArt.ui_key(_canvas, Vector2(x, 440), _prompt(&"ui_accept"), ContentText.of("UI_BUILD_KEY_APPLY", "Apply point"))
	MathArt.ui_key(_canvas, Vector2(636, 440), _prompt(&"ui_back"), ContentText.of("UI_BUILD_KEY_CANCEL", "Cancel"))


func _draw_comparison() -> void:
	var build := Game.build
	var slot := _slots[_index]
	var old := build.slots[slot]
	var credit := build.recycle_value(old)
	var can_buy := build.gold >= offer.cost
	var context: String = {
		"shop": ContentText.of("UI_BUILD_CONTEXT_SHOP", "Shop / purchase"),
		"chest": ContentText.of("UI_BUILD_CONTEXT_CHEST", "Chest / choose equipment"),
	}.get(offer.kind, ContentText.of("UI_BUILD_CONTEXT_GROUND", "Ground / equipment found"))
	MathArt.ui_heading(_canvas,
		ContentText.of("UI_BUILD_COMPARE_TITLE", "Choose what to replace"),
		context,
		ContentText.of("UI_BUILD_WALLET_GOLD", "{gold} Gold").format({"gold": build.gold}))
	_detail_count = _gear_lines(offer.item, 392).size()
	for target in _slots:
		_detail_count = maxi(_detail_count, _gear_lines(build.slots[target], 298).size())
	# The candidate owns the full width; price and balance live inside it so the
	# purchase reads as one object instead of a separate form beside it.
	_gear_card(Rect2(52, 110, 664, 154), offer.item, ContentText.of("UI_BUILD_CANDIDATE", "FOUND / CANDIDATE"), false, true)
	for n in _slots.size():
		var target := _slots[n]
		var width := 326.0 if _slots.size() > 1 else 664.0
		_gear_card(Rect2(52 + n * 338, 278, width, 122), build.slots[target], ContentText.of("UI_BUILD_REPLACE_SLOT", "Replace [{slot}] / +{gold} Gold recycled").format({"slot": _slot_tag(target), "gold": build.recycle_value(build.slots[target])}), n == _index)
	var target_x := 215.0 + _index * 338.0 if _slots.size() > 1 else 384.0
	MathArt.line(_canvas, Vector2(384, 264), Vector2(384, 270), MathArt.PALE, 1.5)
	MathArt.line(_canvas, Vector2(384, 270), Vector2(target_x, 270), MathArt.PALE, 1.5)
	MathArt.line(_canvas, Vector2(target_x, 270), Vector2(target_x, 274), MathArt.PALE, 1.5)
	MathArt.poly(_canvas, MathArt.ngon(3, 4, PI * 0.5, Vector2(target_x, 274)), MathArt.WHITE)
	MathArt.ui_text(_canvas, Vector2(492, 127), ContentText.of("UI_BUILD_PURCHASE", "Purchase") if offer.cost > 0 else ContentText.of("UI_BUILD_FREE", "Free equipment"), 13, MathArt.WHITE)
	MathArt.ui_text(_canvas, Vector2(492, 152), ContentText.of("UI_BUILD_PRICE", "{gold} Gold now").format({"gold": offer.cost}), 24, MathArt.GOLD)
	var balance := ContentText.of("UI_BUILD_BALANCE_AFTER", "After [{slot}]: {gold} Gold").format({"slot": _slot_tag(slot), "gold": build.gold - offer.cost + credit}) if can_buy else ContentText.of("UI_BUILD_NEED_UPFRONT", "Need {gold} Gold up front").format({"gold": offer.cost - build.gold})
	var balance_lines := MathArt.ui_wrap(balance, 224, 13)
	for i in balance_lines.size():
		MathArt.ui_text(_canvas, Vector2(492, 178 + i * MathArt.ui_line_height(13)), balance_lines[i], 13, MathArt.PALE if can_buy else MathArt.DANGER)
	var message := _note_display()
	if message.is_empty():
		message = ContentText.of("UI_BUILD_RECYCLE_AFTER", "Old equipment is recycled after full payment.") if offer.cost > 0 else ContentText.of("UI_BUILD_REPLACES_SELECTED", "Replaces and recycles the selected equipment.")
	var notes := MathArt.ui_wrap(message, 224, 11)
	for i in mini(notes.size(), 3):
		MathArt.ui_text(_canvas, Vector2(492, 216 + i * MathArt.ui_line_height(11)), notes[i], 11, MathArt.DANGER if not _note.is_empty() else MathArt.LIGHT_DIM)
	var extra := ContentText.of("UI_BUILD_DETAILS_RANGE", "{detail} Details {from}–{to} / {total}").format({"detail": _prompt_pair(&"ui_detail_up", &"ui_detail_down"), "from": _detail_scroll + 1, "to": mini(_detail_scroll + _detail_rows, _detail_count), "total": _detail_count}) if _detail_count > _detail_rows else ContentText.of("UI_BUILD_DETAILS_ALL", "All details shown")
	# Between the candidate card (ends 264) and the target cards (start 278).
	MathArt.ui_text(_canvas, Vector2(52, 274), extra, 11, MathArt.LIGHT_DIM)
	var a := build.display_stats(old)
	var b := build.display_stats(offer.item)
	var delta := ContentText.of("UI_BUILD_DELTA", "{label}: {before} → {after} ({change})").format({"label": ContentText.stat_label(a.label), "before": "%d" % int(a.value), "after": "%d" % int(b.value), "change": "%+d" % (int(b.value) - int(a.value))}) if a.label == b.label else ContentText.of("UI_BUILD_DIFFERENT", "{left} {a} / {right} {b} · Different actions").format({"left": ContentText.stat_label(a.label), "a": "%d" % int(a.value), "right": ContentText.stat_label(b.label), "b": "%d" % int(b.value)})
	if build.definition(old).kind == "amulet":
		var next := build.replacement_projection(slot, offer.item, Game.player.hp)
		delta = ContentText.of("UI_BUILD_AMULET_HP", "HP {hp} / {max} → {next_hp} / {next_max} · No healing").format({"hp": "%.1f" % Game.player.hp, "max": "%.1f" % Game.player.max_hp, "next_hp": "%.1f" % next.hp_after, "next_max": "%.1f" % next.max_after})
	MathArt.ui_text(_canvas, Vector2(52, 412), delta, 13, MathArt.WHITE)
	if build.definition(old).kind != "amulet":
		MathArt.ui_text(_canvas, Vector2(542, 412), ContentText.of("UI_BUILD_NORMAL", "Normal · no crit/status"), 11)
	var x := 52.0
	if _slots.size() > 1:
		x += MathArt.ui_key(_canvas, Vector2(x, 428), _prompt_pair(&"ui_nav_left", &"ui_nav_right"), ContentText.of("UI_BUILD_KEY_TARGET", "Target"))
	x += MathArt.ui_key(_canvas, Vector2(x, 428), _prompt(&"ui_accept"), ContentText.of("UI_BUILD_KEY_BUY", "Buy + replace") if offer.cost > 0 else ContentText.of("UI_BUILD_KEY_REPLACE", "Replace"), MathArt.PALE if can_buy else MathArt.LIGHT_DIM)
	if offer.cost == 0:
		x += MathArt.ui_key(_canvas, Vector2(x, 428), _prompt(&"ui_secondary"), ContentText.of("UI_BUILD_KEY_RECYCLE", "Recycle new +{gold}G").format({"gold": build.recycle_value(offer.item)}))
	MathArt.ui_key(_canvas, Vector2(636, 428), _prompt(&"ui_back"), ContentText.of("UI_BUILD_KEY_BACK", "Back"))


func _gear_lines(item: Dictionary, width: float) -> Array[String]:
	var lines := item_details(item).split("\n")
	# Name, identity and headline stat have dedicated fixed positions.
	lines.remove_at(0)
	lines.remove_at(0)
	lines.remove_at(0)
	lines.remove_at(0)
	var cfg := Game.build.definition(item)
	var text := _affix_name(item) + "\n" + "\n".join(lines)
	if MathArt.ui_wrap(_gear_name(item), 264, 16).size() > 2:
		text = ContentText.of("UI_BUILD_FULL_NAME", "Full name: {name}").format({"name": _gear_name(item)}) + "\n" + text
	return MathArt.ui_wrap(text, width, 11)


func _gear_card(rect: Rect2, item: Dictionary, label: String, selected: bool, candidate := false) -> void:
	var build := Game.build
	var cfg := build.definition(item)
	var stats := build.display_stats(item)
	# Opaque cards: on the comparison page these are the surfaces, not a panel.
	MathArt.ui_surface(_canvas, rect, selected or candidate, true)
	# One narrow axis-coloured top edge is enough to identify the item's school.
	MathArt.px_rect(_canvas, Rect2(rect.position, Vector2(rect.size.x, 2)), Color(MathArt.axis_color(str(cfg.get("attribute", "survival"))), 0.85))
	var inset := 100.0 if candidate else 48.0
	var tone := MathArt.PALE if candidate or selected else MathArt.LIGHT_DIM
	MathArt.ui_gear(_canvas, rect.position + Vector2(48 if candidate else 24, 65 if candidate else 40), str(cfg.get("action", "amulet")), 36 if candidate else 16, MathArt.axis_color(str(cfg.get("attribute", "survival"))), str(item.id))
	MathArt.ui_text(_canvas, rect.position + Vector2(inset, 16), label, 11, MathArt.PALE)
	var name_width := minf(rect.size.x - inset - 14, 264.0) if candidate else rect.size.x - inset - 14
	var gear_name := _gear_name(item)
	var names := MathArt.ui_wrap(gear_name, name_width, 16)
	for i in mini(2, names.size()):
		var value := MathArt.ui_short(names[i] + ("…" if i == 1 and names.size() > 2 else ""), name_width, 16)
		MathArt.ui_text(_canvas, rect.position + Vector2(inset, 36 + i * MathArt.ui_line_height(16)), value, 16, tone)
	var stat_y := 84.0 if candidate else 74.0
	var stat_text := ContentText.of("UI_STAT_READOUT", "{label} {value}").format({"label": ContentText.of("UI_STAT_MAX_HP", "Max HP"), "value": "+%d" % int(stats.value)}) if cfg.kind == "amulet" else ContentText.of("UI_STAT_READOUT", "{label} {value}").format({"label": ContentText.stat_label(stats.label), "value": int(stats.value)})
	MathArt.ui_text(_canvas, rect.position + Vector2(inset if candidate else 14, stat_y), stat_text, 16 if candidate else 13, tone)
	var quality_y := 105.0 if candidate else 90.0
	MathArt.ui_quality(_canvas, rect.position + Vector2(inset if candidate else 14, quality_y), str(item.quality))
	var identity := ContentText.of("UI_BUILD_IDENTITY_LEVEL", "{quality} · {axis} {level}").format({"quality": _quality_name(str(item.quality)), "axis": _axis_display(cfg.get("attribute")), "level": build.level(item)}) if cfg.has("attribute") else ContentText.of("UI_BUILD_IDENTITY", "{quality} · {axis}").format({"quality": _quality_name(str(item.quality)), "axis": _axis_display(cfg.get("attribute"))})
	MathArt.ui_text(_canvas, rect.position + Vector2(inset + 20 if candidate else 34, quality_y), identity, 11, tone)
	var lines := _gear_lines(item, 392 if candidate else 298)
	for i in range(_detail_scroll, mini(lines.size(), _detail_scroll + _detail_rows)):
		MathArt.ui_text(_canvas, rect.position + Vector2(14, (124 if candidate else 104) + (i - _detail_scroll) * MathArt.ui_line_height(11)), lines[i], 11, tone)


func item_details(item: Dictionary) -> String:
	var build := Game.build
	var cfg := build.definition(item)
	var stats := build.display_stats(item)
	var kind := _kind_label(str(cfg.kind))
	var identity := ContentText.of("UI_GEAR_IDENTITY", "{kind} / {axis} {level}").format({"kind": kind, "axis": _axis_display(cfg.get("attribute")), "level": build.level(item)}) if cfg.has("attribute") else ContentText.of("UI_GEAR_IDENTITY_PASSIVE", "{kind} / {passive}").format({"kind": kind, "passive": ContentText.of("UI_GEAR_PASSIVE", "PASSIVE")})
	var lines: Array[String] = [_gear_name(item), identity, ContentText.of("UI_BUILD_QUALITY_AFFIX", "{quality} / {affix}").format({"quality": _quality_name(str(item.quality)), "affix": _affix_name(item)})]
	if cfg.kind == "amulet":
		lines.append(ContentText.of("UI_BUILD_MAX_HP_BONUS", "MAX HP BONUS +{hp}").format({"hp": "%.1f" % stats.value}))
	else:
		lines.append(ContentText.of("UI_BUILD_DAMAGE_LINE", "{label} {value} / NORMAL DAMAGE").format({"label": ContentText.stat_label(stats.label), "value": "%d" % int(stats.value)}))
		lines.append(ContentText.of("UI_BUILD_CHARGES_LINE", "CHARGES {charges}/{capacity} / {state}").format({"charges": item.charges, "capacity": stats.capacity, "state": ContentText.of("UI_HUD_READY", "READY") if int(item.charges) > 0 else ContentText.of("UI_HUD_EMPTY", "EMPTY")}))
		lines.append(ContentText.of("UI_BUILD_RECHARGE_LINE", "RECHARGE {cooldown}s / NEXT {next}s").format({"cooldown": "%.2f" % stats.cooldown, "next": "%.2f" % float(item.cooldown)}) if stats.cooldown > 0 else ContentText.of("UI_BUILD_NO_RECHARGE", "NO RECHARGE TIMER"))
	var affix: Dictionary = Data.gear.affixes[item.affix]
	if affix.has("status"):
		lines.append(ContentText.of("UI_BUILD_STATUS_LINE", "{status} ON HIT / SEPARATE DAMAGE").format({"status": ContentText.name("status", str(affix.status), str(STATUS_EN.get(str(affix.status), affix.status)))}))
	if affix.has("power"):
		lines.append(ContentText.of("UI_BUILD_AFFIX_POWER", "AFFIX: +{percent}% BASE POWER (INCLUDED)").format({"percent": roundi(float(affix.power) * 100)}))
	if affix.has("cooldown"):
		lines.append(ContentText.of("UI_BUILD_AFFIX_COOLDOWN", "AFFIX: RECHARGE x{mult} (INCLUDED)").format({"mult": "%.2f" % float(affix.cooldown)}))
	return "\n".join(lines)


static func wrap_text(value: String, width: float, size: int) -> Array[String]:
	return MathArt.ui_wrap(value, width, size)


func _draw_detail(at: Vector2, lines: Array[String], rows := DETAIL_ROWS) -> void:
	for n in range(_detail_scroll, mini(lines.size(), _detail_scroll + rows)):
		_line(at + Vector2(0, (n - _detail_scroll) * LINE_H), lines[n], 13)


func _line(at: Vector2, value: String, size: int) -> void:
	_canvas.draw_string(MathArt.ui_font(), at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, MathArt.PALE)
