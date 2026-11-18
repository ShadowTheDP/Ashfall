extends Node
## Selection is committed once, or memory and disk both retain the previous loadout.
const CHOICES := [
	{"kind": "character", "id": "octa", "field": "selected_character", "old": "square"},
	{"kind": "weapon", "id": "kiss_precision", "field": "selected_weapon", "old": "rusty_sword"},
	{"kind": "armor", "id": "plate", "field": "selected_armor", "old": "none"},
]
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
	assert(Profile.require_test_profile())
	var base := Profile.SAVE_PATH
	for choice: Dictionary in CHOICES:
		for failure in ["protected", "open", "commit"]:
			_failure(base, choice, failure)
		_success(base, choice)
	Profile.SAVE_PATH = base
	Profile.load_profile(true)
	await get_tree().create_timer(1.8).timeout
	print("SELECTION %s: %d checks, %d failures" % ["OK" if _fails == 0 else "FAILED", _checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails else 0)


func _fixture(path: String, future := false) -> void:
	Profile.SAVE_PATH = path
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"version": Profile.VERSION + 1 if future else Profile.VERSION,
		"unlocked_characters": ["square", "octa"], "unlocked_weapons": ["rusty_sword", "kiss_precision"],
		"unlocked_armor": ["none", "plate"], "unknown_nested": {"keep": [1, true]}}))
	file.close()
	Profile.load_profile(true)


func _failure(base: String, choice: Dictionary, failure: String) -> void:
	var path: String = base + ".selection-" + choice.kind + "-" + failure
	_fixture(path, failure == "protected")
	var original := FileAccess.get_file_as_bytes(path)
	if failure == "open":
		assert(DirAccess.make_dir_absolute(path + ".tmp") == OK)
	elif failure == "commit":
		Profile.SAVE_PATH = path + ".directory"
		assert(DirAccess.make_dir_absolute(Profile.SAVE_PATH) == OK)
	var result: Variant = Profile.call("select", choice.kind, choice.id)
	_check(result == false, failure + " returns failure for " + choice.kind)
	_check(Profile.get(choice.field) == choice.old, failure + " rolls back selection in memory")
	_check(not Profile.last_save_error.is_empty(), failure + " exposes persistence failure")
	if choice.kind == "character":
		var hub := HubUi.new()
		add_child(hub)
		hub.open_station("character")
		hub._activate({"id": choice.id, "kind": choice.kind})
		_check(hub._flash > 0.45 and not Profile.last_save_error.is_empty(), failure + " Hub shows save failure")
		_check(hub._status(choice.kind, choice.id, 0, Profile.selected_character) == "Owned", failure + " Hub does not mark equipped")
		hub.free()
	else:
		var archive := ArchiveScreen.new()
		add_child(archive)
		archive.open(choice.kind)
		archive._index = archive._ids.find(choice.id)
		archive._activate()
		_check(archive._note.begins_with("SAVE FAILED:") and not "EQUIPPED" in archive._note, failure + " Archive shows save failure")
		_check(Profile.get(choice.field) == choice.old, failure + " Archive retains previous equipment")
		archive.free()
	_check(FileAccess.get_file_as_bytes(path) == original, failure + " retains byte-exact original")
	_check(not FileAccess.file_exists(Profile.SAVE_PATH + ".tmp"), failure + " leaves no recoverable uncommitted selection")
	DirAccess.remove_absolute(Profile.SAVE_PATH + ".tmp")
	if failure == "commit":
		DirAccess.remove_absolute(Profile.SAVE_PATH)
	Profile.SAVE_PATH = path
	Profile.load_profile(true)
	_check(Profile.get(choice.field) == choice.old, failure + " forced disk reload retains original equipment")
	DirAccess.remove_absolute(path)


func _success(base: String, choice: Dictionary) -> void:
	var path: String = base + ".selection-success-" + choice.kind
	_fixture(path)
	_check(Profile.call("select", choice.kind, choice.id) == true, "successful selection returns true")
	_check(Profile.get(choice.field) == choice.id and Profile.last_save_error.is_empty(), "successful selection updates memory")
	Profile.set(choice.field, choice.old)
	Profile.load_profile(true)
	_check(Profile.get(choice.field) == choice.id, "successful selection survives forced disk reload")
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(disk["unknown_nested"] == JSON.parse_string('{"keep": [1, true]}'), "selection retains unknown save data")
	if choice.kind == "character":
		var hub := HubUi.new()
		add_child(hub)
		hub.open_station("character")
		hub._activate({"id": choice.id, "kind": choice.kind})
		_check(hub._flash == 0.0 and hub._status(choice.kind, choice.id, 0, Profile.selected_character) == "Equipped", "Hub successful selection remains equipped")
		hub.free()
	else:
		var archive := ArchiveScreen.new()
		add_child(archive)
		archive.open(choice.kind)
		archive._index = archive._ids.find(choice.id)
		archive._activate()
		_check(archive._note.begins_with("EQUIPPED:"), "Archive successful selection reports equipped")
		archive.free()
	_check(Profile.call("select", choice.kind, "no-such-id") == false and Profile.get(choice.field) == choice.id, "invalid selection is rejected without changing equipment")
	_check(Profile.call("select", "unknown-kind", "square") == false and Profile.get(choice.field) == choice.id, "invalid kind cannot address an arbitrary Profile property")
	DirAccess.remove_absolute(path)


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("SELECTION FAIL: " + message)
