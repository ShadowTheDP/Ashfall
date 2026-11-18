extends Node

signal runes_changed
## Persistent profile: banked currency, permanent upgrades, skill nodes,
## archives and unlocks. Saved to `user://ashfall_profile.json`.
##
## This is the ONLY place that reads or writes the save file. Gameplay reads
## permanent progression exclusively through `Profile.bonus()` so a single
## upgrade id can feed several stats without touching combat code.
##
## Settings are a separate `ConfigFile` (`user://ashfall_settings.cfg` by
## default) with their own path, error field and atomic writer. They never
## travel through the progress payload or its protection flags.

var SAVE_PATH := "user://ashfall_profile.json"
const VERSION := 6
const SLOT_COUNT := 3
## Preferences live outside the three progress slots: they survive slot
## switches, deaths, resets and new games, and never enter the checkpoint
## payload. Consumers must `duplicate(true)` this read-only constant.
const DEFAULT_PREFERENCES := {
	"general": {"locale": "zh_TW"},
	"audio": {"master": 1.0, "music": 1.0, "sfx": 1.0},
	"display": {"window_mode": "windowed", "vsync": true},
	"input": {"keyboard": {}, "gamepad": {}},
}
const _FORMAL_PREFERENCES_PATH := "user://ashfall_settings.cfg"
## Keep in sync with Interface.GAMEPLAY_ACTIONS; `jump_explicit` is an
## internal mirror and must never be offered as a user binding.
const _PREFERENCE_ACTIONS := [
	"move_left", "move_right", "drop", "climb_up", "climb_down",
	"map", "jump", "attack", "weapon_two", "throw", "aegis",
	"roll", "pause", "interact", "heal", "restart",
]
const _PREFERENCE_LOCALES := ["zh_TW", "en"]
const _PREFERENCE_WINDOW_MODES := ["windowed", "fullscreen"]
## Triggers are the only axes a user may store; stick directions stay on the
## project defaults. Physical keycodes stop at the special-key block.
const _PREFERENCE_TRIGGER_AXES := [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]
const _PREFERENCE_KEYCODE_MAX := KEY_SPECIAL | 0xFF

var active_slot := 1
var _slot_base := SAVE_PATH
var run_checkpoint: Dictionary = {}
var preferences: Dictionary = DEFAULT_PREFERENCES.duplicate(true)
var last_preferences_error := ""
var _settings_path := ""

var cells := 0
var souls := 0
var upgrades: Dictionary = {}
var skill_nodes: Array[String] = []
var seen_enemies: Array[String] = []
var seen_weapons: Array[String] = []
var seen_armor: Array[String] = []
var unlocked_characters: Array[String] = []
var unlocked_weapons: Array[String] = []
var unlocked_armor: Array[String] = []
var selected_character := "square"
var selected_weapon := "rusty_sword"
var selected_armor := "none"
var best_floor := 0
var total_kills := 0
var deaths := 0
var runs := 0
var victories := 0
var unlocked_runes: Array[String] = []
var seen_biomes: Array[String] = []
var boss_cells_unlocked := 0
var active_bsc := 0
var delivered_blueprints: Array[String] = []
var blueprint_cells: Dictionary = {}
var unlocked_mutations: Array[String] = []
var forge_cells := 0
var legacy_snapshot: Dictionary = {}
var retired_content: Dictionary = {}
var _source_payload: Dictionary = {}
var _save_blocked := false
var _loaded := false
var last_save_error := ""


func _ready() -> void:
	var testing := _test_scene_requested()
	# The preferences path is fixed here, once, from the environment or test
	# scene. It must never be derived from SAVE_PATH, which changes per slot.
	_ensure_settings_path(testing)
	load_preferences()
	var isolated_path := OS.get_environment("ASHFALL_PROFILE_PATH")
	if isolated_path.is_empty() and testing:
		isolated_path = "user://ashfall_test_%d.json" % OS.get_process_id()
	if not isolated_path.is_empty():
		SAVE_PATH = isolated_path
	_slot_base = SAVE_PATH
	if testing and not require_test_profile():
		get_tree().quit(1)
		return
	load_profile()


func _test_scene_requested() -> bool:
	for arg in OS.get_cmdline_args():
		if _is_test_path(str(arg)):
			return true
	return false


func _is_test_path(path: String) -> bool:
	var absolute := _absolute_path(path)
	return absolute.begins_with(_absolute_path("res://tests") + "/") and absolute.get_extension() in ["tscn", "gd"]


func _absolute_path(path: String) -> String:
	path = path.replace("\\", "/")
	if path.begins_with("res://") or path.begins_with("user://"):
		path = ProjectSettings.globalize_path(path)
	elif not path.is_absolute_path():
		path = ProjectSettings.globalize_path("res://").path_join(path)
	path = path.simplify_path().trim_suffix("/")
	return path.to_lower() if OS.get_name() == "Windows" else path


func require_test_profile() -> bool:
	for slot in range(1, SLOT_COUNT + 1):
		var live := "user://ashfall_profile.json" + (".slot%d" % slot if slot > 1 else "")
		if _absolute_path(SAVE_PATH) == _absolute_path(live):
			_save_blocked = true
			last_save_error = "TEST PROFILE IS NOT ISOLATED"
			push_error("Profile: test refused to access the live save")
			return false
	return true


func slot_path(slot: int) -> String:
	return _slot_base + (".slot%d" % slot if slot > 1 else "")


