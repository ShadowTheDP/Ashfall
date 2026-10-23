class_name TitleScreen
extends Control
## Keyboard-only title screen. Doubles as the visual thesis of the game:
## every element is a parametric curve (rose, Lissajous, log spiral, phyllotaxis).

signal started

const PALE := Color("#e9e2d2")
const AMBER := Color("#e8a33d")
const CYAN := Color("#8fe3ff")
const VIOLET := Color("#9b6bff")

var _t := 0.0
var _open := true
var _pressed_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 200
	get_tree().paused = true


func _process(delta: float) -> void:
	_t += delta
	if _pressed_t > 0.0:
		_pressed_t = maxf(0.0, _pressed_t - delta)
		if _pressed_t <= 0.0 and _open:
			_open = false
			visible = false
			get_tree().paused = false
			started.emit()
			queue_free()
			return
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_J, KEY_Z]:
			_pressed_t = 0.12
			Sfx.play("reward", -7)
			get_viewport().set_input_as_handled()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var size := get_viewport_rect().size
	var center := Vector2(size.x * 0.5, size.y * 0.42)

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.008, 0.011, 0.020, 0.94))

	_draw_rose_window(center, size)
	_draw_lissajous(center, size)
	_draw_phyllotaxis(center)
	_draw_sigil_ring(center)

	var title := "ASHFALL"
	draw_string(font, Vector2(center.x - 400.0, center.y - 30.0), title,
		HORIZONTAL_ALIGNMENT_CENTER, 800.0, 78, PALE)
	draw_string(font, Vector2(center.x - 400.0, center.y + 4.0),
		"a study in combat, geometry and consequence",
		HORIZONTAL_ALIGNMENT_CENTER, 800.0, 13, Color(0.72, 0.78, 0.86, 0.75))
	draw_line(Vector2(center.x - 110.0, center.y + 16.0), Vector2(center.x + 110.0, center.y + 16.0),
		Color(AMBER, 0.8), 2.0)
	MathArt.draw_poly(self, MathArt.ngon(3, 5.0, -PI * 0.5, Vector2(center.x, center.y + 16.0)),
		AMBER)

	var blink := 0.55 + 0.45 * sin(_t * 3.2)
	draw_string(font, Vector2(center.x - 300.0, size.y * 0.72),
		"PRESS  ENTER  TO  DESCEND",
		HORIZONTAL_ALIGNMENT_CENTER, 600.0, 18, Color(PALE, blink))

	var controls := "A / D  MOVE      SPACE  JUMP      J  SINE EDGE      K  KUNAI      L  AEGIS      SHIFT  ROLL"
	draw_string(font, Vector2(center.x - 480.0, size.y * 0.79), controls,
		HORIZONTAL_ALIGNMENT_CENTER, 960.0, 11, Color(0.55, 0.62, 0.72, 0.85))
	draw_string(font, Vector2(center.x - 480.0, size.y * 0.83),
		"ESC  PAUSE      R  RESTART      Q  QUIT      ·      EVERYTHING IS KEYBOARD",
		HORIZONTAL_ALIGNMENT_CENTER, 960.0, 10, Color(0.42, 0.48, 0.58, 0.7))


func _draw_rose_window(center: Vector2, size: Vector2) -> void:
	for i in 5:
		var radius := 90.0 + float(i) * 62.0
		var alpha := 0.11 - float(i) * 0.017
		MathArt.draw_ring(self, center, radius, Color(AMBER, alpha), 1.0, 128)
	for i in 24:
		var angle := TAU * float(i) / 24.0 + _t * 0.03
		draw_line(center + Vector2.from_angle(angle) * 100.0,
			center + Vector2.from_angle(angle) * 340.0,
			Color(0.55, 0.42, 0.20, 0.045), 1.0)
	# A 12-point star inscribed in the outermost ring.
	MathArt.draw_poly(self, MathArt.star(12, 338.0, 262.0, -PI * 0.5 + _t * 0.01, center),
		Color(0, 0, 0, 0), Color(AMBER, 0.05), 1.0)


func _draw_lissajous(center: Vector2, size: Vector2) -> void:
	var points := PackedVector2Array()
	var scale := size.y * 0.36
	for i in 240:
		var t := TAU * float(i) / 240.0
		points.append(center + MathArt.lissajous(t + _t * 0.12, 3.0, 2.0, PI * 0.5) * scale)
	draw_polyline(points, Color(CYAN, 0.10), 1.0, true)
	points.clear()
	for i in 240:
		var t := TAU * float(i) / 240.0
		points.append(center + MathArt.lissajous(t - _t * 0.09, 5.0, 4.0, PI * 0.25) * scale * 0.72)
	draw_polyline(points, Color(VIOLET, 0.07), 1.0, true)


func _draw_phyllotaxis(center: Vector2) -> void:
	for i in 90:
		var point := center + MathArt.phyllotaxis(i + 1, 11.0) + Vector2(0, -6)
		var alpha := 0.05 + 0.14 * (0.5 + 0.5 * sin(_t * 1.1 + float(i) * 0.35))
		var radius := 1.0 + 1.6 * (1.0 - float(i) / 90.0)
		var tint := AMBER if i % 4 == 0 else (CYAN if i % 4 == 1 else PALE)
		draw_circle(point, radius, Color(tint, alpha))


func _draw_sigil_ring(center: Vector2) -> void:
	for i in 7:
		var angle := _t * 0.35 + TAU * float(i) / 7.0
		var position := center + Vector2.from_angle(angle) * 232.0
		var sides := 3 + i % 4
		MathArt.draw_poly(self, MathArt.ngon(sides, 9.0, -angle * 1.4, position),
			Color(0, 0, 0, 0), Color(PALE, 0.10), 1.0)
	MathArt.draw_spiral(self, center, 240.0, 2.6, Color(AMBER, 0.055), 1.0, 120, _t * 0.02)
