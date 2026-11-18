extends SceneTree
## Centralized Godot execution only; the Python schema probe does not replace this.
const Generator := preload("res://scripts/world/biome_gen.gd")
var _checks := 0

func _initialize() -> void:
	var biomes := _read("res://data/biomes.json")
	var modules := _read("res://data/room_modules.json")
	var routes := _read("res://data/route_graph.json")
	var spatial := _read("res://data/generation_spatial_v2.json")
	var inputs := var_to_bytes([biomes, modules, routes, spatial])
	# Latest revision only: pre-upgrade golden layouts were a historical migration
	# lock, not current generator behaviour (see tests/archive/README.md).
	_check(Generator.validate_spatial(spatial, biomes, modules).is_empty(), "all authored spatial schemas")
	for id in spatial.profiles:
		var signatures := {}
		for seed_value in range(3):
			var result := Generator.generate_checked(id, seed_value, biomes, modules, routes)
			_check(result.errors.is_empty() and result.attempts == 1 and not result.layout.is_empty(), "one bounded authored candidate: " + str(id))
			if result.layout.is_empty(): continue
			var geometry: Array = []
			for room: Dictionary in result.layout.rooms:
				geometry.append([room.id, room.rect, room.bounds, room.ground, room.platforms, room.sockets])
			signatures[var_to_bytes(geometry).hex_encode()] = true
			_check(result.layout.generator_revision == Generator.LATEST_REVISION, "explicit latest layout revision")
		_check(signatures.size() == 3, "three actual spatial signatures excluding template and enemy names: " + str(id))
	var bad := spatial.duplicate(true)
	bad.profiles.ash_gate.variants[1].nodes.lower.grid = [1, 0]
	_reject(bad, biomes, modules, routes, "overlapping footprints")
	bad = spatial.duplicate(true)
	bad.profiles.ash_gate.variants[1].nodes.lower.templates = []
	_reject(bad, biomes, modules, routes, "empty candidate pool")
	bad = spatial.duplicate(true)
	bad.profiles.ash_gate.variants[1].nodes.lower.templates = ["unknown"]
	_reject(bad, biomes, modules, routes, "unknown template")
	for defect in ["point", "normal", "missing", "size", "collision", "gate"]:
		bad = spatial.duplicate(true)
		var name: String = bad.profiles.ash_gate.variants[1].nodes.lower.templates[0]
		bad.profiles.ash_gate.variants[1].nodes.lower.templates = [name]
		var module: Dictionary = bad.modules[name]
		match defect:
			"point": module.sockets.east.point[0] += 32
			"normal": module.sockets.east.normal = [-1, 0]
			"missing": module.sockets.erase("east")
			"size": module.size[0] = 640
			"collision": module.solids[0][2] += 32
			"gate": module["gates"] = [{"id":"escaped_gate", "kind":"break", "rune":"ground_rune", "rect":[-20, -16, 20, 16]}]
		_reject(bad, biomes, modules, routes, defect)
	bad = spatial.duplicate(true)
	bad.profiles.ash_gate.variants[1].nodes.upper["requires_runes"] = ["canopy_rune"]
	_reject(bad, biomes, modules, routes, "variant cannot change Rune prerequisites or create an acquisition cycle")
	bad = spatial.duplicate(true)
	bad.profiles.ash_gate.variants[1].nodes.lower["budget"] = 9
	_reject(bad, biomes, modules, routes, "variant cannot rebalance enemy or reward budgets")
	var unknown := Generator.generate_checked("ash_gate", 1, biomes, modules, routes, "unknown")
	_check(unknown.layout.is_empty() and not unknown.errors.is_empty() and unknown.attempts == 0, "unknown revision fails before assembly")
	bad = spatial.duplicate(true)
	bad.modules["unused_invalid_v2"] = modules.modules.entry.duplicate(true)
	bad.modules.unused_invalid_v2.spawns = "invalid"
	_check(not Generator.validate_spatial(bad, biomes, modules).is_empty(), "unused versioned module is still validated")
	var bad_modules := modules.duplicate(true)
	bad_modules.modules["unused_invalid_original"] = modules.modules.entry.duplicate(true)
	bad_modules.modules.unused_invalid_original.size = [0, 276]
	_check(not Generator.validate_spatial(spatial, biomes, bad_modules).is_empty(), "unused original module is still validated")
	var bad_biomes := biomes.duplicate(true)
	bad_biomes.biomes.clock_spire.nodes[0].grid = [0]
	_check(not Generator.validate_spatial(spatial, bad_biomes, modules).is_empty(), "other biome schema remains validated")
	bad = spatial.duplicate(true)
	bad.profiles.clock_spire.variants[2].nodes.entry = {"grid": [0]}
	_check(not Generator.validate_spatial(bad, biomes, modules).is_empty(), "every other biome variant remains validated")
	bad = spatial.duplicate(true)
	bad.modules["entry"] = modules.modules.entry.duplicate(true)
	bad.modules.entry.roles = []
	_check(not Generator.validate_spatial(bad, biomes, modules).is_empty(), "versioned overrides cannot invalidate original biome candidates")
	var isolated := Generator.generate("ash_gate", 2, biomes, modules, routes)
	isolated.rooms[0].requires_runes.append("layout_only")
	isolated.graph[0]["from"] = "layout_only"
	_check(var_to_bytes([biomes, modules, routes, spatial]) == inputs, "validation, preparation and layout mutation do not mutate input tables")
	print("GENERATION SPATIAL OK (%d checks)" % _checks)
	quit(0)

func _reject(spatial: Dictionary, biomes: Dictionary, modules: Dictionary, routes: Dictionary, label: String) -> void:
	var result := Generator.generate_checked("ash_gate", 1, biomes, modules, routes, Generator.LATEST_REVISION, spatial)
	_check(result.layout.is_empty() and not result.errors.is_empty() and result.attempts <= 1, "bounded rejection: " + label)

func _read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _check(ok: bool, message: String) -> void:
	_checks += 1
	assert(ok, "GENERATION SPATIAL FAIL: " + message)