func slot_summary(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path) and FileAccess.file_exists(path + ".tmp"):
		path += ".tmp"
	if not FileAccess.file_exists(path):
		return {"blocked":DirAccess.dir_exists_absolute(path), "label":"UNAVAILABLE" if DirAccess.dir_exists_absolute(path) else "EMPTY"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"blocked":true, "label":"CANNOT READ SAVE"}
	var json := JSON.new()
	var text := file.get_as_text()
	file.close()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"blocked":true, "label":"DAMAGED SAVE / ORIGINAL RETAINED"}
	var d: Dictionary = json.data
	if _to_int(d.get("version", 1)) > VERSION:
		return {"blocked":true, "label":"NEWER VERSION / PROTECTED"}
	var checkpoint: Variant = d.get("run_checkpoint", {})
	if typeof(checkpoint) != TYPE_DICTIONARY:
		return {"blocked":true, "label":"INVALID CHECKPOINT / PROTECTED"}
	var victories := _to_int(d.get("victories", 0))
	var label := "HUB / %d VICTORIES" % victories
	var checkpoint_node_id := ""
	var checkpoint_kind := ""
	if not checkpoint.is_empty():
		checkpoint_kind = str(checkpoint.get("kind", ""))
		var state: Variant = checkpoint.get("state", {})
		label = "CHECKPOINT NEEDS RECOVERY"
		if typeof(state) == TYPE_DICTIONARY:
			checkpoint_node_id = str(state.get("run_node_id", ""))
			label = str(Data.route_graph.nodes.get(checkpoint_node_id, {}).get("name", "UNKNOWN ROUTE")) + (" / PASSAGE" if checkpoint_kind == "passage" else " / ENTRANCE")
	# checkpoint_node_id / checkpoint_kind / victories are display metadata only:
	# label stays the byte-comparable machine value and nothing here is persisted.
	return {"blocked":false, "label":label, "resume":not checkpoint.is_empty(),
		"checkpoint_node_id":checkpoint_node_id, "checkpoint_kind":checkpoint_kind,
		"victories":_to_int(d.get("victories", 0))}


func select_slot(slot: int) -> bool:
	last_save_error = ""
	if slot < 1 or slot > SLOT_COUNT or not Game.in_hub or not Game.settlement_pending.is_empty():
		last_save_error = "RETURN TO TITLE BEFORE SWITCHING SAVES"
		return false
	if slot_summary(slot).blocked:
		last_save_error = str(slot_summary(slot).label)
		return false
	SAVE_PATH = slot_path(slot)
	active_slot = slot
	_apply_defaults()
	load_profile(true)
	return not _save_blocked


# --------------------------------------------------------------- preferences

## Fixed once in `_ready()`: explicit environment override, then beside the
## isolated profile (relative paths resolve against the project first), then a
## PID-isolated direct-test file, then the live file.
func _ensure_settings_path(testing: bool) -> void:
	if not _settings_path.is_empty():
		return
	var explicit := OS.get_environment("ASHFALL_SETTINGS_PATH")
	if not explicit.is_empty():
		_settings_path = explicit
		return
	var profile_path := OS.get_environment("ASHFALL_PROFILE_PATH")
	if not profile_path.is_empty():
		var directory := _absolute_path(profile_path).get_base_dir()
		if not directory.is_empty():
			_settings_path = directory.path_join("settings.cfg")
			return
	_settings_path = ("user://ashfall_test_%d_settings.cfg" % OS.get_process_id()) if testing else _FORMAL_PREFERENCES_PATH


## A direct test scene may never read or write the real player's preferences.
## This guard is independent of the progress save lock and error fields.
func _settings_access_allowed() -> bool:
	if not _test_scene_requested():
		return true
	return _absolute_path(_settings_path) != _absolute_path(_FORMAL_PREFERENCES_PATH)


## Missing file means defaults and no creation; damaged content is reported
## once and left on disk untouched until the player actually applies settings.
func load_preferences() -> void:
	last_preferences_error = ""
	_ensure_settings_path(_test_scene_requested())
	if not _settings_access_allowed():
		preferences = DEFAULT_PREFERENCES.duplicate(true)
		last_preferences_error = "TEST PREFERENCES ARE NOT ISOLATED"
		push_error("Profile: test refused to access the live preferences")
		return
	preferences = DEFAULT_PREFERENCES.duplicate(true)
	if not FileAccess.file_exists(_settings_path):
		return
	var file := FileAccess.open(_settings_path, FileAccess.READ)
	if file == null:
		last_preferences_error = "CANNOT READ PREFERENCES: " + error_string(FileAccess.get_open_error())
		push_warning("Profile: settings file unreadable; defaults loaded and original retained")
		return
	var text := file.get_as_text()
	file.close()
	# Instance parse reports the failure as a return code; the file is never
	# rewritten here, so the original bytes survive a damaged settings file.
	var config := ConfigFile.new()
	if config.parse(text) != OK:
		push_warning("Profile: settings file damaged; defaults loaded and original retained")
		return
	var general_default: Dictionary = DEFAULT_PREFERENCES["general"]
	var audio_default: Dictionary = DEFAULT_PREFERENCES["audio"]
	var display_default: Dictionary = DEFAULT_PREFERENCES["display"]
	var raw := {
		"general": {"locale": config.get_value("general", "locale", general_default["locale"])},
		"audio": {
			"master": config.get_value("audio", "master", audio_default["master"]),
			"music": config.get_value("audio", "music", audio_default["music"]),
			"sfx": config.get_value("audio", "sfx", audio_default["sfx"]),
		},
		"display": {
			"window_mode": config.get_value("display", "window_mode", display_default["window_mode"]),
			"vsync": config.get_value("display", "vsync", display_default["vsync"]),
		},
		"input": {
			"keyboard": config.get_value("input", "keyboard", {}),
			"gamepad": config.get_value("input", "gamepad", {}),
		},
	}
	preferences = _normalize_preferences(raw, true)


