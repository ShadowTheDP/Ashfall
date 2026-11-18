class_name TitleScreen
extends Control
## Pixel title. The composition is a rose window (circles), a Lissajous figure
## (curves) and a phyllotaxis field (points). Navigation runs on the shared
## Interface actions, so keyboard and gamepad reach the same five actions.

## The title asks Main for the single SettingsScreen above itself; Main keeps
## this page alive and paused, and only suppresses its drawing while open.
signal settings_requested
signal started

var _open := true
var _open_frame := -1
var _pressed_t := 0.0
var _slot := 0
var _view := "main"
var _action := 0
var _confirm_new := false
var _slot_select_failed := false
var resume_requested := false
var note := ""
var _locale := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 200
	_open_frame = Engine.get_process_frames()
	MathArt.ui_reveal(self)
	_slot = Profile.active_slot - 1
	_locale = TranslationServer.get_locale()
	if not Interface.presentation_changed.is_connected(_on_presentation_changed):
		Interface.presentation_changed.connect(_on_presentation_changed)
	get_tree().paused = true


## Prompt device or locale changed. Only the painted presentation moves; the
## focused action and slot stay where the player left them.
func _on_presentation_changed() -> void:
	queue_redraw()


## The composition is static, so it redraws only when something visible changes:
## input handlers, slot selection and the note. A per-frame redraw here would
## re-read three save files every idle frame.
func _process(delta: float) -> void:
	if TranslationServer.get_locale() != _locale:
		_locale = TranslationServer.get_locale()
		queue_redraw()
	if _pressed_t > 0.0:
		_pressed_t = maxf(0.0, _pressed_t - delta)
		if _pressed_t <= 0.0 and _open:
			_open = false
			visible = false
			get_tree().paused = false
			started.emit()
			queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if _settings_open():
		# Settings owns the top layer. Claim menu events as a backstop so no
		# held key can reach the title while the page is up.
		if _is_menu_event(event):
			get_viewport().set_input_as_handled()
		return
	if not _is_menu_event(event):
		return
	# The title is the top layer: claim the event even while the 0.12s exit
	# settle runs, so no gameplay action leaks under a closing page.
	get_viewport().set_input_as_handled()
	# The title can be created from the pause menu's return-to-title action.
	# Ignore that frame so the same press cannot also open a save on arrival.
	if Engine.get_process_frames() == _open_frame:
		return
	if _pressed_t > 0.0:
		return
	if Interface.pressed(event, &"ui_back"):
		_back()
		return
	if Interface.pressed(event, &"ui_accept"):
		_confirm()
		queue_redraw()
		return
	if _view == "main":
		if Interface.pressed(event, &"ui_nav_up"):
			_move_action(-1)
		elif Interface.pressed(event, &"ui_nav_down"):
			_move_action(1)
		elif Interface.pressed(event, &"ui_nav_left") or Interface.pressed(event, &"ui_nav_right"):
			# Sideways has no target on the action list, but it still counts as
			# navigation: a pending destructive confirmation is cancelled.
			_cancel_confirm()
		return
	# The three slot cards read as a horizontal strip; W/S and PageUp/PageDown
	# stay equivalent paths for the same choice.
	if Interface.pressed(event, &"ui_nav_left") or Interface.pressed(event, &"ui_nav_up") or Interface.pressed(event, &"ui_tab_prev"):
		_move_slot(-1)
	elif Interface.pressed(event, &"ui_nav_right") or Interface.pressed(event, &"ui_nav_down") or Interface.pressed(event, &"ui_tab_next"):
		_move_slot(1)


