class_name Braziers
extends Node2D
## Pixel braziers: hex plinth, chunky flame, 1px embers on a phyllotaxis drift.

const AMBER := MathArt.AMBER
const FLAME := MathArt.AMBER_HI
const EMBER := MathArt.RED_HI

var _t := 0.0
var _positions := [Vector2(40, 0), Vector2(420, 0), Vector2(820, 0), Vector2(1210, 0), Vector2(1540, 0)]


func _ready() -> void:
	z_index = 0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	for index in _positions.size():
		_draw_brazier(_positions[index], float(index) * 1.7)


func _draw_brazier(base: Vector2, phase: float) -> void:
	var flicker := 0.5 + 0.5 * sin(_t * 7.0 + phase)
	var ground := base + Vector2(0, -2)

	# Light pool: two chunky ellipses.
	MathArt.px_rect(self, Rect2(ground.x - 26.0, ground.y - 1.0, 52.0, 3.0), Color(AMBER, 0.05 + 0.02 * flicker))
	MathArt.px_rect(self, Rect2(ground.x - 16.0, ground.y - 3.0, 32.0, 2.0), Color(AMBER, 0.07 + 0.03 * flicker))

	# Hex plinth.
	var plinth := MathArt.ngon(6, 15.0, PI / 6.0, base + Vector2(0, -9))
	MathArt.px_poly(self, plinth, MathArt.STONE_2, Color(MathArt.AMBER_DIM, 0.65), 1.0)
	MathArt.px_rect(self, Rect2(base.x - 13.0, base.y - 13.0, 26.0, 5.0), MathArt.STONE_3)
	MathArt.px_rect(self, Rect2(base.x - 13.0, base.y - 13.0, 26.0, 1.0), Color(MathArt.AMBER_DIM, 0.55))

	# Flame: four stacked bands, widths from a rose curve.
	var heights := [10.0, 8.0, 6.0, 4.0]
	for band in 4:
		var k := float(band) / 3.0
		var sway := roundf(sin(_t * 5.0 + phase + k * 1.6) * (1.0 + k * 2.0))
		var width: float = float(heights[band]) * (1.0 + 0.12 * flicker)
		var y := base.y - 15.0 - float(band) * 5.0
		var tint := Color(EMBER, 0.55 + 0.1 * float(band))
		if band >= 2:
			tint = Color(FLAME, 0.55 + 0.12 * float(band))
		MathArt.px_rect(self, Rect2(roundf(base.x - width * 0.5 + sway), roundf(y), roundf(width), 5.0), tint)
	# Hot core.
	MathArt.px_rect(self, Rect2(base.x - 2.0, base.y - 22.0, 4, 6), Color(MathArt.WHITE, 0.55 + 0.2 * flicker))

	# Embers: 1px, rising on a phyllotaxis spread.
	for i in 5:
		var p := MathArt.phyllotaxis(i + 1, 4.0)
		var rise := fmod(_t * (10.0 + float(i) * 2.0) + phase * 9.0, 34.0)
		var pos := base + Vector2(roundf(p.x * 0.6), roundf(-26.0 - rise + p.y * 0.2))
		var alpha := (1.0 - rise / 34.0) * 0.7
		MathArt.px_rect(self, Rect2(pos.x, pos.y, 1, 1), Color(FLAME, alpha))
