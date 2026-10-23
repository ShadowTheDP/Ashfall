extends Node
## Dev-only capture harness for the meta layer: hub, stations, a generated
## floor and the end-of-run screens. Run:
##   godot --path . tests/meta_capture.tscn
## Requires a rendering display (not --headless).

var _dir := "res://output/screenshots"
var _main: Node


func _ready() -> void:
	_main = $Main
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	# A deterministic profile so the captures show real numbers.
	Profile.reset_profile()
	Profile.bank(420)
	Profile.add_upgrade("vitality", 2)
	Profile.add_upgrade("edge", 1)
	Profile.see("enemy", "grunt")
	Profile.see("enemy", "archer")
	Profile.see("enemy", "charger")
	Profile.see("enemy", "bulwark")
	Profile.see("enemy", "warden")
	Profile.see("weapon", "rusty_sword")
	Profile.best_floor = 3

	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	_main.enter_hub()
	await get_tree().create_timer(0.8).timeout
	await _shot("h01_hub")

	# Walk to each station and open it.
	var hub: Node = _main.hub
	var stations: Array = hub.get("STATIONS") if hub.get("STATIONS") != null else []
	for i in stations.size():
		var id := str(stations[i].get("id", "?"))
		hub.set("_near", i)
		_main._on_station_opened(id)
		await get_tree().create_timer(0.45).timeout
		await _shot("h02_%s" % id)
		# The archive owns three tabs; capture each one.
		if id == "archive":
			for tab in ["weapon", "armor"]:
				_main.archive.open(tab)
				await get_tree().create_timer(0.35).timeout
				await _shot("h02_archive_%s" % tab)
		_close_all()
		await get_tree().create_timer(0.2).timeout

	# The door.
	if hub.has_method("setup"):
		hub.setup(3)
	await get_tree().create_timer(0.3).timeout
	await _shot("h03_door")

	# Generated floors.
	for floor_index in [1, 3, 5]:
		_main.start_floor(floor_index)
		await get_tree().create_timer(1.1).timeout
		await _shot("h04_floor%d" % floor_index)
		# Walk right so the next room and its enemies appear.
		Input.action_press("move_right")
		await get_tree().create_timer(2.2).timeout
		Input.action_release("move_right")
		await get_tree().create_timer(0.5).timeout
		await _shot("h05_floor%d_room" % floor_index)

	print("meta_capture: done")
	get_tree().quit()


func _close_all() -> void:
	if _main.archive != null and _main.archive.has_method("is_open") and _main.archive.is_open():
		_main.archive.call("close")
	if _main.skill_tree != null and _main.skill_tree.has_method("is_open") and _main.skill_tree.is_open():
		_main.skill_tree.call("close")
	if _main.hub != null and _main.hub.has_method("close_station"):
		_main.hub.close_station()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_dir, name]
	image.save_png(path)
	print("saved ", path)
