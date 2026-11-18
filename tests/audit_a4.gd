extends Node
## AUDIT A4 probe: input ownership, keyboard reachability, text fit and the
## modal state machine for the title, hub panels, HUD and reward screen.
##
## Run: godot --headless --path . tests/audit_a4.tscn
##
## Text metrics come from the shipped UI face at the real sizes, so a
## failure here means a string overflows its card on a 768x480 screen.

var _main: Node
var _fails := 0
var _checks := 0
var _font: Font



func _ready() -> void:
	if not Data.is_node_ready():
		await Data.ready
	if not Interface.is_node_ready():
		await Interface.ready
	if not Sfx.is_node_ready():
		await Sfx.ready
	TranslationServer.set_locale("en")
	# The title pauses the tree; the probe has to keep running through that.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = $Main
	_font = MathArt.ui_font()
	Profile.reset_profile()
	Profile.bank(900)
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout

	await _test_title()
	await _test_hub_esc()
	await _test_reachability()
	await _test_j_leak()
	await _test_missing_skill_tree()
	await _test_reward()
	_test_text_fit()
	_test_hints()

	print("AUDIT A4 %s (%d checks, %d failures)" % [
		"OK" if _fails == 0 else "FAILED", _checks, _fails])
	get_tree().quit()


# ---------------------------------------------------------------------- title

func _test_title() -> void:
	var title: Variant = _main.get("title_screen")
	_check(title != null and is_instance_valid(title), "title screen missing")
	if title == null:
		return
	_check(get_tree().paused, "title did not pause the tree")
	_check(not _main.hud.visible, "HUD visible under the title")
	# The HUD must recognise the title as a modal even if it never sees a key.
	_check(_main.hud._modal_open(), "HUD does not treat the title as modal")

	# Esc is the pause key. Under the title it must do nothing: the title owns
	# the pause, and a HUD pause latched here paints PAUSED over the first run.
	await _press(KEY_ESCAPE)
	var latched: bool = _main.hud.paused
	_check(not latched, "Esc under the title latched HUD pause")
	if latched:
		# Keep the rest of the probe meaningful after a real failure.
		_main.hud.paused = false
		get_tree().paused = true

	# Enter starts the run and must raise nothing.
	await _press(KEY_ENTER)
	await get_tree().create_timer(0.5).timeout
	_check(not is_instance_valid(title) or not title.visible, "Enter did not start")
	_check(not get_tree().paused, "tree still paused after the title")
	_check(not _main.hud.paused, "HUD still thinks it is paused after the title")
	_check(not _any_open(), "Enter on the title fired a panel")
	_check(_main.hub != null, "no hub after the title")
	await get_tree().create_timer(0.4).timeout


# ------------------------------------------------------------- hub + Esc owner

func _test_hub_esc() -> void:
	var hub: Variant = _main.get("hub")
	if hub == null:
		_fail("hub missing")
		return
	# Pause must work when nothing is open, and unpause on the same key.
	await _press(KEY_ESCAPE)
	_check(get_tree().paused and _main.hud.paused, "Esc did not pause in the hub")
	await _press(KEY_ESCAPE)
	_check(not get_tree().paused and not _main.hud.paused, "Esc did not unpause")

	# Walk to each station, open it with J, close it with Esc. Exactly one
	# handler may act on each key.
	var stations: Array = hub.get("STATIONS")
	for i in stations.size():
		var id := str(stations[i].get("id", "?"))
		await _open_at(hub, float(stations[i].get("x", 0.0)))
		_check(_open_count() == 1, "station %s opened %d panels" % [id, _open_count()])
		_check(not hub.get("player").is_physics_processing(), "%s left the player running" % id)
		await _press(KEY_ESCAPE)
		await get_tree().create_timer(0.2).timeout
		_check(_open_count() == 0, "station %s survived Esc" % id)
		_check(not get_tree().paused, "Esc on %s paused the game" % id)
		_check(not _main.hud.paused, "Esc on %s latched HUD pause" % id)
		_check(hub.get("player").is_physics_processing(), "Esc on %s froze the player" % id)

	# Esc while a panel is open must not also reach the HUD, even if the panel
	# somehow fails to claim the key: the HUD has to see it as a modal too.
	await _open_at(hub, float(stations[2].get("x", 0.0)))
	_check(_main.hud._modal_open(), "HUD does not treat the ARCHIVES as modal")
	await _press(KEY_ESCAPE)
	await get_tree().create_timer(0.2).timeout
	_check(not _main.hud._modal_open(), "HUD still sees a modal after Esc")
	_check(not get_tree().paused, "Esc closed a panel AND paused the game")


