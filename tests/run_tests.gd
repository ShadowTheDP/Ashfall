extends SceneTree
## Headless data and formula tests. Autoloads are intentionally not required;
## this script reads the same JSON files and the same Damage class the game uses.
##
## Run: godot --headless --path . --script res://tests/run_tests.gd

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_test_damage_formula()
	_test_weapon_data()
	_test_enemy_data()
	_test_timing_sanity()

	print("")
	if _failures == 0:
		print("TESTS OK (%d checks)" % _checks)
	else:
		print("TESTS FAILED (%d/%d checks failed)" % [_failures, _checks])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("TEST FAIL: " + message)
		print("FAIL: ", message)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_check(false, "missing file " + path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_check(typeof(parsed) == TYPE_DICTIONARY, "invalid JSON object " + path)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _test_damage_formula() -> void:
	_check(Damage.compute(10.0, 0, false, 1.7) == 10, "base damage should be 10")
	_check(Damage.compute(10.0, 10, false, 1.7) == 22, "10 brutality should scale to 22")
	_check(Damage.compute(10.0, 0, true, 1.7) == 17, "crit should multiply by 1.7")
	_check(Damage.compute(10.0, 0, false, 1.7, 1.5) == 15, "wave scale should apply")
	_check(Damage.compute(0.1, 0, false, 1.0) == 1, "damage should never round to zero")


func _test_weapon_data() -> void:
	var data := _read_json("res://data/weapons.json")
	var sword: Dictionary = data.get("rusty_sword", {})
	_check(not sword.is_empty(), "weapons.json needs rusty_sword")
	var combo: Array = sword.get("combo", [])
	_check(combo.size() == 3, "rusty_sword should have a 3-hit combo")
	_check(float(sword.get("crit_multiplier", 0.0)) > 1.0, "crit multiplier must exceed 1")
	var previous_damage := -1.0
	for step in combo:
		_check(typeof(step) == TYPE_DICTIONARY, "combo step must be an object")
		var windup := float(step.get("windup", 0.0))
		var active := float(step.get("active", 0.0))
		var recovery := float(step.get("recovery", 0.0))
		var cancel_at := float(step.get("cancel_at", 0.0))
		_check(windup > 0.0 and active > 0.0 and recovery > 0.0, "combo timings must be positive")
		_check(cancel_at > 0.0 and cancel_at < 1.0, "cancel_at is a 0..1 fraction")
		_check(float(step.get("damage", 0.0)) > previous_damage, "combo damage should rise")
		previous_damage = float(step.get("damage", 0.0))
		var size: Array = step.get("size", [])
		_check(size.size() == 2 and float(size[0]) > 0.0, "hitbox size must be a 2D vector")


func _test_enemy_data() -> void:
	var data := _read_json("res://data/enemies.json")
	for kind in ["grunt", "archer", "charger"]:
		var cfg: Dictionary = data.get(kind, {})
		_check(not cfg.is_empty(), "enemies.json needs " + kind)
		_check(float(cfg.get("hp", 0.0)) > 0.0, kind + " needs hp")
		_check(float(cfg.get("damage", 0.0)) > 0.0, kind + " needs damage")
		_check(float(cfg.get("windup", 0.0)) > 0.0, kind + " needs a telegraph windup")
		_check(float(cfg.get("active", 0.0)) > 0.0, kind + " needs an active window")
		_check(float(cfg.get("recovery", 0.0)) > 0.0, kind + " needs recovery")
		_check(float(cfg.get("body_radius", 0.0)) > 0.0, kind + " needs a collision radius")
		_check(float(cfg.get("body_height", 0.0)) >= float(cfg.get("body_radius", 0.0)) * 2.0, kind + " capsule is too short")


func _test_timing_sanity() -> void:
	# Feel guards: these are not laws, but they catch accidental 2x timing edits.
	var data := _read_json("res://data/weapons.json")
	var combo: Array = data.get("rusty_sword", {}).get("combo", [])
	for step in combo:
		var total := float(step.get("windup", 0.0)) + float(step.get("active", 0.0)) + float(step.get("recovery", 0.0))
		_check(total >= 0.20 and total <= 0.60, "attack total should stay between 200 and 600 ms")
