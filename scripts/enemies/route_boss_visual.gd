class_name RouteBossVisual
extends EnemyVisual
## Flat silhouettes and exact world-space threat rectangles; never mirror the zones.


func _draw() -> void:
	var boss := e as RouteBoss
	if boss == null or boss.cfg.is_empty():
		return
	var half_h := float(boss.cfg["body_height"]) * 0.5
	_draw_shadow(half_h)
	var sides := 6
	if boss.kind == "clock_warden":
		sides = 8
	elif boss.kind == "silent_regent":
		sides = 5
	var radius := float(boss.cfg["body_radius"]) * MathArt.PHI
	var angle := -PI * 0.5
	if boss.kind == "clock_warden":
		angle += _t * MathArt.INV_PHI
	var fill := MathArt.WHITE if boss.impact > 0.0 else _body_fill()
	MathArt.poly(self, MathArt.ngon(sides, radius, angle), fill, MathArt.BLACK, 2.0)
	MathArt.poly(self, MathArt.ngon(sides, radius * MathArt.INV_PHI, angle),
		MathArt.WHITE if boss.impact > 0.0 else MathArt.INK)
	if boss.phase == 2:
		MathArt.poly(self, MathArt.ngon(sides, radius * MathArt.PHI, -angle),
			Color.TRANSPARENT, Color(MathArt.BOSS, 0.6), 1.0)
	if boss.kind == "silent_regent" and boss._pending_attack == "guard" and boss.state in [Enemy.EState.WINDUP, Enemy.EState.ATTACK]:
		var x := float(boss.facing) * radius
		MathArt.line(self, Vector2(x, -half_h), Vector2(x, half_h), MathArt.BOSS, 3.0)
	if boss.flash > 0.0 and boss.impact <= 0.0:
		MathArt.poly(self, MathArt.ngon(sides, radius, angle), Color.TRANSPARENT,
			Color(MathArt.WHITE, clampf(boss.flash / 0.1, 0.0, 1.0)), 2.0)
	if boss.state in [Enemy.EState.WINDUP, Enemy.EState.ATTACK]:
		for zone in boss.zones:
			_draw_zone(zone, boss.state == Enemy.EState.ATTACK)
	_draw_spawn_flash(half_h)


func _draw_zone(zone: Rect2, attacking: bool) -> void:
	var points := PackedVector2Array([
		to_local(zone.position), to_local(zone.position + Vector2(zone.size.x, 0.0)),
		to_local(zone.end), to_local(zone.position + Vector2(0.0, zone.size.y)),
	])
	MathArt.poly(self, points, Color.TRANSPARENT, Color(MathArt.DANGER, 0.8 if attacking else 0.5), 2.0)
	var center := to_local(zone.get_center())
	var span := zone.size.x * MathArt.INV_PHI * 0.5
	MathArt.line(self, center - Vector2(span, 0.0), center + Vector2(span, 0.0), Color(MathArt.DANGER, 0.5), 1.0)
