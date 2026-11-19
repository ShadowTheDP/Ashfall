extends Node
## Font-measured world labels plus real keyboard/modal input on the fixed viewport.
var _checks := 0
var _fails := 0
var _map: Node



func _ready() -> void:
	if not Data.is_node_ready():
		await Data.ready
	if not Interface.is_node_ready():
		await Interface.ready
	if not Sfx.is_node_ready():
		await Sfx.ready
	TranslationServer.set_locale("en")
	process_mode = Node.PROCESS_MODE_ALWAYS
	assert(Profile.require_test_profile())
	Profile.reset_profile()
	await get_tree().process_frame
	$Main._on_descend(1)
	await get_tree().create_timer(0.7).timeout
	_map = $Main.exploration_map
	_check(_map._world_layout().keys() == ["ash_gate"], "fresh profile reveals only the visited start")
	Profile.unlocked_runes.append("canopy_rune")
	_check(not _map._world_layout().has("silt_cistern"), "unlock alone does not reveal Cistern")
	Profile.seen_biomes.assign(Data.route_graph.default_0_bsc_route)
	await _key(KEY_TAB)
	_check(_map.is_open() and get_tree().paused and not Game.player.can_process(), "Tab opens map and pauses gameplay")
	await _key(KEY_RIGHT)
	_check(_map._tab == 1, "keyboard reaches world map")
	_layout("primary")
	_locks()
	await _shot("world-primary")
	Profile.seen_biomes.append("silt_cistern")
	_check(_map._world_layout().size() == 10 and _map._world_layout().has("silt_cistern"), "visited unlocked Cistern joins nine-visit main route")
	_check(preload("res://scripts/systems/route_graph.gd").lock_reason({"requires_runes": ["canopy_rune"]}, Game.route_state()).is_empty(), "Cistern branch is unlocked")
	_map._canvas.queue_redraw()
	_layout("cistern")
	_locks()
	await _shot("world-cistern")
	var body := Game.player
	var before := [body.global_position, body.hp, body.knife_charges, Game.flask_charges, Game.exit_selected]
	for code in [KEY_UP, KEY_DOWN, KEY_W, KEY_S, KEY_ENTER, KEY_F, KEY_H, KEY_J, KEY_K, KEY_L, KEY_SPACE, KEY_R]:
		await _key(code)
	_check(_map.is_open() and before == [body.global_position, body.hp, body.knife_charges, Game.flask_charges, Game.exit_selected], "world map consumes navigation and gameplay actions")
	await _key(KEY_LEFT)
	_check(_map._tab == 0 and _map._index >= 0 and _map._index < maxi(1, _map._snapshot.get("pads", []).size()), "local map retains valid keyboard selection")
	for i in 8:
		_map._snapshot.markers.append({"pos": _map._snapshot.player, "label": "LONG DISCOVERED PLACE %d" % i, "reason": "Requires a discovered key"})
	_map._canvas.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_map._place_rows() == 2, "browsing shows the two-line place window")
	await _key(KEY_PAGEDOWN)
	_check(_map._place_count > 2 and _map._place_scroll == 2 and _map._tab == 0, "PageDown reveals overflow places without changing map or teleport target")
	await _shot("biome-long-places-fixture")
	await _key(KEY_PAGEUP)
	_check(_map._place_scroll == 0, "PageUp returns to first discovered place")
	for i in 20: await _key(KEY_PAGEDOWN)
	_check(_map._place_scroll == _map._place_count - _map._place_rows(), "browse paging stops on the last two places")
	# Travel mode keeps the side list, so it pages six at a time and still refuses
	# an unreached source instead of teleporting on browse.
	_map.close()
	# Stand where no checkpoint can briefly claim the player: the outcome must be
	# "no travel source", not an accident of the spawn point.
	var room := $Main.level.data["rooms"][0]["rect"] as Rect2
	var spot := room.position + Vector2(room.size.x * 0.5, -40.0)
	var best := -1.0
	for tx in [0.15, 0.5, 0.85]:
		var candidate := room.position + Vector2(room.size.x * float(tx), -40.0)
		var nearest := 1000000.0
		for pad: Dictionary in $Main.level.data["pads"]:
			nearest = minf(nearest, candidate.distance_to(pad["pos"]))
		if nearest > best:
			best = nearest
			spot = candidate
	Game.player.relocate(spot)
	_map.open($Main.level, true)
	await get_tree().process_frame
	_check(_map._teleport and _map._place_rows() == 6, "checkpoint map offers the six-line side list")
	_check(_map._place_scroll <= maxi(0, _map._place_count - 6), "travel paging stays inside its own window")
	_check(_map._source.is_empty(), "refusal fixture starts away from a teleporter")
	await _key(KEY_ENTER)
	_check(_map.is_open() and _map._status_error and _map._status == ContentText.of("UI_MAP_TRAVEL_AT_TELEPORTER", "Travel is available only while standing at a teleporter."), "blocked travel paints its reason inside the paused map")
	await _key(KEY_RIGHT)
	_check(_map._tab == 1, "travel page still switches to the world tab")
	await _key(KEY_ENTER)
	_check(_map.is_open() and _map._status_error and _map._status == ContentText.of("UI_S7_MAP_STATUS_WORLD", "World map is browse only. Open a local map at a checkpoint to travel."), "world tab explains that it is browse only")
	_map.close()
	_map.open($Main.level)
	await get_tree().process_frame
	_fit_checks()
	var browse_index: int = _map._index
	await _key(KEY_DOWN)
	_check(_map._index == browse_index, "browse up/down never moves the teleport target")
	_check(not _map._teleport and _map._source.is_empty(), "browse mode never offers travel")
	await _key(KEY_ESCAPE)
	_check(not _map.is_open() and not get_tree().paused and not $Main.hud.paused, "Escape returns to gameplay without opening pause menu")
	await _key(KEY_TAB)
	_check(_map.is_open() and _map._tab == 0, "reopening resets map focus")
	await _key(KEY_TAB)
	_check(not _map.is_open() and not get_tree().paused, "Tab closes map")
	var biome_id: String = str(($Main.level as Level).route_node)
	var biome_node: Dictionary = Data.route_graph["nodes"][biome_id]
	var canonical: String = str(biome_node.get("name", "")).to_upper()
	TranslationServer.set_locale("zh_TW")
	_map.open($Main.level)
	_check(_map._floor_display() == ContentText.name("biome", biome_id, canonical), "biome map name uses the open locale")
	TranslationServer.set_locale("en")
	_check(_map._floor_display() == canonical, "biome map name follows a locale change while open")
	_map.close()
	var passage := Passage.new()
	TranslationServer.set_locale("zh_TW")
	_map.open(passage)
	_check(_map._floor_display() == ContentText.of("UI_PASSAGE_MAP_NAME", "Passage").to_upper(), "Passage map name uses the open locale")
	TranslationServer.set_locale("en")
	_check(_map._floor_display() == ContentText.of("UI_PASSAGE_MAP_NAME", "Passage").to_upper(), "Passage map name follows a locale change while open")
	_map.close()
	passage.free()
	await _marker_regression()
	print("MAP LAYOUT %s (%d checks, %d failures)" % ["OK" if _fails == 0 else "FAILED", _checks, _fails])
	get_tree().quit(1 if _fails else 0)


