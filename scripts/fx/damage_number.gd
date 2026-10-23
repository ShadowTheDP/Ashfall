class_name DamageNumber
extends Node2D
## Floating combat number.

var _t := 0.0
var _life := 0.72
var _vy := -92.0
var _label: Label


func setup(amount: int, crit: bool, override_text: String = "") -> void:
	_label = Label.new()
	if override_text.is_empty():
		_label.text = ("%d!" % amount) if crit else ("%d" % amount)
	else:
		_label.text = override_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size = Vector2(80, 28)
	_label.position = Vector2(-40, -16)
	if override_text.is_empty():
		_label.add_theme_font_size_override("font_size", 26 if crit else 17)
		_label.add_theme_color_override("font_color", Color("#ffd166") if crit else Color("#f4efe4"))
	else:
		_label.add_theme_font_size_override("font_size", 14)
		_label.add_theme_color_override("font_color", Color("#8fe3ff"))
	_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.95))
	_label.add_theme_constant_override("outline_size", 5)
	add_child(_label)
	z_index = 30
	scale = Vector2.ONE * (1.35 if crit else 1.0)


func _process(delta: float) -> void:
	_t += delta
	_vy += 210.0 * delta
	position.y += _vy * delta
	scale = scale.lerp(Vector2.ONE, delta * 14.0)
	if _label != null:
		_label.modulate.a = clampf(1.0 - _t / _life, 0.0, 1.0)
	if _t >= _life:
		queue_free()
