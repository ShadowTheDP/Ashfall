extends Node
## Captures the title screen, then presses ENTER to prove it starts the game.

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://output/screenshots/00_title.png"))
	print("saved title")

	if not get_tree().paused:
		push_error("TITLE FAIL: title did not pause the tree")
		print("TITLE FAIL")
		get_tree().quit(1)
		return

	var down := InputEventKey.new()
	down.physical_keycode = KEY_ENTER
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().create_timer(0.4).timeout
	if get_tree().paused:
		push_error("TITLE FAIL: ENTER did not resume")
		print("TITLE FAIL")
		get_tree().quit(1)
		return
	if Game.player == null:
		push_error("TITLE FAIL: no player after start")
		print("TITLE FAIL")
		get_tree().quit(1)
		return
	print("TITLE OK")
	get_tree().quit(0)
