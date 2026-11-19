extends CanvasLayer
## One owner for Scroll selection and full-slot replacement/comparison input.
## The page keeps its own focus, scroll and confirmation state; Interface only
## says whether an event is a fresh press of a menu action and how to prompt it.
## Equipment prompts have one mapping, slot_key(), shared by this page, HUD and
## the Collector.
const SLOT_ACTIONS: Array[StringName] = [&"attack", &"weapon_two", &"throw", &"aegis"]
## data/gear.json stores no display names for kinds, so the allowed ids get
## explicit English here; ids are never prettified into names.
const KIND_EN := {"weapon": "WEAPON", "skill": "SKILL", "amulet": "AMULET"}
## Geometry is fixed logical screen space. The plan's y282 detail-count slot is
## moved to y287 because a real 11 px baseline (ascent ~12.8 px) would overlap
## the candidate card's bottom edge at y274; the plan's y416/y432 rows and y452
## key band stay, measured with MathArt.ui_line_height(11) = 16 px.
const CANDIDATE_RECT := Rect2(52, 110, 664, 164)
const TARGET_Y := 294.0
const TARGET_H := 104.0
const TARGET_GAP := 338.0
const DETAIL_Y := 416.0
const DETAIL_WIDTH := 664.0
const COMPARE_DETAIL_ROWS := 2
const SCROLL_DETAIL_Y := 386.0
const SCROLL_DETAIL_ROWS := 3
const COMPARE_KEY_Y := 452.0
const SCROLL_KEY_Y := 440.0
const DETAIL_SIZE := 11
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
var _detail_rows := COMPARE_DETAIL_ROWS
## Wrapped shared details for the candidate plus the selected target (compare)
## or the focused axis (Scroll). Rebuilt at state/locale changes, not per frame.
var _detail_lines: Array[String] = []
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
	# A keyboard/pad switch rewrites prompts only. A locale switch also wraps
	# the same details in the new language. Focus and the scroll position stay
	# exactly where the player left them.
	_prompt_cache.clear()
	_locale = TranslationServer.get_locale()
	_refresh_details()
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
		var kind := str(Game.build.definition(offer.item).get("kind", ""))
		for i in RunBuild.SLOT_KINDS.size():
			if RunBuild.SLOT_KINDS[i] == kind:
				_slots.append(i)
	if _slots.is_empty():
		offer = null
		return
	_index = 0
	_detail_scroll = 0
	_detail_count = 0
	_detail_rows = SCROLL_DETAIL_ROWS if offer.kind == "scroll" else COMPARE_DETAIL_ROWS
	_clear_note()
	_refresh_details()
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
		_refresh_details()
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
		_refresh_details()
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
		result = ContentText.of("UI_BUILD_ANNOUNCE_RECYCLED", "RECYCLED / +{gold} GOLD").format({"gold": _recycle_credit(offer.item)})
	else:
		var slot_name := _slot_name(_slots[_index])
		result = (ContentText.of("UI_BUILD_ANNOUNCE_BOUGHT", "BOUGHT / {slot}") if offer.cost > 0 else ContentText.of("UI_BUILD_ANNOUNCE_EQUIPPED", "EQUIPPED / {slot}")).format({"slot": slot_name})
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
	_refresh_details()


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


## Which equipment slot is being replaced, named as the player sees it. This is
## deliberately not slot_key(): that static mapping is the action prompt for the
## HUD/Collector, not a slot noun.
func _slot_name(slot: int) -> String:
	if slot < 0 or slot >= RunBuild.SLOT_KINDS.size():
		return ""
	var kind := _kind_label(str(RunBuild.SLOT_KINDS[slot]))
	if slot == 4:
		return kind
	return "%s %d" % [kind, slot % 2 + 1]


