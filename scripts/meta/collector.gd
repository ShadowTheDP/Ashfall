extends CanvasLayer
## One pause owner for every Passage service; closing never chooses a destination.
const BUILD_SCREEN := preload("res://scripts/ui/build_screen.gd")
const ROW_H := 32.0 * MathArt.PHI
signal continued
var service := "collector"
var _ids: Array[String] = []
var _index := 0
var _canvas: Control
var _note := ""
var _owner: RunBuild
var _route := false
var _detail_scroll := 0
var _detail_count := 0
## Full raw save diagnostic, in its own scrollable region. The receipt in _note
## names the outcome only, so a long reason is never truncated.
var _fail_detail := ""
var _fail_scroll := 0
var _fail_count := 0
## UI-only: the blueprint that just crossed its unlock cost this session.
var _unlocked_id := ""
## The service opens on the interact press; that same press must not buy.
var _opened_frame := -1
## Reset is the only destructive action here: it owns a nearest-layer confirm
## so Back cancels the reset and still cannot close the service underneath.
var _reset_confirm := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 35
	_owner = Game.build
	_route = _owner != null
	if not _route:
		for id in Data.upgrades:
			if str(Data.upgrades[id].get("currency", "cells")) == "cells":
				_ids.append(str(id))
	else:
		match service:
			"collector": _ids.assign(Data.passage.blueprints.keys())
			"mutation":
				# Reset stays first so W/S order matches the visual order.
				_ids.append("reset")
				for id: String in Data.passage.mutations.keys():
					_ids.append(id)
			"craft":
				for slot in 4: # Game.craft excludes the passive slot.
					_ids.append("upgrade/%d" % slot)
					_ids.append("reforge/%d" % slot)
			"forge": _ids = ["forge"]
			"challenge": _ids.assign(Game.challenge_ids())
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_ui)
	add_child(_canvas)
	get_tree().paused = true
	_opened_frame = Engine.get_process_frames()
	MathArt.ui_reveal(_canvas)
	Interface.presentation_changed.connect(_refresh)
	_canvas.queue_redraw()


## Device/locale switch refreshes key labels only: focus, index and scroll win.
func _refresh() -> void:
	if is_instance_valid(_canvas):
		_canvas.queue_redraw()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	get_viewport().set_input_as_handled()
	if Engine.get_process_frames() == _opened_frame:
		return
	# The unlock card owns every input while it is up: it is acknowledgement, not
	# another purchase and not a service exit.
	if not _unlocked_id.is_empty():
		if Interface.pressed(event, &"ui_accept") or Interface.pressed(event, &"ui_back"):
			_unlocked_id = ""
			_canvas.queue_redraw()
		return
	# Reset confirmation is the nearest acknowledgement: Back cancels only this
	# layer and spends nothing; the service stays open underneath.
	if _reset_confirm:
		if Interface.pressed(event, &"ui_accept"):
			_reset_confirm = false
			_buy()
			_canvas.queue_redraw()
		elif Interface.pressed(event, &"ui_back"):
			_reset_confirm = false
			_note = ContentText.of("UI_S6_RESET_CANCELLED", "Reset cancelled / 0 Gold spent")
			Sfx.play("ui", -14)
			_canvas.queue_redraw()
		return
	if Interface.pressed(event, &"ui_back"):
		_continue()
		return
	if Interface.pressed(event, &"ui_accept"):
		var id := _ids[_index] if not _ids.is_empty() else ""
		if _route and service == "mutation" and id == "reset":
			# Reset is exclusive: an empty reset explains itself here and never
			# reaches _buy(), so it cannot produce a NOT COMMITTED receipt, a
			# save attempt or a failure sound.
			if _owner.mutations.is_empty():
				_note = ContentText.of("UI_S6_RESET_NONE", "No chosen effects to clear.")
				_canvas.queue_redraw()
				return
			# A reset is destructive and paid: show the real price and names
			# first. Confirming is the only path that calls the transaction.
			_reset_confirm = true
			_note = ""
			Sfx.play("ui", -12)
			_canvas.queue_redraw()
			return
		_buy()
		_canvas.queue_redraw()
		return
	var previous := _index
	# Up/Down are rows on both devices: D-pad and keyboard arrows must never be
	# stolen by an overflowing detail. Only the pad right stick (a motion event)
	# addresses the detail region, and its clamped scroll always accepts.
	if event is InputEventJoypadMotion and Interface.pressed(event, &"ui_detail_up"):
		_scroll_detail(-1)
	elif event is InputEventJoypadMotion and Interface.pressed(event, &"ui_detail_down"):
		_scroll_detail(1)
	elif Interface.pressed(event, &"ui_nav_up"):
		_index = wrapi(_index - 1, 0, maxi(1, _ids.size()))
	elif Interface.pressed(event, &"ui_nav_down"):
		_index = wrapi(_index + 1, 0, maxi(1, _ids.size()))
	elif Interface.pressed(event, &"ui_nav_left"):
		_scroll_detail(-1)
	elif Interface.pressed(event, &"ui_nav_right"):
		_scroll_detail(1)
	else:
		return
	if previous != _index:
		_note = ""
		_fail_detail = ""
		_fail_scroll = 0
		_detail_scroll = 0
		if _route: MathArt.ui_select(_canvas)
	_canvas.queue_redraw()


func _detail_visible() -> int:
	return 2 if service == "mutation" else 3


func _fail_rows() -> int:
	return int((214.0 - 60.0) / MathArt.ui_line_height(11))


func _scroll_detail(direction: int) -> void:
	if not _fail_detail.is_empty():
		_fail_scroll = clampi(_fail_scroll + direction, 0, maxi(0, _fail_count - _fail_rows()))
	elif _route and service in ["collector", "mutation"]:
		_detail_scroll = clampi(_detail_scroll + direction, 0, maxi(0, _detail_count - _detail_visible()))
	_canvas.queue_redraw()


## The page header states the three facts a player needs before pressing
## anything: what is spent, whether the effect is run or permanent, and when it
## reaches disk. The wallet line already names the exact balance.
func _scope_context() -> String:
	var spend := ContentText.of("UI_S6_SPEND_CELLS", "Spend: carried Cells")
	var effect := ContentText.of("UI_S6_EFFECT_PERMANENT", "Permanent effect")
	var landing := ContentText.of("UI_S6_LAND_IMMEDIATE", "Saved immediately")
	if _route:
		match service:
			"mutation", "craft":
				spend = ContentText.of("UI_S6_SPEND_GOLD", "Spend: this run's Gold")
				effect = ContentText.of("UI_S6_EFFECT_RUN", "This-run effect")
				landing = ContentText.of("UI_S6_LAND_CHECKPOINT", "Saved at this Passage checkpoint")
			"collector", "forge":
				landing = ContentText.of("UI_S6_LAND_CHECKPOINT", "Saved at this Passage checkpoint")
			"challenge":
				spend = ContentText.of("UI_S6_SPEND_NONE", "No cost")
				effect = ContentText.of("UI_S6_EFFECT_RUN", "This-run effect")
	return spend + " · " + effect + " · " + landing


