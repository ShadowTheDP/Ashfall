extends Node
## Hit feedback service: hitstop, camera trauma and one-shot visual effects.
## Lives in an autoload so any actor can request feedback without knowing the
## scene layout.

var _stop_until := 0.0
var _stopping := false

# A hit's own payload never carries the crit flag: `Enemy.take_hit` resolves the
# crit itself and only hands it to `damage_number()`, one call after the impact.
# That call is therefore where the crit read is attached, and it goes on the
# impact node that fired immediately before it.
var _last_impact: ImpactFx = null
var _last_impact_msec := -1000


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


const TIER_HITSTOP := [0.033, 0.067, 0.100, 0.133]
const TIER_SHAKE := [0.16, 0.30, 0.52, 0.72]
const TIER_PUNCH := [0.0, 0.0, 0.45, 0.75]


## Tiered impact: line sparks + ring + 1-frame flash at the real contact point.
## tier: 0 light, 1 medium, 2 heavy, 3 finisher.
func impact(at: Vector2, direction: Vector2, tier: int, tint: Color = MathArt.WHITE) -> void:
	var fx := ImpactFx.new()
	fx.position = at
	fx.setup(direction, tier, tint)
	_add(fx)
	_last_impact = fx
	_last_impact_msec = Time.get_ticks_msec()
	var t := clampi(tier, 0, 3)
	shake(float(TIER_SHAKE[t]))
	punch(float(TIER_PUNCH[t]))
	hitstop(float(TIER_HITSTOP[t]))
	# Each tier adds one kind of thing rather than scaling everything: the player
	# has to feel the difference between a jab and a finisher instantly.
	if t >= 1:
		Juice.prism_burst(_fx_parent(), at, tint, 10 + t * 6, 240.0 + t * 60.0)
		# Floor debris along the knockback. Sparks only fade; shards fall, which
		# is the cheapest way to give a medium hit weight the light one lacks.
		Juice.debris_poly(_fx_parent(), at, direction.x, tint, 5 + t * 2, 200.0 + t * 50.0)
	if t >= 2:
		var wave := ShockwaveFx.new()
		wave.position = at
		wave.setup(at, 1 if direction.x >= 0.0 else -1, 44.0 + t * 16.0, tint, 5 if t == 2 else 6)
		_add(wave)
	if t >= 3:
		var stars := ConstellationFx.new()
		stars.position = at
		stars.setup(at, 30.0, tint, 9, 0.55)
		_add(stars)
		Juice.rose_bloom(_fx_parent(), at, tint, 6)
		# Streaks along the swing: the finisher has motion the lighter tiers
		# cannot fake, and it leaves on the hit normal so it reads as the strike.
		Juice.speed_lines(_fx_parent(), at, direction, tint, 12, 620.0)


## Death, telegraphs and heavy windups pull inward instead of exploding.
func gather(at: Vector2, radius: float, tint: Color = MathArt.WHITE) -> void:
	var vortex := VortexFx.new()
	vortex.position = at
	vortex.setup(at, radius, tint, 16, 6.0, 0.5)
	_add(vortex)


func _fx_parent() -> Node:
	return Game.fx_root if is_instance_valid(Game.fx_root) else null


## Camera zoom punch: a 2-frame zoom-in that eases back over 5 frames.
func punch(amount: float) -> void:
	if amount <= 0.0:
		return
	if is_instance_valid(Game.player) and is_instance_valid(Game.player.camera):
		Game.player.camera.add_punch(amount)


## Full-screen monochrome feedback (vignette pulse + scanline offset).
func screen_punch(amount: float) -> void:
	if amount <= 0.0:
		return
	var fx := ScreenPunch.new()
	fx.setup(amount)
	var layer: Node = Game.screen_fx_root
	if is_instance_valid(layer):
		layer.add_child(fx)
	else:
		_add(fx)


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
	if crit:
		_mark_crit()


## A crit must be recognisable at a glance next to any tier, so it gets a read
## made of things a tier cannot produce: an exact 12-gon halo with no random
## spacing, the rotating ngon inside the ring, and a 3-frame full stop.
## shortcut: the freeze is capped at 0.05 s (the impact doc's ceiling) -- a
## longer one hides the next input, so a crit on a finisher is not felt longer
## than the finisher already is.
func _mark_crit() -> void:
	if not is_instance_valid(_last_impact):
		return
	if Time.get_ticks_msec() - _last_impact_msec > 16:
		return
	# 5 sides for a crit on light..heavy, 6 on a finisher.
	_last_impact.mark_crit(6 if _last_impact.tier > ImpactFx.Tier.HEAVY else 5)
	Juice.critical_halo(_fx_parent(), _last_impact.position, MathArt.WHITE)
	hitstop(0.05)


func block_number(at: Vector2) -> void:
	var fx := DamageNumber.new()
	fx.position = at
	fx.setup(0, false, "BLOCK")
	_add(fx)


func slash(at: Vector2, facing: int, attack_index: int, tint: Color, blade_length: float = 38.0) -> void:
	var fx := SlashFx.new()
	fx.position = at
	fx.setup(attack_index, facing, tint, blade_length)
	_add(fx)


func afterimage(at: Vector2, facing: int) -> void:
	var fx := Afterimage.new()
	fx.position = at
	fx.setup(facing, MathArt.PALE)
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
	_late_implosion(at, tint, count)


## The body comes apart one frame after the shape breaks, so a kill reads as
## "hit, then collapse" instead of one simultaneous flash. Lives in `shatter`
## because that is the only call the death path makes and the only sign a kill
## has happened. Ignores time_scale: the frame it waits for is the next one the
## player sees, which during a kill's hitstop is the frozen one.
func _late_implosion(at: Vector2, tint: Color, count: int) -> void:
	await get_tree().create_timer(1.0 / 60.0, true, false, true).timeout
	var host := _fx_parent()
	if is_instance_valid(host):
		Juice.kill_implosion(host, at, tint, maxi(10, count))


func dodge_burst(at: Vector2) -> void:
	var fx := BurstFx.new()
	fx.position = at
	fx.setup("dodge", MathArt.WHITE)
	_add(fx)
	var host := _fx_parent()
	if not is_instance_valid(host):
		return
	# The slip: streaks trailing the dodge, fanned across a backwards arc, so the
	# burst reads as a ring behind a body that moved rather than a puff on it.
	var away := Vector2(-1.0, 0.0)
	if is_instance_valid(Game.player):
		away = -Game.player.velocity
		if away.length() < 1.0:
			away = Vector2(float(-Game.player.facing), 0.0)
	away = away.normalized()
	for step in [-0.6, -0.2, 0.2, 0.6]:
		Juice.speed_lines(host, at, away.rotated(float(step)), MathArt.PALE, 3, 420.0)


func block_burst(at: Vector2, facing: int) -> void:
	var fx := BurstFx.new()
	fx.position = at
	fx.setup("block", MathArt.PALE_DIM, facing)
	_add(fx)
	# Emitted on the shield arc the player can actually see: the Aegis shell sits
	# 30-40 px from the body centre and the block point is 14 px in front of it,
	# so 26 px of arc lands on the rings. Directional information, not decoration.
	var host := _fx_parent()
	if is_instance_valid(host):
		Juice.block_shell(host, at, facing, MathArt.PALE)


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
