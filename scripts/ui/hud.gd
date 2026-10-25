class_name Hud
extends Control
## Monochrome HUD for 768x480. Every readout sits in a plate on a φ grid
## (16px margin, 10px gaps); nothing relies on colour to be understood.

const FG := MathArt.PALE
const FG_HI := MathArt.WHITE
const DIM := MathArt.MID
const DIM2 := MathArt.MID_DIM
const BG := MathArt.INK
const BLACK := MathArt.BLACK

# Proportional grid: the margin is 16 and every gap between plates is that
# margin divided by φ, so the HUD column reads as one rhythm instead of
# eyeballed offsets.
const MARGIN := 16.0
const STEP := 10.0
const COL_W := 176.0
const HP_PER_SEGMENT := 20.0
## Hard cap on the segmented health bar's draw loop. See _hp_segments().
const MAX_HP_SEGMENTS := 40

var paused := false

# Health is the only readout whose history matters: a lost segment flashes for
# two frames, so the draw needs the previous lit count.
var _hp_lit := -1
var _hp_flash_at := -1
var _hp_flash_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	queue_redraw()


func _process(delta: float) -> void:
	_hp_flash_t = maxf(0.0, _hp_flash_t - delta)
	# is_instance_valid, not `!= null`: a freed-but-referenced player (the
	# frame between a floor being torn down and the next body existing) turns
	# every read below into an engine error PER FRAME. In the headless audits
	# that error spam cost 42 s per frame.
	var player := Game.player if is_instance_valid(Game.player) else null
	if player != null:
		var lit := int(ceil(_hp_ratio(player) * float(_hp_segments(player))))
		if _hp_lit >= 0 and lit < _hp_lit:
			_hp_flash_at = clampi(lit, 0, _hp_segments(player) - 1)
			_hp_flash_t = 0.034
		_hp_lit = lit
	queue_redraw()


func _hp_ratio(player: Player) -> float:
	return clampf(player.hp / maxf(player.max_hp, 1.0), 0.0, 1.0)


func _hp_segments(player: Player) -> int:
	# Clamped, and it has to be: this number is the count of a per-frame draw
	# loop, so an unbounded max_hp is an unbounded frame cost. The audits set
	# max_hp to 1e9 to survive a walk and the loop ran ~5e7 times - 42 s per
	# frame. A run cannot exceed ~250 hp, so 40 segments is already more than
	# the bar can show.
	return clampi(int(round(player.max_hp / HP_PER_SEGMENT)), 4, MAX_HP_SEGMENTS)


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
	if event.is_action_pressed("pause") and not Game.run_over and Game.hub_return_in <= 0.0:
		# Not while the scene is about to change: Main's fade veil sits above this
		# layer, and pausing would freeze Main's _process and its tween with the
		# veil at alpha 1 - an opaque black screen with the PAUSED overlay
		# painted underneath it, which reads as a hung game.
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
	paused = false
	Combat.cancel_hitstop()
	# Reloading the scene here rebuilt Main, showed the title and dropped the
	# player in the hub with the next floor already unlocked: a retry that
	# banked progress and skipped a floor. Main owns the correct behaviour.
	var main := get_parent()
	while main != null and not main.has_method("restart_attempt"):
		main = main.get_parent()
	if main != null:
		main.restart_attempt()
		return
	get_tree().reload_current_scene()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var size := get_viewport_rect().size
	_draw_hurt_flash(size)
	_draw_left_column(font)
	_draw_timer(font, size)
	_draw_combo(font, size)
	_draw_edge(font, size)
	if not Game.in_hub:
		_draw_progress(font, size)
	_draw_boss(font, size)
	_draw_build(font, size)
	_draw_hints(font, size)
	_draw_announce(font, size)
	_draw_low_health(size)

	if paused:
		_draw_pause(font, size)
	elif Game.run_over:
		_draw_run_over(font, size)


## A plate is the HUD's unit: ink backing, one bright pixel along the top and a
## 12% seam at the bottom. Everything drawn on the HUD sits in one.
func _plate(rect: Rect2) -> void:
	MathArt.px_rect(self, rect, Color(BG, 0.82))
	MathArt.px_rect(self, Rect2(rect.position, Vector2(rect.size.x, 1)), Color(FG_HI, 0.55))
	MathArt.px_rect(self, Rect2(rect.position + Vector2(0.0, rect.size.y - 1.0),
		Vector2(rect.size.x, 1)), Color(FG_HI, 0.12))


