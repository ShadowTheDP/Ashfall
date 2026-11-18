class_name SettingsScreen
extends CanvasLayer
## Preferences page: audio, display, controls and language.
##
## This node owns only the settings draft and the preview/commit transaction.
## `Profile` is still the sole preferences writer, `Interface` owns locale,
## InputMap, audio-bus and display presentation, and the caller keeps its own
## focus and pause state. Nothing here writes a file unless Apply succeeds.

signal closed

const PAGES: Array[String] = ["audio", "display", "controls", "language"]
const FOOTER_APPLY := 0
const FOOTER_RESET := 1
const FOOTER_BACK := 2
const FOOTER_LABEL_KEYS := ["UI_SETTINGS_APPLY", "UI_SETTINGS_RESET_PAGE", "UI_SETTINGS_BACK"]
const FOOTER_LABELS := ["Apply", "Reset this tab", "Back"]
const AUDIO_KEYS := ["master", "music", "sfx"]
const PREVIEW_MSEC := 10000
const BODY_Y := 130.0
const ROW_H := 36.0
const FOOTER_Y := 398.0
const CONTROL_ROWS := 6
const CONTROL_TOP := 148.0

## Public page state. Names are stable so probes can drive real events and then
## inspect the result without calling a handler directly.
var page_index := 0
var content_row := 0
var content_scroll := 0
var footer_focused := false
var footer_action := FOOTER_APPLY
var capture_active := false
var capture_action := ""
var capture_device := "keyboard"
var draft: Dictionary = {}
var committed: Dictionary = {}
var display_preview_active := false
var preview_deadline_ms := 0
var last_error := ""
var status_key := ""
var status_args: Dictionary = {}
## Wrapped critical-status detail. The detail panel scrolls instead of dropping
## lines, so a full raw save diagnostic stays reachable with ui_detail_up/down.
var status_detail_scroll := 0
var status_detail_max_scroll := 0

var _canvas: Control
var _open := false
var _open_frame := -1
var _status_tone := Color.TRANSPARENT
var _presentation_dirty := false
var _preview_last_second := -1
var _capture_gate := false
var _capture_gate_device := ""
var _capture_gate_key := -1
var _capture_gate_button := -1
var _capture_trigger_neutral: Dictionary = {}
var _capture_notice_key := ""
var _capture_notice_args: Dictionary = {}
var _locale := ""


func _ready() -> void:
	layer = 62
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_locale = TranslationServer.get_locale()
	_status_tone = MathArt.LIGHT_DIM
	if not Interface.presentation_changed.is_connected(_on_presentation_changed):
		Interface.presentation_changed.connect(_on_presentation_changed)
	_ensure_canvas()


# ------------------------------------------------------------------ public API

func open() -> void:
	_ensure_canvas()
	## A duplicate open must not silently abandon a live 10-second display
	## preview or unsaved locale/audio preview. Restore presentation first;
	## caller focus and pause stay untouched because no closed signal fires.
	if _open and (display_preview_active or _presentation_dirty):
		_restore_all_committed()
	_cancel_capture(false)
	display_preview_active = false
	preview_deadline_ms = 0
	_presentation_dirty = false
	committed = _snapshot_committed()
	draft = committed.duplicate(true)
	page_index = 0
	content_row = 0
	content_scroll = 0
	footer_focused = false
	footer_action = FOOTER_APPLY
	last_error = ""
	status_key = ""
	status_args.clear()
	status_detail_scroll = 0
	status_detail_max_scroll = 0
	_status_tone = MathArt.LIGHT_DIM
	_locale = TranslationServer.get_locale()
	_open = true
	_open_frame = Engine.get_process_frames()
	visible = true
	MathArt.ui_reveal(_canvas)
	Sfx.play("ui", -10)
	_canvas.queue_redraw()


func close() -> void:
	if not _open:
		return
	_cancel_capture(false)
	if display_preview_active:
		display_preview_active = false
		preview_deadline_ms = 0
		_restore_all_committed()
	elif _presentation_dirty:
		_restore_all_committed()
	_open = false
	visible = false
	## The closing confirm must not become a jump/attack/interact in the world
	## under the page. Pause state stays with the caller.
	if is_instance_valid(Game.player):
		Game.player.suppress_actions()
	Sfx.play("ui", -12)
	closed.emit()


func is_open() -> bool:
	return _open


# ---------------------------------------------------------------------- input

func _process(_delta: float) -> void:
	if not _open:
		return
	if TranslationServer.get_locale() != _locale:
		_locale = TranslationServer.get_locale()
		_canvas.queue_redraw()
	if not display_preview_active:
		return
	var now := Time.get_ticks_msec()
	if now >= preview_deadline_ms:
		_revert_display_preview("UI_SETTINGS_PREVIEW_EXPIRED")
		return
	var seconds := int(ceil(float(preview_deadline_ms - now) / 1000.0))
	if seconds != _preview_last_second:
		_preview_last_second = seconds
		_canvas.queue_redraw()


## `_input`, not `_unhandled_input`: a modal owns every menu event while it is
## open, including events it does not use. The caller keeps the pause state.
func _input(event: InputEvent) -> void:
	if not _open:
		return
	if not _is_menu_event(event):
		return
	get_viewport().set_input_as_handled()
	if Engine.get_process_frames() == _open_frame:
		return
	if capture_active:
		_handle_capture(event)
		return
	if display_preview_active:
		## OS input can arrive before the next _process timeout check. A preview
		## that has already expired must take the existing revert path, never
		## commit, so the deadline stays wall-clock exact.
		if Time.get_ticks_msec() >= preview_deadline_ms:
			_revert_display_preview("UI_SETTINGS_PREVIEW_EXPIRED")
			return
		if Interface.pressed(event, &"ui_accept"):
			_commit_preferences()
		elif Interface.pressed(event, &"ui_back"):
			_revert_display_preview("UI_SETTINGS_PREVIEW_CANCELLED")
		return
	if Interface.pressed(event, &"ui_back"):
		_back()
		return
	if _scroll_status_detail_event(event):
		return
	if Interface.pressed(event, &"ui_tab_prev"):
		_switch_page(-1)
		return
	if Interface.pressed(event, &"ui_tab_next"):
		_switch_page(1)
		return
	if footer_focused:
		_footer_input(event)
	else:
		_content_input(event)


