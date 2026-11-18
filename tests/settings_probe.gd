extends Node
## STEP 3 preferences probe: first use, bus gains, progress isolation, locale /
## audio cancel, persistence through reset / slot switch / a real restart,
## damaged and invalid files, write failure, rebind mirroring, and the headless
## display-preview state. Every choice and confirmation here is a real
## InputEvent driven through the production input path; the only direct calls
## are the public Profile / Interface APIs a normal page uses.
##
## Opt-in through tools/check.py with a 30 second deadline. The full ten second
## display preview runs once in tests/ui_product_probe.gd, not here.

const RESTART_FIXTURE := "res://tests/fixtures/settings_restart_fixture.tscn"
const CORRUPT_FIXTURE := "res://tests/fixtures/settings_corrupt_fixture.tscn"
const CORRUPT_TEXT := "not a config\n[general\nlocale=zh_TW\n"
const CORRUPT_DIAGNOSTIC := "ERROR: ConfigFile parse error at <string>:2: Unexpected identifier 'zh_TW'."

var _checks := 0
var _fails := 0
var _settings_path := ""
var _pid := OS.get_process_id()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Profile.require_test_profile():
		push_error("SETTINGS PROBE FAIL: isolated test profile required")
		get_tree().quit(1)
		return
	for singleton in [Data, Profile, Interface, Sfx]:
		if not singleton.is_node_ready():
			await singleton.ready
	_settings_path = Profile._settings_path
	_run()
	print("SETTINGS PROBE %s (%d checks, %d failures)" % ["OK" if _fails == 0 else "FAILED", _checks, _fails])
	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)


func _run() -> void:
	_check_missing_first_use()
	Profile.run_checkpoint = {"kind": "entrance", "state": {"run_node_id": str(Data.route_graph.start)}}
	_check(Profile.save(), "the checkpoint fixture is written before the preferences proof")
	var progress := _progress_state()
	_check_audio_and_buses(progress)
	_check_persisted_locale()
	_check_cancel_previews()
	_check_invalid_fields()
	await _check_corrupt_file()
	_check_write_failure()
	_check_rebind_mirroring()
	_check_headless_display_state()
	_check_slot_switch_keeps_settings_path()


# ------------------------------------------------------------------ first use

func _check_missing_first_use() -> void:
	_check(not FileAccess.file_exists(_settings_path), "a missing preferences file is not created on first use")
	_check(TranslationServer.get_locale() == "zh_TW", "first use starts in Traditional Chinese")
	_check(Profile.preferences == Profile.DEFAULT_PREFERENCES, "missing preferences load shipping defaults")
	_check(Profile.last_preferences_error.is_empty(), "missing preferences are not an error")
	_check(Profile._absolute_path(_settings_path) != Profile._absolute_path(Profile._FORMAL_PREFERENCES_PATH),
		"the probe never reads the formal preferences path")


# --------------------------------------------------------------- audio/buses

func _check_audio_and_buses(progress: Dictionary) -> void:
	var draft: Dictionary = Profile.preferences.duplicate(true)
	draft["audio"] = {"master": 0.75, "music": 0.0, "sfx": 0.4}
	_check(Profile.save_preferences(draft), "audio preferences persist")
	_check(FileAccess.file_exists(_settings_path), "the successful apply creates the preferences file")
	var reloaded: Dictionary = Profile.preferences.duplicate(true)
	_check(is_equal_approx(float(reloaded["audio"]["master"]), 0.75), "master gain persists")
	_check(is_equal_approx(float(reloaded["audio"]["music"]), 0.0), "music gain persists")
	_check(is_equal_approx(float(reloaded["audio"]["sfx"]), 0.4), "SFX gain persists")
	Interface.apply_preferences(Profile.preferences)
	var music := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("SFX")
	var master := AudioServer.get_bus_index("Master")
	_check(music >= 0 and sfx >= 0 and master >= 0, "the native Music / SFX / Master buses exist")
	if music >= 0:
		_check(AudioServer.is_bus_mute(music), "a music gain of 0 explicitly mutes the Music bus")
	if sfx >= 0:
		_check(not AudioServer.is_bus_mute(sfx), "a positive SFX gain keeps the SFX bus audible")
		_check(absf(db_to_linear(AudioServer.get_bus_volume_db(sfx)) - 0.4) < 0.02,
			"the SFX bus gain is the committed linear value")
	if master >= 0:
		_check(absf(db_to_linear(AudioServer.get_bus_volume_db(master)) - 0.75) < 0.02,
			"the Master bus gain is the committed linear value")
	_check(progress == _progress_state(), "saving preferences leaves the progress files and checkpoint unchanged")