func _draw_left_column(font: Font) -> void:
	var y := MARGIN * 0.75
	var vitals := Rect2(MARGIN, y, COL_W, 32.0)
	_plate(vitals)
	_draw_vitals(font, vitals)
	y += vitals.size.y + STEP
	var cells := Rect2(MARGIN, y, COL_W, 22.0)
	_plate(cells)
	_draw_cells(font, cells)
	y += cells.size.y + STEP
	var knives := Rect2(MARGIN, y, COL_W, 30.0)
	_plate(knives)
	_draw_knives(font, knives)
	y += knives.size.y + STEP
	var aegis := Rect2(MARGIN, y, COL_W, 26.0)
	_plate(aegis)
	_draw_aegis(font, aegis)


func _text(font: Font, at: Vector2, text: String, color: Color, size := 9) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## VITALITY: the loudest read on the HUD. Whole segments, φ-counted notches and
## a two-frame white flash on the segment that was just lost.
func _draw_vitals(font: Font, plate: Rect2) -> void:
	# is_instance_valid, not `!= null`: a freed-but-referenced player (the
	# frame between a floor being torn down and the next body existing) turns
	# every read below into an engine error PER FRAME. In the headless audits
	# that error spam cost 42 s per frame.
	var player := Game.player if is_instance_valid(Game.player) else null
	if player == null:
		return
	var segments := _hp_segments(player)
	var ratio := _hp_ratio(player)
	_text(font, Vector2(plate.position.x + 8.0, plate.position.y + 13.0), "VITALITY", DIM, 9)
	draw_string(font, Vector2(plate.position.x + plate.size.x - 84.0, plate.position.y + 13.0),
		"%d / %d" % [int(ceil(player.hp)), int(player.max_hp)],
		HORIZONTAL_ALIGNMENT_RIGHT, 76.0, 10, FG)
	var bar := Rect2(plate.position.x + 8.0, plate.position.y + 20.0, plate.size.x - 16.0, 10.0)
	MathArt.px_rect(self, bar.grow(1.0), Color(BLACK, 0.6))
	var lit := int(ceil(ratio * float(segments)))
	var seg_w := bar.size.x / float(segments)
	for i in segments:
		var seg := Rect2(bar.position.x + seg_w * float(i), bar.position.y, seg_w - 1.0, bar.size.y)
		if i < lit:
			MathArt.px_rect(self, seg, MathArt.LIGHT)
			MathArt.px_rect(self, Rect2(seg.position, Vector2(seg.size.x, 1.0)), FG_HI)
		elif i == _hp_flash_at and _hp_flash_t > 0.0:
			MathArt.px_rect(self, seg, FG_HI)
		else:
			MathArt.px_rect(self, seg, Color(MathArt.STONE, 0.45))


func _draw_cells(font: Font, plate: Rect2) -> void:
	var center := Vector2(plate.position.x + 14.0, plate.position.y + 11.0)
	MathArt.px_poly(self, PackedVector2Array([
		center + Vector2(0, -5), center + Vector2(4, 0),
		center + Vector2(0, 5), center + Vector2(-4, 0),
	]), FG_HI, FG_HI, 1.0)
	# WHICH wallet: in the hub the only number that matters is the bank the
	# stations spend from, and Game.cells is 0 there (it is a run counter), so
	# the plate read "CELLS 0" next to a hub header reading "CELLS 420". On a
	# floor the number at stake is what this floor has earned, because that is
	# what a death forfeits.
	# WHICH wallet: in the hub the only number that matters is the bank the
	# stations spend from (Game.cells is a run counter and is 0 there). On a
	# floor it is what this floor has earned, because that is what a death
	# forfeits. In the arena fixture nothing ever calls start_floor(), so
	# run_cells stays 0 for the whole run and the plate would read "0 CELLS"
	# while cells were being picked up - hence the third case. After the floor is
	# banked (run_over) the run total is the only number that still exists.
	var shown := Profile.cells
	if not _in_hub():
		shown = Game.cells if Game.floor_index <= 0 else Game.run_cells
		if Game.run_over and Game.cells > 0:
			shown = Game.cells
	draw_string(font, Vector2(plate.position.x + 24.0, plate.position.y + 16.0), "%d" % shown,
		HORIZONTAL_ALIGNMENT_LEFT, 60.0, 12, FG)
	_text(font, Vector2(plate.position.x + 88.0, plate.position.y + 15.0), "CELLS", DIM2, 8)


