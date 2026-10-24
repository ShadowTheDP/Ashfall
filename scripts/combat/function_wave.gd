class_name FunctionWave
extends Area2D
## The Sine Edge finisher: the blade's function released as a travelling wave.
## Drawn as a stack of 1px pixel columns so it matches the rest of the art.

var source: Node2D = null
var damage := 8.0
var crit_mult := 1.5
## Colour-scaling level, set by the player before setup().
var attr := 0
var direction := 1
var speed := 540.0
var tint := MathArt.WHITE
var _t := 0.0
var _life := 0.42
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
	rect.size = Vector2(88.0, 68.0)
	shape.shape = rect
	add_child(shape)
	body_entered.connect(_on_body_entered)
	Combat.burst(global_position, MathArt.WHITE, 6, 120.0)


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
		"damage": Damage.compute(damage, attr, crit, crit_mult),
		"crit": crit,
		"knockback": 240.0,
		"hitstop": 0.03,
		"source_pos": global_position,
		"point": body.global_position,
	})
	Combat.spark(body.global_position + Vector2(0, -16), Vector2(float(direction), 0), crit, tint)


func _draw() -> void:
	var fade := clampf(1.0 - _t / _life, 0.0, 1.0)
	var samples := 30
	for i in samples:
		var k := float(i) / float(samples - 1)
		var x := roundf(lerpf(-40.0, 40.0, k))
		var y := roundf(sin(k * TAU * 1.7 + _t * 26.0) * 10.0)
		var height := roundf(lerpf(1.0, 5.0, sin(k * PI)) * fade) + 1.0
		# Two-tone column: cyan body, white crest.
		MathArt.px_rect(self, Rect2(x, y - height, 1, height * 2.0), Color(tint, 0.55 * fade))
		MathArt.px_rect(self, Rect2(x, y - 1, 1, 2), Color(MathArt.WHITE, 0.75 * fade))
		if i % 6 == 0:
			MathArt.px_rect(self, Rect2(x, y - height - 2, 1, 2), Color(tint, 0.45 * fade))
