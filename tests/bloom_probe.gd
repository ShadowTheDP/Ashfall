extends Node
## Real screen-space glow checks at two render sizes, including an edge and HUD layer.
var _checks := 0
var _fails := 0

class Blocks extends Node2D:
	var boxes: Array[Rect2] = []
	var tone := MathArt.WHITE
	func _draw() -> void:
		for box in boxes:
			MathArt.poly(self, PackedVector2Array([box.position,
				box.position + Vector2(box.size.x, 0), box.end,
				box.position + Vector2(0, box.size.y)]), tone)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/screenshots/bloom"))
	for size in [Vector2i(128, 96), Vector2i(256, 192)]:
		var center: Vector2i = size / 2
		var viewport := SubViewport.new()
		viewport.size = size
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.world_2d = World2D.new()
		add_child(viewport)
		var blocks := Blocks.new()
		blocks.boxes.assign([Rect2(Vector2(center) - Vector2(6, 6), Vector2(12, 12)),
			Rect2(0, center.y - 6, 12, 12)])
		viewport.add_child(blocks)
		var layer := CanvasLayer.new()
		layer.layer = 15
		viewport.add_child(layer)
		var overlay := ColorRect.new()
		overlay.size = Vector2(size)
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/bloom.gdshader")
		overlay.material = material
		layer.add_child(overlay)
		var hud := CanvasLayer.new()
		hud.layer = 20
		viewport.add_child(hud)
		var ui := Blocks.new()
		ui.boxes.assign([Rect2(center.x + 28, center.y - 2, 4, 4)])
		hud.add_child(ui)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		image.save_png("res://output/screenshots/bloom/%dx%d.png" % [size.x, size.y])
		var dark := image.get_pixel(size.x - 8, size.y - 8).r
		_check(image.get_pixel(center.x, center.y).r > 0.95, "bright body remains white")
		_check(image.get_pixel(center.x + 7, center.y).r > dark + 0.01, "local 2px glow at %s" % size)
		_check(image.get_pixel(center.x + 9, center.y).r > dark + 0.01, "local 4px glow at %s" % size)
		_check(image.get_pixel(center.x + 12, center.y).r < dark + 0.005, "glow stays local")
		_check(image.get_pixel(13, center.y).r > dark + 0.01, "edge block has local glow")
		_check(image.get_pixel(32, center.y).r < dark + 0.005, "edge does not brighten distant pixels")
		_check(image.get_pixel(center.x + 29, center.y).r > 0.95, "HUD stays above postprocess")
		_check(image.get_pixel(center.x + 33, center.y).r < dark + 0.005, "HUD does not enter world bloom")
		# Saturated fixtures must glow without whitening; white-body checks above remain.
		for tone: Color in [Color(0.0, 1.0, 1.0), Color(1.0, 0.0, 0.0)]:
			blocks.tone = tone
			blocks.queue_redraw()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var colored := viewport.get_texture().get_image()
			var glow := colored.get_pixel(center.x + 7, center.y)
			var base := colored.get_pixel(size.x - 8, size.y - 8)
			var cyan := tone.g > 0.5
			var dominant := glow.g - base.g if cyan else glow.r - base.r
			var unwanted := absf(glow.r - base.r) if cyan else maxf(absf(glow.g - base.g), absf(glow.b - base.b))
			_check(dominant > 0.01 and unwanted < 0.005, "saturated %s glow retains hue at %s" % ["cyan" if cyan else "red", size])
			if cyan:
				_check(absf((glow.g - base.g) - (glow.b - base.b)) < 0.005, "cyan glow keeps balanced green/blue channels")
			_check(colored.get_pixel(center.x + 29, center.y).r > 0.95, "HUD remains white above colored bloom")
			_check(colored.save_png("res://output/screenshots/bloom/%dx%d-%s.png" % [size.x, size.y, "cyan" if cyan else "red"]) == OK, "save saturated glow capture")
		viewport.queue_free()
		await get_tree().process_frame
	print("BLOOM %s: %d checks, %d failures" % ["OK" if _fails == 0 else "FAILED", _checks, _fails])
	get_tree().quit(1 if _fails else 0)


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("BLOOM FAIL: " + message)
