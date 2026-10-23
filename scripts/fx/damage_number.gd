class_name DamageNumber
extends Node2D
## Floating pixel number. Uses a hard 1px outline so it stays readable at 640x360.

var _t := 0.0
var _life := 0.7
var _vy := -74.0
var _label: Label


func setup(amount: int, crit: bool, override_text: String = "") -> void:
	_label = Label.new()
	if override_text.is_empty():
		_label.text = ("%d!" % amount) if crit else ("%d" % amount)
	else:
		_label.text = override_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size = Vector2(48, 16)
	_label.position = Vector2(-24, -8)
	if override_text.is_empty():
		_label.add_theme_font_size_override("font_size", 13 if crit else 10)
		_label.add_theme_color_override("font_color", MathArt.AMBER_HI if crit else MathArt.PALE)
	else:
		_label.add_theme_font_size_override("font_size", 8)
		_label.add_theme_color_override("font_color", MathArt.CYAN)
	_label.add_theme_color_override("font_outline_color", MathArt.INK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	z_index = 30
	scale = Vector2.ONE * (1.3 if crit else 1.0)


func _process(delta: float) -> void:
	_t += delta
	_vy += 190.0 * delta
	position.y += roundf(_vy * delta)
	scale = scale.lerp(Vector2.ONE, delta * 16.0)
	if _label != null:
		_label.modulate.a = clampf(1.0 - _t / _life, 0.0, 1.0)
	if _t >= _life:
		queue_free()
