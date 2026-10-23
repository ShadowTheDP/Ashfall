class_name RewardScreen
extends Control
## Keyboard-only between-wave boon picker, drawn as three pixel cards.

signal chosen(id: String)

var _choices: Array = []
var _index := 0
var _open := false
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	z_index = 100


func open(choices: Array) -> void:
	_choices = choices.duplicate()
	_index = 0
	_open = true
	_t = 0.0
	visible = true
	Game.reward_open = true
	get_tree().paused = true
	Combat.cancel_hitstop()
	Sfx.play("reward", -8)
	queue_redraw()


func _process(delta: float) -> void:
	if _open:
		_t += delta
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_1:
			_pick(0)
		KEY_2:
			_pick(1)
		KEY_3:
			_pick(2)
		KEY_LEFT, KEY_A:
			_index = wrapi(_index - 1, 0, _choices.size())
			Sfx.play("ui", -12)
			queue_redraw()
		KEY_RIGHT, KEY_D:
			_index = wrapi(_index + 1, 0, _choices.size())
			Sfx.play("ui", -12)
			queue_redraw()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_pick(_index)
		_:
			return
	get_viewport().set_input_as_handled()


func _pick(index: int) -> void:
	if not _open or index < 0 or index >= _choices.size():
		return
	var id: String = _choices[index]
	_open = false
	visible = false
	Game.reward_open = false
	Game.apply_reward(id)
	get_tree().paused = false
	chosen.emit(id)


func _draw() -> void:
	if not _open:
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var size := get_viewport_rect().size
	MathArt.px_rect(self, Rect2(0, 0, size.x, size.y), Color(0.028, 0.028, 0.028, 0.86))
	var mid_x := roundf(size.x * 0.5)
	var title_y := roundf(size.y * 0.17)
	draw_string(font, Vector2(mid_x - 160.0, title_y), "WAVE CLEARED",
		HORIZONTAL_ALIGNMENT_CENTER, 360.0, 26, MathArt.PALE)
	draw_string(font, Vector2(mid_x - 160.0, title_y + 16.0), "CHOOSE A BOON",
		HORIZONTAL_ALIGNMENT_CENTER, 320.0, 7, MathArt.LIGHT)
	MathArt.px_rect(self, Rect2(mid_x - 46.0, title_y + 23.0, 110, 1), Color(MathArt.PALE_DIM, 0.7))

	var card_w := 178.0
	var card_h := 132.0
	var gap := 18.0
	var total_w := card_w * 3.0 + gap * 2.0
	var start_x := roundf((size.x - total_w) * 0.5)
	var card_y := roundf(size.y * 0.30)

	for i in _choices.size():
		_draw_card(font, i, Rect2(start_x + float(i) * (card_w + gap), card_y, card_w, card_h))

	draw_string(font, Vector2(mid_x - 220.0, card_y + card_h + 22.0),
		"LEFT/RIGHT SELECT      1/2/3 QUICK PICK      ENTER CONFIRM",
		HORIZONTAL_ALIGNMENT_CENTER, 440.0, 6, MathArt.LIGHT)


