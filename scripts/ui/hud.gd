class_name Hud
extends Control
## HUD for 768x480: pale readouts, cool backing and semantic accents.
## Shapes and text keep every state readable independently of hue.

## The pause page asks Main to raise the single SettingsScreen above itself.
## Pause, checkpoint failure and abandon confirmation all stay exactly as they
## were; this signal never closes the page or changes tree pause.
signal settings_requested

const FG := MathArt.PALE
const FG_HI := MathArt.PALE
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
const PAUSE_DETAIL_ROWS := 7

# The 768x480 combat layout is fixed: equipment_rects() is the one public
# gear-geometry entry, and the plates around it are single-owner constants so
# probes compare the shipped rectangles instead of re-deriving them.
const FLASK_RECT := Rect2(16, 362, 42, 56)
const AXES_BASELINE := 434.0
const HP_RECT := Rect2(16, 440, 334, 24)
const MINIMAP_RECT := Rect2(588, 346, 164, 84)
const WALLET_RECT := Rect2(554, 432, 198, 32)
const PAUSE_DETAIL_RECT := Rect2(328, 176, 388, 136)

## Pause has two focus groups: the build slots on the left and the durable
## action row at the bottom. X switches groups; left/right never changes what
## up/down means, so detail scrolling stays independent of focus.
const PAUSE_FOCUS_GEAR := 0
const PAUSE_FOCUS_ACTIONS := 1
const PAUSE_ACTIONS := ["continue", "settings", "save", "abandon", "quit"]
## A failed checkpoint hides Continue/Abandon: the only safe exits are retry,
## previous checkpoint, settings and quit.
const PAUSE_ACTIONS_BLOCKED := ["retry", "previous", "settings", "quit"]

var paused := false
var checkpoint_blocked := false
var _pause_index := 0
var _pause_scroll := 0
var _pause_line_count := 0
var _pause_focus := PAUSE_FOCUS_GEAR
var _pause_action := 0
var _abandon_confirm := false

# Health is the only readout whose history matters: a lost segment flashes for
# two frames, so the draw needs the previous lit count.
var _hp_lit := -1
var _hp_flash_at := -1
var _hp_flash_t := 0.0

# --- Shared scripts/ui text surface -----------------------------------------
# ContentText owns row lookup and MathArt.ui_wrap owns the shaping cache, so
# this layer keeps only the three fixed axis labels the HUD draws on its own.
const AXIS_EN := {"brutality": "Brutality", "tactics": "Tactics", "survival": "Survival"}

var _prompt_cache := {}


static func axis_name(axis: String) -> String:
	return ContentText.name("axis", axis, str(AXIS_EN.get(axis, axis)))


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Interface.presentation_changed.is_connected(_on_presentation_changed):
		Interface.presentation_changed.connect(_on_presentation_changed)
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


func health_readout(player: Player) -> Dictionary:
	# Full uses raw values; otherwise floor current / ceil maximum conservatively.
	var maximum := int(ceil(player.max_hp))
	var full := player.hp >= player.max_hp
	var current := maximum if full else (maxi(1, int(floor(player.hp))) if player.hp > 0.0 else 0)
	return {"current":mini(current, maximum), "maximum":maximum, "full":full}


func health_segment_fill(player: Player, index: int) -> float:
	return clampf(_hp_ratio(player) * _hp_segments(player) - index, 0.0, 1.0)


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
	# One physical event runs at most one menu branch: Interface latches axes and
	# ignores key echo/releases, and every page keeps owning its own focus and
	# scroll state.
	# Quit is a terminal owner with no gameplay action: Q stays additive. The
	# durable pause row owns Quit for pad users now, so RB no longer aliases it.
	if paused and _abandon_confirm:
		if Interface.pressed(event, &"ui_accept") or Interface.pressed(event, &"restart"):
			_abandon_confirm = false
			_restart()
		elif Interface.pressed(event, &"ui_back") or Interface.pressed(event, &"pause"):
			# Back is the nearest layer: cancel the confirmation, not the run.
			_abandon_confirm = false
		elif _raw_key(event, KEY_Q):
			get_tree().quit()
		_consume_event(event)
		return
	if checkpoint_blocked:
		# A failed checkpoint is the only safe state: Accept retries, LB/T
		# returns to the previous checkpoint, and B/Start cannot unpause. The
		# action row keeps Settings and Quit reachable without releasing pause.
		_pause_focus = clampi(_pause_focus, PAUSE_FOCUS_GEAR, PAUSE_FOCUS_ACTIONS)
		_pause_action = clampi(_pause_action, 0, _pause_action_count() - 1)
		if Interface.pressed(event, &"ui_secondary"):
			_toggle_pause_focus()
			_consume_event(event)
			return
		if _pause_focus == PAUSE_FOCUS_ACTIONS:
			if Interface.pressed(event, &"ui_nav_left"):
				_pause_action = wrapi(_pause_action - 1, 0, _pause_action_count())
				MathArt.ui_select(self)
			elif Interface.pressed(event, &"ui_nav_right"):
				_pause_action = wrapi(_pause_action + 1, 0, _pause_action_count())
				MathArt.ui_select(self)
			elif Interface.pressed(event, &"ui_accept") or Interface.pressed(event, &"restart"):
				_run_pause_action(str(_pause_action_ids()[_pause_action]))
			elif Interface.pressed(event, &"ui_tab_prev") or _raw_key(event, KEY_T):
				_call_flow(&"return_to_title")
			_consume_event(event)
			return
		if Interface.pressed(event, &"ui_accept") or _raw_key(event, KEY_S):
			_call_flow(&"retry_checkpoint")
			_consume_event(event)
			return
		if Interface.pressed(event, &"ui_tab_prev") or _raw_key(event, KEY_T):
			_call_flow(&"return_to_title")
			_consume_event(event)
			return
		if _raw_key(event, KEY_Q):
			get_tree().quit()
			_consume_event(event)
			return
		# Everything else is swallowed: no held press may leak into a run that
		# has no saved checkpoint and therefore cannot safely resume.
		_consume_event(event)
		return
	if paused:
		if Interface.pressed(event, &"ui_back") or Interface.pressed(event, &"pause"):
			_set_paused(false)
			_consume_event(event)
			return
		if Interface.pressed(event, &"ui_secondary"):
			_toggle_pause_focus()
			_consume_event(event)
			return
		if Interface.pressed(event, &"ui_tab_prev") or _raw_key(event, KEY_T):
			# Save slots: the title screen resumes this checkpoint. This is the
			# same owner the old shortcut used, not a second save path.
			_call_flow(&"return_to_title")
			_consume_event(event)
			return
		if _raw_key(event, KEY_Q):
			get_tree().quit()
			_consume_event(event)
			return
		if Game.build == null:
			_pause_focus = PAUSE_FOCUS_ACTIONS
		if _pause_focus == PAUSE_FOCUS_ACTIONS:
			if Interface.pressed(event, &"ui_nav_left"):
				_pause_action = wrapi(_pause_action - 1, 0, _pause_action_count())
				MathArt.ui_select(self)
			elif Interface.pressed(event, &"ui_nav_right"):
				_pause_action = wrapi(_pause_action + 1, 0, _pause_action_count())
				MathArt.ui_select(self)
			elif Interface.pressed(event, &"ui_accept") or Interface.pressed(event, &"restart"):
				_run_pause_action(str(_pause_action_ids()[_pause_action]))
			elif Interface.pressed(event, &"ui_detail_up") or Interface.pressed(event, &"ui_nav_up"):
				_pause_scroll = maxi(0, _pause_scroll - 1)
			elif Interface.pressed(event, &"ui_detail_down") or Interface.pressed(event, &"ui_nav_down"):
				_pause_scroll = mini(maxi(0, _pause_line_count - PAUSE_DETAIL_ROWS), _pause_scroll + 1)
			_consume_event(event)
			return
		if Interface.pressed(event, &"ui_nav_left"):
			_pause_index = wrapi(_pause_index - 1, 0, 5)
			_pause_scroll = 0
			MathArt.ui_select(self)
		elif Interface.pressed(event, &"ui_nav_right"):
			_pause_index = wrapi(_pause_index + 1, 0, 5)
			_pause_scroll = 0
			MathArt.ui_select(self)
		elif Interface.pressed(event, &"ui_accept") or Interface.pressed(event, &"restart"):
			# Gear Accept never abandons: it moves focus to the action row's
			# Continue, and a second Accept is required to act.
			_pause_focus = PAUSE_FOCUS_ACTIONS
			_pause_action = 0
			MathArt.ui_select(self)
		elif Interface.pressed(event, &"ui_detail_up") or Interface.pressed(event, &"ui_nav_up"):
			_pause_scroll = maxi(0, _pause_scroll - 1)
		elif Interface.pressed(event, &"ui_detail_down") or Interface.pressed(event, &"ui_nav_down"):
			_pause_scroll = mini(maxi(0, _pause_line_count - PAUSE_DETAIL_ROWS), _pause_scroll + 1)
		_consume_event(event)
		return
	if Game.run_over:
		if Interface.pressed(event, &"ui_accept") or Interface.pressed(event, &"restart"):
			_restart()
			_consume_event(event)
			return
		# Run-over keeps its existing owner until its own focusable result row
		# lands; Q stays the additive keyboard quit.
		if _raw_key(event, KEY_Q) or Interface.pressed(event, &"ui_tab_next"):
			get_tree().quit()
			_consume_event(event)
			return
		_consume_event(event)
		return
	if Interface.pressed(event, &"pause") and not Game.run_over and Game.hub_return_in <= 0.0:
		# Not while the scene is about to change: Main's fade veil sits above this
		# layer, and pausing would freeze Main's _process and its tween with the
		# veil at alpha 1 - an opaque black screen with the PAUSED overlay
		# painted underneath it, which reads as a hung game.
		_set_paused(true)
		get_viewport().set_input_as_handled()
		return


