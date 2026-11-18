extends RefCounted
class_name BiomeGen
## Authored modules assembled by a biome concept graph, with explicit sockets.
const LEGACY_REVISION := "legacy_v1"
const LATEST_REVISION := "spatial_v2"
const ALGORITHM_REVISION := "authored_spatial_v2"
static var _spatial_data: Dictionary = {}


static func spatial_data() -> Dictionary:
	if _spatial_data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/generation_spatial_v2.json"))
		if parsed is Dictionary:
			_spatial_data = parsed
	return _spatial_data


static func generate(id: String, seed_value: int, biomes: Dictionary, modules: Dictionary, routes: Dictionary, revision: String = LATEST_REVISION, spatial: Dictionary = {}) -> Dictionary:
	return generate_checked(id, seed_value, biomes, modules, routes, revision, spatial)["layout"]


static func generate_checked(id: String, seed_value: int, biomes: Dictionary, modules: Dictionary, routes: Dictionary, revision: String = LATEST_REVISION, spatial: Dictionary = {}) -> Dictionary:
	var result := {"layout": {}, "errors": PackedStringArray(), "revision": revision, "variant": "", "attempts": 0}
	if revision not in [LEGACY_REVISION, LATEST_REVISION]:
		result.errors.append("unsupported generator revision: " + revision)
		return result
	var errors := validate(biomes, modules)
	if not errors.is_empty():
		result.errors = errors
		return result
	var prepared_biomes := biomes
	var prepared_modules := modules
	if revision == LATEST_REVISION:
		var table := spatial_data() if spatial.is_empty() else spatial
		errors = validate_spatial(table, biomes, modules, id, false)
		if not errors.is_empty():
			result.errors = errors
			return result
		if table.profiles.has(id):
			var variants: Array = table.profiles[id].variants
			var variant: Dictionary = variants[posmod(seed_value, variants.size())]
			var prepared := _prepare_spatial(id, variant, table, biomes, modules)
			prepared_biomes = prepared.biomes
			prepared_modules = prepared.modules
			result.variant = variant.id
		else:
			result.variant = "controlled_arena"
	result.attempts = 1
	var layout := _generate_legacy(id, seed_value, prepared_biomes, prepared_modules, routes)
	if layout.is_empty():
		result.errors.append("socket or gate assembly failed: %s/%s" % [id, result.variant])
		return result
	if revision == LATEST_REVISION:
		errors = _footprint_errors(layout, prepared_biomes.biomes[id])
		if not errors.is_empty():
			result.errors = errors
			return result
		for room: Dictionary in layout.rooms:
			room["rect"] = Rect2((room.rect as Rect2).position, Vector2((room.bounds as Rect2).size.x, 32))
		layout["generator_revision"] = revision
		layout["spatial_variant"] = result.variant
	result.layout = layout
	return result


static func _prepare_spatial(id: String, variant: Dictionary, table: Dictionary, biomes: Dictionary, modules: Dictionary) -> Dictionary:
	var prepared_biomes := biomes.duplicate()
	prepared_biomes.biomes = biomes.biomes.duplicate()
	prepared_biomes.biomes[id] = biomes.biomes[id].duplicate(true)
	var prepared_modules := modules.duplicate()
	prepared_modules.modules = modules.modules.duplicate()
	# Fix every original pool before adding versioned modules, preserving candidate order.
	for node: Dictionary in prepared_biomes.biomes[id].nodes:
		node["templates"] = _candidates(biomes.biomes[id], node, modules)
		var override: Dictionary = variant.nodes.get(node.id, {})
		for field in override:
			node[field] = override[field].duplicate(true)
	for name in table.modules:
		prepared_modules.modules[name] = table.modules[name]
	return {"biomes": prepared_biomes, "modules": prepared_modules}


