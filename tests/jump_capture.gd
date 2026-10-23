extends Node
## Captures the jump tumble frame by frame to verify the square really turns
## 90 degrees and lands on a new face.

var _main: Node


func _ready() -> void:
	_main = $Main
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/screenshots"))
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout

	var player := Game.player
	print("start face=%d tumble=%.2f" % [player.face, player.tumble])

	Input.action_press("jump")
	await get_tree().create_timer(0.30).timeout
	Input.action_release("jump")

	for i in 8:
		await get_tree().create_timer(0.055).timeout
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png(ProjectSettings.globalize_path("res://output/screenshots/jump_%02d.png" % i))
		print("frame %d: y=%.1f vy=%.0f tumble=%.2f face=%d" % [
			i, player.global_position.y, player.velocity.y, player.tumble, player.face
		])

	await get_tree().create_timer(0.6).timeout
	print("landed face=%d tumble=%.2f on_floor=%s" % [player.face, player.tumble, str(player.is_on_floor())])
	get_tree().quit()
