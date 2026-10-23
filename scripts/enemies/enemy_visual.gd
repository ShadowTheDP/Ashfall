class_name EnemyVisual
extends Node2D
## Procedural enemy silhouettes. Shape language distinguishes threat type:
## hunched husk, tall watcher, wide ram.

var e: Enemy
var _t := 0.0


func _ready() -> void:
	e = get_parent() as Enemy
	_t = randf() * 10.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if e == null or e.cfg.is_empty():
		return
	if e._dead:
		# Fade is driven by the modulate tween; keep the last pose drawn.
		pass
	var half_h := float(e.cfg.get("body_height", 42.0)) * 0.5
	var tint: Color = Color(e.cfg.get("color", "#b23a48"))
	var moving := absf(e.velocity.x) > 10.0 and e.state == Enemy.EState.CHASE
	var bob := sin(_t * 9.0) * 2.0 if moving else sin(_t * 2.0) * 1.0
	var lean := 0.12 if moving else 0.0
	if e.state == Enemy.EState.WINDUP:
		lean = -0.16
	elif e.state == Enemy.EState.HURT:
		lean = -0.22
	var flash := e.flash > 0.0
	draw_set_transform(Vector2(0, bob), lean * float(e.facing), Vector2(float(e.facing), 1.0))

	_draw_shadow(half_h)
	match e.kind:
		"archer":
			_draw_archer(tint, flash, half_h)
		"charger":
			_draw_charger(tint, flash, half_h)
		_:
			_draw_grunt(tint, flash, half_h)

	if e.state == Enemy.EState.WINDUP:
		_draw_telegraph(tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_health_bar(half_h)
	_draw_spawn_flash(half_h)


func _c(color: Color, flash: bool, alpha: float = 1.0) -> Color:
	var out := Color(1, 1, 1, 1) if flash else color
	out.a *= alpha
	return out


func _draw_shadow(half_h: float) -> void:
	draw_set_transform(Vector2(0, half_h + 1.0), 0.0, Vector2(1.0, 0.24))
	draw_circle(Vector2.ZERO, float(e.cfg.get("body_radius", 12.0)) + 4.0, Color(0, 0, 0, 0.30))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(float(e.facing), 1.0))


func _draw_grunt(tint: Color, flash: bool, half_h: float) -> void:
	var dark := tint.darkened(0.62)
	var hide := tint.darkened(0.30)
	var rim := tint.lightened(0.30)
	draw_line(Vector2(-5, 4), Vector2(-6, half_h), _c(dark, flash), 5.0)
	draw_line(Vector2(5, 4), Vector2(7, half_h), _c(dark, flash), 5.0)
	var torso := PackedVector2Array([
		Vector2(-11, -10), Vector2(9, -9), Vector2(12, 4),
		Vector2(7, 12), Vector2(-8, 12), Vector2(-13, 3),
	])
	draw_colored_polygon(torso, _c(hide, flash))
	var outline := torso.duplicate()
	outline.append(torso[0])
	draw_polyline(outline, _c(rim, flash, 0.55), 1.2, true)
	# shoulder ridge and belt rag
	draw_line(Vector2(-10, -7), Vector2(9, -6), _c(rim, flash, 0.45), 1.4)
	draw_line(Vector2(-9, 6), Vector2(10, 6), _c(Color("#2a1a1a"), flash, 0.95), 2.5)
	draw_circle(Vector2(1, 7), 1.6, _c(Color("#e8a33d"), flash, 0.8))
	# head: pale bone mask over a dark hood
	draw_circle(Vector2(6, -17), 7.4, _c(dark, flash))
	draw_circle(Vector2(7, -16.5), 5.4, _c(Color("#d9d0c0"), flash))
	draw_line(Vector2(3.5, -18.5), Vector2(11.5, -16.0), _c(Color("#242a33"), flash), 1.8)
	draw_circle(Vector2(9.8, -16.2), 1.5, _c(Color("#ff5b5b"), flash))
	# claw arm
	draw_line(Vector2(6, -2), Vector2(15, 6), _c(rim, flash, 0.9), 3.6)
	for i in 3:
		draw_line(Vector2(15, 6), Vector2(19.5 + i * 1.2, 2.0 + i * 3.0), _c(Color("#e9e2d2"), flash, 0.9), 1.2)


