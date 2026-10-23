class_name Hud
extends Control
## Monochrome HUD for 768x480. Layout uses an 8px grid and proportional
## anchoring; no element relies on colour to be understood.

const FG := MathArt.PALE
const FG_HI := MathArt.WHITE
const DIM := MathArt.MID
const DIM2 := MathArt.MID_DIM
const BG := MathArt.INK

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
	# A hub station panel owns Esc while it is open; otherwise pausing under it
	# traps the player with no way back out.
	if _modal_open():
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


func _modal_open() -> bool:
	var main := get_parent()
	while main != null and not main.has_method("start_floor"):
		main = main.get_parent()
	if main == null:
		return false
	# The title owns Esc as well: it pauses the tree itself, so a HUD pause
	# latched under it would paint PAUSED over the whole first run. Every meta
	# screen hides itself when closed, so `visible` is the whole open state
	# (the archive and the tree are CanvasLayers, the title is a Control).
	for name in ["title_screen", "archive", "skill_tree"]:
		var screen: Variant = main.get(name)
		if not is_instance_valid(screen):
			continue
		var shown: Variant = screen.get("visible")
		if shown is bool and shown:
			return true
	var hub: Variant = main.get("hub")
	if hub != null and hub.has_method("is_open") and hub.is_open():
		return true
	return false


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
	if not Game.in_hub:
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


func _text(font: Font, at: Vector2, text: String, color: Color, size := 9) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw_vitals(font: Font) -> void:
	var player := Game.player
	if player == null:
		return
	var ratio := clampf(player.hp / maxf(player.max_hp, 1.0), 0.0, 1.0)
	_text(font, Vector2(20, 22), "VITALITY", DIM, 9)
	var bar := Rect2(20, 28, 168, 9)
	MathArt.px_rect(self, bar.grow(2.0), Color(0.0, 0.0, 0.0, 0.75))
	MathArt.px_rect(self, bar, MathArt.STONE)
	if ratio > 0.0:
		var w := bar.size.x * ratio
		MathArt.px_rect(self, Rect2(bar.position, Vector2(w, bar.size.y)), MathArt.LIGHT)
		MathArt.px_rect(self, Rect2(bar.position, Vector2(w, 2.0)), MathArt.WHITE)
	draw_rect(bar, Color(MathArt.WHITE, 0.25), false, 1.0)
	for i in range(1, 4):
		var x := bar.position.x + bar.size.x * float(i) / 4.0
		MathArt.px_rect(self, Rect2(x, bar.position.y, 1, bar.size.y), Color(0.0, 0.0, 0.0, 0.5))
	draw_string(font, Vector2(bar.position.x + bar.size.x - 96.0, 22.0),
		"%d / %d" % [int(ceil(player.hp)), int(player.max_hp)],
		HORIZONTAL_ALIGNMENT_RIGHT, 96.0, 10, FG)


func _draw_cells(font: Font) -> void:
	var center := Vector2(26, 56)
	MathArt.px_poly(self, PackedVector2Array([
		center + Vector2(0, -6), center + Vector2(4, 0),
		center + Vector2(0, 6), center + Vector2(-4, 0),
	]), FG_HI, FG_HI, 1.0)
	draw_string(font, Vector2(38, 62), "%d" % Game.cells, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, FG)
	_text(font, Vector2(38, 74), "CELLS", DIM2, 8)


func _draw_knives(font: Font) -> void:
	var player := Game.player
	if player == null:
		return
	_text(font, Vector2(20, 90), "KUNAI", DIM2, 8)
	for i in player.knife_max:
		var center := Vector2(26 + i * 14, 102)
		var charged := i < player.knife_charges
		var tint := FG_HI if charged else MathArt.MID_DIM
		var alpha := 0.95 if charged else 0.35
		MathArt.px_poly(self, PackedVector2Array([
			center + Vector2(0, -5), center + Vector2(4, 0),
			center + Vector2(0, 5), center + Vector2(-4, 0),
		]), Color(tint, alpha), Color(tint, alpha), 1.0)
	if player.knife_charges < player.knife_max:
		var w := float(player.knife_max) * 14.0 - 6.0
		var ratio := clampf(player._knife_regen / player.knife_regen_time, 0.0, 1.0)
		MathArt.px_rect(self, Rect2(20, 110, w, 2), Color(0.0, 0.0, 0.0, 0.6))
		MathArt.px_rect(self, Rect2(20, 110, w * ratio, 2), FG_HI)