## Replaces committed preferences only after the `.tmp` file has been renamed
## over the original. Any failure keeps both the old file and the old values.
func save_preferences(next: Dictionary) -> bool:
	last_preferences_error = ""
	_ensure_settings_path(_test_scene_requested())
	if not _settings_access_allowed():
		last_preferences_error = "TEST PREFERENCES ARE NOT ISOLATED"
		push_error("Profile: test refused to write the live preferences")
		return false
	var normalized := _normalize_preferences(next, false)
	var config := ConfigFile.new()
	config.set_value("general", "locale", normalized["general"]["locale"])
	config.set_value("audio", "master", normalized["audio"]["master"])
	config.set_value("audio", "music", normalized["audio"]["music"])
	config.set_value("audio", "sfx", normalized["audio"]["sfx"])
	config.set_value("display", "window_mode", normalized["display"]["window_mode"])
	config.set_value("display", "vsync", normalized["display"]["vsync"])
	config.set_value("input", "keyboard", normalized["input"]["keyboard"])
	config.set_value("input", "gamepad", normalized["input"]["gamepad"])
	var tmp := _settings_path + ".tmp"
	var err := config.save(tmp)
	if err != OK:
		last_preferences_error = "CANNOT WRITE PREFERENCES: " + error_string(err)
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(tmp)
		push_warning("Profile: cannot write %s; original preferences retained" % tmp)
		return false
	# Rename replaces the target; removing it first would create a data-loss
	# window between the two operations.
	if DirAccess.rename_absolute(tmp, _settings_path) != OK:
		last_preferences_error = "CANNOT COMMIT PREFERENCES"
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(tmp)
		push_warning("Profile: cannot commit %s; original preferences retained" % _settings_path)
		return false
	preferences = normalized
	return true


