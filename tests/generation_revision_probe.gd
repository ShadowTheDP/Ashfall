extends Node
## Current generator revision only: Main/Profile save-resume round trips, stamp
## refusal and failed-generation atomicity. Invoke with an isolated test Profile.
## Historical legacy_v1 restores are archived; no active check reads them here.
const MainScript := preload("res://scripts/main.gd")
var _main: Node
var _checks := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	if not Profile.require_test_profile(): return
	_main = MainScript.new()
	_main.start_mode = "hub"
	_main.skip_title = true
	get_tree().root.add_child(_main)
	await get_tree().process_frame
	_main.enter_hub()
	_check(Game.generator_revision == BiomeGen.LATEST_REVISION, "new run selects latest")
	_check(_main.start_node("ash_gate"), "new Ash Gate entry")
	var latest := Profile.run_checkpoint.duplicate(true)
	_check(latest.generator_revision == BiomeGen.LATEST_REVISION and latest.content == RunCheckpoint.content_stamp(BiomeGen.LATEST_REVISION), "new checkpoint explicitly stamps algorithm, spatial data and traversal")
	var latest_layout: Dictionary = _main.level.data.duplicate(true)
	_check(_main.resume_checkpoint() and _main.level.data == latest_layout, "new entry restores identical canonical layout")
	var before := Profile.run_checkpoint.duplicate(true)
	var disk := FileAccess.get_file_as_string(Profile.SAVE_PATH)
	_check(_main.resume_checkpoint() and _main.level.data == latest_layout and Profile.run_checkpoint == before and FileAccess.get_file_as_string(Profile.SAVE_PATH) == disk, "resume is deterministic and mutates neither checkpoint nor bytes")
	# Reject unknown revision/stamp before destroying a scene or changing either owner.
	for revision in ["unknown", "", null, 2]:
		var bad := latest.duplicate(true)
		bad.generator_revision = revision
		_check(Profile.save(bad), "store isolated unsupported revision")
		var old_player := Game.player
		var old_level: Node = _main.level
		var history := Game.route_history.duplicate()
		var raw := FileAccess.get_file_as_string(Profile.SAVE_PATH)
		_check(not _main.resume_checkpoint() and Game.player == old_player and _main.level == old_level and Game.route_history == history and Game.generator_revision == BiomeGen.LATEST_REVISION, "unsupported revision rejects without mutation")
		_check(FileAccess.get_file_as_string(Profile.SAVE_PATH) == raw, "unsupported checkpoint bytes retained")
	var bad_stamp := latest.duplicate(true)
	bad_stamp.content = RunCheckpoint.content_stamp(BiomeGen.LEGACY_REVISION)
	_check(not RunCheckpoint.error(bad_stamp).is_empty(), "legacy stamp cannot authorize newest generator")
	var traversal_value: Variant = Data.traversal.interact_reach
	Data.traversal.interact_reach = float(traversal_value) + 1
	_check(not RunCheckpoint.error(latest).is_empty(), "new stamp covers traversal")
	Data.traversal.interact_reach = traversal_value
	# A failed save transaction retains the durable checkpoint until explicit retry.
	before = Profile.run_checkpoint.duplicate(true)
	disk = FileAccess.get_file_as_string(Profile.SAVE_PATH)
	Profile._save_blocked = true
	_check(not _main._save_checkpoint("biome_entry", int(before.seed)) and _main.hud.checkpoint_blocked and Profile.run_checkpoint == before and FileAccess.get_file_as_string(Profile.SAVE_PATH) == disk, "failed save transaction keeps durable bytes")
	Profile._save_blocked = false
	_check(_main.retry_checkpoint() and not _main.hud.checkpoint_blocked and str(Profile.run_checkpoint.kind) == "biome_entry", "explicit retry commits the pending checkpoint")
	# Destination preparation fails before Game.enter_node or old scene destruction.
	_main.enter_hub()
	var old_hub: Node = _main.hub
	var old_body := Game.player
	var original := Data.generation_spatial.duplicate(true)
	for variant: Dictionary in Data.generation_spatial.profiles.ash_gate.variants:
		variant.nodes["entry"] = {"grid": [1, 0]}
	disk = FileAccess.get_file_as_string(Profile.SAVE_PATH)
	_check(not _main.start_node("ash_gate") and _main.hub == old_hub and Game.player == old_body and Game.route_history.is_empty() and Game.generator_revision == BiomeGen.LATEST_REVISION, "invalid placement preserves Hub and fresh run")
	_check(FileAccess.get_file_as_string(Profile.SAVE_PATH) == disk, "failed generation cannot change Profile")
	Data.generation_spatial = original
	print("GENERATION REVISION OK (%d checks)" % _checks)
	get_tree().quit(0)

func _check(ok: bool, message: String) -> void:
	_checks += 1
	assert(ok, "GENERATION REVISION FAIL: " + message)
