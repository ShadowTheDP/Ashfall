extends CanvasLayer
## Discovered rooms/world only. Travel requires a physically reached checkpoint.
const GRAPH := preload("res://scripts/systems/route_graph.gd")
var _canvas: Control
var _snapshot: Dictionary = {}
var _level: Node
var _source := ""
var _tab := 0
var _index := 0
var _place_scroll := 0
var _place_count := 0
## Whether this map was opened at a checkpoint, i.e. travel is on offer.
var _teleport := false
## Set only when this page itself paused the tree.
var _owns_pause := false
var _locale := ""
## Full-page map owns its feedback: the HUD announcement is suppressed while a
## modal is open, so a blocked confirm has to leave its reason here.
var _status := ""
var _status_error := false


func _ready() -> void:
	layer = 38
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_locale = TranslationServer.get_locale()
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_canvas)
	_canvas.draw.connect(_draw_map)
	Interface.presentation_changed.connect(_refresh)


func _refresh() -> void:
	if is_instance_valid(_canvas):
		_canvas.queue_redraw()


func is_open() -> bool:
	return visible


func _process(_delta: float) -> void:
	# The map is input-driven, but a locale switch must repaint it while open.
	if visible and TranslationServer.get_locale() != _locale:
		_locale = TranslationServer.get_locale()
		_canvas.queue_redraw()


func open(level_node: Node, teleport_mode := false) -> void:
	if not is_instance_valid(level_node):
		return
	_level = level_node
	_teleport = teleport_mode
	_snapshot = _level.map_snapshot()
	_source = _level.checkpoint_near_player() if teleport_mode and is_instance_valid(_level) else ""
	_tab = 0
	_index = 0
	_place_scroll = 0
	_status = ""
	_status_error = false
	# Pause belongs to whoever owned it: opening over a paused page must not
	# hand the world an unpause when the map closes.
	_owns_pause = not get_tree().paused
	visible = true
	MathArt.ui_reveal(_canvas)
	Game.player.suppress_actions()
	get_tree().paused = true
	Combat.cancel_hitstop()
	_canvas.queue_redraw()


func close() -> void:
	visible = false
	if _owns_pause:
		get_tree().paused = false
	_owns_pause = false
	if is_instance_valid(Game.player):
		Game.player.suppress_actions()
	_level = null
	_source = ""


func _input(event: InputEvent) -> void:
	if not visible:
		return
	get_viewport().set_input_as_handled()
	var pads: Array = _snapshot.get("pads", [])
	_index = clampi(_index, 0, maxi(0, pads.size() - 1))
	if Interface.pressed(event, &"ui_back") or Interface.pressed(event, &"map"):
		close()
		return
	if Interface.pressed(event, &"ui_nav_left") or Interface.pressed(event, &"ui_nav_right"):
		_tab = 1 - _tab
		_clear_status()
	elif Interface.pressed(event, &"ui_tab_prev"):
		_place_scroll = maxi(0, _place_scroll - _place_rows())
	elif Interface.pressed(event, &"ui_tab_next"):
		_place_scroll = mini(maxi(0, _place_count - _place_rows()), _place_scroll + _place_rows())
	elif _tab == 0 and _teleport and Interface.pressed(event, &"ui_nav_up"):
		_index = wrapi(_index - 1, 0, maxi(1, pads.size()))
		_clear_status()
	elif _tab == 0 and _teleport and Interface.pressed(event, &"ui_nav_down"):
		_index = wrapi(_index + 1, 0, maxi(1, pads.size()))
		_clear_status()
	elif Interface.pressed(event, &"ui_accept"):
		var refusal := _travel_refusal(pads)
		if refusal.is_empty() and is_instance_valid(_level) and _level.teleport_to(str(pads[_index]["id"]), _source):
			close()
			return
		if refusal.is_empty():
			refusal = _level.teleport_refusal(str(pads[_index]["id"]), _source) if is_instance_valid(_level) else "RUN UNAVAILABLE"
		_status = _refusal_text(refusal)
		_status_error = true
		_canvas.queue_redraw()
		return
	else:
		return
	MathArt.ui_select(_canvas)
	_canvas.queue_redraw()