func _draw_knives(font: Font, plate: Rect2) -> void:
	# is_instance_valid, not `!= null`: a freed-but-referenced player (the
	# frame between a floor being torn down and the next body existing) turns
	# every read below into an engine error PER FRAME. In the headless audits
	# that error spam cost 42 s per frame.
	var player := Game.player if is_instance_valid(Game.player) else null
	if player == null:
		return
	_text(font, Vector2(plate.position.x + 8.0, plate.position.y + 11.0), "KUNAI", DIM2, 8)
	for i in player.knife_max:
		var center := Vector2(plate.position.x + 14.0 + i * 14.0, plate.position.y + 20.0)
		var charged := i < player.knife_charges
		var tint := FG_HI if charged else MathArt.MID_DIM
		var alpha := 0.95 if charged else 0.35
		MathArt.px_poly(self, PackedVector2Array([
			center + Vector2(0, -4), center + Vector2(3, 0),
			center + Vector2(0, 4), center + Vector2(-3, 0),
		]), Color(tint, alpha), Color(tint, alpha), 1.0)
	if player.knife_charges < player.knife_max:
		var ratio := clampf(player._knife_regen / player.knife_regen_time, 0.0, 1.0)
		MathArt.px_rect(self, Rect2(plate.position.x + 8.0, plate.position.y + 26.0,
			plate.size.x - 16.0, 2.0), Color(BLACK, 0.6))
		MathArt.px_rect(self, Rect2(plate.position.x + 8.0, plate.position.y + 26.0,
			(plate.size.x - 16.0) * ratio, 2.0), FG_HI)


func _draw_aegis(font: Font, plate: Rect2) -> void:
	# is_instance_valid, not `!= null`: a freed-but-referenced player (the
	# frame between a floor being torn down and the next body existing) turns
	# every read below into an engine error PER FRAME. In the headless audits
	# that error spam cost 42 s per frame.
	var player := Game.player if is_instance_valid(Game.player) else null
	if player == null:
		return
	var center := Vector2(plate.position.x + 18.0, plate.position.y + 13.0)
	var total := player.aegis_time + player.aegis_cooldown
	var ratio := 1.0 - clampf(player.aegis_cd / maxf(total, 0.001), 0.0, 1.0)
	var ready := player.aegis_cd <= 0.0
	_text(font, Vector2(plate.position.x + 32.0, plate.position.y + 11.0), "AEGIS", DIM2, 8)
	MathArt.ring(self, center, 7.0, Color(BLACK, 0.7), 3.0)
	MathArt.arc(self, center, 7.0, -PI * 0.5, -PI * 0.5 + TAU * ratio,
		Color(FG_HI, 1.0 if ready else 0.5), 3.0)
	if player.aegis_t > 0.0:
		MathArt.disc(self, center, 2.4, FG_HI)
	elif ready:
		MathArt.disc(self, center, 1.8, Color(FG_HI, 0.8))
	_text(font, Vector2(plate.position.x + 32.0, plate.position.y + 21.0),
		"READY" if ready else "%.1fs" % maxf(player.aegis_cd, 0.0),
		FG if ready else DIM, 8)