## One machine-readable state per row. Name, short text and marker all derive
## from this, so locked and bought never share a single dim style.
func _state_of(id: String) -> String:
	if not _route:
		var upgrade_cost := Profile.upgrade_cost(id)
		if upgrade_cost < 0:
			return "completed"
		return "available" if Game.run_cells >= upgrade_cost else "insufficient"
	match service:
		"collector":
			var cfg: Dictionary = Data.passage.blueprints[id]
			if int(Profile.blueprint_cells.get(id, 0)) >= int(cfg.cost):
				return "completed"
			if Game.carried_blueprints.has(id):
				return "available"
			if not Profile.delivered_blueprints.has(id):
				return "locked"
			return "available" if Game.blueprint_investment(id, int(Data.passage.investment_step)) > 0 else "insufficient"
		"mutation":
			if id == "reset":
				if _owner.mutations.is_empty():
					return "completed"
				return "available" if _owner.gold >= _owner.reset_cost() else "insufficient"
			if _owner.mutations.has(id):
				return "chosen"
			if not Profile.mutation_available(id) or _owner.mutations.size() >= _owner.mutation_capacity:
				return "locked"
			return "available"
		"craft":
			var item := _owner.slots[int(id.get_slice("/", 1))]
			if item.is_empty():
				return "locked"
			var cost := _owner.craft_cost(int(id.get_slice("/", 1)), id.begins_with("reforge"))
			if cost < 0:
				return "completed"
			return "available" if _owner.gold >= cost else "insufficient"
		"forge":
			if Profile.forge_cells >= int(Data.passage.forge.cost):
				return "completed"
			return "available" if Game.forge_investment(int(Data.passage.investment_step)) > 0 else "insufficient"
		"challenge":
			if Game.passage_claims.has(id):
				return "completed"
			return "available" if Game.challenge_available(id) else "locked"
	return "available"


func _state_tone(state: String) -> Color:
	match state:
		"available": return MathArt.ACCENT
		"locked": return MathArt.STONE_HI
		"chosen": return MathArt.HEAL
		"owned": return MathArt.PLAYER
		"completed": return MathArt.HEAL
		"insufficient": return MathArt.DANGER
	return MathArt.PALE


## First fact in the blueprint pane: what the unlocked object actually does.
## Gear goes through the fixed GearPresentation API; a Mutation reads its real
## effect text. This is a read-only probe item, never inserted into the build.
func _blueprint_purpose(id: String) -> String:
	var cfg: Dictionary = Data.passage.blueprints[id]
	var target := str(cfg.target)
	if cfg.kind == "mutation":
		return ContentText.text("mutation", target, str(Data.passage.mutations.get(target, {}).get("text", "")))
	var probe := {"uid": 0, "id": target, "quality": "plain", "affix": "none", "charges": 0, "cooldown": 0.0}
	var info := GearPresentation.describe(_owner, probe)
	var play := str(info.get("playstyle", ""))
	var condition := str(info.get("condition", ""))
	if play.is_empty():
		return str(info.get("headline", ""))
	return play if condition.is_empty() else play + " " + condition


func _blueprint_next_step(id: String, invested: int, complete: bool, carried: bool, delivered: bool) -> String:
	var cost := int(Data.passage.blueprints[id].cost)
	if complete:
		return ContentText.of("UI_S6_NEXT_COMPLETE", "Unlocked for future loot and runs.")
	if carried:
		return ContentText.of("UI_S6_NEXT_DELIVER", "Deliver this blueprint to start investing Cells.")
	if not delivered:
		return ContentText.of("UI_S6_NEXT_FIND", "Find this blueprint in a biome, then bring it to a Collector.")
	var spend := Game.blueprint_investment(id, int(Data.passage.investment_step))
	if spend > 0:
		return ContentText.of("UI_S6_NEXT_INVEST", "Invest {step} Cells now; {left} left to unlock.").format({"step": spend, "left": cost - invested - spend})
	return ContentText.of("UI_S6_NEXT_NEED_CELLS", "Need carried Cells; saved progress is kept.")


func _mutation_tone(id: String) -> Color:
	var cfg: Dictionary = Data.passage.mutations.get(id, {})
	if float(cfg.get("damage", 0)) > 0:
		return MathArt.BRUTALITY
	if float(cfg.get("cooldown", 0)) != 0:
		return MathArt.TACTICS
	if float(cfg.get("damage_taken", 0)) != 0:
		return MathArt.SURVIVAL
	if float(cfg.get("heal_kill", 0)) > 0:
		return MathArt.HEAL
	return MathArt.TACTICS



func _empty_message() -> String:
	match service:
		"collector": return ContentText.of("UI_S6_EMPTY_COLLECTOR", "No blueprints to deliver yet")
		"mutation": return ContentText.of("UI_S6_EMPTY_MUTATION", "No mutation effects are available")
		"craft": return ContentText.of("UI_S6_EMPTY_CRAFT", "No gear to upgrade")
		"forge": return ContentText.of("UI_S6_EMPTY_FORGE", "The Forge is unavailable here")
		"challenge": return ContentText.of("UI_S6_EMPTY_CHALLENGE", "No challenge qualifies at this Passage")
	return ContentText.of("UI_COLLECTOR_EMPTY", "No available entries")


func _buy() -> void:
	if _ids.is_empty():
		return
	var id := _ids[_index]
	var success := false
	var cells_before := Game.run_cells
	var carried := Game.carried_blueprints.has(id)
	var name_before := str(_row(id)[0])
	var unlocked_before := true
	var unlock_cost := 0
	if _route and service == "collector":
		unlock_cost = int(Data.passage.blueprints[id].cost)
		unlocked_before = int(Profile.blueprint_cells.get(id, 0)) >= unlock_cost
	Profile.last_save_error = ""
	if _route:
		if _owner != Game.build or not Game.service_ready():
			return
		match service:
			"collector":
				success = Game.deliver_blueprint(id) if Game.carried_blueprints.has(id) else Game.invest_blueprint(id, int(Data.passage.investment_step)) > 0
			"mutation": success = Game.reset_mutations() if id == "reset" else Game.choose_mutation(id)
			"craft": success = Game.craft(int(id.get_slice("/", 1)), id.begins_with("reforge"))
			"forge": success = Game.invest_forge(int(Data.passage.investment_step)) > 0
			"challenge": success = Game.claim_challenge(id)
	else:
		var cost := Profile.upgrade_cost(id)
		if cost >= 0 and Game.run_cells >= cost and Profile.add_upgrade(id):
			Game.run_cells -= cost
			success = true
	var failed_row := _row(id)
	_note = ContentText.of("UI_COLLECTOR_NOTE_SAVED", "SAVED / {name}").format({"name": name_before}) if success else ContentText.of("UI_COLLECTOR_NOTE_FAILED", "NOT COMMITTED / {reason} / {price}").format({"reason": failed_row[1], "price": _status_text(str(failed_row[2]))})
	if success and _route and service in ["collector", "forge"]:
		_note += ContentText.of("UI_COLLECTOR_NOTE_DELIVERED", " / BLUEPRINT DELIVERED") if carried else ContentText.of("UI_COLLECTOR_NOTE_INVESTED", " / {count} CELLS INVESTED").format({"count": cells_before - Game.run_cells})
	if not Profile.last_save_error.is_empty():
		# Localized, actionable receipt; the raw diagnostic gets its own
		# scrollable region so nothing is ever cut off.
		_note = ContentText.of("UI_COLLECTOR_NOTE_SAVE_FAILED", "SAVE FAILED / NOTHING COMMITTED / {action} RETRY").format({"action": Interface.prompt(&"ui_accept")})
		_fail_detail = Profile.last_save_error
	else:
		_fail_detail = ""
	_fail_scroll = 0
	# Unlock celebration only for a real, persisted crossing of this cost.
	# Delivery, partial investment, no Cells and save failure all stay silent.
	if success and not unlocked_before and unlock_cost > 0 and Profile.last_save_error.is_empty():
		if int(Profile.blueprint_cells.get(id, 0)) >= unlock_cost:
			_unlocked_id = id
	Sfx.play("reward" if success else "block", -10)