## Exact refusal before the world owner runs the teleport. Keeping this in one
## place means the button never claims success and the map never guesses a cause.
func _travel_refusal(pads: Array) -> String:
	if _tab != 0:
		return "WORLD TAB"
	if _source.is_empty():
		return "AT TELEPORTER"
	if pads.is_empty():
		return "NONE DISCOVERED"
	if not is_instance_valid(_level):
		return "RUN UNAVAILABLE"
	return _level.teleport_refusal(str(pads[_index]["id"]), _source)


func _refusal_text(code: String) -> String:
	match code:
		"WORLD TAB": return ContentText.of("UI_S7_MAP_STATUS_WORLD", "World map is browse only. Open a local map at a checkpoint to travel.")
		"AT TELEPORTER": return ContentText.of("UI_MAP_TRAVEL_AT_TELEPORTER", "Travel is available only while standing at a teleporter.")
		"NONE DISCOVERED": return ContentText.of("UI_MAP_NONE_DISCOVERED", "None discovered")
		"RUN UNAVAILABLE": return ContentText.of("UI_S7_MAP_REFUSE_RUN", "Travel is not available during this run state.")
		"UNKNOWN PAD": return ContentText.of("UI_S7_MAP_REFUSE_UNKNOWN", "That destination is not available in this run.")
		"SAME CHECKPOINT": return ContentText.of("UI_S7_MAP_REFUSE_SAME", "You are already at this checkpoint.")
		"TOO FAR": return ContentText.of("UI_S7_MAP_REFUSE_FAR", "Move to the teleporter to travel.")
		"PHASE RUNE REQUIRED": return ContentText.of("UI_S7_MAP_REFUSE_PHASE", "Phase Rune and its paired landing are required.")
		"TARGET NOT REACHED": return ContentText.of("UI_S7_MAP_REFUSE_PAD", "That checkpoint was not reached.")
		"TARGET NOT A TELEPORTER": return ContentText.of("UI_S7_MAP_REFUSE_TARGET", "That pad is not a checkpoint.")
		"LANDING BLOCKED": return ContentText.of("UI_S7_MAP_REFUSE_LANDING", "The landing point is blocked.")
	return ContentText.of("UI_S7_MAP_REFUSE_UNKNOWN", "That destination is not available in this run.")


func _clear_status() -> void:
	_status = ""
	_status_error = false


func _place_rows() -> int:
	return 6 if _teleport else 2


## Browse uses the full page; travel leaves the six-row sidebar. The inner
## 24px is reserved padding and the scale never exceeds 1:1, so one room is
## centered rather than blown up into a fake landmark.
func _plot_area() -> Rect2:
	return Rect2(52, 112, 472, 242) if _teleport else Rect2(52, 112, 664, 242)


## Shared by the page and its probe: no second copy of the fit arithmetic.
func plot_transform(rooms: Array) -> Dictionary:
	if rooms.is_empty():
		return {"scale": 1.0, "origin": Vector2.ZERO}
	var bounds: Rect2 = rooms[0]["bounds"]
	for room: Dictionary in rooms:
		bounds = bounds.merge(room["bounds"])
	var inner := _plot_area().grow(-24.0)
	var scale := minf(minf(inner.size.x / maxf(1.0, bounds.size.x), inner.size.y / maxf(1.0, bounds.size.y)), 1.0)
	return {"scale": scale, "origin": inner.get_center() - bounds.get_center() * scale}


func _floor_display() -> String:
	# The snapshot caches a translated label. Rederive from canonical data on
	# every paint so a locale change while the map is open cannot stay sticky.
	if _level is Passage:
		return ContentText.of("UI_PASSAGE_MAP_NAME", "Passage").to_upper()
	var biome_id := ""
	if _level is Level:
		biome_id = str((_level as Level).route_node)
	if biome_id.is_empty():
		biome_id = Game.run_node_id
	if biome_id.is_empty():
		return str(_snapshot.get("name", ""))
	var node: Dictionary = Data.route_graph["nodes"].get(biome_id, {})
	var canonical := str(node.get("name", ""))
	if canonical.is_empty():
		return str(_snapshot.get("name", ""))
	return ContentText.name("biome", biome_id, canonical).to_upper()