func _layout(case: String) -> void:
	var layout: Dictionary = _map._world_layout()
	var ids: Array = layout.keys()
	var area := Rect2(40, 110, 688, 266)
	var font := MathArt.ui_font()
	for i in ids.size():
		var item: Dictionary = layout[ids[i]]
		var rect: Rect2 = item.label
		_check(area.encloses(rect), case + " label stays in content area: " + str(ids[i]))
		var joined := "".join(item.lines)
		_check(joined == str(Data.route_graph.nodes[ids[i]].name), case + " name remains complete: " + str(ids[i]) + " actual=" + joined + " lines=" + str(item.lines))
		for line: String in item.lines:
			_check(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x <= rect.size.x + 0.01, case + " uses actual 11px font width")
		for j in range(i + 1, ids.size()):
			_check(not rect.grow(2).intersects(layout[ids[j]].label), case + " label overlap: " + str(ids[i]) + " / " + str(ids[j]))
		for other in ids:
			_check(not rect.intersects(Rect2((layout[other].at as Vector2) - Vector2.ONE * 16, Vector2.ONE * 32)), case + " label clears node " + str(other))


func _locks() -> void:
	var layout: Dictionary = _map._world_layout()
	var labels: Array[Rect2] = []
	for edge: Dictionary in Data.route_graph.edges:
		if not layout.has(edge.from) or not layout.has(edge.to):
			continue
		var reason: String = preload("res://scripts/systems/route_graph.gd").lock_reason(edge, Game.route_state())
		if reason.is_empty():
			continue
		var note: Dictionary = _map._world_lock_label(layout[edge.from].at, layout[edge.to].at, reason)
		var rect: Rect2 = note.rect
		_check(Rect2(40, 110, 688, 266).encloses(rect), "lock condition stays in content area")
		_check((note.text as String).replace("\n", " ") == "LOCKED: " + reason, "complete lock condition is retained")
		for previous: Rect2 in labels:
			_check(not rect.grow(2).intersects(previous), "lock conditions do not overlap")
		for other: Dictionary in layout.values():
			_check(not rect.intersects(other.label) and not rect.intersects(Rect2((other.at as Vector2) - Vector2.ONE * 16, Vector2.ONE * 32)), "lock condition clears names and nodes")
		labels.append(rect)


