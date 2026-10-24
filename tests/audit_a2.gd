extends Node
## AUDIT A2 — meta economy + persistence probe.
## Round trip, economy edges, selection integrity, progression loop, corrupt saves.
## Leaves a clean profile behind: Profile.reset_profile() at the end.

var _fails := 0
var _checks := 0


func _ready() -> void:
	Profile.reset_profile()

	_t1_round_trip()
	_t2_economy()
	_t3_selection()
	_t4_progression()
	_t5_corrupt()

	Profile.reset_profile()
	print("")
	print("AUDIT A2 %s (%d checks, %d failures)" % [
		"OK" if _fails == 0 else "FAILED", _checks, _fails])
	# One frame lets the tree finish starting before exit, so the run is leak-free.
	await get_tree().process_frame
	get_tree().quit()


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("A2 FAIL: ", msg)


func _eq(a: Variant, b: Variant, msg: String) -> void:
	_check(a == b, "%s (got %s, want %s)" % [msg, str(a), str(b)])


func _is_int(v: Variant, msg: String) -> void:
	_check(typeof(v) == TYPE_INT, "%s is %s, not int" % [msg, type_string(typeof(v))])


# ---------------------------------------------------------------- 1. round trip

func _t1_round_trip() -> void:
	Profile.reset_profile()
	Profile.cells = 137
	Profile.souls = 4
	Profile.upgrades = {"vitality": 3, "edge": 2, "greed": 1}
	Profile.skill_nodes = ["root_edge", "edge_ii"]
	Profile.seen_enemies = ["grunt", "archer"]
	Profile.seen_weapons = ["rusty_sword", "arc_saber"]
	Profile.seen_armor = ["none", "plate"]
	Profile.unlocked_characters = ["square", "octa"]
	Profile.unlocked_weapons = ["rusty_sword", "arc_saber"]
	Profile.unlocked_armor = ["none", "plate"]
	Profile.selected_character = "octa"
	Profile.selected_weapon = "arc_saber"
	Profile.selected_armor = "plate"
	Profile.best_floor = 3
	Profile.total_kills = 88
	Profile.deaths = 5
	Profile.runs = 9
	Profile.victories = 1
	Profile.save()

	# Wipe every field in memory, then load from disk.
	Profile.cells = -1
	Profile.souls = -1
	Profile.upgrades = {}
	Profile.skill_nodes = []
	Profile.seen_enemies = []
	Profile.seen_weapons = []
	Profile.seen_armor = []
	Profile.unlocked_characters = []
	Profile.unlocked_weapons = []
	Profile.unlocked_armor = []
	Profile.selected_character = "x"
	Profile.selected_weapon = "x"
	Profile.selected_armor = "x"
	Profile.best_floor = -1
	Profile.total_kills = -1
	Profile.deaths = -1
	Profile.runs = -1
	Profile.victories = -1
	Profile.load_profile(true)

	_eq(Profile.cells, 137, "cells round trip")
	_is_int(Profile.cells, "cells type")
	_eq(Profile.souls, 4, "souls round trip")
	_is_int(Profile.souls, "souls type")
	_eq(Profile.upgrades.get("vitality", -1), 3, "upgrades.vitality round trip")
	_is_int(Profile.upgrades.get("vitality", 0.0), "upgrades.vitality type")
	_eq(Profile.upgrades.get("edge", -1), 2, "upgrades.edge round trip")
	_eq(Profile.upgrades.get("greed", -1), 1, "upgrades.greed round trip")
	_eq(Profile.upgrade_level("vitality"), 3, "upgrade_level after load")
	_eq(Profile.skill_nodes, ["root_edge", "edge_ii"], "skill_nodes round trip")
	_eq(Profile.seen_enemies, ["grunt", "archer"], "seen_enemies round trip")
	_eq(Profile.seen_weapons, ["rusty_sword", "arc_saber"], "seen_weapons round trip")
	_eq(Profile.seen_armor, ["none", "plate"], "seen_armor round trip")
	_eq(Profile.unlocked_characters, ["square", "octa"], "unlocked_characters round trip")
	_eq(Profile.unlocked_weapons, ["rusty_sword", "arc_saber"], "unlocked_weapons round trip")
	_eq(Profile.unlocked_armor, ["none", "plate"], "unlocked_armor round trip")
	_eq(Profile.selected_character, "octa", "selected_character round trip")
	_eq(Profile.selected_weapon, "arc_saber", "selected_weapon round trip")
	_eq(Profile.selected_armor, "plate", "selected_armor round trip")
	_eq(Profile.best_floor, 3, "best_floor round trip")
	_is_int(Profile.best_floor, "best_floor type")
	_eq(Profile.total_kills, 88, "total_kills round trip")
	_is_int(Profile.total_kills, "total_kills type")
	_eq(Profile.deaths, 5, "deaths round trip")
	_eq(Profile.runs, 9, "runs round trip")
	_eq(Profile.victories, 1, "victories round trip")

	# Typed-array identity matters: gameplay code calls .has() and appends.
	for pair in [["skill_nodes", Profile.skill_nodes], ["seen_enemies", Profile.seen_enemies],
			["unlocked_weapons", Profile.unlocked_weapons]]:
		var arr: Variant = pair[1]
		_check(typeof(arr) == TYPE_ARRAY, "%s is an array" % pair[0])
		if typeof(arr) == TYPE_ARRAY and not (arr as Array).is_empty():
			_check(typeof((arr as Array)[0]) == TYPE_STRING,
				"%s elements are strings" % pair[0])


