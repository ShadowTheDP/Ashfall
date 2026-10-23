class_name RewardScreen
extends Control
## Keyboard-only between-wave boon picker. Pauses the tree while open.

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
	var viewport_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.008, 0.012, 0.022, 0.80))
	draw_string(font, Vector2(viewport_size.x * 0.5 - 400.0, viewport_size.y * 0.20),
		"WAVE CLEARED", HORIZONTAL_ALIGNMENT_CENTER, 800.0, 36, Color("#e9e2d2"))
	draw_string(font, Vector2(viewport_size.x * 0.5 - 400.0, viewport_size.y * 0.20 + 30.0),
		"CHOOSE A BOON", HORIZONTAL_ALIGNMENT_CENTER, 800.0, 13, Color("#7c8fa3"))
	MathArt.draw_ring(self, Vector2(viewport_size.x * 0.5, viewport_size.y * 0.20 + 14.0), 180.0,
		Color(0.91, 0.64, 0.24, 0.20), 1.0, 64, PI * 0.08, PI * 0.92)

	var card_w := 280.0
	var card_h := 214.0
	var gap := 26.0
	var total_w := card_w * 3.0 + gap * 2.0
	var start_x := (viewport_size.x - total_w) * 0.5
	var card_y := viewport_size.y * 0.34

	for i in _choices.size():
		var x := start_x + float(i) * (card_w + gap)
		_draw_card(font, i, Rect2(x, card_y, card_w, card_h))

	var footer_y := card_y + card_h + 34.0
	draw_string(font, Vector2(viewport_size.x * 0.5 - 420.0, footer_y),
		"LEFT / RIGHT  SELECT        1 / 2 / 3  QUICK PICK        ENTER  CONFIRM",
		HORIZONTAL_ALIGNMENT_CENTER, 840.0, 11, Color("#7c8fa3"))


func _draw_card(font: Font, index: int, rect: Rect2) -> void:
	var id: String = _choices[index]
	var data: Dictionary = Data.rewards.get(id, {})
	var tint := Color(data.get("color", "#e8a33d"))
	var selected := index == _index
	var center := rect.position + Vector2(rect.size.x * 0.5, 0)
	var card_color := Color(0.035, 0.048, 0.075, 0.96) if selected else Color(0.025, 0.035, 0.055, 0.92)
	draw_rect(rect, card_color)
	draw_rect(rect, Color(tint, 0.85 if selected else 0.28), false, 2.0 if selected else 1.0)
	if selected:
		var pulse := 0.45 + 0.25 * sin(_t * 4.0)
		draw_rect(rect.grow(4.0), Color(tint, 0.16 * pulse), false, 1.0)
		MathArt.draw_ring(self, Vector2(center.x, rect.position.y + 74.0), 44.0,
			Color(tint, 0.28), 1.0, 48)

	# Card index (1/2/3)
	draw_string(font, rect.position + Vector2(12, 24), str(index + 1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(tint, 0.9))

	_draw_sigil(id, Vector2(center.x, rect.position.y + 74.0), 32.0, tint)
	draw_string(font, Vector2(rect.position.x, rect.position.y + 128.0),
		str(data.get("name", id)), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 20, Color("#e9e2d2"))

	var desc := str(data.get("desc", "")).split("\n")
	for line in desc.size():
		draw_string(font, Vector2(rect.position.x, rect.position.y + 156.0 + float(line) * 18.0),
			desc[line], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 12, Color("#9fb0c3"))

	var key_label := "1" if index == 0 else ("2" if index == 1 else "3")
	draw_string(font, Vector2(rect.position.x, rect.position.y + rect.size.y - 12.0),
		"PRESS " + key_label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 9, Color(tint, 0.65))


func _draw_sigil(id: String, center: Vector2, radius: float, tint: Color) -> void:
	match id:
		"vitality":
			var points := PackedVector2Array()
			var scale := radius / 17.0
			for i in 48:
				var theta := TAU * float(i) / 48.0
				var x := 16.0 * pow(sin(theta), 3.0)
				var y := 13.0 * cos(theta) - 5.0 * cos(2.0 * theta) - 2.0 * cos(3.0 * theta) - cos(4.0 * theta)
				points.append(center + Vector2(x, -y) * scale)
			MathArt.draw_poly(self, points, Color(tint, 0.18), Color(tint, 0.9), 1.4)
		"edge":
			MathArt.draw_poly(self, MathArt.ngon(3, radius, -PI * 0.5, center),
				Color(tint, 0.16), tint, 1.6)
		"swift":
			for i in 3:
				var y := center.y - 12.0 + float(i) * 12.0
				draw_line(Vector2(center.x - 18, y + 6), Vector2(center.x, y - 4), Color(tint, 0.9), 2.0)
				draw_line(Vector2(center.x, y - 4), Vector2(center.x + 18, y + 6), Color(tint, 0.9), 2.0)
		"ghost":
			MathArt.draw_ring(self, center, radius, Color(tint, 0.8), 1.4)
			MathArt.draw_ring(self, center, radius * 0.62, Color(tint, 0.35), 1.0)
			for i in 6:
				var angle := _t * 0.8 + TAU * float(i) / 6.0
				draw_circle(center + Vector2.from_angle(angle) * radius * 0.82, 2.0, Color(tint, 0.9))
		"armory":
			MathArt.draw_poly(self, MathArt.ngon(4, radius, PI * 0.25, center),
				Color(tint, 0.16), tint, 1.5)
			draw_line(center + Vector2(-radius * 0.7, 0), center + Vector2(radius * 0.7, 0), Color(tint, 0.55), 1.0)
		"leech":
			MathArt.draw_spiral(self, center, radius, 2.2, Color(tint, 0.9), 1.5, 48, _t * 0.3)
		"hunter":
			MathArt.draw_poly(self, MathArt.star(5, radius, radius * 0.42, -PI * 0.5, center),
				Color(tint, 0.16), tint, 1.4)
		_:
			MathArt.draw_sigil(self, center, radius, 6, _t * 0.2, tint)