func _continue() -> void:
	visible = false
	if is_instance_valid(Game.player):
		Game.player.suppress_actions()
	get_tree().paused = false
	continued.emit()
	queue_free()

func _row(id: String) -> Array:
	if not _route:
		var cost := Profile.upgrade_cost(id)
		var effect := ContentText.text("upgrade", id, str(Data.upgrades[id].text))
		return [ContentText.name("upgrade", id, str(Data.upgrades[id].name)), effect, _status_text("MAX") if cost < 0 else _price(cost, "cells"), effect]
	match service:
		"collector":
			var cfg: Dictionary = Data.passage.blueprints[id]
			var progress := int(Profile.blueprint_cells.get(id, 0))
			var biome := str(cfg.biome)
			var status := ContentText.of("UI_COLLECTOR_STATUS_LOCKED", "LOCKED BLUEPRINT / FIND IN {biome}").format({"biome": ContentText.name("biome", biome, str(Data.route_graph["nodes"].get(biome, {}).get("name", biome))).to_upper()})
			var state := ContentText.of("UI_COMMON_LOCKED", "LOCKED")
			if Game.carried_blueprints.has(id):
				status = ContentText.of("UI_COLLECTOR_STATUS_CARRIED", "CARRIED / {action} DELIVER / NO CELLS COST").format({"action": Interface.prompt(&"ui_accept")})
				state = ContentText.of("UI_COLLECTOR_SHORT_CARRIED", "CARRIED")
			elif Profile.delivered_blueprints.has(id):
				var spend := Game.blueprint_investment(id, int(Data.passage.investment_step))
				status = ContentText.of("UI_COLLECTOR_STATUS_INVEST", "{action} INVEST {step} CELLS / {left} LEFT TO UNLOCK").format({"action": Interface.prompt(&"ui_accept"), "step": spend, "left": int(cfg.cost) - progress - spend}) if spend > 0 else ContentText.of("UI_COLLECTOR_STATUS_DELIVERED", "DELIVERED / NEED CARRIED CELLS TO INVEST")
				state = ContentText.of("UI_KEY_INVEST", "Invest") if spend > 0 else ContentText.of("UI_COLLECTOR_SHORT_DELIVERED", "DELIVERED")
			if progress >= int(cfg.cost):
				status = ContentText.of("UI_COLLECTOR_STATUS_UNLOCKED", "UNLOCKED IN PROFILE / FUTURE LOOT")
				state = ContentText.of("UI_COLLECTOR_SHORT_UNLOCKED", "UNLOCKED")
			return [ContentText.name("blueprint", id, str(cfg.name)), status, ContentText.of("UI_PRICE_PROGRESS_CELLS", "{have}/{need} CELLS").format({"have": progress, "need": int(cfg.cost)}), state]
		"mutation":
			if id == "reset":
				return [ContentText.of("UI_COLLECTOR_RESET_NAME", "RESET ALL"), ContentText.of("UI_COLLECTOR_RESET_TEXT", "CLEAR CHOSEN EFFECTS / KEEP SLOTS"), _price(_owner.reset_cost(), "gold"), ContentText.of("UI_KEY_RESET", "Reset")]
			var cfg: Dictionary = Data.passage.mutations[id]
			var status := "CHOOSE"
			if _owner.mutations.has(id): status = "CHOSEN"
			elif not Profile.mutation_available(id): status = "LOCKED"
			elif _owner.mutations.size() >= _owner.mutation_capacity: status = "FULL"
			return [ContentText.name("mutation", id, str(cfg.name)), _status_text(status) + " / " + ContentText.text("mutation", id, str(cfg.text)), status, _status_text(status)]
		"craft":
			var slot := int(id.get_slice("/", 1))
			var item := _owner.slots[slot]
			var cost := _owner.craft_cost(slot, id.begins_with("reforge"))
			var key: String = BUILD_SCREEN.slot_key(slot)
			var action := ContentText.of("UI_COLLECTOR_CRAFT_UPGRADE", "UPGRADE") if id.begins_with("upgrade") else ContentText.of("UI_COLLECTOR_CRAFT_REFORGE", "REFORGE")
			var gear_name := ContentText.name("gear", str(item.id), str(_owner.definition(item).name))
			return [ContentText.of("UI_COLLECTOR_CRAFT_ROW", "{action} [{slot}]").format({"action": action, "slot": key}), ContentText.of("UI_COLLECTOR_CRAFT_DETAIL", "{item} / {quality} / {affix}").format({"item": gear_name, "quality": RunLoot.quality_name(str(item.quality)), "affix": ContentText.name("affix", str(item.affix), str(Data.gear.affixes[item.affix].name))}), _status_text("MAX") if cost < 0 else _price(cost, "gold"), gear_name]
		"forge":
			var spend := Game.forge_investment(int(Data.passage.investment_step))
			var quota := ContentText.of("UI_PRICE_PROGRESS_CELLS", "{have}/{need} CELLS").format({"have": Profile.forge_cells, "need": int(Data.passage.forge.cost)})
			var text := ContentText.of("UI_COLLECTOR_FORGE_INVEST", "{action} INVEST {step} CELLS / FUTURE LOOT {chance}% {quality}").format({"action": Interface.prompt(&"ui_accept"), "step": spend, "chance": roundi(Profile.forge_chance() * 100), "quality": RunLoot.quality_name(str(Data.passage.forge.quality)).to_upper()})
			var state := ContentText.of("UI_KEY_INVEST", "Invest")
			if spend <= 0:
				var done := Profile.forge_cells >= int(Data.passage.forge.cost)
				text = ContentText.of("UI_COLLECTOR_FORGE_COMPLETE", "PERMANENTLY COMPLETE") if done else ContentText.of("UI_COLLECTOR_NEED_CELLS", "NEED CARRIED CELLS TO INVEST")
				state = ContentText.of("UI_COLLECTOR_SHORT_COMPLETE", "COMPLETE") if done else ContentText.of("UI_COLLECTOR_SHORT_NEED_CELLS", "NEED CELLS")
			return [ContentText.of("UI_COLLECTOR_FORGE_NAME", "PERMANENT QUALITY"), text, quota, state]
		"challenge":
			var cfg: Dictionary = Data.passage.challenges[id]
			var status := "CLAIMED" if Game.passage_claims.has(id) else "AVAILABLE"
			if status != "CLAIMED" and not Game.challenge_available(id):
				status = "FAILED"
			return [ContentText.name("challenge", id, str(cfg.name)), ContentText.text("challenge", id, str(cfg.text)), _status_text(status) if status == "CLAIMED" or status == "FAILED" else ContentText.of("UI_PRICE_REWARD_SHORT", "{gold}G +{cells}C").format({"gold": int(cfg.gold), "cells": int(cfg.cells)}), ContentText.text("challenge", id, str(cfg.text))]
	return [id, "", "", ""]