# ------------------------------------------------------------------ 2. economy

func _t2_economy() -> void:
	Profile.reset_profile()

	# Spend more than you have: false, nothing changes.
	Profile.cells = 50
	var before := Profile.cells
	_check(not Profile.spend(51), "overspend refused")
	_eq(Profile.cells, before, "overspend left cells untouched")
	_check(Profile.spend(50), "exact spend accepted")
	_eq(Profile.cells, 0, "exact spend emptied the bank")

	# Upgrade cost curve.
	var last := -1
	for level in Profile.upgrade_max("vitality"):
		Profile.upgrades["vitality"] = level
		var cost := Profile.upgrade_cost("vitality")
		_check(cost > last, "vitality cost rises at lv %d (%d)" % [level, cost])
		last = cost
	Profile.upgrades["vitality"] = Profile.upgrade_max("vitality")
	_eq(Profile.upgrade_cost("vitality"), -1, "maxed vitality cost is -1")
	_eq(Profile.upgrade_cost("no_such_upgrade"), -1, "unknown upgrade cost is -1")

	# Buying at max is refused and costs nothing.
	Profile.cells = 10000
	var wallet := Profile.cells
	_check(not Profile.buy_upgrade("vitality"), "buy at max refused")
	_eq(Profile.cells, wallet, "buy at max spent nothing")
	_eq(Profile.upgrade_level("vitality"), Profile.upgrade_max("vitality"),
		"buy at max did not over-level")

	# add_upgrade clamps.
	Profile.reset_profile()
	Profile.add_upgrade("vitality", 99)
	_eq(Profile.upgrade_level("vitality"), 5, "add_upgrade clamps to max")
	Profile.add_upgrade("vitality", -99)
	_eq(Profile.upgrade_level("vitality"), 0, "add_upgrade clamps to zero")

	# The soul sink: attribute upgrades are priced in souls, never in cells.
	Profile.reset_profile()
	_check(not Data.upgrades.get("brutality", {}).is_empty(),
		"data/upgrades.json has no soul-priced brutality row")
	_eq(Profile.upgrade_currency("brutality"), "souls", "brutality is priced in souls")
	_eq(Profile.upgrade_currency("vitality"), "cells", "vitality is priced in cells")
	Profile.cells = 500
	Profile.souls = 0
	_check(not Profile.can_afford_upgrade("brutality"), "0 souls can afford brutality")
	_check(not Profile.buy_upgrade("brutality"), "bought brutality with no souls")
	_eq(Profile.cells, 500, "a refused soul purchase spent cells")
	Profile.souls = 3
	var soul_cost := Profile.upgrade_cost("brutality")
	_eq(soul_cost, 1, "first brutality level costs 1 soul")
	_check(Profile.buy_upgrade("brutality"), "could not buy brutality with 3 souls")
	_eq(Profile.souls, 3 - soul_cost, "souls were not spent")
	_eq(Profile.cells, 500, "a soul purchase spent cells")
	_eq(Profile.upgrade_level("brutality"), 1, "brutality level did not rise")
	_eq(Profile.bonus("brutality"), 1.0, "bonus(brutality) does not follow the level")
	_eq(Profile.upgrade_cost("brutality"), 2, "the soul cost curve is flat")
	Profile.reset_profile()

	# bonus() aggregates upgrades AND skill nodes for the same stat.
	Profile.reset_profile()
	Profile.upgrades = {"vitality": 2, "edge": 1}
	Profile.skill_nodes = ["root_vit", "root_edge", "edge_ii"]
	_eq(Profile.bonus("hp"), 16.0 + 10.0, "bonus(hp) sums upgrade + node")
	_check(absf(Profile.bonus("damage") - (0.04 + 0.06 + 0.08)) < 0.0001,
		"bonus(damage) sums upgrade + nodes (got %f)" % Profile.bonus("damage"))

	# unlock(): already owned and unknown ids are refused.
	Profile.reset_profile()
	_check(not Profile.unlock("character", "square"), "unlock owned id refused")
	_check(not Profile.unlock("character", "not_a_character"), "unlock unknown id refused")
	_check(not Profile.unlock("weapon", "not_a_weapon"), "unlock unknown weapon refused")
	_check(not Profile.unlock("bogus", "square"), "unlock unknown kind refused")
	_eq(Profile.unlocked_characters, ["square"], "failed unlocks changed nothing")

	# A real unlock charges the documented price once.
	Profile.cells = 500
	var price := int(Data.weapons["arc_saber"].get("unlock_cost", 0))
	_check(Profile.unlock("weapon", "arc_saber"), "unlock arc_saber")
	_eq(Profile.cells, 500 - price, "unlock charged unlock_cost")
	_check(not Profile.unlock("weapon", "arc_saber"), "second unlock refused")
	_eq(Profile.cells, 500 - price, "second unlock spent nothing")


