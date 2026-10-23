class_name Hud
extends Control
## Pixel HUD. Everything is drawn at whole-pixel coordinates on a 640x360
## canvas: chunky bars, 1px frames and small caps labels.

const AMBER := MathArt.AMBER
const AMBER_HI := MathArt.AMBER_HI
const RED := MathArt.RED
const RED_HI := MathArt.RED_HI
const PALE := MathArt.PALE
const DIM := MathArt.STEEL
const CYAN := MathArt.CYAN

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
	var size := get_viewport_rect().size
	_draw_hurt_flash(size)
	_draw_corners(size)
	_draw_vitals(font)
	_draw_cells(font)
	_draw_knives(font)
	_draw_aegis(font)
	_draw_wave(font, size)
	_draw_boss(font, size)
	_draw_combo(font, size)
	_draw_edge(font, size)
	_draw_timer(font, size)
	_draw_build(font, size)
	_draw_hints(font, size)
	_draw_announce(font, size)
	_draw_low_health(size)

	if paused:
		_draw_pause(font, size)
	elif Game.run_over:
		_draw_run_over(font, size)


func _label(font: Font, at: Vector2, text: String, color: Color, size := 6) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw_vitals(font: Font) -> void:
	var player := Game.player
	if player == null:
		return
	var ratio := clampf(player.hp / maxf(player.max_hp, 1.0), 0.0, 1.0)
	_label(font, Vector2(14, 12), "VITALITY", DIM, 6)
	var bar := Rect2(14, 16, 132, 6)
	MathArt.px_rect(self, bar.grow(1.0), Color(0.0, 0.0, 0.0, 0.7))
	MathArt.px_rect(self, bar, MathArt.STONE_2)
	if ratio > 0.0:
		var width := roundf(bar.size.x * ratio)
		MathArt.px_rect(self, Rect2(bar.position, Vector2(width, bar.size.y)), RED)
		MathArt.px_rect(self, Rect2(bar.position, Vector2(width, 1.0)), RED_HI)
		MathArt.px_rect(self, Rect2(bar.position + Vector2(0, bar.size.y - 1.0), Vector2(width, 1.0)), Color(MathArt.RED_DIM, 0.9))
	# Quarter ticks.
	for i in range(1, 4):
		var x := bar.position.x + roundf(bar.size.x * float(i) / 4.0)
		MathArt.px_rect(self, Rect2(x, bar.position.y, 1, bar.size.y), Color(0.0, 0.0, 0.0, 0.45))
	draw_string(font, Vector2(bar.position.x + bar.size.x, 12.0),
		"%d/%d" % [int(ceil(player.hp)), int(player.max_hp)],
		HORIZONTAL_ALIGNMENT_RIGHT, 56.0, 7, PALE)


func _draw_cells(font: Font) -> void:
	var center := Vector2(20, 36)
	MathArt.px_poly(self, PackedVector2Array([
		center + Vector2(0, -4), center + Vector2(3, 0),
		center + Vector2(0, 4), center + Vector2(-3, 0),
	]), AMBER, AMBER_HI, 1.0)
	draw_string(font, Vector2(30, 40), "%d" % Game.cells, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, PALE)
	_label(font, Vector2(30, 47), "CELLS", DIM, 6)


func _draw_knives(font: Font) -> void:
	var player := Game.player
	if player == null:
		return
	_label(font, Vector2(14, 57), "KUNAI", DIM, 6)
	for i in player.knife_max:
		var center := Vector2(18 + i * 11, 66)
		var charged := i < player.knife_charges
		var tint := CYAN if charged else MathArt.STEEL_DIM
		var alpha := 0.95 if charged else 0.30
		MathArt.px_poly(self, PackedVector2Array([
			center + Vector2(0, -4), center + Vector2(3, 0),
			center + Vector2(0, 4), center + Vector2(-3, 0),
		]), Color(tint, alpha), Color(tint, alpha), 1.0)
	if player.knife_charges < player.knife_max:
		var width := float(player.knife_max) * 11.0 - 4.0
		var ratio := clampf(player._knife_regen / player.knife_regen_time, 0.0, 1.0)
		MathArt.px_rect(self, Rect2(14, 73, width, 1), Color(0.0, 0.0, 0.0, 0.5))
		MathArt.px_rect(self, Rect2(14, 73, roundf(width * ratio), 1), CYAN)


