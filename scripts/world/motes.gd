class_name Motes
extends Node2D
## Slow ambient dust that makes the arena breathe.

var _motes: Array[Dictionary] = []


func _ready() -> void:
	z_index = -6
	for i in 70:
		_motes.append({
			"pos": Vector2(randf_range(-150.0, 1600.0), randf_range(-460.0, 80.0)),
			"vel": Vector2(randf_range(-7.0, 7.0), randf_range(-17.0, -5.0)),
			"radius": randf_range(0.6, 2.0),
			"alpha": randf_range(0.10, 0.38),
			"phase": randf() * TAU,
			"color": Color("#8fe3ff") if randf() < 0.6 else Color("#e8a33d"),
		})


func _process(delta: float) -> void:
	for mote in _motes:
		mote["pos"] += mote["vel"] * delta
		var position: Vector2 = mote["pos"]
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
		draw_circle(mote["pos"], float(mote["radius"]), tint)
