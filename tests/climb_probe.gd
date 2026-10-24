extends Node
## Does a melee enemy actually climb to the upper route?
##
## The generator rewards the gallery with cell caches, and the exit needs every
## body dead. Before the climb hop, a grunt walked to the player's x and idled
## under the deck: the high route was a free safe zone against four of the six
## kinds and the floor could not be finished from up there. This probe spawns a
## body on the slab, parks the player two tiers above it, and requires the body
## to close the vertical gap.
##
## Run: godot --headless --path . tests/climb_probe.tscn

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const FLOOR := 1

var _fails := 0
var _world: Node2D


func _ready() -> void:
	await get_tree().process_frame
	_world = ($Main as Node).world
	Game.fx_root = _world
	for kind in ["grunt", "charger", "bulwark"]:
		await _case(kind)
	print("")
	if _fails == 0:
		print("CLIMB PROBE OK")
	else:
		print("CLIMB PROBE FAILED (%d)" % _fails)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if _fails == 0 else 1)


func _case(kind: String) -> void:
	var level := Level.new()
	_world.add_child(level)
	level.build(FLOOR, 1)
	await get_tree().process_frame

	# A deck at least two tiers above a slab, wide enough to stand on.
	var spot := Vector2.ZERO
	var slab_y := 0.0
	for room in (level.data["rooms"] as Array):
		var slab: Rect2 = room["rect"]
		for entry in (room["platforms"] as Array):
			var r: Rect2 = entry
			if r.size.x < 90.0 or r.position.y > slab.position.y - LevelGen.TIER * 1.9:
				continue
			spot = Vector2(r.get_center().x, r.position.y - 8.0)
			slab_y = slab.position.y
			break
		if spot != Vector2.ZERO:
			break
	if spot == Vector2.ZERO:
		_fail("%s: floor %d has no high deck to test" % [kind, FLOOR])
		level.queue_free()
		return

	var player := PLAYER_SCENE.instantiate() as Player
	player.position = spot
	_world.add_child(player)
	player.set_physics_process(false)
	Game.player = player

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.configure(kind, Data.enemies.get(kind, {}), 1.0)
	enemy.position = Vector2(spot.x, slab_y - 30.0)
	_world.add_child(enemy)
	enemy.set_physics_process(true)

	var start_gap := enemy.global_position.y - player.global_position.y
	var best := start_gap
	var frames := 0
	while frames < 480:
		await get_tree().physics_frame
		frames += 1
		best = minf(best, enemy.global_position.y - player.global_position.y)
		if best < 40.0:
			break

	print("  %s: gap %.0f -> %.0f px in %d frames" % [kind, start_gap, best, frames])
	if best > 70.0:
		_fail("%s never climbed: gap stayed at %.0f px" % [kind, best])

	enemy.queue_free()
	player.queue_free()
	level.queue_free()
	await get_tree().process_frame


func _fail(message: String) -> void:
	_fails += 1
	push_error("CLIMB FAIL: " + message)
	print("CLIMB FAIL: ", message)