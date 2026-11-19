extends Node
## STEP 3 product probe: the shipped Chinese face, the zh_TW first-use locale
## without a preference file, native wrapping/truncation, translated consumer
## text, and the complete settings / navigation loop. Title and pause each open
## the single SettingsScreen and return with their own focus and pause intact;
## every choice, cancel, confirm and rebind below is a real parsed InputEvent.
##
## Opt-in through tools/check.py. The ui-product capture alias runs it with a
## display and writes 768x480 frames to output/ui-product/.

const SHIPPED_FONT := "res://assets/fonts/NotoSansCJKtc-Regular.otf"
const FONT_LICENSE := "res://assets/fonts/OFL.txt"
const OUTPUT_DIR := "res://output/ui-product"
const SETTINGS_PAGES := ["audio", "display", "controls", "language"]
const CJK_SAMPLE := ["設", "定", "裝", "備", "鍛", "造"]
const CLOSING_PUNCTUATION := "，。、！？：；）」』】〕》"
const OPENING_PUNCTUATION := "（「『【〔《"
## Fixed glossary cases with explicit canonical English, so the canonical value
## never depends on the locale the probe happens to be testing.
const FIXED_NAMES := [
	["axis", "brutality", "Brutality", "暴虐"],
	["axis", "tactics", "Tactics", "戰術"],
	["axis", "survival", "Survival", "生存"],
	["service", "collector", "Collector", "收藏者"],
	["service", "forge", "Forge", "鍛造"],
	["service", "mutation", "Mutation", "突變"],
	["loot", "scroll", "Scroll", "卷軸"],
	["loot", "gold", "Gold", "金幣"],
]

var _checks := 0
var _fails := 0
var _capture := false
var _main
var _settings_path := "user://ashfall_settings.cfg"
var _presentation_changed := 0


class TextFace extends Control:
	var line := ""

	func _init(value: String) -> void:
		line = value
		size = Vector2(520, 96)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
		MathArt.ui_text(self, Vector2(14, 52), line, 28, Color.WHITE)


func _ready() -> void:
	# The title/hub pause must not stop this probe while it waits for frames.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Profile.require_test_profile():
		push_error("UI PRODUCT FAIL: isolated test profile required")
		get_tree().quit(1)
		return
	for singleton in [Data, Profile, Interface, Sfx]:
		if not singleton.is_node_ready():
			await singleton.ready
	_capture = DisplayServer.get_name() != "headless"
	_main = $Main
	_check(is_instance_valid(_main), "the product Main scene boots for the probe")
	var configured := OS.get_environment("ASHFALL_SETTINGS_PATH")
	if not configured.is_empty():
		_settings_path = configured
	await _run()
	print("UI PRODUCT %s (%d checks, %d failures)" % ["OK" if _fails == 0 else "FAILED", _checks, _fails])
	if _fails == 0:
		# Final consumer proof: the pause action row's own Quit item exits the
		# real product. A successful quit never returns from this await.
		await _check_pause_quit()
		print("UI PRODUCT FAIL: the pause action row quit did not exit the game")
		_fails += 1
	await get_tree().process_frame
	get_tree().quit(1 if _fails else 0)


func _run() -> void:
	_check_first_frame_locale()
	_check_shipped_face()
	_check_wrap()
	_check_short()
	_check_translations()
	if _capture:
		_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR)) == OK, "capture output directory created")
	await _check_collector_failure_detail()
	await _check_input_api()
	await _check_title_pad()
	await _check_hub_pad()
	await _check_meta_failure_detail()
	await _check_gameplay_pad()
	await _check_hud_surface()
	await _check_reward_pad()
	await _check_shop_pad()
	await _check_shop_truth()
	await _check_scroll_truth()
	await _check_service_pad()
	await _check_mutation_reset_layer()
	await _check_craft_live_gold()
	await _check_map_states()
	await _check_slot_states()
	await _check_title_overwrite()
	await _check_result_states()
	if _capture:
		await _capture_surfaces()
	_check(TranslationServer.get_locale() == "zh_TW", "the probe leaves the product locale at zh_TW")
	_check(Profile.preferences == Profile.DEFAULT_PREFERENCES, "the probe restores the committed default preferences")
	_check(FileAccess.file_exists(Profile._settings_path), "only an explicit settings apply writes the preference file")


## No preference file exists on a first run, so the shipped default must be the
## Traditional Chinese locale before any page asks for text.
func _check_first_frame_locale() -> void:
	_check(not FileAccess.file_exists(Profile._settings_path), "no preference file exists at the first frame")
	_check(OS.get_environment("ASHFALL_LOCALE").is_empty(), "the check run does not force ASHFALL_LOCALE")
	_check(TranslationServer.get_locale() == "zh_TW", "first frame defaults to zh_TW without a preference file")
	_check(str(ProjectSettings.get_setting("internationalization/locale/fallback", "")) == "en", "en is the registered fallback locale")
	var locales := TranslationServer.get_loaded_locales()
	_check("zh_TW" in locales and "en" in locales, "both locales are registered with TranslationServer")


func _check_shipped_face() -> void:
	var font := MathArt.ui_font()
	_check(font != null, "the shared UI face resolves")
	if font == null:
		return
	var path := font.resource_path
	_check(path.ends_with(SHIPPED_FONT.get_file()), "UI text uses the shipped face, not an OS font: " + path)
	_check(FileAccess.file_exists(FONT_LICENSE), "the SIL OFL licence ships beside the face")
	var rids := font.get_rids()
	_check(not rids.is_empty(), "the shipped face exposes a TextServer face")
	if rids.is_empty():
		return
	var missing := PackedStringArray()
	for character: String in CJK_SAMPLE:
		if not font.has_char(character.unicode_at(0)) or _glyph_advance(font, character) <= 0.0:
			missing.append(character)
	_check(missing.is_empty(), "the shipped face carries real 設定裝備鍛造 glyphs: missing " + ", ".join(missing))
	var uncovered := PackedStringArray()
	for character in "金幣細胞卷軸突變收藏者鍛造中繼站藍圖暴虐戰術生存":
		if not font.has_char(character.unicode_at(0)):
			uncovered.append(character)
	_check(uncovered.is_empty(), "the shipped face covers the fixed glossary glyphs: missing " + ", ".join(uncovered))
	var mark_missing := PackedStringArray()
	for mark in "\u0301\u0304\u0307\u030c":
		if not font.has_char(mark.unicode_at(0)):
			mark_missing.append("U+%04X" % mark.unicode_at(0))
	_check(mark_missing.is_empty(), "the face carries the combining marks the wrap contract uses: missing " + ", ".join(mark_missing))
	var height_13 := font.get_height(13)
	_check(height_13 > 13.0, "the shipped face reports a real 13px line height: %.2f" % height_13)
	_check(MathArt.ui_line_height(13) >= height_13, "the 13px layout line height covers the face metrics: %.2f" % MathArt.ui_line_height(13))
	_check(MathArt.ui_line_height(24) >= font.get_height(24), "the 24px layout line height covers the face metrics: %.2f" % MathArt.ui_line_height(24))


## Properties of native wrapping, not a copy of the helper's algorithm: every
## line fits, content survives, and breaks respect Chinese punctuation rules and
## grapheme boundaries.
func _check_wrap() -> void:
	var font := MathArt.ui_font()
	var size := 13
	var narrow := MathArt.ui_wrap("短句\n下一句", 640.0, size)
	_check(narrow.size() == 2 and narrow[0].strip_edges() == "短句" and narrow[1].strip_edges() == "下一句", "an explicit newline survives native wrapping")
	var blank := MathArt.ui_wrap("甲\n\n乙", 640.0, size)
	_check(blank.size() == 3 and blank[1].strip_edges().is_empty(), "an explicit blank line stays blank between paragraphs")
	var trailing := MathArt.ui_wrap("甲\n", 640.0, size)
	_check(trailing.size() == 2 and trailing[0].strip_edges() == "甲" and trailing[1].is_empty(), "a trailing newline keeps its terminal empty line")
	var empty := MathArt.ui_wrap("", 640.0, size)
	_check(empty.size() == 1 and empty[0].is_empty(), "empty text keeps the single empty-line contract")
	var mixed := "拾取藍圖「弧刃」後，按 Enter 裝備；重複按 Space 仍不會購買。"
	var width := 180.0
	var lines := MathArt.ui_wrap(mixed, width, size)
	_check(lines.size() > 1, "mixed Chinese/English text wraps at the requested width")
	_check(_compact("".join(lines)) == _compact(mixed), "wrapping never drops or duplicates content")
	for line: String in lines:
		_check(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width + 0.5 or _single_grapheme(line), "each wrapped line fits the width: " + line)
		_check(not _starts_with_any(line, CLOSING_PUNCTUATION), "a closing punctuation mark never starts a line: " + line)
		_check(not _ends_with_any(line, OPENING_PUNCTUATION), "an opening punctuation mark never ends a line: " + line)
	_check(_has_whole_word(lines, "Enter"), "a normal English word stays whole on one line")
	_check(_has_whole_word(lines, "Space"), "the second English word stays whole on one line")
	var long_word := "e\u0301".repeat(60)
	var split := MathArt.ui_wrap(long_word, 100.0, size)
	_check(split.size() > 1, "an over-long word is broken instead of overflowing")
	_check("".join(split) == long_word, "a broken long word keeps every grapheme")
	var offset := 0
	for line: String in split:
		_check(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= 100.5 or _single_grapheme(line), "a long-word line fits the width")
		_check(_is_character_break(long_word, offset), "a long-word break lands on a grapheme boundary")
		_check(not _is_combining(line.substr(0, 1)), "no wrapped line begins with a combining mark")
		_check(not line.ends_with("\u200d"), "no wrapped line ends with a zero-width joiner")
		offset += line.length()
	var marked := "e\u0301\u0304\u0307\u030c".repeat(40)
	var marked_lines := MathArt.ui_wrap(marked, 60.0, size)
	_check(marked_lines.size() > 1, "a long combining sequence is broken instead of overflowing")
	_check("".join(marked_lines) == marked, "a broken combining sequence keeps every mark")
	var marked_offset := 0
	for line: String in marked_lines:
		_check(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= 60.5 or _single_grapheme(line), "a combining line fits the width")
		_check(_is_character_break(marked, marked_offset), "a combining break lands on a grapheme boundary")
		_check(not _is_combining(line.substr(0, 1)), "a combining mark never starts a line")
		_check(not line.ends_with("\u200d"), "a wrapped line never ends with a zero-width joiner")
		marked_offset += line.length()
	# The real save-failure shape at the detail width: one 280-character
	# unbroken ASCII token must keep every character and every rendered line
	# inside 372px, so the fixed receipt plus detail pane cannot clip it.
	var diagnostic := "O".repeat(268) + "END_SENTINEL"
	_check(diagnostic.length() == 280, "the unbroken diagnostic fixture is 280 characters")
	var restore_locale := TranslationServer.get_locale()
	for locale in ["zh_TW", "en"]:
		TranslationServer.set_locale(locale)
		var token_lines: Array[String] = MathArt.ui_wrap(diagnostic, 372.0, size)
		_check(token_lines.size() > 1, "a 280-char unbroken token wraps at the detail width (%s)" % locale)
		_check("".join(token_lines) == diagnostic, "the unbroken diagnostic keeps every character (%s)" % locale)
		var token_offset := 0
		for line: String in token_lines:
			_check(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= 372.5 or _single_grapheme(line), "an unbroken diagnostic line fits 372px (%s): %s" % [locale, line.substr(0, 12)])
			_check(_is_character_break(diagnostic, token_offset), "the unbroken diagnostic breaks on a grapheme boundary (%s)" % locale)
			token_offset += line.length()
	TranslationServer.set_locale(restore_locale)