## Currency amount with its localized unit; the count and the unit are separate rows.
func _price(amount: int, currency: String) -> String:
	var unit := ContentText.of("UI_UNIT_SOULS", "Souls") if currency == "souls" else ContentText.of("UI_UNIT_CELLS", "Cells") if currency == "cells" else ContentText.of("UI_UNIT_GOLD", "Gold")
	return ContentText.of("UI_PRICE_AMOUNT", "{amount} {unit}").format({"amount": amount, "unit": unit})

## Row status tokens stay machine values (`row[2]` is compared for CHOSEN); only
## the drawn text goes through here.
func _status_text(token: String) -> String:
	match token:
		"CHOOSE": return ContentText.of("UI_COMMON_CHOOSE", "CHOOSE")
		"CHOSEN": return ContentText.of("UI_COMMON_CHOSEN", "CHOSEN")
		"LOCKED": return ContentText.of("UI_COMMON_LOCKED", "LOCKED")
		"FULL": return ContentText.of("UI_COMMON_FULL", "FULL")
		"CLAIMED": return ContentText.of("UI_COMMON_CLAIMED", "CLAIMED")
		"FAILED": return ContentText.of("UI_COMMON_FAILED", "FAILED")
		"MAX": return ContentText.of("UI_COMMON_MAX", "MAX")
	return token

func _draw_ui() -> void:
	var c := _canvas
	MathArt.px_rect(c, Rect2(0, 0, 768, 480), Color(MathArt.INK, 0.82))
	MathArt.ui_panel(c, MathArt.UI_PAGE)
	# One backdrop per page. The acknowledgement owns the whole page while it is
	# up, so the service list, price controls and key band are not painted under
	# it and no second full-screen scrim is needed.
	if not _unlocked_id.is_empty():
		_draw_unlock()
		return
	if _reset_confirm:
		_draw_reset_confirm()
		return
	var scope := _scope_context()
	var wallet := ContentText.of("UI_COLLECTOR_WALLET_CELLS", "{count} carried Cells").format({"count": Game.run_cells})
	if _route and service in ["craft", "mutation"]: wallet = _price(_owner.gold, "gold")
	elif _route and service == "challenge": wallet = ContentText.of("UI_COLLECTOR_WALLET_BOTH", "{gold} Gold · {cells} Cells").format({"gold": _owner.gold, "cells": Game.run_cells})
	MathArt.ui_heading(c, Passage.service_name(service), scope, wallet)
	var full_composition := _route and service in ["forge", "challenge", "mutation"]
	var top := maxi(0, _index - 3)
	if not full_composition:
		for i in range(top, mini(top + 4, _ids.size())):
			var row := _row(_ids[i])
			var rect := Rect2(52, 112 + (i - top) * ROW_H, 246, ROW_H - 4)
			if i == _index: MathArt.ui_focus(c, rect)
			var blueprint := _route and service == "collector"
			if blueprint:
				_draw_blueprint_icon(_ids[i], rect.position + Vector2(24, 22), 14, MathArt.WHITE if i == _index else MathArt.MID)
			var inset := 50 if blueprint else 24
			var names := MathArt.ui_wrap(str(row[0]), 246 - inset - 10, 13)
			var pitch := MathArt.ui_line_height(13)
			for n in mini(names.size(), 2):
				MathArt.ui_text(c, rect.position + Vector2(inset, 17 + n * pitch), names[n] + ("…" if n == 1 and names.size() > 2 else ""), 13, MathArt.WHITE if i == _index else MathArt.PALE)
			var state := _state_of(_ids[i])
			MathArt.ui_state(c, rect.position + Vector2(inset + 4, 45), state)
			MathArt.ui_text(c, rect.position + Vector2(inset + 14, 44), MathArt.ui_short(str(row[3]).to_upper(), 104, 11), 11, _state_tone(state), 104)
			MathArt.ui_text(c, rect.position + Vector2(rect.size.x - 66, 44), _status_text(str(row[2])), 11, MathArt.PALE, 58, HORIZONTAL_ALIGNMENT_RIGHT)

	if not full_composition:
		MathArt.ui_text(c, Vector2(60, 351), "%d / %d  ↑ ↓" % [_index + 1 if not _ids.is_empty() else 0, _ids.size()], 11, MathArt.LIGHT_DIM)
		MathArt.line(c, Vector2(310, 112), Vector2(310, 354), MathArt.STONE, 1)
	if not _fail_detail.is_empty():
		_draw_failure()
	elif not _ids.is_empty():
		_draw_service(_ids[_index])
	else:
		MathArt.ui_text(c, Vector2(328, 145), _empty_message(), 16)
		MathArt.ui_text(c, Vector2(328, 172), ContentText.of("UI_S6_EMPTY_DETAIL", "This service can still be closed with Back."), 11, MathArt.LIGHT_DIM)
	MathArt.line(c, Vector2(52, 365), Vector2(716, 365), MathArt.STONE, 1)
	var message := _note
	if message.is_empty(): message = ContentText.of("UI_COLLECTOR_FOOTER", "Select an option to see its effect and cost. Changes save only after success.")
	var lines := MathArt.ui_wrap(message, 650, 11)
	var note_pitch := MathArt.ui_line_height(11)
	for i in mini(lines.size(), 3):
		MathArt.ui_text(c, Vector2(52, 384 + i * note_pitch), lines[i], 11, MathArt.WHITE if not _note.is_empty() else MathArt.PALE)
	var x := 52.0
	x += MathArt.ui_key(c, Vector2(x, 428), _key_labels([&"ui_nav_up", &"ui_nav_down"]), ContentText.of("UI_KEY_SELECT", "Select"))
	var action := ContentText.of("UI_KEY_BUY", "Buy")
	if _route and not _ids.is_empty():
		match service:
			"collector": action = ContentText.of("UI_KEY_DELIVER", "Deliver") if Game.carried_blueprints.has(_ids[_index]) else ContentText.of("UI_KEY_INVEST", "Invest")
			"forge": action = ContentText.of("UI_KEY_INVEST", "Invest")
			"mutation": action = ContentText.of("UI_KEY_RESET", "Reset") if _ids[_index] == "reset" else ContentText.of("UI_KEY_CHOOSE", "Choose")
			"craft": action = ContentText.of("UI_KEY_REFORGE", "Reforge") if _ids[_index].begins_with("reforge") else ContentText.of("UI_KEY_UPGRADE", "Upgrade")
			"challenge": action = ContentText.of("UI_KEY_CLAIM", "Claim")
	MathArt.ui_key(c, Vector2(x, 428), Interface.prompt(&"ui_accept"), action)
	MathArt.ui_key(c, Vector2(572, 428), Interface.prompt(&"ui_back"), ContentText.of("UI_KEY_BACK", "Back"))

