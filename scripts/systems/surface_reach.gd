extends RefCounted
class_name SurfaceReach
## Conservative body/arc checks; real CharacterBody2D probes remain required.
const HALF := Vector2(14, 23)
const MAX_UP := 100.0
const MAX_SPAN := 170.0


static func clear_box(point: Vector2, solids: Array, half: Vector2 = HALF) -> bool:
	var box := Rect2(point - half, half * 2.0)
	for raw: Rect2 in solids:
		if box.intersects(raw):
			return false
	return true


static func supported(point: Vector2, surfaces: Array, half: Vector2 = HALF) -> bool:
	for value: Dictionary in surfaces:
		if _on_surface(point, value, half):
			return true
	return false


static func _on_surface(point: Vector2, surface: Dictionary, half: Vector2 = HALF) -> bool:
	var rect: Rect2 = surface["rect"]
	return point.x >= rect.position.x + half.x and point.x <= rect.end.x - half.x and absf(rect.position.y - point.y - half.y - 1.0) <= 18.0


static func _components(surfaces: Array, solids: Array) -> Array:
	var out: Array = []
	for surface: Dictionary in surfaces:
		var floor_rect: Rect2 = surface["rect"]
		var parts: Array[Rect2] = [floor_rect]
		for obstacle: Rect2 in solids:
			if obstacle.position.y >= floor_rect.position.y or obstacle.end.y <= floor_rect.position.y - 72.0:
				continue
			var next: Array[Rect2] = []
			for part: Rect2 in parts:
				if obstacle.end.x <= part.position.x or obstacle.position.x >= part.end.x:
					next.append(part)
					continue
				if obstacle.position.x - part.position.x >= HALF.x * 2.0:
					next.append(Rect2(part.position, Vector2(obstacle.position.x - part.position.x, part.size.y)))
				if part.end.x - obstacle.end.x >= HALF.x * 2.0:
					next.append(Rect2(Vector2(obstacle.end.x, part.position.y), Vector2(part.end.x - obstacle.end.x, part.size.y)))
			parts = next
		for part: Rect2 in parts:
			var component := surface.duplicate()
			component["rect"] = part
			out.append(component)
	return out


static func _point_reached(point: Vector2, room: String, visited: Dictionary, surfaces: Array, solids: Array) -> bool:
	if not clear_box(point, solids):
		return false
	for index in visited:
		var surface: Dictionary = surfaces[index]
		if str(surface["room"]) != room or not _on_surface(point, surface):
			continue
		var rect: Rect2 = surface["rect"]
		if _segment_clear(Vector2(rect.get_center().x, rect.position.y - 24), point, solids):
			return true
	return false


static func _segment_clear(a: Vector2, b: Vector2, solids: Array) -> bool:
	var steps := maxi(1, int(ceil(a.distance_to(b) / 8.0)))
	for n in range(steps + 1):
		if not clear_box(a.lerp(b, float(n) / float(steps)), solids):
			return false
	return true


static func can_travel(from: Dictionary, to: Dictionary, solids: Array, one_ways: Array) -> bool:
	var a: Rect2 = from["rect"]
	var b: Rect2 = to["rect"]
	var up := a.position.y - b.position.y
	var gap := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	if up > MAX_UP or up < -600.0 or gap > MAX_SPAN or a.size.x < 28 or b.size.x < 28:
		return false
	var x := clampf(b.get_center().x, a.position.x + HALF.x + 1, a.end.x - HALF.x - 1)
	var end_x := clampf(x, b.position.x + HALF.x + 1, b.end.x - HALF.x - 1)
	var start := Vector2(x, a.position.y - 24)
	var end := Vector2(end_x, b.position.y - 24)
	for landing in [start, end]:
		if not clear_box(landing - Vector2(0, 12), solids + one_ways, Vector2(14, 36)):
			return false
	if absf(up) < 0.1 and gap == 0.0:
		return _segment_clear(start, end, solids)
	if _arc_clear(start, end, solids, one_ways, Rect2(), false):
		return true
	return bool(from["oneway"]) and up < 0 and _arc_clear(start, end, solids, one_ways, a, true)


static func _arc_clear(start: Vector2, end: Vector2, solids: Array, one_ways: Array, ignored: Rect2, drop: bool) -> bool:
	var delta_y := end.y - start.y
	var apex_t := 630.0 / 1800.0
	var apex := 630.0 * apex_t - 0.5 * 1800.0 * apex_t * apex_t
	var duration := apex_t + sqrt(maxf(0.0, 2.0 * (apex + delta_y) / 2500.0))
	if drop:
		duration = (-120.0 + sqrt(14400.0 + 5000.0 * delta_y)) / 2500.0
	if duration <= 0.0 or absf(end.x - start.x) / duration > 300.0:
		return false
	var steps := maxi(1, int(ceil(duration * 120.0)))
	var previous := start
	for n in range(1, steps + 1):
		var t := minf(duration, float(n) / 120.0)
		var dy := -630.0 * t + 900.0 * t * t if t <= apex_t else -apex + 1250.0 * (t - apex_t) * (t - apex_t)
		if drop:
			dy = 120.0 * t + 1250.0 * t * t
		var point := Vector2(lerpf(start.x, end.x, t / duration), start.y + dy)
		if not clear_box(point, solids):
			return false
		if point.y > previous.y:
			for rect: Rect2 in one_ways:
				if rect == ignored:
					continue
				if previous.y + HALF.y <= rect.position.y and point.y + HALF.y >= rect.position.y and point.x + HALF.x > rect.position.x and point.x - HALF.x < rect.end.x:
					return false
		previous = point
	return true


