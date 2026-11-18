extends RefCounted
class_name RouteGraph
## Validation and queries for the Ashfall biome-route graph.


static func validate(graph: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if typeof(graph.get("nodes")) != TYPE_DICTIONARY or typeof(graph.get("edges")) != TYPE_ARRAY:
		errors.append("nodes object and edges array are required")
		return errors
	var nodes: Dictionary = graph.get("nodes", {})
	var edges: Array = graph.get("edges", [])
	var start := str(graph.get("start", ""))
	var final := str(graph.get("final", ""))
	if nodes.is_empty():
		errors.append("nodes must not be empty")
		return errors
	if not nodes.has(start):
		errors.append("start node is missing")
	if not nodes.has(final):
		errors.append("final node is missing")
	var biome_count := 0
	var boss_count := 0
	for node_id in nodes:
		if typeof(nodes[node_id]) != TYPE_DICTIONARY:
			errors.append("node must be an object: %s" % str(node_id))
			continue
		var node: Dictionary = nodes[node_id]
		for field in ["rune_rewards", "key_rewards"]:
			if typeof(node.get(field, [])) != TYPE_ARRAY:
				errors.append("node reward list must be an array: %s" % str(node_id))
		var kind := str(node.get("kind", ""))
		if kind == "biome":
			biome_count += 1
		elif kind == "boss":
			boss_count += 1
		else:
			errors.append("unknown node kind: %s" % str(node_id))
		if int(node.get("stage", 0)) <= 0:
			errors.append("node stage must be positive: %s" % str(node_id))
	if biome_count != 15 or boss_count != 4:
		errors.append("no-DLC graph requires 15 biomes and 4 bosses")
	if not errors.is_empty():
		return errors
	var edge_keys := {}
	for edge_value in edges:
		if typeof(edge_value) != TYPE_DICTIONARY:
			errors.append("edge must be an object")
			continue
		var edge: Dictionary = edge_value
		if typeof(edge.get("requires_runes", [])) != TYPE_ARRAY or typeof(edge.get("requires_keys", [])) != TYPE_ARRAY:
			errors.append("edge requirements must be arrays")
			continue
		var source := str(edge.get("from", ""))
		var target := str(edge.get("to", ""))
		if not nodes.has(source) or not nodes.has(target):
			errors.append("edge references an unknown node: %s -> %s" % [source, target])
			continue
		if source == target:
			errors.append("self edge is not allowed: %s" % source)
		var pair := source + "->" + target
		if edge_keys.has(pair):
			errors.append("duplicate edge: %s" % pair)
		edge_keys[pair] = true
		var source_stage := int((nodes[source] as Dictionary).get("stage", -1))
		var target_stage := int((nodes[target] as Dictionary).get("stage", -1))
		if target_stage <= source_stage:
			errors.append("edge must move to a later stage: %s" % pair)
		for rune_value in edge.get("requires_runes", []):
			if str(rune_value).is_empty():
				errors.append("empty rune requirement: %s" % pair)
		for key_value in edge.get("requires_keys", []):
			if str(key_value).is_empty():
				errors.append("empty key requirement: %s" % pair)
	if not errors.is_empty():
		return errors
	var unlocked_runes: Array = []
	for node_value in nodes.values():
		var node: Dictionary = node_value
		for rune in node.get("rune_rewards", []):
			if not unlocked_runes.has(str(rune)):
				unlocked_runes.append(str(rune))
	var fully_unlocked := {"runes": unlocked_runes, "keys": [], "bsc": 5}
	for node_id in nodes:
		if reachable_path(graph, start, str(node_id), fully_unlocked).is_empty():
			errors.append("node is unreachable with all runes and BSCs unlocked: %s" % str(node_id))
	var route: Array = graph.get("default_0_bsc_route", [])
	if route.size() < 2 or str(route[0]) != start or str(route[-1]) != final:
		errors.append("default 0-BSC route must connect start to final")
		return errors
	var route_state: Dictionary = {"runes": [], "keys": [], "bsc": 0}
	for index in route.size():
		var node_id := str(route[index])
		if not nodes.has(node_id):
			errors.append("default route references an unknown node: %s" % node_id)
			continue
		if index == 0:
			_collect_node_rewards(nodes[node_id], route_state)
			continue
		var previous := str(route[index - 1])
		var matching: Dictionary = {}
		for edge_value in edges:
			var edge: Dictionary = edge_value
			if str(edge.get("from", "")) == previous and str(edge.get("to", "")) == node_id:
				matching = edge
				break
		if matching.is_empty():
			errors.append("default route has no edge: %s -> %s" % [previous, node_id])
		elif not _edge_open(matching, route_state):
			errors.append("default route edge is locked at 0 BSC: %s -> %s" % [previous, node_id])
		_collect_node_rewards(nodes[node_id], route_state)
	var state := {"runes": [], "keys": [], "bsc": 0}
	var path := reachable_path(graph, start, final, state)
	if path.is_empty():
		errors.append("final is unreachable for a fresh 0-BSC profile")
	var default_biome_count := 0
	var default_boss_count := 0
	for node_id in route:
		var kind := str((nodes.get(str(node_id), {}) as Dictionary).get("kind", ""))
		if kind == "boss":
			default_boss_count += 1
		elif kind == "biome":
			default_biome_count += 1
	if default_biome_count != 6 or default_boss_count != 3:
		errors.append("default route must contain 6 biomes and 3 bosses")
	var progression := progression_report(graph, 0)
	for node_id in progression["unreachable"]:
		errors.append("node cannot be unlocked from a fresh profile: %s" % str(node_id))
	for rune in progression["missing_runes"]:
		errors.append("rune cannot be acquired: %s" % str(rune))
	for node_id in progression["dead_ends"]:
		errors.append("reachable state cannot reach final: %s" % str(node_id))
	return errors


static func available_exits(graph: Dictionary, node_id: String, state: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for edge_value in graph.get("edges", []):
		var edge: Dictionary = edge_value
		if str(edge.get("from", "")) == node_id and _edge_open(edge, state):
			out.append(edge)
	return out


static func reachable_path(graph: Dictionary, start: String, target: String, state: Dictionary) -> PackedStringArray:
	var nodes: Dictionary = graph.get("nodes", {})
	if not nodes.has(start) or not nodes.has(target):
		return PackedStringArray()
	var initial_state: Dictionary = state.duplicate(true)
	_collect_node_rewards(nodes[start], initial_state)
	var queue: Array[Dictionary] = [{
		"current": start,
		"path": PackedStringArray([start]),
		"state": initial_state,
	}]
	var visited: Dictionary = {}
	while not queue.is_empty():
		var item: Dictionary = queue.pop_front()
		var current: String = str(item["current"])
		var current_state: Dictionary = item["state"]
		var path: PackedStringArray = item["path"]
		if current == target:
			return path
		for edge in available_exits(graph, current, current_state):
			var next_id: String = str(edge.get("to", ""))
			var next_state: Dictionary = current_state.duplicate(true)
			_collect_node_rewards(nodes[next_id], next_state)
			var signature: String = _state_signature(next_id, next_state)
			if visited.has(signature):
				continue
			visited[signature] = true
			var next_path: PackedStringArray = path.duplicate()
			next_path.append(next_id)
			queue.append({"current": next_id, "path": next_path, "state": next_state})
	return PackedStringArray()


static func progression_report(graph: Dictionary, bsc: int = 0) -> Dictionary:
	var nodes: Dictionary = graph.get("nodes", {})
	var known: Array = []
	var reached: Array = []
	var dead_ends: Array = []
	var rounds: Array = []
	var all_runes: Array = []
	for node: Dictionary in nodes.values():
		for rune in node.get("rune_rewards", []):
			if not all_runes.has(rune):
				all_runes.append(rune)
	var changed := true
	while changed:
		changed = false
		var gained: Array = []
		var queue: Array[Dictionary] = [{"node": str(graph["start"]), "state": {"runes": known.duplicate(), "keys": [], "bsc": bsc}}]
		var visited: Dictionary = {}
		while not queue.is_empty():
			var entry: Dictionary = queue.pop_front()
			var id := str(entry["node"])
			var state: Dictionary = entry["state"]
			_collect_node_rewards(nodes[id], state)
			var signature := _state_signature(id, state)
			if visited.has(signature):
				continue
			visited[signature] = true
			if not reached.has(id):
				reached.append(id)
			for rune in state["runes"]:
				if not known.has(rune) and not gained.has(rune):
					gained.append(rune)
			if reachable_path(graph, id, str(graph["final"]), state).is_empty() and not dead_ends.has(id):
				dead_ends.append(id)
			for edge in available_exits(graph, id, state):
				queue.append({"node": str(edge["to"]), "state": state.duplicate(true)})
		if not gained.is_empty():
			known.append_array(gained)
			rounds.append(gained)
			changed = true
	var unreachable: Array = []
	for id in nodes:
		if not reached.has(id):
			unreachable.append(id)
	var missing: Array = []
	for rune in all_runes:
		if not known.has(rune):
			missing.append(rune)
	return {"runes": known, "nodes": reached, "rounds": rounds, "unreachable": unreachable, "missing_runes": missing, "dead_ends": dead_ends}


static func lock_reason(edge: Dictionary, state: Dictionary) -> String:
	if int(state.get("bsc", 0)) < int(edge.get("min_bsc", 0)):
		return "BSC %d" % int(edge["min_bsc"])
	for rune in edge.get("requires_runes", []):
		if not (state.get("runes", []) as Array).has(str(rune)):
			return str(rune).replace("_", " ").to_upper()
	for key in edge.get("requires_keys", []):
		if not (state.get("keys", []) as Array).has(str(key)):
			return str(key).replace("_", " ").to_upper()
	return ""


static func _collect_node_rewards(node: Dictionary, state: Dictionary) -> void:
	var runes: Array = state.get("runes", []).duplicate()
	for rune in node.get("rune_rewards", []):
		if not runes.has(str(rune)):
			runes.append(str(rune))
	state["runes"] = runes
	var keys: Array = state.get("keys", []).duplicate()
	for key in node.get("key_rewards", []):
		if not keys.has(str(key)):
			keys.append(str(key))
	state["keys"] = keys


static func _state_signature(node_id: String, state: Dictionary) -> String:
	var runes: Array = state.get("runes", []).duplicate()
	var keys: Array = state.get("keys", []).duplicate()
	runes.sort()
	keys.sort()
	return "%s|%s|%s|%d" % [node_id, str(runes), str(keys), int(state.get("bsc", 0))]


static func _edge_open(edge: Dictionary, state: Dictionary) -> bool:
	if int(state.get("bsc", 0)) < int(edge.get("min_bsc", 0)):
		return false
	var runes: Array = state.get("runes", [])
	for required in edge.get("requires_runes", []):
		if not runes.has(str(required)):
			return false
	var keys: Array = state.get("keys", [])
	for required in edge.get("requires_keys", []):
		if not keys.has(str(required)):
			return false
	return true
