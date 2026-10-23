class_name Hud
extends Control
## Combat HUD, pause overlay and run-summary overlay. Drawn in one place so the
## prototype has no theme/resource dependencies.

const AMBER := Color("#e8a33d")
const AMBER_LIGHT := Color("#ffd166")
const RED := Color("#d94a4a")
const PALE := Color("#e9e2d2")
const DIM := Color("#7c8fa3")
const INK := Color(0.01, 0.015, 0.025, 1.0)

var paused := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if Game.reward_open:
		return
	if event.is_action_pressed("restart") and (paused or Game.run_over):
		_restart()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and not Game.run_over:
		_set_paused(not paused)
		get_viewport().set_input_as_handled()
		return
	if paused and event is InputEventKey and event.pressed and event.physical_keycode == KEY_Q:
		get_tree().quit()


func _set_paused(value: bool) -> void:
	paused = value
	get_tree().paused = value
	if value:
		Combat.cancel_hitstop()
	Sfx.play("ui", -12)
	queue_redraw()


func _restart() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var viewport_size := get_viewport_rect().size
	_draw_hurt_flash(viewport_size)
	_draw_ornaments(viewport_size)
	_draw_vitals(font)
	_draw_cells(font)
	_draw_knives(font)
	_draw_aegis(font)
	_draw_wave(font, viewport_size)
	_draw_boss(font, viewport_size)
	_draw_combo(font, viewport_size)
	_draw_edge(font, viewport_size)
	_draw_timer(font, viewport_size)
	_draw_build(font, viewport_size)
	_draw_hints(font, viewport_size)
	_draw_announce(font, viewport_size)
	_draw_low_health_pulse(viewport_size)

	if paused:
		_draw_pause(font, viewport_size)
	elif Game.run_over:
		_draw_run_over(font, viewport_size)


