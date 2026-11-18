extends Node2D
## Renders the real BurstFx block mode on the game's black clear colour and
## measures which side of each centre it actually paints, so the facing is proven
## by pixels instead of by re-deriving the angle formula inside the test.
## Needs a display; run as `python tools/check.py --capture burstside`.

const RIGHT_AT := Vector2(200, 240)
const LEFT_AT := Vector2(568, 240)
const SPAN := 60.0

var _checks := 0
var _fails := 0
const SHOT_DIR := "res://output/screenshots/burst-side"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var right := _make(1, RIGHT_AT)
	var left := _make(-1, LEFT_AT)
	await RenderingServer.frame_post_draw
	await _save("sector")
	await _measure(right, "sector")
	await _measure(left, "sector")
	for fx in [right, left]:
		fx._t = fx._life * 0.5
		fx.queue_redraw()
	await RenderingServer.frame_post_draw
	await _save("rays")
	# At mid-life the block also draws a symmetric ring, so the directional read
	# can only be measured outside that ring where the rays stick out.
	await _beyond_ring(right)
	await _beyond_ring(left)
	print("BURST SIDE OK (%d checks)" % _checks if _fails == 0 else "BURST SIDE FAILED (%d/%d)" % [_fails, _checks])
	get_tree().quit(1 if _fails else 0)


func _make(facing: int, at: Vector2) -> BurstFx:
	var fx := BurstFx.new()
	fx.position = at
	add_child(fx)
	fx.setup("block", MathArt.PICKUP, facing)
	fx.set_process(false)
	return fx


## The two bursts sit 368 px apart, so a ±60 px window around one centre can only
## contain that burst's own pixels.
func _measure(fx: BurstFx, stage: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var sum := 0.0
	var count := 0
	for x in range(int(fx.position.x - SPAN), int(fx.position.x + SPAN)):
		for y in range(int(fx.position.y - 40), int(fx.position.y + 40)):
			var color := image.get_pixel(x, y)
			if maxf(color.r, maxf(color.g, color.b)) > 0.12:
				sum += float(x)
				count += 1
	_check(count > 40, "%s burst paints a visible amount (facing %d, %d px)" % [stage, fx.facing, count])
	var offset := sum / float(maxi(count, 1)) - fx.position.x
	_check(offset * float(fx.facing) > 2.0,
		"block %s paints the side it faces (facing %d, offset %.2f px)" % [stage, fx.facing, offset])


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("BURST SIDE FAIL: " + message)


func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(SHOT_DIR.path_join(label + ".png"))
	_check(image.save_png(path) == OK, "native capture written: " + path)


## The expanding ring is symmetric by design; the rays are what carries the side.
## Compare bright pixels beyond the ring radius on each side of the centre.
func _beyond_ring(fx: BurstFx) -> void:
	var image := get_viewport().get_texture().get_image()
	var near := 0
	var far := 0
	for dx in range(12, 20):
		for dy in range(-20, 21):
			if _bright(image, fx.position + Vector2(float(dx) * float(fx.facing), float(dy))):
				near += 1
			if _bright(image, fx.position + Vector2(float(-dx) * float(fx.facing), float(dy))):
				far += 1
	_check(near > far, "block rays extend past the ring on the facing side (facing %d, %d vs %d px)" % [fx.facing, near, far])


func _bright(image: Image, at: Vector2) -> bool:
	var color := image.get_pixel(int(at.x), int(at.y))
	return maxf(color.r, maxf(color.g, color.b)) > 0.12