## Canonical recycle value guarded at the presentation edge. RunBuild.price()
## indexes definition["price"], so an empty/missing-definition slot must not be
## passed through it just to render a card.
func _recycle_credit(item: Dictionary) -> int:
	if item.is_empty() or Game.build.definition(item).is_empty():
		return 0
	return Game.build.recycle_value(item)


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
	MathArt.ui_heading(_canvas,
		ContentText.of("UI_BUILD_SCROLL_TITLE", "Choose your growth"),
		ContentText.of("UI_BUILD_SCROLL_CONTEXT", "Scroll / one point · this run"))
	# Each card answers the whole question for its axis: which equipped gear
	# changes, the real level/damage projection, and the max-HP consequence. The
	# band below is detail, not the only place to read it.
	for n in 3:
		var axis: String = build.attributes.keys()[n]
		var change := build.scroll_projection(axis, Game.player.hp)
		_draw_scroll_card(Rect2(52 + n * 226, 110, 212, 242), axis, n, change, n == _index)
	MathArt.ui_text(_canvas, Vector2(52, 369), ContentText.of("UI_BUILD_DETAILS_LABEL", "Details / equipped impact"), 11, MathArt.LIGHT_DIM)
	MathArt.ui_text(_canvas, Vector2(492, 369), _detail_range_text(), 11, MathArt.LIGHT_DIM, 224, HORIZONTAL_ALIGNMENT_RIGHT)
	_draw_detail(Vector2(52, SCROLL_DETAIL_Y), _detail_rows)
	var x := 52.0
	var preview_keys := _prompt_pair(&"ui_nav_left", &"ui_nav_right")
	if Interface.active_device != &"gamepad":
		# Numeric direct-select is additive and keyboard-only, never the sole path.
		preview_keys = "1 2 3 / " + preview_keys
	x += MathArt.ui_key(_canvas, Vector2(x, SCROLL_KEY_Y), preview_keys, ContentText.of("UI_BUILD_KEY_PREVIEW", "Preview"))
	MathArt.ui_key(_canvas, Vector2(x, SCROLL_KEY_Y), _prompt(&"ui_accept"), ContentText.of("UI_BUILD_KEY_APPLY", "Apply point"))
	MathArt.ui_key(_canvas, Vector2(636, SCROLL_KEY_Y), _prompt(&"ui_back"), ContentText.of("UI_BUILD_KEY_CANCEL", "Cancel"))


