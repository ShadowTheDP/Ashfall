extends Node
## Run state, score, combo tracking and input setup.
##
## shortcut: input actions are registered at runtime instead of project.godot so
## the prototype has no serialized InputEvent blobs. When a settings screen or
## controller remapping lands, move them into project.godot and delete
## `_setup_input`.

const COMBO_WINDOW := 1.6

var player: Player = null
var fx_root: Node = null

var cells := 0
var kills := 0
var combo := 0
var combo_time := 0.0
var combo_pop := 0.0
var max_combo := 0

var wave := 0
var wave_total := 0
var enemies_left := 0

var run_time := 0.0
var run_over := false
var victory := false

var announce_text := ""
var announce_t := 0.0
var announce_max := 1.0


func _enter_tree() -> void:
	_setup_input()


func _process(delta: float) -> void:
	if not run_over:
		run_time += delta
	combo_pop = maxf(0.0, combo_pop - delta * 4.0)
	announce_t = maxf(0.0, announce_t - delta)
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
	wave = 0
	wave_total = 0
	enemies_left = 0
	run_time = 0.0
	run_over = false
	victory = false
	announce_text = ""
	announce_t = 0.0
	announce_max = 1.0
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


func _setup_input() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE, KEY_W, KEY_UP],
		"attack": [KEY_J, KEY_Z],
		"roll": [KEY_SHIFT, KEY_L],
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
