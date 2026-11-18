extends Node
## Cross-scene presentation service: locale, native InputMap overrides, audio
## bus gains, display mode/vsync, the last meaningful input device, and action
## prompts.
##
## Pages keep their own focus, scroll, confirmation and pause ownership. This
## node only applies the committed/preview presentation dictionary and remembers
## what the player last used; it never consumes an event or runs a page.

signal presentation_changed

const DEFAULT_LOCALE := "zh_TW"
const LOCALES := ["zh_TW", "en"]
const DEVICE_KEYBOARD := &"keyboard"
const DEVICE_GAMEPAD := &"gamepad"

## User-rebindable gameplay actions. These are the keys the former runtime
## setup registered; `jump_explicit` is an internal mirror of `jump` and is
## deliberately absent.
const GAMEPLAY_ACTIONS := [
	&"move_left", &"move_right", &"drop", &"climb_up", &"climb_down",
	&"map", &"jump", &"attack", &"weapon_two", &"throw", &"aegis",
	&"roll", &"pause", &"interact", &"heal", &"restart",
]
## These keep the default left-stick direction and D-pad direction even when
## another gamepad button is stored for the action.
const MOVEMENT_ACTIONS := [
	&"move_left", &"move_right", &"climb_up", &"climb_down", &"drop",
]

const TRIGGER_AXES := [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]

var active_device: StringName = DEVICE_KEYBOARD

var _committed_input: Dictionary = {"keyboard": {}, "gamepad": {}}
## Fresh-crossing hysteresis per physical device+axis. It rearms only inside
## 0.25, so a held axis cannot retake the prompt device or create a new action
## transition after a keyboard press.
var _axis_armed: Dictionary = {}
## Pending transition for the current physical axis event. Several action
## queries may inspect the same event; only the first matching one consumes it.
var _axis_event: Dictionary = {}
var _active_gamepad := -1
## Last applied display state. Native window calls are skipped in headless, but
## the requested state is still tracked so preview/restore stays deterministic.
var _display_initialized := false
var _fullscreen_active := false
## Window geometry captured when entering fullscreen; restored on exit.
var _windowed_rect := Rect2i()


func _ready() -> void:
	## Device observation and disconnect handling must also work while a page
	## owns the tree pause (title, map, settings).
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	## Profile loaded its committed preferences before this autoload became
	## ready, so apply them once here (locale, InputMap, display; audio gains
	## wait for Sfx to create its buses). Sfx reapplies the same dictionary
	## once after creating the buses, still before Sfx becomes ready. This
	## node never re-applies automatically afterwards, so a fixture or page
	## that pins a locale later keeps it until it explicitly applies again.
	apply_preferences(Profile.preferences)


func _input(event: InputEvent) -> void:
	## Never handle the event: the owning page decides what it means.
	_observe(event)


# --- Fixed API --------------------------------------------------------------

## Rebuild the native InputMap from project defaults, then replace only the
## stored per-device overrides. Locale, audio bus gains and display mode/vsync
## are applied from the same presentation dictionary; this node owns their
## presentation side, while Settings still owns the preview/commit transaction.
func apply_preferences(values: Dictionary) -> void:
	var next_locale := _locale_from(values)
	var next_input := _input_from(values)
	var next_audio := _audio_from(values)
	var next_display := _display_from(values)
	## Apply always restores the effective map from project defaults, including
	## cancel/reset flows that reapply an unchanged committed input section.
	## Only a real locale/input change emits, so an audio-only preview does not
	## repaint every page.
	var locale_changed := TranslationServer.get_locale() != next_locale
	var input_changed := next_input != _committed_input
	TranslationServer.set_locale(next_locale)
	_apply_input(next_input)
	_committed_input = next_input
	_apply_audio(next_audio)
	_apply_display(next_display)
	if locale_changed or input_changed:
		presentation_changed.emit()


