extends Node
## Real disk failures must leave permanent purchases and the Collector wallet unchanged.

const COLLECTOR := preload("res://scripts/meta/collector.gd")

class TracedProfile extends "res://scripts/autoload/profile.gd":
	var submissions: Array[Dictionary] = []

	func save(checkpoint: Variant = null) -> bool:
		submissions.append({"cells": cells, "souls": souls, "upgrades": upgrades.duplicate(),
			"skills": skill_nodes.duplicate(), "weapons": unlocked_weapons.duplicate(),
			"characters": unlocked_characters.duplicate(), "armor": unlocked_armor.duplicate()})
		return super.save(checkpoint)

var _checks := 0
var _fails := 0



func _ready() -> void:
	if not Data.is_node_ready():
		await Data.ready
	if not Interface.is_node_ready():
		await Interface.ready
	if not Sfx.is_node_ready():
		await Sfx.ready
	TranslationServer.set_locale("en")
	process_mode = Node.PROCESS_MODE_ALWAYS
	var base := Profile.SAVE_PATH
	assert(base != "user://ashfall_profile.json")
	for failure in ["protected", "open", "commit"]:
		Profile.SAVE_PATH = base + ".purchase"
		_put(Profile.SAVE_PATH, JSON.stringify({"version": 999 if failure == "protected" else Profile.VERSION,
			"cells": 5000, "souls": 5}))
		Profile.load_profile(true)
		var original := FileAccess.get_file_as_bytes(Profile.SAVE_PATH)
		if failure == "open":
			DirAccess.make_dir_absolute(Profile.SAVE_PATH + ".tmp")
		elif failure == "commit":
			Profile.SAVE_PATH = base + ".directory"
			DirAccess.make_dir_absolute(Profile.SAVE_PATH)
		for operation in [["spend", 30], ["buy_upgrade", "vitality"], ["buy_upgrade", "brutality"],
				["buy_skill", "root_edge"], ["unlock", "weapon", "kiss_precision"],
				["unlock", "character", "octa"], ["unlock", "armor", "plate"], ["add_upgrade", "vitality"],
				["unlock_rune", "canopy_rune"]]:
			var before := _state()
			var result: Variant = Profile.callv(operation[0], operation.slice(1))
			_check(result == false, "%s refuses %s" % [failure, operation[0]])
			_check(_state() == before, "%s restores %s wallet and grant" % [failure, operation[0]])
		Game.run_cells = 300
		var before_collector := _state()
		var collector := COLLECTOR.new()
		add_child(collector)
		collector._buy()
		_check(Game.run_cells == 300 and _state() == before_collector, failure + " Collector preserves wallet and grant")
		_check("SAVE" in collector._note and not "PERMANENTLY UNLOCKED" in collector._note, failure + " Collector reports save failure")
		collector.free()
		get_tree().paused = false
		var skill := SkillTree.new()
		add_child(skill)
		skill.open()
		skill._index = skill._ids.find("root_edge")
		skill._buy()
		_check("SAVE FAILED" in skill._note, failure + " skill panel reports persistence error")
		skill.free()
		var archive := ArchiveScreen.new()
		add_child(archive)
		archive.open("weapon")
		archive._index = archive._ids.find("kiss_precision")
		archive._activate()
		_check("SAVE FAILED" in archive._note, failure + " archive reports persistence error")
		archive.free()
		var hub_ui := HubUi.new()
		add_child(hub_ui)
		hub_ui.open_station("upgrade")
		hub_ui._activate({"id": "vitality", "kind": "upgrade"})
		_check(hub_ui._flash > 0.45 and not Profile.last_save_error.is_empty(), failure + " Hub keeps the save failure visible")
		hub_ui.free()
		_check(_state() == before_collector, failure + " UI failures preserve ownership and currency")
		_check(FileAccess.get_file_as_bytes(base + ".purchase") == original, failure + " preserves original save bytes")
		_check(not FileAccess.file_exists(Profile.SAVE_PATH + ".tmp"), failure + " leaves no failed purchase for temp recovery")
		DirAccess.remove_absolute(base + ".purchase")
		DirAccess.remove_absolute(base + ".directory")
		DirAccess.remove_absolute(Profile.SAVE_PATH + ".tmp")
	_successful_purchases(base)
	Profile.SAVE_PATH = base
	Profile.load_profile(true)
	print("PURCHASE %s: %d checks, %d failures" % ["OK" if _fails == 0 else "FAILED", _checks, _fails])
	get_tree().quit(1 if _fails else 0)


func _successful_purchases(base: String) -> void:
	var profile := TracedProfile.new()
	profile.SAVE_PATH = base + ".success"
	for operation in [["buy_upgrade", "vitality"], ["buy_upgrade", "brutality"], ["buy_skill", "root_edge"],
			["unlock", "weapon", "kiss_precision"], ["unlock", "character", "octa"], ["unlock", "armor", "plate"]]:
		_put(profile.SAVE_PATH, JSON.stringify({"version": Profile.VERSION, "cells": 5000, "souls": 5,
			"unknown_nested": {"keep": [1, true]}}))
		profile.load_profile(true)
		profile.submissions.clear()
		var expected_cells := 5000
		var expected_souls := 5
		var field := ""
		var id: String = operation.back()
		match operation[0]:
			"buy_upgrade":
				field = "upgrades"
				if profile.upgrade_currency(id) == "souls":
					expected_souls -= profile.upgrade_cost(id)
				else:
					expected_cells -= profile.upgrade_cost(id)
			"buy_skill":
				field = "skills"
				expected_cells -= int(Data.skill_nodes[id]["cost"])
			"unlock":
				field = {"weapon": "weapons", "character": "characters", "armor": "armor"}[operation[1]]
				var cfg: Dictionary = profile._unlock_table(operation[1])[id]
				expected_cells -= int(cfg.get("cost", cfg.get("unlock_cost", 0)))
		_check(profile.callv(operation[0], operation.slice(1)) == true, "successful " + str(operation))
		_check(profile.submissions.size() == 1, "exactly one complete submission for " + str(operation))
		if profile.submissions.is_empty():
			continue
		var submitted: Dictionary = profile.submissions.back()
		_check(submitted["cells"] == expected_cells and submitted["souls"] == expected_souls and submitted[field].has(id), "single submission contains debit AND grant")
		var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(profile.SAVE_PATH))
		_check(int(disk["cells"]) == expected_cells and int(disk["souls"]) == expected_souls and disk["unknown_nested"] == JSON.parse_string('{"keep": [1, true]}'), "committed wallet and unknown fields preserved")
		profile.load_profile(true)
		_check(profile.upgrade_level(id) == 1 if field == "upgrades" else (profile.has_skill(id) if field == "skills" else profile.is_unlocked(operation[1], id)), "grant survives reload")
		_check(not FileAccess.file_exists(profile.SAVE_PATH + ".tmp"), "successful replace consumes temporary file")
	DirAccess.remove_absolute(profile.SAVE_PATH)
	profile.free()


func _state() -> Dictionary:
	return {"cells": Profile.cells, "souls": Profile.souls, "upgrades": Profile.upgrades.duplicate(true),
		"skills": Profile.skill_nodes.duplicate(), "weapons": Profile.unlocked_weapons.duplicate(),
		"characters": Profile.unlocked_characters.duplicate(), "armor": Profile.unlocked_armor.duplicate(),
		"runes": Profile.unlocked_runes.duplicate()}


func _put(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(text)
	file.close()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("PURCHASE FAIL: " + message)