func _draw_scroll_card(rect: Rect2, axis: String, n: int, change: Dictionary, focused: bool) -> void:
	var build := Game.build
	MathArt.ui_surface(_canvas, rect, focused, true)
	# Background watermark only: a second in-card brand emblem would spend the
	# vertical space the affected-gear and HP facts need.
	MathArt.ui_axis_emblem(_canvas, rect.position + Vector2(106, 128), axis, 76.0, Color(MathArt.axis_color(axis), 0.10))
	var tone := MathArt.PALE if focused else MathArt.LIGHT_DIM
	MathArt.ui_text(_canvas, rect.position + Vector2(16, 25), ContentText.of("UI_BUILD_AXIS_CARD", "{index}  {axis}").format({"index": n + 1, "axis": Hud.axis_name(axis)}), 16, tone)
	var affected: Array = change.get("affected", [])
	var icon_x := 34.0
	for entry: Dictionary in affected:
		var item: Dictionary = build.slots[int(entry.slot)]
		var cfg := build.definition(item)
		MathArt.ui_gear(_canvas, rect.position + Vector2(icon_x, 60), str(cfg.get("action", "amulet")), 11, MathArt.axis_color(str(cfg.get("attribute", "survival"))), str(item.id))
		icon_x += 36.0
	var names: Array[String] = []
	for entry: Dictionary in affected:
		names.append(_gear_display_name(build.slots[int(entry.slot)]))
	var names_text := ContentText.of("UI_BUILD_SCROLL_NO_AXIS", "No equipped gear uses this axis. Maximum HP still increases.") if names.is_empty() else ", ".join(names)
	var name_lines := MathArt.ui_wrap(names_text, 180.0, 11)
	for i in mini(3, name_lines.size()):
		var value := name_lines[i]
		if i == 2 and name_lines.size() > 3:
			value = MathArt.ui_short(value + "…", 180.0, 11)
		MathArt.ui_text(_canvas, rect.position + Vector2(16, 88 + i * MathArt.ui_line_height(11)), value, 11, tone, 180)
	MathArt.ui_text(_canvas, rect.position + Vector2(16, 136), ContentText.of("UI_S5_SCROLL_LEVEL", "Level {from} → {to}").format({"from": int(change.get("before", 0)), "to": int(change.get("after", 0))}), 11, tone)
	MathArt.ui_text(_canvas, rect.position + Vector2(16, 152), MathArt.ui_short(_scroll_damage_text(change), 180.0, 11), 11, tone, 180)
	MathArt.ui_text(_canvas, rect.position + Vector2(16, 174), ContentText.of("UI_BUILD_MAX_HP_GAIN", "+{hp} max HP").format({"hp": "%.1f" % (float(change.get("max_after", 0.0)) - float(change.get("max_before", 0.0)))}), 13, tone)
	var hp_fact := ContentText.of("UI_S5_SCROLL_HP_FACT", "Max HP increases; current HP is not restored.")
	var facts := MathArt.ui_wrap(hp_fact, 180.0, 11)
	for i in mini(2, facts.size()):
		var value := facts[i]
		if i == 1 and facts.size() > 2:
			value = MathArt.ui_short(value + "…", 180.0, 11)
		MathArt.ui_text(_canvas, rect.position + Vector2(16, 196 + i * MathArt.ui_line_height(11)), value, 11, MathArt.LIGHT_DIM, 180)
	MathArt.ui_text(_canvas, rect.position + Vector2(16, 232), ContentText.of("UI_BUILD_NO_HEAL", "NO HEAL"), 11, MathArt.LIGHT_DIM)
	if focused:
		MathArt.px_rect(_canvas, Rect2(rect.position + Vector2(0, rect.size.y - 2), Vector2(rect.size.x, 2)), MathArt.ACCENT)


## One honest damage row on a Scroll card. Amulet-only axes say what actually
## changes instead of pretending max HP is attack damage.
func _scroll_damage_text(change: Dictionary) -> String:
	var affected: Array = change.get("affected", [])
	for entry: Dictionary in affected:
		var before: Dictionary = entry.get("before", {})
		var after: Dictionary = entry.get("after", {})
		if str(before.get("label", "")) == "MAX HP":
			continue
		return ContentText.of("UI_S5_SCROLL_DAMAGE", "{label} {before} → {after} ({change})").format({
			"label": ContentText.stat_label(str(before.get("label", ""))),
			"before": "%d" % int(before.get("value", 0)),
			"after": "%d" % int(after.get("value", 0)),
			"change": "%+d" % (int(after.get("value", 0)) - int(before.get("value", 0))),
		})
	return ContentText.of("UI_S5_SCROLL_NO_DAMAGE", "No attack damage on this axis; maximum HP still increases.")