func _key(code: int) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		if DisplayServer.get_name() != "headless": print("WORLD_MAP_PROBE INPUT %dms key=%d pressed=%s" % [Time.get_ticks_msec(), code, str(event.pressed)])
		await get_tree().process_frame


func _shot(label: String) -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	await get_tree().process_frame
	$Main.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image.get_size() == Vector2i(768, 480) and DisplayServer.window_get_size() == Vector2i(1536, 960), "capture retains logical viewport and x2 window")
	DirAccess.make_dir_recursive_absolute("res://output/audit-fixes")
	_check(image.save_png("res://output/audit-fixes/" + label + ".png") == OK, "capture saved")


	await _physical_capture(label)
	print("WORLD_MAP_PROBE FRAME %dms %s" % [Time.get_ticks_msec(), label])
	if OS.get_environment("ASHFALL_CAPTURE_ACK_DIR").is_empty(): await get_tree().create_timer(0.08, true).timeout
	return image


## D1: map_snapshot() localizes marker captions, so ExplorationMap must choose a
## marker's shape and tone from its machine kind, never from that text. The
## teleporter is the discriminating marker: English keeps the TELEPORT caption
## while zh_TW localizes it, yet both locales must paint the identical
## CELL-toned diamond at the identical spot. Real Tab/Escape events drive the
## real page; this never reads marker kinds or renderer source.
func _marker_regression() -> void:
	# The first real open hands over the live level without a tree-path guess.
	await _key(KEY_TAB)
	_check(_map.is_open(), "marker fixture opens the map")
	if not _map.is_open(): return
	var level: Node = _map._level
	await _key(KEY_ESCAPE)
	var body := Game.player
	body.invuln = 1000.0
	var pad := _checkpoint_pad(level)
	_check(not pad.is_empty(), "fixture level owns a checkpoint pad")
	if pad.is_empty(): return
	var pad_pos: Vector2 = pad["pos"]
	var start: Vector2 = body.global_position
	var body_mode := body.process_mode
	body.relocate(pad_pos)
	for i in 6: await get_tree().physics_frame
	_check(level._active_pads.has(str(pad["id"])), "fixture activates the checkpoint pad")
	var room_index := -1
	for i in level.data["rooms"].size():
		if str(level.data["rooms"][i]["id"]) == str(pad["room"]):
			room_index = i
	if room_index >= 0 and not level._room_entered[room_index]:
		level._enter_room(room_index)
	_check(room_index >= 0 and level._room_entered[room_index], "teleporter room is entered")
	body.relocate(start)
	for i in 2: await get_tree().physics_frame
	# One frozen player and no animated backdrop: the open page is the only variable.
	body.process_mode = Node.PROCESS_MODE_DISABLED
	var world: CanvasItem = $Main.world
	var hidden: Array[CanvasLayer] = []
	for child: Node in $Main.get_children():
		if child is CanvasLayer and child != _map and not child.is_ancestor_of(_map) and (child as CanvasLayer).visible:
			hidden.append(child)
			(child as CanvasLayer).visible = false
	world.visible = false
	TranslationServer.set_locale("en")
	await _key(KEY_TAB)
	_check(_map.is_open(), "Tab opens the marker map")
	await _settle_map()
	var en_snapshot: Dictionary = _map._snapshot.duplicate(true)
	var en_places: int = _map._place_count
	var en_image: Image = await _shot("world-markers-en")
	var en_stripped: Dictionary = en_snapshot.duplicate(true)
	_strip_marker(en_stripped, pad_pos)
	var en_stripped_places := await _place_count_for(en_stripped)
	_check(en_stripped_places == en_places, "English teleporter stays out of the known-places window")
	await _key(KEY_ESCAPE)
	_check(not _map.is_open(), "Escape closes the marker map")
	# Reopen instead of patching the snapshot: the producer localizes the label
	# for real, so the second page is what a zh_TW player actually sees.
	TranslationServer.set_locale("zh_TW")
	await _key(KEY_TAB)
	_check(_map.is_open(), "Tab reopens the marker map for zh_TW")
	await _settle_map()
	var zh_snapshot: Dictionary = _map._snapshot.duplicate(true)
	var zh_places: int = _map._place_count
	var zh_image: Image = await _shot("world-markers-zh-tw")
	var zh_stripped: Dictionary = zh_snapshot.duplicate(true)
	_strip_marker(zh_stripped, pad_pos)
	var zh_stripped_places := await _place_count_for(zh_stripped)
	_check(zh_stripped_places == zh_places, "zh_TW teleporter stays out of the known-places window")
	var en_label := _marker_at(en_snapshot, pad_pos)
	var zh_label := _marker_at(zh_snapshot, pad_pos)
	_check(en_label == "TELEPORT", "English snapshot keeps the teleporter caption")
	_check(not zh_label.is_empty() and zh_label != en_label, "zh_TW localizes the teleporter caption")
	if en_image != null and zh_image != null and not en_snapshot.get("rooms", []).is_empty():
		_check(not _map._teleport, "marker captures ride the browse map")
		var crop := _marker_crop(en_snapshot, pad_pos)
		_check(Rect2i(Vector2i.ZERO, Vector2i(768, 480)).encloses(crop), "teleporter crop stays on the painted map")
		print("MAP MARKER CROP %s en=%s zh=%s" % [str(crop), en_label, zh_label])
		var en_patch := en_image.get_region(crop)
		var zh_patch := zh_image.get_region(crop)
		# The canonical ready-teleporter tone is required, so two generic ACCENT
		# rings cannot pass as equivalent markers.
		_check(_tone_pixels(en_patch, MathArt.CELL) >= 3, "English teleporter keeps its CELL diamond")
		_check(_tone_pixels(zh_patch, MathArt.CELL) >= 3, "zh_TW teleporter keeps the same CELL diamond")
		_check(en_patch.get_data() == zh_patch.get_data(), "zh_TW and en paint the identical teleporter marker")
		_check(en_image.get_data() != zh_image.get_data(), "the same map localizes its captions")
	await _key(KEY_ESCAPE)
	TranslationServer.set_locale("en")
	for layer: CanvasLayer in hidden:
		layer.visible = true
	world.visible = true
	body.process_mode = body_mode


