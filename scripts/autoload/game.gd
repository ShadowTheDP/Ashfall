extends Node
## Run state, score, combo tracking, rewards and input setup.
##
## shortcut: input actions are registered at runtime instead of project.godot so
## the prototype has no serialized InputEvent blobs. When a settings screen or
## controller remapping lands, move them into project.godot and delete
## `_setup_input`.

signal rewards_requested(choices: Array)

const COMBO_WINDOW := 1.6
const PERFECT_DODGE_TIME := 2.5
const PERFECT_DODGE_MULT := 1.25

var player: Player = null
var fx_root: Node = null

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
	cells += amount


func add_kill() -> void:
	kills += 1
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


# --- Combat multipliers -----------------------------------------------------

func total_damage_mult() -> float:
	var mult := damage_mult
	if edge_timer > 0.0:
		mult *= PERFECT_DODGE_MULT
	return mult


func perfect_dodge() -> void:
	edge_timer = PERFECT_DODGE_TIME
	perfect_dodges += 1
	if player != null:
		player.refund_knife()
		var at := player.global_position + Vector2(0, -8)
		Combat.dodge_burst(at)
		Combat.burst(at, MathArt.WHITE, 10, 190.0)
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
			if player != null:
				player.roll_iframe_end = minf(0.28, player.roll_iframe_end + 0.03)
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