func _draw_comparison() -> void:
	var build := Game.build
	var can_buy := build.gold >= offer.cost
	var context: String = {
		"shop": ContentText.of("UI_BUILD_CONTEXT_SHOP", "Shop / purchase"),
		"chest": ContentText.of("UI_BUILD_CONTEXT_CHEST", "Chest / choose equipment"),
	}.get(offer.kind, ContentText.of("UI_BUILD_CONTEXT_GROUND", "Ground / equipment found"))
	MathArt.ui_heading(_canvas,
		ContentText.of("UI_BUILD_COMPARE_TITLE", "Choose what to replace"),
		context,
		ContentText.of("UI_BUILD_WALLET_GOLD", "{gold} Gold").format({"gold": build.gold}))
	_candidate_card(build, can_buy)
	for n in _slots.size():
		var target := _slots[n]
		var width := 326.0 if _slots.size() > 1 else 664.0
		_target_card(Rect2(52 + n * TARGET_GAP, TARGET_Y, width, TARGET_H), target, build.slots[target], n == _index)
	# Between the candidate card (ends 274) and the target cards (start 294).
	MathArt.ui_text(_canvas, Vector2(52, 287), _detail_range_text(), 11, MathArt.LIGHT_DIM)
	_draw_detail(Vector2(52, DETAIL_Y), _detail_rows)
	var x := 52.0
	if _slots.size() > 1:
		x += MathArt.ui_key(_canvas, Vector2(x, COMPARE_KEY_Y), _prompt_pair(&"ui_nav_left", &"ui_nav_right"), ContentText.of("UI_BUILD_KEY_TARGET", "Target"))
	x += MathArt.ui_key(_canvas, Vector2(x, COMPARE_KEY_Y), _prompt(&"ui_accept"), ContentText.of("UI_BUILD_KEY_BUY", "Buy + replace") if offer.cost > 0 else ContentText.of("UI_BUILD_KEY_REPLACE", "Replace"), MathArt.PALE if can_buy else MathArt.LIGHT_DIM)
	if offer.cost == 0:
		x += MathArt.ui_key(_canvas, Vector2(x, COMPARE_KEY_Y), _prompt(&"ui_secondary"), ContentText.of("UI_BUILD_KEY_RECYCLE", "Recycle new +{gold}G").format({"gold": _recycle_credit(offer.item)}))
	MathArt.ui_key(_canvas, Vector2(636, COMPARE_KEY_Y), _prompt(&"ui_back"), ContentText.of("UI_BUILD_KEY_BACK", "Back"))