static func validate_spatial(table: Dictionary, biomes: Dictionary, modules: Dictionary, only_id := "", check_modules := true) -> PackedStringArray:
	var errors := validate(biomes, modules) if check_modules else PackedStringArray()
	if not errors.is_empty():
		return errors
	if table.get("schema_version") != 1 or table.get("algorithm_revision") != ALGORITHM_REVISION or not table.get("modules") is Dictionary or not table.get("profiles") is Dictionary:
		return PackedStringArray(["versioned spatial schema/algorithm/modules/profiles required"])
	if check_modules:
		errors.append_array(_module_errors({"modules": table.modules}))
		if not errors.is_empty(): return errors
		var combined := modules.duplicate()
		combined.modules = modules.modules.merged(table.modules, true)
		errors.append_array(_biome_errors(biomes.biomes, combined))
		if not errors.is_empty(): return errors
	if str(only_id).is_empty():
		for id in biomes.biomes:
			if not biomes.biomes[id].has("boss") and not table.profiles.has(id):
				errors.append("missing ordinary spatial profile: " + str(id))
	for id in table.profiles:
		if not biomes.biomes.has(id) or biomes.biomes[id].has("boss"):
			errors.append("spatial profile must be an ordinary biome: " + str(id))
			continue
		if not str(only_id).is_empty() and id != only_id:
			continue
		var profile: Variant = table.profiles[id]
		if not profile is Dictionary or not profile.get("rhythm") is String or not profile.get("variants") is Array or profile.variants.size() < 2 or profile.variants.size() > 4:
			errors.append("two to four authored variants and rhythm required: " + str(id))
			continue
		var nodes := {}
		for node: Dictionary in biomes.biomes[id].nodes: nodes[node.id] = true
		var seen := {}
		for variant: Variant in profile.variants:
			if not variant is Dictionary or not _strings([variant.get("id")]) or not variant.get("nodes") is Dictionary:
				errors.append("invalid spatial variant: " + str(id))
				continue
			if seen.has(variant.id): errors.append("duplicate spatial variant: " + str(id))
			seen[variant.id] = true
			var valid := true
			for room in variant.nodes:
				var override: Variant = variant.nodes[room]
				if not nodes.has(room) or not override is Dictionary:
					errors.append("unknown spatial room/override: " + str(room))
					valid = false
					continue
				for field in override:
					if field not in ["grid", "templates"] or (field == "grid" and not _numbers(override[field], 2)) or (field == "templates" and not _strings(override[field])):
						errors.append("invalid spatial override: %s/%s" % [room, field])
						valid = false
				if override.has("templates") and override.templates.is_empty():
					errors.append("empty spatial module pool: " + str(room))
					valid = false
			if valid and check_modules:
				var prepared := _prepare_spatial(str(id), variant, table, biomes, modules)
				errors.append_array(_biome_errors({id: prepared.biomes.biomes[id]}, prepared.modules))
	if not str(only_id).is_empty() and not table.profiles.has(only_id) and not biomes.biomes.get(only_id, {}).has("boss"):
		errors.append("missing ordinary spatial profile: " + str(only_id))
	return errors


