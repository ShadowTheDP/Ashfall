class_name FunctionWave
extends Area2D
## The Sine Edge finisher: a travelling sine ribbon that pierces enemies.
## It is literally the weapon's function released into the world.

var source: Node2D = null
var damage := 8.0
var crit_mult := 1.5
var direction := 1
var speed := 540.0
var tint := Color("#8fe3ff")
var _t := 0.0
var _life := 0.45
var _hit: Array[Node] = []


func setup(facing: int, p_damage: float, p_tint: Color, p_source: Node2D, p_crit: float) -> void:
	direction = facing
	damage = p_damage
	tint = p_tint
	source = p_source
	crit_mult = p_crit
	scale.x = float(facing)


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.ENEMY
	monitoring = true
	monitorable = false
	z_index = 7
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(96.0, 74.0)
	shape.shape = rect
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	global_position.x += float(direction) * speed * delta
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if body == source or _hit.has(body) or not body.has_method("take_hit"):
		return
	_hit.append(body)
	var crit := false
	if source != null and source.has_method("is_crit_against"):
		crit = source.is_crit_against(body)
	body.take_hit({
		"damage": Damage.compute(damage, 0, crit, crit_mult),
		"crit": crit,
		"knockback": 240.0,
		"hitstop": 0.03,
		"source_pos": global_position,
		"point": body.global_position,
	})
	Combat.spark(body.global_position + Vector2(0, -18), Vector2(float(direction), 0), crit, tint)


func _draw() -> void:
	var fade := clampf(1.0 - _t / _life, 0.0, 1.0)
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	var samples := 18
	for i in samples:
		var k := float(i) / float(samples - 1)
		var x := lerpf(-46.0, 46.0, k)
		var y := sin(k * TAU * 1.6 + _t * 24.0) * 11.0
		var width := lerpf(2.0, 7.0, sin(k * PI)) * fade + 1.0
		top.append(Vector2(x, y - width))
		bottom.append(Vector2(x, y + width))
	var ribbon := PackedVector2Array()
	ribbon.append_array(top)
	for i in range(bottom.size() - 1, -1, -1):
		ribbon.append(bottom[i])
	MathArt.draw_poly(self, ribbon, Color(tint, 0.16 * fade), Color(tint, 0.75 * fade), 1.2)
	var centerline := PackedVector2Array()
	for i in samples:
		var k := float(i) / float(samples - 1)
		centerline.append(Vector2(lerpf(-46.0, 46.0, k), sin(k * TAU * 1.6 + _t * 24.0) * 11.0))
	draw_polyline(centerline, Color(1, 1, 1, 0.45 * fade), 1.0, true)
	for i in 3:
		draw_circle(Vector2(-30.0 + float(i) * 30.0, sin(float(i) * 2.1 + _t * 24.0) * 11.0),
			1.6, Color(tint, 0.6 * fade))