## Candidate owns the full width and the transaction column. It states what the
## object does before what it costs; full mechanics stay in the shared details.
func _candidate_card(build: RunBuild, can_buy: bool) -> void:
	var cfg := build.definition(offer.item)
	var info := GearPresentation.describe(build, offer.item)
	var axis := str(cfg.get("attribute", "survival"))
	MathArt.ui_surface(_canvas, CANDIDATE_RECT, true, true)
	MathArt.px_rect(_canvas, Rect2(CANDIDATE_RECT.position, Vector2(CANDIDATE_RECT.size.x, 2)), Color(MathArt.axis_color(axis), 0.85))
	MathArt.ui_text(_canvas, CANDIDATE_RECT.position + Vector2(16, 17), ContentText.of("UI_BUILD_CANDIDATE", "FOUND / CANDIDATE"), 11, MathArt.PALE)
	MathArt.ui_gear(_canvas, CANDIDATE_RECT.position + Vector2(36, 62), str(cfg.get("action", "amulet")), 32, MathArt.axis_color(axis), str(offer.item.id))
	var name_width := 356.0
	var names := MathArt.ui_wrap(str(info.name), name_width, 16)
	for i in mini(2, names.size()):
		var value := names[i]
		if i == 1 and names.size() > 2:
			value = MathArt.ui_short(value + "…", name_width, 16)
		MathArt.ui_text(_canvas, CANDIDATE_RECT.position + Vector2(80, 36 + i * 24), value, 16, MathArt.PALE)
	var plays := MathArt.ui_wrap(str(info.playstyle), name_width, 13)
	for i in mini(2, plays.size()):
		var value := plays[i]
		if i == 1 and plays.size() > 2:
			value = MathArt.ui_short(value + "…", name_width, 13)
		MathArt.ui_text(_canvas, CANDIDATE_RECT.position + Vector2(80, 81 + i * 19), value, 13, MathArt.PALE)
	var conditions := MathArt.ui_wrap(str(info.condition), name_width, 11)
	for i in mini(2, conditions.size()):
		var value := conditions[i]
		if i == 1 and conditions.size() > 2:
			value = MathArt.ui_short(value + "…", name_width, 11)
		MathArt.ui_text(_canvas, CANDIDATE_RECT.position + Vector2(80, 117 + i * 16), value, 11, MathArt.LIGHT_DIM)
	MathArt.ui_text(_canvas, CANDIDATE_RECT.position + Vector2(80, 152), MathArt.ui_short(str(info.headline), name_width, 13), 13, MathArt.WHITE)
	# Right column: one price, the selected slot's real recycle credit, the
	# post-purchase balance, and the shortfall. The credit never discounts the price.
	var right := Vector2(452, 0)
	var slot := _slots[_index]
	var target_item: Dictionary = build.slots[slot]
	var credit := _recycle_credit(target_item)
	MathArt.ui_text(_canvas, CANDIDATE_RECT.position + right + Vector2(0, 17), ContentText.of("UI_BUILD_PURCHASE", "Purchase") if offer.cost > 0 else ContentText.of("UI_BUILD_FREE", "Free equipment"), 11, MathArt.WHITE)
	var price_text := ContentText.of("UI_BUILD_PRICE", "{gold} Gold now").format({"gold": offer.cost})
	# The price is essential: step the hierarchy down from the planned 24 px
	# until the full localized amount fits the 196 px column; never ellipsize it.
	var price_size := 24
	if MathArt.ui_wrap(price_text, 196.0, price_size).size() > 1:
		price_size = 16
	if MathArt.ui_wrap(price_text, 196.0, price_size).size() > 1:
		price_size = 13
	if MathArt.ui_wrap(price_text, 196.0, price_size).size() > 1:
		price_size = 11
	var price_lines := MathArt.ui_wrap(price_text, 196.0, price_size)
	var price_pitch := MathArt.ui_line_height(price_size)
	for i in price_lines.size():
		MathArt.ui_text(_canvas, CANDIDATE_RECT.position + right + Vector2(0, 57 + i * price_pitch), price_lines[i], price_size, MathArt.GOLD)
	var recycle_y := maxf(80.0, 57.0 + (price_lines.size() - 1) * price_pitch + 12.0)
	MathArt.ui_text(_canvas, CANDIDATE_RECT.position + right + Vector2(0, recycle_y), ContentText.of("UI_S5_RECYCLE_CREDIT", "Recycle credit +{gold} Gold").format({"gold": credit}), 11, MathArt.PALE)
	var balance_y := recycle_y + 22.0
	var balance := ContentText.of("UI_BUILD_BALANCE_AFTER", "After [{slot}]: {gold} Gold").format({"slot": _slot_name(slot), "gold": build.gold - offer.cost + credit}) if can_buy else ContentText.of("UI_BUILD_NEED_UPFRONT", "Need {gold} Gold up front").format({"gold": offer.cost - build.gold})
	var balance_lines := MathArt.ui_wrap(balance, 196.0, 13)
	for i in mini(2, balance_lines.size()):
		MathArt.ui_text(_canvas, CANDIDATE_RECT.position + right + Vector2(0, balance_y + i * 19), balance_lines[i], 13, MathArt.PALE if can_buy else MathArt.DANGER)
	var message := _note_display()
	if message.is_empty():
		if not can_buy:
			message = ContentText.of("UI_S5_PAY_ORDER", "Pay full price first; the old item is recycled after.")
		else:
			message = ContentText.of("UI_BUILD_RECYCLE_AFTER", "Old equipment is recycled after full payment.") if offer.cost > 0 else ContentText.of("UI_BUILD_REPLACES_SELECTED", "Replaces and recycles the selected equipment.")
	var notes_y := balance_y + 39.0
	var notes := MathArt.ui_wrap(message, 196.0, 11)
	var note_rows := 2 if notes_y + MathArt.ui_line_height(11) + 3.17 <= CANDIDATE_RECT.size.y else 1
	for i in mini(note_rows, notes.size()):
		MathArt.ui_text(_canvas, CANDIDATE_RECT.position + right + Vector2(0, notes_y + i * 16), notes[i], 11, MathArt.DANGER if not _note.is_empty() else MathArt.LIGHT_DIM)


