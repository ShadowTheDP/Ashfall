class_name Hitbox
extends Area2D
## Reusable melee hurtbox. Tracks already-hit bodies so one swing deals damage
## once per target.

var damage := 0.0
var knockback := 0.0
var hitstop_time := 0.0
var crit_mult := 1.0
var tier := 0
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
	var final_damage := Damage.compute(damage, 0, crit, crit_mult)
	body.take_hit({
		"damage": final_damage,
		"crit": crit,
		"knockback": knockback,
		"hitstop": hitstop_time,
		"source_pos": source.global_position if source != null else global_position,
		"point": global_position,
		"tier": tier,
	})
