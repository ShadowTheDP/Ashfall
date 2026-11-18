extends Node
## Exercise equivalent CLI paths without touching the live Profile.
var _checks := 0
var _fails := 0


func _ready() -> void:
	if not Profile.require_test_profile():
		get_tree().quit(1)
		return
	var project := ProjectSettings.globalize_path("res://")
	for path in ["tests/esc_probe.tscn", "res://tests/esc_probe.tscn", ".\\tests\\esc_probe.tscn",
			project.path_join("tests/esc_probe.tscn"), "res://tests/../tests/esc_probe.tscn",
			"res://tests/run_tests.tscn"]:
		_check(Profile._is_test_path(path), "recognizes project test: " + path)
	for path in ["scenes/main.tscn", "res://tests/../scenes/main.tscn",
			"tests_other/esc_probe.tscn", "C:/elsewhere/tests/esc_probe.tscn", "tests/readme.txt"]:
		_check(not Profile._is_test_path(path), "rejects non-test: " + path)
	Profile.reset_profile()
	Profile.bank(47)
	Profile.load_profile(true)
	_check(Profile.cells == 47, "isolated reset and write survive reload")
	_check_formal_preferences_guard()
	_check_relative_settings_adjacency()
	print("ISOLATED PROFILE: ", Profile.SAVE_PATH)
	print("PROFILE SAFETY %s: %d checks, %d failures" % ["OK" if _fails == 0 else "FAILED", _checks, _fails])
	get_tree().quit(1 if _fails else 0)


## Ordered by profile_path_probe: the progress path is isolated but the
## preferences path is the real player file. The settings guard must refuse
## that file and stay independent of the progress writer's lock.
func _check_formal_preferences_guard() -> void:
	if OS.get_environment("ASHFALL_EXPECT_FORMAL_PREFERENCES") != "1":
		return
	_check(Profile.last_preferences_error == "TEST PREFERENCES ARE NOT ISOLATED", "the formal preferences path is refused before reading")
	_check(Profile.preferences == Profile.DEFAULT_PREFERENCES, "a refused preferences read leaves shipping defaults")
	Profile.bank(23)
	_check(Profile.save(), "the progress writer stays usable after the preferences guard")
	Profile.load_profile(true)
	_check(Profile.cells == 70, "refused preferences never replace the saved progress")
	_check(not Profile._save_blocked, "the preferences guard leaves progress writes unlocked")
	print("FORMAL PREFERENCES GUARD OK: progress writer usable")


## Ordered by profile_path_probe with a bare relative ASHFALL_PROFILE_PATH: the
## preferences directory must resolve through the same absolute resolver as the
## progress file, never fall through to the live player preferences path.
func _check_relative_settings_adjacency() -> void:
	if OS.get_environment("ASHFALL_EXPECT_RELATIVE_SETTINGS") != "1":
		return
	var profile_absolute := Profile._absolute_path(Profile.SAVE_PATH)
	var adjacent := profile_absolute.get_base_dir().path_join("settings.cfg")
	_check(Profile._absolute_path(Profile._settings_path) == Profile._absolute_path(adjacent),
		"a bare relative profile path keeps preferences adjacent to its resolved file")
	var original := Profile.preferences.duplicate(true)
	var draft := original.duplicate(true)
	draft["audio"]["music"] = 0.25
	_check(Profile.save_preferences(draft), "adjacent preferences save under the relative profile path")
	_check(FileAccess.file_exists(adjacent), "the adjacent settings file exists at the resolved location")
	Profile.preferences = original
	print("RELATIVE SETTINGS OK: adjacent preferences")


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("PROFILE SAFETY FAIL: " + message)
