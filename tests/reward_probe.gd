extends Node
## Keyboard-only reward flow probe. Verifies pause, selection and effects
## without relying on mouse or on the encounter timer.
##
## Run: godot --headless --path . tests/reward_probe.tscn

var _failures := 0
var _main: Node
var _capture := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_capture = DisplayServer.get_name() != "headless"
	_main = $Main
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout

	var player := Game.player
	if player == null:
		_fail("player missing")
		_finish()
		return

	_main.encounter.started = false
	for enemy in _main.encounter.alive:
		enemy.queue_free()
	_main.encounter.alive.clear()
	Game.enemies_left = 0

	# The probe drives the screen itself; detach the encounter continuation.
	_main.reward_screen.chosen.disconnect(Callable(_main, "_on_reward_chosen"))

	# 1 = vitality
	var max_hp_before := player.max_hp
	_main.reward_screen.open(["vitality", "edge", "armory"])
	await get_tree().process_frame
	if not get_tree().paused or not Game.reward_open or not _main.reward_screen.visible:
		_fail("reward screen did not pause the tree")
		return
	await _shot("boon-start")
	await _press(KEY_1)
	if get_tree().paused or Game.reward_open:
		_fail("reward screen did not unpause after picking 1")
	if not is_equal_approx(player.max_hp, max_hp_before + 20.0):
		_fail("vitality did not add 20 max hp")

	# Arrow + Enter path, then number 3.
	_main.reward_screen.open(["edge", "armory", "swift"])
	await get_tree().process_frame
	await _press(KEY_RIGHT)
	await _shot("boon-focused")
	await _press(KEY_ENTER)
	await _shot("boon-confirmed")
	if not Game.reward_counts.has("armory"):
		_fail("arrow + enter did not take armory")
	var knives_before := player.knife_max

	_main.reward_screen.open(["armory", "ghost", "hunter"])
	await get_tree().process_frame
	await _press(KEY_3)
	if not Game.reward_counts.has("hunter"):
		_fail("number 3 did not take hunter")
	if player.crit_bonus <= 0.0:
		_fail("hunter did not add crit bonus")
	if player.knife_max != knives_before:
		_fail("third choice unexpectedly changed knife max")

	# Two-colour build: a coloured boon raises its own colour, and the equipped
	# weapon scales with the colour it carries (rusty_sword is brutality).
	if int(Game.attr.get("brutality", 0)) < 1:
		_fail("hunter did not raise the brutality colour")
	if player.weapon_attr_level() < 1:
		_fail("brutality boon never reached the weapon (level %d)" % player.weapon_attr_level())
	if Damage.compute(10.0, player.weapon_attr_level(), false, 1.0) <= 10:
		_fail("brutality level does not scale damage")

	# A neutral boon must not invent a colour.
	var tactics_before := int(Game.attr.get("tactics", 0))
	_main.reward_screen.open(["swift", "vitality", "leech"])
	await get_tree().process_frame
	await _press(KEY_1)
	if int(Game.attr.get("tactics", 0)) != tactics_before:
		_fail("a neutral boon raised a colour")

	if get_tree().paused:
		get_tree().paused = false
	_finish()


func _shot(label: String) -> void:
	if not _capture: return
	DirAccess.make_dir_recursive_absolute("res://output/screenshots/reward")
	await get_tree().create_timer(0.12, true).timeout
	await get_tree().process_frame
	$Main.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	if get_viewport().get_texture().get_image().save_png("res://output/screenshots/reward/" + label + ".png") != OK:
		_fail("capture " + label)


	await _physical_capture(label)
	print("REWARD_PROBE FRAME %dms %s" % [Time.get_ticks_msec(), label])
	if OS.get_environment("ASHFALL_CAPTURE_ACK_DIR").is_empty(): await get_tree().create_timer(0.08, true).timeout

func _press(key: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.physical_keycode = key
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame
	await get_tree().create_timer(0.05).timeout


func _fail(message: String) -> void:
	_failures += 1
	push_error("REWARD FAIL: " + message)
	print("REWARD FAIL: ", message)


func _finish() -> void:
	if _failures == 0:
		print("REWARD OK")
	else:
		print("REWARD FAILED (%d)" % _failures)
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0 if _failures == 0 else 1)

func _physical_capture(label: String) -> void:
	var directory := OS.get_environment("ASHFALL_CAPTURE_ACK_DIR")
	if directory.is_empty(): return
	var path := directory.path_join(label + ".json")
	var deadline := Time.get_ticks_msec() + 1500
	while not FileAccess.file_exists(path) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(FileAccess.file_exists(path), "owned physical capture acknowledgement: " + label)