func _draw_vitals(font: Font) -> void:
	var player := Game.player
	if player == null:
		return
	var ratio := clampf(player.hp / maxf(player.max_hp, 1.0), 0.0, 1.0)
	var bar := Rect2(30.0, 36.0, 260.0, 12.0)
	draw_rect(bar.grow(3.0), Color(0.0, 0.0, 0.0, 0.55))
	draw_rect(bar, Color(0.08, 0.10, 0.13))
	if ratio > 0.0:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), RED)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, 2.0)), Color(1.0, 0.62, 0.55, 0.75))
	draw_rect(bar, Color(0.35, 0.4, 0.46, 0.55), false, 1.0)
	for i in range(1, 6):
		var x := bar.position.x + bar.size.x * float(i) / 6.0
		draw_line(Vector2(x, bar.position.y), Vector2(x, bar.position.y + bar.size.y), Color(0, 0, 0, 0.35), 1.0)
	draw_string(font, Vector2(30.0, 28.0), "VITALITY", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	draw_string(
		font,
		Vector2(bar.position.x + bar.size.x, 28.0),
		"%d / %d" % [int(ceil(player.hp)), int(player.max_hp)],
		HORIZONTAL_ALIGNMENT_RIGHT,
		120.0,
		12,
		PALE
	)


func _draw_cells(font: Font) -> void:
	var center := Vector2(38.0, 74.0)
	draw_circle(center, 9.0, Color(0.91, 0.64, 0.24, 0.14))
	var diamond := PackedVector2Array([
		center + Vector2(0, -7), center + Vector2(5, 0),
		center + Vector2(0, 7), center + Vector2(-5, 0),
	])
	draw_colored_polygon(diamond, AMBER)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -3.5), center + Vector2(2.5, 0),
		center + Vector2(0, 3.5), center + Vector2(-2.5, 0),
	]), Color("#fff2d6"))
	draw_string(font, Vector2(56.0, 80.0), "%d" % Game.cells, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, PALE)
	draw_string(font, Vector2(56.0, 92.0), "CELLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, DIM)


func _draw_wave(font: Font, viewport_size: Vector2) -> void:
	if Game.wave <= 0:
		return
	var text := "W A V E   %d / %d" % [Game.wave, Game.wave_total]
	draw_string(font, Vector2(viewport_size.x * 0.5 - 200.0, 40.0), text, HORIZONTAL_ALIGNMENT_CENTER, 400.0, 18, PALE)
	if Game.enemies_left > 0:
		draw_string(
			font,
			Vector2(viewport_size.x * 0.5 - 200.0, 58.0),
			"%d HOSTILE%s" % [Game.enemies_left, "" if Game.enemies_left == 1 else "S"],
			HORIZONTAL_ALIGNMENT_CENTER, 400.0, 10, DIM
		)


func _draw_combo(font: Font, viewport_size: Vector2) -> void:
	if Game.combo < 2:
		return
	var pop := 1.0 + Game.combo_pop * 0.22
	var size := int(34.0 * pop)
	var center := Vector2(viewport_size.x - 88.0, 112.0)
	var ratio := clampf(Game.combo_time / Game.COMBO_WINDOW, 0.0, 1.0)
	MathArt.draw_ring(self, center, 38.0, Color(0.0, 0.0, 0.0, 0.40), 3.0, 48)
	MathArt.draw_ring(self, center, 38.0, Color(AMBER, 0.85), 3.0, 48, -PI * 0.5, -PI * 0.5 + TAU * ratio)
	MathArt.draw_ring(self, center, 30.0, Color(AMBER, 0.12), 1.0, 40)
	draw_string(font, Vector2(center.x - 40.0, center.y + float(size) * 0.34),
		"x%d" % Game.combo, HORIZONTAL_ALIGNMENT_CENTER, 80.0, size, AMBER_LIGHT)
	draw_string(font, Vector2(center.x - 60.0, center.y + 56.0), "COMBO", HORIZONTAL_ALIGNMENT_CENTER, 120.0, 9, DIM)


func _draw_knives(font: Font) -> void:
	var player := Game.player
	if player == null:
		return
	draw_string(font, Vector2(30.0, 112.0), "KUNAI", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, DIM)
	for i in player.knife_max:
		var center := Vector2(38.0 + float(i) * 18.0, 124.0)
		var charged := i < player.knife_charges
		var tint := Color("#8fe3ff") if charged else Color(0.24, 0.30, 0.38)
		var blade := PackedVector2Array([
			center + Vector2(0, -6), center + Vector2(3, 0),
			center + Vector2(0, 6), center + Vector2(-3, 0),
		])
		MathArt.draw_poly(self, blade, Color(tint, 0.9 if charged else 0.18), Color(tint, 0.9), 1.0)
	if player.knife_charges < player.knife_max:
		var width := float(player.knife_max) * 18.0 - 4.0
		var ratio := clampf(player._knife_regen / player.knife_regen_time, 0.0, 1.0)
		draw_rect(Rect2(30.0, 134.0, width, 2.0), Color(0.0, 0.0, 0.0, 0.45))
		draw_rect(Rect2(30.0, 134.0, width * ratio, 2.0), Color("#8fe3ff"))


func _draw_aegis(font: Font) -> void:
	var player := Game.player
	if player == null:
		return
	var cyan := Color("#8fe3ff")
	var center := Vector2(47.0, 164.0)
	var total := player.aegis_time + player.aegis_cooldown
	var ratio := 1.0 - clampf(player.aegis_cd / maxf(total, 0.001), 0.0, 1.0)
	var ready := player.aegis_cd <= 0.0
	draw_string(font, Vector2(30.0, 152.0), "AEGIS", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, DIM)
	MathArt.draw_ring(self, center, 9.0, Color(0.0, 0.0, 0.0, 0.45), 2.0, 32)
	MathArt.draw_ring(self, center, 9.0, Color(cyan, 0.85 if ready else 0.45), 2.0, 32,
		-PI * 0.5, -PI * 0.5 + TAU * ratio)
	if player.aegis_t > 0.0:
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 70.0)
		draw_circle(center, 3.2, Color(cyan, pulse))
		MathArt.draw_ring(self, center, 13.0, Color(cyan, 0.35), 1.0, 28)
	elif ready:
		draw_circle(center, 2.2, Color(cyan, 0.75))


func _draw_edge(font: Font, viewport_size: Vector2) -> void:
	if Game.edge_timer <= 0.0:
		return
	var ratio := clampf(Game.edge_timer / Game.PERFECT_DODGE_TIME, 0.0, 1.0)
	var x := viewport_size.x - 218.0
	draw_string(font, Vector2(x, 176.0), "EDGE +25%", HORIZONTAL_ALIGNMENT_LEFT, 180.0, 11, AMBER_LIGHT)
	draw_rect(Rect2(x, 182.0, 180.0, 3.0), Color(0.0, 0.0, 0.0, 0.45))
	draw_rect(Rect2(x, 182.0, 180.0 * ratio, 3.0), AMBER)