func _draw_aegis(font: Font) -> void:
	var player := Game.player
	if player == null:
		return
	var center := Vector2(27, 126)
	var total := player.aegis_time + player.aegis_cooldown
	var ratio := 1.0 - clampf(player.aegis_cd / maxf(total, 0.001), 0.0, 1.0)
	var ready := player.aegis_cd <= 0.0
	_text(font, Vector2(20, 118), "AEGIS", DIM2, 8)
	MathArt.ring(self, center, 7.0, Color(0.0, 0.0, 0.0, 0.7), 3.0)
	MathArt.arc(self, center, 7.0, -PI * 0.5, -PI * 0.5 + TAU * ratio, Color(FG_HI, 1.0 if ready else 0.5), 3.0)
	if player.aegis_t > 0.0:
		MathArt.disc(self, center, 2.4, FG_HI)
	elif ready:
		MathArt.disc(self, center, 1.8, Color(FG_HI, 0.8))


func _draw_wave(font: Font, size: Vector2) -> void:
	# Floor mode shows the floor banner; arena mode keeps the wave counter.
	if Game.floor_index > 0:
		draw_string(font, Vector2(size.x * 0.5 - 160.0, 22.0),
			Game.floor_name, HORIZONTAL_ALIGNMENT_CENTER, 320.0, 11, FG)
		var level := _level_node()
		var remaining := -1
		if level != null and level.has_method("enemies_remaining"):
			remaining = int(level.enemies_remaining())
		if remaining > 0:
			draw_string(font, Vector2(size.x * 0.5 - 160.0, 36.0),
				"%d HOSTILE%s   FLOOR %d / %d" % [remaining,
					"" if remaining == 1 else "S", Game.floor_index, Game.max_floor()],
				HORIZONTAL_ALIGNMENT_CENTER, 320.0, 8, DIM)
		else:
			draw_string(font, Vector2(size.x * 0.5 - 160.0, 36.0),
				"FLOOR %d / %d   GATE OPEN" % [Game.floor_index, Game.max_floor()],
				HORIZONTAL_ALIGNMENT_CENTER, 320.0, 8, DIM)
		return
	if Game.wave <= 0:
		return
	draw_string(font, Vector2(size.x * 0.5 - 140.0, 22.0),
		"WAVE %d / %d" % [Game.wave, Game.wave_total],
		HORIZONTAL_ALIGNMENT_CENTER, 280.0, 11, FG)
	if Game.enemies_left > 0:
		draw_string(font, Vector2(size.x * 0.5 - 140.0, 36.0),
			"%d HOSTILE%s" % [Game.enemies_left, "" if Game.enemies_left == 1 else "S"],
			HORIZONTAL_ALIGNMENT_CENTER, 280.0, 8, DIM)


func _level_node() -> Node:
	var main := get_parent()
	while main != null and not main.has_method("start_floor"):
		main = main.get_parent()
	if main == null:
		return null
	return main.get("level")


func _draw_boss(font: Font, size: Vector2) -> void:
	if not is_instance_valid(Game.boss):
		return
	var boss := Game.boss
	var width := 320.0
	var x := (size.x - width) * 0.5
	var y := 52.0
	var ratio := clampf(boss.hp / maxf(boss.max_hp, 1.0), 0.0, 1.0)
	draw_string(font, Vector2(size.x * 0.5 - 140.0, y - 6.0), "THE WARDEN",
		HORIZONTAL_ALIGNMENT_CENTER, 280.0, 9, FG)
	MathArt.px_rect(self, Rect2(x - 2.0, y - 2.0, width + 4.0, 10.0), Color(0.0, 0.0, 0.0, 0.8))
	MathArt.px_rect(self, Rect2(x, y, width, 6.0), MathArt.STONE)
	MathArt.px_rect(self, Rect2(x, y, width * ratio, 6.0), FG)
	MathArt.px_rect(self, Rect2(x, y, width * ratio, 1.5), FG_HI)
	for i in range(1, 5):
		MathArt.px_rect(self, Rect2(x + width * float(i) / 5.0, y, 1, 6.0), Color(0.0, 0.0, 0.0, 0.45))


