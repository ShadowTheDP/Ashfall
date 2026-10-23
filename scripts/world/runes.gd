class_name Runes
extends Node2D
## Floating geometric runes that make the background feel like a mathematical
## diagram rather than empty air. Purely decorative.

var _t := 0.0
var _runes := [
	{"pos": Vector2(210, -270), "sides": 3, "radius": 26.0, "color": Color("#e8a33d"), "speed": 0.22, "phase": 0.4},
	{"pos": Vector2(560, -340), "sides": 6, "radius": 20.0, "color": Color("#8fe3ff"), "speed": -0.16, "phase": 1.8},
	{"pos": Vector2(930, -250), "sides": 4, "radius": 24.0, "color": Color("#9b6bff"), "speed": 0.18, "phase": 3.1},
	{"pos": Vector2(1260, -330), "sides": 5, "radius": 22.0, "color": Color("#e8a33d"), "speed": -0.14, "phase": 4.4},
	{"pos": Vector2(1470, -190), "sides": 7, "radius": 18.0, "color": Color("#8fe3ff"), "speed": 0.20, "phase": 5.2},
]


func _ready() -> void:
	z_index = -4


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	for rune in _runes:
		var center: Vector2 = rune["pos"]
		var tint: Color = rune["color"]
		var pulse := 0.55 + 0.45 * sin(_t * 1.3 + float(rune["phase"]))
		var rotation := _t * float(rune["speed"]) + float(rune["phase"])
		var radius: float = rune["radius"]
		MathArt.draw_poly(self, MathArt.ngon(int(rune["sides"]), radius, rotation, center),
			Color(tint, 0.035 * pulse), Color(tint, 0.16 * pulse), 1.0)
		MathArt.draw_poly(self, MathArt.ngon(int(rune["sides"]), radius * MathArt.INV_PHI, -rotation, center),
			Color(0, 0, 0, 0), Color(tint, 0.10 * pulse), 1.0)
		MathArt.draw_ring(self, center, radius * 1.35, Color(tint, 0.055 * pulse), 1.0, 32)
		draw_circle(center, 1.4, Color(tint, 0.35 * pulse))