func _draw_boss(font: Font, viewport_size: Vector2) -> void:
	if not is_instance_valid(Game.boss):
		return
	var boss := Game.boss
	var width := 560.0
	var x := (viewport_size.x - width) * 0.5
	var y := 84.0
	var ratio := clampf(boss.hp / maxf(boss.max_hp, 1.0), 0.0, 1.0)
	draw_string(font, Vector2(viewport_size.x * 0.5 - 200.0, y - 6.0),
		"T H E   W A R D E N", HORIZONTAL_ALIGNMENT_CENTER, 400.0, 11, Color("#c9a7ff"))
	draw_rect(Rect2(x - 2.0, y - 2.0, width + 4.0, 14.0), Color(0.0, 0.0, 0.0, 0.55))
	draw_rect(Rect2(x, y, width, 10.0), Color(0.10, 0.06, 0.16))
	draw_rect(Rect2(x, y, width * ratio, 10.0), Color("#8e5bd9"))
	draw_rect(Rect2(x, y, width * ratio, 2.0), Color(0.85, 0.72, 1.0, 0.75))
	if is_instance_valid(boss):
		var ticks := 5
		for i in range(1, ticks):
			var tx := x + width * float(i) / float(ticks)
			draw_line(Vector2(tx, y), Vector2(tx, y + 10.0), Color(0.0, 0.0, 0.0, 0.35), 1.0)
	var wave := MathArt.harmonic_wave(Vector2(x, y + 11.0), width, 2.0, 8.0, Time.get_ticks_msec() / 900.0, 48)
	draw_polyline(wave, Color(0.72, 0.55, 1.0, 0.35), 1.0, true)


func _draw_build(font: Font, viewport_size: Vector2) -> void:
	if Game.reward_counts.is_empty():
		return
	var parts: Array[String] = []
	for id in Game.reward_counts:
		var count := int(Game.reward_counts[id])
		parts.append(str(id).to_upper() + (" x%d" % count if count > 1 else ""))
	var text := " · ".join(parts)
	draw_string(font, Vector2(viewport_size.x - 30.0 - 420.0, viewport_size.y - 44.0),
		text, HORIZONTAL_ALIGNMENT_RIGHT, 420.0, 9, Color(DIM, 0.65))


func _draw_hurt_flash(viewport_size: Vector2) -> void:
	if Game.hurt_flash <= 0.0:
		return
	var alpha := clampf(Game.hurt_flash / 0.32, 0.0, 1.0) * 0.20
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.72, 0.08, 0.10, alpha))
	var border := Color(0.85, 0.12, 0.14, alpha * 1.4)
	draw_rect(Rect2(6.0, 6.0, viewport_size.x - 12.0, viewport_size.y - 12.0), border, false, 2.0)


func _draw_ornaments(viewport_size: Vector2) -> void:
	var ink := Color(0.91, 0.64, 0.24, 0.14)
	var length := 26.0
	var margin := 18.0
	draw_line(Vector2(margin, margin), Vector2(margin + length, margin), ink, 1.0)
	draw_line(Vector2(margin, margin), Vector2(margin, margin + length), ink, 1.0)
	draw_line(Vector2(viewport_size.x - margin, margin), Vector2(viewport_size.x - margin - length, margin), ink, 1.0)
	draw_line(Vector2(viewport_size.x - margin, margin), Vector2(viewport_size.x - margin, margin + length), ink, 1.0)
	draw_line(Vector2(margin, viewport_size.y - margin), Vector2(margin + length, viewport_size.y - margin), ink, 1.0)
	draw_line(Vector2(margin, viewport_size.y - margin), Vector2(margin, viewport_size.y - margin - length), ink, 1.0)
	draw_line(Vector2(viewport_size.x - margin, viewport_size.y - margin), Vector2(viewport_size.x - margin - length, viewport_size.y - margin), ink, 1.0)
	draw_line(Vector2(viewport_size.x - margin, viewport_size.y - margin), Vector2(viewport_size.x - margin, viewport_size.y - margin - length), ink, 1.0)
	MathArt.draw_ring(self, Vector2(margin + 12.0, margin + 42.0), 7.0, ink, 1.0, 24)
	MathArt.draw_ring(self, Vector2(viewport_size.x - margin - 12.0, margin + 42.0), 7.0, ink, 1.0, 24)


func _draw_timer(font: Font, viewport_size: Vector2) -> void:
	var total := int(Game.run_time)
	var text := "%02d:%02d" % [total / 60, total % 60]
	draw_string(font, Vector2(viewport_size.x - 40.0 - 120.0, 36.0), text, HORIZONTAL_ALIGNMENT_RIGHT, 120.0, 16, DIM)
	draw_string(font, Vector2(viewport_size.x - 40.0 - 220.0, 36.0), "RUN", HORIZONTAL_ALIGNMENT_RIGHT, 90.0, 10, Color(DIM, 0.6))


func _draw_hints(font: Font, viewport_size: Vector2) -> void:
	var y := viewport_size.y - 26.0
	var hint := "A/D  MOVE   SPACE  JUMP   J  SINE EDGE   K  KUNAI   L  AEGIS   SHIFT  ROLL   ESC  PAUSE"
	draw_string(font, Vector2(30.0, y), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(DIM, 0.75))
	draw_string(
		font,
		Vector2(viewport_size.x - 30.0 - 260.0, y),
		"ASHFALL  ·  COMBAT PROTOTYPE 0.1",
		HORIZONTAL_ALIGNMENT_RIGHT, 260.0, 9, Color(DIM, 0.45)
	)