## Room ids are internal. The sidebar names teleporters by their order instead
## of showing an ID prettified as if it were a place name.
func _teleporter_display(index: int) -> String:
	return ContentText.of("UI_MAP_TELEPORTER_ENTRY", "Teleporter {index}").format({"index": index + 1})


func _place_text(kind: String, label: String, reason: String) -> String:
	if reason.is_empty():
		return label
	# Exit reasons come from Game.exit_reason() as raw machine values. Gate
	# reasons are already display names from level.gd and must stay as-is.
	var shown := ContentText.lock_reason(reason) if kind == "exit" else reason
	return ContentText.of("UI_MAP_PLACE_REASON", "{place} / {reason}").format({"place": label, "reason": shown})


func _draw_map() -> void:
	if not visible: return
	MathArt.px_rect(_canvas, Rect2(0, 0, 768, 480), Color(MathArt.INK, 0.82))
	MathArt.ui_panel(_canvas, MathArt.UI_PAGE)
	MathArt.ui_heading(_canvas,
		ContentText.of("UI_MAP_TITLE_BIOME", "Biome map") if _tab == 0 else ContentText.of("UI_MAP_TITLE_WORLD", "World routes"),
		ContentText.of("UI_S7_MAP_CONTEXT", "{place} / discovered {rooms} rooms · {edges} links").format({"place": _floor_display(), "rooms": int(_snapshot.get("rooms", []).size()), "edges": int(_snapshot.get("edges", []).size())}) if _tab == 0 else ContentText.of("UI_S7_MAP_CONTEXT_WORLD", "{place} / visited {count} biomes · unknown routes hidden").format({"place": _floor_display(), "count": Profile.seen_biomes.size()}))
	var x := 52.0
	x += MathArt.ui_key(_canvas, Vector2(x, 440), _key_labels([&"ui_nav_left", &"ui_nav_right"]), ContentText.of("UI_MAP_KEY_CHANGE", "Change map"))
	if _tab == 0:
		if _teleport:
			x += MathArt.ui_key(_canvas, Vector2(x, 440), _key_labels([&"ui_nav_up", &"ui_nav_down"]), ContentText.of("UI_MAP_KEY_TELEPORTER", "Teleporter"))
			if not _source.is_empty(): MathArt.ui_key(_canvas, Vector2(x, 440), Interface.prompt(&"ui_accept"), ContentText.of("UI_MAP_KEY_TRAVEL", "Travel"))
		MathArt.ui_key(_canvas, Vector2(x, 440), _key_labels([&"ui_tab_prev", &"ui_tab_next"]), ContentText.of("UI_S7_MAP_KEY_PAGES", "Pages"))
	MathArt.ui_key(_canvas, Vector2(596, 440), _key_labels([&"ui_back", &"map"]), ContentText.of("UI_MAP_KEY_BACK", "Back"))
	if _tab == 1:
		_draw_world()
		return
	var rooms: Array = _snapshot.get("rooms", [])
	if rooms.is_empty():
		MathArt.ui_text(_canvas, Vector2(52, 140), ContentText.of("UI_MAP_NO_ROOMS", "No discovered rooms"), 16)
		if not _status.is_empty():
			MathArt.ui_text(_canvas, Vector2(52, 168), _status, 11, MathArt.DANGER if _status_error else MathArt.PALE, 560)
		return
	var transform := plot_transform(rooms)
	var scale: float = transform["scale"]
	var origin: Vector2 = transform["origin"]
	var positions: Dictionary = {}
	for room: Dictionary in rooms: positions[str(room["id"])] = origin + (room["bounds"] as Rect2).get_center() * scale
	for edge: Dictionary in _snapshot.get("edges", []): MathArt.line(_canvas, positions[str(edge["from"])], positions[str(edge["to"])], MathArt.STONE_HI, 1.5)
	for room: Dictionary in rooms:
		var rect: Rect2 = room["bounds"]
		var drawn := Rect2(origin + rect.position * scale + Vector2.ONE, (rect.size * scale - Vector2.ONE * 2).max(Vector2.ONE))
		MathArt.px_rect(_canvas, drawn, MathArt.STONE_DIM if room["cleared"] else MathArt.BG_2)
		MathArt.poly(_canvas, PackedVector2Array([drawn.position, Vector2(drawn.end.x, drawn.position.y), drawn.end, Vector2(drawn.position.x, drawn.end.y)]), Color.TRANSPARENT, MathArt.STONE_HI, 1)
	for pad_index in _snapshot.get("pads", []).size():
		var pad: Dictionary = _snapshot.pads[pad_index]
		if _teleport and pad_index == _index:
			var target := origin + (pad.pos as Vector2) * scale
			MathArt.ring(_canvas, target, 8, MathArt.ACCENT, 2, 4)
			MathArt.line(_canvas, target + Vector2(0, -12), target + Vector2(0, -20), MathArt.ACCENT, 1)
	var places: Array[String] = []
	for marker: Dictionary in _snapshot.get("markers", []):
		var at: Vector2 = origin + (marker["pos"] as Vector2) * scale
		var label := str(marker["label"])
		var reason := str(marker["reason"])
		# Snapshot markers are ephemeral within one build: kind is authoritative
		# and labels arrive already localized from level.map_snapshot().
		var kind := str(marker.get("kind", ""))
		var tone := MathArt.CELL if kind == "teleport" and reason.is_empty() else MathArt.ACCENT if reason.is_empty() else MathArt.LIGHT_DIM
		match kind:
			"teleport":
				MathArt.poly(_canvas, MathArt.ngon(4, 5, 0, at), MathArt.INK, tone, 1.5)
			"exit":
				MathArt.poly(_canvas, MathArt.ngon(3, 5, -PI * 0.5, at), MathArt.INK, tone, 1.5)
				places.append(_place_text(kind, label, reason))
			_:
				MathArt.ring(_canvas, at, 4, tone, 1.5)
				places.append(_place_text(kind, label, reason))
		if not reason.is_empty(): MathArt.line(_canvas, at + Vector2(-4, 4), at + Vector2(4, -4), tone, 1.5)
	MathArt.px_rect(_canvas, Rect2(origin + (_snapshot["player"] as Vector2) * scale - Vector2(3, 3), Vector2(6, 6)), MathArt.PLAYER)
	var pads: Array = _snapshot.get("pads", [])
	var place_lines := MathArt.ui_wrap("\n".join(places) if not places.is_empty() else ContentText.of("UI_MAP_NONE_DISCOVERED", "None discovered"), 664 if not _teleport else 164, 11)
	_place_count = place_lines.size()
	_place_scroll = clampi(_place_scroll, 0, maxi(0, _place_count - _place_rows()))
	if _teleport:
		MathArt.line(_canvas, Vector2(538, 112), Vector2(538, 364), MathArt.STONE, 1)
		MathArt.ui_text(_canvas, Vector2(552, 126), ContentText.of("UI_MAP_TELEPORTERS", "Teleporters"), 13, MathArt.WHITE)
		if pads.is_empty(): MathArt.ui_text(_canvas, Vector2(552, 152), ContentText.of("UI_MAP_NONE_DISCOVERED", "None discovered"), 11)
		var top := maxi(0, _index - 2)
		for i in range(top, mini(top + 3, pads.size())):
			var rect := Rect2(550, 136 + (i - top) * 32, 166, 30)
			if i == _index: MathArt.ui_focus(_canvas, rect)
			var lines := MathArt.ui_wrap(_teleporter_display(i), 140, 11)
			for n in mini(2, lines.size()): MathArt.ui_text(_canvas, rect.position + Vector2(24, 13 + n * MathArt.ui_line_height(11)), lines[n], 11)
		MathArt.ui_text(_canvas, Vector2(552, 251), ContentText.of("UI_MAP_KNOWN_PLACES", "Known places"), 13, MathArt.WHITE)
		if _place_count > 6: MathArt.ui_text(_canvas, Vector2(552, 251), ContentText.of("UI_MAP_PAGE_COUNT", "{page} · {index} / {total}").format({"page": _key_labels([&"ui_tab_prev", &"ui_tab_next"]), "index": _place_scroll + 1, "total": _place_count}), 11, MathArt.LIGHT_DIM, 164, HORIZONTAL_ALIGNMENT_RIGHT)
		for i in range(_place_scroll, mini(_place_scroll + 6, place_lines.size())): MathArt.ui_text(_canvas, Vector2(552, 272 + (i - _place_scroll) * MathArt.ui_line_height(11)), place_lines[i], 11)
		MathArt.ui_text(_canvas, Vector2(52, 388), ContentText.of("UI_MAP_LEGEND", "■ You · ◇ Teleporter · △ Exit · ○ Place · Slash: locked"), 11)
		var travel_note := _status if not _status.is_empty() else (ContentText.of("UI_MAP_CHOOSE_CHECKPOINT", "Choose a reached checkpoint to travel.") if not _source.is_empty() else ContentText.of("UI_MAP_TRAVEL_AT_TELEPORTER", "Travel is available only while standing at a teleporter."))
		MathArt.ui_text(_canvas, Vector2(52, 410), travel_note, 11, MathArt.DANGER if _status_error else MathArt.PALE, 472)
	else:
		# Browse mode belongs to the map: no side list, only availability and the
		# two-line place window under it. A refused confirm leaves its reason in
		# this line, because the HUD cannot speak while the modal is open.
		var browse_note := _status if not _status.is_empty() else (ContentText.of("UI_MAP_TRAVEL_FROM_CHECKPOINT", "Travel from a reached checkpoint.") if not _source.is_empty() else ContentText.of("UI_MAP_TRAVEL_AT_TELEPORTER", "Travel is available only while standing at a teleporter."))
		MathArt.ui_text(_canvas, Vector2(52, 372), browse_note, 11, MathArt.DANGER if _status_error else MathArt.PALE, 560)
		for i in range(_place_scroll, mini(_place_scroll + 2, place_lines.size())):
			MathArt.ui_text(_canvas, Vector2(52, 389 + (i - _place_scroll) * MathArt.ui_line_height(11)), place_lines[i], 11, MathArt.PALE, 664)
		if _place_count > 2:
			MathArt.ui_text(_canvas, Vector2(620, 372), ContentText.of("UI_MAP_PAGE_PLAIN", "{page} {index} / {total}").format({"page": _key_labels([&"ui_tab_prev", &"ui_tab_next"]), "index": _place_scroll + 1, "total": _place_count}), 11, MathArt.LIGHT_DIM, 96, HORIZONTAL_ALIGNMENT_RIGHT)
		MathArt.ui_text(_canvas, Vector2(52, 424), ContentText.of("UI_MAP_LEGEND", "■ You · ◇ Teleporter · △ Exit · ○ Place · Slash: locked"), 11, MathArt.PALE, 664)