## Floor progress: name, a route strip, hostiles as tally marks (never a bare
## number) and the boon budget still owed by this floor. Hub mode draws none of
## this.
func _draw_progress(font: Font, size: Vector2) -> void:
	if Game.floor_index <= 0:
		if Game.wave <= 0:
			return
		var wave_plate := Rect2(size.x * 0.5 - 168.0, MARGIN * 0.75, 336.0, 42.0)
		_plate(wave_plate)
		draw_string(font, Vector2(wave_plate.position.x + 8.0, wave_plate.position.y + 14.0),
			"WAVE %d / %d" % [Game.wave, Game.wave_total],
			HORIZONTAL_ALIGNMENT_CENTER, 320.0, 11, FG)
		if Game.enemies_left > 0:
			_draw_tally(font, Vector2(wave_plate.position.x + 8.0, wave_plate.position.y + 18.0),
				Game.enemies_left)
			_text(font, Vector2(wave_plate.position.x + 336.0 - 158.0, wave_plate.position.y + 36.0),
				"%d HOSTILE%s" % [Game.enemies_left, "" if Game.enemies_left == 1 else "S"], DIM, 8)
		return

	var plate := Rect2(size.x * 0.5 - 168.0, MARGIN * 0.75, 336.0, 52.0)
	_plate(plate)
	draw_string(font, Vector2(plate.position.x + 8.0, plate.position.y + 14.0),
		Game.floor_name, HORIZONTAL_ALIGNMENT_CENTER, 320.0, 11, FG)
	var level := _level_node()
	var remaining := -1
	if level != null and level.has_method("enemies_remaining"):
		remaining = int(level.enemies_remaining())
	_draw_route(level, plate)
	var summary := "FLOOR %d / %d   BOONS %d" % [Game.floor_index, Game.max_floor(),
		Game.floor_rewards_left]
	if remaining > 0:
		_draw_tally(font, Vector2(plate.position.x + 10.0, plate.position.y + 30.0), remaining)
	else:
		_text(font, Vector2(plate.position.x + 10.0, plate.position.y + 38.0), "GATE OPEN", FG_HI, 8)
	draw_string(font, Vector2(plate.position.x + 8.0, plate.position.y + 47.0), summary,
		HORIZONTAL_ALIGNMENT_RIGHT, 320.0, 8, DIM)


## The floor on one line: one block per room (lit once cleared), a marker for
## the gate and a dot for the player. Without it the only navigation aid on a
## 8200 px floor is "hold right", and a player who took the upper route has no
## idea whether the gate is behind them.
func _draw_route(level: Node, plate: Rect2) -> void:
	if level == null:
		return
	var data: Variant = level.get("data")
	if typeof(data) != TYPE_DICTIONARY:
		return
	var rooms: Array = (data as Dictionary).get("rooms", [])
	if rooms.is_empty():
		return
	var width := maxf(1.0, float((data as Dictionary).get("width", 1.0)))
	var x0 := plate.position.x + 10.0
	var span := plate.size.x - 20.0
	var y := plate.position.y + 22.0
	var flags: Array = level.room_flags() if level.has_method("room_flags") else []
	for i in rooms.size():
		var r: Rect2 = (rooms[i] as Dictionary)["rect"]
		var a := x0 + span * (r.position.x / width)
		var b := x0 + span * (r.end.x / width)
		var done := i < flags.size() and bool(flags[i])
		MathArt.px_rect(self, Rect2(a, y, maxf(b - a - 1.0, 2.0), 3.0),
			Color(FG_HI, 0.70) if done else Color(MathArt.STONE, 0.55))
	var gate_open := false
	if level.has_method("enemies_remaining"):
		gate_open = int(level.enemies_remaining()) == 0
	var gx := x0 + span * clampf(float(((data as Dictionary).get("exit", Vector2.ZERO) as Vector2).x) / width, 0.0, 1.0)
	MathArt.px_rect(self, Rect2(gx - 1.0, y - 3.0, 2.0, 9.0), FG_HI if gate_open else DIM)
	var player := Game.player if is_instance_valid(Game.player) else null
	if player != null:
		var px := x0 + span * clampf(player.global_position.x / width, 0.0, 1.0)
		MathArt.px_rect(self, Rect2(px - 1.0, y - 2.0, 3.0, 7.0), FG_HI)


## One tick per hostile, grouped in fives so the count stays countable at a
## glance; past 34 the tail is reported as +n instead of a wall of pixels.
func _draw_tally(font: Font, at: Vector2, count: int) -> void:
	var shown := mini(count, 34)
	for i in shown:
		var group := (i + 1) % 5 == 0
		var height := 8.0 if group else 6.0
		MathArt.px_rect(self, Rect2(at.x + float(i) * 5.0, at.y + 8.0 - height, 1, height),
			FG_HI if group else DIM)
	if count > shown:
		_text(font, Vector2(at.x + 34.0 * 5.0 + 6.0, at.y + 8.0), "+%d" % (count - shown), DIM, 8)


