extends Node
var _main: Node
var _fails := 0

func _ready() -> void:
	_main = $Main
	Profile.reset_profile()
	Profile.bank(300)
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	_main.enter_hub()
	await get_tree().create_timer(0.6).timeout
	var hub: Node = _main.hub
	if hub == null:
		_fail("no hub")
		_finish()
		return

	# 1. Every station must open and close with Esc.
	var stations: Array = hub.get("STATIONS")
	for i in stations.size():
		var id := str(stations[i].get("id", "?"))
		_main._on_station_opened(id)
		await get_tree().create_timer(0.25).timeout
		if not _any_open():
			_fail("station %s did not open" % id)
			continue
		await _press(KEY_ESCAPE)
		await get_tree().create_timer(0.25).timeout
		if _any_open():
			_fail("station %s did not close on Esc" % id)
		if get_tree().paused:
			_fail("station %s left the tree paused" % id)
			get_tree().paused = false
		if not hub.get("player").is_physics_processing():
			_fail("station %s left the player frozen" % id)

	# 2. Esc must not pause the game while a panel is open.
	_main._on_station_opened("upgrade")
	await get_tree().create_timer(0.25).timeout
	await _press(KEY_ESCAPE)
	await get_tree().create_timer(0.2).timeout
	if get_tree().paused:
		_fail("Esc paused the tree instead of closing the panel")

	# 3. Buying still works after the input move.
	_main._on_station_opened("upgrade")
	await get_tree().create_timer(0.3).timeout
	var before := Profile.upgrade_level("vitality")
	await _press(KEY_ENTER)
	await get_tree().create_timer(0.25).timeout
	if Profile.upgrade_level("vitality") != before + 1:
		_fail("Enter no longer buys an upgrade")
	await _press(KEY_ESCAPE)
	await get_tree().create_timer(0.2).timeout

	_finish()

func _any_open() -> bool:
	for name in ["archive", "skill_tree"]:
		var s: Variant = _main.get(name)
		if s != null and s.has_method("is_open") and s.is_open():
			return true
	var hub: Variant = _main.get("hub")
	return hub != null and hub.has_method("is_open") and hub.is_open()

func _press(key: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.physical_keycode = key
	up.keycode = key
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame

func _fail(msg: String) -> void:
	_fails += 1
	print("ESC TEST FAIL: ", msg)

func _finish() -> void:
	print("ESC TEST %s (%d failures)" % ["OK" if _fails == 0 else "FAILED", _fails])
	get_tree().quit()
