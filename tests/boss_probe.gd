extends Node
## Floor-mode boss probe. The arena fixture hides two whole classes of bug
## because it puts the floor at y = 0:
##
##   * the Warden's slam waves used to be positioned with an ABSOLUTE
##     `position.y = -16`, which is right only when the ground is y = 0. On a
##     generated floor (slab at y 54..150) both waves spawned ~100 px above the
##     fight, so the slam - whose only damage source is those two waves - dealt
##     nothing and nobody noticed, because the boss is only ever tested in the
##     arena.
##   * the boss lane itself is placed by the generator, so "is the boss standing
##     on the slab and not inside it" is a floor-mode question too.
##
## Run: godot --headless --path . tests/boss_probe.tscn

const FLOOR := 5

var _main: Node
var _fails := 0
var _world: Node2D


func _ready() -> void:
	_main = $Main
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	_world = _main.world
	# The slam waves are parented to Game.fx_root; a probe that builds a Level by
	# hand must publish it or the waves are silently dropped.
	Game.fx_root = _world
	for seed_value in [1, 3, 7, 11]:
		await _case(seed_value)

	print("")
	if _fails == 0:
		print("BOSS PROBE OK")
	else:
		print("BOSS PROBE FAILED (%d)" % _fails)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if _fails == 0 else 1)


func _case(seed_value: int) -> void:
	var level := Level.new()
	_world.add_child(level)
	level.build(FLOOR, seed_value)
	await get_tree().process_frame

	var at: Variant = level.data.get("boss_at")
	if at == null:
		_fail("seed %d: floor %d has no boss_at" % [seed_value, FLOOR])
		level.queue_free()
		return
	var warden: Enemy = null
	for child in level.get_children():
		if child is Enemy:
			warden = child as Enemy
			break
	if warden == null:
		# The boss room is entered on the first physics frame; nudge it.
		level._enter_room((level.data["rooms"] as Array).size() - 1)
		await get_tree().physics_frame
		for child in level.get_children():
			if child is Enemy:
				warden = child as Enemy
				break
	if warden == null:
		_fail("seed %d: no Warden spawned" % seed_value)
		level.queue_free()
		return

	if warden.global_position.y > LevelGen.BASE_Y:
		_fail("seed %d: warden below the ledge (y=%.0f)" % [seed_value, warden.global_position.y])

	# Force the slam and catch the waves on the frame they exist.
	warden._pending_attack = "slam"
	warden._slam_done = false
	warden._spawn_shockwaves()
	await get_tree().process_frame

	var waves: Array = []
	for child in _world.get_children():
		if child is Projectile and str(child.get("visual")) == "wave":
			waves.append(child)
	if waves.size() != 2:
		_fail("seed %d: slam produced %d waves, expected 2" % [seed_value, waves.size()])
	for wave in waves:
		var dy: float = absf((wave as Node2D).global_position.y - warden.global_position.y)
		if dy > 40.0:
			_fail("seed %d: slam wave is %.0f px from the warden (must be within 40)" % [seed_value, dy])
		(wave as Node).queue_free()

	print("  seed %d: warden y=%.0f waves=%d" % [seed_value, warden.global_position.y, waves.size()])
	level.queue_free()
	await get_tree().process_frame


func _fail(message: String) -> void:
	_fails += 1
	push_error("BOSS PROBE FAIL: " + message)
	print("BOSS PROBE FAIL: ", message)