## Target keeps only what the decision needs: slot, name, same-kind headline
## delta, short playstyle, and the item's real charge state. Full detail is shared.
func _target_card(rect: Rect2, slot: int, item: Dictionary, selected: bool) -> void:
	var build := Game.build
	var cfg := build.definition(item)
	var info := GearPresentation.describe(build, item)
	var tone := MathArt.PALE if selected else MathArt.LIGHT_DIM
	var width := rect.size.x - 28.0
	MathArt.ui_surface(_canvas, rect, selected, true)
	MathArt.px_rect(_canvas, Rect2(rect.position, Vector2(rect.size.x, 2)), Color(MathArt.axis_color(str(cfg.get("attribute", "survival"))), 0.85))
	if cfg.is_empty():
		MathArt.ui_text(_canvas, rect.position + Vector2(14, 20), ContentText.of("UI_S5_EMPTY_SLOT", "Nothing equipped"), 13, MathArt.LIGHT_DIM)
		return
	MathArt.ui_text(_canvas, rect.position + Vector2(14, 14), ContentText.of("UI_BUILD_REPLACE_SLOT", "Replace [{slot}] / +{gold} Gold recycled").format({"slot": _slot_name(slot), "gold": _recycle_credit(item)}), 11, tone)
	MathArt.ui_text(_canvas, rect.position + Vector2(14, 38), MathArt.ui_short(str(info.name), width, 16), 16, tone)
	var headline := _target_headline(slot, item)
	var headline_size := 13
	if str(cfg.get("kind", "")) == "amulet" or MathArt.ui_wrap(headline, width, 13).size() > 1:
		headline_size = 11
	MathArt.ui_text(_canvas, rect.position + Vector2(14, 59), MathArt.ui_short(headline, width, headline_size), headline_size, MathArt.WHITE)
	MathArt.ui_text(_canvas, rect.position + Vector2(14, 77), MathArt.ui_short(str(info.playstyle), width, 11), 11, tone)
	MathArt.ui_text(_canvas, rect.position + Vector2(14, 94), MathArt.ui_short(_target_charge(item, cfg), width, 11), 11, tone)


## Same-label values compare honestly against the candidate. Different actions
## show the target's own canonical headline and say so, with no fake delta.
func _target_headline(slot: int, item: Dictionary) -> String:
	var build := Game.build
	var old_cfg := build.definition(item)
	var new_cfg := build.definition(offer.item)
	var old_stats := build.display_stats(item)
	if str(old_cfg.get("kind", "")) == "amulet" and str(new_cfg.get("kind", "")) == "amulet":
		var next := build.replacement_projection(slot, offer.item, Game.player.hp)
		return ContentText.of("UI_BUILD_AMULET_HP", "HP {hp} / {max} → {next_hp} / {next_max} · No healing").format({
			"hp": "%.1f" % Game.player.hp,
			"max": "%.1f" % Game.player.max_hp,
			"next_hp": "%.1f" % next.hp_after,
			"next_max": "%.1f" % next.max_after,
		})
	var new_stats := build.display_stats(offer.item)
	var old_action := str(old_cfg.get("action", ""))
	var new_action := str(new_cfg.get("action", ""))
	# Same display label is not the same action: shield/aegis both counter.
	# Compare canonical action identity first, then the label, before a delta.
	if not old_action.is_empty() and old_action == new_action and str(old_stats.label) == str(new_stats.label):
		return ContentText.of("UI_BUILD_DELTA", "{label}: {before} → {after} ({change})").format({
			"label": ContentText.stat_label(str(old_stats.label)),
			"before": "%d" % int(old_stats.value),
			"after": "%d" % int(new_stats.value),
			"change": "%+d" % (int(new_stats.value) - int(old_stats.value)),
		})
	if old_action != new_action:
		return ContentText.of("UI_BUILD_DIFFERENT", "{left} {a} / {right} {b} · Different actions").format({
			"left": ContentText.stat_label(str(old_stats.label)),
			"a": "%d" % int(old_stats.value),
			"right": ContentText.stat_label(str(new_stats.label)),
			"b": "%d" % int(new_stats.value),
		})
	return ContentText.of("UI_S5_NO_COMPARE", "{label} {value} · No direct comparison").format({
		"label": ContentText.stat_label(str(old_stats.label)),
		"value": "%d" % int(old_stats.value),
	})