func _check_short() -> void:
	var font := MathArt.ui_font()
	var value := "限量鍛造：弧刃與軌道環，還有非常長的說明文字 Blueprint"
	var width := 120.0
	_check(MathArt.ui_short("短句", 200.0, 13) == "短句", "ui_short returns text that already fits unchanged")
	var short := MathArt.ui_short(value, width, 13)
	_check(short.ends_with("…"), "ui_short ends in an ellipsis")
	_check(font.get_string_size(short, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x <= width + 0.01, "ui_short fits the requested width")
	var body := short.substr(0, short.length() - 1)
	_check(value.begins_with(body), "ui_short keeps a prefix of the original text")
	_check(_is_character_break(value, body.length()), "ui_short cuts on a grapheme boundary")
	_check(not body.ends_with("\u200d"), "ui_short never ends on a zero-width joiner")
	var accents := "e\u0301".repeat(40)
	var accent_short := MathArt.ui_short(accents, 90.0, 13)
	var accent_body := accent_short.substr(0, accent_short.length() - 1)
	_check(accent_short.ends_with("…") and accents.begins_with(accent_body), "ui_short truncates an accented word without losing its prefix")
	_check(_is_character_break(accents, accent_body.length()), "ui_short truncation respects an accented grapheme cluster")


func _check_translations() -> void:
	var zh := TranslationServer.get_translation_object("zh_TW")
	var en := TranslationServer.get_translation_object("en")
	_check(zh != null and en != null, "translation objects load for zh_TW and en")
	if zh == null or en == null:
		return
	_check(TranslationServer.get_locale() == "zh_TW", "content checks start in the first-use locale")
	_check_content_names()
	_check_surface_labels()
	TranslationServer.set_locale("en")
	_check(ContentText.of("UI_UNIT_CELLS", "Cells") == "Cells", "the display path keeps the canonical English row in en")
	_check(ContentText.name("axis", "brutality", "Brutality") == "Brutality", "content names stay canonical English in en")
	_check(ContentText.name("service", "forge", "Forge") == "Forge", "service names stay canonical English in en")
	_check(ContentText.machine("Run incomplete") == "Run incomplete", "machine values stay canonical English in en")
	TranslationServer.set_locale("zh_TW")


## Content names reach the page through ContentText.name(), so the probe asks
## that seam instead of rebuilding keys. English pages echo the canonical data
## text; zh_TW must carry a real translation, never the English fallback.
func _check_content_names() -> void:
	var rows: Array[Array] = []
	var unsourced := PackedStringArray()
	for id in Data.gear.items:
		var canonical := str((Data.gear.items[id] as Dictionary).get("name", ""))
		rows.append(["gear", str(id), canonical])
	for id in Data.route_graph.get("nodes", {}):
		var canonical := str((Data.route_graph["nodes"][id] as Dictionary).get("name", ""))
		rows.append(["biome", str(id), canonical])
	for row: Array in FIXED_NAMES:
		rows.append(row.slice(0, 3))
	_check(rows.size() > 2, "canonical gear and biome ids load from the data")
	for row: Array in rows:
		if str(row[2]).is_empty():
			unsourced.append("%s/%s" % [row[0], row[1]])
	_check(unsourced.is_empty(), "every canonical content name is present before translation: " + _sample(unsourced))
	var missing := PackedStringArray()
	var fallback := PackedStringArray()
	for row: Array in rows:
		var label := ContentText.name(str(row[0]), str(row[1]), str(row[2]))
		if label == str(row[2]):
			missing.append("%s/%s" % [row[0], row[1]])
		elif not _has_cjk(label):
			fallback.append("%s/%s=%s" % [row[0], row[1], label])
	var wrong := PackedStringArray()
	for row: Array in FIXED_NAMES:
		var label := ContentText.name(str(row[0]), str(row[1]), str(row[2]))
		if label != str(row[3]):
			wrong.append("%s/%s=%s" % [row[0], row[1], label])
	_check(missing.is_empty(), "every content name has a shipped translation: " + _sample(missing))
	_check(fallback.is_empty(), "zh_TW content names carry Chinese text, not the English fallback: " + _sample(fallback))
	_check(wrong.is_empty(), "the fixed vocabulary reaches the drawn name: " + _sample(wrong))


## Every shipped row must surface as real text through the display boundary:
## a key that survives translation, or leaks its UI_ identifier, fails here.
## The fixed vocabulary is asserted on the rows the product actually draws for
## it; proper names that merely contain a term are not renamed.
func _check_surface_labels() -> void:
	# OptimizedTranslation keeps no source-key list, so coverage walks the
	# stable keys the canonical data and the fixed vocabulary own.
	var keys := PackedStringArray()
	for id in Data.gear.items:
		keys.append("GEAR_%s_NAME" % str(id).to_upper())
	for id in Data.route_graph.get("nodes", {}):
		keys.append("BIOME_%s_NAME" % str(id).to_upper())
	for row: Array in FIXED_NAMES:
		keys.append("%s_%s_NAME" % [str(ContentText.PREFIX.get(str(row[0]), str(row[0]).to_upper())), str(row[1]).to_upper()])
	keys.append("UI_UNIT_CELLS")
	keys.append("UI_ENTERING_PASSAGE")
	keys.append("UI_ERR_SAVE_FAILED")
	keys.append("UI_MACHINE_RUN_INCOMPLETE")
	var raw := PackedStringArray()
	for key: String in keys:
		var text := str(TranslationServer.translate(key))
		if text.is_empty() or text == key or text.contains("UI_"):
			raw.append(key)
	_check(raw.is_empty(), "every shipped row surfaces as text, not a raw key: " + _sample(raw))
	_check(ContentText.of("UI_UNIT_CELLS", "Cells") == "細胞", "the drawn Cells unit uses 細胞")
	_check(ContentText.of("UI_ENTERING_PASSAGE", "ENTERING PASSAGE") == "進入中繼站", "the passage announcement uses 中繼站")
	_check(ContentText.of("UI_ERR_SAVE_FAILED", "Save failed") == "存檔失敗", "the save-failure line is translated at display time")
	_check(ContentText.machine("Run incomplete") == "本局尚未完成", "the run-scope machine value uses 本局 at display time")


## The retry receipt must advertise the real accept key for the current device.
func _collector_retry_note() -> String:
	return ContentText.of("UI_COLLECTOR_NOTE_SAVE_FAILED", "SAVE FAILED / NOTHING COMMITTED / {action} RETRY").format({"action": Interface.prompt(&"ui_accept")})


## D5 regression: the raw save diagnostic is retained in full, scrolls through
## real A/D input, and changing the selected row clears the nearest state.
func _check_collector_failure_detail() -> void:
	_main._open_collector()
	await _frames(3)
	var collector = _main.collector
	_check(is_instance_valid(collector) and get_tree().paused, "the Collector opens and pauses for the failure-detail regression")
	if not is_instance_valid(collector):
		return
	var reason := "STORAGE_DIAGNOSTIC_" + "LONG_TOKEN_".repeat(40) + "END_SENTINEL"
	var retry := _collector_retry_note()
	collector._fail_detail = reason
	collector._note = retry
	collector._fail_scroll = 0
	collector._canvas.queue_redraw()
	await _frames(2)
	_check(collector._fail_detail == reason, "the full raw save reason is retained, not truncated")
	_check(collector._fail_count > 1, "the long diagnostic wraps into a scrollable detail block")
	_check(collector._note == retry and retry != "SAVE FAILED / NOTHING COMMITTED / ENTER RETRY", "the localized retry receipt stays beside the raw reason")
	if _capture:
		await _save_view("collector-failure-zh_TW-before")
	for step in collector._fail_count + 2:
		await _key(KEY_D)
	var settled: int = collector._fail_scroll
	await _key(KEY_D)
	_check(collector._fail_scroll == settled and settled > 0, "A/D reaches and holds the terminal diagnostic line")
	if _capture:
		await _save_view("collector-failure-zh_TW-after")
		TranslationServer.set_locale("en")
		collector._note = _collector_retry_note()
		collector._fail_scroll = 0
		collector._canvas.queue_redraw()
		await _frames(2)
		await _save_view("collector-failure-en-before")
		for step in collector._fail_count + 2:
			await _key(KEY_D)
		await _save_view("collector-failure-en-after")
		TranslationServer.set_locale("zh_TW")
	await _key(KEY_A)
	_check(collector._fail_scroll < settled, "A scrolls the diagnostic back")
	await _key(KEY_DOWN)
	_check(collector._fail_detail.is_empty() and collector._note.is_empty() and collector._fail_scroll == 0, "changing the selected row clears the failure state")
	await _key(KEY_ESCAPE)
	await _frames(2)
	_check(not is_instance_valid(_main.collector) and not get_tree().paused, "the real Back key closes the Collector and resumes the tree")


## Display-only evidence: the real Main page is captured in both locales, and
## the production text path (MathArt.ui_text with ContentText strings) is
## rasterised separately, so a surface - not a key list - proves glyph ink.
func _capture_surfaces() -> void:
	# skip_title boots the world but not the hub page; enter it so the real
	# services, wallet and HUD are what the frame proves.
	_main.enter_hub()
	TranslationServer.set_locale("zh_TW")
	# enter_hub fades in from black; wait out the 0.24s reveal before pixels.
	await get_tree().create_timer(0.4).timeout
	await _frames(2)
	var zh_page: Image = await _save_view("hub-keyboard-zh_TW")
	var zh_image: Image = await _render_text(_surface_line())
	zh_image.save_png(ProjectSettings.globalize_path(OUTPUT_DIR + "/surface-keyboard-zh_TW.png"))
	TranslationServer.set_locale("en")
	await _frames(2)
	var en_page: Image = await _save_view("hub-keyboard-en")
	var en_image: Image = await _render_text(_surface_line())
	en_image.save_png(ProjectSettings.globalize_path(OUTPUT_DIR + "/surface-keyboard-en.png"))
	_check(zh_image.get_size() == en_image.get_size(), "both locale surfaces render at the same size")
	_check(_ink_pixels(zh_page) > 500, "the real zh_TW page renders visible content")
	_check(_ink_pixels(en_page) > 500, "the real en page renders visible content")
	_check(_ink_pixels(zh_image) > 80, "rendered zh_TW text has visible glyph ink")
	_check(_ink_pixels(en_image) > 80, "rendered en text has visible glyph ink")
	_check(_changed_pixels(zh_image, en_image) > 80, "the rendered text surface changes between zh_TW and en")
	TranslationServer.set_locale("zh_TW")
	_check(_surface_line().contains("細胞") and _surface_line().contains("鍛造"), "the drawn zh_TW line uses translated labels")
	await _send(_pad_button(JOY_BUTTON_DPAD_DOWN, true))
	await _pad_up(JOY_BUTTON_DPAD_DOWN)
	_check(Interface.active_device == Interface.DEVICE_GAMEPAD, "the hub capture follows a real gamepad press")
	await _save_view("hub-gamepad-zh_TW")
	await _key(KEY_F)
	_check(Interface.active_device == Interface.DEVICE_KEYBOARD, "a real key retakes the hub prompts")
	for entry in [["upgrade", "hub-upgrade"], ["archive", "hub-archive"], ["skill", "hub-skill"]]:
		_main._on_station_opened(str(entry[0]))
		await _frames(2)
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("%s-%s" % [entry[1], locale])
		_present_locale("zh_TW")
		await _frames(2)
		await _key(KEY_ESCAPE)
		await _frames(3)
		_check(not _main._any_panel_open(), "the %s page closes with real Back" % entry[0])


## A line built exactly as the pages build theirs: the display seam first, the
## fallback English second, so a missing row is visible as English on screen.
func _surface_line() -> String:
	return "%s  %s  %s" % [
		ContentText.of("UI_UNIT_CELLS", "Cells"),
		ContentText.name("service", "forge", "Forge"),
		ContentText.of("UI_ENTERING_PASSAGE", "ENTERING PASSAGE"),
	]


func _render_text(line: String) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(520, 96)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var face := TextFace.new(line)
	viewport.add_child(face)
	await _frames(2)
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image


func _save_view(label: String) -> Image:
	await _frames(2)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUTPUT_DIR + "/" + label + ".png"))
	return image


## Motion frames are named with the elapsed wall-clock time measured *after*
## the frame was rendered, so a saved sequence cannot relabel a static image.
func _motion_wait(start_ms: int, target_ms: int) -> void:
	while Time.get_ticks_msec() - start_ms < target_ms:
		await get_tree().process_frame


func _motion_position(canvas: Control, start_ms: int, target_ms: int) -> float:
	await _motion_wait(start_ms, target_ms)
	return canvas.position.y


func _motion_progress(canvas: Control, start_ms: int, target_ms: int) -> float:
	await _motion_wait(start_ms, target_ms)
	return float(canvas.get_meta("ui_focus_progress", 1.0))


func _motion_view(label: String, start_ms: int, target_ms: int) -> void:
	await _motion_wait(start_ms, target_ms)
	await RenderingServer.frame_post_draw
	var elapsed := Time.get_ticks_msec() - start_ms
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUTPUT_DIR + "/%s-t%03dms.png" % [label, elapsed])
	image.save_png(path)
	print("UI MOTION %s measured_t=%dms frame=%d" % [label, elapsed, Engine.get_frames_drawn()])


## Headless glyph truth from the shipped face: the cmap must contain the
## character and the face must give it a positive advance. Rendered ink is
## checked on the visible page and on the rasterised text surface instead.
func _glyph_advance(font: Font, character: String) -> float:
	if not font.has_char(character.unicode_at(0)):
		return 0.0
	var advance := font.get_char_size(character.unicode_at(0), 20)
	if advance.x <= 0.0 or advance.y <= 0.0:
		return 0.0
	return advance.x


func _ink_pixels(image: Image) -> int:
	if image == null or image.is_empty():
		return 0
	var ink := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).get_luminance() > 0.15:
				ink += 1
	return ink


func _changed_pixels(a: Image, b: Image) -> int:
	if a == null or b == null or a.is_empty() or b.is_empty() or a.get_size() != b.get_size():
		return 0
	var changed := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				changed += 1
	return changed


func _is_character_break(value: String, index: int) -> bool:
	var breaks := TextServerManager.get_primary_interface().string_get_character_breaks(value)
	return index == 0 or breaks.has(index)


func _single_grapheme(value: String) -> bool:
	var breaks := TextServerManager.get_primary_interface().string_get_character_breaks(value)
	return breaks.size() <= 1


func _compact(value: String) -> String:
	return value.replace(" ", "").replace("\n", "").replace("\r", "").replace("\t", "")


func _is_combining(character: String) -> bool:
	if character.is_empty():
		return false
	var code := character.unicode_at(0)
	return (code >= 0x0300 and code <= 0x036F) or (code >= 0x1AB0 and code <= 0x1AFF) \
		or (code >= 0x1DC0 and code <= 0x1DFF) or (code >= 0xFE20 and code <= 0xFE2F) \
		or (code >= 0xFE00 and code <= 0xFE0F) or code == 0x200D


func _starts_with_any(value: String, marks: String) -> bool:
	return not value.is_empty() and marks.contains(value.substr(0, 1))


func _ends_with_any(value: String, marks: String) -> bool:
	return not value.is_empty() and marks.contains(value.substr(value.length() - 1, 1))


func _has_whole_word(lines: Array[String], word: String) -> bool:
	for line: String in lines:
		if _contains_word(line, word):
			return true
	return false


func _contains_word(value: String, word: String) -> bool:
	var lowered := value.to_lower()
	var target := word.to_lower()
	var from := 0
	while true:
		var at := lowered.find(target, from)
		if at < 0:
			return false
		var before := lowered.substr(at - 1, 1) if at > 0 else ""
		var after := lowered.substr(at + target.length(), 1)
		if (before.is_empty() or not _is_word_char(before)) and (after.is_empty() or not _is_word_char(after)):
			return true
		from = at + target.length()
	return false


func _is_word_char(character: String) -> bool:
	if character.is_empty():
		return false
	var code := character.unicode_at(0)
	return (code >= 0x61 and code <= 0x7A) or (code >= 0x41 and code <= 0x5A) \
		or (code >= 0x30 and code <= 0x39) or code == 0x5F


func _has_cjk(value: String) -> bool:
	for index in value.length():
		var code := value.unicode_at(index)
		if (code >= 0x3400 and code <= 0x9FFF) or (code >= 0xF900 and code <= 0xFAFF):
			return true
	return false


func _sample(values: PackedStringArray) -> String:
	var first := PackedStringArray()
	for index in mini(values.size(), 3):
		first.append(values[index])
	return "%d issue(s): %s" % [values.size(), ", ".join(first)]


