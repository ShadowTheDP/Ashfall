extends Node
## Lossless old/future/corrupt save checks; never loads the live profile.
var _fails := 0
var _checks := 0


func _ready() -> void:
	var base := Profile.SAVE_PATH
	assert(base != "user://ashfall_profile.json")
	for version in [1, 2, 3, 4, 5]:
		Profile.SAVE_PATH = base + ".fixture%d" % version
		var fixture := {"version": version, "cells": 137, "souls": 4,
			"upgrades": {"vitality": 2, "retired_upgrade": 9}, "skill_nodes": ["root_edge", "retired_skill"],
			"unlocked_weapons": ["rusty_sword", "retired_weapon"], "selected_weapon": "retired_weapon",
			"best_floor": 4, "runs": 8, "unknown_nested": {"inventory": [1, {"x": true}]}}
		var raw := JSON.stringify(fixture, "  ")
		fixture = JSON.parse_string(raw)
		_put(raw)
		Profile.load_profile(true)
		_check(_text(Profile.SAVE_PATH + ".v%d.bak" % version) == raw, "byte-exact v%d backup" % version)
		_check(Profile.legacy_snapshot["profile"] == fixture, "full legacy snapshot v%d" % version)
		_check(Profile.cells == 137 and Profile.souls == 4 and Profile.best_floor == 4, "legacy progress retained")
		_check(Profile.seen_biomes.is_empty(), "old saves do not invent biome discovery")
		_check(is_equal_approx(Profile.bonus("hp"), 16.0), "legacy bonuses still active")
		_check(Profile.selected_weapon == "rusty_sword", "active loadout remains valid")
		Profile.save()
		Profile.load_profile(true)
		Profile.bank(3)
		var saved: Dictionary = JSON.parse_string(_text(Profile.SAVE_PATH))
		_check(int(saved["version"]) == Profile.VERSION and int(saved["cells"]) == 140, "new schema writes once")
		_check(saved["unknown_nested"] == fixture["unknown_nested"], "unknown nested fields retained")
		_check(saved["legacy_snapshot"]["profile"] == fixture, "snapshot immutable after load/save")
		_check(_text(Profile.SAVE_PATH + ".v%d.bak" % version) == raw, "backup not replaced")

	for has_legacy in [false, true]:
		Profile.SAVE_PATH = base + ".current%d" % int(has_legacy)
		var fixture := {"version": Profile.VERSION, "upgrades": {"retired_after_v3": 7},
			"skill_nodes": ["retired_skill"], "unlocked_weapons": ["rusty_sword", "retired_weapon"],
			"legacy_snapshot": {"version": 1, "profile": {"cells": 12}} if has_legacy else {}}
		_put(JSON.stringify(fixture))
		Profile.load_profile(true)
		Profile.save()
		Profile.load_profile(true)
		_check(int(Profile.retired_content["upgrades"]["retired_after_v3"]) == 7, "current retired upgrade recoverable")
		_check(Profile.retired_content["skill_nodes"].has("retired_skill") and Profile.retired_content["unlocked_weapons"].has("retired_weapon"), "current retired skills and gear recoverable")
		_check(Profile.legacy_snapshot == JSON.parse_string(JSON.stringify(fixture["legacy_snapshot"])), "old snapshot not replaced by later retired IDs")
		_check(Data.weapons.has(Profile.selected_weapon) and Profile.bonus("hp") == 0.0, "retired IDs do not become active bonuses")

	for conflict in ["", "other corrupt original"]:
		Profile.SAVE_PATH = base + ".conflict%d" % conflict.length()
		var original := "{ unrecoverable until preserved"
		_put(original)
		_put(conflict, ".corrupt.bak")
		Profile.load_profile(true)
		Profile.bank(11)
		_check(_text(Profile.SAVE_PATH + ".corrupt.bak") == conflict, "conflicting backup untouched")
		_check(_text(Profile.SAVE_PATH + ".corrupt.bak." + original.sha256_text().substr(0, 12)) == original, "exact current original protected before replacement")

	Profile.SAVE_PATH = base + ".future"
	var future := JSON.stringify({"version": Profile.VERSION + 1, "cells": 61, "new_field": ["keep"]})
	_put(future)
	Profile.load_profile(true)
	Profile.bank(10)
	Profile.save()
	Profile.reset_profile()
	_check(_text(Profile.SAVE_PATH) == future, "future save cannot be banked, saved or reset")

	Profile.SAVE_PATH = base + ".blocked"
	var raw := "{\"version\":2,\"cells\":72}"
	_put(raw)
	DirAccess.make_dir_absolute(Profile.SAVE_PATH + ".v2.bak")
	Profile.load_profile(true)
	Profile.bank(10)
	_check(_text(Profile.SAVE_PATH) == raw, "failed backup blocks replacement")
	DirAccess.remove_absolute(Profile.SAVE_PATH + ".v2.bak")

	Profile.SAVE_PATH = base + ".corrupt"
	_put("{ broken original")
	Profile.load_profile(true)
	Profile.bank(11)
	_check(_text(Profile.SAVE_PATH + ".corrupt.bak") == "{ broken original", "corrupt original preserved")
	Profile.load_profile(true)
	_check(Profile.cells == 11, "corrupt recovery remains writable")

	Profile.SAVE_PATH = base + ".recovery"
	_put("{\"version\":3,\"cells\":42}", ".tmp")
	Profile.load_profile(true)
	_check(Profile.cells == 42, "missing main recovers completed temp")
	_put("{\"version\":3,\"cells\":99}", ".tmp")
	Profile.load_profile(true)
	_check(Profile.cells == 42, "stale temp cannot replace valid main")
	await _read_denied(base)
	Profile.SAVE_PATH = base
	Profile.load_profile(true)
	print("PROFILE MIGRATION %s (%d checks, %d failures)" % ["OK" if _fails == 0 else "FAILED", _checks, _fails])
	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)