# ---------------------------------------------------------------- 3. selection

func _t3_selection() -> void:
	Profile.reset_profile()
	Profile.cells = 5000
	Profile.select("character", "octa")
	_eq(Profile.selected_character, "square", "locked character cannot be selected")
	Profile.select("weapon", "nope")
	_eq(Profile.selected_weapon, "rusty_sword", "unknown weapon cannot be selected")
	Profile.unlock("character", "octa")
	Profile.select("character", "octa")
	_eq(Profile.selected_character, "octa", "unlocked character can be selected")

	# A save whose selection no longer exists must sanitise.
	_write_save({
		"cells": 10,
		"unlocked_characters": ["square"],
		"unlocked_weapons": ["rusty_sword", "ghost_blade"],
		"unlocked_armor": ["none"],
		"selected_character": "square",
		"selected_weapon": "ghost_blade",
		"selected_armor": "none",
	})
	Profile.load_profile(true)
	_check(Data.weapons.has(Profile.selected_weapon),
		"stale selected_weapon sanitised to an existing weapon (got %s)"
			% Profile.selected_weapon)
	_check(Profile.unlocked_weapons.has(Profile.selected_weapon),
		"sanitised weapon is still unlocked")
	_check(not Profile.unlocked_weapons.has("ghost_blade"),
		"unknown weapon dropped from unlocked list")

	# Same for character/armour ids that no longer exist in data.
	_write_save({
		"unlocked_characters": ["ghost_body"],
		"unlocked_weapons": ["ghost_blade"],
		"unlocked_armor": ["ghost_shell"],
		"selected_character": "ghost_body",
		"selected_weapon": "ghost_blade",
		"selected_armor": "ghost_shell",
	})
	Profile.load_profile(true)
	_check(Data.characters.has(Profile.selected_character),
		"stale selected_character sanitised (got %s)" % Profile.selected_character)
	_check(Data.weapons.has(Profile.selected_weapon),
		"stale selected_weapon sanitised (got %s)" % Profile.selected_weapon)
	_check(Data.armor.has(Profile.selected_armor),
		"stale selected_armor sanitised (got %s)" % Profile.selected_armor)

	# A save with an empty unlock list must still yield a playable loadout.
	_write_save({"unlocked_characters": [], "unlocked_weapons": [], "unlocked_armor": []})
	Profile.load_profile(true)
	_check(Data.characters.has(Profile.selected_character), "empty unlocks -> valid character")
	_check(Data.weapons.has(Profile.selected_weapon), "empty unlocks -> valid weapon")
	_check(Data.armor.has(Profile.selected_armor), "empty unlocks -> valid armor")


# --------------------------------------------------------------- 4. progression

