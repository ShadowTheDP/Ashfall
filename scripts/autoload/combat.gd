extends Node
## Hit feedback service: hitstop, camera trauma and one-shot visual effects.
## Lives in an autoload so any actor can request feedback without knowing the
## scene layout.

var _stop_until := 0.0
var _stopping := false


func _ready() -> void:
	# Keep running while the tree is paused so a hitstop can always resolve.
	process_mode = Node.PROCESS_MODE_ALWAYS


func hitstop(duration: float) -> void:
	if duration <= 0.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	_stop_until = maxf(_stop_until, now + duration)
	if not _stopping:
		_run_hitstop()


func _run_hitstop() -> void:
	_stopping = true
	Engine.time_scale = 0.06
	while Time.get_ticks_msec() / 1000.0 < _stop_until:
		await get_tree().process_frame
		if get_tree().paused:
			break
	Engine.time_scale = 1.0
	_stopping = false


func cancel_hitstop() -> void:
	_stop_until = 0.0
	_stopping = false
	Engine.time_scale = 1.0


func shake(amount: float) -> void:
	if is_instance_valid(Game.player) and is_instance_valid(Game.player.camera):
		Game.player.camera.add_trauma(amount)


func spark(at: Vector2, direction: Vector2, crit: bool, tint: Color = Color.WHITE) -> void:
	var fx := HitSpark.new()
	fx.position = at
	fx.setup(direction, crit, tint)
	_add(fx)


func damage_number(at: Vector2, amount: int, crit: bool) -> void:
	var fx := DamageNumber.new()
	fx.position = at
	fx.setup(amount, crit)
	_add(fx)


func block_number(at: Vector2) -> void:
	var fx := DamageNumber.new()
	fx.position = at
	fx.setup(0, false, "BLOCK")
	_add(fx)


func slash(at: Vector2, facing: int, attack_index: int, tint: Color) -> void:
	var fx := SlashFx.new()
	fx.position = at + Vector2(0, -10)
	fx.setup(attack_index, facing, tint)
	_add(fx)


func afterimage(at: Vector2, facing: int) -> void:
	var fx := Afterimage.new()
	fx.position = at
	fx.setup(facing, Color("#dfe4ea"))
	_add(fx)


func dust(at: Vector2, count: int, direction: Vector2) -> void:
	# Particles now come from Godot's own emitter; the old signature is kept
	# so existing call sites do not have to change.
	var root: Node = Game.fx_root
	if not is_instance_valid(root):
		return
	Juice.dust(root, at, direction.x, clampf(float(count) / 6.0, 0.4, 1.6))


func burst(at: Vector2, tint: Color, count: int = 14, speed: float = 260.0) -> void:
	var root: Node = Game.fx_root
	if not is_instance_valid(root):
		return
	Juice.hit_sparks(root, at, Vector2.UP, clampf(float(count) / 8.0, 0.4, 1.8))


func parabola_preview(at: Vector2, velocity: Vector2, gravity: float) -> void:
	var fx := ParabolaFx.new()
	fx.position = at
	fx.setup(velocity, gravity)
	_add(fx)


func ring(at: Vector2, tint: Color, radius: float, sides: int = 0) -> void:
	var fx := RingFx.new()
	fx.position = at
	fx.setup(tint, radius, sides)
	_add(fx)


func shatter(at: Vector2, tint: Color, sides: int = 3, count: int = 14, speed: float = 260.0) -> void:
	var fx := ShatterFx.new()
	fx.position = at
	fx.setup(tint, sides, count, speed)
	_add(fx)


func dodge_burst(at: Vector2) -> void:
	var fx := BurstFx.new()
	fx.position = at
	fx.setup("dodge", MathArt.WHITE)
	_add(fx)


func block_burst(at: Vector2, facing: int) -> void:
	var fx := BurstFx.new()
	fx.position = at
	fx.setup("block", MathArt.PALE_DIM, facing)
	_add(fx)


func hurt_burst(at: Vector2, facing: int) -> void:
	var fx := BurstFx.new()
	fx.position = at
	fx.setup("hurt", MathArt.WHITE, facing)
	_add(fx)


func _add(node: Node2D) -> void:
	var root: Node = Game.fx_root
	if not is_instance_valid(root):
		root = get_tree().current_scene
	if is_instance_valid(root):
		root.add_child(node)
	else:
		node.queue_free()