## Raw keyboard shortcut (Q/S/T) that has no gameplay action and no pad
## equivalent; fresh physical press only, never echo or release.
func _raw_key(event: InputEvent, keycode: int) -> bool:
	if not event is InputEventKey:
		return false
	var key := event as InputEventKey
	return key.pressed and not key.echo and key.physical_keycode == keycode


func _consume_event(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventAction:
		get_viewport().set_input_as_handled()


## Stable public geometry for the durable pause row. One writer: drawing and
## input both read this, so a probe never has to duplicate the arithmetic.
func pause_action_rect(index: int) -> Rect2:
	return Rect2(52.0 + float(index) * 134.0, 376.0, 128.0, 28.0)


func _pause_action_ids() -> Array:
	return PAUSE_ACTIONS_BLOCKED if checkpoint_blocked else PAUSE_ACTIONS


func _pause_action_count() -> int:
	return _pause_action_ids().size()


## With no live build there are no gear cards to focus, but the action row
## still owns Continue/Settings/etc.
func _pause_focus_mode() -> int:
	return PAUSE_FOCUS_ACTIONS if Game.build == null else _pause_focus


func _toggle_pause_focus() -> void:
	if Game.build == null:
		_pause_focus = PAUSE_FOCUS_ACTIONS
		return
	_pause_focus = PAUSE_FOCUS_ACTIONS if _pause_focus == PAUSE_FOCUS_GEAR else PAUSE_FOCUS_GEAR
	MathArt.ui_select(self)


func _pause_action_label(id: String) -> String:
	match id:
		"continue": return ContentText.of("UI_HUD_ACTION_CONTINUE", "Continue")
		"settings": return ContentText.of("UI_HUD_ACTION_SETTINGS", "Settings")
		"save": return ContentText.of("UI_HUD_ACTION_SAVE", "Save")
		"abandon": return ContentText.of("UI_HUD_ACTION_ABANDON", "Abandon")
		"quit": return ContentText.of("UI_HUD_ACTION_QUIT", "Quit")
		"retry": return ContentText.of("UI_HUD_ACTION_RETRY", "Retry save")
		"previous": return ContentText.of("UI_HUD_ACTION_RESTORE_CHECKPOINT", "Restore checkpoint")
	return id


## Every item here maps to an owner that already exists. Settings only asks
## Main for the page; it never releases pause or clears abandon/blocked state.
func _run_pause_action(id: String) -> void:
	match id:
		"continue":
			_set_paused(false)
		"settings":
			settings_requested.emit()
		"save":
			_call_flow(&"return_to_title")
		"abandon":
			_abandon_confirm = true
		"quit":
			get_tree().quit()
		"retry":
			_call_flow(&"retry_checkpoint")
		"previous":
			_call_flow(&"return_to_title")
	queue_redraw()


func _pause_focus_hint() -> String:
	if checkpoint_blocked:
		return ContentText.of("UI_HUD_PAUSE_FOCUS_BLOCKED", "{secondary} Focus · {nav} Move · {accept} Select · checkpoint must be saved").format(_prompt_values())
	if _pause_focus_mode() == PAUSE_FOCUS_ACTIONS:
		return ContentText.of("UI_HUD_PAUSE_FOCUS_ACTIONS", "{secondary} Gear · {nav} Actions · {accept} Select · {back} Continue").format(_prompt_values())
	return ContentText.of("UI_HUD_PAUSE_FOCUS_GEAR", "{secondary} Actions · {nav} Equipment · {detail} Scroll details · {back} Continue").format(_prompt_values())


## Device-appropriate keycap for an actual action. Cached until Interface
## reports a locale or binding change; pages never build their own key names.
func _prompt(action: StringName) -> String:
	var key := String(action)
	if not _prompt_cache.has(key):
		_prompt_cache[key] = Interface.prompt(action)
	return str(_prompt_cache[key])


func _prompt_pair(first: StringName, second: StringName) -> String:
	var a := _prompt(first)
	var b := _prompt(second)
	if b.is_empty() or a == b:
		return a
	return "%s / %s" % [a, b]


## Named placeholders for the localized hint/control templates. Values are real
## InputMap prompts for the current device, so the same row works on pad.
func _prompt_values() -> Dictionary:
	return {
		"nav": _prompt_pair(&"ui_nav_left", &"ui_nav_right"),
		"detail": _prompt_pair(&"ui_detail_up", &"ui_detail_down"),
		"back": _prompt(&"ui_back"),
		"accept": _prompt(&"ui_accept"),
		"tabs": _prompt(&"ui_tab_prev"),
		"secondary": _prompt(&"ui_secondary"),
		"move": _prompt_pair(&"move_left", &"move_right"),
		"jump": _prompt(&"jump"),
		"interact": _prompt(&"interact"),
		"pause": _prompt(&"pause"),
		"attack": _prompt(&"attack"),
		"skills": _prompt_pair(&"throw", &"aegis"),
		"roll": _prompt(&"roll"),
		"map": _prompt(&"map"),
	}


func _on_presentation_changed() -> void:
	# Device/locale switch only rewrites prompts and glyphs. Focus, scroll and
	# every page-owned state stay exactly where they were.
	_prompt_cache.clear()
	queue_redraw()


func _flow_owner() -> Node:
	var main := get_parent()
	while main != null and not main.has_method("start_floor"):
		main = main.get_parent()
	return main


func _call_flow(method: StringName) -> void:
	var main := _flow_owner()
	if main != null and main.has_method(method):
		main.call(method)


func _settings_open() -> bool:
	var main := _flow_owner()
	if main == null:
		return false
	var page := main.get("settings_screen") as SettingsScreen
	return is_instance_valid(page) and page.is_open()


func _modal_open() -> bool:
	var main := _flow_owner()
	if main == null:
		return false
	# The shared SettingsScreen is a full-page layer above pause and title. It
	# must block every HUD menu path while visible, including the pause toggle.
	if _settings_open():
		return true
	# The title owns Esc as well: it pauses the tree itself, so a HUD pause
	# latched under it would paint PAUSED over the whole first run. Every meta
	# screen hides itself when closed, so `visible` is the whole open state
	# (the archive and the tree are CanvasLayers, the title is a Control).
	for name in ["title_screen", "archive", "skill_tree", "collector", "exploration_map", "build_screen", "reward_screen"]:
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


## A page, a hub panel, or the reward screen paints its own backdrop and
## wallet. The fight HUD must be absent underneath every one of them, including
## the announce overlay and the minimap.
func _full_page_open() -> bool:
	return Game.reward_open or _modal_open()


func _set_paused(value: bool) -> void:
	paused = value
	_abandon_confirm = false
	_pause_scroll = 0
	if value:
		_pause_focus = PAUSE_FOCUS_GEAR
		_pause_action = 0
	get_tree().paused = value
	if is_instance_valid(Game.player):
		Game.player.suppress_actions()
	if value:
		MathArt.ui_reveal(self)
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
	var main := _flow_owner()
	if main != null:
		main.restart_attempt()
		return
	get_tree().reload_current_scene()


func _draw() -> void:
	var font := MathArt.ui_font()
	var size := get_viewport_rect().size
	# Every full page paints its own single mask and complete information set.
	# Nothing from the fight may bleed through, not even the announce line.
	if _full_page_open():
		return
	if paused:
		_draw_pause(font, size)
		return
	if Game.run_over:
		_draw_run_over(font, size)
		return
	_draw_hurt_flash(size)
	var in_hub := _in_hub()
	# HubUi owns the banked currency header. Drawing the combat wallet and timer
	# here as well made the lobby show duplicate cells and a top-right plate under
	# the hub header.
	if not in_hub:
		if Game.build != null:
			_plate(HP_RECT)
			_draw_vitals(font, HP_RECT)
			_draw_wallet(font)
		else:
			_draw_left_column(font)
			_draw_timer(font, size)
	_draw_combo(font, size)
	_draw_edge(font, size)
	if not Game.in_hub:
		_draw_progress(font, size)
	_draw_boss(font, size)
	if not Game.in_hub and Game.build != null:
		_draw_axes(font)
	_draw_build(font, size)
	_draw_hints(font, size)
	if not Game.in_hub and Game.build != null:
		_draw_flask(font)
	_draw_announce(font, size)
	_draw_low_health(size)


## A plate is the HUD's unit: ink backing, one bright pixel along the top and a
## 12% seam at the bottom. Everything drawn on the HUD sits in one.
func _plate(rect: Rect2, opaque := false) -> void:
	# Bottom-right plates sit over world geometry, whose labels would otherwise
	# read as HUD content; those pass opaque so only the HUD is legible there.
	MathArt.px_rect(self, rect, BG if opaque else Color(BG, 0.82))
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
	if Game.build != null:
		return
	var knives := Rect2(MARGIN, y, COL_W, 32.0)
	_plate(knives)
	_draw_knives(font, knives)
	y += knives.size.y + STEP
	var aegis := Rect2(MARGIN, y, COL_W, 32.0)
	_plate(aegis)
	_draw_aegis(font, aegis)


func _text(font: Font, at: Vector2, text: String, color: Color, size := 11) -> void:
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
	var readout := health_readout(player)
	_text(font, Vector2(plate.position.x + 8.0, plate.position.y + 12.0), ContentText.of("UI_HUD_HP", "HP"), FG, 11)
	draw_string(font, Vector2(plate.position.x + 30.0, plate.position.y + 12.0),
		ContentText.of("UI_HUD_FULL", "Full") if readout.full else ContentText.of("UI_HUD_HURT", "Hurt"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MathArt.HEAL if readout.full else MathArt.DANGER)
	draw_string(font, Vector2(plate.position.x + plate.size.x - 108.0, plate.position.y + 12.0),
		"%d / %d" % [readout.current, readout.maximum],
		HORIZONTAL_ALIGNMENT_RIGHT, 100.0, 13, FG)
	# 4 px high: HP is a glance read, the exact numbers above carry the detail.
	var bar := Rect2(plate.position.x + 8.0, plate.position.y + 17.0, plate.size.x - 16.0, 4.0)
	MathArt.px_rect(self, bar.grow(1.0), Color(BLACK, 0.6))
	var seg_w := bar.size.x / float(segments)
	for i in segments:
		var seg := Rect2(bar.position.x + seg_w * float(i), bar.position.y, maxf(seg_w - 1.0, 1.0), bar.size.y)
		MathArt.px_rect(self, seg, Color(MathArt.STONE, 0.45))
		var fill := health_segment_fill(player, i)
		if fill > 0.0:
			var filled := Rect2(seg.position, Vector2(seg.size.x * fill, seg.size.y))
			MathArt.px_rect(self, filled, MathArt.DANGER if _hp_ratio(player) <= 0.3 else MathArt.HEAL)
			MathArt.px_rect(self, Rect2(filled.position, Vector2(filled.size.x, 1.0)), MathArt.PALE)
		if i == _hp_flash_at and _hp_flash_t > 0.0:
			MathArt.px_rect(self, seg, Color(MathArt.WHITE, 0.9))


func _draw_cells(font: Font, plate: Rect2) -> void:
	var center := Vector2(plate.position.x + 14.0, plate.position.y + 11.0)
	MathArt.px_poly(self, PackedVector2Array([
		center + Vector2(0, -5), center + Vector2(4, 0),
		center + Vector2(0, 5), center + Vector2(-4, 0),
	]), MathArt.CELL, MathArt.CELL, 1.0)
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
		HORIZONTAL_ALIGNMENT_LEFT, 60.0, 13, MathArt.CELL)
	_text(font, Vector2(plate.position.x + 88.0, plate.position.y + 15.0), ContentText.of("UI_HUD_CELLS", "CELLS"), DIM2, 11)


func _draw_knives(font: Font, plate: Rect2) -> void:
	# is_instance_valid, not `!= null`: a freed-but-referenced player (the
	# frame between a floor being torn down and the next body existing) turns
	# every read below into an engine error PER FRAME. In the headless audits
	# that error spam cost 42 s per frame.
	var player := Game.player if is_instance_valid(Game.player) else null
	if player == null:
		return
	var label := ContentText.name("gear", "kunai", str(Data.gear.items.get("kunai", {}).get("name", "Kunai")))
	_text(font, Vector2(plate.position.x + 8.0, plate.position.y + 11.0), label, DIM2, 11)
	for i in player.knife_max:
		var center := Vector2(plate.position.x + 14.0 + i * 14.0, plate.position.y + 21.0)
		var charged := i < player.knife_charges
		var tint := MathArt.TACTICS if charged else MathArt.MID_DIM
		var alpha := 0.95 if charged else 0.35
		MathArt.px_poly(self, PackedVector2Array([
			center + Vector2(0, -4), center + Vector2(3, 0),
			center + Vector2(0, 4), center + Vector2(-3, 0),
		]), Color(tint, alpha), Color(tint, alpha), 1.0)
	if player.knife_charges < player.knife_max:
		var ratio := clampf(player._knife_regen / player.knife_regen_time, 0.0, 1.0)
		MathArt.px_rect(self, Rect2(plate.position.x + 8.0, plate.position.y + 27.0,
			plate.size.x - 16.0, 2.0), Color(BLACK, 0.6))
		MathArt.px_rect(self, Rect2(plate.position.x + 8.0, plate.position.y + 27.0,
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
	var label := ContentText.name("gear", "aegis", str(Data.gear.items.get("aegis", {}).get("name", "Aegis")))
	_text(font, Vector2(plate.position.x + 32.0, plate.position.y + 11.0), label, DIM2, 11)
	MathArt.ring(self, center, 7.0, Color(BLACK, 0.7), 3.0)
	MathArt.arc(self, center, 7.0, -PI * 0.5, -PI * 0.5 + TAU * ratio,
		Color(FG_HI, 1.0 if ready else 0.5), 3.0)
	if player.aegis_t > 0.0:
		MathArt.disc(self, center, 2.4, FG_HI)
	elif ready:
		MathArt.disc(self, center, 1.8, Color(FG_HI, 0.8))
	_text(font, Vector2(plate.position.x + 32.0, plate.position.y + 24.0),
		ContentText.of("UI_HUD_READY", "READY") if ready else ContentText.of("UI_HUD_RECHARGING", "RECHARGING"),
		FG if ready else DIM, 11)


## Floor progress: name, a route strip, hostiles as tally marks (never a bare
## number) and the boon budget still owed by this floor. Hub mode draws none of
## this.
func _floor_title() -> String:
	var place := _floor_display()
	if Game.run_phase == "passage":
		return ContentText.of("UI_HUD_PASSAGE_TITLE", "Passage / {place}").format({"place": place})
	return place


func _draw_progress(font: Font, size: Vector2) -> void:
	if Game.build != null:
		# Location and route breadth belong to the biome-entry announce, the map
		# and pause. Combat keeps only the minimap.
		_draw_minimap()
		return
	if Game.floor_index <= 0:
		if Game.wave <= 0:
			return
		var wave_plate := Rect2(size.x * 0.5 - 168.0, MARGIN * 0.75, 336.0, 42.0)
		_plate(wave_plate)
		draw_string(font, Vector2(wave_plate.position.x + 8.0, wave_plate.position.y + 14.0),
			ContentText.of("UI_HUD_WAVE", "WAVE {wave} / {total}").format({"wave": Game.wave, "total": Game.wave_total}),
			HORIZONTAL_ALIGNMENT_CENTER, 320.0, 11, FG)
		if Game.enemies_left > 0:
			_draw_tally(font, Vector2(wave_plate.position.x + 8.0, wave_plate.position.y + 18.0),
				Game.enemies_left)
			_text(font, Vector2(wave_plate.position.x + 336.0 - 158.0, wave_plate.position.y + 36.0),
				ContentText.of("UI_HUD_HOSTILE_ONE", "{count} HOSTILE").format({"count": Game.enemies_left}) if Game.enemies_left == 1 else ContentText.of("UI_HUD_HOSTILES", "{count} HOSTILES").format({"count": Game.enemies_left}), DIM, 11)
		return

	var plate := Rect2(size.x * 0.5 - 168.0, MARGIN * 0.75, 336.0, 58.0)
	_plate(plate)
	draw_string(font, Vector2(plate.position.x + 8.0, plate.position.y + 14.0),
		_floor_title(), HORIZONTAL_ALIGNMENT_CENTER, 320.0, 11, FG)
	var level := _level_node()
	var remaining := -1
	if level != null and level.has_method("enemies_remaining"):
		remaining = int(level.enemies_remaining())
	_draw_route(level, plate)
	var visit := Game.route_history.size()
	var summary := ContentText.of("UI_HUD_VISIT_BSC", "Visit {visit} · {bsc} BSC").format({"visit": visit, "bsc": Game.run_bsc}) if not Game.run_node_id.is_empty() else ContentText.of("UI_HUD_FLOOR_BOONS", "FLOOR {floor} / {maximum}   BOONS {boons}").format({"floor": Game.floor_index, "maximum": Game.max_floor(), "boons": Game.floor_rewards_left})
	if remaining > 0:
		_draw_tally(font, Vector2(plate.position.x + 10.0, plate.position.y + 34.0), remaining)
	else:
		_text(font, Vector2(plate.position.x + 10.0, plate.position.y + 39.0),
			ContentText.of("UI_HUD_R_EXIT", "{interact} EXIT").format({"interact": _prompt(&"interact")}) if not Game.run_node_id.is_empty() else ContentText.of("UI_HUD_GATE_OPEN", "GATE OPEN"), FG_HI, 11)
	draw_string(font, Vector2(plate.position.x + 8.0, plate.position.y + 52.0), summary,
		HORIZONTAL_ALIGNMENT_RIGHT, 320.0, 11, DIM)


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
	if (data as Dictionary).has("biome"):
		var snapshot: Dictionary = level.map_snapshot()
		var font := MathArt.ui_font()
		draw_string(font, plate.position + Vector2(10, 26),
			ContentText.of("UI_HUD_ROOMS_FOUND", "ROOMS FOUND {count}    {map} MAP").format({"count": snapshot["rooms"].size(), "map": _prompt(&"map")}),
			HORIZONTAL_ALIGNMENT_LEFT, plate.size.x - 20, 11, MathArt.PALE)
		return
	var rooms: Array = (data as Dictionary).get("rooms", [])
	if rooms.is_empty():
		return
	var width := maxf(1.0, float((data as Dictionary).get("width", 1.0)))
	var x0 := plate.position.x + 10.0
	var span := plate.size.x - 20.0
	var y := plate.position.y + 24.0
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
		_text(font, Vector2(at.x + 34.0 * 5.0 + 6.0, at.y + 8.0), "+%d" % (count - shown), DIM, 11)


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


func _floor_display() -> String:
	if not Game.run_node_id.is_empty():
		return ContentText.name("biome", Game.run_node_id, Game.floor_name)
	if Game.floor_index > 0:
		return ContentText.of("FLOOR_%d_NAME" % Game.floor_index, Game.floor_name)
	return Game.floor_name


## The boss keeps the top-centre slot. The game exposes no attack name, so the
## bar shows the name and the segmented pool only.
func _draw_boss(font: Font, size: Vector2) -> void:
	if not is_instance_valid(Game.boss):
		return
	var boss := Game.boss
	var width := 320.0
	var plate := Rect2(size.x * 0.5 - 176.0, 16, 352.0, 44.0)
	_plate(plate)
	var x := plate.position.x + 16.0
	var y := plate.position.y + 27.0
	var ratio := clampf(boss.hp / maxf(boss.max_hp, 1.0), 0.0, 1.0)
	var boss_name := ContentText.name("enemy", str(boss.kind), str(boss.cfg.get("name", boss.kind)))
	draw_string(font, Vector2(x, plate.position.y + 18.0), boss_name,
		HORIZONTAL_ALIGNMENT_CENTER, width, 16, FG_HI)
	MathArt.px_rect(self, Rect2(x, y, width, 6.0), MathArt.STONE)
	MathArt.px_rect(self, Rect2(x, y, width * ratio, 6.0), MathArt.BOSS)
	MathArt.px_rect(self, Rect2(x, y, width * ratio, 1.5), MathArt.PALE)
	for i in range(1, 5):
		MathArt.px_rect(self, Rect2(x + width * float(i) / 5.0, y, 1, 6.0), Color(BLACK, 0.55))


## Combo is a timer, so the remaining window is the arc, not the number.
func _draw_combo(font: Font, size: Vector2) -> void:
	if Game.combo < 2:
		return
	var pop := 1.0 + Game.combo_pop * 0.2
	var plate := Rect2(size.x - MARGIN - 74.0, 136, 74.0, 50.0)
	_plate(plate)
	var center := Vector2(plate.position.x + plate.size.x * 0.5, plate.position.y + 20.0)
	var radius := 15.0 * pop
	var ratio := clampf(Game.combo_time / Game.COMBO_WINDOW, 0.0, 1.0)
	MathArt.ring(self, center, radius, Color(BLACK, 0.6), 3.0)
	MathArt.arc(self, center, radius, -PI * 0.5, -PI * 0.5 + TAU * ratio, FG_HI, 3.0)
	draw_string(font, Vector2(center.x - 24.0, center.y + 5.0), "%d" % Game.combo,
		HORIZONTAL_ALIGNMENT_CENTER, 48.0, 24, FG_HI)
	draw_string(font, Vector2(plate.position.x, plate.position.y + 46.0), ContentText.of("UI_HUD_COMBO", "COMBO"),
		HORIZONTAL_ALIGNMENT_CENTER, plate.size.x, 11, FG)


## Perfect Dodge is a timer too: a draining bar plus the seconds left.
func _draw_edge(font: Font, size: Vector2) -> void:
	if Game.edge_timer <= 0.0:
		return
	var ratio := clampf(Game.edge_timer / Game.PERFECT_DODGE_TIME, 0.0, 1.0)
	var plate := Rect2(size.x - MARGIN - 132.0, 196, 132.0, 30.0)
	_plate(plate)
	_text(font, Vector2(plate.position.x + 8.0, plate.position.y + 13.0), ContentText.of("UI_HUD_EDGE_BONUS", "Edge +25%"), FG_HI, 11)
	draw_string(font, Vector2(plate.position.x + 72.0, plate.position.y + 12.0),
		"%.1fs" % Game.edge_timer, HORIZONTAL_ALIGNMENT_RIGHT, 40.0, 11, FG_HI)
	MathArt.px_rect(self, Rect2(plate.position.x + 8.0, plate.position.y + 16.0, 104.0, 3.0),
		Color(BLACK, 0.6))
	MathArt.px_rect(self, Rect2(plate.position.x + 8.0, plate.position.y + 16.0, 104.0 * ratio, 3.0), FG_HI)


func _draw_wallet(font: Font) -> void:
	var build := Game.build
	if build == null:
		return
	var rect := WALLET_RECT
	_plate(rect, true)
	var pitch := MathArt.ui_line_height(11)
	var baseline := rect.position.y + 14.0
	var gold_text := ContentText.of("UI_HUD_WALLET_GOLD", "Gold {amount}").format({"amount": build.gold})
	var cells_text := ContentText.of("UI_HUD_WALLET_CELLS", "Cells carried {amount}").format({"amount": Game.run_cells})
	MathArt.ui_text(self, Vector2(rect.position.x + 8.0, baseline), gold_text, 11, MathArt.GOLD, 88.0)
	MathArt.ui_text(self, Vector2(rect.position.x + 98.0, baseline), cells_text, 11, MathArt.CELL,
		rect.size.x - 106.0, HORIZONTAL_ALIGNMENT_RIGHT)
	var total := int(Game.run_time)
	var time_text := ContentText.of("UI_HUD_WALLET_TIME", "Time {time}").format({"time": "%02d:%02d" % [total / 60, total % 60]})
	_text(font, Vector2(rect.position.x + 8.0, baseline + pitch), time_text, FG, 11)


func _draw_minimap() -> void:
	var level := _level_node()
	if level == null or not level.has_method("map_snapshot"):
		return
	var snapshot: Dictionary = level.map_snapshot()
	var rect := MINIMAP_RECT
	_plate(rect, true)
	MathArt.ui_text(self, rect.position + Vector2(8, 16), ContentText.of("UI_HUD_TAB_MAP", "{map}  Map").format({"map": _prompt(&"map")}), 11)
	var rooms: Array = snapshot.get("rooms", [])
	if rooms.is_empty():
		MathArt.ui_text(self, rect.position + Vector2(8, 44), ContentText.of("UI_HUD_EXPLORE_REVEAL", "Explore to reveal"), 11, DIM)
		return
	var bounds: Rect2 = rooms[0].bounds
	for room: Dictionary in rooms: bounds = bounds.merge(room.bounds)
	var map_size := Vector2(144, 56)
	var scale := minf(map_size.x / maxf(1, bounds.size.x), map_size.y / maxf(1, bounds.size.y))
	var origin := rect.position + Vector2(10, 24) + (map_size - bounds.size * scale) * 0.5 - bounds.position * scale
	for room: Dictionary in rooms:
		var drawn := Rect2(origin + (room.bounds as Rect2).position * scale, (room.bounds as Rect2).size * scale)
		MathArt.px_rect(self, drawn, MathArt.BG_2)
		MathArt.line(self, drawn.position, Vector2(drawn.end.x, drawn.position.y), MathArt.LIGHT_DIM, 1)
		MathArt.line(self, Vector2(drawn.position.x, drawn.end.y), drawn.end, MathArt.LIGHT_DIM, 1)
	for marker: Dictionary in snapshot.get("markers", []):
		MathArt.poly(self, MathArt.ngon(4, 2.5, 0, origin + (marker.pos as Vector2) * scale), MathArt.LIGHT_DIM)
	MathArt.px_rect(self, Rect2(origin + (snapshot.player as Vector2) * scale - Vector2(2, 2), Vector2(4, 4)), MathArt.PLAYER)


func _draw_timer(font: Font, size: Vector2) -> void:
	var plate := Rect2(size.x - 104.0, size.y - 66.0, 88.0, 20.0)
	MathArt.px_rect(self, plate, BG)
	var total := int(Game.run_time)
	draw_string(font, Vector2(plate.position.x + 6.0, plate.position.y + 15.0),
		"%02d:%02d" % [total / 60, total % 60],
		HORIZONTAL_ALIGNMENT_RIGHT, 76.0, 11, FG)


## Three axis levels sit on one baseline above the HP plate. The emblem carries
## the axis name; the full label and bonuses live in pause.
func _draw_axes(font: Font) -> void:
	var build := Game.build
	if build == null:
		return
	var i := 0
	for axis in build.attributes.keys():
		var x := 24.0 + i * 64.0
		MathArt.ui_axis(self, Vector2(x, AXES_BASELINE - 8.0), str(axis), 6.0)
		_text(font, Vector2(x + 11.0, AXES_BASELINE), str(int(build.attributes[axis])), MathArt.axis_color(str(axis)), 13)
		i += 1


func equipment_rects() -> Array[Rect2]:
	# GEAR ONLY, five elements: two weapons, two skills, then the passive charm.
	# The flask is a separate plate and never an index in this array. The two
	# gaps keep the weapon pair, skill pair and charm reading as groups.
	var rects: Array[Rect2] = [
		Rect2(66, 362, 56, 56),
		Rect2(124, 362, 56, 56),
		Rect2(190, 362, 56, 56),
		Rect2(248, 362, 56, 56),
		Rect2(314, 362, 36, 56),
	]
	return rects


func gear_status(slot: int) -> Dictionary:
	var build := Game.build
	var item := build.slots[slot]
	# display_stats owns the canonical capacity. Skills/shields expose their real
	# charge count; an amulet has none and must never inherit the item default of
	# one charge. Melee carries a canonical one, but the combat card gates charge
	# UI by action, so it is never drawn.
	var cap := int(build.display_stats(item).get("capacity", 0))
	var cooldown := build.cooldown(item)
	return {"ready":int(item.charges) > 0, "charges":int(item.charges), "capacity":cap,
		"recharge":1.0 if int(item.charges) >= cap else 1.0 - clampf(float(item.cooldown) / maxf(cooldown, 0.001), 0, 1)}


func _draw_build(font: Font, size: Vector2) -> void:
	if Game.build != null:
		var build := Game.build
		var main := _flow_owner()
		var screen: Variant = main.get("build_screen") if main != null else null
		var rects := equipment_rects()
		for i in mini(build.slots.size(), rects.size()):
			_draw_run_slot(build, i, rects[i], screen)
		return
	if Game.reward_counts.is_empty():
		return
	var parts: Array[String] = []
	for id in Game.reward_counts:
		var count := int(Game.reward_counts[id])
		var reward_cfg: Dictionary = Data.rewards.get(str(id), {})
		var reward_name: String = ContentText.name("reward", str(id), str(reward_cfg.get("name", id)))
		parts.append(ContentText.of("UI_HUD_REWARD_STACK", "{name} ×{count}").format({"name": reward_name, "count": count}) if count > 1 else reward_name)
	var plate := Rect2(size.x - MARGIN - 296.0, size.y - 58.0, 296.0, 20.0)
	_plate(plate)
	draw_string(font, Vector2(plate.position.x + 8.0, plate.position.y + 15.0),
		ContentText.of("UI_HUD_BUILD_LINE", "BUILD  {items}").format({"items": " · ".join(parts)}),
		HORIZONTAL_ALIGNMENT_RIGHT, 280.0, 11, DIM)


## One combat slot: the real action prompt and icon are primary. Charge marks
## and remaining seconds appear only where the item actually has charges;
## melee and the charm stay quiet rather than faking READY or 1/1.
func _draw_run_slot(build: RunBuild, slot: int, rect: Rect2, screen: Variant) -> void:
	var item := build.slots[slot]
	var cfg := build.definition(item)
	_plate(rect)
	if item.is_empty() or cfg.is_empty():
		MathArt.ui_text(self, rect.position + Vector2(0, 33), ContentText.of("UI_STAT_EMPTY", "Empty"), 11, DIM2, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var action := str(cfg.get("action", "amulet"))
	var kind := str(cfg.get("kind", ""))
	var capacity := int(build.display_stats(item).get("capacity", 0))
	var charges := int(item.charges)
	var ready := charges > 0
	var tint: Color = MathArt.axis_color(str(cfg.get("attribute", "survival"))) if ready else DIM2
	var prompt := ""
	if slot < 4 and is_instance_valid(screen):
		prompt = str(screen.slot_key(slot))
	var timer := ""
	if charges < capacity:
		timer = "%.1fs" % maxf(0.0, float(item.get("cooldown", 0.0)))
	var font := MathArt.ui_font()
	var key_width := 0.0
	if not prompt.is_empty():
		key_width = font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var timer_width := 0.0
	if not timer.is_empty():
		timer_width = font.get_string_size(timer, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var top_timer_width := maxf(timer_width, 24.0)
	# The real binding owns the top line. A long binding pushes the timer to
	# its own bottom-right baseline rather than shortening or overlapping it.
	var timer_below := not timer.is_empty() and key_width + top_timer_width + 12.0 > rect.size.x
	if not prompt.is_empty():
		MathArt.ui_text(self, rect.position + Vector2(4, 12), prompt, 11, FG_HI, rect.size.x - 8)
	var center := rect.position + Vector2(rect.size.x * 0.5, 29.0)
	MathArt.ui_gear(self, center, action, 11.0 if slot == 4 else 12.0, tint, str(item.get("id", "")))
	var shows_charge := kind == "skill" or action == "shield"
	if not shows_charge:
		return
	if not timer.is_empty():
		if timer_below:
			var timer_region := maxf(timer_width, 20.0)
			MathArt.ui_text(self, Vector2(rect.end.x - 4.0 - timer_region, rect.end.y - 2.0), timer, 11, FG, timer_region, HORIZONTAL_ALIGNMENT_RIGHT)
		else:
			MathArt.ui_text(self, Vector2(rect.end.x - 4.0 - top_timer_width, rect.position.y + 12.0), timer, 11, FG, top_timer_width, HORIZONTAL_ALIGNMENT_RIGHT)
	if capacity <= 0:
		return
	var gap := 8.0 if capacity <= 2 else 6.0
	var total_width := (capacity - 1) * gap + 5.0
	var start_x := rect.position.x + 4.0 if timer_below else rect.get_center().x - total_width * 0.5
	for n in capacity:
		MathArt.px_rect(self, Rect2(start_x + n * gap, rect.end.y - 6.0, 5, 4), tint if n < charges else MathArt.STONE_DIM)


## The flask is its own survival plate, outside equipment_rects(). It shows the
## real remaining/capacity pair, not a cooldown ring or a charge glyph.
func _draw_flask(_font: Font) -> void:
	var rect := FLASK_RECT
	var ready := Game.flask_charges > 0
	var tone := MathArt.HEAL if ready else DIM2
	_plate(rect)
	MathArt.ui_text(self, rect.position + Vector2(3, 12), _prompt(&"heal"), 11, FG_HI if ready else DIM2, rect.size.x - 6)
	var p := rect.position
	MathArt.poly(self, PackedVector2Array([p + Vector2(12, 18), p + Vector2(24, 18), p + Vector2(24, 27), p + Vector2(31, 36), p + Vector2(29, 47), p + Vector2(13, 47), p + Vector2(11, 36), p + Vector2(18, 27)]), Color.TRANSPARENT, tone, 1.5)
	MathArt.ui_text(self, Vector2(rect.position.x, rect.position.y + 52), "%d/%d" % [Game.flask_charges, Game.flask_capacity], 11, tone, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_hints(font: Font, size: Vector2) -> void:
	# A real run has no permanent bottom strip: the fight owns that edge, and the
	# same keys live in the pause page's detail column. The hub and the legacy
	# arena path keep theirs.
	if Game.build != null and (not Game.run_node_id.is_empty() or Game.floor_index > 0):
		return
	var hints := ContentText.of("UI_HUD_HINTS_RUN", "{move} Move · {jump} Jump · {attack} Attack · {skills} Skills · {roll} Roll · {pause} Pause").format(_prompt_values())
	if _in_hub():
		hints = ContentText.of("UI_HUD_HINTS_HUB", "{move} Move · {jump} Jump · {interact} Interact · {pause} Pause").format(_prompt_values())
	MathArt.px_rect(self, Rect2(0, size.y - 16, size.x, 16), Color(BG, 0.72))
	MathArt.ui_text(self, Vector2(16, size.y - 4), hints, 11, MathArt.LIGHT_DIM)





## Localized prefix plus the untouched diagnostic: a save failure must stay
## actionable in zh_TW and still expose the original cause to the validator.
static func save_failed_display(reason: String) -> String:
	return ContentText.of("UI_ERR_SAVE_FAILED", "Save failed") + ": " + reason


## Profile.slot_summary().label keeps its machine value; this is the title-page
## rendering of it. Blocked and damaged labels stay raw behind a stable row.
## Readable saves also carry a route node id, so the checkpoint name is a
## content name rather than an English fragment parsed out of the label.
static func slot_label(summary: Dictionary) -> String:
	var label := str(summary.get("label", ""))
	if summary.get("blocked", false):
		return ContentText.machine(label)
	if label in ["EMPTY", "UNAVAILABLE", "CANNOT READ SAVE", "CHECKPOINT NEEDS RECOVERY"]:
		return ContentText.machine(label)
	var node_id := str(summary.get("checkpoint_node_id", ""))
	var kind := str(summary.get("checkpoint_kind", ""))
	if not node_id.is_empty() and kind in ["passage", "biome_entry"]:
		var route := ContentText.name("biome", node_id, str(Data.route_graph.nodes.get(node_id, {}).get("name", "")))
		if kind == "passage":
			return ContentText.of("UI_SLOT_AT_PASSAGE", "{route} / Passage").format({"route": route})
		return ContentText.of("UI_SLOT_AT_ENTRANCE", "{route} / Entrance").format({"route": route})
	if label.begins_with("HUB / ") and label.ends_with(" VICTORIES"):
		var wins: Variant = summary.get("victories", label.trim_prefix("HUB / ").trim_suffix(" VICTORIES"))
		return ContentText.of("UI_SLOT_HUB_VICTORIES", "Hub / {wins} victories").format({"wins": str(wins)})
	return ContentText.machine(label)


func _draw_announce(_font: Font, size: Vector2) -> void:
	if Game.announce_text.is_empty() or Game.announce_t <= 0.0:
		return
	var elapsed := Game.announce_max - Game.announce_t
	var alpha := clampf(elapsed / 0.14, 0.0, 1.0) * clampf(Game.announce_t / 0.26, 0.0, 1.0)
	# Producers localize with ContentText; the HUD owns only wrapping and the
	# severity plate, never a second English parser of announce payloads.
	var lines := MathArt.ui_wrap(Game.announce_text, size.x - 128, 24)
	var line_h := MathArt.ui_line_height(24)
	var y := size.y * 0.30
	if Game.announce_kind == &"error":
		MathArt.px_rect(self, Rect2(48, y - 28, size.x - 96, lines.size() * line_h + 16), Color(MathArt.INK, alpha * 0.94))
	for i in lines.size():
		MathArt.ui_text(self, Vector2(64, y + i * line_h), lines[i], 24, Color(FG, alpha), size.x - 128, HORIZONTAL_ALIGNMENT_CENTER)
	y += (lines.size() - 1) * line_h
	MathArt.px_rect(self, Rect2(size.x * 0.5 - 50.0, y + 6.0, 100, 1), Color(FG_HI, alpha * 0.8))
	if Game.hub_return_in > 0.05:
		MathArt.ui_text(self, Vector2(64, y + 26), ContentText.of("UI_HUD_RETURNING_HUB", "Returning to the Hub in {seconds}s").format({"seconds": "%.1f" % Game.hub_return_in}), 11, Color(DIM, alpha), size.x - 128, HORIZONTAL_ALIGNMENT_CENTER)


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
	var tint := Color(MathArt.DANGER, alpha)
	MathArt.px_rect(self, Rect2(0, 0, size.x, 2), tint)
	MathArt.px_rect(self, Rect2(0, size.y - 2, size.x, 2), tint)
	MathArt.px_rect(self, Rect2(0, 0, 2, size.y), tint)
	MathArt.px_rect(self, Rect2(size.x - 2, 0, 2, size.y), tint)


func _draw_hurt_flash(size: Vector2) -> void:
	if Game.hurt_flash <= 0.0:
		return
	var alpha := clampf(Game.hurt_flash / 0.32, 0.0, 1.0)
	MathArt.px_rect(self, Rect2(0, 0, size.x, size.y), Color(MathArt.DANGER, alpha * 0.10))
	MathArt.px_rect(self, Rect2(0, 0, size.x, 2), Color(MathArt.DANGER, alpha * 0.75))
	MathArt.px_rect(self, Rect2(0, size.y - 2, size.x, 2), Color(MathArt.DANGER, alpha * 0.75))


func _draw_pause(_font: Font, _size: Vector2) -> void:
	# 82% ink: the frozen floor stays legible as context, but the single page is
	# the only surface asking to be read.
	MathArt.px_rect(self, Rect2(0, 0, 768, 480), Color(MathArt.INK, 0.82))
	MathArt.ui_panel(self, MathArt.UI_PAGE)
	var heading := ContentText.of("UI_HUD_PAUSE_TITLE_ABANDON", "Abandon this run?") if _abandon_confirm else (ContentText.of("UI_HUD_PAUSE_TITLE_BLOCKED", "Checkpoint not saved") if checkpoint_blocked else ContentText.of("UI_HUD_PAUSE_TITLE", "Build & pause"))
	MathArt.ui_heading(self, heading, ContentText.of("UI_HUD_PAUSE_CONTEXT", "This run / paused"))
	if _abandon_confirm:
		MathArt.ui_text(self, Vector2(52, 140), ContentText.of("UI_HUD_ABANDON_ASK", "Return to the Hub. This run ends."), 16, MathArt.WHITE)
		MathArt.ui_surface(self, Rect2(52, 166, 326, 144), true)
		MathArt.ui_surface(self, Rect2(390, 166, 326, 144))
		MathArt.ui_text(self, Vector2(68, 195), ContentText.of("UI_HUD_LOSE_RUN", "LOSE THIS RUN"), 16, MathArt.DANGER)
		MathArt.ui_text(self, Vector2(406, 195), ContentText.of("UI_HUD_KEEP_PROGRESS", "KEEP SAVED PROGRESS"), 16, MathArt.PALE)
		var lose := MathArt.ui_wrap(ContentText.of("UI_HUD_LOSE_DETAIL", "Carried Cells, Gold, equipment, Scrolls and carried blueprints."), 294, 13)
		for i in lose.size(): MathArt.ui_text(self, Vector2(68, 226 + i * 20), lose[i], 13)
		var keep := MathArt.ui_wrap(ContentText.of("UI_HUD_KEEP_DETAIL", "Saved unlocks, investments, Runes and banked Cells."), 294, 13)
		for i in keep.size(): MathArt.ui_text(self, Vector2(406, 226 + i * 20), keep[i], 13, MathArt.WHITE)
		MathArt.ui_text(self, Vector2(52, 334), ContentText.of("UI_HUD_CHECKPOINT_NOTE", "Your checkpoint clears only after the result is safely saved."), 13)
		MathArt.ui_key(self, Vector2(52, 428), _prompt(&"ui_accept"), ContentText.of("UI_HUD_KEY_ABANDON_RUN", "Abandon run"))
		MathArt.ui_key(self, Vector2(608, 428), _prompt(&"ui_back"), ContentText.of("UI_HUD_KEY_BACK", "Back"))
		return
	var main := _flow_owner()
	var screen: Variant = main.get("build_screen") if main != null else null
	_pause_action = clampi(_pause_action, 0, _pause_action_count() - 1)
	_pause_line_count = 0
	if Game.build != null and is_instance_valid(screen):
		var build := Game.build
		# Two weapons, two skills, one passive: the category is the grouping, so
		# the five rows stop reading as five interchangeable lines.
		var rects: Array[Rect2] = [Rect2(52, 128, 112, 62), Rect2(176, 128, 112, 62), Rect2(52, 212, 112, 62), Rect2(176, 212, 112, 62), Rect2(52, 294, 236, 38)]
		var labels := [ContentText.of("UI_HUD_SLOT_WEAPONS", "WEAPONS"), ContentText.of("UI_HUD_SLOT_WEAPONS", "WEAPONS"), ContentText.of("UI_HUD_SLOT_SKILLS", "SKILLS"), ContentText.of("UI_HUD_SLOT_SKILLS", "SKILLS"), ContentText.of("UI_HUD_SLOT_PASSIVE", "PASSIVE")]
		for i in build.slots.size():
			var rect: Rect2 = rects[i]
			var cfg := build.definition(build.slots[i])
			if i in [0, 2, 4]:
				MathArt.ui_text(self, Vector2(rect.position.x, rect.position.y - 8), labels[i], 11, MathArt.LIGHT_DIM)
			if i == _pause_index:
				MathArt.ui_focus(self, rect)
			var tint := MathArt.WHITE if i == _pause_index else MathArt.axis_color(str(cfg.get("attribute", "survival")))
			MathArt.ui_gear(self, rect.position + (Vector2(24, 26) if i < 4 else Vector2(24, 19)), str(cfg.get("action", "amulet")), 18 if i < 4 else 13, tint, str(build.slots[i].id))
			var name_width := 60.0 if i < 4 else 184.0
			var gear_name := ContentText.name("gear", str(build.slots[i].id), str(cfg.name))
			var slot_tag: String = screen.slot_key(i)
			var names := MathArt.ui_wrap(ContentText.of("UI_HUD_SLOT_LABEL", "[{key}] {name}").format({"key": slot_tag, "name": gear_name}), name_width, 11)
			var origin := rect.position + (Vector2(48, 24) if i < 4 else Vector2(48, 15))
			for n in mini(2, names.size()):
				MathArt.ui_text(self, origin + Vector2(0, n * MathArt.ui_line_height(11)), names[n], 11, MathArt.WHITE if i == _pause_index else MathArt.PALE, name_width)
		MathArt.line(self, Vector2(310, 112), Vector2(310, 332), MathArt.STONE, 1)
		var selected := build.slots[_pause_index]
		var selected_cfg := build.definition(selected)
		MathArt.ui_gear(self, Vector2(354, 150), str(selected_cfg.get("action", "amulet")), 25, MathArt.axis_color(str(selected_cfg.get("attribute", "survival"))), str(selected.id))
		var description := GearPresentation.describe(build, selected)
		var selected_name := str(description.get("name", ""))
		var title := MathArt.ui_wrap(selected_name, 304, 16)
		for i in mini(2, title.size()): MathArt.ui_text(self, Vector2(402, 135 + i * MathArt.ui_line_height(16)), MathArt.ui_short(title[i] + ("…" if i == 1 and title.size() > 2 else ""), 304, 16), 16, MathArt.WHITE)
		var lines: Array[String] = []
		if checkpoint_blocked:
			var blocked := ContentText.of("UI_HUD_PAUSE_SAVE_FAILED_BODY", "Save failed: {reason}\n{accept} retries this checkpoint. Play stays paused.").format({"reason": Profile.last_save_error, "accept": _prompt(&"ui_accept")})
			blocked += "\n" + ContentText.of("UI_HUD_PAUSE_BLOCKED_BOUNDARY", "Restoring the previous checkpoint discards this run's newer progress.")
			lines.append_array(MathArt.ui_wrap(blocked, 378, 13))
		else:
			# Readability comes first: how the item plays and when it crits, then
			# the complete mechanics. The presenter owns the canonical numbers and
			# already puts the full name once at the front of details.
			_append_detail(lines, str(description.get("playstyle", "")), 378)
			_append_detail(lines, str(description.get("condition", "")), 378)
			_append_detail(lines, str(description.get("headline", "")), 378)
			var details: Array = description.get("details", [])
			var skip_name := title.size() <= 2 and not details.is_empty() and str(details[0]) == selected_name
			for d in details.size():
				if d == 0 and skip_name:
					continue
				_append_detail(lines, str(details[d]), 378)
		_pause_line_count = lines.size()
		_pause_scroll = clampi(_pause_scroll, 0, maxi(0, _pause_line_count - PAUSE_DETAIL_ROWS))
		var row_height := MathArt.ui_line_height(13)
		var first := PAUSE_DETAIL_RECT.position.y + 15.0
		for n in range(_pause_scroll, mini(lines.size(), _pause_scroll + PAUSE_DETAIL_ROWS)):
			MathArt.ui_text(self, Vector2(PAUSE_DETAIL_RECT.position.x, first + (n - _pause_scroll) * row_height), lines[n], 13)
		if lines.size() > PAUSE_DETAIL_ROWS:
			var track := Rect2(PAUSE_DETAIL_RECT.end.x - 3.0, PAUSE_DETAIL_RECT.position.y + 4.0, 1.0, PAUSE_DETAIL_RECT.size.y - 8.0)
			MathArt.px_rect(self, track, Color(MathArt.STONE, 0.5))
			var thumb_height := maxf(18.0, track.size.y * float(PAUSE_DETAIL_ROWS) / float(lines.size()))
			var max_scroll := maxi(1, lines.size() - PAUSE_DETAIL_ROWS)
			var thumb_y := track.position.y + (track.size.y - thumb_height) * float(_pause_scroll) / float(max_scroll)
			MathArt.px_rect(self, Rect2(track.position.x - 0.25, thumb_y, 1.5, thumb_height), MathArt.STONE_HI)
	# Save state stays above the action row, never under it: a blocked
	# checkpoint must read before the actions that are still reachable.
	var info_pitch := MathArt.ui_line_height(11)
	var note := ContentText.of("UI_HUD_SAVE_LINE_HUB", "Save {slot} · Hub progress saved").format({"slot": Profile.active_slot})
	if checkpoint_blocked:
		note = ContentText.of("UI_HUD_SAVE_LINE_NOT_SAVED", "Not saved · {accept} retry · {tabs} previous checkpoint").format({"accept": _prompt(&"ui_accept"), "tabs": _prompt(&"ui_tab_prev")})
	elif not Profile.run_checkpoint.is_empty():
		var place := ContentText.of("UI_HUD_PLACE_PASSAGE", "this Passage") if Profile.run_checkpoint.kind == "passage" else ContentText.of("UI_HUD_PLACE_ENTRANCE", "the biome entrance")
		note = ContentText.of("UI_HUD_SAVE_LINE_CHECKPOINT", "Save {slot} · Restores at {place}. Newer combat progress is not saved.").format({"slot": Profile.active_slot, "place": place})
	MathArt.ui_text(self, Vector2(52, 334), MathArt.ui_short(note, 664, 11), 11)
	if Game.build != null and is_instance_valid(screen):
		var build := Game.build
		MathArt.ui_text(self, Vector2(52, 334.0 + info_pitch), ContentText.of("UI_HUD_PAUSE_WALLET", "{gold} Gold · {blueprints} blueprints").format({"gold": build.gold, "blueprints": Game.carried_blueprints.size()}), 11)
		for i in 3:
			var axis: String = build.attributes.keys()[i]
			var at := Vector2(340 + i * 128, 334.0 + info_pitch - 6.0)
			MathArt.ui_axis(self, at, axis, 6)
			MathArt.ui_text(self, at + Vector2(12, 6), ContentText.of("UI_HUD_AXIS_VALUE", "{axis} {value}").format({"axis": axis_name(axis), "value": build.attributes[axis]}), 11, MathArt.axis_color(axis))
		var mutations := ContentText.of("UI_HUD_MUTATIONS", "Mutations {chosen} / {capacity} · {names}").format({"chosen": build.mutations.size(), "capacity": build.mutation_capacity, "names": _mutation_names(build.mutations)})
		MathArt.ui_text(self, Vector2(52, 334.0 + info_pitch * 2.0), MathArt.ui_short(mutations, 664, 11), 11)
	_draw_pause_actions()
	MathArt.ui_text(self, Vector2(52, 414), _pause_focus_hint(), 11, MathArt.LIGHT_DIM, 664)
	MathArt.ui_text(self, Vector2(52, 430), ContentText.of("UI_HUD_PAUSE_SHORTCUTS", "{tabs} Save slots · Q Quit").format({"tabs": _prompt(&"ui_tab_prev")}), 11, DIM2)


func _append_detail(lines: Array[String], value: String, width: float) -> void:
	var trimmed := value.strip_edges()
	if trimmed.is_empty():
		return
	lines.append_array(MathArt.ui_wrap(trimmed, width, 13))


## Durable action row: five fixed cells in the normal run, four in the blocked
## state. Focus is drawn with the same short-edge/track surface as the title.
func _draw_pause_actions() -> void:
	var ids := _pause_action_ids()
	var row_focused := _pause_focus_mode() == PAUSE_FOCUS_ACTIONS
	for i in ids.size():
		var rect := pause_action_rect(i)
		var focused := row_focused and i == _pause_action
		MathArt.ui_surface(self, rect, focused, true)
		var label := _pause_action_label(str(ids[i]))
		MathArt.ui_text(self, rect.position + Vector2(6, 18), label, 13, MathArt.WHITE if focused else MathArt.PALE, rect.size.x - 12.0, HORIZONTAL_ALIGNMENT_CENTER)


func _mutation_names(mutations: Array) -> String:
	if mutations.is_empty():
		return ContentText.of("UI_HUD_NONE_CHOSEN", "None chosen")
	var names: Array[String] = []
	for id in mutations:
		var cfg: Dictionary = Data.passage.get("mutations", {}).get(str(id), {})
		names.append(ContentText.name("mutation", str(id), str(cfg.get("name", id))))
	return ", ".join(names)


func _draw_run_over(_font: Font, _size: Vector2) -> void:
	MathArt.px_rect(self, Rect2(0, 0, 768, 480), Color(MathArt.INK, 0.97))
	MathArt.ui_panel(self, MathArt.UI_PAGE)
	var pending := not Game.settlement_pending.is_empty()
	var abandoned := pending and not bool(Game.settlement_pending.died)
	var title := ContentText.of("UI_HUD_RUN_ABANDONED", "Run abandoned") if abandoned else (ContentText.of("UI_HUD_ROUTE_SLICE", "Route slice complete") if Game.slice_complete else (ContentText.of("UI_HUD_ASHFALL_COMPLETE", "Ashfall complete") if Game.victory and not Game.run_node_id.is_empty() else (ContentText.of("UI_HUD_FLOOR_CLEARED", "Floor cleared") if Game.victory else ContentText.of("UI_HUD_YOU_DIED", "You died"))))
	var at := Vector2(384, 116)
	MathArt.ui_service(self, at, "abandon" if abandoned else ("victory" if Game.victory else "death"), 32)
	MathArt.ui_text(self, Vector2(52, 188), title, 24, MathArt.ACCENT if Game.victory else MathArt.PALE, 664, HORIZONTAL_ALIGNMENT_CENTER)
	MathArt.ui_text(self, Vector2(52, 218), ContentText.of("UI_HUD_RESULT_NOT_SAVED", "Result not saved") if pending else (ContentText.of("UI_HUD_VICTORY_SAVED", "Victory saved") if Game.victory else ContentText.of("UI_HUD_RUN_ENDED_SAVED", "Run ended · result saved")), 13, MathArt.PALE, 664, HORIZONTAL_ALIGNMENT_CENTER)
	var total := int(Game.run_time)
	var values := [str(Game.kills), "x%d" % Game.max_combo, str(Game.perfect_dodges), "%02d:%02d" % [total / 60, total % 60]]
	var labels := [ContentText.of("UI_HUD_STAT_KILLS", "Kills"), ContentText.of("UI_HUD_STAT_BEST_COMBO", "Best combo"), ContentText.of("UI_HUD_STAT_PERFECT_DODGES", "Perfect dodges"), ContentText.of("UI_HUD_STAT_TIME", "Time")]
	for i in 4:
		var x := 52.0 + i * 166
		MathArt.ui_text(self, Vector2(x, 277), values[i], 24, MathArt.WHITE, 166, HORIZONTAL_ALIGNMENT_CENTER)
		MathArt.ui_text(self, Vector2(x, 299), labels[i], 11, MathArt.PALE, 166, HORIZONTAL_ALIGNMENT_CENTER)
	MathArt.line(self, Vector2(52, 320), Vector2(716, 320), MathArt.STONE, 1)
	var message := ContentText.of("UI_HUD_KEPT_MESSAGE", "Permanent unlocks, investments and banked Cells are kept.")
	if pending:
		message = ContentText.of("UI_HUD_SAVE_FAILED_RESULT", "Save failed: {reason}\nYour previous checkpoint is protected. {accept} retries this result.").format({"reason": Profile.last_save_error, "accept": _prompt(&"ui_accept")})
	elif Game.victory and not Game.run_node_id.is_empty():
		message = ContentText.of("UI_HUD_VICTORY_MESSAGE", "Victory rewards and remaining Cells saved. BSC 1 unlocked.")
	elif not Game.victory:
		message = ContentText.of("UI_HUD_DIED_MESSAGE", "Permanent unlocks, investments and banked Cells are kept.\nCarried Cells, Gold, equipment and blueprints are lost.")
	var lines := MathArt.ui_wrap(message, 664, 13)
	for i in mini(3, lines.size()): MathArt.ui_text(self, Vector2(52, 348 + i * 20), lines[i], 13, MathArt.WHITE if pending else MathArt.PALE)
	if Game.hub_return_in > 0.05:
		MathArt.ui_text(self, Vector2(52, 408), ContentText.of("UI_HUD_RETURNING_HUB", "Returning to the Hub in {seconds}s").format({"seconds": "%.1f" % Game.hub_return_in}), 11)
	MathArt.ui_key(self, Vector2(52, 428), _prompt(&"ui_accept"), ContentText.of("UI_HUD_KEY_RETRY_SAVE", "Retry save") if pending else ContentText.of("UI_HUD_KEY_RETURN_START", "Return to start"))
	MathArt.ui_key(self, Vector2(642, 428), _prompt(&"ui_tab_next"), ContentText.of("UI_HUD_KEY_QUIT", "Quit"))
