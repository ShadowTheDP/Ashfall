extends Node
## Regression probe for R (restart) inside a floor.
##
## The bug: Hud._restart() called reload_current_scene(), which rebuilt Main,
## showed the title and landed in the hub. Because Game.start_floor() had
## already advanced best_floor on entry, the door then offered the NEXT floor.
## So a retry banked progression, skipped the floor and - if the player had
## died - recorded a death that the retry then discarded the body of.
##
## What must hold after a retry, from both "paused mid-fight" and "dead":
##   * still on the same floor, in the same run, not in the hub
##   * Profile is untouched: runs / deaths / victories / best_floor / cells
##   * exactly one Player in the world, and it is alive and processing
##   * the old level is gone: no enemies, no projectiles, no stale door
##   * HUD is not paused, the tree is not paused, time is not dilated
##
## Run: godot --headless --path . tests/restart_probe.tscn

var _main: Node
var _fails := 0


func _ready() -> void:
	_main = $Main
	Profile.reset_profile()
	Profile.bank(120)
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	_main.enter_hub()
	await get_tree().create_timer(0.3).timeout

	await _descend(1)
	await _check_retry_paused()

	# Dying then pressing R is the nastier path: end_run(false) has already
	# written a death into the profile.
	var level: Node = _main.level
	if level != null and Game.player != null:
		Game.player.hp = 0.0
	await get_tree().create_timer(0.4).timeout
	if not Game.run_over:
		_fail("death did not end the run")
	await _check_retry_dead()

	print("")
	if _fails == 0:
		print("RESTART PROBE OK")
	else:
		print("RESTART PROBE FAILED (%d)" % _fails)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if _fails == 0 else 1)


func _descend(floor_index: int) -> void:
	_main._on_descend(floor_index)
	await get_tree().create_timer(0.6).timeout


func _snapshot() -> Dictionary:
	return {
		"cells": Profile.cells, "souls": Profile.souls,
		"runs": Profile.runs, "deaths": Profile.deaths,
		"victories": Profile.victories, "best_floor": Profile.best_floor,
	}


func _diff(before: Dictionary) -> String:
	var out: Array[String] = []
	for key in before:
		if before[key] != Profile.get(key):
			out.append("%s %s -> %s" % [key, str(before[key]), str(Profile.get(key))])
	return ", ".join(out)


func _players() -> int:
	var count := 0
	for node in _main.world.get_children():
		if node is Player:
			count += 1
	return count


func _retry() -> void:
	# Pause first, like a player would, then press R through the HUD path.
	if not Game.run_over:
		_main.hud._set_paused(true)
		await get_tree().process_frame
	_main.hud._restart()
	await get_tree().create_timer(0.4).timeout


func _assert_retry(label: String, before: Dictionary, floor_index: int) -> void:
	if Game.in_hub:
		_fail("%s: retry landed in the hub" % label)
	if Game.floor_index != floor_index:
		_fail("%s: retry moved to floor %d (wanted %d)" % [label, Game.floor_index, floor_index])
	if Game.run_over:
		_fail("%s: run_over survived the retry" % label)
	if get_tree().paused:
		_fail("%s: tree stayed paused" % label)
	if _main.hud.paused:
		_fail("%s: HUD stayed paused" % label)
	if not is_equal_approx(Engine.time_scale, 1.0):
		_fail("%s: time_scale is %.2f" % [label, Engine.time_scale])
	if Profile.best_floor != before["best_floor"]:
		_fail("%s: retry advanced best_floor (%s)" % [label, _diff(before)])
	# Both snapshots are taken immediately before the retry, so ANY change here
	# is the retry writing progress it has no right to write.
	var changed := _diff(before)
	if not changed.is_empty():
		_fail("%s: retry touched the profile (%s)" % [label, changed])
	var players := _players()
	if players != 1:
		_fail("%s: %d Player nodes in the world" % [label, players])
	if Game.player == null or not is_instance_valid(Game.player):
		_fail("%s: Game.player is gone" % label)
	elif Game.player.hp <= 0.0:
		_fail("%s: retried player is already dead" % label)
	elif not Game.player.is_physics_processing():
		_fail("%s: retried player is frozen" % label)
	var leftovers := 0
	for node in _main.world.get_children():
		if node is Enemy or node is Projectile or node is FunctionWave:
			leftovers += 1
	if leftovers > 0:
		_fail("%s: %d nodes from the old floor survived" % [label, leftovers])
	var level: Node = _main.level
	if level == null:
		_fail("%s: no level after the retry" % label)
	elif int(level.enemies_remaining()) <= 0:
		_fail("%s: retried floor has no enemies" % label)
	print("  %s: floor=%d enemies=%d players=%d profile[%s]" % [
		label, Game.floor_index, int(level.enemies_remaining()) if level != null else -1,
		players, _diff(before) if not changed.is_empty() else "unchanged"])


func _check_retry_paused() -> void:
	var before := _snapshot()
	# Earn cells so a wrongly-banked attempt would be visible in Profile.cells.
	Game.add_cells(9)
	await _retry()
	_assert_retry("paused retry", before, 1)


func _check_retry_dead() -> void:
	var before := _snapshot()
	await _retry()
	_assert_retry("dead retry", before, 1)


func _fail(message: String) -> void:
	_fails += 1
	push_error("RESTART FAIL: " + message)
	print("RESTART FAIL: ", message)