## Real charge state, not a readiness label on a bar the item does not have.
func _target_charge(item: Dictionary, cfg: Dictionary) -> String:
	var stats := Game.build.display_stats(item)
	if str(cfg.get("kind", "")) == "amulet":
		return ContentText.of("UI_BUILD_NO_HEAL", "NO HEAL")
	if str(cfg.get("action", "")) == "melee":
		return ContentText.of("UI_S5_NO_CHARGE", "No charge system")
	var state := ContentText.of("UI_HUD_READY", "READY")
	if int(item.get("charges", 0)) <= 0:
		var remaining := float(item.get("cooldown", 0.0))
		state = ContentText.of("UI_S5_RECHARGE_IN", "Next {seconds}s").format({"seconds": "%.1f" % remaining}) if remaining > 0.0 else ContentText.of("UI_HUD_EMPTY", "EMPTY")
	return ContentText.of("UI_BUILD_CHARGES_LINE", "CHARGES {charges}/{capacity} / {state}").format({
		"charges": int(item.get("charges", 0)),
		"capacity": int(stats.capacity),
		"state": state,
	})


## Rebuild one shared details band from canonical presenter/canonical projections.
## Called on open, focus change, note change and locale change; never per frame.
func _refresh_details() -> void:
	# ui_wrap returns its cache-owned array. A successful rebuild below replaces
	# this reference; never clear it in place or the cache itself is mutated and
	# a later cache hit (for example en→zh→en) returns an already-cleared array.
	if not is_instance_valid(offer) or offer == null:
		_detail_lines = []
		_detail_count = 0
		_detail_scroll = 0
		return
	var build := Game.build
	var parts: Array[String] = []
	if offer.kind == "scroll":
		var axis: String = build.attributes.keys()[_index]
		var change := build.scroll_projection(axis, Game.player.hp)
		if not _note.is_empty():
			parts.append(_note_display())
			parts.append("")
		var affected: Array = change.get("affected", [])
		for entry: Dictionary in affected:
			var item: Dictionary = build.slots[int(entry.slot)]
			var before: Dictionary = entry.get("before", {})
			var after: Dictionary = entry.get("after", {})
			parts.append(ContentText.of("UI_BUILD_SCROLL_AFFECTED", "[{slot}] {name} / {label} {before} → {after} ({delta})").format({
				"slot": _slot_name(int(entry.slot)),
				"name": _gear_display_name(item),
				"label": ContentText.stat_label(str(before.get("label", ""))),
				"before": "%d" % int(before.get("value", 0)),
				"after": "%d" % int(after.get("value", 0)),
				"delta": "%+d" % (int(after.get("value", 0)) - int(before.get("value", 0))),
			}))
		if affected.is_empty():
			parts.append(ContentText.of("UI_BUILD_SCROLL_NO_AXIS", "No equipped gear uses this axis. Maximum HP still increases."))
		parts.append(ContentText.of("UI_BUILD_SCROLL_NORMAL", "Normal damage · critical hits and status effects excluded"))
		parts.append(ContentText.of("UI_S5_SCROLL_HP_FACT", "Max HP increases; current HP is not restored."))
	else:
		if _slots.is_empty():
			_detail_lines = []
			_detail_count = 0
			_detail_scroll = 0
			return
		var slot := _slots[clampi(_index, 0, _slots.size() - 1)]
		var target_item: Dictionary = build.slots[slot]
		if not _note.is_empty():
			parts.append(_note_display())
			parts.append("")
		# The band scrolls, so each block names its owner; the card labels alone
		# would be off-screen while the player reads these mechanics.
		parts.append(ContentText.of("UI_BUILD_CANDIDATE", "FOUND / CANDIDATE"))
		var candidate_info := GearPresentation.describe(build, offer.item)
		for line: Variant in candidate_info.details:
			parts.append(str(line))
		parts.append("")
		parts.append(ContentText.of("UI_BUILD_REPLACE_SLOT", "Replace [{slot}] / +{gold} Gold recycled").format({
			"slot": _slot_name(slot),
			"gold": _recycle_credit(target_item),
		}))
		var target_info := GearPresentation.describe(build, target_item)
		if build.definition(target_item).is_empty():
			parts.append(ContentText.of("UI_S5_EMPTY_SLOT", "Nothing equipped"))
		else:
			# describe() has no current-HP argument by contract; the real
			# replacement projection lives here, once, with no healing implied.
			if str(build.definition(target_item).get("kind", "")) == "amulet" and str(build.definition(offer.item).get("kind", "")) == "amulet":
				var next := build.replacement_projection(slot, offer.item, Game.player.hp)
				parts.append(ContentText.of("UI_BUILD_AMULET_HP", "HP {hp} / {max} → {next_hp} / {next_max} · No healing").format({
					"hp": "%.1f" % Game.player.hp,
					"max": "%.1f" % Game.player.max_hp,
					"next_hp": "%.1f" % next.hp_after,
					"next_max": "%.1f" % next.max_after,
				}))
		for line: Variant in target_info.details:
			parts.append(str(line))
	_detail_lines = MathArt.ui_wrap("\n".join(parts), DETAIL_WIDTH, DETAIL_SIZE)
	_detail_count = _detail_lines.size()
	_detail_scroll = clampi(_detail_scroll, 0, maxi(0, _detail_count - _detail_rows))