# ------------------------------------------------ arrows + Enter only, no mouse

func _test_reachability() -> void:
	var archive: Variant = _main.get("archive")
	var tree: Variant = _main.get("skill_tree")
	var hub: Variant = _main.get("hub")
	if archive == null or tree == null or hub == null:
		_fail("meta screens missing")
		return

	# ARCHIVES: RIGHT changes tab, DOWN moves the row, Enter buys/equips.
	await _open_at(hub, 830.0)
	await _press(KEY_RIGHT)
	_check(str(archive.get("_tab")) == "weapon", "RIGHT did not switch archive tab")
	await _press(KEY_DOWN)
	_check(int(archive.get("_index")) == 1, "DOWN did not move the archive row")
	var line := str(archive.call("_unlock_line", "arc_saber"))
	_check(line.contains("SILT CISTERN") and line.contains("20 C"), "archive hides blueprint source/investment: %s" % line)
	var owned := Profile.unlocked_weapons.size()
	var wallet := Profile.cells
	await _press(KEY_ENTER)
	_check(Profile.unlocked_weapons.size() == owned and Profile.cells == wallet, "archive bypassed Collector blueprint")
	_check(str(archive.get("_note")).contains("BLUEPRINT"), "missing blueprint acquisition note")
	await _press(KEY_DOWN)
	await _press(KEY_ENTER)
	await get_tree().create_timer(0.2).timeout
	_check(Profile.unlocked_weapons.size() == owned + 1, "Enter did not unlock legacy non-blueprint weapon")
	_check(str(archive.get("_note")).contains("UNLOCKED"), "Enter gave no unlock note")
	await _press(KEY_ESCAPE)
	await get_tree().create_timer(0.2).timeout

	# SKILL TREE: Enter buys the node the cursor opens on, arrows move it.
	await _open_at(hub, 520.0)
	var learned := Profile.skill_nodes.size()
	await _press(KEY_ENTER)
	await get_tree().create_timer(0.2).timeout
	_check(Profile.skill_nodes.size() == learned + 1, "Enter did not buy a skill")
	var start := int(tree.get("_index"))
	await _press(KEY_DOWN)
	_check(int(tree.get("_index")) != start, "DOWN did not move the skill cursor")
	await _press(KEY_ESCAPE)
	await get_tree().create_timer(0.2).timeout

	# UPGRADES: arrows move, Enter buys.
	await _open_at(hub, 210.0)
	await _press(KEY_DOWN)
	_check(int(hub.get("ui").get("_index")) == 1, "DOWN did not move the upgrade row")
	var level := Profile.upgrade_level("edge")
	await _press(KEY_ENTER)
	await get_tree().create_timer(0.2).timeout
	_check(Profile.upgrade_level("edge") == level + 1, "Enter did not buy an upgrade")
	await _press(KEY_ESCAPE)
	await get_tree().create_timer(0.2).timeout


# ------------------------------------------------------- J ownership / re-entry

func _test_j_leak() -> void:
	var hub: Variant = _main.get("hub")
	var archive: Variant = _main.get("archive")
	var tree: Variant = _main.get("skill_tree")
	if hub == null or archive == null or tree == null:
		return

	# Walk to the ARCHIVES station and open it with J, like a player does.
	await _open_at(hub, 830.0)
	_check(archive.is_open(), "J on the ARCHIVES station did not open it")

	# J is not an archive key, so the modal must swallow it instead of letting
	# it reach the hub's proximity handler and re-open the station.
	await _press(KEY_DOWN)
	await _press(KEY_DOWN)
	var index_before := int(archive.get("_index"))
	await _press(KEY_J)
	await get_tree().create_timer(0.2).timeout
	_check(_open_count() == 1, "J inside the ARCHIVES raised a second panel")
	_check(int(archive.get("_index")) == index_before,
		"J inside the ARCHIVES re-opened it and reset the cursor")

	await _press(KEY_ESCAPE)
	await get_tree().create_timer(0.2).timeout
	_check(_open_count() == 0, "ARCHIVES survived Esc")
	_check(hub.get("player").is_physics_processing(), "player still frozen after ARCHIVES")

	# Same for the skill tree. Move the cursor first: the tree always opens on
	# the first available node, so a silent re-open is only visible from there.
	await _open_at(hub, 520.0)
	await _press(KEY_DOWN)
	var skill_index := int(tree.get("_index"))
	await _press(KEY_J)
	await get_tree().create_timer(0.2).timeout
	_check(_open_count() == 1, "J inside the SKILL TREE raised a second panel")
	_check(int(tree.get("_index")) == skill_index, "J inside the SKILL TREE reset the cursor")
	await _press(KEY_ESCAPE)
	await get_tree().create_timer(0.2).timeout
	_close_all()

	# And the upgrade panel: J confirms, it must not also attack.
	await _open_at(hub, 210.0)
	_check(hub.get("ui").is_open(), "J on the UPGRADES station did not open it")
	var level := Profile.upgrade_level("vitality")
	var swing := float(hub.get("player").get("attack_t"))
	await _press(KEY_J)
	await get_tree().create_timer(0.2).timeout
	_check(Profile.upgrade_level("vitality") == level + 1, "J does not confirm a row")
	_check(float(hub.get("player").get("attack_t")) == swing, "J started an attack under a panel")
	await _press(KEY_ESCAPE)
	await get_tree().create_timer(0.2).timeout
	_close_all()


