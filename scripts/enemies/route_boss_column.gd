class_name RouteBossColumn
extends Hitbox
## A delayed floor rectangle; the drawn outline and collision share one shape.

const MAX_TTL := 6.0

var delay := 0.0
var duration := 0.0
var size := Vector2.ZERO
var age := 0.0
var _armed := false


func _ready() -> void:
	collision_mask = Layers.PLAYER
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	add_child(shape)
	super._ready()


func _physics_process(delta: float) -> void:
	age += delta
	if not is_instance_valid(source) or source._dead or source.is_queued_for_deletion() or Game.run_over or age >= minf(delay + duration, MAX_TTL):
		disable()
		queue_free()
		return
	if not _armed and age >= delay:
		_armed = true
		enable(damage, knockback, 0.0, source, 1.0, 2)
	queue_redraw()


func _try_hit(body: Node) -> void:
	if is_instance_valid(source) and not source._dead and not source.is_queued_for_deletion() and not is_queued_for_deletion() and not Game.run_over:
		super._try_hit(body)


func _draw() -> void:
	var points := PackedVector2Array([
		-size * 0.5, Vector2(size.x, -size.y) * 0.5,
		size * 0.5, Vector2(-size.x, size.y) * 0.5,
	])
	MathArt.poly(self, points, Color(MathArt.INK, 0.18),
		MathArt.DANGER if active else Color(MathArt.DANGER, 0.65), 2.0)
	var inset := size.x * MathArt.INV_PHI * 0.5
	MathArt.line(self, Vector2(-inset, size.y * 0.5), Vector2(inset, size.y * 0.5), MathArt.DANGER, 3.0)
	if active:
		MathArt.line(self, Vector2(0.0, -size.y * 0.5), Vector2(0.0, size.y * 0.5), MathArt.DANGER, 2.0)