## One count/range line used by both pages. The prompt pair, first–last visible
## row and total keep the scroll position honest without covering price/confirm.
func _detail_range_text() -> String:
	if _detail_count <= _detail_rows:
		return ContentText.of("UI_BUILD_DETAILS_ALL", "All details shown")
	return ContentText.of("UI_BUILD_DETAILS_RANGE", "{detail} Details {from}–{to} / {total}").format({
		"detail": _prompt_pair(&"ui_detail_up", &"ui_detail_down"),
		"from": _detail_scroll + 1,
		"to": mini(_detail_scroll + _detail_rows, _detail_count),
		"total": _detail_count,
	})


## Player-facing gear name at the presentation boundary. Empty/missing items
## say "Empty" instead of exposing an id.
func _gear_display_name(item: Dictionary) -> String:
	var cfg := Game.build.definition(item)
	if cfg.is_empty() or str(item.get("id", "")).is_empty():
		return ContentText.of("UI_STAT_EMPTY", "Empty")
	return ContentText.name("gear", str(item.id), str(cfg.get("name", item.id)))


func _draw_detail(at: Vector2, rows: int) -> void:
	var pitch := MathArt.ui_line_height(DETAIL_SIZE)
	for n in range(_detail_scroll, mini(_detail_lines.size(), _detail_scroll + rows)):
		_canvas.draw_string(MathArt.ui_font(), at + Vector2(0, (n - _detail_scroll) * pitch), _detail_lines[n], HORIZONTAL_ALIGNMENT_LEFT, -1, DETAIL_SIZE, MathArt.PALE)