func _settle_map() -> void:
	for i in 4: await get_tree().process_frame
	await get_tree().create_timer(0.15, true).timeout


func _marker_at(snapshot: Dictionary, at: Vector2) -> String:
	for marker: Dictionary in snapshot.get("markers", []):
		if (marker["pos"] as Vector2).distance_to(at) <= 0.01:
			return str(marker["label"])
	return ""


## Prefer a checkpoint away from the spawn: the player square must not cover
## the teleporter crop, and the entry pad is the landing spot.
func _checkpoint_pad(level: Node) -> Dictionary:
	var fallback := {}
	var away := {}
	for pad: Dictionary in level.data.get("pads", []):
		if str(pad.get("kind", "")) != "checkpoint":
			continue
		if fallback.is_empty(): fallback = pad
		if str(pad.get("id", "")) != "entry": away = pad
	return away if not away.is_empty() else fallback


func _strip_marker(snapshot: Dictionary, at: Vector2) -> void:
	var kept: Array = []
	for marker: Dictionary in snapshot.get("markers", []):
		if (marker["pos"] as Vector2).distance_to(at) > 0.01:
			kept.append(marker)
	snapshot["markers"] = kept


## The page's own browse fit. Delegating to the map keeps the probe honest:
## a changed padding rule or 1:1 cap moves this point too.
func _plot_point(snapshot: Dictionary, at: Vector2) -> Vector2:
	var rooms: Array = snapshot.get("rooms", [])
	if rooms.is_empty():
		return Vector2.INF
	var transform: Dictionary = _map.plot_transform(rooms)
	return (transform["origin"] as Vector2) + at * float(transform["scale"])


