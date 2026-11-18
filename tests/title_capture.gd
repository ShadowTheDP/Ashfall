extends Node
## Captures the title main view, then the keyboard-driven save cards, then Enter.

var _captured: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	await _save("00_title")
	var directory := OS.get_environment("ASHFALL_CAPTURE_ACK_DIR")
	if not directory.is_empty():
		var deadline := Time.get_ticks_msec() + 1500
		while not FileAccess.file_exists(directory.path_join("00_title.json")) and Time.get_ticks_msec() < deadline: await get_tree().process_frame
		assert(FileAccess.file_exists(directory.path_join("00_title.json")), "owned title client capture")

	if not get_tree().paused:
		_fail("title did not pause the tree")
		return
	if not is_instance_valid(_main().title_screen) or _main().title_screen._view != "main":
		_fail("initial title is not the main action view")
		return

	# Real keys reach the save cards; the second image has no external ack owner,
	# so it is written and reported without inventing a wait for one.
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	await get_tree().create_timer(0.25).timeout
	if _main().title_screen._view != "saves":
		_fail("Saves action did not open the save cards")
		return
	await _save("01_title_saves")
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(0.2).timeout
	if _main().title_screen._view != "main":
		_fail("Esc did not return to the action list")
		return
	await _key(KEY_UP)
	await _key(KEY_UP)
	await _key(KEY_ENTER)
	await get_tree().create_timer(0.4).timeout
	if get_tree().paused:
		_fail("ENTER did not resume")
		return
	if Game.player == null:
		_fail("no player after start")
		return
	print("TITLE OK %s" % str(_captured))
	get_tree().quit(0)


func _main() -> Node:
	return $Main


func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://output/screenshots/%s.png" % label))
	_captured.append(label)
	print("saved " + label)


func _key(code: int) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await get_tree().process_frame


func _fail(message: String) -> void:
	push_error("TITLE FAIL: " + message)
	print("TITLE FAIL")
	get_tree().quit(1)