## True when this event is a fresh press of the action's current effective
## binding. Keys and buttons use the native just-pressed-by-event edge, so the
## binding must be released before a second confirmation. Release, keyboard
## echo, drift and a held axis never count. The event is observed even when an
## earlier node already marked it handled.
func pressed(event: InputEvent, action: StringName) -> bool:
	if event == null:
		return false
	_observe(event)
	if not InputMap.has_action(action):
		return false
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return false
		return Input.is_action_just_pressed_by_event(action, event)
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if not button.pressed:
			return false
		return Input.is_action_just_pressed_by_event(action, event)
	if event is InputEventJoypadMotion:
		return _motion_pressed(action, event as InputEventJoypadMotion)
	return false


## Short neutral label for the current device's effective binding. The caller
## draws the keycap geometry; this never returns a platform-branded glyph.
func prompt(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "—"
	if active_device == DEVICE_GAMEPAD:
		return _gamepad_prompt(action)
	return _keyboard_prompt(action)


# --- Preferences ------------------------------------------------------------

func _locale_from(values: Dictionary) -> String:
	var general: Variant = values.get("general", {})
	if typeof(general) != TYPE_DICTIONARY:
		return DEFAULT_LOCALE
	var locale := str((general as Dictionary).get("locale", DEFAULT_LOCALE))
	return locale if locale in LOCALES else DEFAULT_LOCALE


func _input_from(values: Dictionary) -> Dictionary:
	var out := {"keyboard": {}, "gamepad": {}}
	var input: Variant = values.get("input", {})
	if typeof(input) != TYPE_DICTIONARY:
		return out
	var raw := input as Dictionary
	var keyboard: Variant = raw.get("keyboard", {})
	if typeof(keyboard) == TYPE_DICTIONARY:
		var keys := keyboard as Dictionary
		for action in GAMEPLAY_ACTIONS:
			var name := String(action)
			if not keys.has(name):
				continue
			var code: Variant = keys[name]
			if typeof(code) != TYPE_INT or int(code) <= 0:
				continue
			out["keyboard"][name] = int(code)
	var gamepad: Variant = raw.get("gamepad", {})
	if typeof(gamepad) == TYPE_DICTIONARY:
		var pads := gamepad as Dictionary
		for action in GAMEPLAY_ACTIONS:
			var name := String(action)
			if not pads.has(name):
				continue
			var binding := _gamepad_override(pads[name])
			if not binding.is_empty():
				out["gamepad"][name] = binding
	return out


func _gamepad_override(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var data := value as Dictionary
	var kind := str(data.get("type", ""))
	var index_value: Variant = data.get("index", -1)
	if typeof(index_value) != TYPE_INT:
		return {}
	var index := int(index_value)
	if kind == "button":
		if index < 0 or index >= JOY_BUTTON_MAX:
			return {}
		return {"type": "button", "index": index}
	if kind == "axis":
		## Triggers are positive motion axes. Stick directions stay on their
		## project defaults rather than being duplicated by a stored override.
		if index not in TRIGGER_AXES:
			return {}
		var sign_value: Variant = data.get("sign", 0)
		if typeof(sign_value) != TYPE_INT or int(sign_value) != 1:
			return {}
		return {"type": "axis", "index": index, "sign": 1}
	return {}


## Audio levels are bus gains only; each source keeps its own volume/pitch.
func _audio_from(values: Dictionary) -> Dictionary:
	var fallback := _default_section("audio")
	var raw := _section(values, "audio")
	return {
		"master": _volume(raw.get("master", fallback.get("master", 1.0)), float(fallback.get("master", 1.0))),
		"music": _volume(raw.get("music", fallback.get("music", 1.0)), float(fallback.get("music", 1.0))),
		"sfx": _volume(raw.get("sfx", fallback.get("sfx", 1.0)), float(fallback.get("sfx", 1.0))),
	}


## Display values are normalized here; Settings owns the preview countdown and
## asks this node to apply either the draft or the committed display dictionary.
func _display_from(values: Dictionary) -> Dictionary:
	var fallback := _default_section("display")
	var raw := _section(values, "display")
	var mode := str(raw.get("window_mode", fallback.get("window_mode", "windowed")))
	var fallback_mode := str(fallback.get("window_mode", "windowed"))
	if mode != "windowed" and mode != "fullscreen":
		mode = fallback_mode if fallback_mode in ["windowed", "fullscreen"] else "windowed"
	var vsync_value: Variant = raw.get("vsync", fallback.get("vsync", true))
	var vsync := bool(vsync_value) if typeof(vsync_value) == TYPE_BOOL else true
	return {"window_mode": mode, "vsync": vsync}


func _section(values: Dictionary, name: String) -> Dictionary:
	var value: Variant = values.get(name, {})
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value as Dictionary


func _default_section(name: String) -> Dictionary:
	var defaults: Variant = Profile.DEFAULT_PREFERENCES.get(name, {})
	if typeof(defaults) != TYPE_DICTIONARY:
		return {}
	return defaults as Dictionary


func _volume(value: Variant, fallback: float) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return clampf(fallback, 0.0, 1.0)
	var number := float(value)
	if is_nan(number) or is_inf(number):
		return clampf(fallback, 0.0, 1.0)
	return clampf(number, 0.0, 1.0)


func _apply_audio(values: Dictionary) -> void:
	_set_bus_gain("Master", float(values.get("master", 1.0)))
	_set_bus_gain("Music", float(values.get("music", 1.0)))
	_set_bus_gain("SFX", float(values.get("sfx", 1.0)))


## 0 means an explicit mute; everything else is the bus gain, so per-source
## volumes and pitches stay untouched.
func _set_bus_gain(bus_name: String, gain: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	var level := clampf(gain, 0.0, 1.0)
	AudioServer.set_bus_mute(index, level <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(level) if level > 0.0 else -80.0)


# --- Display ----------------------------------------------------------------

## Window mode and vsync are applied here with a headless guard. The logical
## 768x480 viewport, aspect keep and fractional stretch are project settings and
## are never touched. Entering fullscreen remembers the windowed geometry;
## returning restores it.
func _apply_display(values: Dictionary) -> void:
	var want_fullscreen := str(values.get("window_mode", "windowed")) == "fullscreen"
	var want_vsync := bool(values.get("vsync", true))
	var headless := _headless()
	if not _display_initialized:
		_display_initialized = true
		if not headless:
			_fullscreen_active = _native_fullscreen()
			if not _fullscreen_active:
				_windowed_rect = Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
	if not headless:
		_apply_vsync(want_vsync)
	if want_fullscreen == _fullscreen_active:
		return
	if headless:
		## State stays truthful for preview/restore; no physical mode evidence.
		_fullscreen_active = want_fullscreen
		return
	if want_fullscreen:
		_windowed_rect = Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		if _windowed_rect.size.x > 0 and _windowed_rect.size.y > 0:
			DisplayServer.window_set_size(_windowed_rect.size)
			DisplayServer.window_set_position(_windowed_rect.position)
	_fullscreen_active = want_fullscreen


func _apply_vsync(enabled: bool) -> void:
	var want := DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED
	if DisplayServer.window_get_vsync_mode() != want:
		DisplayServer.window_set_vsync_mode(want)


func _native_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func _headless() -> bool:
	return DisplayServer.get_name().to_lower() == "headless"


func _apply_input(input_values: Dictionary) -> void:
	InputMap.load_from_project_settings()
	var keyboard: Dictionary = input_values.get("keyboard", {})
	var gamepad: Dictionary = input_values.get("gamepad", {})
	for action in GAMEPLAY_ACTIONS:
		var name := String(action)
		if keyboard.has(name):
			_replace_keyboard(action, int(keyboard[name]))
		if gamepad.has(name):
			_replace_gamepad(action, gamepad[name] as Dictionary)
	_mirror_jump_explicit(keyboard, gamepad)


func _replace_keyboard(action: StringName, code: int) -> void:
	if not InputMap.has_action(action):
		return
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	InputMap.action_add_event(action, _make_key(code))


func _replace_gamepad(action: StringName, binding: Dictionary) -> void:
	if not InputMap.has_action(action):
		return
	var keep_dpad := _movement_dpad(action)
	var keep_stick := action in MOVEMENT_ACTIONS
	var dpad_kept := false
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			var button := event as InputEventJoypadButton
			if keep_dpad >= 0 and button.button_index == keep_dpad:
				dpad_kept = true
				continue
			InputMap.action_erase_event(action, event)
		elif event is InputEventJoypadMotion:
			var motion := event as InputEventJoypadMotion
			if keep_stick and (motion.axis == JOY_AXIS_LEFT_X or motion.axis == JOY_AXIS_LEFT_Y):
				continue
			InputMap.action_erase_event(action, event)
	if str(binding.get("type", "")) == "button":
		var index := int(binding.get("index", -1))
		if dpad_kept and index == keep_dpad:
			return
	InputMap.action_add_event(action, _make_gamepad(binding))


func _movement_dpad(action: StringName) -> int:
	match action:
		&"move_left":
			return JOY_BUTTON_DPAD_LEFT
		&"move_right":
			return JOY_BUTTON_DPAD_RIGHT
		&"climb_up":
			return JOY_BUTTON_DPAD_UP
		&"climb_down", &"drop":
			return JOY_BUTTON_DPAD_DOWN
	return -1


func _mirror_jump_explicit(keyboard: Dictionary, gamepad: Dictionary) -> void:
	if not InputMap.has_action(&"jump_explicit"):
		return
	for event in InputMap.action_get_events(&"jump_explicit"):
		if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
			InputMap.action_erase_event(&"jump_explicit", event)
	if keyboard.has("jump"):
		InputMap.action_add_event(&"jump_explicit", _make_key(int(keyboard["jump"])))
	else:
		var space := InputEventKey.new()
		space.device = -1
		space.physical_keycode = KEY_SPACE
		InputMap.action_add_event(&"jump_explicit", space)
	if gamepad.has("jump"):
		InputMap.action_add_event(&"jump_explicit", _make_gamepad(gamepad["jump"] as Dictionary))
	else:
		var a := InputEventJoypadButton.new()
		a.device = -1
		a.button_index = JOY_BUTTON_A
		InputMap.action_add_event(&"jump_explicit", a)


func _make_key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.device = -1
	event.physical_keycode = code
	return event


func _make_gamepad(binding: Dictionary) -> InputEvent:
	if str(binding.get("type", "")) == "button":
		var button := InputEventJoypadButton.new()
		button.device = -1
		button.button_index = int(binding.get("index", 0))
		return button
	var motion := InputEventJoypadMotion.new()
	motion.device = -1
	motion.axis = int(binding.get("index", JOY_AXIS_TRIGGER_LEFT))
	motion.axis_value = 1.0
	return motion


# --- Matching ---------------------------------------------------------------

func _motion_pressed(action: StringName, event: InputEventJoypadMotion) -> bool:
	var key := _axis_key(event)
	var magnitude := absf(event.axis_value)
	if magnitude < 0.25:
		_axis_armed[key] = true
		_axis_event.erase(key)
		return false
	if magnitude <= 0.5:
		return false
	var pending_value: Variant = _axis_event.get(key)
	if typeof(pending_value) != TYPE_DICTIONARY:
		return false
	var pending := pending_value as Dictionary
	if int(pending.get("event_id", 0)) != event.get_instance_id():
		return false
	if bool(pending.get("consumed", true)):
		return false
	var direction := 1 if event.axis_value > 0.0 else -1
	for binding in InputMap.action_get_events(action):
		var motion := binding as InputEventJoypadMotion
		if motion == null or motion.axis != event.axis:
			continue
		if not _same_device(motion.device, event.device):
			continue
		var binding_direction := 1 if motion.axis_value >= 0.0 else -1
		if binding_direction != direction:
			continue
		pending["consumed"] = true
		return true
	return false


func _same_device(binding_device: int, event_device: int) -> bool:
	return binding_device == -1 or event_device == -1 or binding_device == event_device


func _axis_key(event: InputEventJoypadMotion) -> String:
	return "%d:%d" % [event.device, event.axis]


# --- Device observation -----------------------------------------------------

func _observe(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			_set_device(DEVICE_KEYBOARD)
	elif event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if button.pressed:
			_set_gamepad(button.device)
	elif event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		var key := _axis_key(motion)
		var magnitude := absf(motion.axis_value)
		if magnitude < 0.25:
			_axis_armed[key] = true
			_axis_event.erase(key)
		elif magnitude > 0.5:
			if bool(_axis_armed.get(key, true)):
				_axis_armed[key] = false
				_axis_event[key] = {
					"event_id": motion.get_instance_id(),
					"consumed": false,
				}
				_set_gamepad(motion.device)
			else:
				var pending_value: Variant = _axis_event.get(key)
				if typeof(pending_value) == TYPE_DICTIONARY:
					var pending := pending_value as Dictionary
					if int(pending.get("event_id", 0)) != motion.get_instance_id():
						_axis_event.erase(key)


func _set_gamepad(device: int) -> void:
	_active_gamepad = device
	_set_device(DEVICE_GAMEPAD)


func _set_device(device: StringName) -> void:
	if active_device == device:
		return
	active_device = device
	presentation_changed.emit()


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		## Reconnect never resumes the game or takes the prompt device back.
		return
	if active_device == DEVICE_GAMEPAD and (device == _active_gamepad or _active_gamepad == -1):
		_set_device(DEVICE_KEYBOARD)
	_pause_unpaused_live_run()


func _pause_unpaused_live_run() -> void:
	## Reuse the HUD's own pause ownership so the overlay, input lock and
	## escape handling all stay in one place. Keyboard remains live.
	if get_tree().paused or Game.run_over:
		return
	if Game.in_hub or Game.run_phase not in ["biome", "passage", "arena"]:
		return
	if Game.reward_open or Game.hub_return_in > 0.0:
		return
	var main := get_tree().current_scene
	if main == null:
		return
	var hud: Variant = main.get("hud")
	if not is_instance_valid(hud):
		return
	if not bool(hud.get("visible")):
		return
	if bool(hud.get("paused")):
		return
	if hud.has_method("_modal_open") and bool(hud.call("_modal_open")):
		return
	if hud.has_method("_set_paused"):
		hud.call("_set_paused", true)


# --- Prompts ----------------------------------------------------------------

func _keyboard_prompt(action: StringName) -> String:
	for binding in InputMap.action_get_events(action):
		var key := binding as InputEventKey
		if key == null:
			continue
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		if code == 0:
			continue
		var label := ""
		match code:
			KEY_PAGEUP:
				label = "PgUp"
			KEY_PAGEDOWN:
				label = "PgDn"
			KEY_BACKSPACE:
				label = "Bksp"
		if label.is_empty():
			label = OS.get_keycode_string(code)
		if not label.is_empty():
			return label
	return "—"


func _gamepad_prompt(action: StringName) -> String:
	for binding in InputMap.action_get_events(action):
		var button := binding as InputEventJoypadButton
		if button != null:
			return _button_label(button.button_index)
		var motion := binding as InputEventJoypadMotion
		if motion != null:
			return _motion_label(motion.axis)
	return "—"


func _button_label(index: int) -> String:
	match index:
		JOY_BUTTON_A:
			return "A"
		JOY_BUTTON_B:
			return "B"
		JOY_BUTTON_X:
			return "X"
		JOY_BUTTON_Y:
			return "Y"
		JOY_BUTTON_LEFT_SHOULDER:
			return "LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "RB"
		JOY_BUTTON_BACK:
			return "View"
		JOY_BUTTON_START:
			return "Start"
		JOY_BUTTON_LEFT_STICK:
			return "LS"
		JOY_BUTTON_RIGHT_STICK:
			return "RS"
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
			return "D-pad"
	return "B%d" % index


func _motion_label(axis: int) -> String:
	match axis:
		JOY_AXIS_TRIGGER_LEFT:
			return "LT"
		JOY_AXIS_TRIGGER_RIGHT:
			return "RT"
		JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y:
			return "LS"
		JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y:
			return "RS"
	return "Axis"