func _world_layout() -> Dictionary:
	var groups: Dictionary = {}
	var nodes: Dictionary = Data.route_graph["nodes"]
	for id in Profile.seen_biomes:
		if not nodes.has(id):
			continue
		var stage := int(nodes[id]["stage"])
		if not groups.has(stage):
			groups[stage] = []
		groups[stage].append(id)
	var stages: Array = groups.keys()
	stages.sort()
	var font := MathArt.ui_font()
	var height := font.get_height(11)
	var gap := height * MathArt.INV_PHI
	var step := 608.0 / float(maxi(1, stages.size() - 1))
	var layout: Dictionary = {}
	for i in stages.size():
		var ids: Array = groups[stages[i]]
		for n in ids.size():
			var id := str(ids[n])
			var at := Vector2(80 + float(i) * step, 230 + (float(n) - float(ids.size() - 1) * 0.5) * 32 * MathArt.PHI * MathArt.PHI)
			var display := ContentText.name("biome", id, str(nodes[id]["name"]))
			var lines := PackedStringArray(MathArt.ui_wrap(display, step - gap, 11))
			var width := 0.0
			for text in lines:
				width = maxf(width, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
			var label := Rect2(Vector2(clampf(at.x - width * 0.5, 40, 728 - width), at.y + 16 + gap), Vector2(width, height * lines.size()))
			for previous: Dictionary in layout.values():
				if label.grow(2).intersects(previous.label):
					label.position.y = (previous.label as Rect2).end.y + gap
			layout[id] = {"at": at, "lines": lines, "label": label}
	return layout


func _world_lock_label(a: Vector2, b: Vector2, reason: String) -> Dictionary:
	var font := MathArt.ui_font()
	# `text` stays the raw English payload that tests compare; `display` is the
	# only one painted.
	var text := "LOCKED:\n" + reason.replace(" ", "\n")
	var display := ContentText.of("UI_MAP_LOCKED_LABEL", "LOCKED\n{reason}").format({"reason": ContentText.lock_reason(reason)})
	var size := font.get_multiline_string_size(display, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
	var gap := font.get_height(11) * MathArt.INV_PHI
	return {"text": text, "display": display, "rect": Rect2((a + b) * 0.5 - Vector2(size.x * 0.5, 16 + gap + size.y), size)}


func _draw_world() -> void:
	var font := MathArt.ui_font()
	var nodes: Dictionary = Data.route_graph["nodes"]
	var layout := _world_layout()
	for edge: Dictionary in Data.route_graph["edges"]:
		if layout.has(str(edge["from"])) and layout.has(str(edge["to"])):
			var a: Vector2 = layout[str(edge["from"])]["at"]
			var b: Vector2 = layout[str(edge["to"])]["at"]
			var reason: String = GRAPH.lock_reason(edge, Game.route_state())
			MathArt.line(_canvas, a, b, MathArt.PALE if reason.is_empty() else MathArt.STONE_DIM, 2)
			if not reason.is_empty():
				var note := _world_lock_label(a, b, reason)
				_canvas.draw_multiline_string(font, (note.rect as Rect2).position + Vector2(0, font.get_ascent(11)), note.display, HORIZONTAL_ALIGNMENT_CENTER, (note.rect as Rect2).size.x, 11, -1, MathArt.PALE)
	for id in layout:
		var at: Vector2 = layout[id]["at"]
		MathArt.poly(_canvas, MathArt.ngon(4 if str(nodes[id]["kind"]) == "biome" else 5, 16, -PI * 0.5, at), MathArt.ACCENT if id == Game.run_node_id else MathArt.BG_2, MathArt.ACCENT if id == Game.run_node_id else MathArt.STONE_HI, 2)
		if id == Game.run_node_id:
			MathArt.poly(_canvas, MathArt.ngon(4 if str(nodes[id]["kind"]) == "biome" else 5, 16 * MathArt.INV_PHI, -PI * 0.5, at), MathArt.INK)
		var label: Rect2 = layout[id]["label"]
		var lines: PackedStringArray = layout[id]["lines"]
		for i in lines.size():
			_canvas.draw_string(font, label.position + Vector2(0, font.get_ascent(11) + float(i) * font.get_height(11)), lines[i], HORIZONTAL_ALIGNMENT_CENTER, label.size.x, 11, MathArt.PALE)
	_canvas.draw_string(font, Vector2(40, 390), ContentText.of("UI_MAP_WORLD_FOOTER", "Visited biomes only · Locks use this run’s Runes, keys and BSC."), HORIZONTAL_ALIGNMENT_LEFT, 680, 11, MathArt.PALE)
	if not _status.is_empty():
		_canvas.draw_string(font, Vector2(40, 410), _status, HORIZONTAL_ALIGNMENT_LEFT, 680, 11, MathArt.DANGER if _status_error else MathArt.PALE)


## One prompt per distinct label: keyboard shows "A D", pad shows "D-pad".
func _key_labels(actions: Array) -> String:
	var parts: Array[String] = []
	for action in actions:
		var label := Interface.prompt(StringName(action))
		if label.is_empty() or label == "—":
			continue
		if not parts.has(label):
			parts.append(label)
	return " ".join(parts) if not parts.is_empty() else "—"