# -------------------------------------------------------- locale persistence

func _check_persisted_locale() -> void:
	var draft: Dictionary = Profile.preferences.duplicate(true)
	draft["general"]["locale"] = "en"
	_check(Profile.save_preferences(draft), "the English locale persists before a restart")
	Interface.apply_preferences(Profile.preferences)
	_check(TranslationServer.get_locale() == "en", "the committed English locale is live")
	var settings_bytes := _text(_settings_path)
	var path_before := Profile._settings_path

	Profile.reset_profile()
	_check(TranslationServer.get_locale() == "en", "profile reset never clears the committed locale")
	_check(Profile._settings_path == path_before, "profile reset never recomputes the preferences path")
	_check(_text(_settings_path) == settings_bytes, "profile reset never rewrites preferences")

	Game.in_hub = true
	Game.settlement_pending.clear()
	var progress_before := Profile.SAVE_PATH
	_check(Profile.select_slot(2), "a slot switch succeeds for the locale proof")
	_check(TranslationServer.get_locale() == "en", "switching slots keeps the committed locale")
	_check(Profile._settings_path == path_before, "switching slots keeps the preferences path fixed")
	_check(Profile.select_slot(1), "the probe returns to its original slot")
	_check(Profile.SAVE_PATH == progress_before, "the original progress path is restored")
	_check(TranslationServer.get_locale() == "en", "returning slots keeps the committed locale")

	var result := _run_child(RESTART_FIXTURE, {})
	var restart_output := str(result[1])
	_check(int(result[0]) == 0, "a real engine restart reads the saved preferences")
	_check("SETTINGS RESTART OK" in restart_output, "the restarted process starts in English")
	var restart_unexpected := _unexpected_child_errors(restart_output, PackedStringArray())
	_check(restart_unexpected.is_empty(), "the restart fixture emits no engine, script, parse, compile or failure line: %s"
		% " | ".join(restart_unexpected))


func _check_cancel_previews() -> void:
	var committed: Dictionary = Profile.preferences.duplicate(true)
	var settings_bytes := _text(_settings_path)
	var preview: Dictionary = committed.duplicate(true)
	preview["general"]["locale"] = "zh_TW"
	preview["audio"]["music"] = 0.2
	Interface.apply_preferences(preview)
	_check(TranslationServer.get_locale() == "zh_TW", "an unapplied language preview is visible immediately")
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "an unapplied music preview changes the bus")
	_check(Profile.preferences == committed, "previewing never commits the in-memory preferences")
	_check(_text(_settings_path) == settings_bytes, "previewing never writes the preferences file")
	Interface.apply_preferences(committed)
	_check(TranslationServer.get_locale() == "en", "cancelling the language preview restores the committed locale")
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "cancelling restores the committed music mute")

	var reset_preview: Dictionary = Profile.DEFAULT_PREFERENCES.duplicate(true)
	Interface.apply_preferences(reset_preview)
	_check(TranslationServer.get_locale() == "zh_TW", "a default reset previews the default locale")
	Interface.apply_preferences(committed)
	_check(TranslationServer.get_locale() == "en", "cancelling a default reset restores the committed locale")
	_check(Profile.preferences == committed, "cancelling a default reset keeps committed preferences")
	_check(_text(_settings_path) == settings_bytes, "cancelling a default reset keeps the file bytes")


# ------------------------------------------------------------ invalid fields

