extends StaticBody2D
## A local physical lock; changes collision deferred out of a physics flush.
signal opened
var spec: Dictionary = {}
var unlocked := false
var _shape: CollisionShape2D


func _ready() -> void:
	var rect: Rect2 = spec["rect"]
	position = rect.get_center()
	collision_layer = Layers.WORLD
	collision_mask = 0
	_shape = CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	_shape.shape = box
	add_child(_shape)


func try_open() -> bool:
	if unlocked:
		return true
	if str(spec["kind"]) != "key" or not Game.run_keys.has(str(spec["key"])):
		return false
	Game.run_keys.erase(str(spec["key"]))
	_open()
	return true


func try_break(player: Player) -> bool:
	if unlocked or str(spec["kind"]) != "break" or player.state != Player.State.DIVE or not Profile.unlocked_runes.has(str(spec["rune"])):
		return false
	_open()
	Juice.land_dust(get_parent(), global_position, 1.0)
	return true


func _open() -> void:
	unlocked = true
	_shape.set_deferred("disabled", true)
	set_deferred("collision_layer", 0)
	opened.emit()
	queue_redraw()


func _draw() -> void:
	if unlocked:
		return
	var rect: Rect2 = spec["rect"]
	var local := Rect2(-rect.size * 0.5, rect.size)
	var tint := MathArt.DANGER if str(spec["kind"]) == "break" else MathArt.GOLD
	MathArt.px_rect(self, local, MathArt.STONE_DIM)
	MathArt.poly(self, PackedVector2Array([local.position, Vector2(local.end.x, local.position.y), local.end, Vector2(local.position.x, local.end.y)]), Color.TRANSPARENT, tint, 2)
	if str(spec["kind"]) == "break":
		for i in 3:
			var x := local.position.x + local.size.x * (float(i) + 0.5) / 3.0
			MathArt.line(self, Vector2(x - 8, -4), Vector2(x, 4), tint, 2)
			MathArt.line(self, Vector2(x, 4), Vector2(x + 8, -4), tint, 2)
	else:
		for i in int(rect.size.y / (24.0 * MathArt.PHI)):
			var y := local.position.y + float(i + 1) * 24.0 * MathArt.PHI
			MathArt.line(self, Vector2(-8, y - 8), Vector2(8, y + 8), tint, 2)