## Full reset confirmation. It is a nearest layer, not a second page: it shows
## the real price and the exact names it will erase, and Back spends nothing.
func _draw_reset_confirm() -> void:
	var c := _canvas
	var card := Rect2(184, 104, 400, 272)
	MathArt.ui_panel(c, card, true)
	var cost := _owner.reset_cost()
	MathArt.ui_text(c, Vector2(204, 134), ContentText.of("UI_S6_RESET_TITLE", "RESET MUTATIONS?"), 16, MathArt.WHITE)
	MathArt.ui_text(c, Vector2(204, 156), ContentText.of("UI_S6_RESET_CONTEXT", "THIS RUN · PASSAGE CHECKPOINT"), 11, MathArt.LIGHT_DIM)
	var cost_line := ContentText.of("UI_S6_RESET_COST", "Cost {cost} Gold · {after} Gold after").format({"cost": cost, "after": _owner.gold - cost}) if _owner.gold >= cost else ContentText.of("UI_S6_RESET_COST_ONLY", "Cost {cost} Gold").format({"cost": cost})
	MathArt.ui_text(c, Vector2(204, 190), cost_line, 16, MathArt.GOLD)
	var balance := ContentText.of("UI_S6_RESET_BALANCE", "Current Gold {gold}").format({"gold": _owner.gold})
	var balance_tone := MathArt.PALE
	if _owner.gold < cost:
		balance = ContentText.of("UI_S6_RESET_SHORT", "Current Gold {gold} · need {short} more").format({"gold": _owner.gold, "short": cost - _owner.gold})
		balance_tone = MathArt.DANGER
	MathArt.ui_text(c, Vector2(204, 212), balance, 11, balance_tone)
	MathArt.ui_text(c, Vector2(204, 240), ContentText.of("UI_S6_RESET_CLEARS", "Clears these chosen effects:"), 11, MathArt.LIGHT_DIM)
	if _owner.mutations.is_empty():
		MathArt.ui_text(c, Vector2(204, 262), ContentText.of("UI_S6_RESET_NONE", "No chosen effects to clear."), 13, MathArt.LIGHT_DIM)
	else:
		var pitch := MathArt.ui_line_height(13)
		for i in _owner.mutations.size():
			var mid: String = _owner.mutations[i]
			var name := ContentText.name("mutation", mid, str(Data.passage.mutations[mid].name))
			MathArt.ui_state(c, Vector2(210, 258 + i * pitch), "chosen")
			MathArt.ui_text(c, Vector2(222, 262 + i * pitch), name, 13, MathArt.WHITE)
	MathArt.ui_text(c, Vector2(204, 322), ContentText.of("UI_S6_RESET_KEEP", "Slots, gear, charges and cooldown are kept."), 11, MathArt.LIGHT_DIM)
	MathArt.ui_text(c, Vector2(204, 352), ContentText.of("UI_S6_RESET_FOOTER", "{accept} Confirm reset · {back} Cancel · cancel spends 0 Gold").format({"accept": Interface.prompt(&"ui_accept"), "back": Interface.prompt(&"ui_back")}), 11, MathArt.PALE, 360)


## Acknowledgement of a real persisted unlock. Nothing here writes anything.
func _draw_unlock() -> void:
	var c := _canvas
	var card := Rect2(174, 126, 420, 242)
	MathArt.ui_panel(c, card, true)
	_draw_blueprint_icon(_unlocked_id, Vector2(384, 190), 40, MathArt.WHITE)
	var cfg: Dictionary = Data.passage.blueprints[_unlocked_id]
	var name_line := MathArt.ui_short(ContentText.name("blueprint", _unlocked_id, str(cfg.name)), 360, 16)
	MathArt.ui_text(c, Vector2(194, 252), name_line, 16, MathArt.WHITE, 380, HORIZONTAL_ALIGNMENT_CENTER)
	var description := ContentText.of("UI_COLLECTOR_UNLOCK_GEAR", "Added to future loot.") if cfg.kind == "gear" else ContentText.of("UI_COLLECTOR_UNLOCK_MUTATION", "Available for future runs.")
	var notes := MathArt.ui_wrap(description, 380, 13)
	var note_pitch := MathArt.ui_line_height(13)
	for i in mini(2, notes.size()):
		MathArt.ui_text(c, Vector2(194, 292 + i * note_pitch), notes[i], 13, MathArt.PALE, 380, HORIZONTAL_ALIGNMENT_CENTER)
	MathArt.ui_text(c, Vector2(194, 330), ContentText.of("UI_COLLECTOR_UNLOCK_SAVED", "UNLOCKED / SAVED"), 13, MathArt.HEAL, 380, HORIZONTAL_ALIGNMENT_CENTER)
	MathArt.ui_text(c, Vector2(194, 352), ContentText.of("UI_COLLECTOR_UNLOCK_FOOTER", "{accept} / {back} Continue").format({"accept": Interface.prompt(&"ui_accept"), "back": Interface.prompt(&"ui_back")}), 11, MathArt.PALE, 380, HORIZONTAL_ALIGNMENT_CENTER)

func _draw_service(id: String) -> void:
	if _route:
		match service:
			"collector": _draw_blueprint(id)
			"mutation": _draw_mutation(id)
			"craft": _draw_craft(id)
			"forge": _draw_forge()
			"challenge": _draw_challenges()
		return
	var row := _row(id)
	MathArt.ui_service(_canvas, Vector2(364, 160), "forge", 28)
	var names := MathArt.ui_wrap(str(row[0]), 300, 16)
	for i in mini(2, names.size()): MathArt.ui_text(_canvas, Vector2(412, 146 + i * MathArt.ui_line_height(16)), names[i], 16, MathArt.WHITE)
	MathArt.ui_text(_canvas, Vector2(328, 220), str(row[2]), 20, MathArt.CELL)
	var details := MathArt.ui_wrap(str(row[1]), 372, 13)
	for i in mini(6, details.size()): MathArt.ui_text(_canvas, Vector2(328, 254 + i * 19), details[i], 13)

## The raw save diagnostic in full. It owns the detail column and scrolls, so the
## reason is never cut off by the three-line receipt above the keycaps.
func _draw_failure() -> void:
	var c := _canvas
	var card := Rect2(328, 140, 388, 214)
	MathArt.ui_surface(c, card, true, true)
	var pitch := MathArt.ui_line_height(11)
	MathArt.ui_text(c, card.position + Vector2(14, 22), ContentText.of("UI_ERR_SAVE_FAILED", "Save failed"), 11, MathArt.DANGER)
	var lines := MathArt.ui_wrap(_fail_detail, card.size.x - 28, 11)
	_fail_count = lines.size()
	var rows := int((card.size.y - 60) / pitch)
	_fail_scroll = clampi(_fail_scroll, 0, maxi(0, _fail_count - rows))
	for i in mini(rows, _fail_count - _fail_scroll):
		MathArt.ui_text(c, card.position + Vector2(14, 44 + i * pitch), lines[_fail_scroll + i], 11, MathArt.PALE, card.size.x - 28)
	if _fail_count > rows:
		MathArt.ui_text(c, card.position + Vector2(14, card.size.y - 12), ContentText.of("UI_COLLECTOR_SCROLL_HINT", "{scroll} {index} / {count}").format({"scroll": _scroll_prompt(), "index": _fail_scroll + 1, "count": _fail_count}), 11, MathArt.LIGHT_DIM, card.size.x - 28, HORIZONTAL_ALIGNMENT_RIGHT)