func _check_invalid_fields() -> void:
	var path := "user://ashfall_fields_%d.cfg" % _pid
	var file := ConfigFile.new()
	file.set_value("general", "locale", "fr")
	file.set_value("audio", "master", NAN)
	file.set_value("audio", "music", -0.5)
	file.set_value("audio", "sfx", 2.0)
	file.set_value("display", "window_mode", "wide")
	file.set_value("display", "vsync", "yes")
	file.set_value("input", "keyboard", {"jump": KEY_C, "not_a_gameplay_action": KEY_F})
	file.set_value("input", "gamepad", {
		"jump": {"type": "button", "index": JOY_BUTTON_MAX},
		"move_left": {"type": "axis", "index": 0, "sign": -1},
	})
	_check(file.save(path) == OK, "the invalid-field fixture is valid ConfigFile syntax")
	var raw := _text(path)
	var saved_path := Profile._settings_path
	Profile._settings_path = path
	Profile.load_preferences()
	Profile._settings_path = saved_path
	_check(Profile.last_preferences_error.is_empty(), "invalid fields are defaults, not a read error")
	_check(str(Profile.preferences["general"]["locale"]) == "zh_TW", "an invalid locale uses zh_TW")
	_check(is_equal_approx(float(Profile.preferences["audio"]["master"]), 1.0), "a NaN gain uses its default")
	_check(is_equal_approx(float(Profile.preferences["audio"]["music"]), 0.0), "an out-of-range gain clamps to 0")
	_check(is_equal_approx(float(Profile.preferences["audio"]["sfx"]), 1.0), "an out-of-range gain clamps to 1")
	_check(str(Profile.preferences["display"]["window_mode"]) == "windowed", "an invalid window mode uses windowed")
	_check(bool(Profile.preferences["display"]["vsync"]), "an invalid vsync value uses the default")
	_check(Profile.preferences["input"]["keyboard"] == {"jump": KEY_C},
		"only the valid gameplay key survives")
	_check(Profile.preferences["input"]["gamepad"].is_empty(), "invalid gamepad bindings are ignored")
	_check(_text(path) == raw, "invalid fields never rewrite the original bytes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Profile.load_preferences()
	_check(str(Profile.preferences["general"]["locale"]) == "en", "the real preferences reload after the field fixture")


func _check_corrupt_file() -> void:
	var path := "user://ashfall_corrupt_%d.cfg" % _pid
	_write(path, CORRUPT_TEXT)
	var result := _run_child(CORRUPT_FIXTURE, {
		"ASHFALL_SETTINGS_PATH": ProjectSettings.globalize_path(path),
		"ASHFALL_EXPECT_CORRUPT_SIZE": str(CORRUPT_TEXT.length()),
	})
	var output := str(result[1])
	_check(int(result[0]) == 0, "a malformed preferences file still boots with defaults")
	_check("CORRUPT SETTINGS OK" in output, "malformed preferences leave defaults and the original bytes intact")
	var parse_errors := 0
	for line in output.split("\n"):
		if line.strip_edges() == CORRUPT_DIAGNOSTIC:
			parse_errors += 1
	_check(parse_errors == 1, "the malformed file emits exactly its known native parse diagnostic")
	var unexpected := _unexpected_child_errors(output, PackedStringArray([CORRUPT_DIAGNOSTIC]))
	_check(unexpected.is_empty(), "the malformed fixture emits no other engine, script, parse, compile or failure line: %s"
		% " | ".join(unexpected))
	_check(_text(path) == CORRUPT_TEXT, "the malformed preferences file is never rewritten")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check_write_failure() -> void:
	var blocker := "user://ashfall_blocker_%d" % _pid
	_write(blocker, "not a directory")
	var saved_path := Profile._settings_path
	var committed: Dictionary = Profile.preferences.duplicate(true)
	var saved_bytes := _text(saved_path)
	var last_save_error := Profile.last_save_error
	var was_blocked := Profile._save_blocked
	var old_fullscreen: bool = Interface._fullscreen_active
	var progress_before := _progress_state()
	Profile._settings_path = blocker + "/settings.cfg"
	var draft: Dictionary = committed.duplicate(true)
	draft["audio"]["music"] = 0.05
	_check(not Profile.save_preferences(draft), "a preferences write into a file path fails")
	_check(Profile.last_preferences_error.begins_with("CANNOT WRITE PREFERENCES:"),
		"the write failure reports its own preferences error")
	_check(Profile.preferences == committed, "a failed write keeps the committed preferences")
	_check(_text(saved_path) == saved_bytes, "a failed write keeps the original preferences bytes")
	_check(Profile.last_save_error == last_save_error, "a failed preferences write never reuses the progress error")
	_check(Profile._save_blocked == was_blocked, "a failed preferences write never locks progress saves")
	_check(progress_before == _progress_state(), "a failed preferences write never changes progress files or checkpoint")
	_check(Interface._fullscreen_active == old_fullscreen, "a failed preferences write never changes the display mode")
	_check(not FileAccess.file_exists(blocker + "/settings.cfg"), "a failed write leaves no partial preferences file")
	Profile._settings_path = saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocker))
	Profile.load_preferences()
	_check(Profile.preferences == committed, "the committed preferences survive the failed write")