## One validator for both load and save: sections are defaulted, unknown
## fields and actions are ignored, and every stored value is type-checked.
func _normalize_preferences(source: Dictionary, report: bool) -> Dictionary:
	var out := DEFAULT_PREFERENCES.duplicate(true)
	var general: Variant = source.get("general", {})
	if typeof(general) != TYPE_DICTIONARY:
		_preference_problem(report, "general section is not a dictionary; defaults used")
	else:
		var general_out: Dictionary = out["general"]
		var locale: Variant = (general as Dictionary).get("locale", general_out["locale"])
		if typeof(locale) in [TYPE_STRING, TYPE_STRING_NAME] and str(locale) in _PREFERENCE_LOCALES:
			general_out["locale"] = str(locale)
		else:
			_preference_problem(report, "invalid locale; zh_TW used")
	var audio: Variant = source.get("audio", {})
	if typeof(audio) != TYPE_DICTIONARY:
		_preference_problem(report, "audio section is not a dictionary; defaults used")
	else:
		var audio_out: Dictionary = out["audio"]
		for key in ["master", "music", "sfx"]:
			var value: Variant = (audio as Dictionary).get(key, audio_out[key])
			var number := float(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else NAN
			if is_finite(number):
				audio_out[key] = clampf(number, 0.0, 1.0)
			else:
				_preference_problem(report, "invalid %s volume; default used" % key)
	var display: Variant = source.get("display", {})
	if typeof(display) != TYPE_DICTIONARY:
		_preference_problem(report, "display section is not a dictionary; defaults used")
	else:
		var display_out: Dictionary = out["display"]
		var mode: Variant = (display as Dictionary).get("window_mode", display_out["window_mode"])
		if typeof(mode) in [TYPE_STRING, TYPE_STRING_NAME] and str(mode) in _PREFERENCE_WINDOW_MODES:
			display_out["window_mode"] = str(mode)
		else:
			_preference_problem(report, "invalid window mode; windowed used")
		var vsync: Variant = (display as Dictionary).get("vsync", display_out["vsync"])
		if typeof(vsync) == TYPE_BOOL:
			display_out["vsync"] = bool(vsync)
		else:
			_preference_problem(report, "invalid vsync value; default used")
	var input: Variant = source.get("input", {})
	if typeof(input) != TYPE_DICTIONARY:
		_preference_problem(report, "input section is not a dictionary; defaults used")
		return out
	var keyboard: Variant = (input as Dictionary).get("keyboard", {})
	if typeof(keyboard) != TYPE_DICTIONARY:
		_preference_problem(report, "keyboard overrides are not a dictionary; ignored")
	else:
		var keyboard_out: Dictionary = out["input"]["keyboard"]
		for raw_action in keyboard:
			var action := str(raw_action)
			if not _PREFERENCE_ACTIONS.has(action):
				_preference_problem(report, "unknown keyboard action '%s' ignored" % action)
				continue
			var code: Variant = (keyboard as Dictionary)[raw_action]
			if typeof(code) != TYPE_INT or int(code) <= 0 or int(code) > _PREFERENCE_KEYCODE_MAX:
				_preference_problem(report, "invalid key for '%s' ignored" % action)
				continue
			keyboard_out[action] = int(code)
	var gamepad: Variant = (input as Dictionary).get("gamepad", {})
	if typeof(gamepad) != TYPE_DICTIONARY:
		_preference_problem(report, "gamepad overrides are not a dictionary; ignored")
	else:
		var gamepad_out: Dictionary = out["input"]["gamepad"]
		for raw_action in gamepad:
			var action := str(raw_action)
			if not _PREFERENCE_ACTIONS.has(action):
				_preference_problem(report, "unknown gamepad action '%s' ignored" % action)
				continue
			var binding := _valid_gamepad_binding((gamepad as Dictionary)[raw_action])
			if binding.is_empty():
				_preference_problem(report, "invalid gamepad binding for '%s' ignored" % action)
				continue
			gamepad_out[action] = binding
	return out


func _valid_gamepad_binding(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var data := value as Dictionary
	var kind: Variant = data.get("type", "")
	if typeof(kind) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return {}
	var index_value: Variant = data.get("index", -1)
	if typeof(index_value) != TYPE_INT:
		return {}
	var index := int(index_value)
	if str(kind) == "button":
		if index < 0 or index >= JOY_BUTTON_MAX:
			return {}
		return {"type": "button", "index": index}
	if str(kind) == "axis":
		if index not in _PREFERENCE_TRIGGER_AXES:
			return {}
		var sign_value: Variant = data.get("sign", 0)
		if typeof(sign_value) != TYPE_INT or int(sign_value) != 1:
			return {}
		return {"type": "axis", "index": index, "sign": 1}
	return {}


func _preference_problem(report: bool, message: String) -> void:
	if report:
		push_warning("Profile: " + message)


# ---------------------------------------------------------------- save / load

## Idempotent by default; `force` re-reads the file (tests, future "reload save").
func load_profile(force: bool = false) -> void:
	if _loaded and not force:
		return
	_loaded = true
	_save_blocked = false
	last_save_error = ""
	_source_payload.clear()
	legacy_snapshot.clear()
	run_checkpoint.clear()
	# Older saves could lose the live file between remove and rename; recover
	# their complete temp file instead of starting the player over.
	if not FileAccess.file_exists(SAVE_PATH) and FileAccess.file_exists(SAVE_PATH + ".tmp"):
		if DirAccess.rename_absolute(SAVE_PATH + ".tmp", SAVE_PATH) != OK:
			_apply_defaults()
			_save_blocked = true
			push_warning("Profile: recovery failed; original temp retained and writes disabled")
			return
	if not FileAccess.file_exists(SAVE_PATH):
		_apply_defaults()
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		var read_error := FileAccess.get_open_error()
		_apply_defaults()
		_save_blocked = true
		last_save_error = "CANNOT READ PROFILE: " + error_string(read_error)
		push_warning("Profile: existing save unreadable; writes disabled until a successful reload")
		return
	# JSON.parse_string() pushes an engine ERROR on malformed input; the instance
	# API reports the same failure as a return code, so a bad save stays quiet.
	var json := JSON.new()
	var text := file.get_as_text()
	file.close()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		_apply_defaults()
		_save_blocked = not _preserve_original(text, ".corrupt.bak")
		return
	var d: Dictionary = json.data
	if typeof(d.get("run_checkpoint", {})) != TYPE_DICTIONARY:
		_apply_defaults()
		_save_blocked = true
		last_save_error = "INVALID RUN CHECKPOINT"
		return
	run_checkpoint = d.get("run_checkpoint", {}).duplicate(true)
	_source_payload = d.duplicate(true)
	var source_version := _to_int(d.get("version", 1))
	_save_blocked = source_version > VERSION
	if source_version < VERSION:
		_save_blocked = not _preserve_original(text, ".v%d.bak" % source_version)
		if typeof(d.get("legacy_snapshot")) != TYPE_DICTIONARY:
			d["legacy_snapshot"] = {"version": source_version, "profile": _source_payload.duplicate(true)}
	_migrate_profile(d)
	legacy_snapshot = d.get("legacy_snapshot", {}).duplicate(true) if typeof(d.get("legacy_snapshot")) == TYPE_DICTIONARY else {}
	cells = _to_int(d.get("cells", 0))
	souls = _to_int(d.get("souls", 0))
	upgrades = _to_dict(d.get("upgrades", {}))
	skill_nodes = _to_strings(d.get("skill_nodes", []))
	seen_enemies = _to_strings(d.get("seen_enemies", []))
	seen_weapons = _to_strings(d.get("seen_weapons", []))
	seen_armor = _to_strings(d.get("seen_armor", []))
	unlocked_characters = _to_strings(d.get("unlocked_characters", []))
	unlocked_weapons = _to_strings(d.get("unlocked_weapons", []))
	unlocked_armor = _to_strings(d.get("unlocked_armor", []))
	selected_character = str(d.get("selected_character", "square"))
	selected_weapon = str(d.get("selected_weapon", "rusty_sword"))
	selected_armor = str(d.get("selected_armor", "none"))
	best_floor = _to_int(d.get("best_floor", 0))
	total_kills = _to_int(d.get("total_kills", 0))
	deaths = _to_int(d.get("deaths", 0))
	runs = _to_int(d.get("runs", 0))
	victories = _to_int(d.get("victories", 0))
	unlocked_runes = _to_strings(d.get("unlocked_runes", []))
	seen_biomes = _to_strings(d.get("seen_biomes", []))
	boss_cells_unlocked = _to_int(d.get("boss_cells_unlocked", 0))
	active_bsc = _to_int(d.get("active_bsc", 0))
	delivered_blueprints = _to_strings(d.get("delivered_blueprints", []))
	blueprint_cells = _to_dict(d.get("blueprint_cells", {}))
	unlocked_mutations = _to_strings(d.get("unlocked_mutations", []))
	forge_cells = _to_int(d.get("forge_cells", 0))
	retired_content = d.get("retired_content", {}).duplicate(true) if typeof(d.get("retired_content")) == TYPE_DICTIONARY else {}
	_archive_retired(d)
	_sanitize()


func _preserve_original(text: String, suffix: String) -> bool:
	var path := SAVE_PATH + suffix
	if FileAccess.file_exists(path):
		if FileAccess.get_file_as_string(path) == text:
			return true
		# Keep conflicting/truncated backups; preserve this original separately.
		path += "." + text.sha256_text().substr(0, 12)
		if FileAccess.file_exists(path):
			return FileAccess.get_file_as_string(path) == text
	var tmp := path + ".tmp"
	var original := FileAccess.open(tmp, FileAccess.WRITE)
	if original == null:
		push_warning("Profile: cannot preserve original save; writes disabled")
		return false
	original.store_string(text)
	original.flush()
	var ok := original.get_error() == OK
	original.close()
	if not ok or FileAccess.get_file_as_string(tmp) != text:
		return false
	return DirAccess.rename_absolute(tmp, path) == OK


func _archive_retired(data: Dictionary) -> void:
	var archived_upgrades: Variant = retired_content.get("upgrades")
	var old_upgrades: Dictionary = archived_upgrades.duplicate(true) if typeof(archived_upgrades) == TYPE_DICTIONARY else {}
	if typeof(data.get("upgrades")) == TYPE_DICTIONARY:
		for id in data["upgrades"]:
			if not Data.upgrades.is_empty() and not Data.upgrades.has(id):
				old_upgrades[id] = data["upgrades"][id]
	retired_content["upgrades"] = old_upgrades
	var tables := {"skill_nodes": Data.skill_nodes, "unlocked_weapons": Data.weapons,
		"unlocked_characters": Data.characters, "unlocked_armor": Data.armor,
		"selected_weapon": Data.weapons, "selected_character": Data.characters, "selected_armor": Data.armor}
	for field in tables:
		var archived_value: Variant = retired_content.get(field)
		var archived: Array = archived_value.duplicate(true) if typeof(archived_value) == TYPE_ARRAY else []
		var value: Variant = data.get(field, [])
		var ids: Array = value if typeof(value) == TYPE_ARRAY else [value]
		for id in ids:
			if not (tables[field] as Dictionary).is_empty() and not (tables[field] as Dictionary).has(str(id)) and not archived.has(id):
				archived.append(id)
		retired_content[field] = archived


func _migrate_profile(data: Dictionary) -> void:
	var version := _to_int(data.get("version", 1))
	if version < 2:
		data["unlocked_runes"] = data.get("unlocked_runes", [])
		data["boss_cells_unlocked"] = data.get("boss_cells_unlocked", 0)
		data["active_bsc"] = data.get("active_bsc", 0)
		data["version"] = 2


func _apply_defaults() -> void:
	cells = 0
	souls = 0
	upgrades.clear()
	skill_nodes.clear()
	seen_enemies.clear()
	seen_weapons.clear()
	seen_armor.clear()
	unlocked_characters = ["square"]
	unlocked_weapons = ["rusty_sword"]
	unlocked_armor = ["none"]
	selected_character = "square"
	selected_weapon = "rusty_sword"
	selected_armor = "none"
	best_floor = 0
	total_kills = 0
	deaths = 0
	runs = 0
	victories = 0
	unlocked_runes.clear()
	seen_biomes.clear()
	boss_cells_unlocked = 0
	active_bsc = 0
	delivered_blueprints.clear()
	blueprint_cells.clear()
	unlocked_mutations.clear()
	forge_cells = 0
	legacy_snapshot.clear()
	retired_content.clear()
	run_checkpoint.clear()
	_source_payload.clear()
	_save_blocked = false


func _sanitize() -> void:
	# A save from an older build must never leave the player with a loadout that
	# no longer exists: ids missing from the data tables are dropped first, then
	# every selection is re-checked against what survived.
	upgrades = _pruned_upgrades(upgrades)
	if not Data.skill_nodes.is_empty():
		skill_nodes = skill_nodes.filter(func(id: String) -> bool:
			return Data.skill_nodes.has(id))
	unlocked_characters = _prune_ids("character", unlocked_characters, "square")
	unlocked_weapons = _prune_ids("weapon", unlocked_weapons, "rusty_sword")
	unlocked_armor = _prune_ids("armor", unlocked_armor, "none")
	selected_character = _pick("character", selected_character, unlocked_characters)
	selected_weapon = _pick("weapon", selected_weapon, unlocked_weapons)
	selected_armor = _pick("armor", selected_armor, unlocked_armor)
	boss_cells_unlocked = clampi(boss_cells_unlocked, 0, 5)
	active_bsc = clampi(active_bsc, 0, boss_cells_unlocked)
	# Unknown progression IDs remain archived in place, but never confer eligibility.
	forge_cells = clampi(forge_cells, 0, int(Data.passage.forge.cost))
	for id in blueprint_cells:
		if Data.passage.blueprints.has(id):
			blueprint_cells[id] = clampi(int(blueprint_cells[id]), 0, int(Data.passage.blueprints[id].cost))


func _prune_ids(kind: String, list: Array[String], fallback: String) -> Array[String]:
	var table := _unlock_table(kind)
	var out: Array[String] = []
	for id in list:
		if (table.is_empty() or table.has(id)) and not out.has(id):
			out.append(id)
	if out.is_empty():
		out.append(fallback if table.is_empty() or table.has(fallback) else str(table.keys()[0]))
	return out


func _pick(kind: String, id: String, unlocked: Array[String]) -> String:
	var table := _unlock_table(kind)
	if unlocked.has(id) and (table.is_empty() or table.has(id)):
		return id
	return unlocked[0]


## Levels are clamped to the data max and ids the tables no longer know are
## dropped, so a hand-edited save cannot buy 99 levels of VITALITY.
func _pruned_upgrades(source: Dictionary) -> Dictionary:
	# Same guard the skill table already had: Data._read_json() returns {} when a
	# file is missing or malformed, and pruning against an empty table silently
	# deletes every purchased upgrade - then saves that deletion on the next
	# bank(). A missing data table must never be read as "nothing is valid".
	if Data.upgrades.is_empty():
		return source.duplicate()
	var out := {}
	for id in source:
		var cfg: Dictionary = Data.upgrades.get(id, {})
		if cfg.is_empty():
			continue
		out[id] = clampi(int(source[id]), 0, int(cfg.get("max", 1)))
	return out


func save(checkpoint: Variant = null) -> bool:
	if _test_scene_requested() and not require_test_profile():
		return false
	last_save_error = ""
	if _save_blocked:
		last_save_error = "PROFILE IS PROTECTED"
		push_warning("Profile: writes disabled to protect the existing save")
		return false
	var next_checkpoint: Dictionary = run_checkpoint if checkpoint == null else checkpoint
	var payload := _source_payload.duplicate(true)
	payload.merge({
		"run_checkpoint": next_checkpoint,
		"version": VERSION,
		"cells": cells,
		"souls": souls,
		"upgrades": upgrades,
		"skill_nodes": skill_nodes,
		"seen_enemies": seen_enemies,
		"seen_weapons": seen_weapons,
		"seen_armor": seen_armor,
		"unlocked_characters": unlocked_characters,
		"unlocked_weapons": unlocked_weapons,
		"unlocked_armor": unlocked_armor,
		"selected_character": selected_character,
		"selected_weapon": selected_weapon,
		"selected_armor": selected_armor,
		"best_floor": best_floor,
		"total_kills": total_kills,
		"deaths": deaths,
		"runs": runs,
		"victories": victories,
		"unlocked_runes": unlocked_runes,
		"seen_biomes": seen_biomes,
		"boss_cells_unlocked": boss_cells_unlocked,
		"active_bsc": active_bsc,
		"delivered_blueprints": delivered_blueprints,
		"blueprint_cells": blueprint_cells,
		"unlocked_mutations": unlocked_mutations,
		"forge_cells": forge_cells,
		"legacy_snapshot": legacy_snapshot,
		"retired_content": retired_content,
	}, true)
	# Temp-then-rename: an interrupted write must never truncate the real save,
	# otherwise a crash mid-save silently resets the whole profile.
	var tmp := SAVE_PATH + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		last_save_error = "CANNOT WRITE PROFILE"
		push_warning("Profile: cannot write %s; original save retained" % tmp)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	var complete := file.get_error() == OK
	file.close()
	if not complete:
		last_save_error = "INCOMPLETE PROFILE WRITE"
		DirAccess.remove_absolute(tmp)
		push_warning("Profile: incomplete write; original save retained")
		return false
	# Rename replaces an existing file; removing it first creates a data-loss window.
	if DirAccess.rename_absolute(tmp, SAVE_PATH) != OK:
		last_save_error = "CANNOT COMMIT PROFILE"
		DirAccess.remove_absolute(tmp)
		push_warning("Profile: cannot commit %s; original save retained" % SAVE_PATH)
		return false
	run_checkpoint = next_checkpoint.duplicate(true)
	return true


func reset_profile() -> void:
	if _test_scene_requested() and not require_test_profile():
		return
	if _save_blocked:
		push_warning("Profile: reset refused for protected save")
		return
	_apply_defaults()
	save()


# ------------------------------------------------------------------ currency

func bank(amount: int) -> void:
	if amount <= 0:
		return
	cells += amount
	save()


func spend(amount: int) -> bool:
	last_save_error = ""
	if amount <= 0:
		return true
	if cells < amount:
		return false
	cells -= amount
	if save():
		return true
	cells += amount
	return false


# ------------------------------------------------------------------ upgrades

func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))