func _is_menu_event(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventJoypadButton \
		or event is InputEventJoypadMotion or event is InputEventAction


func _back() -> void:
	close()


func _content_input(event: InputEvent) -> void:
	if page_index == 2:
		if Interface.pressed(event, &"ui_nav_left"):
			_switch_device(-1)
		elif Interface.pressed(event, &"ui_nav_right"):
			_switch_device(1)
		elif Interface.pressed(event, &"ui_nav_up"):
			_move_row(-1)
		elif Interface.pressed(event, &"ui_nav_down"):
			_move_row(1)
		elif Interface.pressed(event, &"ui_accept"):
			_begin_capture(_action_at(content_row), capture_device, event)
		return
	if Interface.pressed(event, &"ui_nav_left"):
		_adjust_row(-1)
	elif Interface.pressed(event, &"ui_nav_right"):
		_adjust_row(1)
	elif Interface.pressed(event, &"ui_nav_up"):
		_move_row(-1)
	elif Interface.pressed(event, &"ui_nav_down"):
		_move_row(1)
	elif Interface.pressed(event, &"ui_accept"):
		_adjust_row(1)


func _footer_input(event: InputEvent) -> void:
	if Interface.pressed(event, &"ui_nav_left"):
		footer_action = wrapi(footer_action - 1, 0, 3)
		Sfx.play("ui", -14)
		_canvas.queue_redraw()
	elif Interface.pressed(event, &"ui_nav_right"):
		footer_action = wrapi(footer_action + 1, 0, 3)
		Sfx.play("ui", -14)
		_canvas.queue_redraw()
	elif Interface.pressed(event, &"ui_nav_up"):
		footer_focused = false
		content_row = clampi(content_row, 0, maxi(0, _row_count() - 1))
		MathArt.ui_select(_canvas)
		Sfx.play("ui", -14)
		_canvas.queue_redraw()
	elif Interface.pressed(event, &"ui_accept"):
		_activate_footer()


func _activate_footer() -> void:
	match footer_action:
		FOOTER_APPLY:
			_apply()
		FOOTER_RESET:
			_reset_page()
		_:
			close()


func _move_row(direction: int) -> void:
	if footer_focused:
		if direction < 0:
			footer_focused = false
			content_row = clampi(content_row, 0, maxi(0, _row_count() - 1))
			MathArt.ui_select(_canvas)
			Sfx.play("ui", -14)
			_canvas.queue_redraw()
		return
	var count := _row_count()
	var next := content_row + direction
	if next < 0:
		return
	if next >= count:
		if direction > 0:
			footer_focused = true
			footer_action = FOOTER_APPLY
			MathArt.ui_select(_canvas)
			Sfx.play("ui", -14)
			_canvas.queue_redraw()
		return
	content_row = next
	if page_index == 2:
		var visible := _visible_rows()
		if content_row < content_scroll:
			content_scroll = content_row
		elif content_row >= content_scroll + visible:
			content_scroll = content_row - visible + 1
	MathArt.ui_select(_canvas)
	Sfx.play("ui", -14)
	_canvas.queue_redraw()


func _switch_page(direction: int) -> void:
	page_index = wrapi(page_index + direction, 0, PAGES.size())
	content_row = 0
	content_scroll = 0
	footer_focused = false
	footer_action = FOOTER_APPLY
	status_key = ""
	status_args.clear()
	status_detail_scroll = 0
	status_detail_max_scroll = 0
	_cancel_capture(false)
	MathArt.ui_select(_canvas)
	Sfx.play("ui", -14)
	_canvas.queue_redraw()


func _switch_device(direction: int) -> void:
	if direction == 0:
		return
	capture_device = "gamepad" if direction > 0 else "keyboard"
	Sfx.play("ui", -14)
	_canvas.queue_redraw()


# ------------------------------------------------------------------ settings

func _adjust_row(direction: int) -> void:
	if direction == 0 or display_preview_active:
		return
	match page_index:
		0:
			if content_row < 0 or content_row >= AUDIO_KEYS.size():
				return
			_adjust_audio(AUDIO_KEYS[content_row], direction)
		1:
			if content_row == 0:
				_toggle_window_mode()
			else:
				_toggle_vsync()
		2:
			return
		3:
			_toggle_locale()


func _adjust_audio(key: String, direction: int) -> void:
	var audio := _section_live(draft, "audio")
	var percent := int(round(_number(audio.get(key, 1.0), 1.0) * 100.0))
	percent = clampi(percent + direction * 5, 0, 100)
	audio[key] = float(percent) / 100.0
	_preview_audio_locale()
	_set_status("UI_SETTINGS_UNSAVED", {
		"back": Interface.prompt(&"ui_back"),
	}, MathArt.GOLD)


func _toggle_window_mode() -> void:
	var display := _section_live(draft, "display")
	display["window_mode"] = "fullscreen" if _window_mode() == "windowed" else "windowed"
	_set_status("UI_SETTINGS_DISPLAY_PENDING", {}, MathArt.GOLD)


func _toggle_vsync() -> void:
	var display := _section_live(draft, "display")
	display["vsync"] = not _vsync()
	_set_status("UI_SETTINGS_DISPLAY_PENDING", {}, MathArt.GOLD)


func _toggle_locale() -> void:
	var general := _section_live(draft, "general")
	general["locale"] = "en" if _locale_value() == "zh_TW" else "zh_TW"
	_preview_audio_locale()
	_set_status("UI_SETTINGS_UNSAVED", {
		"back": Interface.prompt(&"ui_back"),
	}, MathArt.GOLD)


func _reset_page() -> void:
	var defaults := _defaults()
	capture_active = false
	match page_index:
		0:
			draft["audio"] = (defaults["audio"] as Dictionary).duplicate(true)
			_preview_audio_locale()
		1:
			draft["display"] = (defaults["display"] as Dictionary).duplicate(true)
		2:
			draft["input"] = (defaults["input"] as Dictionary).duplicate(true)
		3:
			draft["general"] = (defaults["general"] as Dictionary).duplicate(true)
			_preview_audio_locale()
	_set_status("UI_SETTINGS_RESET_DONE", {}, MathArt.PALE)
	Sfx.play("ui", -12)
	_canvas.queue_redraw()


## Apply without a display change saves immediately. A display change first
## runs the native 10-second wall-clock preview; only Keep writes the file.
func _apply() -> void:
	if display_preview_active:
		_commit_preferences()
	elif _display_changed():
		_begin_display_preview()
	else:
		_commit_preferences()


func _begin_display_preview() -> void:
	display_preview_active = true
	preview_deadline_ms = Time.get_ticks_msec() + PREVIEW_MSEC
	_preview_last_second = PREVIEW_MSEC / 1000
	_presentation_dirty = _draft_presentation_differs()
	## Display preview still uses committed input; draft bindings never touch
	## gameplay before Profile.save_preferences() succeeds.
	Interface.apply_preferences(_preview_values(draft))
	status_key = ""
	status_args.clear()
	status_detail_scroll = 0
	status_detail_max_scroll = 0
	Sfx.play("ui", -12)
	_canvas.queue_redraw()


func _commit_preferences() -> void:
	if not Profile.save_preferences(draft.duplicate(true)):
		last_error = Profile.last_preferences_error
		var reason := last_error.strip_edges()
		if reason.is_empty():
			reason = ContentText.of("UI_SETTINGS_UNKNOWN_ERROR", "Unknown error")
		push_warning("SettingsScreen: preferences were not saved: %s" % reason)
		display_preview_active = false
		preview_deadline_ms = 0
		_restore_all_committed()
		_set_status("UI_SETTINGS_SAVE_FAILED", {"reason": reason}, MathArt.DANGER)
		Sfx.play("block", -10)
		_canvas.queue_redraw()
		return
	last_error = ""
	committed = _snapshot_committed()
	draft = committed.duplicate(true)
	display_preview_active = false
	preview_deadline_ms = 0
	_presentation_dirty = false
	## Persistence succeeded; this is the first point where new bindings,
	## locale, audio and display become the effective presentation.
	Interface.apply_preferences(committed)
	_set_status("UI_SETTINGS_APPLIED", {}, MathArt.HEAL)
	Sfx.play("ui", -8)
	_canvas.queue_redraw()


func _revert_display_preview(reason_key: String) -> void:
	display_preview_active = false
	preview_deadline_ms = 0
	_preview_last_second = -1
	## Keep audio/language previewing if that was already dirty; restore only
	## the display section (and committed input) to its previous actual state.
	Interface.apply_preferences(_preview_values(committed))
	_presentation_dirty = _draft_presentation_differs()
	_set_status(reason_key, {}, MathArt.GOLD)
	Sfx.play("block", -12)
	_canvas.queue_redraw()


func _restore_all_committed() -> void:
	Interface.apply_preferences(committed)
	_presentation_dirty = false


func _preview_values(display_source: Dictionary) -> Dictionary:
	return {
		"general": _section_read(draft, "general").duplicate(true),
		"audio": _section_read(draft, "audio").duplicate(true),
		"display": _section_read(display_source, "display").duplicate(true),
		"input": _section_read(committed, "input").duplicate(true),
	}


func _preview_audio_locale() -> void:
	## Locale and bus gains preview immediately, but the input section stays
	## committed so a pending rebind cannot leak into gameplay.
	Interface.apply_preferences(_preview_values(committed))
	_presentation_dirty = _draft_presentation_differs()
	_canvas.queue_redraw()


func _display_changed() -> bool:
	var desired := _section_read(draft, "display")
	var old := _section_read(committed, "display")
	return str(desired.get("window_mode", "windowed")) != str(old.get("window_mode", "windowed")) \
		or bool(desired.get("vsync", true)) != bool(old.get("vsync", true))


func _draft_presentation_differs() -> bool:
	var draft_general := _section_read(draft, "general")
	var old_general := _section_read(committed, "general")
	if str(draft_general.get("locale", "zh_TW")) != str(old_general.get("locale", "zh_TW")):
		return true
	var draft_audio := _section_read(draft, "audio")
	var old_audio := _section_read(committed, "audio")
	for key in AUDIO_KEYS:
		if absf(_number(draft_audio.get(key, 1.0), 1.0) - _number(old_audio.get(key, 1.0), 1.0)) > 0.0001:
			return true
	return false


# ------------------------------------------------------------------ bindings

func _begin_capture(action: String, device: String, event: InputEvent) -> void:
	capture_active = true
	capture_action = action
	capture_device = "gamepad" if device == "gamepad" else "keyboard"
	_capture_gate = true
	_capture_gate_device = ""
	_capture_gate_key = -1
	_capture_gate_button = -1
	if event is InputEventKey:
		var key := event as InputEventKey
		_capture_gate_device = "keyboard"
		_capture_gate_key = _key_code(key)
	elif event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		_capture_gate_device = "gamepad"
		_capture_gate_button = button.button_index
	else:
		_capture_gate = false
	_capture_notice_key = ""
	_capture_notice_args.clear()
	_capture_trigger_neutral.clear()
	_status_tone = MathArt.PALE
	for axis in Interface.TRIGGER_AXES:
		_capture_trigger_neutral[axis] = _trigger_is_neutral(axis)
	MathArt.ui_select(_canvas)
	Sfx.play("ui", -12)
	_canvas.queue_redraw()


func _cancel_capture(show_status: bool) -> void:
	if not capture_active:
		return
	capture_active = false
	capture_action = ""
	_capture_gate = false
	_capture_gate_device = ""
	_capture_gate_key = -1
	_capture_gate_button = -1
	_capture_notice_key = ""
	_capture_notice_args.clear()
	if show_status:
		_set_status("UI_SETTINGS_CAPTURE_CANCELLED", {}, MathArt.PALE)
		Sfx.play("ui", -12)
		_canvas.queue_redraw()


func _handle_capture(event: InputEvent) -> void:
	## Esc/B cancels before any binding interpretation, including while the
	## entry confirm is still held.
	if Interface.pressed(event, &"ui_back"):
		_cancel_capture(true)
		return
	if _capture_gate:
		if _gate_released(event):
			_capture_gate = false
		return
	if capture_device == "keyboard":
		if event is InputEventKey:
			var key := event as InputEventKey
			if key.pressed and not key.echo:
				var code := _key_code(key)
				if code > 0:
					_try_bind_keyboard(code)
		return
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if button.pressed:
			_try_bind_gamepad_button(button.button_index)
		return
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if motion.axis not in Interface.TRIGGER_AXES:
			return
		if motion.axis_value <= 0.25:
			_capture_trigger_neutral[motion.axis] = true
		elif motion.axis_value > 0.5 and bool(_capture_trigger_neutral.get(motion.axis, false)):
			_capture_trigger_neutral[motion.axis] = false
			_try_bind_gamepad_axis(motion.axis)


func _gate_released(event: InputEvent) -> bool:
	if _capture_gate_device == "keyboard" and event is InputEventKey:
		var key := event as InputEventKey
		return not key.pressed and _key_code(key) == _capture_gate_key
	if _capture_gate_device == "gamepad" and event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		return not button.pressed and button.button_index == _capture_gate_button
	return false


func _try_bind_keyboard(code: int) -> void:
	var conflict := _keyboard_conflict(code, capture_action)
	if not conflict.is_empty():
		_capture_notice_key = "UI_SETTINGS_CONFLICT"
		_capture_notice_args = {"action": _action_name(conflict)}
		status_detail_scroll = 0
		status_detail_max_scroll = 0
		_status_tone = MathArt.DANGER
		Sfx.play("block", -10)
		_canvas.queue_redraw()
		return
	var input := _section_live(draft, "input")
	var keyboard := _section_live(input, "keyboard")
	keyboard[capture_action] = code
	var action := capture_action
	capture_active = false
	_set_status("UI_SETTINGS_BOUND_KEY", {
		"action": _action_name(action),
		"binding": _keyboard_code_label(code),
	}, MathArt.HEAL)
	Sfx.play("pickup", -10)
	_canvas.queue_redraw()


func _try_bind_gamepad_button(index: int) -> void:
	if index < 0 or index >= JOY_BUTTON_MAX:
		return
	var binding := {"type": "button", "index": index}
	_try_bind_gamepad(binding)


func _try_bind_gamepad_axis(axis: int) -> void:
	if axis not in Interface.TRIGGER_AXES:
		return
	_try_bind_gamepad({"type": "axis", "index": axis, "sign": 1})


func _try_bind_gamepad(binding: Dictionary) -> void:
	var conflict := _gamepad_conflict(binding, capture_action)
	if not conflict.is_empty():
		_capture_notice_key = "UI_SETTINGS_CONFLICT"
		_capture_notice_args = {"action": _action_name(conflict)}
		status_detail_scroll = 0
		status_detail_max_scroll = 0
		_status_tone = MathArt.DANGER
		Sfx.play("block", -10)
		_canvas.queue_redraw()
		return
	var input := _section_live(draft, "input")
	var gamepad := _section_live(input, "gamepad")
	gamepad[capture_action] = binding.duplicate(true)
	var action := capture_action
	capture_active = false
	_set_status("UI_SETTINGS_BOUND_PAD", {
		"action": _action_name(action),
		"binding": _gamepad_binding_label(binding),
	}, MathArt.HEAL)
	Sfx.play("pickup", -10)
	_canvas.queue_redraw()


func _keyboard_conflict(code: int, target: String) -> String:
	for action_value in Interface.GAMEPLAY_ACTIONS:
		var other := String(action_value)
		if other == target:
			continue
		if not _effective_keyboard_codes(other).has(code):
			continue
		if _keyboard_alias_allowed(target, other, code):
			continue
		return other
	return ""


func _gamepad_conflict(binding: Dictionary, target: String) -> String:
	for action_value in Interface.GAMEPLAY_ACTIONS:
		var other := String(action_value)
		if other == target:
			continue
		for existing_value in _effective_gamepad_bindings(other):
			var existing := existing_value as Dictionary
			if str(existing.get("type", "")) != str(binding.get("type", "")):
				continue
			if int(existing.get("index", -1)) != int(binding.get("index", -2)):
				continue
			if _gamepad_alias_allowed(target, other, binding):
				continue
			return other
	return ""


## Only the approved defaults may share a physical input. These are not
## arbitrary overlaps: W/Up belong to jump+climb_up, S/Down and D-pad Down
## belong to drop+climb_down.
func _keyboard_alias_allowed(first: String, second: String, code: int) -> bool:
	if _same_pair(first, second, "jump", "climb_up") and code in [KEY_W, KEY_UP]:
		return true
	if _same_pair(first, second, "drop", "climb_down") and code in [KEY_S, KEY_DOWN]:
		return true
	return false


func _gamepad_alias_allowed(first: String, second: String, binding: Dictionary) -> bool:
	if str(binding.get("type", "")) != "button":
		return false
	return _same_pair(first, second, "drop", "climb_down") \
		and int(binding.get("index", -1)) == JOY_BUTTON_DPAD_DOWN


func _same_pair(first: String, second: String, a: String, b: String) -> bool:
	return (first == a and second == b) or (first == b and second == a)


func _effective_keyboard_codes(action: String) -> Array[int]:
	var out: Array[int] = []
	var input := _section_read(draft, "input")
	var keyboard := _section_read(input, "keyboard")
	if keyboard.has(action):
		var value: Variant = keyboard[action]
		if typeof(value) == TYPE_INT and int(value) > 0:
			out.append(int(value))
			return out
	for event_value in _native_events(action):
		if event_value is InputEventKey:
			var key := event_value as InputEventKey
			var code := _key_code(key)
			if code > 0 and not out.has(code):
				out.append(code)
	return out


func _effective_gamepad_bindings(action: String) -> Array:
	var native := _native_gamepad_bindings(action)
	var input := _section_read(draft, "input")
	var gamepad := _section_read(input, "gamepad")
	var override := _valid_gamepad_override(gamepad.get(action))
	if override.is_empty():
		return native
	var out: Array = []
	var keep_dpad := _movement_dpad(action)
	var keep_stick := Interface.MOVEMENT_ACTIONS.has(StringName(action))
	for item_value in native:
		var item := item_value as Dictionary
		if str(item.get("type", "")) == "button" and int(item.get("index", -1)) == keep_dpad:
			out.append(item.duplicate(true))
		elif str(item.get("type", "")) == "axis" and keep_stick \
				and int(item.get("index", -1)) in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
			out.append(item.duplicate(true))
	out.append(override.duplicate(true))
	return _dedupe_bindings(out)


func _native_events(action: String) -> Array:
	var config_value: Variant = ProjectSettings.get_setting("input/" + action, {})
	if typeof(config_value) != TYPE_DICTIONARY:
		return []
	var events: Variant = (config_value as Dictionary).get("events", [])
	return events if typeof(events) == TYPE_ARRAY else []


func _native_gamepad_bindings(action: String) -> Array:
	var out: Array = []
	for event_value in _native_events(action):
		if event_value is InputEventJoypadButton:
			var button := event_value as InputEventJoypadButton
			out.append({"type": "button", "index": button.button_index})
		elif event_value is InputEventJoypadMotion:
			var motion := event_value as InputEventJoypadMotion
			out.append({
				"type": "axis",
				"index": motion.axis,
				"sign": 1 if motion.axis_value >= 0.0 else -1,
			})
	return _dedupe_bindings(out)


func _dedupe_bindings(values: Array) -> Array:
	var out: Array = []
	for value in values:
		if not out.has(value):
			out.append(value)
	return out


func _valid_gamepad_override(value: Variant) -> Dictionary:
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
		if index not in Interface.TRIGGER_AXES:
			return {}
		var sign_value: Variant = data.get("sign", 0)
		if typeof(sign_value) != TYPE_INT or int(sign_value) != 1:
			return {}
		return {"type": "axis", "index": index, "sign": 1}
	return {}


func _key_code(event: InputEventKey) -> int:
	return event.physical_keycode if event.physical_keycode != 0 else event.keycode


func _movement_dpad(action: String) -> int:
	match action:
		"move_left":
			return JOY_BUTTON_DPAD_LEFT
		"move_right":
			return JOY_BUTTON_DPAD_RIGHT
		"climb_up":
			return JOY_BUTTON_DPAD_UP
		"climb_down", "drop":
			return JOY_BUTTON_DPAD_DOWN
	return -1


func _trigger_is_neutral(axis: int) -> bool:
	for device in 8:
		if absf(Input.get_joy_axis(device, axis)) > 0.25:
			return false
	return true


# --------------------------------------------------------------------- state

func _defaults() -> Dictionary:
	var value: Variant = Profile.DEFAULT_PREFERENCES
	return (value as Dictionary).duplicate(true)


func _snapshot_committed() -> Dictionary:
	var out := _defaults()
	var source_value: Variant = Profile.preferences
	if typeof(source_value) != TYPE_DICTIONARY:
		return out
	var source := source_value as Dictionary
	for name in ["general", "audio", "display"]:
		var section: Variant = source.get(name, {})
		if typeof(section) == TYPE_DICTIONARY:
			out[name] = (section as Dictionary).duplicate(true)
	var input_value: Variant = source.get("input", {})
	if typeof(input_value) == TYPE_DICTIONARY:
		var input := input_value as Dictionary
		var keyboard: Variant = input.get("keyboard", {})
		var gamepad: Variant = input.get("gamepad", {})
		out["input"] = {
			"keyboard": (keyboard as Dictionary).duplicate(true) if typeof(keyboard) == TYPE_DICTIONARY else {},
			"gamepad": (gamepad as Dictionary).duplicate(true) if typeof(gamepad) == TYPE_DICTIONARY else {},
		}
	return out


func _section_read(values: Dictionary, name: String) -> Dictionary:
	var value: Variant = values.get(name, {})
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


func _section_live(values: Dictionary, name: String) -> Dictionary:
	var value: Variant = values.get(name)
	if typeof(value) != TYPE_DICTIONARY:
		value = {}
		values[name] = value
	return value as Dictionary


func _row_count() -> int:
	match page_index:
		0:
			return AUDIO_KEYS.size()
		1:
			return 2
		2:
			return Interface.GAMEPLAY_ACTIONS.size()
		3:
			return 1
	return 0


func _visible_rows() -> int:
	return CONTROL_ROWS if page_index == 2 else 7


func _action_at(index: int) -> String:
	if index < 0 or index >= Interface.GAMEPLAY_ACTIONS.size():
		return ""
	return String(Interface.GAMEPLAY_ACTIONS[index])


func _window_mode() -> String:
	var display := _section_read(draft, "display")
	return "fullscreen" if str(display.get("window_mode", "windowed")) == "fullscreen" else "windowed"


func _vsync() -> bool:
	var display := _section_read(draft, "display")
	var value: Variant = display.get("vsync", true)
	return bool(value) if typeof(value) == TYPE_BOOL else true


func _locale_value() -> String:
	var general := _section_read(draft, "general")
	return "en" if str(general.get("locale", "zh_TW")) == "en" else "zh_TW"


func _number(value: Variant, fallback: float) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return clampf(fallback, 0.0, 1.0)
	var number := float(value)
	return clampf(number, 0.0, 1.0) if is_finite(number) else clampf(fallback, 0.0, 1.0)


func _set_status(key: String, args: Dictionary, tone: Color) -> void:
	status_key = key
	status_args = args.duplicate(true)
	status_detail_scroll = 0
	status_detail_max_scroll = 0
	_status_tone = tone
	_canvas.queue_redraw()


func _status_text() -> String:
	if display_preview_active:
		var seconds := maxi(0, int(ceil(float(preview_deadline_ms - Time.get_ticks_msec()) / 1000.0)))
		return _copy("UI_SETTINGS_PREVIEW_COUNTDOWN",
			"Display preview: keep in {seconds}s · {accept} keep / {back} revert", {
				"seconds": seconds,
				"accept": Interface.prompt(&"ui_accept"),
				"back": Interface.prompt(&"ui_back"),
			})
	if capture_active:
		if not _capture_notice_key.is_empty():
			return _copy(_capture_notice_key,
				"Binding refused: already used by {action}. Original binding kept." if _capture_notice_key == "UI_SETTINGS_CONFLICT" else "{action}", _capture_notice_args)
		var prompt := "Press a key for {action} · {back} to cancel" if capture_device == "keyboard" \
			else "Press a button or move a trigger for {action} · {back} to cancel"
		return _copy("UI_SETTINGS_PRESS_KEY" if capture_device == "keyboard" else "UI_SETTINGS_PRESS_PAD",
			prompt, {
				"action": _action_name(capture_action),
				"back": Interface.prompt(&"ui_back"),
			})
	if not status_key.is_empty():
		return _copy(status_key, _status_english(status_key), status_args)
	return _copy("UI_SETTINGS_OPEN_HINT",
		"Draft only · audio and language preview live · Apply saves every change")


func _status_english(key: String) -> String:
	match key:
		"UI_SETTINGS_UNSAVED":
			return "Unsaved changes · choose Apply below to save / {back} to discard"
		"UI_SETTINGS_DISPLAY_PENDING":
			return "Display draft changed · choose Apply below for a 10-second preview"
		"UI_SETTINGS_RESET_DONE":
			return "This tab's defaults are back in the draft. Apply to save them."
		"UI_SETTINGS_APPLIED":
			return "Settings applied and saved."
		"UI_SETTINGS_SAVE_FAILED":
			return "Settings not saved; original settings retained: {reason}"
		"UI_SETTINGS_PREVIEW_EXPIRED":
			return "Display preview expired; original mode and window size restored."
		"UI_SETTINGS_PREVIEW_CANCELLED":
			return "Display preview cancelled; original mode restored. Apply to retry."
		"UI_SETTINGS_CAPTURE_CANCELLED":
			return "Binding capture cancelled; original binding kept."
		"UI_SETTINGS_BOUND_KEY":
			return "Keyboard binding for {action}: {binding}"
		"UI_SETTINGS_BOUND_PAD":
			return "Gamepad binding for {action}: {binding}"
		"UI_SETTINGS_CONFLICT":
			return "Binding refused: already used by {action}. Original binding kept."
	return key


func _copy(key: String, english: String, args: Dictionary = {}) -> String:
	var text := ContentText.of(key, english)
	return text.format(args) if not args.is_empty() else text


# ------------------------------------------------------------------- labels

func _page_label(index: int) -> String:
	match index:
		0:
			return ContentText.of("UI_SETTINGS_TAB_AUDIO", "Audio")
		1:
			return ContentText.of("UI_SETTINGS_TAB_DISPLAY", "Display")
		2:
			return ContentText.of("UI_SETTINGS_TAB_CONTROLS", "Controls")
		_:
			return ContentText.of("UI_SETTINGS_TAB_LANGUAGE", "Language")


func _audio_label(key: String) -> String:
	match key:
		"master":
			return ContentText.of("UI_SETTINGS_MASTER", "Master volume")
		"music":
			return ContentText.of("UI_SETTINGS_MUSIC", "Music")
		_:
			return ContentText.of("UI_SETTINGS_SFX", "Effects")


func _window_mode_label() -> String:
	return ContentText.of("UI_SETTINGS_FULLSCREEN", "Fullscreen") if _window_mode() == "fullscreen" \
		else ContentText.of("UI_SETTINGS_WINDOWED", "Windowed")


func _vsync_label() -> String:
	return ContentText.of("UI_SETTINGS_ON", "On") if _vsync() else ContentText.of("UI_SETTINGS_OFF", "Off")


func _locale_label() -> String:
	return ContentText.of("UI_SETTINGS_LOCALE_ZH_NAME", "Traditional Chinese") if _locale_value() == "zh_TW" \
		else ContentText.of("UI_SETTINGS_LOCALE_EN_NAME", "English")


func _action_name(action: String) -> String:
	match action:
		"move_left":
			return ContentText.of("UI_SETTINGS_ACTION_MOVE_LEFT", "Move left")
		"move_right":
			return ContentText.of("UI_SETTINGS_ACTION_MOVE_RIGHT", "Move right")
		"drop":
			return ContentText.of("UI_SETTINGS_ACTION_DROP", "Drop through")
		"climb_up":
			return ContentText.of("UI_SETTINGS_ACTION_CLIMB_UP", "Climb up")
		"climb_down":
			return ContentText.of("UI_SETTINGS_ACTION_CLIMB_DOWN", "Climb down")
		"map":
			return ContentText.of("UI_SETTINGS_ACTION_MAP", "Map")
		"jump":
			return ContentText.of("UI_SETTINGS_ACTION_JUMP", "Jump")
		"attack":
			return ContentText.of("UI_SETTINGS_ACTION_ATTACK", "Attack")
		"weapon_two":
			return ContentText.of("UI_SETTINGS_ACTION_WEAPON_TWO", "Weapon 2")
		"throw":
			return ContentText.of("UI_SETTINGS_ACTION_THROW", "Throw")
		"aegis":
			return ContentText.of("UI_SETTINGS_ACTION_AEGIS", "Skill 2")
		"roll":
			return ContentText.of("UI_SETTINGS_ACTION_ROLL", "Roll")
		"pause":
			return ContentText.of("UI_SETTINGS_ACTION_PAUSE", "Pause")
		"interact":
			return ContentText.of("UI_SETTINGS_ACTION_INTERACT", "Interact")
		"heal":
			return ContentText.of("UI_SETTINGS_ACTION_HEAL", "Heal")
		"restart":
			return ContentText.of("UI_SETTINGS_ACTION_RESTART", "Restart")
	return action


func _binding_text(action: String, device: String) -> String:
	if capture_active and capture_action == action and capture_device == device:
		return ContentText.of("UI_SETTINGS_CAPTURING", "Press…")
	if device == "gamepad":
		var labels: Array[String] = []
		for value in _effective_gamepad_bindings(action):
			var label := _gamepad_binding_label(value as Dictionary)
			if not labels.has(label):
				labels.append(label)
		return " / ".join(labels) if not labels.is_empty() else ContentText.of("UI_SETTINGS_UNBOUND", "Unbound")
	var keys: Array[String] = []
	for code in _effective_keyboard_codes(action):
		var label := _keyboard_code_label(code)
		if not keys.has(label):
			keys.append(label)
	if keys.is_empty():
		return ContentText.of("UI_SETTINGS_UNBOUND", "Unbound")
	return " / ".join(keys.slice(0, 2)) + (" +%d" % (keys.size() - 2) if keys.size() > 2 else "")


func _keyboard_code_label(code: int) -> String:
	if code <= 0:
		return ContentText.of("UI_SETTINGS_UNBOUND", "Unbound")
	var label := OS.get_keycode_string(code)
	return label if not label.is_empty() else str(code)


func _gamepad_binding_label(binding: Dictionary) -> String:
	var index := int(binding.get("index", -1))
	if str(binding.get("type", "")) == "axis":
		match index:
			JOY_AXIS_TRIGGER_LEFT:
				return "LT"
			JOY_AXIS_TRIGGER_RIGHT:
				return "RT"
			JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y:
				return "LS"
			JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y:
				return "RS"
		return "Axis %d" % index
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
		JOY_BUTTON_DPAD_UP:
			return "D-pad ↑"
		JOY_BUTTON_DPAD_DOWN:
			return "D-pad ↓"
		JOY_BUTTON_DPAD_LEFT:
			return "D-pad ←"
		JOY_BUTTON_DPAD_RIGHT:
			return "D-pad →"
	return "B%d" % index


func _prompt_pair(first: StringName, second: StringName) -> String:
	var a := Interface.prompt(first)
	var b := Interface.prompt(second)
	return a if a == b else a + "/" + b


# ------------------------------------------------------------------- painting

func _ensure_canvas() -> void:
	if _canvas != null:
		return
	_canvas = Control.new()
	_canvas.name = "Paint"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_paint.bind(_canvas))
	add_child(_canvas)