func _draw_mutation(id: String) -> void:
	var c := _canvas
	var capacity := _owner.mutation_capacity
	# Reset is a different kind of action from a choice, so it owns its own row.
	var reset := Rect2(52, 108, 664, 28)
	var reset_focused := id == "reset"
	if reset_focused: MathArt.ui_focus(c, reset)
	MathArt.ui_text(c, reset.position + Vector2(16, 19), ContentText.of("UI_COLLECTOR_RESET_NAME", "RESET ALL"), 13, MathArt.WHITE if reset_focused else MathArt.PALE)
	MathArt.ui_text(c, reset.position + Vector2(106, 19), ContentText.of("UI_COLLECTOR_RESET_TEXT", "CLEAR CHOSEN EFFECTS / KEEP SLOTS"), 11, MathArt.LIGHT_DIM, 300)
	MathArt.ui_state(c, reset.position + Vector2(reset.size.x - 112, 14), _state_of("reset"))
	MathArt.ui_text(c, reset.position + Vector2(reset.size.x - 96, 19), _price(_owner.reset_cost(), "gold"), 11, MathArt.GOLD, 80, HORIZONTAL_ALIGNMENT_RIGHT)
	var label_w := 96.0
	if capacity > 0:
		var slot_w := (664.0 - label_w) / float(capacity)
		for i in capacity:
			var rect := Rect2(52 + i * slot_w, 144, slot_w - 6, 32)
			var equipped := i < _owner.mutations.size()
			MathArt.ui_surface(c, rect, equipped, true)
			var slot_name := ContentText.name("mutation", _owner.mutations[i], str(Data.passage.mutations[_owner.mutations[i]].name)) if equipped else ContentText.of("UI_COLLECTOR_OPEN_SLOT", "Open slot")
			var names := MathArt.ui_wrap(slot_name, slot_w - 26, 12)
			MathArt.ui_text(c, rect.position + Vector2(10, 21), names[0] + ("…" if names.size() > 1 else ""), 12, MathArt.WHITE if equipped else MathArt.MID, slot_w - 26)
		MathArt.ui_text(c, Vector2(52 + 664 - label_w + 8, 158), ContentText.of("UI_COLLECTOR_CHOSEN_COUNT", "CHOSEN {count} / {capacity}").format({"count": _owner.mutations.size(), "capacity": capacity}), 11, MathArt.PALE, label_w - 8)
	else:
		MathArt.ui_text(c, Vector2(52, 164), ContentText.of("UI_COLLECTOR_NO_SLOTS", "No mutation slots available yet"), 13, MathArt.LIGHT_DIM)
	# Effects: a three-row window over the real list, reset excluded.
	var effects: Array[String] = []
	for entry in _ids:
		if entry != "reset":
			effects.append(entry)
	var selected := effects.find(id)
	var start := 0 if selected < 0 else clampi(selected - 1, 0, maxi(0, effects.size() - 3))
	_detail_count = 0
	for n in 3:
		var index := start + n
		if index >= effects.size():
			break
		var mid := effects[index]
		var cfg: Dictionary = Data.passage.mutations[mid]
		var row := _row(mid)
		var rect := Rect2(52, 188 + n * 56, 664, 52)
		var focused := index == selected
		if focused:
			MathArt.ui_focus(c, rect)
		MathArt.ui_mutation(c, rect.position + Vector2(24, 26), mid, 13, _mutation_tone(mid))
		var names := MathArt.ui_wrap(ContentText.name("mutation", mid, str(cfg.name)), 166, 13)
		for i in mini(2, names.size()):
			MathArt.ui_text(c, rect.position + Vector2(46, 20 + i * MathArt.ui_line_height(13)), names[i], 13, MathArt.WHITE if focused else MathArt.PALE)
		var lines := MathArt.ui_wrap(ContentText.text("mutation", mid, str(cfg.text)), 352, 13)
		if focused:
			_detail_count = lines.size()
		var offset := _detail_scroll if focused else 0
		var pitch := MathArt.ui_line_height(13)
		for i in range(offset, mini(lines.size(), offset + 2)):
			MathArt.ui_text(c, rect.position + Vector2(212, 20 + (i - offset) * pitch), lines[i], 13, MathArt.WHITE if focused else MathArt.PALE, 352)
		MathArt.ui_state(c, rect.position + Vector2(550, 20), _state_of(mid))
		MathArt.ui_text(c, rect.position + Vector2(568, 20), _status_text(str(row[2])), 11, MathArt.HEAL if str(row[2]) == "CHOSEN" else MathArt.LIGHT_DIM, 80, HORIZONTAL_ALIGNMENT_RIGHT)
		if focused and _detail_count > 2:
			MathArt.ui_text(c, rect.position + Vector2(568, 42), ContentText.of("UI_COLLECTOR_SCROLL_HINT", "{scroll} {index} / {count}").format({"scroll": _scroll_prompt(), "index": _detail_scroll + 1, "count": _detail_count}), 11, MathArt.LIGHT_DIM, 80, HORIZONTAL_ALIGNMENT_RIGHT)
	var tail := ContentText.of("UI_COLLECTOR_MUTATION_FOOTER", "{scroll} Scroll effect · {accept} Choose · {back} Back").format({"scroll": _scroll_prompt(), "accept": Interface.prompt(&"ui_accept"), "back": Interface.prompt(&"ui_back")})
	MathArt.ui_text(c, Vector2(52, 357), tail, 11, MathArt.LIGHT_DIM)