## Discovered bounds grow into the plot but keep 24px breathing room; a single
## small room is centred rather than blown up past 1:1.
func _fit_checks() -> void:
	var inner: Rect2 = _map._plot_area().grow(-24.0)
	var single: Dictionary = _map.plot_transform([{"bounds": Rect2(0, 0, 80, 60)}])
	var scale := float(single["scale"])
	_check(absf(scale - 1.0) < 0.001, "single room caps at 1:1")
	var center: Vector2 = (single["origin"] as Vector2) + Vector2(40, 30) * scale
	_check(center.distance_to(inner.get_center()) < 0.01, "single room centres inside the padded plot")
	var many: Array = []
	for i in 12:
		many.append({"bounds": Rect2(i * 200, 0, 180, 140)})
	var fit: Dictionary = _map.plot_transform(many)
	var origin: Vector2 = fit["origin"]
	var many_scale := float(fit["scale"])
	_check(many_scale < 1.0, "wide discovered bounds shrink to fit")
	for room: Dictionary in many:
		var rect: Rect2 = room["bounds"]
		var mapped := Rect2(origin + rect.position * many_scale, rect.size * many_scale)
		_check(inner.grow(0.5).encloses(mapped), "every discovered room stays inside the 24px padding")


## Marker-only crop: excludes the localized caption rows below the plot.
func _marker_crop(snapshot: Dictionary, at: Vector2) -> Rect2i:
	var radius := 7
	var point := _plot_point(snapshot, at)
	return Rect2i(Vector2i(roundi(point.x) - radius, roundi(point.y) - radius), Vector2i(radius * 2 + 1, radius * 2 + 1))


## Patch tone test: pixels nearer `tone` than to any other palette entry count as
## that tone, so a CELL diamond is distinguishable from a generic ACCENT ring.
func _tone_pixels(image: Image, tone: Color) -> int:
	var palette := [tone, MathArt.ACCENT, MathArt.PLAYER, MathArt.INK, MathArt.STONE_DIM, MathArt.STONE_HI, MathArt.BG_2]
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			var best := INF
			var best_index := -1
			for i in palette.size():
				var swatch: Color = palette[i]
				var distance := pow(pixel.r - swatch.r, 2.0) + pow(pixel.g - swatch.g, 2.0) + pow(pixel.b - swatch.b, 2.0)
				if distance < best:
					best = distance
					best_index = i
			if best_index == 0: count += 1
	return count


func _place_count_for(snapshot: Dictionary) -> int:
	_map._snapshot = snapshot
	_map._canvas.queue_redraw()
	for i in 3: await get_tree().process_frame
	return _map._place_count

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("MAP LAYOUT FAIL: " + message)

func _physical_capture(label: String) -> void:
	var directory := OS.get_environment("ASHFALL_CAPTURE_ACK_DIR")
	if directory.is_empty(): return
	var path := directory.path_join(label + ".json")
	var deadline := Time.get_ticks_msec() + 1500
	while not FileAccess.file_exists(path) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(FileAccess.file_exists(path), "owned physical capture acknowledgement: " + label)