func _draw_aegis(font: Font) -> void:
	var player := Game.player
	if player == null:
		return
	var center := Vector2(20, 86)
	var total := player.aegis_time + player.aegis_cooldown
	var ratio := 1.0 - clampf(player.aegis_cd / maxf(total, 0.001), 0.0, 1.0)
	var ready := player.aegis_cd <= 0.0
	_label(font, Vector2(14, 78), "AEGIS", DIM, 6)
	MathArt.px_ring(self, center, 5.0, Color(0.0, 0.0, 0.0, 0.6), 2.0)
	var arc_end := -PI * 0.5 + TAU * ratio
	MathArt.px_arc(self, center, 5.0, -PI * 0.5, arc_end, Color(CYAN, 0.95 if ready else 0.45), 2.0)
	if player.aegis_t > 0.0:
		MathArt.px_rect(self, Rect2(center.x - 1, center.y - 1, 3, 3), Color(CYAN, 1.0))
	elif ready:
		MathArt.px_rect(self, Rect2(center.x - 1, center.y - 1, 2, 2), Color(CYAN, 0.75))


func _draw_wave(font: Font, size: Vector2) -> void:
	if Game.wave <= 0:
		return
	draw_string(font, Vector2(size.x * 0.5 - 120.0, 15.0),
		"WAVE %d/%d" % [Game.wave, Game.wave_total],
		HORIZONTAL_ALIGNMENT_CENTER, 240.0, 8, PALE)
	if Game.enemies_left > 0:
		draw_string(font, Vector2(size.x * 0.5 - 120.0, 25.0),
			"%d HOSTILE%s" % [Game.enemies_left, "" if Game.enemies_left == 1 else "S"],
			HORIZONTAL_ALIGNMENT_CENTER, 240.0, 6, DIM)


func _draw_boss(font: Font, size: Vector2) -> void:
	if not is_instance_valid(Game.boss):
		return
	var boss := Game.boss
	var width := 260.0
	var x := roundf((size.x - width) * 0.5)
	var y := 36.0
	var ratio := clampf(boss.hp / maxf(boss.max_hp, 1.0), 0.0, 1.0)
	draw_string(font, Vector2(size.x * 0.5 - 120.0, y - 4.0), "THE WARDEN",
		HORIZONTAL_ALIGNMENT_CENTER, 240.0, 7, Color(MathArt.VIOLET, 0.95))
	MathArt.px_rect(self, Rect2(x - 1.0, y - 1.0, width + 2.0, 7.0), Color(0.0, 0.0, 0.0, 0.75))
	MathArt.px_rect(self, Rect2(x, y, width, 5.0), Color(0.10, 0.06, 0.16))
	MathArt.px_rect(self, Rect2(x, y, roundf(width * ratio), 5.0), MathArt.VIOLET_MID)
	MathArt.px_rect(self, Rect2(x, y, roundf(width * ratio), 1.0), Color(0.85, 0.72, 1.0, 0.8))
	for i in range(1, 5):
		var tx := x + roundf(width * float(i) / 5.0)
		MathArt.px_rect(self, Rect2(tx, y, 1, 5.0), Color(0.0, 0.0, 0.0, 0.4))


func _draw_combo(font: Font, size: Vector2) -> void:
	if Game.combo < 2:
		return
	var pop := 1.0 + Game.combo_pop * 0.2
	var center := Vector2(size.x - 34.0, 40.0)
	var radius := roundf(16.0 * pop)
	var ratio := clampf(Game.combo_time / Game.COMBO_WINDOW, 0.0, 1.0)
	MathArt.px_ring(self, center, radius, Color(0.0, 0.0, 0.0, 0.55), 3.0)
	MathArt.px_arc(self, center, radius, -PI * 0.5, -PI * 0.5 + TAU * ratio, AMBER, 3.0)
	draw_string(font, Vector2(center.x - 20.0, center.y + 4.0), "%d" % Game.combo,
		HORIZONTAL_ALIGNMENT_CENTER, 40.0, int(11.0 * pop), AMBER_HI)
	draw_string(font, Vector2(center.x - 24.0, center.y + 24.0), "COMBO",
		HORIZONTAL_ALIGNMENT_CENTER, 48.0, 5, DIM)