func _draw_craft(id: String) -> void:
	var c := _canvas
	var slot := int(id.get_slice("/", 1))
	var item := _owner.slots[slot]
	var cfg := _owner.definition(item)
	var preview := _owner.craft_projection(slot, id.begins_with("reforge"))
	MathArt.ui_gear(c, Vector2(364, 155), str(cfg.get("action", "amulet")), 28, MathArt.axis_color(str(cfg.get("attribute", "survival"))), str(item.id))
	var names := MathArt.ui_wrap(ContentText.name("gear", str(item.id), str(cfg.name)), 292, 16)
	for i in mini(2, names.size()): MathArt.ui_text(c, Vector2(412, 138 + i * MathArt.ui_line_height(16)), names[i], 16, MathArt.WHITE)
	var price := ContentText.of("UI_COLLECTOR_MAX_QUALITY", "Maximum quality") if preview.is_empty() else (ContentText.of("UI_S6_CRAFT_PAY", "Pay {cost} Gold · {after} Gold after").format({"cost": preview.cost, "after": _owner.gold - preview.cost}) if _owner.gold >= preview.cost else ContentText.of("UI_S6_CRAFT_NEED", "Need {amount} more Gold · {gold} now").format({"amount": preview.cost - _owner.gold, "gold": _owner.gold}))
	MathArt.ui_text(c, Vector2(328, 195), price, 13, MathArt.GOLD)
	if preview.is_empty():
		MathArt.ui_text(c, Vector2(328, 248), ContentText.of("UI_COLLECTOR_NO_UPGRADE", "This item cannot be upgraded further."), 13)
		return
	for i in 2:
		var target: Dictionary = item if i == 0 else preview.item
		var rect := Rect2(328 + i * 194, 202, 178, 80)
		MathArt.ui_surface(c, rect, i == 1)
		MathArt.ui_text(c, rect.position + Vector2(12, 16), ContentText.of("UI_COMMON_CURRENT", "CURRENT") if i == 0 else ContentText.of("UI_COLLECTOR_AFTER_PAYMENT", "AFTER PAYMENT"), 11, MathArt.LIGHT_DIM)
		MathArt.ui_quality(c, rect.position + Vector2(12, 38), str(target.quality))
		MathArt.ui_text(c, rect.position + Vector2(32, 39), RunLoot.quality_name(str(target.quality)), 16, MathArt.WHITE)
		var affix := MathArt.ui_wrap(ContentText.name("affix", str(target.affix), str(Data.gear.affixes[target.affix].name)), 154, 11)
		for n in mini(2, affix.size()): MathArt.ui_text(c, rect.position + Vector2(12, 58 + n * MathArt.ui_line_height(11)), affix[n], 11)
	MathArt.line(c, Vector2(508, 242), Vector2(520, 242), MathArt.PALE, 1.5)
	# The preview is the real craft_projection result: name the exact outcome,
	# never a "random chance" promise the transaction does not make.
	var result_item: Dictionary = preview.item
	MathArt.ui_text(c, Vector2(328, 300), ContentText.of("UI_S6_CRAFT_RESULT", "Result: {quality} / {affix}").format({"quality": RunLoot.quality_name(str(result_item.quality)), "affix": ContentText.name("affix", str(result_item.affix), str(Data.gear.affixes[result_item.affix].name))}), 11, MathArt.PALE)
	MathArt.ui_text(c, Vector2(328, 326), ContentText.of("UI_COLLECTOR_STAT_CHANGE", "{label} {before} → {after}").format({"label": ContentText.stat_label(preview.before.label), "before": preview.before.value, "after": preview.after.value}), 16, MathArt.WHITE)
	MathArt.ui_text(c, Vector2(328, 344), ContentText.of("UI_COLLECTOR_RECHARGE", "Recharge {before}s → {after}s").format({"before": "%.2f" % preview.before.cooldown, "after": "%.2f" % preview.after.cooldown}), 12)
	MathArt.ui_text(c, Vector2(328, 359), ContentText.of("UI_S6_CRAFT_KEEP", "Preserves current charges and remaining recharge."), 11, MathArt.LIGHT_DIM)

func _draw_forge() -> void:
	var c := _canvas
	var cfg: Dictionary = Data.passage.forge
	MathArt.ui_service(c, Vector2(152, 207), "forge", 46)
	MathArt.ui_text(c, Vector2(248, 137), ContentText.of("UI_COLLECTOR_FORGE_HEADER", "PERMANENT / FUTURE LOOT"), 11, MathArt.LIGHT_DIM)
	MathArt.ui_text(c, Vector2(248, 186), ContentText.of("UI_COLLECTOR_FORGE_CHANCE_VALUE", "{chance}% {quality}").format({"chance": roundi(Profile.forge_chance() * 100), "quality": RunLoot.quality_name(str(cfg.quality))}), 32, MathArt.ACCENT)
	MathArt.ui_text(c, Vector2(248, 218), ContentText.of("UI_COLLECTOR_FORGE_CHANCE", "Chance for newly generated equipment"), 13)
	MathArt.ui_text(c, Vector2(248, 245), ContentText.of("UI_COLLECTOR_FORGE_KEEP", "Carried equipment keeps its current quality."), 11, MathArt.LIGHT_DIM)
	MathArt.ui_text(c, Vector2(248, 262), ContentText.of("UI_S6_FORGE_NO_GEAR", "Does not change carried gear."), 11, MathArt.PALE)
	var ratio := clampf(float(Profile.forge_cells) / float(cfg.cost), 0, 1)
	MathArt.px_rect(c, Rect2(68, 284, 632, 10), MathArt.STONE_DIM)
	MathArt.px_rect(c, Rect2(68, 284, 632 * ratio, 10), MathArt.CELL)
	for threshold: Dictionary in cfg.thresholds:
		var x := 68 + 632 * float(threshold.cells) / float(cfg.cost)
		MathArt.line(c, Vector2(x, 280), Vector2(x, 299), MathArt.PALE, 1)
	MathArt.ui_text(c, Vector2(68, 324), ContentText.of("UI_PRICE_PROGRESS_CELLS_SLASH", "{have} / {need} Cells").format({"have": Profile.forge_cells, "need": cfg.cost}), 20, MathArt.CELL)
	var spend := Game.forge_investment(int(Data.passage.investment_step))
	var action := ContentText.of("UI_COLLECTOR_INVEST_NOW", "Invest {amount} Cells now").format({"amount": spend}) if spend > 0 else (ContentText.of("UI_COLLECTOR_FORGE_COMPLETE", "PERMANENTLY COMPLETE") if ratio >= 1 else ContentText.of("UI_COLLECTOR_NEED_CELLS", "NEED CARRIED CELLS TO INVEST"))
	MathArt.ui_text(c, Vector2(370, 324), action, 13, MathArt.WHITE)
	MathArt.ui_text(c, Vector2(68, 350), ContentText.of("UI_COLLECTOR_FORGE_FOOTER", "Permanent investment · progress survives this run"), 11, MathArt.LIGHT_DIM)