static func verify(data: Dictionary, runes: Array, enemy_catalog: Dictionary) -> Dictionary:
	var keys: Array = []
	var reached_rooms: Array = []
	var bad_spawns: Array = []
	var missing: Array = []
	var iterations := 0
	var solids: Array = []
	var surfaces: Array = []
	var visited: Dictionary = {}
	var pickups: Array = data.get("keys", [data["key"]] if not data.get("key", {}).is_empty() else [])
	while iterations <= pickups.size():
		iterations += 1
		solids = data["solids"].duplicate()
		surfaces = data["surfaces"].duplicate()
		for gate: Dictionary in data["gates"]:
			var open := (str(gate["kind"]) == "break" and runes.has(str(gate["rune"]))) or (str(gate["kind"]) == "key" and keys.has(str(gate["key"])))
			if not open:
				solids.append(gate["rect"])
				if str(gate["kind"]) == "break":
					surfaces.append({"rect": gate["rect"], "oneway": false, "room": str(gate["room"])})
		surfaces = _components(surfaces, solids)
		visited.clear()
		reached_rooms.clear()
		var queue: Array[int] = []
		for i in surfaces.size():
			if _on_surface(data["start"], surfaces[i]) and clear_box(data["start"], solids):
				queue.append(i)
		while not queue.is_empty():
			var current: int = queue.pop_front()
			if visited.has(current):
				continue
			visited[current] = true
			var room_id := str(surfaces[current]["room"])
			if not reached_rooms.has(room_id):
				reached_rooms.append(room_id)
			for edge: Dictionary in data["graph"]:
				if str(edge["from"]) != room_id or str(edge["mode"]) not in ["vine", "wall", "phase"] or not runes.has(str(edge["rune"])):
					continue
				if not _point_reached(edge["source"], room_id, visited, surfaces, solids) or not clear_box(edge["target"], solids):
					continue
				if str(edge["mode"]) != "phase" and not _segment_clear(edge["source"], edge["target"], solids):
					continue
				for j in surfaces.size():
					if str(surfaces[j]["room"]) == str(edge["to"]) and _on_surface(edge["target"], surfaces[j]):
						queue.append(j)
			for j in surfaces.size():
				if not visited.has(j) and can_travel(surfaces[current], surfaces[j], solids, data["oneways"]):
					queue.append(j)
		var gained := false
		for key: Dictionary in pickups:
			if not keys.has(str(key["id"])) and _point_reached(key["pos"], str(key["room"]), visited, surfaces, solids):
				keys.append(str(key["id"]))
				gained = true
		if not gained:
			break
	var required_rooms: Array = []
	for room: Dictionary in data["rooms"]:
		var required := true
		for rune in room["requires_runes"]:
			if not runes.has(str(rune)):
				required = false
		if required:
			required_rooms.append(str(room["id"]))
			if not reached_rooms.has(str(room["id"])):
				missing.append(str(room["id"]))
		var count := 0
		var half := Vector2.ZERO
		for encounter: Array in room["enemies"]:
			var cfg: Dictionary = enemy_catalog.get(str(encounter[0]), {})
			count += int(encounter[1])
			if cfg.is_empty():
				bad_spawns.append("unknown enemy: " + str(encounter[0]))
			half = Vector2(maxf(half.x, float(cfg.get("body_radius", 12))), maxf(half.y, float(cfg.get("body_height", 42)) * 0.5))
		if count > room["spawns"].size():
			bad_spawns.append("missing spawn slots: " + str(room["id"]))
		if count > 0:
			for point: Vector2 in room["spawns"]:
				if not clear_box(point, solids + data["oneways"], half) or not supported(point, surfaces, half):
					bad_spawns.append(point)
	for key: Dictionary in pickups:
		if required_rooms.has(str(key["room"])) and not keys.has(str(key["id"])):
			missing.append("unreachable key: " + str(key["id"]))
	for marker: Dictionary in data["exits"] + data["pads"]:
		if required_rooms.has(str(marker["room"])) and not _point_reached(marker["pos"], str(marker["room"]), visited, surfaces, solids):
			missing.append("unreachable marker: " + str(marker.get("id", marker.get("to", ""))))
	return {"ok": missing.is_empty() and bad_spawns.is_empty() and data["socket_errors"].is_empty(), "rooms": reached_rooms, "missing": missing, "bad_spawns": bad_spawns, "keys": keys, "socket_errors": data["socket_errors"]}