# ---------------------------------------------------------------- rebinding

func _check_rebind_mirroring() -> void:
	var rebound: Dictionary = Profile.preferences.duplicate(true)
	rebound["input"] = {
		"keyboard": {"jump": KEY_C},
		"gamepad": {
			"jump": {"type": "button", "index": JOY_BUTTON_A},
			"move_left": {"type": "button", "index": JOY_BUTTON_B},
		},
	}
	_check(Profile.save_preferences(rebound), "a jump rebind persists")
	Interface.apply_preferences(Profile.preferences)
	_check(_has_key("jump", KEY_C), "the jump action takes the new keyboard binding")
	_check(not _has_key("jump", KEY_SPACE) and not _has_key("jump", KEY_W) and not _has_key("jump", KEY_UP),
		"the jump action drops its replaced keyboard defaults")
	_check(_has_key("jump_explicit", KEY_C), "jump_explicit mirrors the keyboard rebind")
	_check(not _has_key("jump_explicit", KEY_W) and not _has_key("jump_explicit", KEY_UP),
		"jump_explicit never receives the W / Up alias")
	_check(_has_button("jump_explicit", JOY_BUTTON_A), "jump_explicit mirrors the gamepad A default")
	_check(_has_button("move_left", JOY_BUTTON_B), "a movement override keeps its new button")
	_check(_has_button("move_left", JOY_BUTTON_DPAD_LEFT), "a movement override preserves the D-pad default")
	_check(_has_axis("move_left", JOY_AXIS_LEFT_X), "a movement override preserves the left stick")

	var defaults: Dictionary = Profile.DEFAULT_PREFERENCES.duplicate(true)
	_check(Profile.save_preferences(defaults), "the default preferences persist again")
	Interface.apply_preferences(Profile.preferences)
	_check(_has_key("jump", KEY_SPACE) and _has_key("jump", KEY_W) and _has_key("jump", KEY_UP),
		"the default jump aliases are restored")
	_check(_has_key("jump_explicit", KEY_SPACE), "jump_explicit restores Space")
	_check(not _has_key("jump_explicit", KEY_W) and not _has_key("jump_explicit", KEY_UP),
		"jump_explicit still excludes the W / Up alias")
	_check(_has_button("jump_explicit", JOY_BUTTON_A), "jump_explicit restores gamepad A")
	_check(TranslationServer.get_locale() == "zh_TW", "default preferences restore the Traditional Chinese locale")


# ------------------------------------------------------------------- display

func _check_headless_display_state() -> void:
	_check(DisplayServer.get_name() == "headless", "this fixture verifies display state without a native window")
	var committed: Dictionary = Profile.preferences.duplicate(true)
	var settings_bytes := _text(_settings_path)
	var preview: Dictionary = committed.duplicate(true)
	preview["display"]["window_mode"] = "fullscreen"
	preview["display"]["vsync"] = false
	Interface.apply_preferences(preview)
	_check(bool(Interface._fullscreen_active), "a fullscreen preview updates the headless display state")
	_check(Profile.preferences == committed, "a display preview never commits preferences")
	_check(_text(_settings_path) == settings_bytes, "a display preview never writes preferences")
	Interface.apply_preferences(committed)
	_check(not bool(Interface._fullscreen_active), "restoring the committed display leaves the preview state")
	_check(Profile.preferences == committed, "restoring the display keeps committed preferences")


