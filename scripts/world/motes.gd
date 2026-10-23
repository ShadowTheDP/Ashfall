class_name Motes
extends Node2D
## Ambient pixel dust placed by a phyllotaxis spiral, drifting on a harmonic.

var _motes: Array[Dictionary] = []


func _ready() -> void:
	z_index = -6
	var center := Vector2(720, -140)
	for i in 70:
		var radius := 500.0 * sqrt(randf())
		var angle := float(i) * MathArt.GOLDEN_ANGLE + randf() * 0.4
		var position := center + Vector2.from_angle(angle) * radius
		position.x = clampf(position.x, -140.0, 1580.0)
		position.y = clampf(position.y, -440.0, 60.0)
		_motes.append({
			"pos": position,
			"vel": Vector2(randf_range(-5.0, 5.0), randf_range(-14.0, -4.0)),
			"alpha": randf_range(0.10, 0.40),
			"phase": randf() * TAU,
			"color": MathArt.WHITE if i % 5 != 0 else MathArt.PALE_DIM,
		})


func _process(delta: float) -> void:
	for mote in _motes:
		var position: Vector2 = mote["pos"]
		var velocity: Vector2 = mote["vel"]
		mote["phase"] = float(mote["phase"]) + delta * 0.8
		position += Vector2(velocity.x + sin(float(mote["phase"])) * 4.0, velocity.y) * delta
		if position.y < -450.0:
			position.y = 80.0
			position.x = randf_range(-140.0, 1580.0)
		if position.x < -150.0:
			position.x = 1590.0
		elif position.x > 1590.0:
			position.x = -150.0
		mote["pos"] = position
	queue_redraw()


func _draw() -> void:
	var time := Time.get_ticks_msec() / 1000.0
	for mote in _motes:
		var tint: Color = mote["color"]
		tint.a = float(mote["alpha"]) * (0.55 + 0.45 * sin(time * 1.6 + float(mote["phase"])))
		var position: Vector2 = mote["pos"]
		MathArt.px_rect(self, Rect2(roundf(position.x), roundf(position.y), 1, 1), tint)