func _key(code: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame


func _key_event(code: int, pressed: bool, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	return event


func _pad_button(index: int, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = pressed
	event.device = 0
	return event


func _pad_motion(axis: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	event.device = 0
	return event


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	await get_tree().process_frame


func _pad_tap(index: int) -> void:
	await _send(_pad_button(index, true))
	await _send(_pad_button(index, false))
	await _frames(2)


func _pad_down(index: int) -> void:
	await _send(_pad_button(index, true))


func _pad_up(index: int) -> void:
	await _send(_pad_button(index, false))


func _stick(axis: int, value: float) -> void:
	await _send(_pad_motion(axis, value))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _on_presentation_changed() -> void:
	_presentation_changed += 1


## The fixed Interface contract: prompts follow meaningful input, while drift,
## release and a still-held axis never reset focus or re-fire. Every pressed()
## assertion here is a real parsed event observed by a live page; unparsed
## direct calls are not consumer proof.
func _check_input_api() -> void:
	if not Interface.presentation_changed.is_connected(_on_presentation_changed):
		Interface.presentation_changed.connect(_on_presentation_changed)
	await _key(KEY_F)
	var keyboard_prompt := Interface.prompt(&"ui_accept")
	_check(not keyboard_prompt.is_empty() and keyboard_prompt != "—", "the keyboard accept prompt is visible")
	var changes := _presentation_changed
	await _stick(JOY_AXIS_LEFT_Y, 0.1)
	_check(Interface.prompt(&"ui_accept") == keyboard_prompt and _presentation_changed == changes, "axis drift never changes the prompt or device")
	await _stick(JOY_AXIS_LEFT_Y, 0.8)
	_check(Interface.prompt(&"ui_accept") != keyboard_prompt and _presentation_changed == changes + 1, "a real gamepad axis switches the prompt once")
	await _stick(JOY_AXIS_LEFT_Y, 0.0)
	await _key(KEY_F)
	_check(Interface.prompt(&"ui_accept") == keyboard_prompt, "a real keyboard event takes the prompt back")
	Interface.apply_preferences({"general": {"locale": "zh_TW"}, "input": {"keyboard": {"jump": KEY_K}, "gamepad": {"jump": {"type": "button", "index": JOY_BUTTON_Y}}}})
	Interface.apply_preferences({"general": {"locale": "zh_TW"}, "input": {"keyboard": {"jump": KEY_K}, "gamepad": {"jump": {"type": "button", "index": JOY_BUTTON_Y}}}})
	_check(TranslationServer.get_locale() == "zh_TW", "applying the same preferences twice keeps the zh_TW locale")
	Interface.apply_preferences({"general": {"locale": "zh_TW"}, "input": {"keyboard": {}, "gamepad": {}}})
	_check(TranslationServer.get_locale() == "zh_TW" and not Interface.prompt(&"ui_accept").is_empty(), "restoring default input keeps the locale and a visible prompt")


## Title and Saves through real pad events. A duplicate pressed event without a
## release must not become a second confirmation; keyboard retake must not move
## the focused action or the focused slot.
func _check_title_pad() -> void:
	_main.return_to_title()
	await _frames(4)
	var title = _main.title_screen
	_check(is_instance_valid(title) and get_tree().paused, "the title is modal and pauses the tree")
	if not is_instance_valid(title):
		return
	_check(str(title._view) == "saves", "the pause-title opens on the save strip")
	await _pad_tap(JOY_BUTTON_B)
	_check(str(title._view) == "main", "pad B returns from the save strip")
	var summary: Dictionary = Profile.slot_summary(Profile.active_slot)
	var slot_label := Hud.slot_label(summary)
	_check(not slot_label.contains("PROTECTED") and not slot_label.contains("CHECKPOINT") and not slot_label.contains("EMPTY"), "the title slot label never leaks a machine state")
	# Slot-state captures: the damaged / newer-version / empty files are written
	# through the isolated profile's own path and restored afterwards. The slot
	# cards live on the save strip, so the fixture shows that real view.
	title._view = "saves"
	title.queue_redraw()
	await _frames(2)
	if _capture:
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("title-slot-checkpoint-%s" % locale)
		_present_locale("zh_TW")
		await _frames(2)
	var other_slot := 1 if Profile.active_slot != 1 else 2
	var other_path := Profile.slot_path(other_slot)
	var other_had := FileAccess.file_exists(other_path)
	var other_original := FileAccess.get_file_as_string(other_path) if other_had else ""
	title._slot = other_slot - 1
	for state in ["damaged", "newer", "empty"]:
		match state:
			"damaged":
				_write_text(other_path, "{ not json")
			"newer":
				_write_text(other_path, JSON.stringify({"version": int(Profile.VERSION) + 1, "run_checkpoint": {}}))
			"empty":
				DirAccess.remove_absolute(ProjectSettings.globalize_path(other_path))
		title.queue_redraw()
		await _frames(2)
		if _capture:
			for locale in ["zh_TW", "en"]:
				_present_locale(locale)
				await _frames(2)
				await _save_view("title-slot-%s-%s" % [state, locale])
			_present_locale("zh_TW")
			await _frames(2)
	if other_had:
		_write_text(other_path, other_original)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(other_path))
	title._slot = Profile.active_slot - 1
	title._view = "main"
	title.queue_redraw()
	await _frames(2)

	var title_runs: int = Profile.runs
	var title_guard := 0
	while int(title._action) != 3 and title_guard < 8:
		await _pad_tap(JOY_BUTTON_DPAD_DOWN)
		title_guard += 1
	_check(int(title._action) == 3, "the title Settings row is reachable with the D-pad")
	if int(title._action) != 3:
		return
	var title_focus := int(title._action)
	await _pad_tap(JOY_BUTTON_A)
	await _frames(3)
	var title_settings = _main.settings_screen
	_check(is_instance_valid(title_settings) and title_settings.is_open(), "the title's Settings row opens the single settings page")
	if not is_instance_valid(title_settings) or not title_settings.is_open():
		return
	_check(get_tree().paused and bool(title._open), "opening settings from the title never unpauses it")
	_check(title_settings.committed == Profile.preferences, "settings opens on the committed preferences")
	await _settings_cycle(title_settings, "gamepad", "title-zh")
	await _pad_tap(JOY_BUTTON_B)
	await _frames(2)
	_check(not title_settings.is_open() and bool(title._open) and get_tree().paused,
		"pad B closes settings and returns to the still-paused title")
	_check(int(title._action) == title_focus, "closing settings restores the title's own focus")
	_check(Profile.runs == title_runs, "closing settings never starts a run or falls through to gameplay")

	await _key(KEY_ENTER)
	await _frames(3)
	_check(title_settings.is_open(), "the title's Settings row also opens from Enter")
	await _settings_cycle(title_settings, "keyboard", "title-keyboard-zh")
	await _key(KEY_ESCAPE)
	await _frames(2)
	_check(not title_settings.is_open() and bool(title._open) and get_tree().paused,
		"Esc closes settings and returns to the still-paused title")
	_check(int(title._action) == title_focus, "keyboard close also keeps the title focus")
	_check(Profile.runs == title_runs, "keyboard close cannot fall through to an attack or a new run")

	var ray := int(title._action)
	await _stick(JOY_AXIS_LEFT_Y, 0.1)
	_check(int(title._action) == ray, "axis drift 0.1 never moves the title focus")
	await _stick(JOY_AXIS_LEFT_Y, 0.5)
	_check(int(title._action) == ray, "axis 0.5 stays inside the dead band")
	await _stick(JOY_AXIS_LEFT_Y, 0.6)
	_check(int(title._action) == wrapi(ray + 1, 0, 5), "axis crossing 0.6 moves exactly one step")
	await _stick(JOY_AXIS_LEFT_Y, 0.6)
	_check(int(title._action) == wrapi(ray + 1, 0, 5), "a held axis does not repeat focus")
	await _stick(JOY_AXIS_LEFT_Y, 0.3)
	await _stick(JOY_AXIS_LEFT_Y, 0.6)
	_check(int(title._action) == wrapi(ray + 1, 0, 5), "a held axis stays latched above neutral")
	await _stick(JOY_AXIS_LEFT_Y, 0.25)
	await _stick(JOY_AXIS_LEFT_Y, 0.2)
	await _stick(JOY_AXIS_LEFT_Y, 0.6)
	_check(int(title._action) == wrapi(ray + 2, 0, 5), "neutral 0.2 re-arms the next crossing once")
	await _stick(JOY_AXIS_LEFT_Y, 0.0)

	var echo_focus := int(title._action)
	await _send(_key_event(KEY_DOWN, true))
	await _send(_key_event(KEY_DOWN, true, true))
	await _send(_key_event(KEY_DOWN, false))
	_check(int(title._action) == wrapi(echo_focus + 1, 0, 5), "keyboard echo and release never move focus twice")
	await _key(KEY_F)
	var keyboard_prompt := Interface.prompt(&"ui_accept")
	var focus_before := int(title._action)
	await _pad_tap(JOY_BUTTON_DPAD_DOWN)
	_check(int(title._action) == wrapi(focus_before + 1, 0, 5), "pad down moves the title focus once")
	var focused := int(title._action)
	_check(Interface.prompt(&"ui_accept") != keyboard_prompt, "the pad accept prompt differs from the keyboard prompt")
	if _capture:
		await _wait(0.16)
		await _save_view("title-gamepad-zh_TW")
	await _key(KEY_F)
	_check(int(title._action) == focused, "keyboard retake keeps the title focus")
	_check(Interface.prompt(&"ui_accept") == keyboard_prompt, "keyboard retake restores the keyboard prompt")
	if _capture:
		await _save_view("title-keyboard-zh_TW")
		_present_locale("en")
		await _frames(2)
		await _save_view("title-keyboard-en")
		_present_locale("zh_TW")
		await _frames(2)
	while int(title._action) != 2:
		await _pad_tap(JOY_BUTTON_DPAD_DOWN)
	await _pad_down(JOY_BUTTON_A)
	await _frames(5)
	_check(str(title._view) == "saves", "a held accept opens the save strip")
	await _send(_pad_button(JOY_BUTTON_A, true))
	await _frames(4)
	_check(str(title._view) == "saves" and is_instance_valid(title), "a duplicate A press without release does not choose a slot")
	await _pad_up(JOY_BUTTON_A)
	await _frames(2)
	_check(str(title._view) == "saves" and get_tree().paused, "releasing the held accept still does not choose a slot")
	var slot := int(title._slot)
	await _pad_tap(JOY_BUTTON_DPAD_RIGHT)
	_check(int(title._slot) == wrapi(slot + 1, 0, Profile.SLOT_COUNT), "pad right moves the save focus")
	var slot_now := int(title._slot)
	await _key(KEY_F)
	_check(int(title._slot) == slot_now, "keyboard retake keeps the save focus")
	await _pad_tap(JOY_BUTTON_A)
	await _wait(0.5)
	_check(Profile.active_slot == slot_now + 1 and not is_instance_valid(_main.title_screen) and Game.in_hub, "a fresh pad accept selects the focused save and enters the hub")


func _check_hub_pad() -> void:
	var hub = _main.hub
	_check(is_instance_valid(hub) and is_instance_valid(hub.player), "the hub is live after the title hand-off")
	if not is_instance_valid(hub) or not is_instance_valid(hub.player):
		return
	await _frames(3)
	var start_x: float = hub.player.position.x
	await _pad_down(JOY_BUTTON_DPAD_LEFT)
	await _wait(0.25)
	await _pad_up(JOY_BUTTON_DPAD_LEFT)
	_check(hub.player.position.x < start_x - 4.0, "the D-pad moves the hub body")

	Profile.cells = 300
	hub.player.position = Vector2(210, -40)
	await _frames(3)
	await _pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(3)
	_check(hub.ui.is_open() and str(hub.ui._open_id) == "upgrade", "RB opens the upgrade page at its station")
	var rows: Array = hub.ui.call("_rows")
	if rows.size() > 1:
		await _pad_tap(JOY_BUTTON_DPAD_DOWN)
		_check(int(hub.ui._index) == 1, "pad down moves the upgrade focus")
	var cells_before: int = Profile.cells
	await _pad_tap(JOY_BUTTON_A)
	_check(Profile.cells != cells_before or not str(hub.ui._note).is_empty(), "pad accept buys or reports the upgrade blocker")
	await _pad_tap(JOY_BUTTON_B)
	await _frames(3)
	_check(not hub.ui.is_open(), "pad B closes the upgrade page")
	_check(hub.player.is_physics_processing(), "closing the page restores hub movement")

	hub.player.position = Vector2(830, -40)
	await _frames(3)
	await _pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(3)
	var archive = _main.archive
	_check(is_instance_valid(archive) and archive.is_open() and str(archive._tab) == "enemy", "RB opens Archives at its station")
	if is_instance_valid(archive):
		# Long-record fixture: real wrapped detail exceeds the six visible rows,
		# so the right stick and the X detail focus have somewhere to scroll.
		var long_id := str(archive._ids[0])
		var long_cfg: Dictionary = Data.enemies[long_id]
		var saved_cfg := long_cfg.duplicate(true)
		var was_seen := Profile.seen_enemies.has(long_id)
		if not was_seen:
			Profile.seen_enemies.append(long_id)
		long_cfg["hp"] = 1.2345678901234567e29
		long_cfg["damage"] = 9.8765432109876543e28
		long_cfg["speed"] = 8.7654321098765432e28
		long_cfg["attack_range"] = 7.6543210987654321e28
		long_cfg["windup"] = 6.5432109876543210e28
		long_cfg["active"] = 5.4321098765432109e28
		long_cfg["recovery"] = 4.3210987654321098e28
		long_cfg["cells"] = 999999999
		archive._index = 0
		archive._detail_scroll = 0
		archive._canvas.queue_redraw()
		await _frames(2)
		await _stick(JOY_AXIS_RIGHT_Y, 0.0)
		await _stick(JOY_AXIS_RIGHT_Y, 1.0)
		await _stick(JOY_AXIS_RIGHT_Y, 0.0)
		await _frames(2)
		_check(int(archive._detail_scroll) > 0, "right stick scrolls the record detail without a focus toggle")
		await _key(KEY_X)
		_check(bool(archive._detail_focus), "X opens the record detail focus")
		var record_index: int = archive._index
		var scrolled: int = archive._detail_scroll
		await _key(KEY_UP)
		_check(int(archive._index) == record_index and int(archive._detail_scroll) == scrolled - 1, "X then U scrolls the detail without moving the record")
		await _key(KEY_DOWN)
		_check(int(archive._detail_scroll) == scrolled, "X then D scrolls the detail back")
		await _key(KEY_X)
		_check(not bool(archive._detail_focus), "X returns to record focus")
		await _key(KEY_DOWN)
		_check(int(archive._index) == record_index + 1, "X toggles back to record focus for U/D navigation")
		Data.enemies[long_id] = saved_cfg
		if not was_seen:
			Profile.seen_enemies.erase(long_id)
		var tab := str(archive._tab)
		await _pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
		_check(str(archive._tab) != tab, "RB pages the archive category")
		await _pad_tap(JOY_BUTTON_A)
		_check(not str(archive._note).is_empty(), "pad accept equips or reports the record")
		await _pad_tap(JOY_BUTTON_B)
		await _frames(3)
		_check(not archive.is_open(), "pad B closes Archives from either focus")

	hub.player.position = Vector2(520, -40)
	await _frames(3)
	await _pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(3)
	var tree = _main.skill_tree
	_check(is_instance_valid(tree) and tree.is_open(), "RB opens the Skill tree at its station")
	if is_instance_valid(tree):
		var first := int(tree._index)
		_check(str(tree._ids[first]) == "root_edge", "a fresh tree starts on the first available node")
		Profile.cells = 300
		await _pad_tap(JOY_BUTTON_A)
		_check(Profile.has_skill("root_edge"), "pad accept learns the focused skill")
		await _pad_tap(JOY_BUTTON_DPAD_RIGHT)
		_check(int(tree._index) != first or tree._ids.size() <= 1, "pad nav moves the tree focus")
		await _pad_tap(JOY_BUTTON_B)
		await _frames(3)
		_check(not tree.is_open(), "pad B closes the Skill tree")


## STEP6: a long save diagnostic on Archive and Skill Tree stays reachable in
## the existing scrollable detail, while the visible receipt never carries the
## raw reason; a row change clears the state.
func _check_meta_failure_detail() -> void:
	var token := "STORAGE_FAILURE_" + "LONG_RECORD_TOKEN_".repeat(14) + "END_SENTINEL"
	var blocked_before := bool(Profile._save_blocked)
	var cells_before: int = Profile.cells
	var error_before := str(Profile.last_save_error)
	Profile._save_blocked = true
	Profile.cells = 99999
	_main._on_station_opened("archive")
	await _frames(3)
	var archive = _main.archive
	_check(is_instance_valid(archive) and archive.is_open(), "the archive opens for the failure detail")
	if is_instance_valid(archive):
		await _pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
		_check(str(archive._tab) == "weapon", "the archive failure fixture opens the weapon tab")
		var target := -1
		for index in archive._ids.size():
			var candidate := str(archive._ids[index])
			var price := int((Data.weapons.get(candidate, {}) as Dictionary).get("unlock_cost", 0))
			if not Profile.is_unlocked("weapon", candidate) and Profile.gear_blueprint(candidate).is_empty() \
				and price > 0 and Profile.cells >= price:
				target = index
				break
		_check(target >= 0, "a purchasable non-blueprint weapon exists for the real write attempt")
		if target < 0:
			Profile._save_blocked = blocked_before
			Profile.cells = cells_before
			Profile.last_save_error = error_before
			return
		archive._index = target
		var selected := str(archive._ids[target])
		_check(Profile.gear_blueprint(selected).is_empty()
			and not Profile.is_unlocked("weapon", selected)
			and int((Data.weapons[selected] as Dictionary).get("unlock_cost", 0)) > 0,
			"the selected weapon takes the real unlock branch, not the blueprint branch")
		await _pad_tap(JOY_BUTTON_A)
		_check(bool(archive._failed) and not str(archive._fail_reason).is_empty()
			and str(archive._fail_reason) == str(Profile.last_save_error),
			"the archive failure reads the real Profile diagnostic")
		var receipt := str(archive._note_display())
		var expected_receipt := ContentText.of("UI_S6_SAVE_FAILED_FIXED", "NOT SAVED / {action} RETRY / reason in detail pane").format({"action": Interface.prompt(&"ui_accept")})
		_check(receipt == expected_receipt and not receipt.contains("END_SENTINEL"),
			"the archive receipt is the fixed localized line, not the raw reason")
		archive._fail_reason = token
		archive._note = "SAVE FAILED: " + token
		archive._detail_scroll = 0
		archive._canvas.queue_redraw()
		await _frames(2)
		var copy: Dictionary = archive._record_copy(str(archive._ids[archive._index]))
		var details: Array = copy.get("details", [])
		var full_reason := "".join(details)
		_check(details.size() > 6 and full_reason.contains("END_SENTINEL"),
			"the archive detail carries the full reason in wrapped lines (lines=%d tail=%s)" % [details.size(), str(details[details.size() - 1]) if not details.is_empty() else ""])
		if _capture:
			await _save_view("archive-save-failure-zh_TW-before")
		await _key(KEY_X)
		_check(bool(archive._detail_focus), "X focuses the archive detail pane")
		for step in details.size():
			if int(archive._detail_scroll) >= maxi(0, details.size() - 6):
				break
			await _key(KEY_DOWN)
		_check(int(archive._detail_scroll) == maxi(0, details.size() - 6) and int(archive._detail_scroll) > 0,
			"real detail input reaches the last row of the full reason")
		if _capture:
			await _save_view("archive-save-failure-zh_TW-after")
		await _key(KEY_X)
		await _key(KEY_DOWN)
		_check(not bool(archive._failed) and str(archive._fail_reason).is_empty(),
			"changing the archive row clears the failure state")
		await _pad_tap(JOY_BUTTON_B)
		await _frames(3)
		_check(not archive.is_open(), "Back closes the archive after the failure detail")
	Profile.cells = maxi(cells_before, 99999)
	Profile.last_save_error = ""
	_main._on_station_opened("skill")
	await _frames(3)
	var tree = _main.skill_tree
	_check(is_instance_valid(tree) and tree.is_open(), "the skill tree opens for the failure detail")
	if is_instance_valid(tree):
		var target := -1
		for index in tree._ids.size():
			var node_id := str(tree._ids[index])
			var node_cfg: Dictionary = Data.skill_nodes.get(node_id, {})
			var node_cost := maxi(0, int(node_cfg.get("cost", 40)))
			if not Profile.has_skill(node_id) and Profile.skill_available(node_id) \
				and node_cost > 0 and int(Profile.cells) >= node_cost:
				target = index
				break
		_check(target >= 0, "a purchasable unlearned skill with met prerequisites exists for the real write attempt")
		if target >= 0:
			var skill_id := str(tree._ids[target])
			_check(Profile.skill_available(skill_id)
				and not Profile.has_skill(skill_id)
				and int(Profile.cells) >= maxi(0, int((Data.skill_nodes.get(skill_id, {}) as Dictionary).get("cost", 40))),
				"the selected skill passes the canonical purchase gate")
			tree._index = target
			await _pad_tap(JOY_BUTTON_A)
			_check(bool(tree._failed) and not str(tree._fail_reason).is_empty()
				and str(tree._fail_reason) == str(Profile.last_save_error),
				"the skill-tree failure reads the real Profile diagnostic")
			var receipt := str(tree._note_display())
			var expected_receipt := ContentText.of("UI_S6_SAVE_FAILED_FIXED", "NOT SAVED / {action} RETRY / reason in detail pane").format({"action": Interface.prompt(&"ui_accept")})
			_check(receipt == expected_receipt and not receipt.contains("END_SENTINEL"),
				"the skill-tree receipt is the fixed localized line, not the raw reason")
			tree._fail_reason = token
			tree._note = "SAVE FAILED: " + token
			tree._fail_scroll = 0
			tree._canvas.queue_redraw()
			await _frames(2)
			var wrapped := MathArt.ui_wrap(ContentText.of("UI_S6_FAIL_DETAIL", "NOT SAVED / DIAGNOSTIC") + "\n" + token, 220, 13)
			_check(int(tree._fail_count) == wrapped.size() and wrapped.size() > 7
				and "".join(wrapped).contains("END_SENTINEL"),
				"the skill-tree failure pane wraps the retained tail (%d lines, tail=%s)" % [wrapped.size(), str(wrapped[wrapped.size() - 1])])
			if _capture:
				await _save_view("skill-save-failure-zh_TW-before")
			var guard := 0
			while int(tree._fail_scroll) < maxi(0, int(tree._fail_count) - 7) and guard < wrapped.size():
				await _key(KEY_DOWN)
				guard += 1
			_check(int(tree._fail_scroll) == maxi(0, int(tree._fail_count) - 7) and int(tree._fail_scroll) > 0,
				"real detail input reaches the last row of the skill diagnostic")
			if _capture:
				await _save_view("skill-save-failure-zh_TW-after")
			var before_node := int(tree._index)
			for direction in [JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP]:
				if int(tree._index) != before_node:
					break
				await _pad_tap(direction)
			_check(int(tree._index) != before_node and not bool(tree._failed) and str(tree._fail_reason).is_empty(),
				"changing the skill node clears the failure state")
		await _pad_tap(JOY_BUTTON_B)
		await _frames(3)
		_check(not tree.is_open(), "Back closes the skill tree after the failure detail")
	Profile._save_blocked = blocked_before
	Profile.cells = cells_before
	Profile.last_save_error = error_before


func _wait_ground() -> void:
	for _index in 120:
		if is_instance_valid(Game.player) and Game.player.is_on_floor() and Game.player.state != Player.State.AIR:
			return
		await get_tree().process_frame


func _jump_with(kind: String) -> bool:
	await _wait_ground()
	var player = Game.player
	if not is_instance_valid(player):
		return false
	var start_y: float = player.position.y
	await _send(_key_event(KEY_W, true))
	await _frames(2)
	match kind:
		"pad_a":
			await _pad_tap(JOY_BUTTON_A)
		"pad_y":
			await _pad_tap(JOY_BUTTON_Y)
		"space":
			await _send(_key_event(KEY_SPACE, true))
			await _send(_key_event(KEY_SPACE, false))
		"key_k":
			await _send(_key_event(KEY_K, true))
			await _send(_key_event(KEY_K, false))
		"key_c":
			await _send(_key_event(KEY_C, true))
			await _send(_key_event(KEY_C, false))
	var low := start_y
	for _index in 14:
		await get_tree().process_frame
		low = minf(low, player.position.y)
	await _send(_key_event(KEY_W, false))
	return low <= start_y - 4.0


## Live gameplay: explicit jump, no up-stick jump, LT/RT defaults, View and
## Start, plus the gamepad/keyboard captures for pause and map.
func _check_gameplay_pad() -> void:
	_main.start_node(str(Data.route_graph.start))
	await _wait(0.6)
	_check(Game.run_phase == "biome" and Game.build != null and is_instance_valid(Game.player), "a biome run starts for gameplay input")
	if not is_instance_valid(Game.player):
		return
	_check(await _jump_with("pad_a"), "pad A jumps while climb-up is held")
	_check(await _jump_with("space"), "Space jumps while climb-up is held")

	Interface.apply_preferences({"input": {"keyboard": {"jump": KEY_K}, "gamepad": {"jump": {"type": "button", "index": JOY_BUTTON_Y}}}})
	_check(await _jump_with("key_k"), "a rebound keyboard jump works while climbing")
	_check(await _jump_with("pad_y"), "a rebound pad jump works while climbing")
	var space_after: bool = await _jump_with("space")
	_check(not space_after, "the replaced Space binding no longer jumps")
	Interface.apply_preferences({})

	# The native rebuild must not leave a held, now-replaced key stuck on jump.
	await _wait_ground()
	await _send(_key_event(KEY_SPACE, true))
	await _frames(2)
	Interface.apply_preferences({"input": {"keyboard": {"jump": KEY_C}, "gamepad": {"jump": {"type": "button", "index": JOY_BUTTON_Y}}}})
	await _send(_key_event(KEY_SPACE, false))
	await _frames(2)
	_check(not Input.is_action_pressed(&"jump"), "releasing a replaced held Space does not leave jump stuck")
	_check(await _jump_with("key_c"), "the new C jump still works after the held old key")
	_check(await _jump_with("pad_y"), "the new pad Y jump still works after the held old key")
	Interface.apply_preferences({})
	_check(await _jump_with("space"), "restoring defaults restores the Space jump")

	await _wait_ground()
	await _stick(JOY_AXIS_LEFT_Y, -1.0)
	await _frames(16)
	_check(not Input.is_action_pressed(&"jump") and Game.player.state != Player.State.AIR, "up stick never presses jump")
	await _stick(JOY_AXIS_LEFT_Y, 0.0)

	await _wait_ground()
	await _stick(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await _frames(4)
	await _stick(JOY_AXIS_TRIGGER_LEFT, 0.0)
	_check(int(Game.player.weapon_slot) == 1, "LT selects the second weapon slot")
	_check(Game.player.guard_t > 0.0, "LT raises the shield guard")

	await _wait_ground()
	Game.player.hp = Game.player.max_hp * 0.5
	Game.flask_capacity = maxi(1, Game.flask_capacity)
	Game.flask_charges = Game.flask_capacity
	var charges := Game.flask_charges
	await _stick(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _frames(4)
	await _stick(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_check(Game.player.hp > Game.player.max_hp * 0.5 and Game.flask_charges == charges - 1, "RT heals once and spends one flask charge")

	var node: String = Game.run_node_id
	await _pad_tap(JOY_BUTTON_BACK)
	await _frames(3)
	_check(_main.exploration_map.is_open() and get_tree().paused, "View opens the map")
	var tab = _main.exploration_map._tab
	await _stick(JOY_AXIS_LEFT_X, 1.0)
	await _frames(3)
	await _stick(JOY_AXIS_LEFT_X, 0.0)
	_check(_main.exploration_map._tab != tab, "left stick switches the map tab")
	if _capture:
		await _wait(0.16)
		await _save_view("map-gamepad-zh_TW")
	var map_tab = _main.exploration_map._tab
	await _key(KEY_F)
	_check(_main.exploration_map._tab == map_tab, "keyboard retake keeps the map focus")
	if _capture:
		await _save_view("map-keyboard-zh_TW")
	await _pad_tap(JOY_BUTTON_B)
	await _frames(2)
	_check(not _main.exploration_map.is_open() and not get_tree().paused and Game.run_node_id == node, "pad B closes the map without restarting")

	await _pad_tap(JOY_BUTTON_START)
	await _frames(3)
	_check(_main.hud.paused and get_tree().paused, "Start pauses the live run")
	if _capture:
		await _wait(0.16)
		await _save_view("pause-gamepad-zh_TW")
	var pause_index: int = _main.hud._pause_index
	await _pad_tap(JOY_BUTTON_DPAD_RIGHT)
	_check(int(_main.hud._pause_index) == wrapi(pause_index + 1, 0, 5), "pad right moves the pause gear focus")
	await _key(KEY_F)
	_check(int(_main.hud._pause_index) == wrapi(pause_index + 1, 0, 5), "keyboard retake keeps the pause gear focus")
	if _capture:
		await _wait(0.16)
		await _save_view("pause-keyboard-zh_TW")
	await _check_pause_settings(node)
	_check(_main.hud.paused and get_tree().paused,
		"closing settings returns to the still-paused game")
	await _pad_tap(JOY_BUTTON_B)
	await _frames(2)
	_check(not _main.hud.paused and not get_tree().paused, "pad B closes the pause overlay after settings")
	var live_node: String = Game.run_node_id
	await _pad_tap(JOY_BUTTON_B)
	await _frames(3)
	_check(Game.run_node_id == live_node and not get_tree().paused and not Game.run_over, "B in live gameplay never restarts")


## STEP4 combat cluster and modal surface proof. The gear array is asserted by
## hud_readability_probe; here the real 768x480 render must show the separate
## flask/HP/axes/wallet/minimap surfaces, states and both locales, and a full
## page must paint no HUD pixels. Pixels come from the live product frame.
func _check_hud_surface() -> void:
	var hud: Control = _main.hud
	var build: RunBuild = Game.build
	var player: Player = Game.player
	if not is_instance_valid(hud) or build == null or not is_instance_valid(player):
		_check(false, "HUD surface fixture has a live build and player")
		return
	var hp := player.hp
	var flasks := Game.flask_charges
	var skill_charges: Array[int] = [int(build.slots[2].get("charges", 0)), int(build.slots[3].get("charges", 0))]
	var skill_cooldowns: Array[float] = [float(build.slots[2].get("cooldown", 0.0)), float(build.slots[3].get("cooldown", 0.0))]
	var commit_locale := str(Profile.preferences.general.locale)
	if _capture:
		_present_locale("zh_TW")
		await _frames(2)
		var with_hud := await _save_view("hud-surface-zh_TW")
		hud.visible = false
		await _frames(2)
		var without_hud := await _save_view("hud-surface-hidden-zh_TW")
		hud.visible = true
		for region in [
			["flask", Rect2(16, 362, 42, 56)],
			["gear", Rect2(66, 362, 248, 56)],
			["charm", Rect2(314, 362, 36, 56)],
			["axes", Rect2(16, 412, 334, 24)],
			["health", Rect2(16, 440, 334, 24)],
			["minimap", Rect2(588, 346, 164, 84)],
			["wallet", Rect2(554, 432, 198, 32)],
		]:
			_check(_region_difference(with_hud, without_hud, region[1]) > 20, "the live HUD paints the approved %s surface" % region[0])
		var gear_states := [
			["ready", int(build.definition(build.slots[2]).get("charges", 1)), 0.0],
			["partial", 1, float(build.cooldown(build.slots[2])) * 0.5],
			["empty", 0, float(build.cooldown(build.slots[2]))],
		]
		for state in gear_states:
			build.slots[2]["charges"] = int(state[1])
			build.slots[2]["cooldown"] = float(state[2])
			build.slots[3]["charges"] = int(state[1])
			build.slots[3]["cooldown"] = float(state[2])
			hud.queue_redraw()
			await _frames(2)
			for locale in ["zh_TW", "en"]:
				_present_locale(locale)
				await _frames(2)
				await _save_view("hud-%s-%s" % [state[0], locale])
		var old_boss = Game.boss
		var boss := Enemy.new()
		boss.kind = "bridge_sentinel"
		boss.cfg = {"name": "Bridge Sentinel"}
		boss.hp = 140.0
		boss.max_hp = 240.0
		Game.boss = boss
		hud.queue_redraw()
		await _frames(2)
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("hud-boss-%s" % locale)
		Game.boss = old_boss
		boss.free()
		hud.queue_redraw()
		await _frames(2)
	# Real Start opens pause; capture both locales and prove the HUD cannot leak
	# below the page panel (UI_PAGE ends at y=456, so samples sit below it).
	await _pad_tap(JOY_BUTTON_START)
	await _frames(3)
	_check(hud.paused and get_tree().paused, "pad Start pauses for the surface proof")
	if _capture:
		_present_locale("zh_TW")
		await _frames(2)
		var pause_with := await _save_view("pause-modal-zh_TW")
		hud.visible = false
		await _frames(2)
		var pause_world := await _save_view("pause-modal-world-zh_TW")
		hud.visible = true
		_check(_masked_region_matches(pause_with, pause_world, Rect2(16, 458, 334, 4)), "the pause page hides combat HUD outside its panel")
		_present_locale("en")
		await _frames(2)
		await _save_view("pause-modal-en")
		_present_locale("zh_TW")
		await _frames(2)
	# Abandon confirmation is the nearest layer, in both locales. The action
	# row moves left/right; down is detail scroll even while actions are focused.
	await _pad_tap(JOY_BUTTON_X)
	await _frames(1)
	for n in 3:
		await _pad_tap(JOY_BUTTON_DPAD_RIGHT)
	_check(int(hud._pause_action) == 3, "the action row reaches Abandon with real right input")
	await _pad_tap(JOY_BUTTON_A)
	await _frames(2)
	_check(hud._abandon_confirm and hud.paused, "the pause action row opens abandon confirmation")
	if _capture:
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("abandon-%s" % locale)
	await _pad_tap(JOY_BUTTON_B)
	await _frames(2)
	_check(not hud._abandon_confirm and hud.paused, "B returns to pause without leaving the run")
	# Settings is a separate full-page layer: with it open, hiding the HUD must
	# change zero pixels. This is the consumer-visible absence proof.
	if _capture:
		_main.settings_screen.open()
		await _wait(0.2)
		var page_with := await _save_view("settings-hud-hidden-zh_TW-with")
		hud.visible = false
		await _frames(2)
		var page_without := await _save_view("settings-hud-hidden-zh_TW-without")
		hud.visible = true
		_check(_image_difference(page_with, page_without) == 0, "the full-page settings layer paints no combat HUD pixels")
		_main.settings_screen.close()
		await _frames(2)
	_check(_main.settings_screen.is_open() == false and hud.paused and get_tree().paused, "closing settings returns to the paused game")
	await _pad_tap(JOY_BUTTON_B)
	await _frames(2)
	_check(not hud.paused and not get_tree().paused, "the HUD surface fixture resumes cleanly")
	_present_locale(commit_locale)
	build.slots[2]["charges"] = skill_charges[0]
	build.slots[2]["cooldown"] = skill_cooldowns[0]
	build.slots[3]["charges"] = skill_charges[1]
	build.slots[3]["cooldown"] = skill_cooldowns[1]
	player.hp = hp
	Game.flask_charges = flasks
	hud.queue_redraw()
	await _frames(2)


func _present_locale(locale: String) -> void:
	var values := Profile.preferences.duplicate(true)
	values.general.locale = locale
	Interface.apply_preferences(values)


func _region_difference(first: Image, second: Image, rect: Rect2) -> int:
	var changed := 0
	for y in range(int(rect.position.y), mini(int(rect.end.y), first.get_height())):
		for x in range(int(rect.position.x), mini(int(rect.end.x), first.get_width())):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.03:
				changed += 1
	return changed


func _image_difference(first: Image, second: Image) -> int:
	if first.get_width() != second.get_width() or first.get_height() != second.get_height():
		return 1
	var a := first.get_data()
	var b := second.get_data()
	if a.size() != b.size():
		return 1
	for i in a.size():
		if a[i] != b[i]:
			return 1
	return 0


func _masked_region_matches(page: Image, world: Image, rect: Rect2) -> bool:
	var matches := 0
	var total := 0
	var ink := MathArt.INK
	for y in range(int(rect.position.y), mini(int(rect.end.y), page.get_height())):
		for x in range(int(rect.position.x), mini(int(rect.end.x), page.get_width())):
			var under := world.get_pixel(x, y)
			var expected := Color(
				under.r * 0.18 + ink.r * 0.82,
				under.g * 0.18 + ink.g * 0.82,
				under.b * 0.18 + ink.b * 0.82)
			var actual := page.get_pixel(x, y)
			if absf(actual.r - expected.r) + absf(actual.g - expected.g) + absf(actual.b - expected.b) < 0.06:
				matches += 1
			total += 1
	return total > 0 and float(matches) / float(total) >= 0.95


## A modal page opened by a held accept must not consume that same hold: the
## reward closes only after a release and a fresh press.
func _check_reward_pad() -> void:
	var screen = _main.reward_screen
	_check(is_instance_valid(screen), "the reward page exists for the held-confirm proof")
	if not is_instance_valid(screen):
		return
	await _wait_ground()
	await _pad_down(JOY_BUTTON_A)
	await _frames(2)
	var damage: float = Game.total_damage_mult()
	var choices: Array = Data.rewards.keys()
	choices = choices.slice(0, mini(3, choices.size()))
	screen.open(choices)
	await _frames(3)
	_check(bool(screen._open) and Game.reward_open and get_tree().paused, "a reward page opens modal")
	_check(screen._choices.size() == 3 and choices.size() == 3, "the reward page shows three canonical choices")
	_check(is_equal_approx(Game.total_damage_mult(), damage), "the held accept does not pick on open")
	await _send(_pad_button(JOY_BUTTON_A, true))
	await _frames(3)
	_check(bool(screen._open) and Game.reward_open, "a duplicate A press without release does not pick")
	await _pad_up(JOY_BUTTON_A)
	await _frames(2)
	_check(bool(screen._open) and Game.reward_open, "releasing the held accept still does not pick")
	var focus_before: int = screen._index
	await _pad_tap(JOY_BUTTON_DPAD_RIGHT)
	_check(int(screen._index) == wrapi(focus_before + 1, 0, 3), "pad right moves the reward focus")
	if _capture:
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("reward-%s" % locale)
		_present_locale("zh_TW")
		await _frames(2)
	await _pad_tap(JOY_BUTTON_A)
	await _frames(3)
	_check(not bool(screen._open) and not Game.reward_open and not get_tree().paused, "a fresh pad A picks the reward and resumes")


## Scroll and gear compare with real pad events: a held accept never claims on
## open, a duplicate press without release never buys twice, and the focused
## replacement slot survives a keyboard retake.
func _check_shop_pad() -> void:
	await _wait_ground()
	var build = Game.build
	var player = Game.player
	var attribute_total := 0
	for value in build.attributes.values():
		attribute_total += int(value)
	var scroll := RunLoot.new()
	scroll.kind = "scroll"
	scroll.item = {"id": "scroll", "axis": "brutality"}
	scroll.cost = 0
	scroll.position = player.position + Vector2(12, 0)
	_main.level.add_child(scroll)
	await _frames(2)
	_check(scroll.available(), "a free scroll offer is live for the pad walk")
	await _pad_down(JOY_BUTTON_A)
	await _frames(2)
	await _pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(4)
	_check(_main.build_screen.is_open() and get_tree().paused, "RB with a held A opens the scroll page")
	_check(not scroll.consumed, "the held accept does not claim on open")
	await _pad_up(JOY_BUTTON_A)
	await _frames(2)
	_check(not scroll.consumed, "releasing the held accept still does not claim")
	await _pad_down(JOY_BUTTON_A)
	await _frames(3)
	await _send(_pad_button(JOY_BUTTON_A, true))
	await _frames(3)
	await _pad_up(JOY_BUTTON_A)
	var claimed_total := 0
	for value in build.attributes.values():
		claimed_total += int(value)
	_check(claimed_total == attribute_total + 1, "a duplicate A press without release claims the scroll once")
	_check(not _main.build_screen.is_open() and not get_tree().paused, "the claimed scroll closes the compare page")

	var gear_item: Dictionary = Game.create_loot("shop", 0)
	_check(not gear_item.is_empty(), "the shop pool offers a gear piece")
	if gear_item.is_empty():
		return
	var gear := RunLoot.new()
	gear.kind = "shop"
	gear.item = gear_item
	gear.cost = 10
	gear.position = player.position + Vector2(12, 0)
	_main.level.add_child(gear)
	await _frames(2)
	build.gold = 0
	await _pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(4)
	_check(_main.build_screen.is_open(), "a gear offer opens the compare page")
	if _main.build_screen._slots.size() > 1:
		var old_index: int = _main.build_screen._index
		await _pad_tap(JOY_BUTTON_DPAD_RIGHT)
		_check(int(_main.build_screen._index) == wrapi(old_index + 1, 0, _main.build_screen._slots.size()), "pad right moves the replacement slot")
	await _pad_tap(JOY_BUTTON_A)
	_check(str(_main.build_screen._note_kind) == "need" and not gear.consumed and int(build.gold) == 0, "insufficient gold refuses without spending")
	if _capture:
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("compare-insufficient-%s" % locale)
		_present_locale("zh_TW")
		await _frames(2)
	await _pad_tap(JOY_BUTTON_B)
	await _frames(2)
	_check(not _main.build_screen.is_open(), "pad B closes the refused compare page")

	build.gold = 20
	await _pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(4)
	_check(_main.build_screen.is_open(), "the funded gear offer reopens")
	if _capture:
		await _wait(0.16)
		await _save_view("compare-gamepad-zh_TW")
	var compare_slot: int = _main.build_screen._index
	await _key(KEY_F)
	_check(int(_main.build_screen._index) == compare_slot, "keyboard retake keeps the compare focus")
	if _capture:
		await _save_view("compare-keyboard-zh_TW")
	await _pad_down(JOY_BUTTON_A)
	await _frames(3)
	await _send(_pad_button(JOY_BUTTON_A, true))
	await _frames(2)
	await _pad_up(JOY_BUTTON_A)
	_check(build.owns(gear_item), "a funded pad accept commits exactly one swap")
	_check(not _main.build_screen.is_open() and not get_tree().paused, "the committed swap closes the compare page")


## STEP5: the world shop card is a real screen-space surface (outside the modal)
## carrying the presenter name, the full price and the real interact binding.
## The shared compare page then proves its detail scroll and free-only X.
func _check_shop_truth() -> void:
	await _wait_ground()
	var player = Game.player
	var build = Game.build
	if not is_instance_valid(player) or build == null or Game.run_phase != "biome":
		_check(false, "the shop truth fixture needs the live run")
		return
	var long_id := ""
	var long_len := 0
	for id in Data.gear.items:
		var label := ContentText.name("gear", str(id), str(Data.gear.items[id].get("name", "")))
		if label.length() > long_len:
			long_len = label.length()
			long_id = str(id)
	_check(not long_id.is_empty(), "a longest shipped gear name exists for the tip fixture")
	build.gold = 50
	var item: Dictionary = build.create(long_id, "etched", "keen")
	var tip := RunLoot.new()
	tip.kind = "shop"
	tip.item = item
	tip.cost = 10
	tip.position = player.position + Vector2(14, -10)
	_main.level.add_child(tip)
	Game.announce_t = 0.0
	Game.announce_text = ""
	await _frames(3)
	_check(tip.available(), "the shop stock is live next to the player")
	var card: Rect2 = tip.shop_tip_rect()
	_check(card.has_area() and card.size == Vector2(304, 154) and Rect2(16, 16, 736, 320).encloses(card),
		"the shop card is a bounded screen-space surface")
	await _key(KEY_F)
	await _frames(2)
	_check(Interface.active_device == Interface.DEVICE_KEYBOARD,
		"a real neutral key retakes the prompt before the long binding check (device=%s)" % str(Interface.active_device))
	var default_prompt := Interface.prompt(&"interact")
	Interface.apply_preferences({"input": {"keyboard": {"interact": KEY_PAGEDOWN}, "gamepad": {}}})
	await _frames(2)
	var rebound := false
	for event in InputMap.action_get_events(&"interact"):
		if event is InputEventKey and int(event.physical_keycode) == KEY_PAGEDOWN:
			rebound = true
	_check(rebound, "the live interact binding carries the PageDown physical key")
	var long_prompt := Interface.prompt(&"interact")
	_check(Interface.active_device == Interface.DEVICE_KEYBOARD and long_prompt == "PgDn",
		"a long interact binding reaches the real prompt (device=%s prompt=%s)" % [str(Interface.active_device), long_prompt])
	if _capture:
		var zh_view := await _save_view("shop-tip-zh_TW")
		tip.visible = false
		await _frames(2)
		var zh_hidden := await _save_view("shop-tip-zh_TW-hidden")
		tip.visible = true
		_check(_region_difference(zh_view, zh_hidden, card) > 200, "the live shop card paints real pixels")
		_present_locale("en")
		await _frames(2)
		await _save_view("shop-tip-en")
		_present_locale("zh_TW")
		await _frames(2)
	Interface.apply_preferences({})
	await _frames(2)
	_check(Interface.prompt(&"interact") == default_prompt,
		"the default interact binding is restored to its consumer prompt (prompt=%s)" % Interface.prompt(&"interact"))
	tip.queue_free()
	# The shared compare page: bounded detail scroll, then X.
	var gear_item: Dictionary = Game.create_loot("shop", 2)
	_check(not gear_item.is_empty(), "the shop pool offers a compare candidate")
	if gear_item.is_empty():
		return
	var paid := RunLoot.new()
	paid.kind = "shop"
	paid.item = gear_item
	paid.cost = 10
	paid.position = player.position + Vector2(12, 0)
	_main.level.add_child(paid)
	build.gold = 50
	await _frames(2)
	await _pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(4)
	var page = _main.build_screen
	_check(page.is_open(), "the funded candidate opens the compare page")
	if not page.is_open():
		return
	var candidate_kind := str(build.definition(page.offer.item).get("kind", ""))
	if candidate_kind == "skill":
		var different := str(page._target_headline(3, build.slots[3]))
		var same := str(page._target_headline(2, build.slots[2]))
		_check(different.contains("用途不同") or different.contains("Different actions"),
			"a different canonical action reads as different instead of a numeric delta")
		_check(not different.contains("→"), "a different action never shows the same-column numeric delta")
		_check(same.contains("→"), "a same-action replacement keeps its numeric comparison")
	var detail_count := int(page._detail_count)
	var detail_rows := int(page._detail_rows)
	var detail_end := maxi(0, detail_count - detail_rows)
	var guard := 0
	if detail_end > 0:
		await _key(KEY_DOWN)
		guard = 1
		_check(int(page._detail_scroll) == 1 and page.is_open() and Interface.active_device == Interface.DEVICE_KEYBOARD,
			"one real down press takes the keyboard and moves the shared detail (scroll=%d count=%d rows=%d open=%s device=%s)" % [int(page._detail_scroll), detail_count, detail_rows, str(page.is_open()), str(Interface.active_device)])
	while int(page._detail_scroll) < detail_end and guard < detail_end + 4:
		await _key(KEY_DOWN)
		guard += 1
	_check(int(page._detail_scroll) == detail_end,
		"the shared detail scroll reaches its last row (count=%d rows=%d end=%d scroll=%d steps=%d)" % [detail_count, detail_rows, detail_end, int(page._detail_scroll), guard])
	var gold_before: int = build.gold
	await _key(KEY_X)
	_check(str(page._note_kind) == "recycle" and not paid.consumed and int(build.gold) == gold_before and page.is_open(),
		"X refuses unsold shop stock without spending or closing")
	if _capture:
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("compare-detail-%s" % locale)
		_present_locale("zh_TW")
		await _frames(2)
	await _pad_tap(JOY_BUTTON_B)
	await _frames(2)
	_check(not page.is_open(), "B closes the refused compare page")
	# A free candidate the player already owns is the only recycle target.
	var saved_slot: Dictionary = build.slots[0].duplicate(true)
	var free := RunLoot.new()
	free.kind = "gear"
	free.item = build.slots[0]
	free.cost = 0
	free.position = player.position + Vector2(12, 0)
	_main.level.add_child(free)
	var gold_free: int = build.gold
	await _frames(2)
	await _pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(4)
	_check(page.is_open(), "the free owned candidate opens the compare page")
	if page.is_open():
		await _key(KEY_X)
		await _frames(2)
		_check(not page.is_open() and int(build.gold) > gold_free, "X recycles a free owned candidate for gold")
	build.slots[0] = saved_slot
	if is_instance_valid(Game.player):
		Game.player._apply_loadout()
	build.gold = 25
	await _frames(2)
	var amulet_item: Dictionary = build.create("ash_charm", "plain", "none")
	var amulet := RunLoot.new()
	amulet.kind = "shop"
	amulet.item = amulet_item
	amulet.cost = 0
	amulet.position = player.position + Vector2(12, 0)
	_main.level.add_child(amulet)
	await _frames(2)
	await _pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(4)
	_check(page.is_open() and page._slots.size() == 1 and int(page._slots[0]) == 4,
		"the amulet candidate targets the amulet slot")
	if page.is_open():
		var amulet_headline := str(page._target_headline(4, build.slots[4]))
		_check((amulet_headline.contains("不回血") or amulet_headline.contains("No healing"))
			and amulet_headline.contains("HP"), "the amulet card keeps current/max HP with no healing")
		var charge := str(page._target_charge(build.slots[4], build.definition(build.slots[4])))
		_check(charge.contains("不回血") or charge.contains("NO HEAL"), "the amulet line states no heal")
		if _capture:
			for locale in ["zh_TW", "en"]:
				_present_locale(locale)
				await _frames(2)
				await _save_view("compare-amulet-%s" % locale)
			_present_locale("zh_TW")
			await _frames(2)
		await _pad_tap(JOY_BUTTON_B)
		await _frames(2)
		_check(not page.is_open(), "B closes the amulet comparison")


## STEP5: the scroll page shows every axis card, states the no-heal fact, and
## its canonical projection equals the real claim.
func _check_scroll_truth() -> void:
	await _wait_ground()
	var build = Game.build
	var player = Game.player
	if build == null or not is_instance_valid(player) or Game.run_phase != "biome":
		_check(false, "the scroll fixture needs the live run")
		return
	var scroll := RunLoot.new()
	scroll.kind = "scroll"
	scroll.item = {"id": "scroll"}
	scroll.cost = 0
	scroll.position = player.position + Vector2(12, 0)
	_main.level.add_child(scroll)
	await _frames(2)
	player.hp = player.max_hp * 0.6
	var hp_before: float = player.hp
	await _pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(4)
	var page = _main.build_screen
	_check(page.is_open() and page._slots.size() == 3, "the scroll page shows all three axis cards")
	if not page.is_open():
		return
	for index in 3:
		_check(not page._detail_lines.is_empty(), "the scroll card %d explains its real effect" % index)
		if _capture:
			await _save_view("scroll-card-%d-zh_TW" % index)
		if index < 2:
			await _pad_tap(JOY_BUTTON_DPAD_RIGHT)
	await _key(KEY_1)
	_check(int(page._index) == 0, "the numeric quick pick returns the scroll focus to the first axis")
	var axis := str(build.attributes.keys()[0])
	var projection := build.scroll_projection(axis, player.hp)
	_check(not projection.is_empty() and float(projection["max_after"]) > float(projection["max_before"]),
		"the selected scroll raises maximum HP in its canonical projection")
	_check(float(projection["hp_after"]) < float(projection["max_after"]),
		"the projection never restores current HP to the new maximum")
	var fact := ContentText.of("UI_S5_SCROLL_HP_FACT", "Max HP increases; current HP is not restored.")
	_check(_compact("".join(page._detail_lines)).contains(_compact(fact)), "the scroll detail states the no-heal fact")
	_check(int(page._detail_count) >= int(page._detail_rows), "the scroll detail is bounded to its visible rows")
	if _capture:
		_present_locale("en")
		await _frames(2)
		for index in 3:
			await _save_view("scroll-card-%d-en" % index)
			if index < 2:
				await _pad_tap(JOY_BUTTON_DPAD_RIGHT)
		_present_locale("zh_TW")
		await _frames(2)
		await _key(KEY_1)
	await _pad_tap(JOY_BUTTON_A)
	await _frames(2)
	_check(not page.is_open(), "a fresh accept claims the scroll once and closes the page")
	_check(int(build.attributes[axis]) == int(projection["before"]) + 1, "the committed scroll increments the projected axis")
	_check(is_equal_approx(player.max_hp, float(projection["max_after"])), "the committed maximum equals the projection")
	_check(is_equal_approx(player.hp, hp_before), "claiming the scroll does not heal current HP")


## Passage services: real Collector entry, held-confirm transaction, then every
## service page through pad focus/accept/back. Forge keeps its boss fixture
## through the accept because the transaction re-checks it.
func _check_service_pad() -> void:
	_main._on_exit_chosen("hanging_gallery")
	await _wait(2.0)
	_check(Game.run_phase == "passage" and Game.service_ready(), "the run reaches the passage services")
	if Game.run_phase != "passage":
		return
	Game.run_cells = 20
	Profile.blueprint_cells["chain_lash"] = 15
	if not Game.carried_blueprints.has("chain_lash"):
		Game.carried_blueprints.append("chain_lash")
	Game.player.position = Vector2(Passage.COLLECTOR_X, -40)
	await _frames(3)
	await _pad_down(JOY_BUTTON_A)
	await _frames(2)
	await _pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(4)
	var collector = _main.collector
	_check(is_instance_valid(collector) and get_tree().paused, "RB opens the Collector in the passage")
	if not is_instance_valid(collector):
		return
	_check(str(collector._ids[collector._index]) == "chain_lash", "the Collector focuses the carried blueprint")
	if _capture:
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("collector-carried-%s" % locale)
		_present_locale("zh_TW")
		await _frames(2)
	_check(Game.carried_blueprints.has("chain_lash") and int(Profile.blueprint_cells["chain_lash"]) == 15, "the held accept does not deliver on open")
	await _pad_up(JOY_BUTTON_A)
	await _frames(2)
	await _pad_tap(JOY_BUTTON_A)
	await _frames(2)
	_check(not Game.carried_blueprints.has("chain_lash"), "pad accept delivers the carried blueprint")
	if _capture:
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("collector-partial-%s" % locale)
		_present_locale("zh_TW")
		await _frames(2)
	await _pad_tap(JOY_BUTTON_A)
	await _frames(2)
	_check(int(Profile.blueprint_cells["chain_lash"]) == 20 and Game.run_cells == 15 and str(collector._unlocked_id) == "chain_lash", "pad accept invests the step and opens the unlock acknowledgement")
	if _capture:
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("collector-unlocked-%s" % locale)
		_present_locale("zh_TW")
		await _frames(2)
	await _pad_tap(JOY_BUTTON_B)
	await _frames(2)
	_check(str(collector._unlocked_id).is_empty() and is_instance_valid(collector) and get_tree().paused, "B closes only the unlock acknowledgement")
	await _pad_tap(JOY_BUTTON_B)
	await _frames(3)
	_check(not is_instance_valid(_main.collector) and not get_tree().paused, "a second B closes the Collector")

	for id in ["mutation", "craft", "challenge"]:
		_main._open_service(id)
		await _frames(3)
		var page = _main.collector
		_check(is_instance_valid(page) and page._ids.size() > 1, "%s opens with real rows" % id)
		if not is_instance_valid(page):
			continue
		var before_index: int = page._index
		await _pad_tap(JOY_BUTTON_DPAD_DOWN)
		_check(int(page._index) != before_index or page._ids.size() <= 1, "%s moves its focus with the pad" % id)
		if id == "craft":
			Game.build.gold = 100
		if _capture:
			for locale in ["zh_TW", "en"]:
				_present_locale(locale)
				await _frames(2)
				await _save_view("service-%s-%s" % [id, locale])
			_present_locale("zh_TW")
			await _frames(2)
		await _pad_tap(JOY_BUTTON_A)
		_check(not str(page._note).is_empty(), "%s reports the pad transaction result" % id)
		await _pad_tap(JOY_BUTTON_B)
		await _frames(3)
		_check(not is_instance_valid(_main.collector), "%s closes with pad B" % id)

	var old_node: String = Game.run_node_id
	var old_boss: bool = Game.boss_defeated
	Game.run_node_id = "bridge_sentinel"
	Game.boss_defeated = true
	Game.run_cells = 10
	_main._open_service("forge")
	await _frames(3)
	var forge = _main.collector
	_check(is_instance_valid(forge), "the Forge opens under a boss-passage fixture")
	if is_instance_valid(forge):
		var cells_before: int = Game.run_cells
		if _capture:
			for locale in ["zh_TW", "en"]:
				_present_locale(locale)
				await _frames(2)
				await _save_view("service-forge-%s" % locale)
			_present_locale("zh_TW")
			await _frames(2)
		await _pad_tap(JOY_BUTTON_A)
		_check(Game.run_cells < cells_before and int(Profile.forge_cells) > 0, "pad accept invests forge cells")
		await _pad_tap(JOY_BUTTON_B)
		await _frames(3)
		_check(not is_instance_valid(_main.collector), "pad B closes the Forge")
	Game.run_node_id = old_node
	Game.boss_defeated = old_boss


## STEP6/STEP8: the paid mutation reset is the nearest confirmation layer above
## the service. Back cancels only that layer, spends nothing, and cannot also
## close the service underneath.
func _check_mutation_reset_layer() -> void:
	if Game.run_phase != "passage" or Game.build == null:
		_check(false, "the mutation reset fixture needs the passage run")
		return
	Game.build.gold = 999
	Game.build.mutations.clear()
	var mutation_id := ""
	for id in Data.passage.mutations.keys():
		mutation_id = str(id)
		break
	_check(not mutation_id.is_empty(), "canonical mutations exist for the reset layer")
	if mutation_id.is_empty():
		return
	Game.build.mutations.append(mutation_id)
	_main._open_service("mutation")
	await _frames(3)
	var page = _main.collector
	_check(is_instance_valid(page) and bool(page.visible), "the mutation service opens for the reset layer")
	if not is_instance_valid(page):
		return
	var reset_index := int(page._ids.find("reset"))
	_check(reset_index >= 0, "the mutation service lists the reset row")
	var guard := 0
	while int(page._index) != reset_index and guard < page._ids.size() + 2:
		await _pad_tap(JOY_BUTTON_DPAD_DOWN)
		guard += 1
	_check(int(page._index) == reset_index, "the reset row is reachable with the pad")
	await _pad_tap(JOY_BUTTON_A)
	_check(bool(page._reset_confirm) and Game.build.mutations.has(mutation_id) and int(Game.build.gold) == 999,
		"the first accept arms the reset without spending")
	_check(get_tree().paused, "the reset confirmation keeps the service pause")
	if _capture:
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("mutation-reset-confirm-%s" % locale)
		_present_locale("zh_TW")
		await _frames(2)
	await _pad_tap(JOY_BUTTON_B)
	_check(not bool(page._reset_confirm) and is_instance_valid(page) and Game.build.mutations.has(mutation_id),
		"B cancels only the reset layer and keeps the service open")
	_check(not str(page._note).is_empty() and int(Game.build.gold) == 999,
		"cancelling the reset reports a real zero-spend receipt")
	await _pad_tap(JOY_BUTTON_A)
	_check(bool(page._reset_confirm), "the reset can be armed again after a cancel")
	var reset_cost := int(Game.build.reset_cost())
	_check(reset_cost > 0, "the reset has a real positive price")
	Game.build.gold = 0
	page._canvas.queue_redraw()
	await _frames(2)
	if _capture:
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("mutation-reset-insufficient-%s" % locale)
		_present_locale("zh_TW")
		await _frames(2)
	await _pad_tap(JOY_BUTTON_A)
	_check(Game.build.mutations.has(mutation_id) and int(Game.build.gold) == 0
		and not str(page._note).is_empty() and not bool(page._reset_confirm),
		"an unaffordable reset confirms the refusal and keeps the mutations")
	Game.build.gold = 999
	await _pad_tap(JOY_BUTTON_A)
	_check(bool(page._reset_confirm), "the funded reset arms its confirmation")
	await _pad_tap(JOY_BUTTON_A)
	_check(not bool(page._reset_confirm) and Game.build.mutations.is_empty(),
		"the second accept commits the reset")
	_check(not str(page._note).is_empty(), "the committed reset reports its result")
	if _capture:
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("mutation-reset-done-%s" % locale)
		_present_locale("zh_TW")
		await _frames(2)
	await _pad_tap(JOY_BUTTON_B)
	await _frames(3)
	_check(not is_instance_valid(_main.collector), "B closes the mutation service after the reset")


## STEP6: craft charges live Gold (not the cloned projection balance), and the
## committed item equals the canonical projection item.
func _check_craft_live_gold() -> void:
	if Game.run_phase != "passage" or Game.build == null:
		_check(false, "the craft fixture needs the passage run")
		return
	_main._open_service("craft")
	await _frames(3)
	var page = _main.collector
	_check(is_instance_valid(page) and not page._ids.is_empty(), "the craft service opens with real rows")
	if not is_instance_valid(page) or page._ids.is_empty():
		return
	var id := ""
	var slot := -1
	var reforge := false
	var cost := -1
	var focus := -1
	for candidate in page._ids:
		var candidate_id := str(candidate)
		var candidate_slot := int(candidate_id.get_slice("/", 1))
		var candidate_reforge := candidate_id.begins_with("reforge")
		var candidate_cost := int(Game.build.craft_cost(candidate_slot, candidate_reforge))
		if candidate_cost > 0:
			id = candidate_id
			slot = candidate_slot
			reforge = candidate_reforge
			cost = candidate_cost
			focus = int(page._ids.find(candidate_id))
			break
	_check(cost > 0, "a craft row with a real positive cost exists (rows=%d id=%s slot=%d reforge=%s cost=%d quality=%s gold=%d)" % [page._ids.size(), id, slot, str(reforge), cost, str((Game.build.slots[slot] as Dictionary).get("quality", "")), int(Game.build.gold)])
	if cost <= 0:
		return
	var nav_guard := 0
	while int(page._index) != focus and nav_guard < page._ids.size():
		await _pad_tap(JOY_BUTTON_DPAD_DOWN)
		nav_guard += 1
	_check(int(page._index) == focus and str(page._ids[page._index]) == id,
		"real pad navigation focuses the eligible craft row (index=%d expected=%d id=%s)" % [int(page._index), focus, str(page._ids[page._index])])
	page._canvas.queue_redraw()
	Game.build.gold = maxi(0, cost - 1)
	var short_before: int = Game.build.gold
	await _pad_tap(JOY_BUTTON_A)
	_check(int(Game.build.gold) == short_before and not str(page._note).is_empty(),
		"insufficient live Gold refuses the craft and keeps the balance")
	_check(is_instance_valid(page) and bool(page.visible), "the refused craft keeps the service open")
	var projection: Dictionary = Game.build.craft_projection(slot, reforge)
	_check(not projection.is_empty() and int(projection.get("cost", -1)) == cost,
		"the canonical projection prices the same transaction")
	Game.build.gold = cost
	await _pad_tap(JOY_BUTTON_A)
	_check(int(Game.build.gold) == 0, "the committed craft charges the canonical price from live Gold")
	_check(Game.build.display_stats(Game.build.slots[slot]) == projection.get("after", {}),
		"the committed item equals the canonical projection item")
	if _capture:
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("craft-committed-%s" % locale)
		_present_locale("zh_TW")
		await _frames(2)
	await _pad_tap(JOY_BUTTON_B)
	await _frames(3)
	_check(not is_instance_valid(_main.collector), "B closes the craft service")


## STEP7: travel keeps its six-row sidebar, browse uses the whole page, a
## single room never upscales past 1:1, and a world-tab Accept reports the
## refusal instead of travelling.
func _check_map_states() -> void:
	if Game.run_phase != "passage":
		_check(false, "the map fixture starts in the passage run (phase=%s)" % Game.run_phase)
		return
	var map = _main.exploration_map
	await _key(KEY_TAB)
	await _frames(3)
	var browse_open: bool = is_instance_valid(map) and map.is_open()
	var browse_teleport: bool = is_instance_valid(map) and bool(map._teleport)
	_check(browse_open and not browse_teleport,
		"Tab opens the Passage map in browse mode (open=%s teleport=%s phase=%s)" % [str(browse_open), str(browse_teleport), str(Game.run_phase)])
	if not browse_open:
		return
	_check(int(map._place_rows()) == 2 and map._plot_area().size == Vector2(664, 242),
		"passage browse uses the full page and two place rows")
	if _capture:
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("map-browse-%s" % locale)
		_present_locale("zh_TW")
		await _frames(2)
	await _key(KEY_ESCAPE)
	await _frames(2)
	_check(not map.is_open() and not get_tree().paused, "Esc closes the Passage browse map")
	var destination := str(Game.pending_destination)
	_check(not destination.is_empty() and bool(Game.exit_selected),
		"the route already selected a legal destination (destination=%s selected=%s)" % [destination, str(Game.exit_selected)])
	if destination.is_empty():
		return
	Game.player.relocate(Vector2(Passage.EXIT_X, -40))
	await _frames(3)
	await _key(KEY_R)
	await _frames(6)
	_check(Game.run_phase == "biome" and Game.run_node_id == destination and is_instance_valid(_main.level),
		"the Passage exit continues into the selected biome (phase=%s node=%s expected=%s level=%s)" % [str(Game.run_phase), str(Game.run_node_id), destination, str(is_instance_valid(_main.level))])
	var level = _main.level
	if not is_instance_valid(level):
		return
	var level_data: Dictionary = level.get("data")
	var pad_id := ""
	var pad_pos := Vector2.ZERO
	for pad in level_data.get("pads", []):
		if str(pad["kind"]) == "checkpoint":
			pad_id = str(pad["id"])
			pad_pos = pad["pos"] as Vector2
			break
	_check(not pad_id.is_empty(), "the biome has a checkpoint pad for real travel")
	if pad_id.is_empty():
		return
	Game.player.relocate(pad_pos + Vector2(0, -4))
	await _frames(6)
	_check(str(level.checkpoint_near_player()) == pad_id,
		"the live checkpoint pad is active under the player (pad=%s near=%s)" % [pad_id, str(level.checkpoint_near_player())])
	await _key(KEY_R)
	await _frames(3)
	var travel_open: bool = is_instance_valid(map) and map.is_open() and bool(map._teleport)
	_check(travel_open,
		"checkpoint interact opens travel over the live biome (open=%s phase=%s node=%s)" % [str(is_instance_valid(map) and map.is_open()), str(Game.run_phase), str(Game.run_node_id)])
	if not travel_open:
		return
	_check(int(map._place_rows()) == 6,
		"travel mode reserves its six-row teleporter sidebar")
	_check(map._plot_area().size == Vector2(472, 242), "travel plots into the sidebar layout")
	var fit: Dictionary = map.plot_transform([{"id":"only", "bounds":Rect2(0, 0, 80, 60)}])
	_check(is_equal_approx(float(fit.get("scale", 0.0)), 1.0), "a single room never upscales past 1:1")
	var inner: Rect2 = map._plot_area().grow(-24.0)
	_check((fit.get("origin", Vector2.ZERO) as Vector2) + Vector2(40, 30) == inner.get_center(),
		"a single room is centred in the plot area")
	_check(map.plot_transform([{"id":"big", "bounds":Rect2(0, 0, 4000, 3000)}]).get("scale", 1.0) < 1.0,
		"a large discovered area scales down instead of overflowing")
	var place_rows := int(map._place_count)
	if place_rows > int(map._place_rows()):
		var before_scroll: int = map._place_scroll
		await _key(KEY_PAGEDOWN)
		_check(int(map._place_scroll) == mini(before_scroll + int(map._place_rows()), place_rows - int(map._place_rows())),
			"PageDown pages the known-place list")
	if _capture:
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("map-travel-%s" % locale)
		_present_locale("zh_TW")
		await _frames(2)
	await _key(KEY_RIGHT)
	_check(int(map._tab) == 1, "right switches the map to the world tab")
	var node_id: String = Game.run_node_id
	await _key(KEY_ENTER)
	_check(bool(map._status_error) and map.is_open() and Game.run_node_id == node_id,
		"world-tab accept reports browse-only instead of travelling")
	if _capture:
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("map-world-refusal-%s" % locale)
		_present_locale("zh_TW")
		await _frames(2)
	await _pad_tap(JOY_BUTTON_B)
	await _frames(3)
	_check(not map.is_open() and not get_tree().paused and Game.run_phase == "biome",
		"B closes travel and restores the live biome run")


## STEP7: slot states stay honest at the display boundary and reading never
## repairs, creates or clears a slot file.
func _check_slot_states() -> void:
	var active: int = Profile.active_slot
	var other := 1 if active != 1 else 2
	var path := Profile.slot_path(other)
	var had_file := FileAccess.file_exists(path)
	var original := FileAccess.get_file_as_string(path) if had_file else ""
	var runs_before: int = Profile.runs
	if had_file:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var empty_summary: Dictionary = Profile.slot_summary(other)
	_check(str(empty_summary.get("label", "")) == "EMPTY" and not FileAccess.file_exists(path),
		"an empty slot reports EMPTY and creates no file")
	_check(Hud.slot_label(empty_summary) != str(empty_summary.get("label", "")),
		"the empty slot label crosses the display boundary")
	_write_text(path, "{ not json")
	var corrupt: Dictionary = Profile.slot_summary(other)
	_check(bool(corrupt.get("blocked", false)) and str(corrupt.get("label", "")).begins_with("DAMAGED"),
		"a damaged slot stays protected instead of becoming empty")
	_check(FileAccess.get_file_as_string(path) == "{ not json", "reading a damaged slot never rewrites it")
	_check(Hud.slot_label(corrupt) != str(corrupt.get("label", "")),
		"the damaged label is translated at the display boundary")
	var newer_text := JSON.stringify({"version": int(Profile.VERSION) + 1, "run_checkpoint": {}})
	_write_text(path, newer_text)
	var newer: Dictionary = Profile.slot_summary(other)
	_check(bool(newer.get("blocked", false)) and str(newer.get("label", "")).contains("NEWER VERSION"),
		"a newer-version slot is protected")
	var newer_after := FileAccess.get_file_as_string(path)
	_check(newer_after == newer_text,
		"reading a newer-version slot never rewrites it (len=%d/%d head=%s exists=%s tmp=%s)" % [newer_after.length(), newer_text.length(), newer_after.left(48), str(FileAccess.file_exists(path)), str(FileAccess.file_exists(path + ".tmp"))])
	_write_text(path, JSON.stringify({"version": int(Profile.VERSION), "victories": 0,
		"run_checkpoint": {"kind": "biome_entry", "state": {"run_node_id": "ash_gate"}}}))
	var invalid: Dictionary = Profile.slot_summary(other)
	_check(not str(invalid.get("resume_error", "")).is_empty() and not bool(invalid.get("resume", true)),
		"a present but invalid checkpoint never advertises resume")
	_check(Hud.slot_label(invalid) != str(Hud.slot_label(empty_summary)),
		"an unusable checkpoint reads differently from an empty slot")
	_check(not str(TranslationServer.translate("UI_S7_TITLE_UNUSABLE_CHECKPOINT")).contains("UI_"),
		"the unusable-checkpoint explanation ships as real text")
	if had_file:
		_write_text(path, original)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(Profile.runs == runs_before, "slot-state inspection never changes run progress")
	var active_summary: Dictionary = Profile.slot_summary(active)
	_check(bool(active_summary.get("resume", false)) == (not Profile.run_checkpoint.is_empty()),
		"the active slot's resume flag matches the canonical checkpoint")


## STEP7/STEP8: the result layer names the canonical end reason, offers retry
## only for a pending settlement, and never claims a failed save succeeded.
func _check_result_states() -> void:
	_main.enter_hub()
	await _frames(3)
	var hud = _main.hud
	Game.run_over = false
	Game.run_abandoned = false
	Game.settlement_pending.clear()
	_check(Game.end_run(false, true), "an explicit abandonment ends the run")
	_check(Game.run_abandoned and not Game.victory and Game.settlement_pending.is_empty(),
		"a saved abandonment records its canonical reason")
	_check(hud.run_over_action_ids() == ["return", "quit"],
		"a saved abandonment offers return and leave")
	if _capture:
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("result-abandoned-%s" % locale)
		_present_locale("zh_TW")
		await _frames(2)
	Game.reset_run()
	_main.enter_hub()
	await _frames(3)
	Profile._save_blocked = true
	_check(Game.end_run(false, true), "a failed-save abandonment still reaches the result layer")
	Profile._save_blocked = false
	_check(Game.run_abandoned and not Game.settlement_pending.is_empty(),
		"the failed abandonment keeps its reason and a pending settlement")
	_check(Game.announce_kind == &"error" and not Game.announce_text.is_empty(),
		"the failed result announces an error severity with real text")
	_check(hud.run_over_action_ids() == ["retry", "quit"],
		"a pending result offers retry save and leave")
	if _capture:
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("result-save-failed-%s" % locale)
		_present_locale("zh_TW")
		await _frames(2)
	_check(Game.retry_settlement(), "the result retry settles once the writer recovers")
	_check(Game.settlement_pending.is_empty(), "a successful retry clears the pending settlement")
	_check(Game.retry_settlement(), "a second retry is a harmless no-op")
	Game.reset_run()
	_main.enter_hub()
	await _frames(3)
	_check(Game.end_run(false), "a death ends the run through the same canonical call")
	_check(not Game.run_abandoned and not Game.victory, "a death is not recorded as an abandonment")
	_check(hud.run_over_action_ids() == ["return", "quit"], "a death offers return and leave")
	var victory_copy := str(TranslationServer.translate("UI_S7_HUD_VICTORY_BSC"))
	_check(victory_copy.contains("0 BSC") and not victory_copy.contains("UI_"),
		"the victory result states the 0 BSC route and does not leak a key")
	_check(victory_copy.contains("not playable") or victory_copy.contains("尚不可遊玩"),
		"the victory result never promises BSC 1 is playable")
	if _capture:
		await _save_view("result-death-zh_TW")
	Game.reset_run()
	_main.enter_hub()
	await _frames(3)
	# The canonical predicate decides victory readiness; the fixture only fills
	# the route state a real completed run would have.
	Game.in_hub = false
	Game.run_phase = "biome"
	Game.run_bsc = 0
	Game.run_node_id = str(Data.route_graph.final)
	Game.route_history.clear()
	for id in Data.route_graph.default_0_bsc_route:
		Game.route_history.append(str(id))
	Game.defeated_bosses.clear()
	for id in Data.route_graph.get("nodes", {}):
		if str((Data.route_graph["nodes"][id] as Dictionary).get("kind", "")) == "boss":
			Game.defeated_bosses.append(str(id))
	Game.boss_defeated = true
	# Fixture seed only: a real completed run holds this route's gate keys.
	var route_ids: Array = Data.route_graph["default_0_bsc_route"]
	for index in range(route_ids.size() - 1):
		var pair_from := str(route_ids[index])
		var pair_to := str(route_ids[index + 1])
		for edge in Data.route_graph.get("edges", []):
			if str(edge.get("from", "")) == pair_from and str(edge.get("to", "")) == pair_to:
				for required in edge.get("requires_keys", []):
					if not Game.run_keys.has(str(required)):
						Game.run_keys.append(str(required))
				break
	var illegal_pair := ""
	var illegal_reason := ""
	for index in range(route_ids.size() - 1):
		var pair_from := str(route_ids[index])
		var pair_to := str(route_ids[index + 1])
		for edge in Data.route_graph.get("edges", []):
			if str(edge.get("from", "")) == pair_from and str(edge.get("to", "")) == pair_to:
				var reason := RouteGraph.lock_reason(edge, Game.route_state())
				if not reason.is_empty() and illegal_pair.is_empty():
					illegal_pair = "%s -> %s" % [pair_from, pair_to]
					illegal_reason = reason
				break
	_check(illegal_pair.is_empty(),
		"the completed route fixture opens every pair (first=%s reason=%s keys=%s)" % [illegal_pair, illegal_reason, str(Game.run_keys)])
	_check(is_instance_valid(Game.player), "the victory fixture has the live hub player")
	if is_instance_valid(Game.player):
		Game.player.hp = Game.player.max_hp
	_check(Game.final_ready(), "the canonical victory predicate accepts the completed route fixture")
	_check(Game.end_run(true), "the completed route ends in victory")
	_check(Game.victory and not Game.run_abandoned,
		"victory never records an abandonment reason")
	if _capture:
		for locale in ["zh_TW", "en"]:
			_present_locale(locale)
			await _frames(2)
			await _save_view("result-victory-%s" % locale)
		_present_locale("zh_TW")
		await _frames(2)
	Game.reset_run()
	_main.enter_hub()
	await _frames(3)


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "fixture can write " + path)
		return
	file.store_string(text)
	file.close()


## A checkpoint exists now, so the title's destructive overwrite needs a fresh
## press after release: a duplicate pressed A without release must not commit.
func _check_title_overwrite() -> void:
	var runs: int = Profile.runs
	_main.return_to_title()
	await _frames(4)
	var title = _main.title_screen
	if not is_instance_valid(title):
		_check(false, "the title opens for the overwrite proof")
		return
	if str(title._view) != "main":
		await _pad_tap(JOY_BUTTON_B)
	while int(title._action) != 1:
		await _pad_tap(JOY_BUTTON_DPAD_DOWN)
	await _pad_down(JOY_BUTTON_A)
	await _frames(3)
	_check(title._confirm_new and Profile.runs == runs, "the first accept only arms the overwrite")
	await _send(_pad_button(JOY_BUTTON_A, true))
	await _frames(4)
	_check(title._confirm_new and Profile.runs == runs and not Profile.run_checkpoint.is_empty(), "a duplicate A press without release does not overwrite")
	await _pad_up(JOY_BUTTON_A)
	await _frames(2)
	_check(title._confirm_new and Profile.runs == runs and not Profile.run_checkpoint.is_empty(), "releasing the held accept still does not overwrite")
	await _pad_tap(JOY_BUTTON_A)
	await _wait(0.5)
	_check(Profile.runs == runs + 1 and Profile.run_checkpoint.is_empty() and Game.in_hub, "release then a fresh A confirms the overwrite")


## Pause owns its focus; settings is a page above it, never a page swap. The
## walk covers every category in both locales and on both devices, proves the
## draft binding never reaches InputMap before a persisted Apply, rejects a
## conflict, and runs the real ten second display preview before restoring the
## committed defaults.
func _check_pause_settings(node_before: String) -> void:
	var hud = _main.hud
	var settings = _main.settings_screen
	_check(int(hud._pause_focus) == 0, "pause starts on the equipment row")
	await _pad_tap(JOY_BUTTON_X)
	_check(int(hud._pause_focus) == 1 and int(hud._pause_action) == 0,
		"pad X moves pause focus to the action row's Continue")
	await _pad_tap(JOY_BUTTON_DPAD_RIGHT)
	_check(int(hud._pause_action) == 1, "pad right moves the action row to Settings")
	await _pad_tap(JOY_BUTTON_DPAD_LEFT)
	_check(int(hud._pause_action) == 0, "pad left returns the action row to Continue")
	await _pad_tap(JOY_BUTTON_DPAD_DOWN)
	_check(int(hud._pause_action) == 0, "pad down scrolls details without changing the action focus")
	await _pad_tap(JOY_BUTTON_DPAD_RIGHT)
	_check(int(hud._pause_action) == 1, "pad right focuses Settings before confirming")
	var motion_epoch := Time.get_ticks_msec()
	await _send(_pad_button(JOY_BUTTON_A, true))
	var settings_opened: bool = is_instance_valid(settings) and settings.is_open()
	_check(settings_opened, "the pause Settings action opens the shared page")
	if not settings_opened:
		await _pad_up(JOY_BUTTON_A)
		return
	# STEP8 motion: the 100ms reveal and the 120ms focus settle are real
	# wall-clock tweens. Capture consecutive frames at honest measured times;
	# a second selection mid-flight must interrupt and restart the focus tween.
	var reveal_start_y := float(settings._canvas.position.y)
	_check(reveal_start_y > 0.0, "the settings reveal still starts offset after opening")
	if _capture:
		await _motion_view("settings-motion-reveal", motion_epoch, 0)
	await _pad_up(JOY_BUTTON_A)
	await _frames(1)
	var reveal_50 := await _motion_position(settings._canvas, motion_epoch, 50)
	_check(reveal_50 < reveal_start_y and reveal_50 >= 0.0, "the reveal moves inside its 100ms budget")
	if _capture:
		await _motion_view("settings-motion-reveal", motion_epoch, 50)
	var reveal_100 := await _motion_position(settings._canvas, motion_epoch, 100)
	_check(reveal_100 <= 2.0, "the reveal is settled at the 100ms budget")
	if _capture:
		await _motion_view("settings-motion-reveal", motion_epoch, 100)
	var reveal_150 := await _motion_position(settings._canvas, motion_epoch, 150)
	_check(reveal_150 == 0.0, "the reveal completes by 150ms")
	if _capture:
		await _motion_view("settings-motion-reveal", motion_epoch, 150)
	var focus_epoch := Time.get_ticks_msec()
	await _send(_pad_button(JOY_BUTTON_DPAD_DOWN, true))
	await _send(_pad_button(JOY_BUTTON_DPAD_DOWN, false))
	var focus_0 := float(settings._canvas.get_meta("ui_focus_progress", 1.0))
	_check(focus_0 < 1.0, "the focus tween starts below its settled value")
	if _capture:
		await _motion_view("settings-motion-focus", focus_epoch, 0)
	await _motion_wait(focus_epoch, 50)
	await _send(_pad_button(JOY_BUTTON_DPAD_UP, true))
	await _send(_pad_button(JOY_BUTTON_DPAD_UP, false))
	var focus_interrupted := float(settings._canvas.get_meta("ui_focus_progress", 1.0))
	_check(focus_interrupted < 1.0, "a consecutive focus change interrupts the running tween")
	if _capture:
		await _motion_view("settings-motion-focus", focus_epoch, 50)
	var focus_100 := await _motion_progress(settings._canvas, focus_epoch, 100)
	_check(focus_100 > focus_interrupted, "the restarted focus tween advances after the interrupt")
	if _capture:
		await _motion_view("settings-motion-focus", focus_epoch, 100)
	await _motion_wait(focus_epoch, 150)
	if _capture:
		await _motion_view("settings-motion-focus", focus_epoch, 150)
	await _motion_wait(focus_epoch, 240)
	_check(float(settings._canvas.get_meta("ui_focus_progress", 0.0)) == 1.0,
		"the interrupted focus tween still completes")
	_check(int(settings.content_row) == 0, "the motion fixture leaves settings on its first row")
	_check(hud.paused and get_tree().paused, "opening settings never clears the caller's pause")
	_check(settings.committed == Profile.preferences, "settings opens on the committed preferences")
	_check(settings.draft == settings.committed, "an untouched settings draft equals its committed values")

	await _settings_cycle(settings, "gamepad", "zh")
	await _settings_cycle(settings, "keyboard", "zh")

	await _settings_page(settings, 0, "gamepad")
	await _settings_input(settings, "gamepad", "down")
	var music_before := float(settings.draft["audio"]["music"])
	await _settings_input(settings, "gamepad", "left")
	_check(is_equal_approx(float(settings.draft["audio"]["music"]), music_before - 0.05),
		"an audio row decreases its draft value by the configured step immediately")
	await _settings_footer(settings, 1, "gamepad")
	await _settings_input(settings, "gamepad", "accept")
	_check(settings.draft["audio"] == Profile.DEFAULT_PREFERENCES["audio"],
		"Reset on the audio category restores only the audio draft")

	await _settings_page(settings, 2, "gamepad")
	await _settings_input(settings, "gamepad", "left")
	_check(str(settings.capture_device) == "keyboard", "the controls column switches back to keyboard")
	for _row in 6:
		await _settings_input(settings, "gamepad", "down")
	_check(int(settings.content_row) == 6, "the controls list scrolls to the jump action")
	await _settings_input(settings, "gamepad", "accept")
	_check(bool(settings.capture_active) and str(settings.capture_action) == "jump",
		"accept on jump waits for the next physical key")
	await _key(KEY_C)
	_check(not bool(settings.capture_active), "the captured key ends the wait")
	_check(int(settings.draft["input"]["keyboard"]["jump"]) == KEY_C,
		"a valid keyboard jump lands in the draft")
	_check(not _has_key(&"jump", KEY_C), "the draft keyboard jump is not live before Apply")
	await _settings_input(settings, "gamepad", "accept")
	_check(bool(settings.capture_active), "a second capture waits again")
	await _key(KEY_J)
	_check(bool(settings.capture_active) and str(settings._capture_notice_key) == "UI_SETTINGS_CONFLICT"
		and not str(settings._status_text()).is_empty(),
		"a key owned by attack is rejected by name and keeps the wait open")
	_check(int(settings.draft["input"]["keyboard"]["jump"]) == KEY_C,
		"a rejected conflict never changes the draft")
	await _key(KEY_ESCAPE)
	_check(not bool(settings.capture_active), "Esc cancels the rebind wait without closing settings")
	_check(int(settings.draft["input"]["keyboard"]["jump"]) == KEY_C,
		"cancel leaves the accepted draft binding intact")
	await _settings_input(settings, "gamepad", "right")
	_check(str(settings.capture_device) == "gamepad", "the controls column switches to gamepad")
	await _settings_input(settings, "gamepad", "accept")
	await _pad_tap(JOY_BUTTON_A)
	_check(not bool(settings.capture_active) and int(settings.draft["input"]["gamepad"]["jump"]["index"]) == JOY_BUTTON_A,
		"a valid pad A jump lands in the draft")
	await _settings_input(settings, "gamepad", "accept")
	await _pad_tap(JOY_BUTTON_X)
	_check(bool(settings.capture_active) and str(settings._capture_notice_key) == "UI_SETTINGS_CONFLICT"
		and not str(settings._status_text()).is_empty(),
		"pad X owned by attack is rejected as a jump binding")
	await _pad_tap(JOY_BUTTON_B)
	_check(not bool(settings.capture_active), "B cancels the pad rebind wait")

	await _settings_page(settings, 3, "gamepad")
	await _settings_input(settings, "gamepad", "right")
	_check(str(settings.draft["general"]["locale"]) == "en", "the language draft toggles to English")
	_check(TranslationServer.get_locale() == "en", "an unapplied language preview is visible immediately")
	_check(str(Profile.preferences["general"]["locale"]) == "zh_TW",
		"the language preview has not changed the committed preferences")
	_check(not _has_key(&"jump", KEY_C), "the language preview still uses committed input")
	if _capture:
		await _save_view("settings-language-gamepad-en-preview")
	await _settings_footer(settings, 0, "gamepad")
	await _settings_input(settings, "gamepad", "accept")
	await _frames(3)
	_check(str(Profile.preferences["general"]["locale"]) == "en",
		"Apply persists the English language choice")
	_check(int(Profile.preferences["input"]["keyboard"]["jump"]) == KEY_C,
		"Apply persists the keyboard jump draft")
	_check(int(Profile.preferences["input"]["gamepad"]["jump"]["index"]) == JOY_BUTTON_A,
		"Apply persists the gamepad jump draft")
	_check(str(settings.status_key) == "UI_SETTINGS_APPLIED", "the page confirms the applied settings")
	_check(_has_key(&"jump", KEY_C), "the stored keyboard jump becomes live only after Apply")
	_check(not _has_key(&"jump", KEY_SPACE), "the new keyboard jump replaces the old default")
	_check(_has_key(&"jump_explicit", KEY_C), "jump_explicit mirrors the applied keyboard jump")
	_check(_has_button(&"jump_explicit", JOY_BUTTON_A), "jump_explicit mirrors the applied pad jump")
	_check(FileAccess.file_exists(Profile._settings_path), "a successful Apply writes the preference file")

	await _settings_cycle(settings, "keyboard", "en")
	await _settings_cycle(settings, "gamepad", "en")

	await _settings_page(settings, 1, "keyboard")
	await _settings_input(settings, "keyboard", "right")
	_check(str(settings.draft["display"]["window_mode"]) == "fullscreen",
		"the display draft requests the native fullscreen mode")
	if _capture:
		await _save_view("settings-display-keyboard-en")
	var applied_bytes := _text(Profile._settings_path)
	await _settings_footer(settings, 0, "keyboard")
	await _settings_input(settings, "keyboard", "accept")
	await _frames(2)
	_check(bool(settings.display_preview_active), "Apply on a display change starts the preview")
	var remaining := int(settings.preview_deadline_ms) - Time.get_ticks_msec()
	_check(remaining > 9000 and remaining <= 10000,
		"the preview uses the real ten second wall-clock deadline")
	_check(bool(Interface._fullscreen_active), "the headless preview applies its display state")
	_check(str(Profile.preferences["display"]["window_mode"]) == "windowed",
		"the display preview has not changed committed preferences")
	_check(_text(Profile._settings_path) == applied_bytes,
		"the display preview has not written the preference file")
	if _capture:
		await _save_view("settings-display-preview-en")
	await _wait(10.2)
	await _frames(3)
	_check(not bool(settings.display_preview_active), "the unconfirmed preview expires by wall clock")
	_check(str(settings.status_key) == "UI_SETTINGS_PREVIEW_EXPIRED",
		"the expired preview reports its own status")
	_check(not bool(Interface._fullscreen_active), "the expired preview restores the old display mode")
	_check(str(Profile.preferences["display"]["window_mode"]) == "windowed",
		"the expired preview keeps committed display preferences")
	_check(_text(Profile._settings_path) == applied_bytes,
		"the expired preview never writes the preference file")
	await _key(KEY_ESCAPE)
	await _frames(2)
	_check(not settings.is_open() and hud.paused and get_tree().paused,
		"closing settings after a preview returns to the still-paused game")
	_check(int(hud._pause_focus) == 1 and int(hud._pause_action) == 1,
		"the pause action row keeps its Settings focus after the page closes")

	await _pad_tap(JOY_BUTTON_A)
	await _frames(3)
	_check(settings.is_open(), "the retained Settings action reopens the page")
	for target in [2, 0, 1, 3]:
		await _settings_page(settings, target, "gamepad")
		await _settings_footer(settings, 1, "gamepad")
		await _settings_input(settings, "gamepad", "accept")
	await _settings_footer(settings, 0, "gamepad")
	await _settings_input(settings, "gamepad", "accept")
	await _frames(3)
	_check(Profile.preferences == Profile.DEFAULT_PREFERENCES,
		"resetting each category and applying restores the committed defaults")
	_check(TranslationServer.get_locale() == "zh_TW", "the restored locale is zh_TW")
	_check(not bool(Interface._fullscreen_active), "the restored display mode is windowed")
	_check(_has_key(&"jump", KEY_SPACE) and _has_key(&"jump", KEY_W) and _has_key(&"jump", KEY_UP),
		"the default jump keyboard bindings are restored")
	_check(_has_key(&"jump_explicit", KEY_SPACE) and _has_button(&"jump_explicit", JOY_BUTTON_A),
		"jump_explicit is restored to Space and pad A")
	_check(not _has_key(&"jump_explicit", KEY_W) and not _has_key(&"jump_explicit", KEY_UP),
		"jump_explicit still never owns the W / Up climb alias")
	await _check_settings_cancel(settings)
	if not settings.is_open():
		return
	await _check_settings_write_failure(settings)
	if not settings.is_open():
		return
	await _pad_tap(JOY_BUTTON_B)
	await _frames(2)
	_check(not settings.is_open() and hud.paused and get_tree().paused,
		"B closes settings and leaves the pause overlay open")
	_check(int(hud._pause_focus) == 1 and int(hud._pause_action) == 1,
		"closing settings does not reset the pause action focus")
	_check(not Game.player.hitbox.active and Game.player.state != Player.State.ATTACK,
		"closing settings never falls through to an attack")
	_check(Game.run_node_id == node_before, "closing settings never restarts or moves the run")


func _check_settings_cancel(settings) -> void:
	var settings_bytes := _text(Profile._settings_path)
	var music_index := AudioServer.get_bus_index("Music")
	await _settings_page(settings, 0, "gamepad")
	await _settings_input(settings, "gamepad", "down")
	await _settings_input(settings, "gamepad", "left")
	await _frames(2)
	_check(float(settings.draft["audio"]["music"]) < 1.0,
		"an audio draft changes as soon as the row value moves")
	_check(float(Profile.preferences["audio"]["music"]) == 1.0,
		"the audio draft never commits to Profile before Apply")
	_check(music_index >= 0 and not AudioServer.is_bus_mute(music_index),
		"the audio preview keeps the Music bus audible")
	await _pad_tap(JOY_BUTTON_B)
	await _frames(2)
	_check(not settings.is_open() and _main.hud.paused and get_tree().paused,
		"B cancels the audio draft and leaves the pause overlay open")
	_check(float(Profile.preferences["audio"]["music"]) == 1.0
		and absf(db_to_linear(AudioServer.get_bus_volume_db(music_index)) - 1.0) < 0.02,
		"cancelling the audio draft restores the committed gain")
	_check(_text(Profile._settings_path) == settings_bytes,
		"cancelling the audio draft keeps the committed preference bytes")
	_check(int(_main.hud._pause_focus) == 1 and int(_main.hud._pause_action) == 1,
		"cancelling settings keeps the pause Settings focus")
	await _pad_tap(JOY_BUTTON_A)
	await _frames(3)
	_check(settings.is_open(), "the pause Settings action reopens the page after a cancel")
	await _settings_page(settings, 3, "gamepad")
	await _settings_input(settings, "gamepad", "right")
	await _frames(2)
	_check(str(settings.draft["general"]["locale"]) == "en"
		and TranslationServer.get_locale() == "en",
		"the language draft previews English immediately")
	_check(str(Profile.preferences["general"]["locale"]) == "zh_TW",
		"the language preview never commits to Profile before Apply")
	await _pad_tap(JOY_BUTTON_B)
	await _frames(2)
	_check(not settings.is_open() and TranslationServer.get_locale() == "zh_TW",
		"B cancels the language draft and restores the committed locale")
	_check(str(Profile.preferences["general"]["locale"]) == "zh_TW"
		and _text(Profile._settings_path) == settings_bytes,
		"cancelling the language draft keeps committed preferences and bytes")
	_check(_main.hud.paused and get_tree().paused,
		"cancelling the language draft never unpauses the game")
	await _pad_tap(JOY_BUTTON_A)
	await _frames(3)
	_check(settings.is_open(), "the pause Settings action reopens after the language cancel")


func _check_settings_write_failure(settings) -> void:
	var real_path := str(Profile._settings_path)
	var blocker := "user://ashfall_ui_blocker_%d" % OS.get_process_id()
	var blocker_file := FileAccess.open(blocker, FileAccess.WRITE)
	_check(blocker_file != null, "the settings failure fixture creates its blocker file")
	if blocker_file == null:
		return
	blocker_file.store_string("blocked")
	blocker_file.close()
	var blocker_absolute := ProjectSettings.globalize_path(blocker)
	var blocked_path := blocker_absolute.path_join("settings.cfg")
	var bytes_before := _text(real_path)
	var run_before := JSON.stringify(Profile.run_checkpoint)
	var slot_before := _text(Profile.slot_path(1))
	var committed_before: Dictionary = settings.committed.duplicate(true)
	var save_error_before := str(Profile.last_save_error)
	var blocked_before := bool(Profile._save_blocked)
	var display_before := bool(Interface._fullscreen_active)
	Profile._settings_path = blocked_path
	await _settings_page(settings, 0, "gamepad")
	await _settings_input(settings, "gamepad", "right")
	await _settings_footer(settings, SettingsScreen.FOOTER_APPLY, "gamepad")
	await _settings_input(settings, "gamepad", "accept")
	await _frames(3)
	_check(str(settings.status_key) == "UI_SETTINGS_SAVE_FAILED",
		"a failed Apply keeps the settings page on the save-failure state")
	_check(str(settings.last_error).begins_with("CANNOT WRITE PREFERENCES:"),
		"the page exposes the real preference write failure")
	_check(not FileAccess.file_exists(blocked_path), "a failed preference write creates no partial file")
	_check(settings.committed == committed_before and Profile.preferences == committed_before,
		"a failed preference write retains the committed settings")
	_check(_text(real_path) == bytes_before,
		"a failed preference write retains the original preference bytes")
	_check(JSON.stringify(Profile.run_checkpoint) == run_before and _text(Profile.slot_path(1)) == slot_before,
		"a failed preference write never changes progress or the checkpoint")
	_check(str(Profile.last_save_error) == save_error_before and bool(Profile._save_blocked) == blocked_before,
		"preference failure stays independent of the progress save state")
	_check(bool(Interface._fullscreen_active) == display_before,
		"preference failure never changes the display mode")
	Profile._settings_path = real_path
	Profile.load_preferences()
	var reason := str(settings.last_error) + " " \
		+ "Retry the destination or cancel; the original settings remain committed. ".repeat(30) \
		+ "END_SENTINEL"
	settings.last_error = reason
	settings.status_args["reason"] = reason
	settings._canvas.queue_redraw()
	await _frames(3)
	_check(int(settings.status_detail_max_scroll) > 0,
		"a long save diagnostic exposes a bounded failure-detail scroll range")
	if _capture:
		await _save_view("settings-save-failed-zh_TW-before")
	await _settings_scroll_detail_to_end(settings)
	_check(int(settings.status_detail_scroll) == int(settings.status_detail_max_scroll),
		"real ui_detail_down input reaches the end of the full save diagnostic")
	var zh_lines: Array = MathArt.ui_wrap(str(settings._status_text()), 664.0 - 32.0, 11)
	_check(not zh_lines.is_empty() and "".join(zh_lines).contains("END_SENTINEL"),
		"wrapping the save diagnostic keeps every character of the raw reason")
	if _capture:
		await _save_view("settings-save-failed-zh_TW-after")
	TranslationServer.set_locale("en")
	settings._canvas.queue_redraw()
	await _frames(3)
	settings.status_detail_scroll = 0
	settings._canvas.queue_redraw()
	await _frames(2)
	if _capture:
		await _save_view("settings-save-failed-en-before")
	await _settings_scroll_detail_to_end(settings)
	var en_lines: Array = MathArt.ui_wrap(str(settings._status_text()), 664.0 - 32.0, 11)
	_check(not en_lines.is_empty() and "".join(en_lines).contains("END_SENTINEL"),
		"the English failure detail keeps every character of the raw reason")
	if _capture:
		await _save_view("settings-save-failed-en-after")
	Interface.apply_preferences(Profile.preferences)
	await _frames(2)
	_check(TranslationServer.get_locale() == "zh_TW", "the failure fixture restores the committed locale")
	await _settings_page(settings, 1, "gamepad")
	_check(str(settings.status_key).is_empty() and int(settings.status_detail_scroll) == 0,
		"changing category clears the failure detail and its scroll")
	DirAccess.remove_absolute(blocker_absolute)
	_check(not FileAccess.file_exists(blocker_absolute), "the failure fixture removes its blocker file")


func _settings_scroll_detail_to_end(settings) -> void:
	var guard := 0
	while int(settings.status_detail_scroll) < int(settings.status_detail_max_scroll) and guard < 80:
		var before := int(settings.status_detail_scroll)
		await _key(KEY_DOWN)
		guard += 1
		if int(settings.status_detail_scroll) == before:
			break


func _settings_cycle(settings, device: String, tag: String) -> void:
	for target in SETTINGS_PAGES.size():
		await _settings_page(settings, target, device)
		_check(int(settings.page_index) == target, "the settings category %s is reachable" % SETTINGS_PAGES[target])
		var row_before := int(settings.content_row)
		await _settings_input(settings, device, "down")
		await _settings_input(settings, device, "up")
		_check(int(settings.content_row) == row_before and not bool(settings.footer_focused),
			"the %s category moves its content focus with %s" % [SETTINGS_PAGES[target], device])
		if _capture:
			await _save_view("settings-%s-%s-%s" % [tag, device, SETTINGS_PAGES[target]])


func _settings_page(settings, target: int, device: String) -> void:
	var guard := 0
	while int(settings.page_index) != target and guard < 4:
		await _settings_input(settings, device, "tab_next")
		guard += 1


func _settings_footer(settings, target: int, device: String) -> void:
	var guard := 0
	while not bool(settings.footer_focused) and guard < 20:
		await _settings_input(settings, device, "down")
		guard += 1
	guard = 0
	while int(settings.footer_action) != target and guard < 3:
		await _settings_input(settings, device, "right")
		guard += 1


func _settings_input(settings, device: String, action: String) -> void:
	if device == "gamepad":
		match action:
			"down": await _pad_tap(JOY_BUTTON_DPAD_DOWN)
			"up": await _pad_tap(JOY_BUTTON_DPAD_UP)
			"left": await _pad_tap(JOY_BUTTON_DPAD_LEFT)
			"right": await _pad_tap(JOY_BUTTON_DPAD_RIGHT)
			"accept": await _pad_tap(JOY_BUTTON_A)
			"back": await _pad_tap(JOY_BUTTON_B)
			"tab_next": await _pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
			"tab_prev": await _pad_tap(JOY_BUTTON_LEFT_SHOULDER)
	else:
		match action:
			"down": await _key(KEY_DOWN)
			"up": await _key(KEY_UP)
			"left": await _key(KEY_LEFT)
			"right": await _key(KEY_RIGHT)
			"accept": await _key(KEY_ENTER)
			"back": await _key(KEY_ESCAPE)
			"tab_next": await _key(KEY_PAGEDOWN)
			"tab_prev": await _key(KEY_PAGEUP)
	await _frames(1)


## Last consumer proof: the pause action row's own Quit item exits the real
## product. If it works, the process exits before this function returns.
func _check_pause_quit() -> void:
	_main.start_node(str(Data.route_graph.start))
	await _wait(0.6)
	await _frames(3)
	await _pad_tap(JOY_BUTTON_START)
	await _frames(3)
	await _pad_tap(JOY_BUTTON_X)
	var hud = _main.hud
	var guard := 0
	while int(hud._pause_action) != 4 and guard < 6:
		await _pad_tap(JOY_BUTTON_DPAD_RIGHT)
		guard += 1
	await _frames(2)
	await _pad_tap(JOY_BUTTON_A)
	await _wait(0.4)


func _text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "<absent>"
	return FileAccess.get_file_as_string(path)


func _has_key(action: StringName, code: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and int((event as InputEventKey).physical_keycode) == code:
			return true
	return false


func _has_button(action: StringName, index: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and int((event as InputEventJoypadButton).button_index) == index:
			return true
	return false


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		return
	_fails += 1
	print("UI PRODUCT FAIL: " + message)
	push_error("UI PRODUCT FAIL: " + message)
