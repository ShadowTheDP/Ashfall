class_name RunCheckpoint
extends RefCounted
## Safe boundaries only: a fresh biome entrance or a fully settled Passage.
const VERSION := 1
const LEGACY_CONTENT_STAMP := "6e650d44b82df4dffbc159894f441eab687f38594d6b01852a67ade3953b15e0"
const FIELDS := ["run_node_id", "route_history", "defeated_bosses", "run_bsc", "floor_index", "floor_name", "run_time", "cells", "run_cells", "kills", "max_combo", "perfect_dodges", "run_keys", "carried_blueprints", "node_time", "kill_streak", "best_kill_streak", "boss_damage", "boss_defeated", "exit_selected", "pending_destination", "passage_snapshot", "passage_claims", "flask_capacity", "flask_charges"]
const COUNTS := ["run_bsc", "floor_index", "cells", "run_cells", "kills", "max_combo", "perfect_dodges", "kill_streak", "best_kill_streak", "flask_capacity", "flask_charges"]
const LISTS := ["route_history", "defeated_bosses", "run_keys", "carried_blueprints"]


static func generator_revision(data: Dictionary) -> String:
	# Missing is the historical v1 contract, never an alias for the newest algorithm.
	if not data.has("generator_revision"): return BiomeGen.LEGACY_REVISION
	return data.generator_revision if data.generator_revision is String else ""


static func content_stamp(revision: String = BiomeGen.LEGACY_REVISION) -> String:
	var original := [Data.route_graph, Data.route_profiles, Data.biomes, Data.room_modules, Data.gear, Data.passage, Data.weapons, Data.enemies]
	if revision == BiomeGen.LEGACY_REVISION:
		return JSON.stringify(original).sha256_text()
	if revision == BiomeGen.LATEST_REVISION:
		return JSON.stringify([revision, BiomeGen.ALGORITHM_REVISION, original, Data.generation_spatial, Data.traversal]).sha256_text()
	return ""


static func capture(game: Node, kind: String, seed_value := 0) -> Dictionary:
	var state := {}
	for field: String in FIELDS:
		var value: Variant = game.get(field)
		state[field] = value.duplicate(true) if typeof(value) in [TYPE_ARRAY, TYPE_DICTIONARY] else value
	var body: Player = game.player
	return {"version":VERSION, "generator_revision":game.generator_revision, "content":content_stamp(game.generator_revision), "kind":kind, "seed":seed_value,
		"state":state, "build":game.build.checkpoint(), "hp":clampf(body.hp, 0, body.max_hp), "weapon_slot":body.weapon_slot}