func upgrade_max(id: String) -> int:
	var cfg: Dictionary = Data.upgrades.get(id, {})
	return int(cfg.get("max", 1))


func upgrade_cost(id: String) -> int:
	var cfg: Dictionary = Data.upgrades.get(id, {})
	if cfg.is_empty():
		return -1
	var level := upgrade_level(id)
	if level >= int(cfg.get("max", 1)):
		return -1
	return int(cfg.get("cost", 30)) + int(cfg.get("cost_step", 25)) * level


## An upgrade is priced in cells unless it says otherwise. The attribute
## upgrades are the soul sink: victory pays souls and nothing else spends them.
func upgrade_currency(id: String) -> String:
	return str(Data.upgrades.get(id, {}).get("currency", "cells"))


func can_afford_upgrade(id: String) -> bool:
	var cost := upgrade_cost(id)
	if cost <= 0:
		return true
	return souls >= cost if upgrade_currency(id) == "souls" else cells >= cost


func buy_upgrade(id: String) -> bool:
	last_save_error = ""
	var cost := upgrade_cost(id)
	if cost < 0 or not can_afford_upgrade(id):
		return false
	var use_souls := upgrade_currency(id) == "souls"
	if use_souls:
		souls -= cost
	else:
		cells -= cost
	if add_upgrade(id):
		return true
	if use_souls:
		souls += cost
	else:
		cells += cost
	return false


