extends Node
## Headless data and formula tests.
## Scene mode loads the project autoloads required by MathArt.
##
## Run: godot --headless --path . tests/run_tests.tscn

var _failures := 0
var _checks := 0


func _ready() -> void:
	_test_damage_formula()
	_test_weapon_data()
	_test_enemy_data()
	_test_reward_data()
	_test_math_art()
	_test_timing_sanity()

	print("")
	if _failures == 0:
		print("TESTS OK (%d checks)" % _checks)
	else:
		print("TESTS FAILED (%d/%d checks failed)" % [_failures, _checks])
	get_tree().quit(0 if _failures == 0 else 1)


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
	# The finisher wave is content: it used to be a literal 8.0 in player.gd, so
	# every weapon released an identical wave.
	_check(float(sword.get("wave_damage", 0.0)) > 0.0, "weapon needs wave_damage")
	for id in data:
		_check(float((data[id] as Dictionary).get("wave_damage", 0.0)) > 0.0,
			"%s needs wave_damage" % str(id))


func _test_enemy_data() -> void:
	var data := _read_json("res://data/enemies.json")
	for kind in ["grunt", "archer", "charger", "bulwark", "warden"]:
		var cfg: Dictionary = data.get(kind, {})
		_check(not cfg.is_empty(), "enemies.json needs " + kind)
		_check(float(cfg.get("hp", 0.0)) > 0.0, kind + " needs hp")
		_check(float(cfg.get("damage", 0.0)) > 0.0, kind + " needs damage")
		_check(float(cfg.get("windup", 0.0)) > 0.0, kind + " needs a telegraph windup")
		_check(float(cfg.get("active", 0.0)) > 0.0, kind + " needs an active window")
		_check(float(cfg.get("recovery", 0.0)) > 0.0, kind + " needs recovery")
		_check(float(cfg.get("body_radius", 0.0)) > 0.0, kind + " needs a collision radius")
		_check(float(cfg.get("body_height", 0.0)) >= float(cfg.get("body_radius", 0.0)) * 2.0, kind + " capsule is too short")
	_check(bool(data.get("bulwark", {}).get("shield", false)), "bulwark needs the shield flag")
	var warden: Dictionary = data.get("warden", {})
	_check(bool(warden.get("boss", false)), "warden needs the boss flag")
	_check(float(warden.get("shockwave_damage", 0.0)) > 0.0, "warden needs shockwave damage")
	_check(float(warden.get("shockwave_speed", 0.0)) > 0.0, "warden needs shockwave speed")


func _test_reward_data() -> void:
	var data := _read_json("res://data/rewards.json")
	_check(data.size() >= 7, "rewards.json should offer at least 7 boons")
	for id in data:
		var cfg: Dictionary = data[id]
		_check(not str(cfg.get("name", "")).is_empty(), id + " reward needs a name")
		_check(not str(cfg.get("desc", "")).is_empty(), id + " reward needs a description")
		var tint := str(cfg.get("color", ""))
		_check(tint.begins_with("#") and tint.length() == 7, id + " reward needs a hex color")


func _test_math_art() -> void:
	# The art language is numeric; guard the constants that the visuals rely on.
	_check(absf(MathArt.PHI - 1.618033988749895) < 1e-9, "PHI must be the golden ratio")
	_check(absf(MathArt.INV_PHI - (MathArt.PHI - 1.0)) < 1e-9, "INV_PHI must be 1/PHI")
	_check(absf(MathArt.GOLDEN_ANGLE - 2.399963229728653) < 1e-9, "golden angle must be 2.399963...")
	_check(MathArt.fibonacci(0) == 0 and MathArt.fibonacci(1) == 1, "fibonacci base case")
	_check(MathArt.fibonacci(10) == 55, "fibonacci(10) must be 55")
	var hexagon := MathArt.ngon(6, 10.0)
	_check(hexagon.size() == 6, "ngon must return the requested sides")
	for point in hexagon:
		_check(absf(point.length() - 10.0) < 0.001, "ngon points must sit on the radius")
	var star := MathArt.star(5, 20.0, 8.0)
	_check(star.size() == 10, "star must alternate outer and inner")
	# Ballistic solver: a shot at a target 200 px right and 100 px up must reach it.
	var origin := Vector2.ZERO
	var target := Vector2(200.0, -100.0)
	var gravity := 700.0
	var velocity := MathArt.ballistic_velocity(origin, target, 900.0, gravity)
	var flight := 0.42
	var landed := velocity * flight + Vector2(0.0, 0.5 * gravity * flight * flight)
	# Solve for the actual flight time to x = 200 and check the height there.
	var t_hit := 200.0 / velocity.x
	var y_at := velocity.y * t_hit + 0.5 * gravity * t_hit * t_hit
	_check(absf(y_at - (-100.0)) < 0.5, "ballistic solver should hit the target height")
	_check(absf(velocity.length() - 900.0) < 0.5, "ballistic solver should preserve speed")


func _test_timing_sanity() -> void:
	# Feel guards: these are not laws, but they catch accidental 2x timing edits.
	var data := _read_json("res://data/weapons.json")
	var combo: Array = data.get("rusty_sword", {}).get("combo", [])
	for step in combo:
		var total := float(step.get("windup", 0.0)) + float(step.get("active", 0.0)) + float(step.get("recovery", 0.0))
		_check(total >= 0.20 and total <= 0.60, "attack total should stay between 200 and 600 ms")
