extends Node
## End-to-end: hub -> floors 1..5 -> victory -> hub. Proves the game is
## completable and that the economy survives the whole loop.

var _main: Node
var _fails := 0

func _ready() -> void:
	_main = $Main
	Profile.reset_profile()
	Profile.bank(500)
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	_main.enter_hub()
	await get_tree().create_timer(0.4).timeout

	var banked_before := Profile.cells
	for floor_index in range(1, 6):
		_main.start_floor(floor_index)
		await get_tree().create_timer(0.5).timeout
		var level: Node = _main.level
		if level == null:
			_fail("floor %d: no level" % floor_index)
			break
		var budget := int(Data.floors.get(str(floor_index), {}).get("reward", 0))
		if Game.floor_rewards_left != budget:
			_fail("floor %d carries %d boons, data says %d" % [
				floor_index, Game.floor_rewards_left, budget])
		var rewards_before := _reward_total()
		var name: String = level.floor_name()
		var remaining := int(level.enemies_remaining())
		print("floor %d '%s': %d enemies" % [floor_index, name, remaining])
		if remaining <= 0:
			_fail("floor %d has no enemies" % floor_index)

		# Walk into every room so everything spawns, then kill it all. Wait for
		# the spawn instead of assuming one physics frame is enough: under load
		# the position lands after the level's _physics_process, the room is
		# never entered, and the run reports a phantom leftover enemy.
		var rooms: Array = level.data.get("rooms", [])
		for i in rooms.size():
			var rect: Rect2 = rooms[i]["rect"]
			if Game.player != null:
				Game.player.global_position = Vector2(rect.position.x + 40.0, rect.position.y - 40.0)
			for frame in 30:
				await get_tree().physics_frame
				if int(level._room_alive[i]) > 0 or int(level._pending_total) == 0:
					break
			await _kill_all(level)
		# Every room has been visited, so nothing may still be pending.
		for frame in 30:
			await get_tree().process_frame
			if int(level.enemies_remaining()) == 0:
				break
		if int(level.enemies_remaining()) != 0:
			_fail("floor %d still has %d enemies" % [floor_index, int(level.enemies_remaining())])

		# data/floors.json pays its boons per cleared room; a floor that clears
		# rooms without granting one is the bug this probe exists to catch.
		if budget > 0 and _reward_total() <= rewards_before:
			_fail("floor %d cleared rooms but granted no boon" % floor_index)

		# Touch the door.
		var exit: Vector2 = level.data.get("exit", Vector2.ZERO)
		if Game.player != null:
			Game.player.global_position = exit + Vector2(0.0, -30.0)
		await get_tree().physics_frame
		await get_tree().physics_frame
		await get_tree().process_frame

		if floor_index < 5:
			if Game.run_over:
				_fail("floor %d ended the run early" % floor_index)
			await get_tree().create_timer(2.0).timeout   # transition -> hub
			await get_tree().create_timer(0.4).timeout
			if _main.hub == null:
				_fail("floor %d did not return to the hub" % floor_index)
		else:
			await get_tree().create_timer(0.4).timeout
			if not Game.victory:
				_fail("floor 5 did not set victory")

	if Profile.best_floor != 5:
		_fail("best_floor %d != 5" % Profile.best_floor)
	if Profile.victories < 1:
		_fail("victories not recorded")
	if Profile.cells < banked_before:
		_fail("cells went down: %d -> %d" % [banked_before, Profile.cells])
	print("cells %d -> %d  best_floor=%d victories=%d" % [
		banked_before, Profile.cells, Profile.best_floor, Profile.victories])

	Profile.reset_profile()
	print("RUN PROBE %s (%d failures)" % ["OK" if _fails == 0 else "FAILED", _fails])
	get_tree().quit()

func _kill_all(level: Node) -> void:
	for i in 40:
		var found := false
		for child in level.get_children():
			if child is Enemy and not (child as Enemy)._dead:
				found = true
				(child as Enemy).take_hit({
					"damage": 1.0e6, "crit": true, "knockback": 0.0, "hitstop": 0.0,
					"source_pos": (child as Enemy).global_position + Vector2(-40.0, 0.0),
					"point": (child as Enemy).global_position,
				})
		await get_tree().process_frame
		if not found:
			return

func _reward_total() -> int:
	var total := 0
	for id in Game.reward_counts:
		total += int(Game.reward_counts[id])
	return total


func _fail(msg: String) -> void:
	_fails += 1
	print("RUN PROBE FAIL: ", msg)