func _draw_edge(font: Font, size: Vector2) -> void:
	if Game.edge_timer <= 0.0:
		return
	var ratio := clampf(Game.edge_timer / Game.PERFECT_DODGE_TIME, 0.0, 1.0)
	var x := size.x - 96.0
	_label(font, Vector2(x, 78), "EDGE +25%", AMBER_HI, 6)
	MathArt.px_rect(self, Rect2(x, 82, 82, 2), Color(0.0, 0.0, 0.0, 0.5))
	MathArt.px_rect(self, Rect2(x, 82, roundf(82.0 * ratio), 2), AMBER)


func _draw_timer(font: Font, size: Vector2) -> void:
	var total := int(Game.run_time)
	draw_string(font, Vector2(size.x - 70.0, 15.0), "%02d:%02d" % [total / 60, total % 60],
		HORIZONTAL_ALIGNMENT_RIGHT, 56.0, 8, DIM)


func _draw_build(font: Font, size: Vector2) -> void:
	if Game.reward_counts.is_empty():
		return
	var parts: Array[String] = []
	for id in Game.reward_counts:
		var count := int(Game.reward_counts[id])
		parts.append(str(id).to_upper() + ("x%d" % count if count > 1 else ""))
	draw_string(font, Vector2(size.x - 230.0, size.y - 30.0), " · ".join(parts),
		HORIZONTAL_ALIGNMENT_RIGHT, 216.0, 6, Color(DIM, 0.7))


func _draw_hints(font: Font, size: Vector2) -> void:
	draw_string(font, Vector2(14, size.y - 8.0),
		"A/D MOVE   SPACE JUMP   J EDGE   K KUNAI   L AEGIS   SHIFT ROLL   ESC PAUSE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(DIM, 0.78))
	draw_string(font, Vector2(size.x - 96.0, size.y - 8.0), "ASHFALL 0.2",
		HORIZONTAL_ALIGNMENT_RIGHT, 82.0, 6, Color(DIM, 0.5))


func _draw_announce(font: Font, size: Vector2) -> void:
	if Game.announce_text.is_empty() or Game.announce_t <= 0.0:
		return
	var elapsed := Game.announce_max - Game.announce_t
	var alpha := clampf(elapsed / 0.14, 0.0, 1.0) * clampf(Game.announce_t / 0.26, 0.0, 1.0)
	var y := size.y * 0.30
	draw_string(font, Vector2(size.x * 0.5 - 150.0, y), Game.announce_text,
		HORIZONTAL_ALIGNMENT_CENTER, 300.0, 18, Color(PALE, alpha))
	MathArt.px_rect(self, Rect2(size.x * 0.5 - 40.0, y + 4.0, 80, 1), Color(AMBER, alpha * 0.8))


func _draw_low_health(size: Vector2) -> void:
	var player := Game.player
	if player == null or Game.run_over:
		return
	var ratio := player.hp / maxf(player.max_hp, 1.0)
	if ratio > 0.3:
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 7.0)
	var alpha := 0.10 + 0.14 * pulse * (1.0 - ratio / 0.3)
	var tint := Color(0.72, 0.10, 0.12, alpha)
	MathArt.px_rect(self, Rect2(0, 0, size.x, 2), tint)
	MathArt.px_rect(self, Rect2(0, size.y - 2, size.x, 2), tint)
	MathArt.px_rect(self, Rect2(0, 0, 2, size.y), tint)
	MathArt.px_rect(self, Rect2(size.x - 2, 0, 2, size.y), tint)


