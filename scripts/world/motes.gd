class_name Motes
extends Node2D
## Ambient dust placed by a phyllotaxis spiral. Motion is a slow harmonic
## drift, so the field never repeats visibly.

var _motes: Array[Dictionary] = []


func _ready() -> void:
	z_index = -6
	var center := Vector2(720, -160)
	for i in 90:
		var radius := 520.0 * sqrt(randf())
		var angle := float(i) * MathArt.GOLDEN_ANGLE + randf() * 0.35
		var position := center + Vector2.from_angle(angle) * radius
		position.x = clampf(position.x, -150.0, 1600.0)
		position.y = clampf(position.y, -470.0, 70.0)
		_motes.append({
			"pos": position,
			"vel": Vector2(randf_range(-6.0, 6.0), randf_range(-16.0, -4.0)),
			"radius": randf_range(0.7, 2.2),
			"alpha": randf_range(0.08, 0.34),
			"phase": randf() * TAU,
			"shape": i % 3,
			"color": Color("#8fe3ff") if i % 5 != 0 else Color("#e8a33d"),
		})


func _process(delta: float) -> void:
	for mote in _motes:
		var position: Vector2 = mote["pos"]
		var velocity: Vector2 = mote["vel"]
		mote["phase"] = float(mote["phase"]) + delta * 0.7
		position += Vector2(velocity.x + sin(float(mote["phase"])) * 4.0, velocity.y) * delta
		if position.y < -470.0:
			position.y = 90.0
			position.x = randf_range(-150.0, 1600.0)
		if position.x < -160.0:
			position.x = 1610.0
		elif position.x > 1610.0:
			position.x = -160.0
		mote["pos"] = position
	queue_redraw()


func _draw() -> void:
	var time := Time.get_ticks_msec() / 1000.0
	for mote in _motes:
		var tint: Color = mote["color"]
		var pulse := 0.6 + 0.4 * sin(time * 1.7 + float(mote["phase"]))
		tint.a = float(mote["alpha"]) * pulse
		var position: Vector2 = mote["pos"]
		var radius: float = mote["radius"]
		match int(mote["shape"]):
			0:
				draw_circle(position, radius, tint)
			1:
				MathArt.draw_poly(self, MathArt.ngon(4, radius * 1.4, float(mote["phase"]), position),
					Color(tint, tint.a * 0.8))
			_:
				MathArt.draw_poly(self, MathArt.ngon(3, radius * 1.5, -float(mote["phase"]), position),
					Color(tint, tint.a * 0.7))