func _draw_announce(font: Font, viewport_size: Vector2) -> void:
	if Game.announce_text.is_empty() or Game.announce_t <= 0.0:
		return
	var elapsed := Game.announce_max - Game.announce_t
	var alpha := clampf(elapsed / 0.16, 0.0, 1.0) * clampf(Game.announce_t / 0.28, 0.0, 1.0)
	var y := viewport_size.y * 0.28
	draw_string(
		font,
		Vector2(viewport_size.x * 0.5 - 300.0, y),
		Game.announce_text,
		HORIZONTAL_ALIGNMENT_CENTER, 600.0, 34, Color(PALE, alpha)
	)
	draw_line(
		Vector2(viewport_size.x * 0.5 - 70.0, y + 12.0),
		Vector2(viewport_size.x * 0.5 + 70.0, y + 12.0),
		Color(AMBER, alpha * 0.7), 2.0
	)


func _draw_low_health_pulse(viewport_size: Vector2) -> void:
	var player := Game.player
	if player == null or Game.run_over:
		return
	var ratio := player.hp / maxf(player.max_hp, 1.0)
	if ratio > 0.3:
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 7.0)
	var tint := Color(0.7, 0.1, 0.12, 0.08 + 0.10 * pulse * (1.0 - ratio / 0.3))
	draw_rect(Rect2(12.0, 12.0, viewport_size.x - 24.0, 3.0), tint)
	draw_rect(Rect2(12.0, viewport_size.y - 15.0, viewport_size.x - 24.0, 3.0), tint)
	draw_rect(Rect2(12.0, 12.0, 3.0, viewport_size.y - 24.0), tint)
	draw_rect(Rect2(viewport_size.x - 15.0, 12.0, 3.0, viewport_size.y - 24.0), tint)


func _draw_pause(font: Font, viewport_size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.01, 0.015, 0.025, 0.78))
	var time := Time.get_ticks_msec() / 1000.0
	MathArt.draw_spiral(self, Vector2(viewport_size.x * 0.5, viewport_size.y * 0.42 - 8.0), 170.0, 2.4,
		Color(0.91, 0.64, 0.24, 0.07), 1.2, 80, time * 0.04)
	MathArt.draw_ring(self, Vector2(viewport_size.x * 0.5, viewport_size.y * 0.42 - 8.0), 120.0,
		Color(0.91, 0.64, 0.24, 0.10), 1.0, 64)
	draw_string(font, Vector2(viewport_size.x * 0.5 - 300.0, viewport_size.y * 0.42), "PAUSED", HORIZONTAL_ALIGNMENT_CENTER, 600.0, 52, PALE)
	draw_line(
		Vector2(viewport_size.x * 0.5 - 60.0, viewport_size.y * 0.42 + 16.0),
		Vector2(viewport_size.x * 0.5 + 60.0, viewport_size.y * 0.42 + 16.0),
		AMBER, 2.0
	)
	draw_string(
		font,
		Vector2(viewport_size.x * 0.5 - 300.0, viewport_size.y * 0.42 + 62.0),
		"ESC  RESUME        R  RESTART        Q  QUIT",
		HORIZONTAL_ALIGNMENT_CENTER, 600.0, 13, DIM
	)


func _draw_run_over(font: Font, viewport_size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.01, 0.012, 0.02, 0.74))
	var title := "FLOOR CLEARED" if Game.victory else "YOU DIED"
	var title_color := AMBER if Game.victory else RED
	var y := viewport_size.y * 0.34
	draw_string(font, Vector2(viewport_size.x * 0.5 - 350.0, y), title, HORIZONTAL_ALIGNMENT_CENTER, 700.0, 58, title_color)
	draw_line(
		Vector2(viewport_size.x * 0.5 - 90.0, y + 18.0),
		Vector2(viewport_size.x * 0.5 + 90.0, y + 18.0),
		Color(title_color, 0.8), 2.0
	)
	var total := int(Game.run_time)
	var stats := "%d CELLS        %d KILLS        x%d COMBO        %d PERFECT        %02d:%02d" % [
		Game.cells, Game.kills, Game.max_combo, Game.perfect_dodges, total / 60, total % 60
	]
	draw_string(font, Vector2(viewport_size.x * 0.5 - 350.0, y + 62.0), stats, HORIZONTAL_ALIGNMENT_CENTER, 700.0, 13, PALE)
	draw_string(
		font,
		Vector2(viewport_size.x * 0.5 - 350.0, y + 104.0),
		"PRESS  R  TO  RUN  IT  BACK",
		HORIZONTAL_ALIGNMENT_CENTER, 700.0, 12, DIM
	)