static func error(data: Dictionary) -> String:
	if data.get("version") != VERSION: return "UNSUPPORTED CHECKPOINT VERSION"
	var revision := generator_revision(data)
	if revision not in [BiomeGen.LEGACY_REVISION, BiomeGen.LATEST_REVISION]: return "UNSUPPORTED GENERATOR REVISION"
	var stamp := content_stamp(revision)
	if (revision == BiomeGen.LEGACY_REVISION and stamp != LEGACY_CONTENT_STAMP) or data.get("content") != stamp: return "CONTENT CHANGED / START A NEW RUN"
	if data.get("kind") not in ["biome_entry", "passage"]: return "INVALID CHECKPOINT KIND"
	if typeof(data.get("state")) != TYPE_DICTIONARY or typeof(data.get("build")) != TYPE_DICTIONARY: return "INVALID CHECKPOINT DATA"
	var state: Dictionary = data.state
	for field: String in COUNTS:
		if not RunBuild._count(state.get(field)): return "INVALID CHECKPOINT COUNT"
	for field in ["run_time", "node_time", "boss_damage"]:
		var value: Variant = state.get(field)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0: return "INVALID CHECKPOINT TIMER"
	for field: String in LISTS:
		if typeof(state.get(field)) != TYPE_ARRAY: return "INVALID CHECKPOINT LIST"
		var seen := {}
		for id: Variant in state[field]:
			if typeof(id) != TYPE_STRING or seen.has(id): return "INVALID CHECKPOINT ID"
			seen[id] = true
	for field in ["boss_defeated", "exit_selected"]:
		if typeof(state.get(field)) != TYPE_BOOL: return "INVALID CHECKPOINT FLAG"
	for field in ["floor_name", "run_node_id", "pending_destination"]:
		if typeof(state.get(field)) != TYPE_STRING: return "INVALID CHECKPOINT NAME"
	var node := str(state.run_node_id)
	if not Data.route_profiles.nodes.has(node) or state.route_history.is_empty() or state.route_history.size() > Data.route_graph.default_0_bsc_route.size() or state.route_history[0] != Data.route_graph.start or state.route_history[-1] != node: return "INVALID SAVED ROUTE"
	if int(state.run_bsc) != 0 or int(state.floor_index) != int(Data.route_profiles.nodes[node].floor_profile): return "INVALID SAVED FLOOR"
	for i in state.route_history.size():
		var id: String = state.route_history[i]
		if not Data.route_profiles.nodes.has(id): return "UNKNOWN SAVED BIOME"
		if i == 0: continue
		var connected := false
		for edge: Dictionary in Data.route_graph.edges:
			if edge.from == state.route_history[i - 1] and edge.to == id:
				connected = true
		if not connected: return "DISCONNECTED SAVED ROUTE"
	for id: String in state.defeated_bosses:
		if not state.route_history.has(id) or Data.route_graph.nodes[id].kind != "boss": return "INVALID SAVED BOSS"
	for id: String in state.carried_blueprints:
		if not Data.passage.blueprints.has(id): return "UNKNOWN SAVED BLUEPRINT"
	if int(state.flask_capacity) != int(Data.route_profiles.flask.capacity) or int(state.flask_charges) > int(state.flask_capacity): return "INVALID SAVED FLASK"
	if typeof(state.get("passage_snapshot")) != TYPE_DICTIONARY or typeof(state.get("passage_claims")) != TYPE_DICTIONARY: return "INVALID PASSAGE STATE"
	if data.kind == "passage":
		if not state.exit_selected or state.passage_snapshot.is_empty(): return "UNFINISHED SAVED PASSAGE"
		var legal := false
		for edge: Dictionary in Data.route_graph.edges:
			if edge.from == node and edge.to == state.pending_destination: legal = true
		if not legal: return "INVALID SAVED DESTINATION"
		var metrics: Dictionary = state.passage_snapshot
		if typeof(metrics.get("flawless")) != TYPE_BOOL or not RunBuild._count(metrics.get("streak")) or typeof(metrics.get("time")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(metrics.time)) or float(metrics.time) < 0: return "INVALID PASSAGE METRICS"
		for key: Variant in state.passage_claims:
			if key not in ["fountain", "time", "streak", "flawless"] or state.passage_claims[key] != true: return "INVALID PASSAGE CLAIM"
	elif state.exit_selected or not state.pending_destination.is_empty() or not state.passage_claims.is_empty():
		return "INVALID BIOME ENTRANCE"
	if not RunBuild._count(data.get("seed")) or not RunBuild._count(data.get("weapon_slot")) or int(data.weapon_slot) > 1: return "INVALID CHECKPOINT POSITION"
	var build := RunBuild.from_checkpoint(data.build)
	if build == null: return "INVALID SAVED GEAR"
	var hp: Variant = data.get("hp")
	if typeof(hp) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(hp)) or float(hp) <= 0 or float(hp) > build.health(): return "INVALID SAVED HEALTH"
	return ""


static func restore(game: Node, data: Dictionary) -> bool:
	if not error(data).is_empty(): return false
	game.reset_run()
	game.generator_revision = generator_revision(data)
	for field: String in FIELDS:
		var current: Variant = game.get(field)
		var value: Variant = data.state[field]
		match typeof(current):
			TYPE_ARRAY: current.assign(value)
			TYPE_DICTIONARY: game.set(field, value.duplicate(true))
			TYPE_INT: game.set(field, int(value))
			TYPE_FLOAT: game.set(field, float(value))
			_: game.set(field, value)
	game.build = RunBuild.from_checkpoint(data.build)
	game.in_hub = false
	game.run_phase = "passage" if data.kind == "passage" else "biome"
	return true
