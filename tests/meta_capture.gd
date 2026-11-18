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

	# Generated-floor screenshots lived on the retired five-floor path; the
	# formal route's rooms are captured by the biome probe instead.

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
	await get_tree().process_frame
	$Main.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_dir, name]
	image.save_png(path)
	await _physical_capture(name)
	print("META FRAME %dms %s" % [Time.get_ticks_msec(), name])
	if OS.get_environment("ASHFALL_CAPTURE_ACK_DIR").is_empty(): await get_tree().create_timer(0.08, true).timeout

func _physical_capture(label: String) -> void:
	var directory := OS.get_environment("ASHFALL_CAPTURE_ACK_DIR")
	if directory.is_empty(): return
	var path := directory.path_join(label + ".json")
	var deadline := Time.get_ticks_msec() + 1500
	while not FileAccess.file_exists(path) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(FileAccess.file_exists(path), "owned physical capture acknowledgement: " + label)
