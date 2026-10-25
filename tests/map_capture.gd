extends Node
## Dev-only capture harness for the generator: one whole-floor overview and one
## in-game shot per room, for every floor. Needs a display (not --headless).
##   godot --path . tests/map_capture.tscn

var _dir := "res://output/screenshots/map"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	Profile.reset_profile()
	await get_tree().process_frame
	var main: Node = $Main
	for floor_index in range(1, 6):
		main.start_floor(floor_index)
		await get_tree().create_timer(0.35).timeout
		var level: Node = main.level
		var data: Dictionary = level.get("data")
		var player: Player = Game.player
		var cam := player.camera
		var width := float(data["width"])
		# The camera recomputes zoom from BASE_ZOOM every physics frame, so an
		# overview has to park it first; otherwise the shot is a normal crop.
		cam.set_physics_process(false)
		cam.limit_left = -400
		cam.limit_right = int(width) + 400
		cam.limit_top = -900
		cam.limit_bottom = 600
		cam.zoom = Vector2.ONE * minf(760.0 / width, 0.34)
		cam.global_position = Vector2(width * 0.5, -150.0)
		cam.offset = Vector2.ZERO
		cam.rotation = 0.0
		await get_tree().create_timer(0.4).timeout
		await _shot("floor%d_overview" % floor_index)
		print("floor %d width %.0f rooms %d" % [floor_index, width, (data["rooms"] as Array).size()])
		var rooms: Array = data["rooms"]
		for i in rooms.size():
			var room: Dictionary = rooms[i]
			var rect: Rect2 = room["rect"]
			cam.zoom = Vector2.ONE * 0.86
			cam.set_physics_process(true)
			cam.limit_left = -120
			cam.limit_right = int(width) + 120
			cam.limit_top = -600
			cam.limit_bottom = 400
			player.global_position = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y - 40.0)
			await get_tree().create_timer(0.35).timeout
			await _shot("floor%d_r%d_%s" % [floor_index, i, str(room.get("role", "?"))])
			print("  room %d %-9s %-10s %-16s platforms %d" % [i, str(room.get("role", "?")),
				str(room["kind"]), str(room.get("template", "?")), (room["platforms"] as Array).size()])
	print("map_capture: done")
	get_tree().quit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [_dir, name])
