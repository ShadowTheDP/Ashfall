extends Node
## Availability comes from canonical charges, including partial sequential recharge.

## Test-only translation overlay. Godot adds a second same-locale Translation
## without guaranteeing that it shadows the CSV-loaded native resource, so the
## fixture removes the native object and delegates every other key back to it.
class OverrideTranslation extends Translation:
	var backing: Translation
	var override_key: StringName
	var override_value: StringName

	func _get_message(src_message: StringName, context: StringName) -> StringName:
		if src_message == override_key and context == &"":
			return override_value
		if backing == null:
			return &""
		return backing.get_message(src_message, context)

var _checks := 0
var _capture := false
var _capture_states: Array[Dictionary] = []

func _ready() -> void:
	if not Data.is_node_ready():
		await Data.ready
	if not Interface.is_node_ready():
		await Interface.ready
	if not Sfx.is_node_ready():
		await Sfx.ready
	TranslationServer.set_locale("en")
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Profile.require_test_profile(): return
	_capture = DisplayServer.get_name() != "headless"
	if _capture:
		_check(get_viewport().get_visible_rect().size == Vector2(768, 480) and DisplayServer.window_get_size() == Vector2i(1536, 960), "768x480 logical / 1536x960 display window")
	Profile.reset_profile()
	await get_tree().process_frame
	$Main.enter_hub()
	_check_palette("hub")
	_check_semantic_colors()
	_check($Main.start_node("ash_gate"), "route starts")
	_check_palette("ash_gate")
	get_tree().paused = true
	var hud: Hud = $Main.hud
	for notice in ["SAVE FAILED: PROFILE IS PROTECTED", "SAVE FAILED: " + "LONG_STORAGE_ERROR_TOKEN_".repeat(6) + " - ENTER TO RETRY"]:
		var lines := MathArt.ui_wrap(notice, 640, 24)
		_check("".join(lines) == notice, "announcements preserve the complete failure and retry instruction")
		for line in lines:
			_check(MathArt.ui_font().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x <= 640, "announcement fits without shrinking or truncating")
	var player: Player = Game.player
	var hp := player.hp
	var maximum := player.max_hp
	player.max_hp = 141.6
	for value in [0.0, 0.1, 70.8, 141.59, 141.6]:
		player.hp = value
		var readout := hud.health_readout(player)
		_check(readout.current <= readout.maximum and readout.maximum == 142, "HP rounding bounded %.2f" % value)
		_check(readout.full == (value >= player.max_hp), "FULL uses raw health %.2f" % value)
		var fill := 0.0
		for i in hud._hp_segments(player):
			fill += hud.health_segment_fill(player, i)
		_check(is_equal_approx(fill / hud._hp_segments(player), value / player.max_hp), "fractional bar is honest %.2f" % value)
		if value == 0.1:
			await _shot("hp-critical")
		elif value == 141.59:
			await _shot("hp-near-full")
		elif value == 141.6:
			await _shot("hp-full-fractional")
	player.hp = hp
	player.max_hp = maximum
	# STEP4 combat cluster: five gear cards only; the flask is a separate
	# survival surface and must never be folded back into this array.
	var rects := hud.equipment_rects()
	var expected := [
		Rect2(66, 362, 56, 56), Rect2(124, 362, 56, 56),
		Rect2(190, 362, 56, 56), Rect2(248, 362, 56, 56),
		Rect2(314, 362, 36, 56),
	]
	_check(rects.size() == expected.size(), "five gear slots, no flask in the equipment array")
	for i in mini(rects.size(), expected.size()):
		_check(rects[i].position.is_equal_approx(expected[i].position) and rects[i].size.is_equal_approx(expected[i].size), "gear slot %d has the approved STEP4 geometry" % i)
		for j in range(i):
			_check(not rects[i].intersects(rects[j]), "gear rectangles never overlap %d/%d" % [i, j])
	for i in [0, 2]:
		if i + 1 < rects.size():
			_check(is_equal_approx(rects[i + 1].position.x - rects[i].end.x, 2.0), "two-pixel pair gutter stays exact %d" % i)
	for i in [1, 3]:
		if i + 1 < rects.size():
			_check(rects[i + 1].position.x - rects[i].end.x >= 8.0, "weapon/skill group gutter keeps its separation %d" % i)
	_check(hud.FLASK_RECT == Rect2(16, 362, 42, 56), "flask keeps its separate survival strip")
	_check(hud.HP_RECT == Rect2(16, 440, 334, 24), "health plate keeps the STEP4 geometry")
	_check(hud.MINIMAP_RECT == Rect2(588, 346, 164, 84), "minimap keeps the STEP4 geometry")
	_check(hud.WALLET_RECT == Rect2(554, 432, 198, 32), "wallet and timer keep two readable lines")
	_check(is_equal_approx(hud.AXES_BASELINE, 434.0), "axis readout baseline keeps its approved row")
	_check(not hud.FLASK_RECT.intersects(rects[0]), "flask keeps its own 16..58 strip outside the gear array")
	for i in 5:
		_check(hud.pause_action_rect(i) == Rect2(52 + i * 134, 376, 128, 28), "pause action row keeps its fixed geometry %d" % i)
	# The compact card carries icon and key only; the name is measured against
	# the width the pause headline actually uses.
	var skill := Game.build.slots[2]
	_check(hud.gear_status(2).ready and hud.gear_status(2).recharge == 1, "full Kunai bright with full ring")
	await _shot("ready")
	Game.build.use(2)
	Game.build.tick(Game.build.cooldown(skill) * 0.5)
	_check(hud.gear_status(2).ready and hud.gear_status(2).charges == 1 and is_equal_approx(float(hud.gear_status(2).recharge), 0.5), "one charge remains usable during recharge")
	await _shot("partial")
	if _capture:
		var partial_cooldown := float(skill.get("cooldown", 0.0))
		var gear_rect := rects[2]
		var top_stray := Rect2(gear_rect.position.x, 0.0, gear_rect.size.x, 16.0)
		var short_fast := await _timer_shot(skill, 0.1, "timer-short-0.1")
		var short_slow := await _timer_shot(skill, 0.6, "timer-short-0.6")
		_check(_region_changed(short_fast, short_slow, gear_rect), "short prompt timer ink stays inside its gear card")
		_check(not _region_changed(short_fast, short_slow, top_stray), "short prompt timer never paints at the screen top")
		var saved_preferences := Profile.preferences.duplicate(true)
		saved_preferences.general.locale = TranslationServer.get_locale()
		var long_preferences := saved_preferences.duplicate(true)
		long_preferences["input"]["keyboard"]["throw"] = KEY_PAGEDOWN
		Interface.apply_preferences(long_preferences)
		var long_prompt := Interface.prompt(&"throw")
		var long_prompt_width := MathArt.ui_font().get_string_size(long_prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		_check(long_prompt == "PgDn", "the long timer fixture identifies its real PageDown binding", long_prompt)
		_check(long_prompt_width <= gear_rect.size.x - 8.0, "the PageDown prompt fits the gear card key row", "%.1fpx / %.1fpx available" % [long_prompt_width, gear_rect.size.x - 8.0])
		var long_fast := await _timer_shot(skill, 0.1, "timer-long-0.1")
		var long_slow := await _timer_shot(skill, 0.6, "timer-long-0.6")
		_check(_region_changed(long_fast, long_slow, gear_rect), "long prompt timer stays inside the same gear card")
		_check(not _region_changed(long_fast, long_slow, top_stray), "long prompt timer never paints at the screen top")
		Interface.apply_preferences(saved_preferences)
		skill["cooldown"] = partial_cooldown
		hud.queue_redraw()
		await _frames(2)
	Game.build.use(2)
	Game.build.use(3)
	_check(not hud.gear_status(2).ready and not hud.gear_status(3).ready, "empty Q and E are dimmed independently")
	await _shot("empty")
	Game.build.tick(Game.build.cooldown(skill) * 0.5)
	_check(hud.gear_status(2).ready and hud.gear_status(2).charges == 1 and not hud.gear_status(3).ready, "next charge restores Q without falsely marking E ready")
	hud._set_paused(true)
	await _shot("pause-entry")
	await _key(KEY_D)
	_check(hud._pause_index == 1, "input works during modal entry motion")
	await _shot("pause-selected-during-entry")
	await _key(KEY_A)
	if _capture: await get_tree().create_timer(0.12, true).timeout
	await _shot("details")
	await _key(KEY_D)
	_check(hud._pause_index == 1 and get_tree().paused, "pause detail selection cannot resume gameplay")
	await _key(KEY_ENTER)
	for step in 3:
		await _key(KEY_RIGHT)
	await _key(KEY_ENTER)
	_check(hud._abandon_confirm and not Game.run_over, "pause asks before abandoning")
	await _shot("abandon-confirm")
	await _key(KEY_ESCAPE)
	_check(not hud._abandon_confirm and hud.paused, "abandon cancel restores pause")
	await _shot("abandon-cancelled")
	# Bilingual long-name fixture: English comes from canonical Data mutation,
	# while zh_TW needs its real stable content key seeded temporarily. Both
	# paths must reach the real pause detail tail and be captured.
	var short_name := str(Data.gear.items.kunai.name)
	var english_long := "Kunai of the Long Suffering Twilight".repeat(4)
	var zh_long := "試煉之刃・漫長暮光".repeat(6)
	Data.gear.items.kunai.name = english_long
	Game.build.equip(2, Game.build.create("kunai"))
	hud._pause_index = 2
	hud.queue_redraw()
	await _frames(2)
	_check(ContentText.name("gear", "kunai", english_long) == english_long, "English fixture reads the mutated canonical name")
	_check(MathArt.ui_wrap(english_long, 304, 16).size() > 2, "English fixture name exceeds the pause headline")
	_check(hud._pause_line_count > hud.PAUSE_DETAIL_ROWS, "English long name keeps its full text in the pause detail column")
	for n in 40: await _key(KEY_DOWN)
	_check(hud._pause_scroll == hud._pause_line_count - hud.PAUSE_DETAIL_ROWS, "English pause detail scroll reaches the last line")
	await _shot("long-name-en")
	var native_zh := TranslationServer.get_translation_object("zh_TW")
	_check(native_zh != null, "the shipped zh_TW translation object is loaded")
	if native_zh == null:
		return
	var zh_translation := OverrideTranslation.new()
	zh_translation.locale = "zh_TW"
	zh_translation.backing = native_zh
	zh_translation.override_key = &"GEAR_KUNAI_NAME"
	zh_translation.override_value = StringName(zh_long)
	TranslationServer.remove_translation(native_zh)
	TranslationServer.add_translation(zh_translation)
	TranslationServer.set_locale("zh_TW")
	await _frames(2)
	var resolved_zh := ContentText.name("gear", "kunai", english_long)
	_check(resolved_zh == zh_long, "zh fixture resolves the real stable key, not the English mutation", resolved_zh)
	_check(MathArt.ui_wrap(zh_long, 304, 16).size() > 2, "zh fixture name exceeds the pause headline without shrinking type")
	hud._pause_scroll = 0
	hud.queue_redraw()
	await _frames(2)
	_check(hud._pause_line_count > hud.PAUSE_DETAIL_ROWS, "zh long name keeps its full text in the pause detail column")
	for n in 40: await _key(KEY_DOWN)
	_check(hud._pause_scroll == hud._pause_line_count - hud.PAUSE_DETAIL_ROWS, "zh pause detail scroll reaches the last line")
	await _shot("long-name-zh")
	TranslationServer.remove_translation(zh_translation)
	TranslationServer.add_translation(native_zh)
	TranslationServer.set_locale("en")
	Data.gear.items.kunai.name = short_name
	hud.queue_redraw()
	await _frames(2)
	hud._set_paused(false)
	await _check_rapid_focus(hud)
	if _capture:
		get_tree().paused = true
		for row in [["boss-announcement", "BRIDGE SENTINEL DEFEATED", &"info"], ["rune-announcement", "RUNE ACQUIRED: VINE", &"info"], ["save-announcement", "SAVE FAILED: PROFILE IS PROTECTED", &"error"], ["long-save-announcement", "SAVE FAILED: " + "LONG_STORAGE_ERROR_TOKEN_".repeat(6) + " - ENTER TO RETRY", &"error"]]:
			Game.announce(str(row[1]), 4.0, StringName(row[2]))
			Game.announce_t = 3.0
			await _shot(row[0])
	# Three layouts total; use real transition/restore owners without a seed sweep.
	_check(Game.select_destination("hanging_gallery"), "palette fixture chooses lawful first exit")
	Game.run_phase = "transition"
	$Main.enter_passage()
	_check_palette("passage")
	var passage_checkpoint := Profile.run_checkpoint.duplicate(true)
	$Main._on_passage_continued()
	_check(Game.run_node_id == "hanging_gallery", "palette follows continued biome")
	_check_palette("hanging_gallery")
	$Main.enter_hub()
	_check_palette("hub")
	Profile.load_profile(true)
	_check($Main.resume_checkpoint(), "biome palette fixture restores durable checkpoint")
	_check(Game.run_node_id == "hanging_gallery", "restore retains biome identity")
	_check_palette("hanging_gallery")
	_check(Profile.save(passage_checkpoint), "restore durable Passage fixture")
	$Main.enter_hub()
	Profile.load_profile(true)
	_check($Main.resume_checkpoint() and Game.run_phase == "passage", "Passage palette fixture restores durable checkpoint")
	_check_palette("passage")
	print("HUD READABILITY OK (%d checks)" % _checks)
	get_tree().quit()

func _check_palette(id: String) -> void:
	var material: ShaderMaterial
	for layer in $Main.get_children():
		if layer is CanvasLayer and layer.layer == -10:
			material = layer.get_child(0).material
	_check(material != null, "integrated background material exists: " + id)
	if material == null: return
	for row in [["shade_top", "background_top"], ["shade_mid", "background_mid"], ["shade_bottom", "background_bottom"], ["light_color", "accent"]]:
		_check(material.get_shader_parameter(row[0]) == MathArt.biome_color(id, row[1]), "background follows location %s: %s" % [id, row[1]])

func _check_semantic_colors() -> void:
	_check(MathArt.gear_color("melee", "chain_lash") == MathArt.SURVIVAL, "canonical survival melee overrides generic action")
	for id in ["arc_saber", "kiss_precision", "orbit_rings"]:
		_check(MathArt.gear_color("melee", id) == MathArt.TACTICS, "canonical tactics melee overrides generic action: " + id)
	_check(MathArt.gear_color("melee", "unknown_fixture") == MathArt.BRUTALITY, "unknown melee retains generic action identity")
	_check(MathArt.PLAYER.g > MathArt.PLAYER.r and MathArt.ENEMY.r > MathArt.ENEMY.g, "player and enemy retain distinct cool/warm identities")
	var axes: Array[Color] = []
	for axis in ["brutality", "tactics", "survival"]:
		var tone := MathArt.axis_color(axis)
		_check(tone.s > 0.2 and tone.a == 1.0 and not axes.has(tone), "axis has a distinct opaque semantic hue: " + axis)
		axes.append(tone)
	_check(_contrast(MathArt.PALE, MathArt.INK) >= 4.5, "primary text has readable panel contrast")
	for id in Data.biomes.biomes:
		_check(_contrast(MathArt.PLAYER, MathArt.biome_color(id, "background_mid")) >= 4.5, "player separates from biome background: " + str(id))
	_check(MathArt.biome_color("ash_gate", "background_mid") != MathArt.biome_color("hanging_gallery", "background_mid"), "first biome transition has a visible palette change")

func _contrast(a: Color, b: Color) -> float:
	var linear_a := a.srgb_to_linear().get_luminance()
	var linear_b := b.srgb_to_linear().get_luminance()
	return (maxf(linear_a, linear_b) + 0.05) / (minf(linear_a, linear_b) + 0.05)

## STEP8 consumer edge: a focus change must land immediately even while the
## page reveal is still animating, and the newest keypress must win. Freezing
## engine time keeps both tweens deterministically mid-flight across frames, so
## the proof never depends on frame pacing; frames and wall ticks still run.
func _check_rapid_focus(hud: Hud) -> void:
	hud._set_paused(true)
	## Fixture state: the long-name section left the selection on slot 2, so
	## start this proof from the first slot before sending real input.
	hud._pause_index = 0
	## _set_paused cancels any hitstop (Engine.time_scale = 1.0); freeze after it
	## so the reveal and settle tweens stay mid-flight for the whole proof.
	Engine.time_scale = 0.0
	var reveal := hud.get_meta("ui_reveal", null) as Tween
	_check(reveal != null and reveal.is_valid() and hud.position.y > 0.0,
		"the pause reveal is still running when the next press arrives")
	await _key(KEY_D)
	_check(hud._pause_index == 1, "focus moves on the first press without waiting for the reveal")
	var first := hud.get_meta("ui_select", null) as Tween
	_check(first != null and first.is_valid(), "the first focus change starts its settle tween")
	await _key(KEY_D)
	_check(hud._pause_index == 2, "the latest of two rapid presses owns the focus")
	_check(first == null or not first.is_valid(), "the newest selection kills the previous settle tween")
	var second := hud.get_meta("ui_select", null) as Tween
	_check(second != null and second != first and second.is_valid(), "only the newest settle tween remains")
	_check(is_zero_approx(float(hud.get_meta("ui_focus_progress", -1.0))),
		"the focus target is committed before its settle animation")
	_check(hud.position.y > 0.0 and reveal.is_valid(), "input never waits for the page reveal")
	Engine.time_scale = 1.0
	await get_tree().create_timer(0.2, true).timeout
	_check(hud._pause_index == 2, "the focus target survives the resumed animation")
	hud._set_paused(false)


## Idle frames for redraw settling; the tree may be paused, so this waits on the
## tree signal instead of any node's process tick.
func _frames(count: int) -> void:
	for n in count:
		await get_tree().process_frame


func _key(code: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		if _capture: print("HUD INPUT %dms key=%d pressed=%s" % [Time.get_ticks_msec(), code, str(pressed)])
		await get_tree().process_frame

func _timer_shot(skill: Dictionary, cooldown: float, label: String) -> Image:
	skill["cooldown"] = cooldown
	$Main.hud.queue_redraw()
	await _frames(2)
	return await _shot(label)

func _region_changed(first: Image, second: Image, rect: Rect2) -> bool:
	if first == null or second == null:
		return false
	if first.get_size() != second.get_size():
		return true
	for y in range(int(rect.position.y), int(rect.end.y)):
		for x in range(int(rect.position.x), int(rect.end.x)):
			if first.get_pixel(x, y) != second.get_pixel(x, y):
				return true
	return false

func _shot(label: String) -> Image:
	if not _capture: return null
	DirAccess.make_dir_recursive_absolute("res://output/screenshots/hud")
	await get_tree().process_frame
	$Main.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	var state := {"label":label,"ticks_usec":Time.get_ticks_usec(),"render_frame":Engine.get_frames_drawn(),"hp":Game.player.hp,"max_hp":Game.player.max_hp,"readout":$Main.hud.health_readout(Game.player),"q":$Main.hud.gear_status(2),"e":$Main.hud.gear_status(3),"announcement":Game.announce_text}
	_capture_states.append(state)
	var ledger := FileAccess.open("res://output/screenshots/hud/states.json", FileAccess.WRITE)
	ledger.store_string(JSON.stringify(_capture_states, "\t"))
	ledger.close()
	var image := get_viewport().get_texture().get_image()
	_check(image.save_png("res://output/screenshots/hud/" + label + ".png") == OK, "capture " + label)
	await _physical_capture(label)
	print("HUD FRAME %dms %s y=%.3f selected=%d state=%s" % [Time.get_ticks_msec(), label, $Main.hud.position.y, $Main.hud._pause_index, JSON.stringify(state)])
	if "entry" not in label and OS.get_environment("ASHFALL_CAPTURE_ACK_DIR").is_empty(): await get_tree().create_timer(0.08, true).timeout
	return image

func _check(ok: bool, message: String, actual: Variant = null) -> void:
	_checks += 1
	if not ok:
		if actual != null:
			message += " (actual: %s)" % str(actual)
		push_error("HUD READABILITY FAIL: " + message)
		get_tree().quit(1)

func _physical_capture(label: String) -> void:
	var directory := OS.get_environment("ASHFALL_CAPTURE_ACK_DIR")
	if directory.is_empty(): return
	var path := directory.path_join(label + ".json")
	var deadline := Time.get_ticks_msec() + 1500
	while not FileAccess.file_exists(path) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(FileAccess.file_exists(path), "owned physical capture acknowledgement: " + label)
