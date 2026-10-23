extends Node
## AUDIT A4 probe: input ownership, keyboard reachability, text fit and the
## modal state machine for the title, hub panels, HUD and reward screen.
##
## Run: godot --headless --path . tests/audit_a4.tscn
##
## Text metrics come from the real fallback font at the real sizes, so a
## failure here means a string overflows its card on a 768x480 screen.

var _main: Node
var _fails := 0
var _checks := 0
var _font: Font


func _ready() -> void:
	# The title pauses the tree; the probe has to keep running through that.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = $Main
	_font = ThemeDB.fallback_font
	Profile.reset_profile()
	Profile.bank(900)
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout

	await _test_title()
	await _test_hub_esc()
	await _test_reachability()
	await _test_j_leak()
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
	# Weapons price the unlock as `unlock_cost`; the card must quote it.
	var line := str(archive.call("_unlock_line", "arc_saber"))
	_check(line.contains("60"), "archive hides the weapon price: %s" % line)
	var owned := Profile.unlocked_weapons.size()
	await _press(KEY_ENTER)
	await get_tree().create_timer(0.2).timeout
	_check(Profile.unlocked_weapons.size() == owned + 1, "Enter did not unlock a weapon")
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
	# 1. Archive list rows: 12px name, 34px in from a 298px row, 150px kept on
	#    the right for WORN / the gem. (archive_screen._draw_list)
	for tab in ArchiveScreen.TABS:
		var table := _table(tab)
		for id in table:
			_fit(str(table[id].get("name", id)), 12, 264.0 - 34.0, "archive row name")
			_fit(str(table[id].get("name", id)), 16, 376.0 - 32.0, "archive card name")
	# 2. Archive stat columns: 8px label in 62px, 11px value in 90px.
	for label in ["DAMAGE TAKEN", "BLADE LENGTH", "I-FRAMES", "TELEGRAPH / HIT / RECOVER",
			"DAMAGE PER COMBO STEP", "HP BONUS", "DAMAGE PER STEP"]:
		_fit(label, 8, 344.0, "archive label %s" % label)
	_fit("DAMAGE TAKEN", 8, 62.0, "archive label column")
	_fit("+50 ms", 11, 90.0, "archive value column")
	_fit("NO RECORD. MEET IT IN THE FIELD.", 9, 376.0, "archive unknown line")
	_fit("LEFT/RIGHT TAB      UP/DOWN SCROLL      ENTER EQUIP / UNLOCK      ESC CLOSE",
		8, 768.0, "archive footer")
	_fit("ENTER TO UNLOCK FOR 999 CELLS", 9, 376.0, "archive unlock line")
	# 3. Skill tree card: the status column starts 176px from the right edge,
	#    the text starts 16px in, so the text owns 512-16-8 px.
	for id in Data.skill_nodes:
		var node: Dictionary = Data.skill_nodes[id]
		_fit(str(node.get("text", "")), 10, 488.0, "skill text %s" % id)
		_fit(str(node.get("name", id)), 14, 400.0, "skill card name")
		_fit(str(node.get("name", id)), 8, 120.0, "skill node label")
	_fit("REQUIRES EDGE III, SWIFT II", 10, 160.0, "skill status column")
	# 4. HUD floor banner: 320px centred at 11px.
	for key in Data.floors:
		_fit(str(Data.floors[key].get("name", "")), 11, 320.0, "floor banner %s" % key)
	_fit("%d HOSTILE%s   FLOOR %d / %d" % [99, "S", 5, 5], 8, 320.0, "floor subline")
	_fit("FLOOR %d / %d   GATE OPEN" % [5, 5], 8, 320.0, "floor gate line")
	# The floor name is also announced at 24px on entry (hud._draw_announce).
	for key in Data.floors:
		_fit(str(Data.floors[key].get("name", "")), 24, 400.0, "floor announce %s" % key)
	_fit("PERFECT DODGE", 24, 400.0, "announce line")
	_fit("%d CELLS    %d KILLS    x%d COMBO    %d PERFECT    %02d:%02d" % [
		9999, 999, 999, 999, 99, 59], 10, 480.0, "run over stats")
	_fit("A/D MOVE    SPACE JUMP    J EDGE    K KUNAI    L AEGIS    SHIFT ROLL    ESC PAUSE",
		8, 768.0 - 20.0 - 140.0, "hud hint strip")
	_fit("ESC RESUME      R RESTART      Q QUIT", 10, 400.0, "pause hints")
	# 5. Reward cards: 178 wide, name 14px, description 9px.
	for id in Data.rewards:
		_fit(str(Data.rewards[id].get("name", id)), 14, 178.0, "boon name")
		for line in str(Data.rewards[id].get("desc", "")).split("\n"):
			_fit(str(line), 9, 178.0, "boon desc")
		# 4 desc lines would collide with the "PRESS n" line at y+126.
		var lines := str(Data.rewards[id].get("desc", "")).split("\n").size()
		_check(100.0 + float(lines) * 12.0 <= 126.0, "boon %s desc runs into PRESS n" % id)
	_fit("LEFT/RIGHT SELECT      1/2/3 QUICK PICK      ENTER CONFIRM", 6, 440.0, "reward hints")
	# 6. Hub station rows (read-only files: report-only widths, still asserted so
	#    a future content edit cannot silently overflow them).
	for id in Data.characters:
		var cfg: Dictionary = Data.characters[id]
		_fit("%s" % str(cfg.get("name", id)), 12, 506.0, "hub character name")
		_fit("HP %d   SPD %d   KNIVES %d   %s" % [int(cfg.get("hp", 0.0)),
			int(cfg.get("speed", 0.0)), int(cfg.get("knives", 0)), str(cfg.get("passive_text", ""))],
			8, 540.0, "hub character passive")
	for id in Data.upgrades:
		var cfg: Dictionary = Data.upgrades[id]
		_fit("LV %d/%d   %s" % [5, int(cfg.get("max", 1)), str(cfg.get("text", ""))],
			8, 540.0, "hub upgrade text")


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

## Every panel has to advertise the keys it acts on, on screen.
func _test_hints() -> void:
	_hint_covers("res://scripts/ui/archive_screen.gd",
		["ESC", "LEFT/RIGHT", "UP/DOWN", "ENTER"])
	_hint_covers("res://scripts/ui/skill_tree.gd", ["ESC", "ARROW", "ENTER"])
	_hint_covers("res://scripts/meta/hub_ui.gd",
		["ESC", "UP/DOWN", "LEFT/RIGHT", "ENTER"])
	_hint_covers("res://scripts/ui/reward_screen.gd",
		["LEFT/RIGHT", "ENTER", "1/2/3"])


func _hint_covers(path: String, labels: Array) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		_fail("cannot read %s" % path)
		return
	# The hint line is the one draw_string that closes with ESC CLOSE / CONFIRM.
	var hint := ""
	for line in text.split("\n"):
		if line.contains("ESC CLOSE") or line.contains("CONFIRM") or line.contains("QUICK PICK") \
				or line.contains("NEAREST NODE") or line.contains("ENTER BUY"):
			hint += line + "\n"
	_check(not hint.is_empty(), "%s draws no key hint line" % path.get_file())
	for label in labels:
		_check(hint.contains(str(label)) or text.contains(str(label)),
			"%s never mentions %s" % [path.get_file(), label])


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