func _on_presentation_changed() -> void:
	## Device changes only swap prompts/keycaps; focus, row and scroll stay.
	_canvas.queue_redraw()


func _paint(canvas: Control) -> void:
	MathArt.px_rect(canvas, Rect2(0, 0, 768, 480), MathArt.INK)
	MathArt.ui_panel(canvas, MathArt.UI_PAGE)
	MathArt.ui_heading(canvas,
		ContentText.of("UI_SETTINGS_TITLE", "Settings"),
		ContentText.of("UI_SETTINGS_CONTEXT", "Audio / display / controls / language · progress stays separate"))
	for index in PAGES.size():
		var rect := Rect2(52 + index * 167, 104, 163, 24)
		if index == page_index:
			MathArt.ui_focus(canvas, rect)
		else:
			MathArt.ui_surface(canvas, rect, false, true)
		MathArt.ui_text(canvas, Vector2(rect.position.x, rect.position.y + 17),
			_page_label(index), 11, MathArt.WHITE if index == page_index else MathArt.PALE,
			rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	match page_index:
		0:
			_draw_audio(canvas)
		1:
			_draw_display(canvas)
		2:
			_draw_controls(canvas)
		3:
			_draw_language(canvas)
	_draw_footer(canvas)
	_draw_status(canvas)
	_draw_key_hints(canvas)


func _row_rect(index: int) -> Rect2:
	return Rect2(52, BODY_Y + index * ROW_H, 664, ROW_H)


func _draw_row(canvas: Control, rect: Rect2, selected: bool) -> void:
	MathArt.ui_surface(canvas, rect, selected, true)


func _draw_audio(canvas: Control) -> void:
	for index in AUDIO_KEYS.size():
		var rect := _row_rect(index)
		var selected := not footer_focused and content_row == index
		_draw_row(canvas, rect, selected)
		MathArt.ui_text(canvas, rect.position + Vector2(18, 23), _audio_label(AUDIO_KEYS[index]),
			13, MathArt.WHITE if selected else MathArt.PALE)
		var percent := int(round(_number(_section_read(draft, "audio").get(AUDIO_KEYS[index], 1.0), 1.0) * 100.0))
		var track := Rect2(rect.position.x + 300, rect.position.y + 18, 250, 2)
		MathArt.px_rect(canvas, track, MathArt.STONE_DIM)
		if percent > 0:
			MathArt.px_rect(canvas, Rect2(track.position, Vector2(track.size.x * float(percent) / 100.0, 2)), MathArt.ACCENT)
		for tick in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var x: float = track.position.x + track.size.x * tick
			MathArt.line(canvas, Vector2(x, track.position.y - 3), Vector2(x, track.position.y + 3), MathArt.STONE_HI, 1)
		MathArt.disc(canvas, track.position + Vector2(track.size.x * float(percent) / 100.0, 1), 3, MathArt.PALE)
		var value := ContentText.of("UI_SETTINGS_PERCENT", "{percent}%").format({"percent": percent}) if percent > 0 \
			else ContentText.of("UI_SETTINGS_MUTED", "Muted")
		MathArt.ui_text(canvas, Vector2(rect.end.x - 142, rect.position.y + 23), value, 13,
			MathArt.DANGER if percent <= 0 else (MathArt.WHITE if selected else MathArt.PALE),
			124, HORIZONTAL_ALIGNMENT_RIGHT)
	_draw_note(canvas, Vector2(52, 276),
		ContentText.of("UI_SETTINGS_AUDIO_NOTE", "Volume 0 mutes that bus. Each sound keeps its own mix; Apply saves the levels."))


func _draw_display(canvas: Control) -> void:
	for index in 2:
		var rect := _row_rect(index)
		var selected := not footer_focused and content_row == index
		_draw_row(canvas, rect, selected)
		var label := ContentText.of("UI_SETTINGS_WINDOW_MODE", "Window mode") if index == 0 \
			else ContentText.of("UI_SETTINGS_VSYNC", "VSync")
		var value := _window_mode_label() if index == 0 else _vsync_label()
		MathArt.ui_text(canvas, rect.position + Vector2(18, 23), label, 13,
			MathArt.WHITE if selected else MathArt.PALE)
		MathArt.ui_text(canvas, Vector2(rect.position.x + 300, rect.position.y + 23), value, 13,
			MathArt.WHITE if selected else MathArt.PALE, 330, HORIZONTAL_ALIGNMENT_RIGHT)
	_draw_note(canvas, Vector2(52, 208),
		ContentText.of("UI_SETTINGS_DISPLAY_NOTE", "Display changes preview for 10 seconds after Apply. Keep to save; cancel or timeout restores the previous mode and window size."))
	_draw_note(canvas, Vector2(52, 246),
		ContentText.of("UI_SETTINGS_DISPLAY_NOTE2", "The 768×480 logical view, aspect and fractional scaling never change."))


func _draw_language(canvas: Control) -> void:
	var rect := _row_rect(0)
	var selected := not footer_focused and content_row == 0
	_draw_row(canvas, rect, selected)
	MathArt.ui_text(canvas, rect.position + Vector2(18, 23),
		ContentText.of("UI_SETTINGS_LANGUAGE", "Language"), 13, MathArt.WHITE if selected else MathArt.PALE)
	MathArt.ui_text(canvas, Vector2(rect.position.x + 300, rect.position.y + 23), _locale_label(), 13,
		MathArt.WHITE if selected else MathArt.PALE, 330, HORIZONTAL_ALIGNMENT_RIGHT)
	_draw_note(canvas, Vector2(52, 196),
		ContentText.of("UI_SETTINGS_LANGUAGE_NOTE", "Language previews immediately. Apply saves it; Back returns to the committed language."))
	_draw_note(canvas, Vector2(52, 234),
		ContentText.of("UI_SETTINGS_LANGUAGE_DEFAULT", "First use starts in Traditional Chinese; English is the fallback."))


func _draw_controls(canvas: Control) -> void:
	var header_y := 143.0
	MathArt.ui_text(canvas, Vector2(70, header_y), ContentText.of("UI_SETTINGS_ACTION", "Action"), 11, MathArt.LIGHT_DIM)
	MathArt.ui_text(canvas, Vector2(320, header_y), ContentText.of("UI_SETTINGS_KEYBOARD", "Keyboard"), 11,
		MathArt.WHITE if capture_device == "keyboard" else MathArt.LIGHT_DIM, 168, HORIZONTAL_ALIGNMENT_CENTER)
	MathArt.ui_text(canvas, Vector2(500, header_y), ContentText.of("UI_SETTINGS_GAMEPAD", "Gamepad"), 11,
		MathArt.WHITE if capture_device == "gamepad" else MathArt.LIGHT_DIM, 200, HORIZONTAL_ALIGNMENT_CENTER)
	MathArt.line(canvas, Vector2(320, 147), Vector2(488, 147),
		MathArt.ACCENT if capture_device == "keyboard" else MathArt.STONE, 1)
	MathArt.line(canvas, Vector2(500, 147), Vector2(700, 147),
		MathArt.ACCENT if capture_device == "gamepad" else MathArt.STONE, 1)
	for slot in CONTROL_ROWS:
		var index := content_scroll + slot
		if index >= Interface.GAMEPLAY_ACTIONS.size():
			break
		var action := _action_at(index)
		var rect := Rect2(52, CONTROL_TOP + slot * ROW_H, 664, 34)
		var selected := not footer_focused and content_row == index
		MathArt.ui_surface(canvas, rect, selected, true)
		MathArt.ui_text(canvas, Vector2(rect.position.x + 16, rect.position.y + 21), "%02d" % (index + 1), 11,
			MathArt.PALE if selected else MathArt.MID_DIM)
		MathArt.ui_text(canvas, Vector2(rect.position.x + 46, rect.position.y + 21),
			MathArt.ui_short(_action_name(action), 252, 13), 13, MathArt.WHITE if selected else MathArt.PALE)
		_draw_binding_cell(canvas, Rect2(320, rect.position.y + 4, 168, 26), action, "keyboard", selected)
		_draw_binding_cell(canvas, Rect2(500, rect.position.y + 4, 200, 26), action, "gamepad", selected)
	var first := content_scroll + 1 if Interface.GAMEPLAY_ACTIONS.size() > 0 else 0
	var last := mini(content_scroll + CONTROL_ROWS, Interface.GAMEPLAY_ACTIONS.size())
	MathArt.ui_text(canvas, Vector2(52, 382),
		ContentText.of("UI_SETTINGS_PAGE_POSITION", "{first}–{last} / {total}").format({
			"first": first, "last": last, "total": Interface.GAMEPLAY_ACTIONS.size(),
		}), 11, MathArt.LIGHT_DIM)
	MathArt.ui_text(canvas, Vector2(716, 382),
		ContentText.of("UI_SETTINGS_INPUT_SCOPE", "Gameplay actions only · menu keys stay available"), 11,
		MathArt.LIGHT_DIM, 360, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_binding_cell(canvas: Control, rect: Rect2, action: String, device: String, row_selected: bool) -> void:
	var column_selected := capture_device == device
	var cell_color := MathArt.BG_2 if row_selected and column_selected else MathArt.BG_1
	MathArt.px_rect(canvas, rect, cell_color)
	if row_selected and column_selected:
		MathArt.px_rect(canvas, Rect2(rect.position, Vector2(2, rect.size.y)), MathArt.ACCENT)
	var text := _binding_text(action, device)
	MathArt.ui_text(canvas, Vector2(rect.position.x + 10, rect.position.y + 18),
		MathArt.ui_short(text, rect.size.x - 20, 11), 11,
		MathArt.WHITE if row_selected and column_selected else MathArt.PALE)
	if capture_active and capture_action == action and capture_device == device:
		MathArt.line(canvas, Vector2(rect.position.x + 8, rect.end.y - 3), Vector2(rect.end.x - 8, rect.end.y - 3),
			MathArt.ACCENT, 1)


func _draw_footer(canvas: Control) -> void:
	for index in 3:
		var rect := Rect2(52 + index * 220, FOOTER_Y, 208, 28)
		var focused := footer_focused and footer_action == index and not capture_active
		if focused:
			MathArt.ui_focus(canvas, rect)
		else:
			MathArt.ui_surface(canvas, rect, false, true)
		MathArt.ui_text(canvas, Vector2(rect.position.x, rect.position.y + 19),
			ContentText.of(FOOTER_LABEL_KEYS[index], FOOTER_LABELS[index]), 11,
			MathArt.WHITE if focused else MathArt.PALE, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_status(canvas: Control) -> void:
	var text := _status_text()
	var tone := _status_tone if not display_preview_active else MathArt.GOLD
	if not _status_is_critical():
		text = MathArt.ui_short(text, 664, 11)
		MathArt.ui_text(canvas, Vector2(52, 440), text, 11, tone)
		return
	## Critical text is never shortened. A single short confirmation keeps the
	## footer line; anything wider or multi-line uses the full body panel.
	var width := MathArt.ui_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	if width > 664.0 or MathArt.ui_wrap(text, 632.0, 11).size() > 1:
		_draw_status_detail(canvas, text)
		return
	MathArt.ui_text(canvas, Vector2(52, 440), text, 11, tone)


## Errors, refusals and capture/confirmation prompts must stay complete. Only
## ordinary hints may shorten; a long critical line wraps in the body instead.
func _status_is_critical() -> bool:
	if display_preview_active or capture_active:
		return true
	return status_key in [
		"UI_SETTINGS_SAVE_FAILED", "UI_SETTINGS_CONFLICT",
		"UI_SETTINGS_BOUND_KEY", "UI_SETTINGS_BOUND_PAD",
		"UI_SETTINGS_APPLIED", "UI_SETTINGS_CAPTURE_CANCELLED",
		"UI_SETTINGS_PREVIEW_EXPIRED", "UI_SETTINGS_PREVIEW_CANCELLED",
	]


func _draw_status_detail(canvas: Control, text: String) -> void:
	var rect := Rect2(52, BODY_Y, 664, 256)
	MathArt.px_rect(canvas, rect, Color(MathArt.BG_0, 0.98))
	MathArt.line(canvas, Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y), MathArt.STONE, 1)
	MathArt.line(canvas, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), MathArt.STONE, 1)
	var lines := MathArt.ui_wrap(text, rect.size.x - 32, 11)
	var line_height := MathArt.ui_line_height(11)
	var max_lines := _status_detail_visible_lines()
	var total := lines.size()
	status_detail_max_scroll = maxi(0, total - max_lines)
	status_detail_scroll = clampi(status_detail_scroll, 0, status_detail_max_scroll)
	var first := status_detail_scroll
	var last := mini(first + max_lines, total)
	var tone := _status_tone if not display_preview_active else MathArt.GOLD
	for offset in max_lines:
		var index := first + offset
		if index >= total:
			break
		MathArt.ui_text(canvas, Vector2(rect.position.x + 16, rect.position.y + 18 + offset * line_height),
			lines[index], 11, tone)
	if total <= max_lines:
		return
	## The range and thumb make the hidden tail explicit and reachable; the
	## text is never shortened by the footer's single-line fit.
	var track := Rect2(rect.end.x - 10, rect.position.y + 12, 2, rect.size.y - 40)
	MathArt.px_rect(canvas, track, Color(MathArt.STONE_DIM, 0.55))
	var thumb_height := maxf(12.0, track.size.y * float(max_lines) / float(total))
	var thumb_y := track.position.y + (track.size.y - thumb_height) * float(status_detail_scroll) / float(status_detail_max_scroll)
	MathArt.px_rect(canvas, Rect2(track.position.x, thumb_y, track.size.x, thumb_height), MathArt.STONE_HI)
	var range_text := _copy("UI_SETTINGS_DETAIL_RANGE", "{first}–{last} / {total}", {
		"first": first + 1,
		"last": last,
		"total": total,
	})
	MathArt.ui_text(canvas, Vector2(rect.end.x - 176, rect.end.y - 8), range_text, 11,
		MathArt.LIGHT_DIM, 156, HORIZONTAL_ALIGNMENT_RIGHT)


func _status_detail_visible_lines() -> int:
	return maxi(1, int(floor((256.0 - 24.0) / MathArt.ui_line_height(11))))


func _status_detail_overflow() -> bool:
	if not _status_is_critical():
		status_detail_max_scroll = 0
		status_detail_scroll = 0
		return false
	var text := _status_text()
	var total := MathArt.ui_wrap(text, 664.0 - 32.0, 11).size()
	var width := MathArt.ui_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	if width <= 664.0 and total <= 1:
		status_detail_max_scroll = 0
		status_detail_scroll = 0
		return false
	status_detail_max_scroll = maxi(0, total - _status_detail_visible_lines())
	status_detail_scroll = clampi(status_detail_scroll, 0, status_detail_max_scroll)
	return status_detail_max_scroll > 0


func _scroll_status_detail_event(event: InputEvent) -> bool:
	if not _status_detail_overflow():
		return false
	if Interface.pressed(event, &"ui_detail_up"):
		_scroll_status_detail(-1)
		return true
	if Interface.pressed(event, &"ui_detail_down"):
		_scroll_status_detail(1)
		return true
	return false


func _scroll_status_detail(direction: int) -> void:
	var next := clampi(status_detail_scroll + direction, 0, status_detail_max_scroll)
	if next != status_detail_scroll:
		status_detail_scroll = next
		Sfx.play("ui", -14)
	_canvas.queue_redraw()


func _draw_key_hints(canvas: Control) -> void:
	if capture_active:
		MathArt.ui_key(canvas, Vector2(52, 452), Interface.prompt(&"ui_back"),
			ContentText.of("UI_SETTINGS_HINT_CANCEL_CAPTURE", "Cancel binding"))
		return
	if display_preview_active:
		var x := 52.0
		x += MathArt.ui_key(canvas, Vector2(x, 452), Interface.prompt(&"ui_accept"),
			ContentText.of("UI_SETTINGS_HINT_KEEP", "Keep"))
		MathArt.ui_key(canvas, Vector2(x, 452), Interface.prompt(&"ui_back"),
			ContentText.of("UI_SETTINGS_HINT_REVERT", "Revert"))
		return
	var cursor := 52.0
	cursor = _draw_hint(canvas, cursor, _prompt_pair(&"ui_tab_prev", &"ui_tab_next"),
		ContentText.of("UI_SETTINGS_HINT_CATEGORY", "Category"))
	if _status_detail_overflow():
		cursor = _draw_hint(canvas, cursor, _prompt_pair(&"ui_detail_up", &"ui_detail_down"),
			ContentText.of("UI_SETTINGS_HINT_DETAIL", "Detail"))
	else:
		cursor = _draw_hint(canvas, cursor, _prompt_pair(&"ui_nav_up", &"ui_nav_down"),
			ContentText.of("UI_SETTINGS_HINT_ROW", "Row"))
	cursor = _draw_hint(canvas, cursor, _prompt_pair(&"ui_nav_left", &"ui_nav_right"),
		ContentText.of("UI_SETTINGS_HINT_DEVICE", "Device") if page_index == 2
		else ContentText.of("UI_SETTINGS_HINT_ADJUST", "Adjust"))
	cursor = _draw_hint(canvas, cursor, Interface.prompt(&"ui_accept"),
		ContentText.of("UI_SETTINGS_HINT_REBIND", "Rebind") if page_index == 2
		else ContentText.of("UI_SETTINGS_HINT_SELECT", "Select"))
	MathArt.ui_key(canvas, Vector2(636, 452), Interface.prompt(&"ui_back"),
		ContentText.of("UI_SETTINGS_HINT_BACK", "Back"))


func _draw_hint(canvas: Control, x: float, key: String, label: String) -> float:
	var width := _key_width(key, label)
	if x + width > 624:
		return x
	MathArt.ui_key(canvas, Vector2(x, 452), key, label)
	return x + width


func _key_width(key: String, label: String) -> float:
	var font := MathArt.ui_font()
	var width := maxf(18, font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 10)
	return width + 6 + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + MathArt.UI_GAP


func _draw_note(canvas: Control, at: Vector2, text: String) -> void:
	var lines := MathArt.ui_wrap(text, 664, 11)
	for index in mini(2, lines.size()):
		MathArt.ui_text(canvas, at + Vector2(0, index * MathArt.ui_line_height(11)), lines[index],
			11, MathArt.LIGHT_DIM)