func add_upgrade(id: String, levels: int = 1) -> bool:
	last_save_error = ""
	if not Data.upgrades.has(id):
		return false
	var previous := upgrades.duplicate()
	upgrades[id] = clampi(upgrade_level(id) + levels, 0, upgrade_max(id))
	if save():
		return true
	upgrades = previous
	return false


## Aggregated permanent bonus for one gameplay stat.
## stats: hp, damage, speed, knives, iframe, crit, cells
func bonus(stat: String) -> float:
	var total := 0.0
	for id in upgrades.keys():
		var cfg: Dictionary = Data.upgrades.get(id, {})
		if cfg.is_empty():
			continue
		if str(cfg.get("stat", "")) != stat:
			continue
		total += float(cfg.get("per_level", 0)) * float(upgrade_level(id))
	for node_id in skill_nodes:
		var node: Dictionary = Data.skill_nodes.get(node_id, {})
		if node.is_empty():
			continue
		if str(node.get("stat", "")) != stat:
			continue
		total += float(node.get("per_level", 0))
	return total


# -------------------------------------------------------------------- skills

func has_skill(id: String) -> bool:
	return skill_nodes.has(id)


func skill_available(id: String) -> bool:
	if has_skill(id):
		return false
	var node: Dictionary = Data.skill_nodes.get(id, {})
	if node.is_empty():
		return false
	for parent_id in node.get("requires", []):
		if not has_skill(str(parent_id)):
			return false
	return true


