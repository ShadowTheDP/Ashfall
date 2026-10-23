extends Node
## Run state, score, combo tracking, rewards and input setup.
##
## shortcut: input actions are registered at runtime instead of project.godot so
## the prototype has no serialized InputEvent blobs. When a settings screen or
## controller remapping lands, move them into project.godot and delete
## `_setup_input`.

signal rewards_requested(choices: Array)
signal floor_started(index: int, floor_name: String)
signal floor_cleared(index: int)
signal run_ended(victory: bool)

const COMBO_WINDOW := 1.6
const PERFECT_DODGE_TIME := 2.5
const PERFECT_DODGE_MULT := 1.25

var player: Player = null
var fx_root: Node = null
var screen_fx_root: Node = null

var cells := 0
var kills := 0
var combo := 0
var combo_time := 0.0
var combo_pop := 0.0
var max_combo := 0
var perfect_dodges := 0

var wave := 0
var wave_total := 0
var enemies_left := 0

var run_time := 0.0
var run_over := false
var victory := false

var announce_text := ""
var announce_t := 0.0
var announce_max := 1.0

# Build state
var damage_mult := 1.0
var edge_timer := 0.0
var leech := 0
var reward_counts: Dictionary = {}
var reward_open := false
var auto_choose_rewards := false

# Boss
var boss: Enemy = null
var boss_defeated := false

# --- Meta progression -------------------------------------------------------
# floor_index is 1-based while inside a floor and 0 while in the hub.
var floor_index := 0
var floor_name := ""
var run_cells := 0          # unbanked; lost on death
var in_hub := true
var run_kills := 0

# Presentation
var hurt_flash := 0.0


func _enter_tree() -> void:
	_setup_input()


func _process(delta: float) -> void:
	if not run_over:
		run_time += delta
	combo_pop = maxf(0.0, combo_pop - delta * 4.0)
	announce_t = maxf(0.0, announce_t - delta)
	edge_timer = maxf(0.0, edge_timer - delta)
	hurt_flash = maxf(0.0, hurt_flash - delta)
	if combo_time > 0.0:
		combo_time -= delta
		if combo_time <= 0.0:
			combo = 0


func reset_run() -> void:
	cells = 0
	kills = 0
	combo = 0
	combo_time = 0.0
	combo_pop = 0.0
	max_combo = 0
	perfect_dodges = 0
	wave = 0
	wave_total = 0
	enemies_left = 0
	run_time = 0.0
	run_over = false
	victory = false
	announce_text = ""
	announce_t = 0.0
	announce_max = 1.0
	damage_mult = 1.0
	edge_timer = 0.0
	leech = 0
	reward_counts.clear()
	reward_open = false
	auto_choose_rewards = false
	boss = null
	boss_defeated = false
	hurt_flash = 0.0
	floor_index = 0
	floor_name = ""
	run_cells = 0
	in_hub = true
	run_kills = 0
	player = null
	Engine.time_scale = 1.0
	get_tree().paused = false


func combo_hit() -> void:
	combo += 1
	combo_time = COMBO_WINDOW
	combo_pop = 1.0
	max_combo = maxi(max_combo, combo)


func combo_break() -> void:
	combo = 0
	combo_time = 0.0


func add_cells(amount: int) -> void:
	# Permanent GREED upgrades and the hub bank both read this counter, so the
	# multiplier is applied once here rather than at every drop site.
	var scaled := int(roundf(float(amount) * (1.0 + Profile.bonus("cells"))))
	cells += scaled
	if not in_hub:
		run_cells += scaled


func add_kill() -> void:
	kills += 1
	run_kills += 1
	if leech > 0 and player != null:
		player.hp = minf(player.max_hp, player.hp + float(leech))


func announce(text: String, duration: float = 1.3) -> void:
	announce_text = text
	announce_t = duration
	announce_max = duration


func end_run(did_win: bool) -> void:
	if run_over:
		return
	run_over = true
	victory = did_win
	announce_t = 0.0
	Sfx.play("wave" if did_win else "death", -4.0)
	Profile.note_run(run_kills, not did_win, did_win)
	# Dying forfeits whatever was still in the run; winning banks it all.
	if did_win:
		Profile.bank(run_cells)
		Profile.add_souls(1)
	run_ended.emit(did_win)


