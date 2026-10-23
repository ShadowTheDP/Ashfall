class_name TitleScreen
extends Control
## Keyboard-only pixel title. The composition is a rose window (circles),
## a Lissajous figure (curves) and a phyllotaxis field (points).

signal started

const PALE := MathArt.PALE
const AMBER := MathArt.AMBER
const AMBER_HI := MathArt.AMBER_HI
const CYAN := MathArt.CYAN
const VIOLET := MathArt.VIOLET

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
	var center := Vector2(roundf(size.x * 0.5), roundf(size.y * 0.40))

	MathArt.px_rect(self, Rect2(0, 0, size.x, size.y), Color(0.02, 0.028, 0.04, 0.96))

	_draw_rose_window(center)
	_draw_lissajous(center)
	_draw_phyllotaxis(center)
	_draw_orbit_sigils(center)

	draw_string(font, Vector2(center.x - 200.0, center.y), "ASHFALL",
		HORIZONTAL_ALIGNMENT_CENTER, 400.0, 28, PALE)
	draw_string(font, Vector2(center.x - 200.0, center.y + 16.0),
		"combat, geometry and consequence",
		HORIZONTAL_ALIGNMENT_CENTER, 400.0, 7, Color(0.72, 0.78, 0.86, 0.8))
	MathArt.px_rect(self, Rect2(center.x - 56.0, center.y + 22.0, 112, 1), Color(AMBER, 0.85))
	MathArt.px_poly(self, MathArt.ngon(3, 3.0, -PI * 0.5, Vector2(center.x, center.y + 22.0)), AMBER)

	var blink := 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 3.4))
	draw_string(font, Vector2(center.x - 150.0, roundf(size.y * 0.70)), "PRESS ENTER TO DESCEND",
		HORIZONTAL_ALIGNMENT_CENTER, 300.0, 10, Color(PALE, blink))

	draw_string(font, Vector2(center.x - 240.0, roundf(size.y * 0.79)),
		"A/D MOVE    SPACE JUMP    J SINE EDGE    K KUNAI    L AEGIS    SHIFT ROLL",
		HORIZONTAL_ALIGNMENT_CENTER, 480.0, 6, Color(0.55, 0.62, 0.72, 0.9))
	draw_string(font, Vector2(center.x - 240.0, roundf(size.y * 0.85)),
		"ESC PAUSE      R RESTART      Q QUIT      EVERYTHING IS KEYBOARD",
		HORIZONTAL_ALIGNMENT_CENTER, 480.0, 6, Color(0.42, 0.48, 0.58, 0.8))


func _draw_rose_window(center: Vector2) -> void:
	for i in 4:
		var radius := 52.0 + float(i) * 30.0
		MathArt.px_ring(self, center, radius, Color(AMBER, 0.14 - float(i) * 0.025), 1.0)
	for i in 16:
		var angle := TAU * float(i) / 16.0 + _t * 0.02
		var from_point := center + Vector2.from_angle(angle) * 54.0
		var to_point := center + Vector2.from_angle(angle) * 140.0
		MathArt.px_line(self, from_point, to_point, Color(0.55, 0.42, 0.20, 0.07), 1.0)
	# star() already places points around `center`; do not offset again.
	var star_points := MathArt.star(12, 138.0, 108.0, -PI * 0.5 + _t * 0.01, center)
	for i in star_points.size():
		MathArt.px_line(self, star_points[i], star_points[(i + 1) % star_points.size()], Color(AMBER, 0.10), 1.0)


func _draw_lissajous(center: Vector2) -> void:
	# Dots instead of polylines: a 1px polyline is anti-aliased, a 1px dot is not.
	var scale := 118.0
	for i in 220:
		var t := TAU * float(i) / 220.0
		var point := center + MathArt.lissajous(t + _t * 0.14, 3.0, 2.0, PI * 0.5) * scale
		if i % 2 == 0:
			MathArt.px_rect(self, Rect2(roundf(point.x), roundf(point.y), 1, 1), Color(CYAN, 0.30))
	for i in 220:
		var t := TAU * float(i) / 220.0
		var point := center + MathArt.lissajous(t - _t * 0.10, 5.0, 4.0, PI * 0.25) * scale * 0.66
		if i % 3 == 0:
			MathArt.px_rect(self, Rect2(roundf(point.x), roundf(point.y), 1, 1), Color(VIOLET, 0.26))


func _draw_phyllotaxis(center: Vector2) -> void:
	for i in 70:
		var point := center + MathArt.phyllotaxis(i + 1, 7.0)
		var alpha := 0.10 + 0.22 * (0.5 + 0.5 * sin(_t * 1.2 + float(i) * 0.4))
		var tint := AMBER_HI if i % 4 == 0 else (CYAN if i % 4 == 1 else PALE)
		MathArt.px_rect(self, Rect2(roundf(point.x), roundf(point.y), 1, 1), Color(tint, alpha))


func _draw_orbit_sigils(center: Vector2) -> void:
	for i in 6:
		var angle := _t * 0.4 + TAU * float(i) / 6.0
		var position := center + Vector2.from_angle(angle) * 132.0
		var sides := 3 + i % 4
		MathArt.px_poly(self, MathArt.ngon(sides, 5.0, -angle * 1.6, position),
			Color(0, 0, 0, 0), Color(PALE, 0.16), 1.0)