func _level_node() -> Node:
	var main := get_parent()
	while main != null and not main.has_method("start_floor"):
		main = main.get_parent()
	if main == null:
		return null
	return main.get("level")


## True only while the walkable hub is the live scene. `hub` is a field on Main
## that is nulled by _clear_terrain(), so a freed node cannot answer here.
func _in_hub() -> bool:
	var main := get_parent()
	while main != null and not main.has_method("start_floor"):
		main = main.get_parent()
	if main == null:
		return false
	return is_instance_valid(main.get("hub"))


## The boss keeps the top-centre slot. The game exposes no attack name, so the
## bar shows the name and the segmented pool only.
func _draw_boss(font: Font, size: Vector2) -> void:
	if not is_instance_valid(Game.boss):
		return
	var boss := Game.boss
	var width := 320.0
	# 52 is the progress plate's height (hud.gd _draw_progress): the boss plate sits
	# one STEP under it, like every other pair on this HUD.
	var plate := Rect2(size.x * 0.5 - 168.0, MARGIN * 0.75 + 52.0 + STEP, 336.0, 22.0)
	_plate(plate)
	var x := plate.position.x + 8.0
	var y := plate.position.y + 14.0
	var ratio := clampf(boss.hp / maxf(boss.max_hp, 1.0), 0.0, 1.0)
	draw_string(font, Vector2(x, plate.position.y + 10.0), "THE WARDEN",
		HORIZONTAL_ALIGNMENT_CENTER, width, 9, FG)
	MathArt.px_rect(self, Rect2(x, y, width, 6.0), MathArt.STONE)
	MathArt.px_rect(self, Rect2(x, y, width * ratio, 6.0), FG)
	MathArt.px_rect(self, Rect2(x, y, width * ratio, 1.5), FG_HI)
	for i in range(1, 5):
		MathArt.px_rect(self, Rect2(x + width * float(i) / 5.0, y, 1, 6.0), Color(BLACK, 0.55))


## Combo is a timer, so the remaining window is the arc, not the number.
func _draw_combo(font: Font, size: Vector2) -> void:
	if Game.combo < 2:
		return
	var pop := 1.0 + Game.combo_pop * 0.2
	var plate := Rect2(size.x - MARGIN - 74.0, MARGIN * 0.75 + 22.0 + STEP, 74.0, 50.0)
	_plate(plate)
	var center := Vector2(plate.position.x + plate.size.x * 0.5, plate.position.y + 20.0)
	var radius := 15.0 * pop
	var ratio := clampf(Game.combo_time / Game.COMBO_WINDOW, 0.0, 1.0)
	MathArt.ring(self, center, radius, Color(BLACK, 0.6), 3.0)
	MathArt.arc(self, center, radius, -PI * 0.5, -PI * 0.5 + TAU * ratio, FG_HI, 3.0)
	draw_string(font, Vector2(center.x - 24.0, center.y + 5.0), "%d" % Game.combo,
		HORIZONTAL_ALIGNMENT_CENTER, 48.0, int(15.0 * pop), FG_HI)
	draw_string(font, Vector2(plate.position.x, plate.position.y + 46.0), "COMBO",
		HORIZONTAL_ALIGNMENT_CENTER, plate.size.x, 8, DIM2)


## Perfect Dodge is a timer too: a draining bar plus the seconds left.
func _draw_edge(font: Font, size: Vector2) -> void:
	if Game.edge_timer <= 0.0:
		return
	var ratio := clampf(Game.edge_timer / Game.PERFECT_DODGE_TIME, 0.0, 1.0)
	var plate := Rect2(size.x - MARGIN - 120.0, MARGIN * 0.75 + 22.0 + STEP + 50.0 + STEP, 120.0, 26.0)
	_plate(plate)
	_text(font, Vector2(plate.position.x + 8.0, plate.position.y + 12.0), "EDGE +25%", FG_HI, 9)
	draw_string(font, Vector2(plate.position.x + 72.0, plate.position.y + 12.0),
		"%.1fs" % Game.edge_timer, HORIZONTAL_ALIGNMENT_RIGHT, 40.0, 8, FG_HI)
	MathArt.px_rect(self, Rect2(plate.position.x + 8.0, plate.position.y + 16.0, 104.0, 3.0),
		Color(BLACK, 0.6))
	MathArt.px_rect(self, Rect2(plate.position.x + 8.0, plate.position.y + 16.0, 104.0 * ratio, 3.0), FG_HI)