static func _footprint_errors(layout: Dictionary, cfg: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var rooms: Array = layout.rooms
	for i in rooms.size():
		var room: Dictionary = rooms[i]
		var bounds: Rect2 = room.bounds
		for j in range(i):
			if bounds.intersects(rooms[j].bounds):
				errors.append("room footprint overlap: %s/%s" % [rooms[j].id, room.id])
		# The existing floor slab occupies the 32px shared support below a footprint.
		var collision_bounds := Rect2(bounds.position, bounds.size + Vector2(0, 32))
		for rect: Rect2 in room.ground + room.platforms:
			if not collision_bounds.encloses(rect):
				errors.append("collision outside footprint: " + str(room.id))
		for socket: Dictionary in room.sockets.values():
			var normal: Vector2 = socket.normal
			if normal not in [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				errors.append("invalid socket direction: " + str(room.id))
	for gate: Dictionary in layout.gates:
		# The unchanged authored local lock deliberately spans both Ramparts lanes.
		if str(gate.id) == str(cfg.get("local_gate", {}).get("id", "")):
			continue
		var room: Dictionary = rooms[int(layout.room_ids[gate.room])]
		var bounds: Rect2 = room.bounds
		if not Rect2(bounds.position, bounds.size + Vector2(0, 32)).encloses(gate.rect):
			errors.append("module gate outside footprint: " + str(gate.id))
	for edge: Dictionary in layout.graph:
		var source: Dictionary = rooms[int(layout.room_ids[edge.from])].sockets[edge.from_socket]
		var target: Dictionary = rooms[int(layout.room_ids[edge.to])].sockets[edge.to_socket]
		var normal: Vector2 = source.normal
		var target_normal: Vector2 = target.normal
		var mode := str(edge.mode)
		if (mode == "phase" and (normal != Vector2.ZERO or target_normal != Vector2.ZERO)) or (mode == "walk" and normal == Vector2.ZERO) or (mode in ["vine", "wall"] and (normal != Vector2.UP or target_normal != Vector2.DOWN)) or (mode == "break" and (normal != Vector2.DOWN or target_normal != Vector2.UP)):
			errors.append("socket direction incompatible with traversal mode: " + str(edge))
	return errors


static func validate(biomes: Dictionary, modules: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if biomes.get("schema_version") != 1 or modules.get("schema_version") != 1 or not biomes.get("biomes") is Dictionary or not modules.get("modules") is Dictionary or not _numbers(biomes.get("grid"), 2):
		return PackedStringArray(["version 1, grid, biomes/modules objects required"])
	if float(biomes["grid"][0]) <= 0 or float(biomes["grid"][1]) <= 0:
		return PackedStringArray(["positive room grid required"])
	errors = _module_errors(modules)
	if not errors.is_empty(): return errors
	return _biome_errors(biomes["biomes"], modules)


static func _module_errors(modules: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for id in modules["modules"]:
		var module: Variant = modules["modules"][id]
		if not module is Dictionary:
			errors.append("module must be object: " + str(id))
			continue
		if not _numbers(module.get("size"), 2) or not module.get("sockets") is Dictionary or not _strings(module.get("roles")) or not _strings(module.get("biome_tags")):
			errors.append("module size/sockets/roles/tags required: " + str(id))
			continue
		if float(module["size"][0]) <= 0 or float(module["size"][1]) <= 0:
			errors.append("positive module size required: " + str(id))
		for field in ["solids", "oneways", "spawns", "loot"]:
			if not module.get(field) is Array:
				errors.append("module array required: %s/%s" % [id, field])
				continue
			for raw in module[field]:
				if not _numbers(raw, 4 if field in ["solids", "oneways"] else 2):
					errors.append("invalid module geometry: " + str(id))
				elif field in ["solids", "oneways"] and (float(raw[2]) <= 0 or float(raw[3]) <= 0):
					errors.append("positive collision rectangle required: " + str(id))
		for socket in module["sockets"].values():
			if not socket is Dictionary:
				errors.append("socket must be object: " + str(id))
				continue
			for field in ["point", "normal", "stand"]:
				if not _numbers(socket.get(field), 2):
					errors.append("invalid socket: " + str(id))
		if not module.get("gates", []) is Array:
			errors.append("gates must be array: " + str(id))
		else:
			for gate in module.get("gates", []):
				if not _valid_gate(gate):
					errors.append("invalid physical gate: " + str(id))
	return errors


static func _biome_errors(biomes: Dictionary, modules: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for id in biomes:
		var cfg: Variant = biomes[id]
		if not cfg is Dictionary or not cfg.get("tag") is String or not _numbers([cfg.get("palette")], 1) or not cfg.get("nodes") is Array or not cfg.get("edges") is Array or not cfg.get("exits") is Dictionary or not _strings(cfg.get("enemy_pool")) or not _strings(cfg.get("checkpoints")) or not cfg.get("rune") is String or not cfg.get("rune_room") is String or typeof(cfg.get("slice_end", false)) != TYPE_BOOL:
			errors.append("invalid biome fields: " + str(id))
			continue
		var nodes: Dictionary = {}
		var valid := true
		for node in cfg["nodes"]:
			if not node is Dictionary or not node.get("id") is String or not node.get("role") is String or not _numbers(node.get("grid"), 2) or not _strings(node.get("requires_runes", [])) or not _numbers([node.get("budget", 0)], 1) or not _numbers([node.get("cache", 0)], 1) or typeof(node.get("boss", false)) != TYPE_BOOL:
				errors.append("invalid room: " + str(id))
				valid = false
				continue
			var key: String = node["id"]
			if key.is_empty() or nodes.has(key) or float(node.get("budget", 0)) < 0 or float(node.get("cache", 0)) < 0:
				errors.append("invalid room id/budget: " + str(id))
				valid = false
			nodes[key] = node
			if bool(node.get("boss", false)) and (not cfg.get("boss") is String or str(cfg["boss"]).is_empty()):
				errors.append("boss room requires boss: " + str(id))
			if int(node.get("budget", 0)) > 0 and cfg["enemy_pool"].is_empty():
				errors.append("enemy budget requires pool: " + str(id))
		for edge in cfg["edges"]:
			if not edge is Dictionary or not _strings([edge.get("from"), edge.get("to"), edge.get("from_socket"), edge.get("to_socket"), edge.get("mode")]):
				errors.append("invalid edge fields: " + str(id))
				valid = false
				continue
			if str(edge["mode"]) not in ["walk", "vine", "wall", "phase", "break"] or (str(edge["mode"]) != "walk" and (not edge.get("rune") is String or str(edge["rune"]).is_empty())) or not nodes.has(edge["from"]) or not nodes.has(edge["to"]):
				errors.append("invalid graph endpoint/mode/Rune: " + str(id))
				valid = false
		if cfg.has("boss") and (not cfg["boss"] is String or str(cfg["boss"]).is_empty() or not nodes.has("arena") or not bool(nodes["arena"].get("boss", false))):
			errors.append("boss requires arena node: " + str(id))
		if not nodes.has("entry") or not nodes.has(cfg["exits"].get("primary_room", "")) or not nodes.has(cfg["exits"].get("secondary_room", "")):
			errors.append("entry/exit room missing: " + str(id))
		for checkpoint in cfg["checkpoints"]:
			if not nodes.has(checkpoint):
				errors.append("checkpoint room missing: " + str(id))
		if not str(cfg["rune"]).is_empty() and not nodes.has(cfg["rune_room"]):
			errors.append("Rune room missing: " + str(id))
		if (cfg.has("keys") and not cfg["keys"] is Array) or (cfg.has("keys") and cfg.has("key")):
			errors.append("keys array or legacy key required, not both: " + str(id))
		else:
			var key_ids: Array[String] = []
			for key: Variant in cfg.get("keys", [cfg["key"]] if cfg.has("key") else []):
				if not key is Dictionary or not _strings([key.get("id"), key.get("room")]) or not nodes.has(key["room"]) or not _numbers(key.get("at"), 2) or key_ids.has(str(key["id"])):
					errors.append("invalid or duplicate key: " + str(id))
				else:
					key_ids.append(str(key["id"]))
		if cfg.has("local_gate"):
			var gate: Variant = cfg["local_gate"]
			if not _valid_gate(gate) or not nodes.has(gate.get("room", "")):
				errors.append("invalid local gate: " + str(id))
		if valid:
			for node: Dictionary in cfg["nodes"]:
				if _candidates(cfg, node, modules).is_empty():
					errors.append("no compatible module: %s/%s" % [id, node["id"]])
	return errors


static func _numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for component in value:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
			return false
	return true


static func _strings(value: Variant) -> bool:
	if not value is Array:
		return false
	for component in value:
		if not component is String or component.is_empty():
			return false
	return true


static func _valid_gate(value: Variant) -> bool:
	if not value is Dictionary or not _strings([value.get("id"), value.get("kind")]) or not _numbers(value.get("rect"), 4):
		return false
	var kind: String = value["kind"]
	return kind in ["key", "break"] and _strings([value.get("key" if kind == "key" else "rune")]) and float(value["rect"][2]) > 0 and float(value["rect"][3]) > 0


static func _candidates(cfg: Dictionary, node: Dictionary, table: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in table["modules"]:
		if node.has("templates") and not node["templates"].has(str(id)):
			continue
		var module: Dictionary = table["modules"][id]
		if not (module.get("roles", []) as Array).has(str(node["role"])) or not (module.get("biome_tags", []) as Array).has(str(cfg["tag"])):
			continue
		if module["spawns"].size() < (1 if bool(node.get("boss", false)) else int(node.get("budget", 0))) or (int(node.get("cache", 0)) > 0 and module["loot"].is_empty()):
			continue
		var compatible := true
		for edge: Dictionary in cfg.get("edges", []):
			var socket := ""
			if str(edge["from"]) == str(node["id"]):
				socket = str(edge["from_socket"])
			elif str(edge["to"]) == str(node["id"]):
				socket = str(edge["to_socket"])
			if not socket.is_empty() and not module.get("sockets", {}).has(socket):
				compatible = false
		if compatible:
			out.append(str(id))
	return out


static func _generate_legacy(id: String, seed_value: int, biomes: Dictionary, modules: Dictionary, routes: Dictionary) -> Dictionary:
	if not validate(biomes, modules).is_empty() or not routes.get("nodes") is Dictionary or not routes["nodes"].has(id) or not routes.get("edges") is Array:
		return {}
	var cfg: Dictionary = biomes["biomes"].get(id, {})
	if cfg.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + id.hash()
	var rooms: Array = []
	var by_id: Dictionary = {}
	var solids: Array[Rect2] = []
	var platforms: Array[Rect2] = []
	var surfaces: Array[Dictionary] = []
	var gates: Array[Dictionary] = []
	var caches: Array[Dictionary] = []
	var pads: Array[Dictionary] = []
	var world_bounds := Rect2(0, -126, 640, 276)
	var grid := Vector2(float(biomes["grid"][0]), float(biomes["grid"][1]))
	for spec: Dictionary in cfg["nodes"]:
		var candidates := _candidates(cfg, spec, modules)
		if candidates.is_empty():
			return {}
		var module_id := candidates[rng.randi_range(0, candidates.size() - 1)]
		var module: Dictionary = modules["modules"][module_id]
		var origin := Vector2(float(spec["grid"][0]) * grid.x, 150.0 + float(spec["grid"][1]) * grid.y)
		var bounds := Rect2(origin + Vector2(0, -float(module["size"][1])), Vector2(float(module["size"][0]), float(module["size"][1])))
		world_bounds = world_bounds.merge(bounds)
		var room := {"id": str(spec["id"]), "kind": "hall", "role": str(spec["role"]), "template": module_id,
			"rect": Rect2(origin, Vector2(grid.x, 32)), "bounds": bounds, "ground": [], "platforms": [], "oneway": [],
			"enemies": [], "spawns": [], "sockets": {}, "requires_runes": spec.get("requires_runes", []).duplicate()}
		for field in ["solids", "oneways"]:
			for raw: Array in module[field]:
				var rect := _rect(raw, origin)
				var one_way: bool = field == "oneways"
				if one_way:
					room["platforms"].append(rect)
					room["oneway"].append(true)
					platforms.append(rect)
				else:
					room["ground"].append(rect)
					solids.append(rect)
				if rect.size.y <= 32.0:
					surfaces.append({"rect": rect, "oneway": one_way, "room": str(spec["id"])})
		for name in module["sockets"]:
			var socket: Dictionary = module["sockets"][name]
			room["sockets"][name] = {"point": origin + _point(socket["point"]), "normal": _point(socket["normal"]), "stand": origin + _point(socket["stand"])}
		for raw: Array in module["spawns"]:
			room["spawns"].append(origin + _point(raw))
		if bool(spec.get("boss", false)):
			room["enemies"] = [[str(cfg["boss"]), 1]]
		else:
			for n in int(spec.get("budget", 0)):
				var pool: Array = cfg["enemy_pool"]
				room["enemies"].append([str(pool[rng.randi_range(0, pool.size() - 1)]), 1])
		for raw_gate: Dictionary in module.get("gates", []):
			var gate := raw_gate.duplicate(true)
			gate["rect"] = _rect(raw_gate["rect"], origin)
			gate["room"] = str(spec["id"])
			gates.append(gate)
		if int(spec.get("cache", 0)) > 0:
			caches.append({"pos": origin + _point(module["loot"][0]), "value": int(spec["cache"]), "room": str(spec["id"])})
		if (cfg["checkpoints"] as Array).has(str(spec["id"])):
			pads.append({"id": str(spec["id"]), "room": str(spec["id"]), "kind": "checkpoint", "pos": origin + Vector2(96, -24)})
		by_id[str(spec["id"])] = rooms.size()
		rooms.append(room)
	var edges: Array[Dictionary] = []
	var vines: Array[Dictionary] = []
	var socket_errors := PackedStringArray()
	for spec: Dictionary in cfg["edges"]:
		var a: Dictionary = rooms[int(by_id[str(spec["from"])])]
		var b: Dictionary = rooms[int(by_id[str(spec["to"])])]
		if not a["sockets"].has(str(spec["from_socket"])) or not b["sockets"].has(str(spec["to_socket"])):
			socket_errors.append("missing socket: " + str(spec))
			continue
		var source: Dictionary = a["sockets"][str(spec["from_socket"])]
		var target: Dictionary = b["sockets"][str(spec["to_socket"])]
		var mode := str(spec["mode"])
		if mode != "phase" and ((source["point"] as Vector2).distance_to(target["point"]) > 0.1 or (source["normal"] as Vector2) != -(target["normal"] as Vector2)):
			socket_errors.append("incompatible socket landing: " + str(spec))
		var edge := spec.duplicate(true)
		edge["source"] = source["stand"]
		edge["target"] = target["stand"]
		edges.append(edge)
		if mode == "vine":
			vines.append({"rect": Rect2(Vector2((source["stand"] as Vector2).x - 18, (target["stand"] as Vector2).y - 24), Vector2(36, (source["stand"] as Vector2).y - (target["stand"] as Vector2).y + 48)), "room": str(spec["from"])})
		elif mode == "phase":
			var pair := "phase_%d" % edges.size()
			pads.append({"id": pair + "_source", "room": str(spec["from"]), "kind": "phase", "pos": source["stand"], "pair": pair + "_target"})
			pads.append({"id": pair + "_target", "room": str(spec["to"]), "kind": "phase", "pos": target["stand"], "pair": pair + "_source"})
	if not socket_errors.is_empty():
		return {}
	if cfg.has("local_gate"):
		var gate: Dictionary = cfg["local_gate"].duplicate(true)
		gate["rect"] = _rect(gate["rect"], (rooms[int(by_id[str(gate["room"])])]["rect"] as Rect2).position)
		gates.append(gate)
	var gate_ids: Dictionary = {}
	for gate: Dictionary in gates:
		if gate_ids.has(str(gate["id"])):
			return {}
		gate_ids[str(gate["id"])] = true
	var keys: Array[Dictionary] = []
	for raw_key: Dictionary in cfg.get("keys", [cfg["key"]] if cfg.has("key") else []):
		var key := raw_key.duplicate(true)
		key["pos"] = (rooms[int(by_id[str(key["room"])])]["rect"] as Rect2).position + _point(key["at"])
		keys.append(key)
	var exits: Array[Dictionary] = []
	var outgoing: Array[Dictionary] = []
	for edge: Dictionary in routes["edges"]:
		if str(edge["from"]) == id:
			outgoing.append(edge)
	if bool(cfg.get("slice_end", false)):
		outgoing.clear()
	if outgoing.is_empty():
		outgoing.append({"from": id, "to": ""})
	for n in outgoing.size():
		var room_id := str(cfg["exits"]["primary_room"] if n == 0 else cfg["exits"]["secondary_room"])
		var rect: Rect2 = rooms[int(by_id[room_id])]["rect"]
		var exit := outgoing[n].duplicate(true)
		exit["pos"] = rect.position + Vector2(480.0 if n == 0 else 96.0 + float(n - 1) * 184.0, -24)
		exit["room"] = room_id
		exits.append(exit)
	var boss_at: Variant = null
	if cfg.has("boss"):
		boss_at = (rooms[int(by_id["arena"])]["spawns"] as Array)[0]
	return {"biome": id, "seed": seed_value, "name": str(routes["nodes"][id]["name"]).to_upper(), "palette": cfg["palette"],
		"rooms": rooms, "room_ids": by_id, "width": world_bounds.end.x, "bounds": world_bounds,
		"start": (rooms[int(by_id["entry"])]["rect"] as Rect2).position + Vector2(96, -24), "exit": exits[0]["pos"] + Vector2(0, 24),
		"exits": exits, "graph": edges, "solids": solids, "oneways": platforms, "surfaces": surfaces,
		"gates": gates, "pads": pads, "vines": vines, "keys": keys, "key": keys[0] if not keys.is_empty() else {}, "caches": caches, "boss": str(cfg.get("boss", "")), "boss_at": boss_at,
		"rune": str(cfg["rune"]), "rune_room": int(by_id.get(str(cfg["rune_room"]), -1)), "socket_errors": socket_errors}


static func _point(raw: Array) -> Vector2:
	return Vector2(float(raw[0]), float(raw[1]))


static func _rect(raw: Array, origin: Vector2) -> Rect2:
	return Rect2(origin + Vector2(float(raw[0]), float(raw[1])), Vector2(float(raw[2]), float(raw[3])))
