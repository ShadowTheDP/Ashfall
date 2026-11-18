extends SceneTree
const Generator := preload("res://scripts/world/biome_gen.gd")
const Reach := preload("res://scripts/systems/surface_reach.gd")
var _checks := 0
var _fails := 0


func _initialize() -> void:
	var biomes: Dictionary = _read("biomes")
	var modules: Dictionary = _read("room_modules")
	var routes: Dictionary = _read("route_graph")
	var enemies: Dictionary = _read("enemies")
	_check(Generator.validate(biomes, modules).is_empty(), "module/graph schema")
	var broken := modules.duplicate(true)
	broken["modules"]["split"]["sockets"]["east_high"]["point"][1] = -200
	var mismatch := Generator.generate("ash_gate", 1, biomes, broken, routes)
	_check(mismatch.is_empty(), "reject mismatched socket before building bodies")
	broken = modules.duplicate(true)
	broken["modules"]["split"]["sockets"].erase("east_high")
	_check(not Generator.validate(biomes, broken).is_empty(), "reject required socket missing from candidate")
	broken = modules.duplicate(true)
	broken["modules"]["entry"].erase("spawns")
	_check(not Generator.validate(biomes, broken).is_empty(), "reject absent spawn array")
	var malformed := biomes.duplicate(true)
	malformed.erase("grid")
	_check(not Generator.validate(malformed, modules).is_empty(), "reject absent root grid")
	_check(Generator.generate("ash_gate", 1, malformed, modules, routes).is_empty(), "invalid schema fails generation closed")
	broken = modules.duplicate(true)
	broken["modules"]["split"]["gates"].append(broken["modules"]["split"]["gates"][0].duplicate(true))
	_check(Generator.generate("ash_gate", 1, biomes, broken, routes).is_empty(), "duplicate physical gate IDs cannot alias runtime state")
	for field in ["size", "solids", "oneways", "spawns", "loot", "sockets", "roles", "biome_tags"]:
		broken = modules.duplicate(true)
		broken["modules"]["entry"].erase(field)
		_check(not Generator.validate(biomes, broken).is_empty(), "missing field rejected: " + field)
		_check(Generator.generate("ash_gate", 1, biomes, broken, routes).is_empty(), "missing field cannot build: " + field)
	for field in ["nodes", "edges"]:
		malformed = biomes.duplicate(true)
		malformed["biomes"]["ash_gate"][field] = [null]
		_check(not Generator.validate(malformed, modules).is_empty(), "wrong nested type rejected: " + field)
	malformed = biomes.duplicate(true)
	malformed["biomes"]["ash_gate"]["nodes"].reverse()
	var reordered := Generator.generate("ash_gate", 1, malformed, modules, routes)
	_check(reordered["start"] == Vector2(96, 126), "entry spawn is independent of node array order")
	for role in ["shop", "elite", "reward"]:
		var concept := biomes.duplicate(true)
		concept["biomes"]["ash_gate"]["nodes"][2]["role"] = role
		concept["biomes"]["ash_gate"]["nodes"][2]["budget"] = 0 if role == "shop" else 2
		_check(not Generator.generate("ash_gate", 1, concept, modules, routes).is_empty(), "concept graph supports " + role + " room")
	var blocked := [Rect2(40, -130, 30, 130)]
	_check(not Reach.can_travel({"rect": Rect2(0, 0, 40, 32), "oneway": false}, {"rect": Rect2(70, 0, 40, 32), "oneway": false}, blocked, []), "solid wall blocks nominally short jump")
	_check(not Reach.can_travel({"rect": Rect2(0, 0, 80, 32), "oneway": false}, {"rect": Rect2(80, 0, 80, 32), "oneway": false}, [Rect2(0, -66, 180, 8)], []), "72px headroom rejects low ceiling")
	var trap := Generator.generate("stone_ramparts", 1, biomes, modules, routes)
	trap["keys"][0]["room"] = "exit_main"
	_check(not Reach.verify(trap, [], enemies)["ok"], "key behind its door cannot prove a valid route")
	trap = Generator.generate("silt_cistern", 1, biomes, modules, routes)
	for edge: Dictionary in trap["graph"]:
		if str(edge["mode"]) == "phase":
			edge["target"] = Vector2(10000, -10000)
	_check(not Reach.verify(trap, ["phase_rune"], enemies)["ok"], "phase cannot prove reachability without a supported landing")
	trap = Generator.generate("silt_cistern", 1, biomes, modules, routes)
	for edge: Dictionary in trap["graph"]:
		if str(edge["mode"]) == "phase":
			edge["source"] = Vector2(10000, -10000)
	_check(not Reach.verify(trap, ["phase_rune"], enemies)["ok"], "unreachable phase source cannot prove traversal")
	trap = Generator.generate("silt_cistern", 1, biomes, modules, routes)
	trap["surfaces"].append({"rect": Rect2(9960, -9976, 80, 32), "oneway": false, "room": "phase_vault"})
	trap["exits"].append({"pos": Vector2(10000, -10000), "room": "phase_vault"})
	_check(not Reach.verify(trap, ["phase_rune"], enemies)["ok"], "phase landing does not reveal isolated surfaces in same room")
	trap = Generator.generate("stone_ramparts", 1, biomes, modules, routes)
	trap["keys"][0]["pos"] = Vector2(10000, -10000)
	_check(not Reach.verify(trap, [], enemies)["ok"], "key requires its actual pickup to be reachable")
	trap = Generator.generate("ash_gate", 1, biomes, modules, routes)
	trap["rooms"][int(trap["room_ids"]["lower"])]["spawns"] = []
	_check(not Reach.verify(trap, [], enemies)["ok"], "enemy budget requires authored spawn slots")
	trap = Generator.generate("ash_gate", 1, biomes, modules, routes)
	trap["exits"][0]["pos"] = Vector2(10000, -10000)
	_check(not Reach.verify(trap, [], enemies)["ok"], "actual physical exit must be reachable")
	var oversized := enemies.duplicate(true)
	for kind in oversized:
		oversized[kind]["body_height"] = 120
	trap = Generator.generate("ash_gate", 1, biomes, modules, routes)
	_check(not Reach.verify(trap, [], oversized)["ok"], "spawn clearance uses actual enemy body dimensions")
	var abilities := ["canopy_rune", "climb_rune", "ground_rune", "phase_rune"]
	var states: Array[Array] = []
	for mask in 16:
		var state: Array = []
		for bit in abilities.size():
			if mask & (1 << bit):
				state.append(abilities[bit])
		states.append(state)
	var count := 4
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--seeds="):
			count = int(str(arg).trim_prefix("--seeds="))
	for id in biomes["biomes"]:
		for seed_value in range(1, count + 1):
			var layout := Generator.generate(str(id), seed_value, biomes, modules, routes)
			_check(var_to_bytes(layout) == var_to_bytes(Generator.generate(str(id), seed_value, biomes, modules, routes)), "deterministic node/seed")
			# shortcut: keys mirror verify()'s gate/edge/room Rune reads, update if that dependency contract grows.
			var controlled_runes := {}
			for gate: Dictionary in layout["gates"]:
				if gate["kind"] == "break":
					controlled_runes[str(gate["rune"])] = true
			for edge: Dictionary in layout["graph"]:
				if str(edge["mode"]) in ["vine", "wall", "phase"]:
					controlled_runes[str(edge["rune"])] = true
			for room: Dictionary in layout["rooms"]:
				for rune: String in room["requires_runes"]:
					controlled_runes[rune] = true
			var verification_cache := {}
			for runes: Array in states:
				var signature := ""
				for rune: String in abilities:
					if controlled_runes.has(rune) and runes.has(rune):
						signature += rune + "|"
				var result: Dictionary = verification_cache.get(signature, {})
				if result.is_empty():
					result = Reach.verify(layout, runes, enemies)
					verification_cache[signature] = result
				_check(bool(result["ok"]), "%s seed %d runes %s: %s" % [str(id), seed_value, str(runes), str(result)])
		print("BIOME GEN PROGRESS %s: %d/%d seeds" % [str(id), count, count])
	print("BIOME GEN %s (%d checks, %d failures, %d seeds per biome)" % ["OK" if _fails == 0 else "FAILED", _checks, _fails, count])
	quit(0 if _fails == 0 else 1)


func _read(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % name))


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("BIOME GEN FAIL: " + message)
