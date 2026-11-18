extends SceneTree
## Reusable raw generation evidence; invoke with an isolated ASHFALL_PROFILE_PATH.
const Generator := preload("res://scripts/world/biome_gen.gd")
const Reach := preload("res://scripts/systems/surface_reach.gd")
const RUNE_STATES := {
	"fresh": [],
	"after_gallery": ["canopy_rune"],
	"after_cistern": ["canopy_rune", "phase_rune"],
	"completed_delivery_a": ["canopy_rune", "phase_rune", "clock_rune", "homunculus_rune"]}


func _initialize() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--output="):
			output = str(arg).trim_prefix("--output=")
	if OS.get_environment("ASHFALL_PROFILE_PATH").is_empty() or output.is_empty():
		push_error("GENERATION METRICS requires isolated ASHFALL_PROFILE_PATH and --output")
		quit(1)
		return
	var biomes: Dictionary = _read("biomes")
	var modules: Dictionary = _read("room_modules")
	var routes: Dictionary = _read("route_graph")
	var enemies: Dictionary = _read("enemies")
	if not Generator.validate(biomes, modules).is_empty():
		push_error("GENERATION METRICS invalid inherited schema")
		quit(1)
		return
	var records: Array = []
	var checks := 0
	for id in biomes["biomes"]:
		for seed_value in range(1, 33):
			var started := Time.get_ticks_usec()
			var layout := Generator.generate(str(id), seed_value, biomes, modules, routes)
			var elapsed_us := Time.get_ticks_usec() - started
			if layout.is_empty() or var_to_bytes(layout) != var_to_bytes(Generator.generate(str(id), seed_value, biomes, modules, routes)):
				push_error("GENERATION METRICS empty or nondeterministic: %s/%d" % [id, seed_value])
				quit(1)
				return
			checks += 1
			var verification := {}
			var cache := {}
			var controlled := {}
			for gate: Dictionary in layout["gates"]:
				if str(gate["kind"]) == "break":
					controlled[str(gate["rune"])] = true
			for edge: Dictionary in layout["graph"]:
				if str(edge["mode"]) in ["vine", "wall", "phase"]:
					controlled[str(edge["rune"])] = true
			for room: Dictionary in layout["rooms"]:
				for rune: String in room["requires_runes"]:
					controlled[rune] = true
			for state in RUNE_STATES:
				var signature := ""
				for rune: String in RUNE_STATES[state]:
					if controlled.has(rune):
						signature += rune + "|"
				if not cache.has(signature):
					cache[signature] = Reach.verify(layout, RUNE_STATES[state], enemies)
				verification[state] = cache[signature]
				checks += 1
				if not bool(verification[state]["ok"]):
					push_error("GENERATION METRICS reach failure: %s/%d/%s: %s" % [id, seed_value, state, str(verification[state])])
					quit(1)
					return
			records.append({"profile": id, "seed": seed_value, "generation_elapsed_us": elapsed_us,
				"layout": _json_value(layout), "verification": _json_value(verification)})
		print("GENERATION METRICS %s: 32 seeds" % id)
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("GENERATION METRICS cannot open output: " + output)
		quit(1)
		return
	file.store_string(JSON.stringify({"schema_version": 1, "seeds": range(1, 33),
		"rune_states": RUNE_STATES, "checks": checks, "records": records}, "\t", true, true))
	file.close()
	print("GENERATION METRICS OK: %d layouts, %d checks" % [records.size(), checks])
	quit(0)


func _json_value(value: Variant) -> Variant:
	if value is Vector2:
		return [value.x, value.y]
	if value is Rect2:
		return [value.position.x, value.position.y, value.size.x, value.size.y]
	if value is Dictionary:
		var out := {}
		for key in value:
			out[str(key)] = _json_value(value[key])
		return out
	if value is Array or value is PackedStringArray:
		var out: Array = []
		for item in value:
			out.append(_json_value(item))
		return out
	return value


func _read(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % name))