func _test_missing_skill_tree() -> void:
	var tree: Node = _main.skill_tree
	_main.skill_tree = null
	await _open_at(_main.hub, 520.0)
	_check(not _main.hub.ui.is_open(), "missing SkillTree must not open a second implementation")
	_check(_main.hub.player.is_physics_processing(), "missing SkillTree must release the station freeze")
	_check(Game.announce_text == "SKILL TREE UNAVAILABLE", "missing SkillTree must report an unavailable module")
	_main.skill_tree = tree
	await _open_at(_main.hub, 520.0)
	_check(tree.is_open(), "restored SkillTree remains keyboard-reachable")
	await _press(KEY_ESCAPE)


# --------------------------------------------------------------------- reward

func _test_reward() -> void:
	var screen: Variant = _main.get("reward_screen")
	if screen == null:
		_fail("reward screen missing")
		return
	if screen.chosen.is_connected(Callable(_main, "_on_reward_chosen")):
		screen.chosen.disconnect(Callable(_main, "_on_reward_chosen"))
	screen.open(["vitality", "edge", "armory"])
	await get_tree().process_frame
	_check(get_tree().paused and Game.reward_open, "reward did not pause")
	# Esc must not pause underneath the reward screen.
	await _press(KEY_ESCAPE)
	_check(not _main.hud.paused, "Esc under the reward screen latched HUD pause")
	_check(screen.visible, "Esc closed the reward screen")
	await _press(KEY_ENTER)
	await get_tree().process_frame
	_check(not get_tree().paused and not Game.reward_open, "reward did not unpause")
	_check(not _main.hud.paused, "HUD paused after the reward screen")


# ------------------------------------------------------------------- text fit

func _test_text_fit() -> void:
	if _font == null:
		_fail("no fallback font to measure with")
		return
	for tab in ArchiveScreen.TABS:
		var table := _table(tab)
		for id in table:
			_wrapped_fits(str(table[id].get("name", id)), 13, 210, 2, "archive row")
			_wrapped_fits(str(table[id].get("name", id)), 20, 298, 2, "archive title")
	for id in Data.skill_nodes:
		var node: Dictionary = Data.skill_nodes[id]
		_fit(str(node.get("name", id)).capitalize(), 11, 110, "skill node label")
		_wrapped_fits(str(node.get("name", id)).capitalize(), 20, 220, 2, "skill title")
		_wrapped_fits(str(node.get("text", "")), 13, 220, 4, "skill effect")
	for id in Data.rewards:
		_wrapped_fits(str(Data.rewards[id].get("name", id)), 20, 180, 2, "boon name")
		_wrapped_fits(str(Data.rewards[id].get("desc", "")), 13, 180, 4, "boon effect")
	for table in [Data.characters, Data.upgrades]:
		for id in table:
			_wrapped_fits(str(table[id].get("name", id)), 13, 210, 2, "hub row")
			_wrapped_fits(str(table[id].get("name", id)), 20, 372, 2, "hub title")
	for key in Data.floors:
		_fit(str(Data.floors[key].get("name", "")), 24, 400, "floor announcement")
	# Long tokens and spaces must survive wrapping; a cropped line can conceal an effect.
	for value in ["UNBROKEN".repeat(40), "A long item name with many affixes ".repeat(12)]:
		var lines := MathArt.ui_wrap(value, 180, 13)
		_check("".join(lines) == value, "wrapping preserves complete content")
		for line in lines: _fit(line, 13, 180, "long content")
	_fit("PERFECT DODGE", 24, 400, "combat announcement")
	_fit("999999 Gold · 999999 Cells", 11, 220, "large wallet")