func buy_skill(id: String) -> bool:
	last_save_error = ""
	if not skill_available(id):
		return false
	var cost := maxi(0, int(Data.skill_nodes[id].get("cost", 40)))
	if cells < cost:
		return false
	cells -= cost
	skill_nodes.append(id)
	if save():
		return true
	cells += cost
	skill_nodes.erase(id)
	return false


# ------------------------------------------------------------------ archives

func see(kind: String, id: String) -> void:
	var list := _archive(kind)
	if id.is_empty() or list.has(id):
		return
	list.append(id)
	save()


func has_seen(kind: String, id: String) -> bool:
	return _archive(kind).has(id)


func _archive(kind: String) -> Array:
	match kind:
		"enemy":
			return seen_enemies
		"weapon":
			return seen_weapons
		"armor":
			return seen_armor
	# Unknown kinds get a throwaway list instead of silently writing to enemies.
	return []


# ------------------------------------------------------------------- unlocks

func is_unlocked(kind: String, id: String) -> bool:
	match kind:
		"character":
			return unlocked_characters.has(id)
		"weapon":
			return unlocked_weapons.has(id)
		"armor":
			return unlocked_armor.has(id)
	return false


func unlock(kind: String, id: String) -> bool:
	last_save_error = ""
	var table: Dictionary = _unlock_table(kind)
	if table.is_empty():
		return false
	var cfg: Dictionary = table.get(id, {})
	if cfg.is_empty():
		return false
	if is_unlocked(kind, id):
		return false
	if kind == "weapon" and not gear_blueprint(id).is_empty():
		return false
	# Weapons carry "unlock_cost"; armour and characters carry "cost".
	var price := maxi(0, int(cfg.get("cost", cfg.get("unlock_cost", 0))))
	if cells < price:
		return false
	cells -= price
	_unlock_list(kind).append(id)
	if save():
		return true
	cells += price
	_unlock_list(kind).erase(id)
	return false


func unlock_free(kind: String, id: String) -> void:
	if is_unlocked(kind, id) or not _unlock_table(kind).has(id):
		return
	_unlock_list(kind).append(id)
	save()


func _unlock_table(kind: String) -> Dictionary:
	match kind:
		"character":
			return Data.characters
		"weapon":
			return Data.weapons
		"armor":
			return Data.armor
	return {}


func _unlock_list(kind: String) -> Array:
	match kind:
		"character":
			return unlocked_characters
		"weapon":
			return unlocked_weapons
		"armor":
			return unlocked_armor
	return unlocked_characters


func select(kind: String, id: String) -> bool:
	last_save_error = ""
	if not _unlock_table(kind).has(id) or not is_unlocked(kind, id):
		return false
	var field := "selected_" + kind
	var previous: String = get(field)
	set(field, id)
	if save():
		return true
	set(field, previous)
	return false


# ------------------------------------------------------------- Collector / Forge