func _draw_combo(font: Font, size: Vector2) -> void:
	if Game.combo < 2:
		return
	var pop := 1.0 + Game.combo_pop * 0.2
	var center := Vector2(size.x - 46.0, 54.0)
	var radius := 22.0 * pop
	var ratio := clampf(Game.combo_time / Game.COMBO_WINDOW, 0.0, 1.0)
	MathArt.ring(self, center, radius, Color(0.0, 0.0, 0.0, 0.6), 3.0)
	MathArt.arc(self, center, radius, -PI * 0.5, -PI * 0.5 + TAU * ratio, FG_HI, 3.0)
	draw_string(font, Vector2(center.x - 24.0, center.y + 5.0), "%d" % Game.combo,
		HORIZONTAL_ALIGNMENT_CENTER, 48.0, int(15.0 * pop), FG_HI)
	draw_string(font, Vector2(center.x - 30.0, center.y + 32.0), "COMBO",
		HORIZONTAL_ALIGNMENT_CENTER, 60.0, 7, DIM2)


func _draw_edge(font: Font, size: Vector2) -> void:
	if Game.edge_timer <= 0.0:
		return
	var ratio := clampf(Game.edge_timer / Game.PERFECT_DODGE_TIME, 0.0, 1.0)
	var x := size.x - 132.0
	_text(font, Vector2(x, 96), "EDGE +25%", FG_HI, 9)
	MathArt.px_rect(self, Rect2(x, 102, 112, 3), Color(0.0, 0.0, 0.0, 0.6))
	MathArt.px_rect(self, Rect2(x, 102, 112.0 * ratio, 3), FG_HI)


func _draw_timer(font: Font, size: Vector2) -> void:
	var total := int(Game.run_time)
	draw_string(font, Vector2(size.x - 100.0, 22.0), "%02d:%02d" % [total / 60, total % 60],
		HORIZONTAL_ALIGNMENT_RIGHT, 80.0, 11, DIM)


func _draw_build(font: Font, size: Vector2) -> void:
	if Game.reward_counts.is_empty():
		return
	var parts: Array[String] = []
	for id in Game.reward_counts:
		var count := int(Game.reward_counts[id])
		parts.append(str(id).to_upper() + ("x%d" % count if count > 1 else ""))
	draw_string(font, Vector2(size.x - 300.0, size.y - 42.0), " · ".join(parts),
		HORIZONTAL_ALIGNMENT_RIGHT, 280.0, 8, Color(DIM, 0.8))


func _draw_hints(font: Font, size: Vector2) -> void:
	draw_string(font, Vector2(20, size.y - 14.0),
		"A/D MOVE    SPACE JUMP    J EDGE    K KUNAI    L AEGIS    SHIFT ROLL    ESC PAUSE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(DIM, 0.85))
	draw_string(font, Vector2(size.x - 130.0, size.y - 14.0), "ASHFALL 0.3",
		HORIZONTAL_ALIGNMENT_RIGHT, 110.0, 8, Color(DIM2, 0.6))


func _draw_announce(font: Font, size: Vector2) -> void:
	if Game.announce_text.is_empty() or Game.announce_t <= 0.0:
		return
	var elapsed := Game.announce_max - Game.announce_t
	var alpha := clampf(elapsed / 0.14, 0.0, 1.0) * clampf(Game.announce_t / 0.26, 0.0, 1.0)
	var y := size.y * 0.30
	draw_string(font, Vector2(size.x * 0.5 - 200.0, y), Game.announce_text,
		HORIZONTAL_ALIGNMENT_CENTER, 400.0, 24, Color(FG, alpha))
	MathArt.px_rect(self, Rect2(size.x * 0.5 - 50.0, y + 6.0, 100, 1), Color(FG_HI, alpha * 0.8))


func _draw_low_health(size: Vector2) -> void:
	var player := Game.player
	if player == null or Game.run_over:
		return
	var ratio := player.hp / maxf(player.max_hp, 1.0)
	if ratio > 0.3:
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 7.0)
	var alpha := 0.08 + 0.14 * pulse * (1.0 - ratio / 0.3)
	var tint := Color(1.000, 1.000, 1.000, alpha)
	MathArt.px_rect(self, Rect2(0, 0, size.x, 2), tint)
	MathArt.px_rect(self, Rect2(0, size.y - 2, size.x, 2), tint)
	MathArt.px_rect(self, Rect2(0, 0, 2, size.y), tint)
	MathArt.px_rect(self, Rect2(size.x - 2, 0, 2, size.y), tint)