func _wrapped_fits(value: String, size: int, width: float, rows: int, what: String) -> void:
	var lines := MathArt.ui_wrap(value, width, size)
	_check(lines.size() <= rows, "%s exceeds its visible lines (%s)" % [what, value])
	for line in lines: _fit(line, size, width, what)


func _table(tab: String) -> Dictionary:
	if tab == "weapon":
		return Data.weapons
	if tab == "armor":
		return Data.armor
	return Data.enemies


func _fit(text: String, size: int, width: float, what: String) -> void:
	if _font == null:
		return
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_check(w <= width, "%s overflows: %.0f > %.0f px (%s)" % [what, w, width, text])


# --------------------------------------------------------------------- hints

## Every panel has to advertise the shared InputMap actions it acts on, through
## the same prompt service; no page may paint a frozen keyboard-only label.
func _test_hints() -> void:
	_prompt_covers("res://scripts/ui/archive_screen.gd", [&"ui_back", &"ui_nav_left", &"ui_nav_right", &"ui_nav_up", &"ui_nav_down", &"ui_accept", &"ui_tab_prev", &"ui_tab_next", &"ui_secondary", &"ui_detail_up", &"ui_detail_down"])
	_prompt_covers("res://scripts/ui/skill_tree.gd", [&"ui_back", &"ui_accept", &"ui_nav_up", &"ui_nav_left", &"ui_nav_down", &"ui_nav_right"])
	_prompt_covers("res://scripts/meta/hub_ui.gd", [&"ui_back", &"ui_accept", &"ui_nav_up", &"ui_nav_down", &"ui_nav_left", &"ui_nav_right", &"ui_tab_prev", &"ui_tab_next"])
	_prompt_covers("res://scripts/ui/reward_screen.gd", [&"ui_nav_left", &"ui_nav_right", &"ui_accept"])
	var reward := FileAccess.get_file_as_string("res://scripts/ui/reward_screen.gd")
	_check(reward.contains('"1 2 3"'), "reward keeps the numeric quick-pick hint on screen")


func _prompt_covers(path: String, actions: Array) -> void:
	var source := FileAccess.get_file_as_string(path)
	if source.is_empty():
		_fail("cannot read %s" % path)
		return
	_check(source.contains("Interface.prompt("), "%s routes key hints through the prompt service" % path.get_file())
	for action: StringName in actions:
		_check(source.contains('&"%s"' % action), "%s advertises %s" % [path.get_file(), action])
	for line in source.split("\n"):
		if not line.contains("MathArt.ui_key("):
			continue
		for frozen in ['"ENTER"', '"ESC"', '"A D"', '"W S"', '"W A S D"']:
			_check(not line.contains(frozen), "%s has no frozen keyboard hint %s" % [path.get_file(), frozen])


# --------------------------------------------------------------------- helpers

## Walk to a station and press J, exactly like a player: this is the only real
## path into a panel, and it is what freezes the body.
func _open_at(hub: Variant, x: float) -> void:
	hub.get("player").position = Vector2(x, -40.0)
	await get_tree().create_timer(0.2).timeout
	await _press(KEY_J)
	await get_tree().create_timer(0.2).timeout


func _open_count() -> int:
	var n := 0
	for key in ["archive", "skill_tree"]:
		var s: Variant = _main.get(key)
		if is_instance_valid(s) and s.has_method("is_open") and s.is_open():
			n += 1
	var hub: Variant = _main.get("hub")
	if is_instance_valid(hub) and hub.has_method("is_open") and hub.is_open():
		n += 1
	return n


func _any_open() -> bool:
	return _open_count() > 0


func _close_all() -> void:
	for key in ["archive", "skill_tree"]:
		var s: Variant = _main.get(key)
		if is_instance_valid(s) and s.has_method("is_open") and s.is_open():
			s.close()
	var hub: Variant = _main.get("hub")
	if is_instance_valid(hub) and hub.has_method("is_open") and hub.is_open():
		hub.get("ui")._close()


func _press(key: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.physical_keycode = key
	up.keycode = key
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fail(msg)


func _fail(msg: String) -> void:
	_fails += 1
	print("AUDIT A4 FAIL: ", msg)