func _draw_challenges() -> void:
	var c := _canvas
	var width := 664.0 if _ids.size() == 1 else 326.0
	for i in _ids.size():
		var id := _ids[i]
		var cfg: Dictionary = Data.passage.challenges[id]
		var claimed := Game.passage_claims.has(id)
		var ready := Game.challenge_available(id)
		var rect := Rect2(52 + i * 338, 112, width, 242)
		MathArt.ui_surface(c, rect, i == _index)
		MathArt.ui_service(c, rect.position + Vector2(38, 35), "challenge", 20)
		MathArt.ui_text(c, rect.position + Vector2(74, 29), ContentText.name("challenge", id, str(cfg.name)), 16, MathArt.WHITE)
		MathArt.ui_text(c, rect.position + Vector2(74, 51), ContentText.of("UI_COLLECTOR_THIS_PASSAGE", "THIS PASSAGE"), 11, MathArt.LIGHT_DIM)
		MathArt.ui_text(c, rect.position + Vector2(16, 100), ContentText.of("UI_COMMON_CLAIMED", "CLAIMED") if claimed else (ContentText.of("UI_COLLECTOR_ACHIEVED", "ACHIEVED") if ready else ContentText.of("UI_COMMON_FAILED", "FAILED")), 24, MathArt.HEAL if claimed or ready else MathArt.DANGER)
		var details := MathArt.ui_wrap(ContentText.text("challenge", id, str(cfg.text)), width - 32, 13)
		for n in mini(3, details.size()): MathArt.ui_text(c, rect.position + Vector2(16, 128 + n * 19), details[n], 13)
		MathArt.line(c, rect.position + Vector2(16, 178), rect.position + Vector2(width - 16, 178), MathArt.STONE, 1)
		MathArt.ui_text(c, rect.position + Vector2(16, 209), ContentText.of("UI_COLLECTOR_REWARD", "{gold} Gold + {cells} Cells").format({"gold": int(cfg.gold), "cells": int(cfg.cells)}), 20, MathArt.GOLD)
		MathArt.ui_text(c, rect.position + Vector2(16, 230), ContentText.of("UI_S6_CHALLENGE_SAVED", "Saved to this run / cannot be claimed twice") if claimed else (ContentText.of("UI_COLLECTOR_CLAIM_ONCE", "{action} to claim once").format({"action": Interface.prompt(&"ui_accept")}) if ready else ContentText.of("UI_COLLECTOR_REQUIREMENT", "Requirement not met on this visit")), 11, MathArt.LIGHT_DIM)

func _draw_blueprint_icon(id: String, at: Vector2, radius: float, tone: Color) -> void:
	var cfg: Dictionary = Data.passage.blueprints[id]
	if cfg.kind == "gear":
		MathArt.ui_gear(_canvas, at, str(Data.gear.items[cfg.target].get("action", "amulet")), radius, MathArt.axis_color(str(Data.gear.items[cfg.target].get("attribute", "survival"))) if tone != MathArt.LIGHT_DIM else tone, str(cfg.target))
	else:
		var target := str(cfg.target)
		var shade := tone if tone == MathArt.LIGHT_DIM else _mutation_tone(target)
		MathArt.ui_mutation(_canvas, at, target, radius, shade)

func _draw_blueprint(id: String) -> void:
	var c := _canvas
	var cfg: Dictionary = Data.passage.blueprints[id]
	var invested := int(Profile.blueprint_cells.get(id, 0))
	var complete := invested >= int(cfg.cost)
	var carried := Game.carried_blueprints.has(id)
	var delivered := Profile.delivered_blueprints.has(id)
	var blueprint_name := ContentText.name("blueprint", id, str(cfg.name))
	MathArt.ui_text(c, Vector2(328, 127), ContentText.of("UI_COLLECTOR_BLUEPRINT_WEAPON", "PERMANENT / WEAPON") if cfg.kind == "gear" else ContentText.of("UI_COLLECTOR_BLUEPRINT_MUTATION", "PERMANENT / MUTATION"), 11, MathArt.LIGHT_DIM)
	_draw_blueprint_icon(id, Vector2(390, 190), 42, MathArt.WHITE if complete or carried or delivered else MathArt.LIGHT_DIM)
	var names := MathArt.ui_wrap(blueprint_name, 250, 16)
	for i in mini(2, names.size()):
		MathArt.ui_text(c, Vector2(450, 158 + i * MathArt.ui_line_height(16)), names[i] + ("…" if i == 1 and names.size() > 2 else ""), 16, MathArt.WHITE)
	var description := ContentText.of("UI_COLLECTOR_BLUEPRINT_UNLOCK_GEAR", "Unlocks this weapon in future loot.") if cfg.kind == "gear" else ContentText.of("UI_COLLECTOR_BLUEPRINT_UNLOCK_MUTATION", "Unlocks this Mutation for future runs.")
	# Purpose first: what the object does in play, then the acquisition route.
	# Names longer than two lines stay in the same scrollable copy block.
	var purpose := _blueprint_purpose(id)
	var details := MathArt.ui_wrap((blueprint_name + "\n" if names.size() > 2 else "") + purpose + "\n" + description, 250, 12)
	_detail_count = details.size()
	var detail_pitch := MathArt.ui_line_height(12)
	for i in range(_detail_scroll, mini(details.size(), _detail_scroll + 3)):
		MathArt.ui_text(c, Vector2(450, 202 + (i - _detail_scroll) * detail_pitch), details[i], 12)
	MathArt.line(c, Vector2(390, 235), Vector2(390, 260), MathArt.STONE_HI, 1)
	MathArt.px_rect(c, Rect2(328, 260, 372, 8), MathArt.STONE_DIM)
	MathArt.px_rect(c, Rect2(328, 260, 372 * clampf(float(invested) / float(cfg.cost), 0, 1), 8), MathArt.CELL)
	MathArt.ui_text(c, Vector2(328, 294), ContentText.of("UI_PRICE_PROGRESS_CELLS_SLASH", "{have} / {need} Cells").format({"have": invested, "need": int(cfg.cost)}), 22, MathArt.CELL)
	var price := ContentText.of("UI_COLLECTOR_PRICE_UNLOCKED", "Unlocked · future runs") if complete else (ContentText.of("UI_COLLECTOR_PRICE_FREE", "Deliver blueprint · Free") if carried else (ContentText.of("UI_COLLECTOR_INVEST_NOW", "Invest {amount} Cells now").format({"amount": Game.blueprint_investment(id, int(Data.passage.investment_step))}) if delivered and Game.run_cells > 0 else (ContentText.of("UI_COLLECTOR_NO_CELLS", "No Cells to invest") if delivered else ContentText.of("UI_COLLECTOR_NOT_DELIVERED", "Blueprint not delivered"))))
	MathArt.ui_text(c, Vector2(328, 318), price, 13, MathArt.WHITE)
	# Real next step, not the row's status token: it names the exact action and
	# the Cells still missing at this checkpoint.
	var next_step := MathArt.ui_wrap(_blueprint_next_step(id, invested, complete, carried, delivered), 372, 11)
	for i in mini(2, next_step.size()):
		MathArt.ui_text(c, Vector2(328, 340 + i * MathArt.ui_line_height(11)), next_step[i], 11, MathArt.PALE)
	if _detail_count > 3:
		MathArt.ui_text(c, Vector2(60, 335), ContentText.of("UI_COLLECTOR_DETAILS_HINT", "{scroll} Details {index} / {count}").format({"scroll": _scroll_prompt(), "index": _detail_scroll + 1, "count": _detail_count}), 11)


## The scroll hint must advertise only what that device can actually do:
## keyboard uses A/D; the pad uses D-pad left/right and the right stick.
func _scroll_prompt() -> String:
	var actions: Array = [&"ui_nav_left", &"ui_nav_right"]
	if Interface.active_device == Interface.DEVICE_GAMEPAD:
		actions.append(&"ui_detail_up")
	return _key_labels(actions)


## One prompt per distinct label: keyboard shows "A D", pad shows "D-pad".
func _key_labels(actions: Array) -> String:
	var parts: Array[String] = []
	for action in actions:
		var label := Interface.prompt(StringName(action))
		if label.is_empty() or label == "—":
			continue
		if not parts.has(label):
			parts.append(label)
	return " ".join(parts) if not parts.is_empty() else "—"