func _draw_hurt_flash(size: Vector2) -> void:
	if Game.hurt_flash <= 0.0:
		return
	var alpha := clampf(Game.hurt_flash / 0.32, 0.0, 1.0)
	MathArt.px_rect(self, Rect2(0, 0, size.x, size.y), Color(1.000, 1.000, 1.000, alpha * 0.10))
	MathArt.px_rect(self, Rect2(0, 0, size.x, 2), Color(1.000, 1.000, 1.000, alpha * 0.75))
	MathArt.px_rect(self, Rect2(0, size.y - 2, size.x, 2), Color(1.000, 1.000, 1.000, alpha * 0.75))


func _draw_corners(size: Vector2) -> void:
	var ink := Color(MathArt.WHITE, 0.18)
	var length := 14.0
	var m := 10.0
	MathArt.px_rect(self, Rect2(m, m, length, 1), ink)
	MathArt.px_rect(self, Rect2(m, m, 1, length), ink)
	MathArt.px_rect(self, Rect2(size.x - m - length, m, length, 1), ink)
	MathArt.px_rect(self, Rect2(size.x - m - 1.0, m, 1, length), ink)
	MathArt.px_rect(self, Rect2(m, size.y - m - 1.0, length, 1), ink)
	MathArt.px_rect(self, Rect2(m, size.y - m - length, 1, length), ink)
	MathArt.px_rect(self, Rect2(size.x - m - length, size.y - m - 1.0, length, 1), ink)
	MathArt.px_rect(self, Rect2(size.x - m - 1.0, size.y - m - length, 1, length), ink)


func _draw_pause(font: Font, size: Vector2) -> void:
	MathArt.px_rect(self, Rect2(0, 0, size.x, size.y), Color(0.028, 0.028, 0.028, 0.82))
	MathArt.ring(self, Vector2(size.x * 0.5, size.y * 0.44), 70.0, Color(MathArt.WHITE, 0.14), 1.0)
	MathArt.ring(self, Vector2(size.x * 0.5, size.y * 0.44), 44.0, Color(MathArt.WHITE, 0.10), 1.0)
	draw_string(font, Vector2(size.x * 0.5 - 200.0, size.y * 0.44), "PAUSED",
		HORIZONTAL_ALIGNMENT_CENTER, 400.0, 34, FG)
	MathArt.px_rect(self, Rect2(size.x * 0.5 - 44.0, size.y * 0.44 + 12.0, 88, 1), FG_HI)
	draw_string(font, Vector2(size.x * 0.5 - 200.0, size.y * 0.44 + 40.0),
		"ESC RESUME      R RESTART      Q QUIT",
		HORIZONTAL_ALIGNMENT_CENTER, 400.0, 10, DIM)


func _draw_run_over(font: Font, size: Vector2) -> void:
	MathArt.px_rect(self, Rect2(0, 0, size.x, size.y), Color(0.028, 0.028, 0.028, 0.85))
	var title := "FLOOR CLEARED" if Game.victory else "YOU DIED"
	var y := size.y * 0.34
	draw_string(font, Vector2(size.x * 0.5 - 220.0, y), title,
		HORIZONTAL_ALIGNMENT_CENTER, 440.0, 38, FG_HI)
	MathArt.px_rect(self, Rect2(size.x * 0.5 - 60.0, y + 12.0, 120, 1), Color(FG_HI, 0.8))
	var total := int(Game.run_time)
	var stats := "%d CELLS    %d KILLS    x%d COMBO    %d PERFECT    %02d:%02d" % [
		Game.cells, Game.kills, Game.max_combo, Game.perfect_dodges, total / 60, total % 60
	]
	draw_string(font, Vector2(size.x * 0.5 - 240.0, y + 44.0), stats,
		HORIZONTAL_ALIGNMENT_CENTER, 480.0, 10, FG)
	draw_string(font, Vector2(size.x * 0.5 - 240.0, y + 72.0), "PRESS R TO RUN IT BACK",
		HORIZONTAL_ALIGNMENT_CENTER, 480.0, 9, DIM)
