class_name RewardScreen
extends Control
## Between-wave boon picker, drawn as three pixel cards. Keyboard, gamepad and
## a numeric quick-pick all drive the same selection.
signal chosen(id: String)

var _choices: Array = []
var _index := 0
var _open := false
var _open_frame := -1
var _t := 0.0
var _locale := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	z_index = 100
	if not Interface.presentation_changed.is_connected(_on_presentation_changed):
		Interface.presentation_changed.connect(_on_presentation_changed)


func _on_presentation_changed() -> void:
	queue_redraw()


func open(choices: Array) -> void:
	_choices = choices.duplicate()
	_index = 0
	_open = true
	_open_frame = Engine.get_process_frames()
	_t = 0.0
	_locale = TranslationServer.get_locale()
	visible = true
	MathArt.ui_reveal(self)
	Game.reward_open = true
	get_tree().paused = true
	Combat.cancel_hitstop()
	Sfx.play("reward", -8)
	queue_redraw()


func _process(delta: float) -> void:
	if not _open:
		return
	_t += delta
	# Locale changes alter both the wrapping keys and the card copy; one string
	# compare per frame is cheaper than shaping the page again for no reason.
	if TranslationServer.get_locale() != _locale:
		_locale = TranslationServer.get_locale()
		queue_redraw()
	queue_redraw()


## Full-screen mandatory picker: input must be claimed here so nothing leaks to
## the world underneath while a boon is pending. Accept confirms, nav moves;
## Back is swallowed because the picker has no back action by contract.
func _input(event: InputEvent) -> void:
	if not _open:
		return
	if not _is_menu_event(event):
		return
	get_viewport().set_input_as_handled()
	# A boon can be opened from an interact/clear flow; ignore the frame it
	# opened on so that press cannot also choose a card.
	if Engine.get_process_frames() == _open_frame:
		return
	# Back is swallowed, not acted on: the reward is mandatory. Without this a
	# gamepad B would reach the HUD and pause the game under the picker.
	if Interface.pressed(event, &"ui_back"):
		return
	# Numeric quick-pick is a keyboard-only convenience, never the only path.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1:
				_pick(0)
				return
			KEY_2:
				_pick(1)
				return
			KEY_3:
				_pick(2)
				return
	if Interface.pressed(event, &"ui_accept"):
		_pick(_index)
		return
	if Interface.pressed(event, &"ui_nav_left"):
		_focus(-1)
	elif Interface.pressed(event, &"ui_nav_right"):
		_focus(1)


func _is_menu_event(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventAction


## A gamepad maps both directions to the same prompt; show it once.
func _prompt_pair(first: StringName, second: StringName) -> String:
	var a := Interface.prompt(first)
	var b := Interface.prompt(second)
	return a if a == b else a + "/" + b


func _focus(delta_index: int) -> void:
	if _choices.is_empty():
		return
	_index = wrapi(_index + delta_index, 0, _choices.size())
	MathArt.ui_select(self)
	Sfx.play("ui", -12)
	queue_redraw()


func _pick(index: int) -> void:
	if not _open or index < 0 or index >= _choices.size():
		return
	var id: String = _choices[index]
	_open = false
	visible = false
	Game.reward_open = false
	Game.apply_reward(id)
	if is_instance_valid(Game.player):
		Game.player.suppress_actions()
	get_tree().paused = false
	chosen.emit(id)


func _draw() -> void:
	if not _open: return
	MathArt.px_rect(self, Rect2(0, 0, 768, 480), MathArt.INK)
	MathArt.ui_panel(self, MathArt.UI_PAGE)
	MathArt.ui_heading(self,
		ContentText.of("UI_REWARD_TITLE", "Choose a boon"),
		ContentText.of("UI_REWARD_CONTEXT_ROOM", "Legacy Arena / room cleared") if Game.floor_index > 0 else ContentText.of("UI_REWARD_CONTEXT_WAVE", "Legacy Arena / wave cleared"))
	for i in _choices.size():
		var id := str(_choices[i])
		var cfg: Dictionary = Data.rewards.get(id, {})
		var rect := Rect2(52 + i * 226, 116, 212, 262)
		MathArt.ui_surface(self, rect, i == _index)
		MathArt.ui_text(self, rect.position + Vector2(16, 24), str(i + 1), 11, MathArt.WHITE)
		var at := rect.position + Vector2(106, 72)
		match id:
			"edge", "armory": MathArt.ui_gear(self, at, "melee" if id == "edge" else "kunai", 32)
			"vitality", "leech":
				MathArt.line(self, at + Vector2(-16, 0), at + Vector2(16, 0), MathArt.HEAL, 4)
				MathArt.line(self, at + Vector2(0, -16), at + Vector2(0, 16), MathArt.HEAL, 4)
				if id == "leech": MathArt.ring(self, at, 32, MathArt.HEAL, 1)
			"swift":
				for n in 3:
					MathArt.line(self, at + Vector2(-20 + n * 14, -12), at + Vector2(-8 + n * 14, 0), MathArt.TACTICS, 2)
					MathArt.line(self, at + Vector2(-8 + n * 14, 0), at + Vector2(-20 + n * 14, 12), MathArt.TACTICS, 2)
			_: MathArt.ui_gear(self, at, "aegis", 32)
		var names := MathArt.ui_wrap(ContentText.name("reward", id, str(cfg.get("name", id))), 180, 16)
		for n in mini(2, names.size()): MathArt.ui_text(self, rect.position + Vector2(16, 132 + n * MathArt.ui_line_height(16)), names[n], 16, MathArt.WHITE)
		var copy := ContentText.of("UI_S6_REWARD_CHANGE", "WHAT CHANGES · THIS RUN") + "\n" + ContentText.text("reward", id, str(cfg.get("desc", "")))
		var lines := MathArt.ui_wrap(copy, 180, 13)
		for n in mini(5, lines.size()): MathArt.ui_text(self, rect.position + Vector2(16, 196 + n * MathArt.ui_line_height(13)), lines[n], 13, MathArt.WHITE if n == 0 else MathArt.PALE)
	var nav := _prompt_pair(&"ui_nav_left", &"ui_nav_right")
	MathArt.ui_text(self, Vector2(52, 408), ContentText.of("UI_REWARD_HELP", "Use {nav} to preview · {accept} chooses · number keys pick immediately").format({"nav": nav, "accept": Interface.prompt(&"ui_accept")}), 11)
	var x := 52.0
	x += MathArt.ui_key(self, Vector2(x, 428), nav, ContentText.of("UI_REWARD_KEY_FOCUS", "Focus"))
	x += MathArt.ui_key(self, Vector2(x, 428), Interface.prompt(&"ui_accept"), ContentText.of("UI_REWARD_KEY_CHOOSE", "Choose"))
	MathArt.ui_key(self, Vector2(x, 428), "1 2 3", ContentText.of("UI_REWARD_KEY_QUICK", "Quick pick"))
