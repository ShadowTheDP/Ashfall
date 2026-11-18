extends Node
## Exercise the real hit packet and spawned feedback without changing combat numbers.
class Target extends Enemy:
	var received: Dictionary = {}
	func _ready() -> void:
		set_physics_process(false)
	func take_hit(info: Dictionary) -> void:
		received = info

class PlainTarget extends Node2D:
	var received: Dictionary = {}
	func take_hit(info: Dictionary) -> void:
		received = info

var _checks := 0
var _fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	assert(Profile.require_test_profile())
	await get_tree().process_frame
	var attacker := Node2D.new()
	add_child(attacker)
	var target := Target.new()
	target.cfg = {"body_radius": 12.0}
	add_child(target)
	target.position = Vector2(50, 0)
	var box := Hitbox.new()
	add_child(box)
	for row in [[0, 38], [100, 62], [50, 38]]:
		attacker.position.x = row[0]
		box.enable(11, 180, 0.04, attacker, 1.5, 2)
		box._try_hit(target)
		_check(target.received.point == Vector2(row[1], -6), "Enemy near-side contact for attacker x=" + str(row[0]))
		_packet(target.received, attacker.position)
		box.disable()
	target.cfg.body_radius = 20.0
	attacker.position.x = 0
	box.enable(11, 180, 0.04, attacker, 1.5, 2)
	box._try_hit(target)
	_check(target.received.point == Vector2(30, -6), "contact uses configured Enemy radius")
	box.disable()
	box.position = Vector2(10, 0)
	box.enable(11, 180, 0.04, null, 1.5, 2)
	box._try_hit(target)
	_check(target.received.point == Vector2(50, -6), "source-less Hitbox preserves centre contact")
	_packet(target.received, box.position)
	box.disable()
	var plain := PlainTarget.new()
	plain.position = Vector2(50, 0)
	add_child(plain)
	box.enable(11, 180, 0.04, attacker, 1.5, 2)
	box._try_hit(plain)
	_check(plain.received.point == Vector2(38, -6), "non-Enemy target preserves default radius")
	box.disable()
	for row in [[-50, 1], [50, 1], [0, 1], [0, -1], [null, 1], [null, -1]]:
		_player_contact(row[0], row[1])
	_damage_number_motion()
	Combat.cancel_hitstop()
	# No assertion waits on time here. This lets the spawned feedback nodes reach
	# their own lifetime before quit so the exit diagnostics stay limited to the
	# known audio references; the longest of them is the 0.7 s damage number.
	await get_tree().create_timer(0.75).timeout
	print("CONTACT %s (%d checks, %d failures)" % ["OK" if _fails == 0 else "FAILED", _checks, _fails])
	get_tree().quit(1 if _fails else 0)


func _packet(info: Dictionary, source: Vector2) -> void:
	_check(info.damage == 11 and info.knockback == 180 and info.hitstop == 0.04 and info.tier == 2 and not info.crit and info.source_pos == source, "contact correction retains damage/knockback/tier/source payload")


func _player_contact(source_x: Variant, facing: int) -> void:
	var player := Game.player
	player.hp = 100
	player.armor_taken = 1
	player.invuln = 0
	player.aegis_t = 0
	player.guard_t = 0
	player.roll_iframe_t = -1
	player.facing = facing
	player.set_state(Player.State.IDLE)
	var info := {"damage": 10}
	if source_x != null:
		info.source_pos = player.global_position + Vector2(source_x, 0)
	var dir := -signf(float(source_x)) if source_x != null and source_x != 0 else -float(facing)
	var expected := player.global_position + Vector2(-dir * 14, -8)
	var effects := Game.fx_root.get_children()
	var siblings := player.get_parent().get_children()
	player.take_hit(info)
	var sparks := 0
	var bursts := 0
	var particles := 0
	for fx in Game.fx_root.get_children():
		if effects.has(fx):
			continue
		if fx is HitSpark:
			sparks += 1
			_check(fx.global_position == expected and fx.direction == Vector2(dir, 0), "player spark is on near edge, direction remains knockback")
		elif fx is BurstFx and fx.mode == "hurt":
			bursts += 1
			_check(fx.global_position == expected and fx.facing == int(dir), "player hurt burst uses same near edge")
	for fx in player.get_parent().get_children():
		if not siblings.has(fx) and fx is CPUParticles2D:
			particles += 1
			_check(fx.global_position == expected and fx.direction == Vector2(dir, 0), "player Juice particles share the contact edge")
	_check(sparks == 1 and bursts == 1 and particles == 1, "all three player feedback layers were observed")
	_check(player.hp == 90 and player.velocity == Vector2(dir * player.hurt_knockback, -150), "damage and knockback magnitude/direction are unchanged")
	Combat.cancel_hitstop()


func _damage_number_motion() -> void:
	var positions := {}
	for fps in [60, 120, 240]:
		var number := DamageNumber.new()
		number.setup(12, false)
		add_child(number)
		number.set_process(false)
		for frame in roundi(0.2 * fps):
			number._process(1.0 / float(fps))
		positions[fps] = number.position.y
		_check(number.position.y < -1.0, "DamageNumber rises at %d Hz" % fps)
		number.free()
	var values: Array = positions.values()
	_check(float(values.max()) - float(values.min()) < 1.0, "DamageNumber position is frame-rate independent after 0.2s")

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("CONTACT FAIL: " + message)
