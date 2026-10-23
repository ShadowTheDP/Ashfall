class_name Runes
extends Node2D
## Floating pixel sigils. Each is a regular polygon with a 1/phi inner outline.

var _t := 0.0
var _runes := [
	{"pos": Vector2(210, -240), "sides": 3, "radius": 20.0, "color": MathArt.AMBER, "speed": 0.20, "phase": 0.4},
	{"pos": Vector2(560, -290), "sides": 6, "radius": 15.0, "color": MathArt.CYAN, "speed": -0.15, "phase": 1.8},
	{"pos": Vector2(930, -225), "sides": 4, "radius": 18.0, "color": MathArt.VIOLET, "speed": 0.17, "phase": 3.1},
	{"pos": Vector2(1260, -280), "sides": 5, "radius": 17.0, "color": MathArt.AMBER, "speed": -0.13, "phase": 4.4},
	{"pos": Vector2(1470, -180), "sides": 7, "radius": 14.0, "color": MathArt.CYAN, "speed": 0.19, "phase": 5.2},
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
		var sides := int(rune["sides"])
		MathArt.px_poly(self, MathArt.ngon(sides, radius, rotation, center),
			Color(tint, 0.05 * pulse), Color(tint, 0.22 * pulse), 1.0)
		MathArt.px_poly(self, MathArt.ngon(sides, radius * MathArt.INV_PHI, -rotation, center),
			Color(0, 0, 0, 0), Color(tint, 0.14 * pulse), 1.0)
		MathArt.px_rect(self, Rect2(roundf(center.x), roundf(center.y), 1, 1), Color(tint, 0.5 * pulse))