func _check_slot_switch_keeps_settings_path() -> void:
	var saved_path := Profile._settings_path
	Game.in_hub = true
	Game.settlement_pending.clear()
	_check(Profile.select_slot(2), "the slot switch for the settings-path proof succeeds")
	_check(Profile._settings_path == saved_path, "the preferences path stays fixed across a slot switch")
	_check(Profile.select_slot(1), "the probe returns to slot one after the settings-path proof")
	_check(Profile._settings_path == saved_path, "returning slots still keeps the preferences path fixed")


# ------------------------------------------------------------------- helpers

func _progress_state() -> Dictionary:
	var state := {"active_slot": Profile.active_slot, "checkpoint": JSON.stringify(Profile.run_checkpoint)}
	for slot in range(1, Profile.SLOT_COUNT + 1):
		state["slot%d" % slot] = _text(Profile.slot_path(slot))
	return state


func _unexpected_child_errors(output: String, allowed: PackedStringArray) -> PackedStringArray:
	var lines := output.split("\n")
	var error_re := RegEx.new()
	error_re.compile("^(?:ERROR:|SCRIPT ERROR\\b|Parse Error\\b|Compile Error\\b|(?:[A-Z0-9_ /-]*\\s)?(?:FAILED\\b|FAIL:))")
	var audio_re := RegEx.new()
	audio_re.compile("^ERROR: ([0-9]+) resources still in use at exit\\.?$")
	var resource_re := RegEx.new()
	resource_re.compile("^Resource still in use: (res://\\S+ \\(AudioStreamWAV\\))$")
	var leaked_re := RegEx.new()
	leaked_re.compile("^Leaked instance: ([^:]+):")
	var audio_line := ""
	var resources: Array[String] = []
	var classes: Array[String] = []
	for raw_line in lines:
		var line: String = raw_line.strip_edges()
		if audio_re.search(line) != null:
			audio_line = line
		var resource_match := resource_re.search(line)
		if resource_match != null:
			resources.append(resource_match.get_string(1))
		var leaked_match := leaked_re.search(line)
		if leaked_match != null:
			classes.append(leaked_match.get_string(1))
	var audio_ok := false
	if not audio_line.is_empty():
		var count := int(audio_re.search(audio_line).get_string(1))
		audio_ok = count > 0 and count == resources.size() and not classes.is_empty()
		for path in resources:
			audio_ok = audio_ok and path.begins_with("res://assets/audio/")
		for kind in classes:
			audio_ok = audio_ok and kind in ["AudioStreamWAV", "AudioStreamPlaybackWAV"]
	var unexpected := PackedStringArray()
	for raw_line in lines:
		var line: String = raw_line.strip_edges()
		if allowed.has(line):
			continue
		if audio_ok and line == audio_line:
			continue
		if error_re.search(line) != null:
			unexpected.append(line)
	return unexpected


func _run_child(scene: String, overrides: Dictionary) -> Array:
	var previous := {}
	var present := {}
	for key in overrides:
		present[key] = OS.has_environment(str(key))
		previous[key] = OS.get_environment(str(key)) if bool(present[key]) else ""
		OS.set_environment(str(key), str(overrides[key]))
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--verbose", "--path", ProjectSettings.globalize_path("res://"), scene,
	]), output, true)
	for key in overrides:
		if bool(present[key]):
			OS.set_environment(str(key), str(previous[key]))
		else:
			OS.unset_environment(str(key))
	var lines := PackedStringArray()
	for line in output:
		lines.append(str(line))
	return [code, "\n".join(lines)]


func _has_key(action: StringName, code: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and int((event as InputEventKey).physical_keycode) == code:
			return true
	return false


func _has_button(action: StringName, index: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and int((event as InputEventJoypadButton).button_index) == index:
			return true
	return false


func _has_axis(action: StringName, axis: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion and int((event as InputEventJoypadMotion).axis) == axis:
			return true
	return false


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(text)
	file.close()


func _text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "<absent>"
	return FileAccess.get_file_as_string(path)


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		return
	_fails += 1
	print("SETTINGS PROBE FAIL: " + message)
	push_error("SETTINGS PROBE FAIL: " + message)