# --- Floor flow -------------------------------------------------------------

func start_floor(index: int) -> void:
	floor_index = maxi(1, index)
	in_hub = false
	run_cells = 0
	run_over = false
	victory = false
	run_kills = 0
	Profile.note_floor_reached(floor_index)
	floor_started.emit(floor_index, floor_name)


func finish_floor() -> void:
	# Clearing a floor banks the run's cells immediately, so the hub always has
	# something to spend even if the player dies on the next floor.
	Profile.bank(run_cells)
	run_cells = 0
	floor_cleared.emit(floor_index)


func go_to_hub() -> void:
	in_hub = true
	floor_index = 0
	run_cells = 0


func max_floor() -> int:
	return Data.floors.size()


# --- Combat multipliers -----------------------------------------------------

func total_damage_mult() -> float:
	var mult := damage_mult
	if edge_timer > 0.0:
		mult *= PERFECT_DODGE_MULT
	return mult


func perfect_dodge() -> void:
	# The DANCER passive doubles the window and lets it stack twice, so a good
	# dodge chain keeps the buff alive instead of merely refreshing it.
	var scale := 1.0
	if is_instance_valid(player):
		scale = player.perfect_dodge_scale
	var gained := PERFECT_DODGE_TIME * scale
	var cap := PERFECT_DODGE_TIME * scale * (2.0 if scale > 1.5 else 1.0)
	edge_timer = minf(cap, edge_timer + gained)
	perfect_dodges += 1
	if player != null:
		player.refund_knife()
		var at := player.global_position + Vector2(0, -8)
		Combat.dodge_burst(at)
		Juice.dodge(Game.fx_root, at)
	Combat.shake(0.14)
	# A 2-frame freeze sells the read without a screen flash.
	Combat.hitstop(0.033)
	Sfx.play("dodge", -5)
	announce("PERFECT DODGE", 0.6)


# --- Rewards ----------------------------------------------------------------

func request_rewards(count: int = 3) -> void:
	var ids: Array = Data.rewards.keys()
	ids.shuffle()
	var choices: Array = ids.slice(0, mini(count, ids.size()))
	reward_open = true
	rewards_requested.emit(choices)


func apply_reward(id: String) -> void:
	var data: Dictionary = Data.rewards.get(id, {})
	if data.is_empty():
		push_error("Unknown reward: " + id)
		return
	match id:
		"vitality":
			if player != null:
				player.max_hp += 20.0
				player.heal(20.0)
		"edge":
			damage_mult += 0.12
		"swift":
			if player != null:
				player.max_speed *= 1.08
		"ghost":
			# The cap used to be 0.28, which made this boon a no-op for the
			# GLASS character (already 0.32). The cap now sits above every
			# reachable value so the boon always does something.
			if player != null:
				player.roll_iframe_end = minf(0.40, player.roll_iframe_end + 0.03)
		"armory":
			if player != null:
				player.add_knife_max()
		"leech":
			leech += 1
		"hunter":
			if player != null:
				player.crit_bonus += 0.15
	reward_counts[id] = int(reward_counts.get(id, 0)) + 1
	reward_open = false
	Sfx.play("reward", -6)


func grant_random_reward() -> void:
	var ids: Array = Data.rewards.keys()
	if ids.is_empty():
		return
	ids.shuffle()
	apply_reward(ids[0])


func _setup_input() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE, KEY_W, KEY_UP],
		"attack": [KEY_J, KEY_Z],
		"throw": [KEY_K],
		"aegis": [KEY_L],
		"roll": [KEY_SHIFT],
		"pause": [KEY_ESCAPE],
		"restart": [KEY_R],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

	var joy_buttons := {
		"jump": JOY_BUTTON_A,
		"attack": JOY_BUTTON_X,
		"throw": JOY_BUTTON_Y,
		"aegis": JOY_BUTTON_LEFT_SHOULDER,
		"roll": JOY_BUTTON_B,
		"pause": JOY_BUTTON_START,
		"restart": JOY_BUTTON_BACK,
	}
	for action in joy_buttons:
		_joy(action, joy_buttons[action])

	# Keyboard-only guarantee: every action above has a key binding and the
	# game never requires a mouse. Do not add mouse-only actions.


func _joy(action: String, button: int) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)