func _t4_progression() -> void:
	Profile.reset_profile()

	# bank -> spend must be lossless.
	Profile.bank(250)
	_eq(Profile.cells, 250, "bank adds")
	Profile.bank(-50)
	_eq(Profile.cells, 250, "negative bank ignored")
	_check(Profile.spend(250), "spend banked")
	_eq(Profile.cells, 0, "bank/spend lossless")
	Profile.bank(10)
	Profile.bank(10)
	_eq(Profile.cells, 20, "repeated banks accumulate")

	# best_floor only ever increases.
	Profile.note_floor_reached(3)
	_eq(Profile.best_floor, 3, "best_floor set")
	Profile.note_floor_reached(1)
	_eq(Profile.best_floor, 3, "best_floor never decreases")
	Profile.note_floor_reached(-4)
	_eq(Profile.best_floor, 3, "best_floor ignores negatives")
	Profile.note_floor_reached(4)
	_eq(Profile.best_floor, 4, "best_floor increases")

	# note_run counts one run exactly once.
	var runs := Profile.runs
	var kills := Profile.total_kills
	var deaths := Profile.deaths
	var wins := Profile.victories
	Profile.note_run(7, true, false)
	_eq(Profile.runs, runs + 1, "note_run counts one run")
	_eq(Profile.total_kills, kills + 7, "note_run adds kills once")
	_eq(Profile.deaths, deaths + 1, "note_run counts a death")
	_eq(Profile.victories, wins, "loss is not a victory")
	Profile.note_run(-3, false, true)
	_eq(Profile.total_kills, kills + 7, "negative kills ignored")
	_eq(Profile.victories, wins + 1, "note_run counts a victory")
	_eq(Profile.deaths, deaths + 1, "victory is not a death")

	# Bookkeeping survives a save/load cycle (int types included).
	Profile.save()
	_check(FileAccess.file_exists(Profile.SAVE_PATH), "save wrote the profile")
	_check(not FileAccess.file_exists(Profile.SAVE_PATH + ".tmp"), "save left no temp file")
	Profile.load_profile(true)
	_eq(Profile.runs, runs + 2, "runs persisted")
	_is_int(Profile.runs, "runs type after reload")


# ------------------------------------------------------------- 5. corrupt saves

func _t5_corrupt() -> void:
	# Garbage.
	_write_raw("{ this is not json ]]")
	Profile.load_profile(true)
	_check(Profile.cells == 0 and Profile.runs == 0, "corrupt json falls back to defaults")
	_check(Data.weapons.has(Profile.selected_weapon), "corrupt json yields a valid weapon")

	# Empty file.
	_write_raw("")
	Profile.load_profile(true)
	_eq(Profile.cells, 0, "empty file falls back to defaults")

	# JSON that is not an object.
	_write_raw("[1, 2, 3]")
	Profile.load_profile(true)
	_eq(Profile.cells, 0, "array save falls back to defaults")

	# Partial object.
	_write_raw("{\"cells\": 42}")
	Profile.load_profile(true)
	_eq(Profile.cells, 42, "partial save keeps present fields")
	_eq(Profile.souls, 0, "partial save defaults missing fields")
	_check(Profile.unlocked_weapons.has("rusty_sword"), "partial save has a starting weapon")

	# Right keys, wrong types.
	_write_raw("{\"cells\": \"abc\", \"upgrades\": [1], \"skill_nodes\": 5, " +
		"\"seen_enemies\": {}, \"best_floor\": null, \"selected_weapon\": 7}")
	Profile.load_profile(true)
	_is_int(Profile.cells, "bad cell type coerced to int")
	_eq(Profile.cells, 0, "unparseable cell coerced to 0")
	_eq(typeof(Profile.upgrades), TYPE_DICTIONARY, "bad upgrades coerced to dict")
	_eq(typeof(Profile.skill_nodes), TYPE_ARRAY, "bad skill_nodes coerced to array")
	_eq(typeof(Profile.seen_enemies), TYPE_ARRAY, "bad seen_enemies coerced to array")
	_is_int(Profile.best_floor, "bad best_floor coerced to int")
	_check(Data.weapons.has(Profile.selected_weapon), "numeric selected_weapon sanitised")

	# Upgrades stored as floats (a hand-edited save) must come back as ints.
	_write_raw("{\"cells\": 5, \"upgrades\": {\"vitality\": 3.0, \"edge\": 1.5}}")
	Profile.load_profile(true)
	_is_int(Profile.upgrades.get("vitality", 0.0), "float upgrade level coerced to int")
	_eq(Profile.upgrade_level("edge"), 1, "fractional upgrade level truncated")

	# Unknown upgrade / skill ids in a save must not inflate bonuses or crash.
	_write_raw("{\"upgrades\": {\"ghost_upgrade\": 9}, \"skill_nodes\": [\"ghost_node\"]}")
	Profile.load_profile(true)
	_eq(Profile.bonus("hp"), 0.0, "unknown upgrade id contributes no bonus")
	_eq(Profile.bonus("damage"), 0.0, "unknown skill node contributes no bonus")

	# After a corrupt load the profile must still be writable and re-readable.
	Profile.bank(11)
	Profile.load_profile(true)
	_eq(Profile.cells, 11, "save after corrupt load works")


# -------------------------------------------------------------------- helpers

func _write_raw(text: String) -> void:
	var file := FileAccess.open(Profile.SAVE_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _write_save(data: Dictionary) -> void:
	_write_raw(JSON.stringify(data, "\t"))