func _draw_card(font: Font, index: int, rect: Rect2) -> void:
	var id: String = _choices[index]
	var data: Dictionary = Data.rewards.get(id, {})
	var tint := Color(data.get("color", "#dfe4ea"))
	var selected := index == _index
	var center := Vector2(roundf(rect.position.x + rect.size.x * 0.5), rect.position.y)

	MathArt.px_rect(self, rect, Color(0.080, 0.080, 0.080, 0.97) if selected else Color(0.053, 0.053, 0.053, 0.94))
	MathArt.px_rect(self, Rect2(rect.position, Vector2(rect.size.x, 1)), Color(tint, 0.9 if selected else 0.3))
	MathArt.px_rect(self, Rect2(rect.position + Vector2(0, rect.size.y - 1.0), Vector2(rect.size.x, 1)), Color(tint, 0.55 if selected else 0.2))
	MathArt.px_rect(self, Rect2(rect.position, Vector2(1, rect.size.y)), Color(tint, 0.55 if selected else 0.2))
	MathArt.px_rect(self, Rect2(rect.position + Vector2(rect.size.x - 1.0, 0), Vector2(1, rect.size.y)), Color(tint, 0.55 if selected else 0.2))
	if selected:
		var pulse := 0.35 + 0.35 * sin(_t * 5.0)
		draw_rect(Rect2(rect.position.x - 2.0, rect.position.y - 2.0, rect.size.x + 4.0, rect.size.y + 4.0),
			Color(tint, 0.10 * pulse), false, 1.0)

	draw_string(font, rect.position + Vector2(6, 12), str(index + 1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(tint, 0.9))

	var sigil_center := Vector2(center.x, rect.position.y + 52.0)
	_draw_sigil(id, sigil_center, 22.0, tint)

	draw_string(font, Vector2(rect.position.x, rect.position.y + 84.0), str(data.get("name", id)),
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 14, MathArt.PALE)

	var lines: PackedStringArray = str(data.get("desc", "")).split("\n")
	for line in lines.size():
		draw_string(font, Vector2(rect.position.x, rect.position.y + 100.0 + float(line) * 12.0),
			lines[line], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 9, Color(0.725, 0.725, 0.725))

	var key_label := str(index + 1)
	draw_string(font, Vector2(rect.position.x, rect.position.y + rect.size.y - 6.0),
		"PRESS " + key_label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 8, Color(tint, 0.7))


func _draw_sigil(id: String, center: Vector2, radius: float, tint: Color) -> void:
	match id:
		"vitality":
			# Cardioid: x = 16 sin^3 t, y = 13 cos t - 5 cos 2t - 2 cos 3t - cos 4t
			var points := PackedVector2Array()
			var scale := radius / 17.0
			for i in 32:
				var theta := TAU * float(i) / 32.0
				var x := 16.0 * pow(sin(theta), 3.0)
				var y := 13.0 * cos(theta) - 5.0 * cos(2.0 * theta) - 2.0 * cos(3.0 * theta) - cos(4.0 * theta)
				points.append(center + Vector2(x, -y) * scale)
			MathArt.px_poly(self, points, Color(tint, 0.22), tint, 1.0)
		"edge":
			MathArt.px_poly(self, MathArt.ngon(3, radius, -PI * 0.5, center), Color(tint, 0.20), tint, 1.0)
		"swift":
			for i in 3:
				var y := center.y - 7.0 + float(i) * 7.0
				MathArt.px_line(self, Vector2(center.x - 11, y + 4), Vector2(center.x, y - 3), tint, 1.0)
				MathArt.px_line(self, Vector2(center.x, y - 3), Vector2(center.x + 11, y + 4), tint, 1.0)
		"ghost":
			MathArt.px_ring(self, center, radius, tint, 1.0)
			MathArt.px_ring(self, center, radius * MathArt.INV_PHI, Color(tint, 0.5), 1.0)
			for i in 6:
				var angle := _t * 0.9 + TAU * float(i) / 6.0
				var point := center + Vector2.from_angle(angle) * radius * 0.82
				MathArt.px_rect(self, Rect2(roundf(point.x), roundf(point.y), 1, 1), tint)
		"armory":
			MathArt.px_poly(self, MathArt.ngon(4, radius * 0.8, PI * 0.25, center), Color(tint, 0.20), tint, 1.0)
			MathArt.px_line(self, center + Vector2(-radius * 0.6, 0), center + Vector2(radius * 0.6, 0), Color(tint, 0.7), 1.0)
		"leech":
			var spiral := MathArt.spiral(radius, 1.8, 26, _t * 0.4)
			for point in spiral:
				MathArt.px_rect(self, Rect2(roundf(center.x + point.x), roundf(center.y + point.y), 1, 1), tint)
		"hunter":
			MathArt.px_poly(self, MathArt.star(5, radius, radius * 0.42, -PI * 0.5, center), Color(tint, 0.20), tint, 1.0)
		_:
			MathArt.px_poly(self, MathArt.ngon(6, radius, _t * 0.2, center), Color(0, 0, 0, 0), tint, 1.0)