func _is_menu_event(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventAction


## The single SettingsScreen belongs to Main. Walk up to the flow owner rather
## than caching it, so a rebuilt title can never hold a freed page.
func _settings_open() -> bool:
	var owner := get_parent()
	while owner != null and not owner.has_method("start_floor"):
		owner = owner.get_parent()
	if owner == null:
		return false
	var page := owner.get("settings_screen") as SettingsScreen
	return is_instance_valid(page) and page.is_open()


func _request_settings() -> void:
	settings_requested.emit()
	queue_redraw()


## Public UI-only switch used by Main.return_to_title so pause "Saves" lands here.
func show_saves() -> void:
	_view = "saves"
	_confirm_new = false
	_slot_select_failed = false
	note = ""
	queue_redraw()


func _back() -> void:
	_confirm_new = false
	_slot_select_failed = false
	note = ""
	_view = "main"
	queue_redraw()


func _cancel_confirm() -> void:
	_confirm_new = false
	_slot_select_failed = false
	note = ""
	queue_redraw()


func _move_action(delta_index: int) -> void:
	_cancel_confirm()
	_action = wrapi(_action + delta_index, 0, 5)
	MathArt.ui_select(self)


func _move_slot(delta_index: int) -> void:
	_cancel_confirm()
	_slot = wrapi(_slot + delta_index, 0, Profile.SLOT_COUNT)
	MathArt.ui_select(self)


func _confirm() -> void:
	# A pending new-run confirmation outranks every normal action in both views,
	# so a second accept press is always the explicit confirmation. The shared
	# Interface edge-trigger ignores echo and release, so a held accept cannot
	# confirm twice.
	if _confirm_new:
		_choose(true)
	elif _view == "saves":
		_choose(false)
	else:
		match _action:
			0: _choose(false)
			1: _choose(true)
			2: show_saves()
			3: _request_settings()
			4: get_tree().quit()


func _choose(new_run: bool) -> void:
	_slot_select_failed = false
	if not Profile.select_slot(_slot + 1):
		_slot_select_failed = true
		note = Profile.last_save_error
		return
	if new_run and not Profile.run_checkpoint.is_empty():
		if not _confirm_new:
			_confirm_new = true
			note = "CONFIRM AGAIN: ABANDON CHECKPOINT / KEEP PERMANENT UNLOCKS"
			return
		var saved: Variant = Profile.run_checkpoint.get("state", {})
		var raw_kills: Variant = saved.get("kills", 0) if typeof(saved) == TYPE_DICTIONARY else 0
		var kills := int(raw_kills) if RunBuild._count(raw_kills) else 0
		if not Profile.note_run(kills, false, false):
			note = "SAVE FAILED: " + Profile.last_save_error
			return
	resume_requested = not Profile.run_checkpoint.is_empty()
	if resume_requested:
		note = RunCheckpoint.error(Profile.run_checkpoint)
		if not note.is_empty(): return
	_pressed_t = 0.12
	Sfx.play("reward", -7)


## The note keeps its raw English payload (other systems and fixtures compare
## it); only this rendering is localized.
func _note_display() -> String:
	if note.begins_with("SAVE FAILED: "):
		return Hud.save_failed_display(note.substr(13))
	if note == "CONFIRM AGAIN: ABANDON CHECKPOINT / KEEP PERMANENT UNLOCKS":
		return ContentText.of("UI_TITLE_CONFIRM_AGAIN", "CONFIRM AGAIN: ABANDON CHECKPOINT / KEEP PERMANENT UNLOCKS")
	if note.is_empty():
		return ""
	if _slot_select_failed:
		# Select-slot refusals are file/slot problems, not checkpoint damage.
		# The blocked labels stay machine values in Profile and only become
		# player text here through the shared save-slot labeler.
		var refused := ContentText.of("UI_TITLE_SLOT_REFUSED", "Refused · file unchanged")
		var summary := Profile.slot_summary(_slot + 1)
		if summary.blocked:
			return refused + " · " + Hud.slot_label(summary)
		# Keep a real diagnostic reason (e.g. CANNOT READ PROFILE: ...), while
		# a bare workflow refusal is not allowed to masquerade as checkpoint
		# damage or leak an internal token.
		if note.contains(": "):
			return refused + " · " + note
		return refused
	return ContentText.of("UI_TITLE_CHECKPOINT_BLOCKED", "Checkpoint blocked: {reason}").format({"reason": note})


func _draw() -> void:
	if _settings_open():
		# Settings paints the only full-page backdrop. Leaving this canvas
		# blank prevents a second page (and its mask) showing through.
		return
	MathArt.px_rect(self, Rect2(0, 0, 768, 480), MathArt.INK)
	MathArt.ui_text(self, Vector2(52, 58), ContentText.of("UI_TITLE_TAGLINE", "ASHFALL / ORIGINAL GEOMETRY"), 11, MathArt.LIGHT_DIM)
	if _view == "saves":
		_draw_saves()
	else:
		_draw_main()


func _draw_main() -> void:
	MathArt.ui_brand(self, Vector2(604, 102), 58)
	MathArt.ui_text(self, Vector2(52, 114), ContentText.of("UI_TITLE_BRAND", "ASHFALL"), 24, MathArt.PALE)
	MathArt.ui_text(self, Vector2(54, 141), ContentText.of("UI_TITLE_SUBTITLE", "Combat, geometry and consequence"), 13, MathArt.PALE)
	MathArt.ui_text(self, Vector2(52, 179), ContentText.of("UI_TITLE_CHOOSE", "Choose an action"), 16, MathArt.WHITE)
	var resume := not Profile.run_checkpoint.is_empty()
	var labels: Array[String] = [
		ContentText.of("UI_TITLE_CONTINUE", "Continue checkpoint") if resume else ContentText.of("UI_TITLE_ENTER_HUB", "Enter Hub"),
		ContentText.of("UI_TITLE_NEW_RUN", "New run"),
		ContentText.of("UI_TITLE_SAVES", "Saves"),
		ContentText.of("UI_TITLE_SETTINGS", "Settings"),
		ContentText.of("UI_TITLE_QUIT", "Quit"),
	]
	var hints: Array[String] = [
		ContentText.of("UI_TITLE_HINT_RESUME", "Resume the saved checkpoint") if resume else ContentText.of("UI_TITLE_HINT_OPEN_HUB", "Open the Hub"),
		ContentText.of("UI_TITLE_HINT_KEEP_PROGRESS", "Keep permanent progress"),
		ContentText.of("UI_TITLE_HINT_CHOOSE_SLOT", "Choose a save slot"),
		ContentText.of("UI_TITLE_HINT_SETTINGS", "Sound, display, controls and language"),
		ContentText.of("UI_TITLE_HINT_CLOSE_GAME", "Close the game"),
	]
	for i in 5:
		var rect := Rect2(52, 190 + i * 43, 306, 39)
		var focused := i == _action
		MathArt.ui_surface(self, rect, focused, true)
		MathArt.ui_text(self, rect.position + Vector2(16, 29), "%02d" % [i + 1], 24, MathArt.ACCENT if focused else MathArt.STONE_HI)
		MathArt.ui_text(self, rect.position + Vector2(70, 16), labels[i], 13, MathArt.WHITE if focused else MathArt.PALE)
		MathArt.ui_text(self, rect.position + Vector2(70, 16 + MathArt.ui_line_height(13)), hints[i], 11, MathArt.LIGHT_DIM)
	var summary := Profile.slot_summary(Profile.active_slot)
	MathArt.ui_surface(self, Rect2(378, 194, 338, 154), _confirm_new, true)
	MathArt.ui_text(self, Vector2(394, 218), ContentText.of("UI_TITLE_ACTIVE_SAVE", "ACTIVE SAVE"), 11, MathArt.LIGHT_DIM)
	MathArt.ui_text(self, Vector2(394, 248), ContentText.of("UI_TITLE_SAVE_NUMBER", "Save {slot}").format({"slot": Profile.active_slot}), 16, MathArt.WHITE)
	var state := ContentText.of("UI_TITLE_STATE_PROTECTED", "Protected / refused") if summary.blocked else (ContentText.of("UI_TITLE_STATE_CHECKPOINT", "Checkpoint available") if summary.get("resume", false) else (ContentText.of("UI_TITLE_STATE_EMPTY", "Empty / fresh start") if str(summary.label) == "EMPTY" else ContentText.of("UI_TITLE_STATE_HUB", "Hub / permanent progress")))
	MathArt.ui_text(self, Vector2(394, 272), state, 13, MathArt.PALE, 306)
	var explain := MathArt.ui_wrap(ContentText.of("UI_TITLE_SLOT_EXPLAIN", "{state} · {hint}").format({"state": Hud.slot_label(summary), "hint": hints[_action]}), 306, 11)
	for i in mini(3, explain.size()):
		MathArt.ui_text(self, Vector2(394, 296 + i * MathArt.ui_line_height(11)), explain[i], 11, MathArt.LIGHT_DIM, 306)
	MathArt.ui_text(self, Vector2(52, 420), ContentText.of("UI_TITLE_SAVE_EXPLAIN", "Saves at biome entrances, Passage and permanent purchases."), 11, MathArt.LIGHT_DIM)
	var notes := MathArt.ui_wrap(_note_display(), 306, 11)
	for i in mini(3, notes.size()):
		MathArt.ui_text(self, Vector2(394, 374 + i * MathArt.ui_line_height(11)), notes[i], 11, MathArt.DANGER if _confirm_new else MathArt.WHITE, 306)
	var x := 52.0
	x += MathArt.ui_key(self, Vector2(x, 440), _prompt_pair(&"ui_nav_up", &"ui_nav_down"), ContentText.of("UI_TITLE_KEY_SELECT", "Select"))
	MathArt.ui_key(self, Vector2(x, 440), Interface.prompt(&"ui_accept"), ContentText.of("UI_TITLE_KEY_OPEN", "Open"))


func _draw_saves() -> void:
	MathArt.ui_brand(self, Vector2(660, 92), 40)
	MathArt.ui_text(self, Vector2(52, 96), ContentText.of("UI_TITLE_SAVES_TITLE", "SAVES"), 24, MathArt.WHITE)
	var nav := _prompt_pair(&"ui_nav_left", &"ui_nav_right")
	var accept := Interface.prompt(&"ui_accept")
	MathArt.ui_text(self, Vector2(52, 122), ContentText.of("UI_TITLE_SAVES_HELP", "Use {nav} to choose a slot · {accept} opens · {back} back").format({"nav": nav, "accept": accept, "back": Interface.prompt(&"ui_back")}), 11, MathArt.LIGHT_DIM)
	for i in Profile.SLOT_COUNT:
		var rect := Rect2(52 + i * 226, 150, 212, 190)
		var summary := Profile.slot_summary(i + 1)
		var focused := i == _slot
		MathArt.ui_surface(self, rect, focused, true)
		MathArt.ui_text(self, rect.position + Vector2(16, 26), "%02d" % [i + 1], 24, MathArt.ACCENT if focused else MathArt.STONE_HI)
		if i + 1 == Profile.active_slot:
			MathArt.ui_text(self, rect.position + Vector2(rect.size.x - 70, 26), ContentText.of("UI_TITLE_ACTIVE", "ACTIVE"), 11, MathArt.HEAL, 54, HORIZONTAL_ALIGNMENT_RIGHT)
		var state := ContentText.of("UI_TITLE_SLOT_PROTECTED", "PROTECTED") if summary.blocked else (ContentText.of("UI_TITLE_SLOT_CHECKPOINT", "CHECKPOINT") if summary.get("resume", false) else (ContentText.of("UI_TITLE_SLOT_EMPTY", "EMPTY") if str(summary.label) == "EMPTY" else ContentText.of("UI_TITLE_SLOT_HUB", "HUB")))
		MathArt.ui_text(self, rect.position + Vector2(16, 56), state, 13, MathArt.PALE)
		var lines := MathArt.ui_wrap(Hud.slot_label(summary), 180, 13)
		for n in mini(4, lines.size()):
			MathArt.ui_text(self, rect.position + Vector2(16, 84 + n * MathArt.ui_line_height(13)), lines[n], 13, MathArt.WHITE if focused else MathArt.PALE, 180)
		var footer := ContentText.of("UI_TITLE_SLOT_REFUSED", "Refused · file unchanged") if summary.blocked else (ContentText.of("UI_TITLE_SLOT_ENTER_CONTINUES", "{accept} continues").format({"accept": accept}) if summary.get("resume", false) else (ContentText.of("UI_TITLE_SLOT_ENTER_FRESH", "{accept} starts fresh").format({"accept": accept}) if str(summary.label) == "EMPTY" else ContentText.of("UI_TITLE_SLOT_ENTER_HUB", "{accept} opens Hub").format({"accept": accept})))
		MathArt.ui_text(self, rect.position + Vector2(16, 174), footer, 11, MathArt.LIGHT_DIM, 180)
	var selected := Profile.slot_summary(_slot + 1)
	var label := MathArt.ui_wrap(ContentText.of("UI_TITLE_SELECTED_SAVE", "Save {slot} · {state}").format({"slot": _slot + 1, "state": Hud.slot_label(selected)}), 664, 16)
	for i in mini(2, label.size()):
		MathArt.ui_text(self, Vector2(52, 360 + i * MathArt.ui_line_height(16)), label[i], 16, MathArt.WHITE, 664)
	var notes := MathArt.ui_wrap(_note_display(), 664, 11)
	for i in mini(2, notes.size()):
		MathArt.ui_text(self, Vector2(52, 412 + i * MathArt.ui_line_height(11)), notes[i], 11, MathArt.DANGER if _confirm_new else MathArt.WHITE, 664)
	var x := 52.0
	x += MathArt.ui_key(self, Vector2(x, 440), _prompt_pair(&"ui_nav_left", &"ui_nav_right"), ContentText.of("UI_TITLE_KEY_SLOT", "Slot"))
	x += MathArt.ui_key(self, Vector2(x, 440), _prompt_pair(&"ui_tab_prev", &"ui_tab_next"), ContentText.of("UI_TITLE_KEY_SLOT", "Slot"))
	x += MathArt.ui_key(self, Vector2(x, 440), Interface.prompt(&"ui_accept"), ContentText.of("UI_TITLE_KEY_OPEN", "Open"))
	MathArt.ui_key(self, Vector2(636, 440), Interface.prompt(&"ui_back"), ContentText.of("UI_TITLE_KEY_BACK", "Back"))


## One keycap per action source: the prompt owner decides keyboard or gamepad.
## A gamepad maps both directions to the same D-pad/stick prompt; show it once.
func _prompt_pair(first: StringName, second: StringName) -> String:
	var a := Interface.prompt(first)
	var b := Interface.prompt(second)
	return a if a == b else a + "/" + b
