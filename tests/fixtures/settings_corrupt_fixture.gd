extends Node
## Child-process proof for malformed preferences. ConfigFile.parse emits one
## engine ERROR before this scene starts; the parent asserts that exact
## diagnostic, while this fixture proves the consumer outcome: defaults loaded,
## no error state and the damaged bytes retained.

func _ready() -> void:
	var path := OS.get_environment("ASHFALL_SETTINGS_PATH")
	var raw := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var size := int(OS.get_environment("ASHFALL_EXPECT_CORRUPT_SIZE"))
	var ok := raw.length() == size and raw.begins_with("not a config")
	ok = ok and Profile.preferences == Profile.DEFAULT_PREFERENCES
	ok = ok and Profile.last_preferences_error == ""
	ok = ok and TranslationServer.get_locale() == "zh_TW"
	if ok:
		print("CORRUPT SETTINGS OK: defaults loaded, original bytes retained")
	else:
		push_error("CORRUPT SETTINGS FAILED: size=%d stored_locale=%s error=%s" % [
			raw.length(), str(Profile.preferences.get("general", {}).get("locale", "")),
			Profile.last_preferences_error])
	get_tree().quit(0 if ok else 1)