func _draw_hurt_flash(size: Vector2) -> void:
	if Game.hurt_flash <= 0.0:
		return
	var alpha := clampf(Game.hurt_flash / 0.32, 0.0, 1.0)
	MathArt.px_rect(self, Rect2(0, 0, size.x, size.y), Color(0.70, 0.08, 0.10, alpha * 0.16))
	MathArt.px_rect(self, Rect2(0, 0, size.x, 1), Color(0.90, 0.16, 0.18, alpha * 0.8))
	MathArt.px_rect(self, Rect2(0, size.y - 1, size.x, 1), Color(0.90, 0.16, 0.18, alpha * 0.8))


func _draw_corners(size: Vector2) -> void:
	var ink := Color(AMBER, 0.20)
	var length := 10.0
	var m := 6.0
	MathArt.px_rect(self, Rect2(m, m, length, 1), ink)
	MathArt.px_rect(self, Rect2(m, m, 1, length), ink)
	MathArt.px_rect(self, Rect2(size.x - m - length, m, length, 1), ink)
	MathArt.px_rect(self, Rect2(size.x - m - 1.0, m, 1, length), ink)
	MathArt.px_rect(self, Rect2(m, size.y - m - 1.0, length, 1), ink)
	MathArt.px_rect(self, Rect2(m, size.y - m - length, 1, length), ink)
	MathArt.px_rect(self, Rect2(size.x - m - length, size.y - m - 1.0, length, 1), ink)
	MathArt.px_rect(self, Rect2(size.x - m - 1.0, size.y - m - length, 1, length), ink)


func _draw_pause(font: Font, size: Vector2) -> void:
	MathArt.px_rect(self, Rect2(0, 0, size.x, size.y), Color(0.02, 0.03, 0.045, 0.80))
	MathArt.px_ring(self, Vector2(size.x * 0.5, size.y * 0.44), 56.0, Color(AMBER, 0.12), 1.0)
	MathArt.px_ring(self, Vector2(size.x * 0.5, size.y * 0.44), 34.0, Color(AMBER, 0.09), 1.0)
	draw_string(font, Vector2(size.x * 0.5 - 150.0, size.y * 0.44), "PAUSED",
		HORIZONTAL_ALIGNMENT_CENTER, 300.0, 26, PALE)
	MathArt.px_rect(self, Rect2(size.x * 0.5 - 34.0, size.y * 0.44 + 8.0, 68, 1), AMBER)
	draw_string(font, Vector2(size.x * 0.5 - 150.0, size.y * 0.44 + 30.0),
		"ESC RESUME    R RESTART    Q QUIT",
		HORIZONTAL_ALIGNMENT_CENTER, 300.0, 8, DIM)


func _draw_run_over(font: Font, size: Vector2) -> void:
	MathArt.px_rect(self, Rect2(0, 0, size.x, size.y), Color(0.02, 0.025, 0.04, 0.82))
	var title := "FLOOR CLEARED" if Game.victory else "YOU DIED"
	var title_color := AMBER if Game.victory else RED
	var y := size.y * 0.34
	draw_string(font, Vector2(size.x * 0.5 - 180.0, y), title,
		HORIZONTAL_ALIGNMENT_CENTER, 360.0, 28, title_color)
	MathArt.px_rect(self, Rect2(size.x * 0.5 - 50.0, y + 9.0, 100, 1), Color(title_color, 0.8))
	var total := int(Game.run_time)
	var stats := "%d CELLS   %d KILLS   x%d COMBO   %d PERFECT   %02d:%02d" % [
		Game.cells, Game.kills, Game.max_combo, Game.perfect_dodges, total / 60, total % 60
	]
	draw_string(font, Vector2(size.x * 0.5 - 200.0, y + 34.0), stats,
		HORIZONTAL_ALIGNMENT_CENTER, 400.0, 8, PALE)
	draw_string(font, Vector2(size.x * 0.5 - 200.0, y + 56.0), "PRESS R TO RUN IT BACK",
		HORIZONTAL_ALIGNMENT_CENTER, 400.0, 7, DIM)
