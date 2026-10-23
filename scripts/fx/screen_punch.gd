class_name ScreenPunch
extends Node2D
## Full-screen feedback for heavy hits, drawn in a CanvasLayer above the world
## but below the HUD. Monochrome only:
##   - a vignette pulse (darkens the edges, keeps the centre clear)
##   - two 1px horizontal scanline bands offset horizontally for 2 frames
##
## Everything is intentionally short: the screen is never tinted or inverted.

var strength := 0.0
var _t := 0.0
var _life := 0.22
var _bands: Array[Dictionary] = []


func setup(p_strength: float) -> void:
	strength = clampf(p_strength, 0.0, 1.0)
	_life = 0.10 + 0.12 * strength
	_bands.clear()
	var count := 2 if strength > 0.55 else 1
	for i in count:
		_bands.append({
			"y": randf_range(0.18, 0.82),
			"height": 1.0 if strength < 0.8 else 2.0,
			"offset": randf_range(2.0, 4.0) * (1.0 if i % 2 == 0 else -1.0),
			"life": 0.033,
		})
	z_index = 0


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size

	# Vignette pulse: 0 -> peak in 1 frame, then back to 0.
	var vignette_k := clampf(_t / 0.016, 0.0, 1.0) * clampf(1.0 - _t / _life, 0.0, 1.0)
	var peak := 0.10 + 0.10 * strength
	if vignette_k > 0.0:
		for i in 4:
			var inset := float(i) * 14.0
			var alpha := peak * vignette_k * (0.35 - float(i) * 0.08)
			if alpha <= 0.0:
				continue
			MathArt.px_rect(self, Rect2(inset, inset, size.x - inset * 2.0, 3.0), Color(0.0, 0.0, 0.0, alpha))
			MathArt.px_rect(self, Rect2(inset, size.y - inset - 3.0, size.x - inset * 2.0, 3.0), Color(0.0, 0.0, 0.0, alpha))
			MathArt.px_rect(self, Rect2(inset, inset, 3.0, size.y - inset * 2.0), Color(0.0, 0.0, 0.0, alpha))
			MathArt.px_rect(self, Rect2(size.x - inset - 3.0, inset, 3.0, size.y - inset * 2.0), Color(0.0, 0.0, 0.0, alpha))

	# Scanline offset: two 1px bands slide sideways for 2 frames.
	for band in _bands:
		var band_life: float = band["life"]
		if _t > band_life:
			continue
		var k := 1.0 - _t / band_life
		var y := float(band["y"]) * size.y
		var height: float = band["height"]
		var offset: float = float(band["offset"]) * k
		MathArt.px_rect(self, Rect2(offset, y, size.x, height), Color(1.0, 1.0, 1.0, 0.16 * k))
		MathArt.px_rect(self, Rect2(-offset, y + height, size.x, height), Color(0.0, 0.0, 0.0, 0.22 * k))
