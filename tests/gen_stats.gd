extends Node
## Generator macro-shape regression. The map went from "a row of rooms" to
## "a two-tier place with an optional upper route and rewards on it"; these are
## the properties that makes it that, asserted across floors x seeds so a future
## generator edit cannot quietly drop them back to a corridor.
##
## Fast on purpose (~5 s): it only generates layouts, it never runs physics.
##
## Run: godot --headless --path . tests/gen_stats.tscn

const SEEDS := 20

var _fails := 0


func _ready() -> void:
	await get_tree().process_frame
	for floor_index in range(1, 6):
		var widths: Array = []
		var rooms_avg := 0.0
		var decks_avg := 0.0
		var links_avg := 0.0
		var caches_min := 99
		var unreachable := 0
		var lost_decks := 0
		var gallery_seeds := 0
		for seed_value in range(1, SEEDS + 1):
			var data: Dictionary = LevelGen.generate(floor_index, seed_value)
			widths.append(float(data["width"]))
			rooms_avg += (data["rooms"] as Array).size()
			decks_avg += _decks(data)
			links_avg += _links(data)
			gallery_seeds += 1 if _links(data) > 0 else 0
			var caches: Array = data.get("caches", [])
			caches_min = mini(caches_min, caches.size())
			var reach: Dictionary = data.get("reachable", {})
			if not bool(reach.get("ok", false)):
				unreachable += 1
			lost_decks += int(reach.get("decks", 0))
			for entry in caches:
				if not _cache_on_surface(data, (entry as Dictionary)["pos"]):
					_fail("floor %d seed %d: cache off any surface" % [floor_index, seed_value])
		var n := float(SEEDS)
		widths.sort()
		print("floor %d: width %.0f-%.0f rooms %.1f decks/floor %.1f gallery-links %.1f (in %d/%d seeds) caches min %d" % [
			floor_index, widths[0], widths[widths.size() - 1], rooms_avg / n, decks_avg / n,
			links_avg / n, gallery_seeds, SEEDS, caches_min])

		if unreachable > 0:
			_fail("floor %d has %d/%d unreachable layouts" % [floor_index, unreachable, SEEDS])
		if lost_decks > 0:
			_fail("floor %d has %d deck(s) outside the jump budget" % [floor_index, lost_decks])
		if caches_min < 1:
			_fail("floor %d has a layout with no reward to explore for" % floor_index)
		if widths[0] < 2600.0:
			_fail("floor %d got narrower than 2600 px" % floor_index)
		# Floors 1-4 are the exploration floors; the last one is the boss arena
		# and is meant to be a single straight fight.
		if floor_index < 5:
			if rooms_avg / n < 5.0:
				_fail("floor %d averages %.1f rooms, expected 5+" % [floor_index, rooms_avg / n])
			if widths[0] < 5200.0:
				_fail("floor %d minimum width %.0f, expected 5200+" % [floor_index, widths[0]])
			if gallery_seeds < SEEDS / 2:
				_fail("floor %d only %d/%d seeds have an upper route" % [floor_index, gallery_seeds, SEEDS])

	print("")
	if _fails == 0:
		print("GEN STATS OK (%d floor x seed layouts)" % (5 * SEEDS))
	else:
		print("GEN STATS FAILED (%d)" % _fails)
	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)


func _decks(data: Dictionary) -> float:
	var n := 0.0
	for room in (data["rooms"] as Array):
		n += (room["platforms"] as Array).size()
	return n


## A gallery link is a connector deck that spans a gap, i.e. a surface that
## belongs to the previous room and starts inside the gap.
func _links(data: Dictionary) -> int:
	var rooms: Array = data["rooms"]
	var n := 0
	for i in range(1, rooms.size()):
		var prev: Rect2 = rooms[i - 1]["rect"]
		var here: Rect2 = rooms[i]["rect"]
		for entry in (rooms[i - 1]["platforms"] as Array):
			var r: Rect2 = entry
			if r.position.x >= prev.end.x - 1.0 and r.position.x <= here.position.x:
				n += 1
	return n


func _cache_on_surface(data: Dictionary, spot: Vector2) -> bool:
	for surface in LevelGen._surfaces(data["rooms"]):
		var r: Rect2 = surface
		if spot.x < r.position.x - 2.0 or spot.x > r.end.x + 2.0:
			continue
		if absf(r.position.y - (spot.y + 12.0)) <= 4.0:
			return true
	return false


func _fail(message: String) -> void:
	_fails += 1
	push_error("GEN STATS FAIL: " + message)
	print("GEN STATS FAIL: ", message)