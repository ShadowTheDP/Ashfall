extends SceneTree

const Graph := preload("res://scripts/systems/route_graph.gd")
var _fails := 0
var _checks := 0


func _initialize() -> void:
	var file := FileAccess.open("res://data/route_graph.json", FileAccess.READ)
	var graph: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	_check(Graph.validate(graph).is_empty(), "graph schema and progressive reachability")
	var fresh := {"runes": [], "keys": [], "bsc": 0}
	var path := Graph.reachable_path(graph, str(graph["start"]), str(graph["final"]), fresh)
	_check(path.size() == 9, "fresh acceptance path has nine visits")
	_check(Graph.available_exits(graph, "ash_gate", fresh).size() == 1, "fresh start is Gallery only")
	_check(Graph.available_exits(graph, "ash_gate", {"runes": ["canopy_rune"]}).size() == 2, "canopy opens Cistern")
	var report := Graph.progression_report(graph)
	_check(report["unreachable"].is_empty(), "all 19 nodes reachable through legitimate repeated runs")
	_check(report["missing_runes"].is_empty(), "all runes can be earned")
	_check(report["dead_ends"].is_empty(), "no reachable state traps a run")
	_check(report["rounds"].size() > 1, "unlocking requires multiple runs")
	_check(not fresh["runes"].has("canopy_rune") and fresh["keys"].is_empty(), "query does not mutate caller state")
	_check(Graph.available_exits(graph, "stone_ramparts", fresh).size() == 1, "BSC 0 gate closed")
	_check(Graph.available_exits(graph, "stone_ramparts", {"bsc": 3}).size() == 2, "BSC 3 gate opens")
	for edge: Dictionary in graph["edges"]:
		if edge.get("requires_keys", []).is_empty():
			continue
		var state := {"runes": report["runes"], "keys": [], "bsc": 5}
		_check(not Graph.lock_reason(edge, state).is_empty(), "key gate rejects empty wallet")
		state["keys"] = edge["requires_keys"].duplicate()
		_check(Graph.lock_reason(edge, state).is_empty(), "key gate accepts exact keys")
	var broken := graph.duplicate(true)
	for edge: Dictionary in broken["edges"]:
		if str(edge["to"]) == "ash_graveyard":
			edge["requires_runes"] = ["pathfinder_rune"]
	var locked := Graph.progression_report(broken)
	_check(locked["unreachable"].has("ash_graveyard"), "self-locked Graveyard detected")
	_check(locked["missing_runes"].has("pathfinder_rune") and locked["missing_runes"].has("lens_rune"), "downstream rune deadlock reported")
	_check(not Graph.validate(broken).is_empty(), "validator rejects progression deadlock")
	var dead := graph.duplicate(true)
	dead["edges"] = (dead["edges"] as Array).filter(func(e: Dictionary) -> bool: return e["from"] != "silt_cistern")
	_check(Graph.progression_report(dead)["dead_ends"].has("silt_cistern"), "reachable dead end reported")
	# Two sibling branches cannot pool their keys into a gate neither can open.
	var siblings := {"start": "a", "final": "z", "nodes": {
		"a": {}, "b": {"key_rewards": ["left"]}, "c": {"key_rewards": ["right"]}, "z": {}},
		"edges": [{"from": "a", "to": "b"}, {"from": "a", "to": "c"},
			{"from": "b", "to": "z", "requires_keys": ["left", "right"]},
			{"from": "c", "to": "z", "requires_keys": ["left", "right"]}]}
	_check(Graph.reachable_path(siblings, "a", "z", fresh).is_empty(), "sibling keys stay path-local")
	print("ROUTE GRAPH %s (%d checks, %d failures, %d progressive rounds)" % ["OK" if _fails == 0 else "FAILED", _checks, _fails, report["rounds"].size()])
	quit(0 if _fails == 0 else 1)


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("ROUTE GRAPH FAIL: " + message)
