extends Node
## Child-process proof: a committed locale survives a real engine restart.
## Launched by tests/settings_probe.gd with the same isolated preferences file.

func _ready() -> void:
	var locale_ok := TranslationServer.get_locale() == "en"
	var stored_ok := str(Profile.preferences.get("general", {}).get("locale", "")) == "en"
	var file_ok := FileAccess.file_exists(Profile._settings_path)
	var prompt_ok := not Interface.prompt(&"ui_accept").is_empty()
	var ok := locale_ok and stored_ok and file_ok and prompt_ok
	if ok:
		print("SETTINGS RESTART OK: en locale reloaded from preferences")
	else:
		push_error("SETTINGS RESTART FAILED: locale=%s stored=%s file=%s prompt=%s" % [
			TranslationServer.get_locale(), str(stored_ok), str(file_ok), str(prompt_ok)])
	get_tree().quit(0 if ok else 1)
