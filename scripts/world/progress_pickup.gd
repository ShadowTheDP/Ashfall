extends Node2D
## World Rune/key interaction; entering a room never grants progress.
var item_id := ""
var item_type := "rune"


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(Game.player) or Game.run_over or Game.run_phase != "biome" or Game.player.hp <= 0.0:
		return
	var accepted: bool = Interface.pressed(event, &"interact")
	if accepted and Game.player.global_position.distance_to(global_position) <= float(Data.traversal["interact_reach"]):
		get_viewport().set_input_as_handled()
		Game.player.suppress_actions()
		var gained := false
		if item_type == "key":
			if not Game.run_keys.has(item_id):
				Game.run_keys.append(item_id)
				gained = true
		elif item_type == "blueprint":
			if Data.passage.blueprints.has(item_id) and not Game.carried_blueprints.has(item_id) and not Profile.delivered_blueprints.has(item_id):
				Game.carried_blueprints.append(item_id)
				gained = true
		else:
			gained = Profile.unlock_rune(item_id)
			if not gained and not Profile.last_save_error.is_empty():
				# Localized, actionable prefix; the raw diagnostic stays readable.
				# Severity travels beside the text so the HUD can style it.
				Game.announce(ContentText.of("UI_ERR_SAVE_FAILED", "Save failed") + ": " + Profile.last_save_error, 1.8, &"error")
				return
		if gained:
			Game.announce(ContentText.of("UI_WORLD_ACQUIRED", "{item} acquired").format({"item": _item_name().to_upper()}), 1.6)
			Sfx.play("reward", -6)
		else:
			# A taken-everything result still answers; the pickup never vanishes
			# as if the press did nothing.
			Game.announce(ContentText.of(_no_gain_key(), "Cannot take this item right now."), 1.6)
		queue_free()


## Exact condition for an interaction that changed nothing, with the item kind
## as the only difference.
func _no_gain_key() -> String:
	if item_type == "key":
		return "UI_S7_WORLD_ALREADY_KEY"
	if item_type == "blueprint":
		return "UI_S7_WORLD_ALREADY_BLUEPRINT" if Game.carried_blueprints.has(item_id) or Profile.delivered_blueprints.has(item_id) else "UI_S7_WORLD_TAKE_FAILED"
	return "UI_S7_WORLD_ALREADY_RUNE" if Profile.unlocked_runes.has(item_id) else "UI_S7_WORLD_TAKE_FAILED"


func _draw() -> void:
	var spin := Time.get_ticks_msec() / 1600.0
	var tint := MathArt.GOLD if item_type == "key" else (MathArt.CELL if item_type == "blueprint" else MathArt.PICKUP)
	MathArt.poly(self, MathArt.ngon(6 if item_type == "rune" else 4, 12, spin), MathArt.INK, tint, 2)
	MathArt.poly(self, MathArt.ngon(3, 12 * MathArt.INV_PHI, -spin), tint)
	if is_instance_valid(Game.player) and Game.player.global_position.distance_to(global_position) <= float(Data.traversal["interact_reach"]):
		var hint := ContentText.of("UI_WORLD_HINT_TAKE_BLUEPRINT", "{action} take blueprint {item}") if item_type == "blueprint" else ContentText.of("UI_WORLD_HINT_TAKE", "{action} take {item}")
		draw_string(MathArt.ui_font(), Vector2(-140, -30), hint.format({"action": Interface.prompt(&"interact"), "item": _item_name()}), HORIZONTAL_ALIGNMENT_CENTER, 280, 11, MathArt.WHITE)


## The pickup's name: a Rune, a world key or a blueprint, never its id.
func _item_name() -> String:
	if item_type == "blueprint":
		var cfg: Dictionary = Data.passage.blueprints.get(item_id, {})
		return ContentText.name("blueprint", item_id, str(cfg.get("name", item_id)))
	return Level.key_name(item_id) if item_type == "key" else Level.rune_name(item_id)