func _draw_timer(font: Font, size: Vector2) -> void:
	var plate := Rect2(size.x - MARGIN - 88.0, MARGIN * 0.75, 88.0, 22.0)
	_plate(plate)
	var total := int(Game.run_time)
	draw_string(font, Vector2(plate.position.x + 6.0, plate.position.y + 16.0),
		"%02d:%02d" % [total / 60, total % 60],
		HORIZONTAL_ALIGNMENT_RIGHT, 76.0, 11, FG)


func _draw_build(font: Font, size: Vector2) -> void:
	if Game.reward_counts.is_empty():
		return
	var parts: Array[String] = []
	for id in Game.reward_counts:
		var count := int(Game.reward_counts[id])
		parts.append(str(id).to_upper() + ("x%d" % count if count > 1 else ""))
	var plate := Rect2(size.x - MARGIN - 296.0, size.y - 58.0, 296.0, 20.0)
	_plate(plate)
	draw_string(font, Vector2(plate.position.x + 8.0, plate.position.y + 15.0), "BUILD  " + " · ".join(parts),
		HORIZONTAL_ALIGNMENT_RIGHT, 280.0, 8, DIM)


func _draw_hints(font: Font, size: Vector2) -> void:
	# A modal panel (hub card, archive, tree) prints its own hint strip at the
	# bottom of the card, and this one contradicted it under the same screen.
	if _modal_open():
		return
	_plate(Rect2(MARGIN, size.y - 32.0, size.x - MARGIN * 2.0, 22.0))
	# Contextual: the hub has no combat, and a hint that does not work where it is
	# printed teaches the player that the hints are decoration. Tested on the hub
	# NODE, not on Game.in_hub: the arena fixture never calls start_floor(), so
	# in_hub stays true there and the capture harness printed J INTERACT over a
	# fight.
	var hints := "A/D MOVE    SPACE JUMP    J EDGE    K KUNAI    L AEGIS    SHIFT ROLL    ESC PAUSE"
	if _in_hub():
		hints = "A/D MOVE    SPACE JUMP    J INTERACT    ESC PAUSE"
	draw_string(font, Vector2(20, size.y - 14.0), hints,
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
	# A floor clear hands the player back to the hub on a timer. Saying so under
	# the headline is the difference between "the game moved on" and "the game
	# dropped me".
	if Game.hub_return_in > 0.05:
		draw_string(font, Vector2(size.x * 0.5 - 200.0, y + 24.0),
			"RETURNING TO HUB IN %.1fs" % Game.hub_return_in,
			HORIZONTAL_ALIGNMENT_CENTER, 400.0, 8, Color(DIM, alpha))


## Low health is an edge state: it never paints over the fight, and the pulse
## stays under the 12% ceiling the play area is allowed.
func _draw_low_health(size: Vector2) -> void:
	# is_instance_valid, not `!= null`: a freed-but-referenced player (the
	# frame between a floor being torn down and the next body existing) turns
	# every read below into an engine error PER FRAME. In the headless audits
	# that error spam cost 42 s per frame.
	var player := Game.player if is_instance_valid(Game.player) else null
	if player == null or Game.run_over:
		return
	var ratio := _hp_ratio(player)
	if ratio > 0.3:
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 7.0)
	var alpha := 0.06 + 0.06 * pulse * (1.0 - ratio / 0.3)
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
	# The overlay used to promise "PRESS R TO RUN IT BACK" and then leave for the
	# hub on a timer two seconds later, which made the only key it offered a
	# gamble on how fast the player read the screen. Say both things - and only
	# say the second one when a return is actually pending (the arena fixture
	# never returns to a hub).
	var back := "R RUN IT BACK" if Game.victory else "R RETRY"
	var leaving := ""
	if Game.hub_return_in > 0.05:
		leaving = "      RETURNING TO HUB IN %.1fs" % Game.hub_return_in
	draw_string(font, Vector2(size.x * 0.5 - 240.0, y + 72.0), back + leaving,
		HORIZONTAL_ALIGNMENT_CENTER, 480.0, 9, DIM)