func _draw_archer(tint: Color, flash: bool, half_h: float) -> void:
	var dark := tint.darkened(0.6)
	draw_line(Vector2(-4, 6), Vector2(-7, half_h), _c(dark, flash), 4.0)
	draw_line(Vector2(4, 6), Vector2(7, half_h), _c(dark, flash), 4.0)
	var robe := PackedVector2Array([
		Vector2(-8, -14), Vector2(8, -14), Vector2(13, 14), Vector2(6, 18), Vector2(-8, 18), Vector2(-13, 12),
	])
	draw_colored_polygon(robe, _c(tint.darkened(0.25), flash))
	# hood
	var hood := PackedVector2Array([
		Vector2(3, -27), Vector2(12, -18), Vector2(9, -10), Vector2(-1, -12), Vector2(-3, -20),
	])
	draw_colored_polygon(hood, _c(dark, flash))
	draw_circle(Vector2(9, -16), 1.6, _c(Color("#ffd166"), flash))
	# bow
	var bow_color := _c(Color("#d8c08a"), flash)
	draw_arc(Vector2(12, -2), 15.0, -1.25, 1.25, 12, bow_color, 2.0, true)
	draw_line(Vector2(16, -15), Vector2(16, 11), _c(Color(0.85, 0.85, 0.8), flash, 0.5), 1.0)
	if e.state == Enemy.EState.WINDUP:
		var pull := clampf(e.state_t / float(e.cfg.get("windup", 0.5)), 0.0, 1.0)
		draw_line(Vector2(16, -14), Vector2(16 - 10.0 * pull, 0), _c(Color("#f4efe4"), flash), 1.2)
		draw_line(Vector2(16 - 10.0 * pull, 0), Vector2(30, 0), _c(Color("#f4efe4"), flash), 1.2)


func _draw_charger(tint: Color, flash: bool, half_h: float) -> void:
	var dark := tint.darkened(0.6)
	draw_line(Vector2(-7, 8), Vector2(-9, half_h), _c(dark, flash), 6.0)
	draw_line(Vector2(7, 8), Vector2(9, half_h), _c(dark, flash), 6.0)
	var body := PackedVector2Array([
		Vector2(-15, -14), Vector2(14, -14), Vector2(17, 6),
		Vector2(11, 14), Vector2(-12, 14), Vector2(-17, 4),
	])
	draw_colored_polygon(body, _c(tint, flash))
	# shoulder plates
	draw_colored_polygon(PackedVector2Array([Vector2(-17, -12), Vector2(-6, -16), Vector2(-4, 2), Vector2(-13, 4)]), _c(dark, flash))
	draw_colored_polygon(PackedVector2Array([Vector2(17, -12), Vector2(6, -16), Vector2(4, 2), Vector2(13, 4)]), _c(dark, flash))
	# helmet
	draw_rect(Rect2(-6, -25, 20, 12), _c(dark, flash))
	draw_line(Vector2(-6, -21), Vector2(14, -21), _c(Color("#ff8a3d"), flash), 2.0)
	# horns
	draw_line(Vector2(-4, -25), Vector2(-10, -33), _c(Color("#e9e2d2"), flash), 2.5)
	draw_line(Vector2(12, -25), Vector2(19, -32), _c(Color("#e9e2d2"), flash), 2.5)
	# shield arm
	draw_line(Vector2(12, -2), Vector2(20, 8), _c(tint.lightened(0.1), flash), 5.0)
	draw_circle(Vector2(21, 9), 5.0, _c(Color("#5a4634"), flash))


func _draw_telegraph(tint: Color) -> void:
	var windup := maxf(0.001, float(e.cfg.get("windup", 0.4)))
	var progress := clampf(e.state_t / windup, 0.0, 1.0)
	var pulse := 0.35 + 0.45 * progress
	if e.kind == "charger":
		var length := 40.0 + 70.0 * progress
		draw_line(Vector2(10, -6), Vector2(10 + length, -6), Color(1.0, 0.35, 0.25, pulse), 3.0)
		draw_line(Vector2(10, -6), Vector2(10 + length, -6), Color(1.0, 0.8, 0.6, pulse * 0.5), 1.2)
	elif e.kind == "archer":
		draw_circle(Vector2(12, -2), 18.0 + 5.0 * progress, Color(1.0, 0.4, 0.3, pulse * 0.18))
		draw_arc(Vector2(12, -2), 19.0 + 5.0 * progress, -1.2, 1.2, 14, Color(1.0, 0.45, 0.35, pulse), 1.6)
	else:
		draw_arc(Vector2(8, -4), 26.0, -1.15, 1.15, 12, Color(1.0, 0.4, 0.28, pulse), 2.0)
		draw_line(Vector2(8, -4), Vector2(8 + 30.0 * progress, -4), Color(1.0, 0.7, 0.5, pulse * 0.6), 1.0)


func _draw_health_bar(half_h: float) -> void:
	if e.hp >= e.max_hp or e._dead:
		return
	var width := 36.0
	var y := -(half_h + 14.0)
	draw_rect(Rect2(-width * 0.5, y, width, 4.0), Color(0.02, 0.02, 0.03, 0.85))
	var ratio := clampf(e.hp / maxf(e.max_hp, 1.0), 0.0, 1.0)
	draw_rect(Rect2(-width * 0.5, y, width * ratio, 4.0), Color("#d94a4a"))
	draw_rect(Rect2(-width * 0.5, y, width * ratio, 1.0), Color(1.0, 0.55, 0.5, 0.7))


func _draw_spawn_flash(half_h: float) -> void:
	if e._spawn_t <= 0.0 or e._spawn_t > 0.4:
		return
	var a := clampf(e._spawn_t / 0.4, 0.0, 1.0) * 0.5
	draw_circle(Vector2(0, -4), 26.0 + 10.0 * (1.0 - a), Color(1.0, 0.9, 0.7, a * 0.35))
