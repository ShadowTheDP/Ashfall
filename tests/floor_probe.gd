extends Node
## Regression probe for the hub -> floor handoff. Reports every piece of state
## that can freeze the game so a failure names the cause instead of "it hangs".

var _main: Node

func _ready() -> void:
	_main = $Main
	Profile.reset_profile()
	Profile.bank(300)
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	_main.enter_hub()
	await get_tree().create_timer(0.6).timeout
	print("--- before descend ---")
	_dump()
	_main._on_descend(1)
	await get_tree().create_timer(1.0).timeout
	print("--- after descend ---")
	_dump()
	# Try to move for half a second and see whether anything actually happens.
	var start := _player_pos()
	Input.action_press("move_right")
	await get_tree().create_timer(0.6).timeout
	Input.action_release("move_right")
	var moved := _player_pos() - start
	print("moved dx=%.1f" % moved.x)
	var ok := true
	if get_tree().paused:
		print("FAIL: tree paused")
		ok = false
	if Engine.time_scale < 0.99:
		print("FAIL: time_scale=%.2f" % Engine.time_scale)
		ok = false
	if absf(moved.x) < 5.0:
		print("FAIL: player did not move")
		ok = false
	var p := Game.player
	if p == null:
		print("FAIL: Game.player null")
		ok = false
	elif not p.is_physics_processing():
		print("FAIL: player physics disabled")
		ok = false
	print("FLOOR PROBE %s" % ("OK" if ok else "FAILED"))
	get_tree().quit()

func _player_pos() -> Vector2:
	return Game.player.global_position if Game.player != null else Vector2.ZERO

func _dump() -> void:
	var p := Game.player
	print("  paused=%s time_scale=%.2f in_hub=%s floor=%d run_over=%s reward_open=%s" % [
		str(get_tree().paused), Engine.time_scale, str(Game.in_hub), Game.floor_index,
		str(Game.run_over), str(Game.reward_open)])
	if p == null:
		print("  player=NULL")
		return
	print("  player state=%d hp=%.0f pos=%s phys=%s state_proc=%d" % [
		p.state, p.hp, str(p.global_position.round()), str(p.is_physics_processing()),
		p.process_mode])
	print("  level=%s enemies=%s" % [str(_main.level != null),
		str(_main.level.enemies_remaining()) if _main.level != null and _main.level.has_method("enemies_remaining") else "?"])
