class_name Hitbox
extends Area2D
## Reusable melee hurtbox. Tracks already-hit bodies so one swing deals damage
## once per target.

var damage := 0.0
var knockback := 0.0
var hitstop_time := 0.0
var crit_mult := 1.0
var tier := 0
## Colour-scaling level for the attacker (0 = no colour). The owner sets this
## BEFORE enable(); enable() deliberately does not touch it, so a box can be
## re-armed for a different swing without a signature change.
var attr := 0
var status_id := ""
var source: Node2D = null
var active := false
var shape_node: CollisionShape2D = null

var _hit_bodies: Array[Node] = []


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	for child in get_children():
		if child is CollisionShape2D:
			shape_node = child
			shape_node.set_deferred("disabled", true)
	body_entered.connect(_on_body_entered)


func enable(p_damage: float, p_knockback: float, p_hitstop: float, p_source: Node2D, p_crit_mult: float = 1.0, p_tier: int = 0) -> void:
	damage = p_damage
	knockback = p_knockback
	hitstop_time = p_hitstop
	crit_mult = p_crit_mult
	tier = p_tier
	source = p_source
	active = true
	_hit_bodies.clear()
	if shape_node != null:
		shape_node.set_deferred("disabled", false)
	call_deferred("_sweep_existing")


func disable() -> void:
	active = false
	if shape_node != null:
		shape_node.set_deferred("disabled", true)


func _sweep_existing() -> void:
	await get_tree().physics_frame
	if not active:
		return
	for body in get_overlapping_bodies():
		_try_hit(body)


func _on_body_entered(body: Node2D) -> void:
	_try_hit(body)


func _try_hit(body: Node) -> void:
	if not active or _hit_bodies.has(body) or body == source:
		return
	if not body.has_method("take_hit"):
		return
	_hit_bodies.append(body)
	var crit := false
	if source != null and source.has_method("is_crit_against"):
		crit = source.is_crit_against(body)
	var final_damage := Damage.compute(damage, attr, crit, crit_mult)
	# The contact point, not the target's centre: the impact spec allows 2 px of
	# error, and a spark popping in the middle of the silhouette it just hit
	# reads as the body hurting itself. Offset toward the attacker by the
	# target's own radius.
	var point: Vector2 = body.global_position + Vector2(0.0, -6.0)
	if source != null:
		var away := signf(body.global_position.x - source.global_position.x)
		if away == 0.0:
			away = 1.0
		var radius := 12.0
		if body is Enemy:
			radius = float((body as Enemy).cfg.get("body_radius", 12.0))
		point.x -= away * radius
	# HUNTER promises a knife back on every crit; the hit is the only place
	# that knows a crit happened, so the refund lives here.
	if crit and source != null and source.has_method("on_crit"):
		source.on_crit()
	body.take_hit({
		"damage": final_damage,
		"status": status_id,
		"status_attr": attr,
		"crit": crit,
		"knockback": knockback,
		"hitstop": hitstop_time,
		"source_pos": source.global_position if source != null else global_position,
		# The body that was hit, offset to its contact edge - not this box. A
		# Hitbox lives on the attacker and its shape is offset in front of the
		# body, so `global_position` here put every spark, ring, flash and
		# shockwave inside the PLAYER square while the damage number popped on the
		# enemy - the one anti-pattern the impact spec exists to prevent.
		"point": point,
		"tier": tier,
	})