func _read_denied(base: String) -> void:
	if OS.get_name() != "Windows":
		return
	Profile.SAVE_PATH = base + ".read-denied"
	var raw := JSON.stringify({"version": Profile.VERSION, "cells": 137, "unknown": "keep"})
	_put(raw)
	var ready := Profile.SAVE_PATH + ".ready"
	var release := Profile.SAVE_PATH + ".release"
	var python := OS.get_environment("ASHFALL_TEST_PYTHON")
	if python.is_empty():
		python = "python"
	var pid := OS.create_process(python, PackedStringArray([
		ProjectSettings.globalize_path("res://tests/profile_read_lock.py"),
		ProjectSettings.globalize_path(Profile.SAVE_PATH),
		ProjectSettings.globalize_path(ready), ProjectSettings.globalize_path(release)]))
	var deadline := Time.get_ticks_msec() + 3000
	while pid > 0 and not FileAccess.file_exists(ready) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.01).timeout
	_check(pid > 0 and FileAccess.file_exists(ready), "exclusive read-lock fixture starts")
	if FileAccess.file_exists(ready):
		_check(FileAccess.file_exists(Profile.SAVE_PATH), "locked profile still exists")
		Profile.load_profile(true)
		_check(Profile._save_blocked, "unreadable existing profile blocks writes")
	var signal_file := FileAccess.open(release, FileAccess.WRITE)
	if signal_file != null:
		signal_file.close()
	deadline = Time.get_ticks_msec() + 2000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.01).timeout
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	_check(_text(Profile.SAVE_PATH) == raw, "lock release retains original bytes")
	Profile.cells = 999
	_check(not Profile.save(), "writes remain blocked after the lock is released")
	Profile.reset_profile()
	_check(_text(Profile.SAVE_PATH) == raw, "blocked save/reset cannot replace original progress")
	Profile.load_profile(true)
	_check(Profile.cells == 137 and not Profile._save_blocked, "successful reload restores progress and write access")
	_check(Profile.save(), "successful reload permits saving again")
	for path in [Profile.SAVE_PATH, ready, release]:
		DirAccess.remove_absolute(path)


func _put(value: String, suffix := "") -> void:
	var file := FileAccess.open(Profile.SAVE_PATH + suffix, FileAccess.WRITE)
	assert(file != null)
	file.store_string(value)
	file.close()


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("MIGRATION FAIL: " + message)
