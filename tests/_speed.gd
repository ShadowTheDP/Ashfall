extends Node
func _ready() -> void:
	Engine.max_fps = 0
	Engine.max_physics_steps_per_frame = 64
	var t0 := Time.get_ticks_msec()
	for i in 600:
		await get_tree().physics_frame
	print("600 physics frames in %d ms (fps=%d)" % [Time.get_ticks_msec() - t0, Engine.get_frames_per_second()])
	get_tree().quit()