func gear_blueprint(id: String) -> String:
	for blueprint: String in Data.passage.blueprints:
		var row: Dictionary = Data.passage.blueprints[blueprint]
		if row.kind == "gear" and row.target == id:
			return blueprint
	return ""


func gear_available(id: String) -> bool:
	var cfg: Dictionary = Data.gear.items.get(id, {})
	if cfg.is_empty():
		return false
	if cfg.get("starter", false) or unlocked_weapons.has(id):
		return true
	for blueprint in Data.passage.blueprints:
		var row: Dictionary = Data.passage.blueprints[blueprint]
		if row.kind == "gear" and row.target == id and delivered_blueprints.has(blueprint) and int(blueprint_cells.get(blueprint, 0)) >= int(row.cost):
			return true
	return false


func mutation_available(id: String) -> bool:
	return Data.passage.mutations.has(id) and (Data.passage.mutations[id].get("starter", false) or unlocked_mutations.has(id))


func deliver_blueprint(id: String, checkpoint: Variant = null) -> bool:
	last_save_error = ""
	if not Data.passage.blueprints.has(id) or delivered_blueprints.has(id):
		return false
	delivered_blueprints.append(id)
	if save(checkpoint):
		return true
	delivered_blueprints.erase(id)
	return false


func invest_blueprint(id: String, requested: int, checkpoint: Variant = null) -> int:
	last_save_error = ""
	if requested <= 0 or not delivered_blueprints.has(id) or not Data.passage.blueprints.has(id):
		return 0
	var cfg: Dictionary = Data.passage.blueprints[id]
	var previous := blueprint_cells.duplicate()
	var owned := unlocked_weapons.duplicate()
	var mutations := unlocked_mutations.duplicate()
	var amount := mini(requested, int(cfg.cost) - int(blueprint_cells.get(id, 0)))
	if amount <= 0:
		return 0
	blueprint_cells[id] = int(blueprint_cells.get(id, 0)) + amount
	if int(blueprint_cells[id]) == int(cfg.cost):
		if cfg.kind == "gear" and Data.weapons.has(cfg.target) and not unlocked_weapons.has(cfg.target):
			unlocked_weapons.append(str(cfg.target))
		elif cfg.kind == "mutation" and not unlocked_mutations.has(cfg.target):
			unlocked_mutations.append(str(cfg.target))
	if save(checkpoint):
		return amount
	blueprint_cells = previous
	unlocked_weapons = owned
	unlocked_mutations = mutations
	return 0


func invest_forge(requested: int, checkpoint: Variant = null) -> int:
	last_save_error = ""
	var amount := mini(requested, int(Data.passage.forge.cost) - forge_cells)
	if amount <= 0:
		return 0
	forge_cells += amount
	if save(checkpoint):
		return amount
	forge_cells -= amount
	return 0


func forge_chance() -> float:
	var chance := 0.0
	for row: Dictionary in Data.passage.forge.thresholds:
		if forge_cells >= int(row.cells):
			chance = float(row.chance)
	return chance


# ------------------------------------------------------------- run bookkeeping

func discover_biome(id: String) -> bool:
	if seen_biomes.has(id):
		return true
	if not Data.route_graph.get("nodes", {}).has(id):
		return false
	seen_biomes.append(id)
	if save():
		return true
	seen_biomes.erase(id)
	return false


func unlock_rune(id: String) -> bool:
	last_save_error = ""
	if id.is_empty() or unlocked_runes.has(id):
		return false
	unlocked_runes.append(id)
	if not save():
		unlocked_runes.erase(id)
		return false
	runes_changed.emit()
	return true


func note_floor_reached(index: int) -> bool:
	if index <= best_floor:
		return true
	var previous := best_floor
	best_floor = index
	if save():
		return true
	best_floor = previous
	return false


func note_run(kills: int, died: bool, won: bool, residual_cells: int = 0, final_bsc: int = -1) -> bool:
	if (died and won) or residual_cells < 0 or final_bsc not in [-1, 0] or (not won and (residual_cells > 0 or final_bsc >= 0)):
		return false
	var before := [runs, total_kills, deaths, victories, cells, souls, boss_cells_unlocked]
	var old_runes := unlocked_runes.duplicate()
	runs += 1
	total_kills += maxi(0, kills)
	if died:
		deaths += 1
	if won:
		victories += 1
		cells += residual_cells
		souls += 1
		if final_bsc == 0:
			boss_cells_unlocked = maxi(1, boss_cells_unlocked)
			for rune: String in Data.route_graph.nodes[Data.route_graph.final].get("rune_rewards", []):
				if not unlocked_runes.has(rune):
					unlocked_runes.append(rune)
	# The receipt and removal of the active run are one atomic file replacement.
	if not save({}):
		runs = before[0]
		total_kills = before[1]
		deaths = before[2]
		victories = before[3]
		cells = before[4]
		souls = before[5]
		boss_cells_unlocked = before[6]
		unlocked_runes.assign(old_runes)
		return false
	if unlocked_runes != old_runes:
		runes_changed.emit()
	return true


# ------------------------------------------------------------------- helpers

## JSON turns every number into a float and can hand back null; int(null) is a
## runtime error, so every persisted number goes through here.
func _to_int(value: Variant) -> int:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING:
			return int(value)
	return 0

func _to_strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for item in value:
		if item == null:
			continue
		out.append(str(item))
	return out


func _to_dict(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var out := {}
	for key in value:
		out[str(key)] = _to_int(value[key])
	return out
