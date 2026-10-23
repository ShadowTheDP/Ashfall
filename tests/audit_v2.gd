extends Node
## Audit V2: the enemy / encounter layer at generated-floor scale.
##
## Every probe builds REAL geometry from LevelGen (same rects, same one-way
## flags as level.gd) so a failure is a gameplay failure, not a test artefact.
##
## Run: godot --headless --path . tests/audit_v2.tscn

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const FLOOR := 4
const SEED := 20260214

var _failures := 0
var _world: Node2D
var _player: Player
var _rects: Array = []      # [{ "rect": Rect2, "oneway": bool }]
var _data: Dictionary = {}
var _verbose := true


func _ready() -> void:
	await get_tree().process_frame
	_data = LevelGen.generate(FLOOR, SEED)
	_build_world()
	await _probe_spawn_embed()
	await _probe_floor_new_kinds()
	await _probe_deck_fall()
	await _probe_recovery()
	await _probe_deembed()
	await _probe_clump()
	await _probe_archer_wall()
	await _probe_cells()
	await _probe_all_kinds()
	await _probe_new_kinds()
	await _probe_budget()
	_finish()


# --- harness ----------------------------------------------------------------

func _build_world() -> void:
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	Game.fx_root = _world
	Game.run_over = false
	Game.reset_run()
	Game.run_over = false
	Game.fx_root = _world

	for room in _data["rooms"]:
		for ground in room["ground"]:
			_body(ground, false)
		for entry in _surfaces_of(room):
			_body(entry["rect"], bool(entry["oneway"]))
	_body(Rect2(-24.0, -560.0, 24.0, 760.0), false)
	_body(Rect2(float(_data["width"]), -560.0, 24.0, 760.0), false)

	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = _data["start"]
	_world.add_child(_player)
	Game.player = _player
	_player.max_hp = 100000.0
	_player.hp = 100000.0


## LevelGen stores surfaces as `platforms: Array[Rect2]` plus a parallel
## `oneway: Array[bool]`; an older build used one dictionary per surface. The
## probe reads both so a generator refactor cannot silently empty the world.
func _surfaces_of(room: Dictionary) -> Array:
	var out: Array = []
	var plats: Array = room.get("platforms", [])
	var flags: Array = room.get("oneway", [])
	for i in plats.size():
		var entry: Variant = plats[i]
		if entry is Dictionary:
			out.append({"rect": entry["rect"], "oneway": bool(entry.get("oneway", false))})
		else:
			out.append({"rect": entry, "oneway": bool(flags[i]) if i < flags.size() else false})
	return out


func _body(rect: Rect2, oneway: bool) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = Layers.ONEWAY if oneway else Layers.WORLD
	body.collision_mask = 0
	body.position = rect.position + rect.size * 0.5
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	if oneway:
		collision.one_way_collision = true
		collision.one_way_collision_margin = 6.0
	body.add_child(collision)
	_world.add_child(body)
	_rects.append({"rect": rect, "oneway": oneway})


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL: ", message)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _note(message: String) -> void:
	if _verbose:
		print("  . ", message)


func _spawn(kind: String, at: Vector2) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.configure(kind, Data.enemies.get(kind, {}), 1.0)
	enemy.position = at
	_world.add_child(enemy)
	enemy._spawn_t = 0.0
	return enemy


func _inside_solid(point: Vector2, include_oneway := true) -> bool:
	for entry in _rects:
		if not include_oneway and bool(entry["oneway"]):
			continue
		if (entry["rect"] as Rect2).has_point(point):
			return true
	return false


## The continuous bottom ledge: the widest ground rect on the floor.
func _ledge_y() -> float:
	var best := -1.0e9
	var widest := 0.0
	for entry in _rects:
		var r: Rect2 = entry["rect"]
		if bool(entry["oneway"]) or r.size.x <= widest:
			continue
		widest = r.size.x
		best = r.position.y
	return best


## Distance from a point to the nearest walkable surface directly below it.
func _surface_below(point: Vector2) -> float:
	var best := 1.0e9
	for entry in _rects:
		var r: Rect2 = entry["rect"]
		if point.x < r.position.x or point.x > r.end.x:
			continue
		if r.position.y < point.y - 1.0:
			continue
		best = minf(best, r.position.y)
	return best


func _park_player(at: Vector2) -> void:
	_player.global_position = at
	_player.velocity = Vector2.ZERO
	_player.hp = 100000.0
	Game.run_over = false


# --- 1. spawn integrity -----------------------------------------------------

## Spawns every enemy in a room's own spawn table, including the fallback point
## level.gd uses when a room runs out of spawn points, and reports any body
## born inside stone.
func _probe_spawn_embed() -> void:
	print("\n--- 1. SPAWN INTEGRITY (13 bodies, real Level) ---")
	var level := Level.new()
	level.name = "Level"
	add_child(level)
	level.build(FLOOR, SEED)
	await _frames(2)
	_park_player(_data["start"])
	for i in (level.data["rooms"] as Array).size():
		level._enter_room(i)
	await _frames(4)

	var spawned := 0
	var embedded := 0
	for child in level.get_children():
		if not (child is Enemy):
			continue
		var enemy := child as Enemy
		spawned += 1
		var centre: Vector2 = enemy.global_position
		var feet: Vector2 = centre + Vector2(0.0, float(enemy.cfg.get("body_height", 42.0)) * 0.5)
		if _inside_solid(centre) or _inside_solid(feet):
			embedded += 1
			print("    embedded %s at %s (centre_solid=%s feet_solid=%s)" % [
				enemy.kind, str(centre.round()), str(_inside_solid(centre)), str(_inside_solid(feet))])
	var expected := 0
	for group in (Data.floors[str(FLOOR)]["enemies"] as Array):
		expected += int(group[1])
	_check(spawned == expected, "floor %d spawned %d enemies, floor table asks for %d" % [
		FLOOR, spawned, expected])
	_check(embedded == 0, "%d of %d spawned bodies started inside geometry" % [embedded, spawned])
	_note("spawned=%d embedded=%d" % [spawned, embedded])
	for child in level.get_children():
		if child is Enemy:
			child.queue_free()
	level.queue_free()
	await _frames(2)


## The floor table is out of this worker's scope, so the probe adds the two new
## kinds in memory only: everything else is the real Level spawn path.
func _probe_floor_new_kinds() -> void:
	print("
--- 1b. NEW KINDS SPAWNED BY A FLOOR ---")
	var floor_cfg: Dictionary = Data.floors[str(FLOOR)]
	var saved: Array = (floor_cfg["enemies"] as Array).duplicate(true)
	(floor_cfg["enemies"] as Array).append(["spitter", 2])
	(floor_cfg["enemies"] as Array).append(["leaper", 2])
	var level := Level.new()
	add_child(level)
	level.build(FLOOR, SEED)
	await _frames(2)
	_park_player(_data["start"])
	for i in (level.data["rooms"] as Array).size():
		level._enter_room(i)
	await _frames(4)
	var counts := {}
	var embedded := 0
	for child in level.get_children():
		if not (child is Enemy):
			continue
		var enemy := child as Enemy
		counts[enemy.kind] = int(counts.get(enemy.kind, 0)) + 1
		if _inside_solid(enemy.global_position):
			embedded += 1
			print("    %s spawned inside geometry at %s" % [enemy.kind, str(enemy.global_position.round())])
	_check(int(counts.get("spitter", 0)) == 2, "floor spawned %d spitters, expected 2" % int(counts.get("spitter", 0)))
	_check(int(counts.get("leaper", 0)) == 2, "floor spawned %d leapers, expected 2" % int(counts.get("leaper", 0)))
	_check(embedded == 0, "%d new bodies started inside geometry" % embedded)
	_note("kinds spawned: %s" % str(counts))
	for child in level.get_children():
		if child is Enemy:
			child.queue_free()
	level.queue_free()
	floor_cfg["enemies"] = saved
	await _frames(2)


# --- 2. one-way decks -------------------------------------------------------

func _probe_deck_fall() -> void:
	print("\n--- 2. ONE-WAY DECKS ---")
	var decks: Array = []
	for entry in _rects:
		if bool(entry["oneway"]) and (entry["rect"] as Rect2).size.x > 60.0:
			decks.append(entry["rect"])
	_check(decks.size() >= 4, "floor has only %d one-way decks to test" % decks.size())
	var dropped := 0
	for i in mini(4, decks.size()):
		var deck: Rect2 = decks[i]
		var at := Vector2(deck.get_center().x, deck.position.y - 60.0)
		_park_player(at + Vector2(600.0, -400.0))
		var enemy := _spawn("grunt", at)
		await _frames(45)
		var landed := absf(enemy.global_position.y - (deck.position.y - 21.0)) < 10.0
		if not landed:
			dropped += 1
			print("    deck %d: body rest y=%.1f, deck top=%.1f, on_floor=%s" % [
				i, enemy.global_position.y, deck.position.y, str(enemy.is_on_floor())])
		enemy.queue_free()
	# Knocked up through a deck: it must come back down and land on top.
	var deck2: Rect2 = decks[0]
	var under := Vector2(deck2.get_center().x, deck2.end.y + 40.0)
	var knock := _spawn("grunt", under)
	await _frames(20)
	knock.take_hit({"damage": 1.0, "knockback": 300.0, "source_pos": knock.global_position - Vector2(30.0, 0.0)})
	await _frames(60)
	var above := knock.global_position.y < deck2.position.y - 5.0
	_check(not above, "knockback pushed a body up through a one-way deck (y=%.1f, deck=%.1f)" % [
		knock.global_position.y, deck2.position.y])
	knock.queue_free()
	_check(dropped == 0, "%d of 4 bodies fell through the deck they spawned on" % dropped)
	_note("decks=%d dropped=%d" % [decks.size(), dropped])
	await _frames(2)


# --- 3. recovery ------------------------------------------------------------

## An enemy stranded on a deck above the player must come down and engage
## instead of pacing on the deck forever.
func _probe_recovery() -> void:
	print("\n--- 3. DECK RECOVERY ---")
	var decks: Array = []
	for entry in _rects:
		if bool(entry["oneway"]) and (entry["rect"] as Rect2).size.x > 120.0:
			decks.append(entry["rect"])
	# Clear the field. `_separation()` makes every body push its neighbours, so
	# a leftover body standing where this one spawns holds it in place at a
	# crawl - which reads as "never recovers" when the AI is actually fine.
	# Only bodies from EARLIER probes are removed; this probe's own subject is
	# spawned afterwards.
	for other in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(other):
			other.queue_free()
	await _frames(4)
	var deck: Rect2 = decks[0]
	var floor_y := _surface_below(Vector2(deck.get_center().x, deck.end.y + 1.0))
	_park_player(Vector2(deck.get_center().x, floor_y - 40.0))
	var enemy := _spawn("grunt", Vector2(deck.get_center().x, deck.position.y - 40.0))
	var start := enemy.global_position
	var engaged := false
	for i in 480:
		await get_tree().physics_frame
		_player.hp = 100000.0
		if enemy.global_position.y > deck.end.y + 10.0:
			engaged = true
			break
	_check(engaged, "grunt never left the deck above the player (y=%.1f, deck top=%.1f)" % [
		enemy.global_position.y, deck.position.y])
	_note("recovered=%s travel=%.0f px" % [str(engaged), enemy.global_position.distance_to(start)])
	enemy.queue_free()
	await _frames(2)


## level.gd's fallback spawn point is the room centre, which is where a "well"
## room stands its wall. A body born inside it has to get itself out.
func _probe_deembed() -> void:
	print("
--- 3b. DE-EMBED A SPAWN INSIDE A WALL ---")
	var wall := Rect2()
	var found := false
	for entry in _rects:
		var r: Rect2 = entry["rect"]
		if not bool(entry["oneway"]) and r.size.y > 120.0 and r.size.x < 140.0:
			wall = r
			found = true
			break
	if not _check(found, "no wall to spawn inside"):
		return
	_park_player(Vector2(wall.position.x - 400.0, _ledge_y() - 40.0))
	var enemy := _spawn("grunt", wall.get_center())
	await _frames(6)
	var centre: Vector2 = enemy.global_position
	var feet: Vector2 = centre + Vector2(0.0, 21.0)
	_check(not _inside_solid(centre, false), "%s stayed buried in the wall at %s" % [
		enemy.kind, str(centre.round())])
	_check(not _inside_solid(feet, false), "%s has its feet inside the wall at %s" % [
		enemy.kind, str(feet.round())])
	_note("spawned inside %s, settled at %s" % [str(wall), str(centre.round())])
	enemy.queue_free()
	await _frames(2)


# --- 4. clumping ------------------------------------------------------------

func _probe_clump() -> void:
	print("\n--- 4. CLUMPING ---")
	var ledge_y := _surface_below(Vector2(_data["start"].x, _data["start"].y))
	_park_player(Vector2(_data["start"].x, ledge_y - 40.0))
	var bodies: Array = []
	for i in 5:
		bodies.append(_spawn("grunt", Vector2(_data["start"].x + 200.0 + float(i) * 6.0, ledge_y - 40.0)))
	# Clumping is bodies occupying one silhouette for a sustained stretch, not a
	# single frame of two windups overlapping.
	var overlap := {}
	var longest := 0.0
	for i in 300:
		await get_tree().physics_frame
		for a in bodies.size():
			for b in range(a + 1, bodies.size()):
				var key := "%d-%d" % [a, b]
				var gap: float = (bodies[a] as Node2D).global_position.distance_to((bodies[b] as Node2D).global_position)
				overlap[key] = float(overlap.get(key, 0.0)) + (1.0 / 120.0 if gap < 12.0 else -0.02)
				overlap[key] = maxf(0.0, float(overlap[key]))
				longest = maxf(longest, float(overlap[key]))
	_check(longest < 0.5, "two grunts shared one silhouette for %.2fs" % longest)
	_note("longest shared silhouette = %.2fs" % longest)
	for body in bodies:
		body.queue_free()
	await _frames(2)


# --- 5. archers and walls ---------------------------------------------------

## A Watcher with a pillar between it and the player must not fire into stone.
func _probe_archer_wall() -> void:
	print("\n--- 5. ARCHER LINE OF FIRE ---")
	var wall: Rect2 = Rect2()
	var found := false
	for entry in _rects:
		var r: Rect2 = entry["rect"]
		if not bool(entry["oneway"]) and r.size.y > 120.0 and r.size.x > 40.0 and r.size.x < 120.0:
			wall = r
			found = true
			break
	if not _check(found, "no pillar/wall found on this floor to hide behind"):
		return
	var y := _ledge_y()
	_park_player(Vector2(wall.position.x - 150.0, y - 40.0))
	var archer := _spawn("archer", Vector2(wall.end.x + 150.0, y - 40.0))
	var shots := 0
	for i in 300:
		await get_tree().physics_frame
		_player.hp = 100000.0
		for child in _world.get_children():
			if child is Projectile and not child.is_queued_for_deletion():
				if not child.has_meta("counted"):
					child.set_meta("counted", true)
					shots += 1
		if shots > 0:
			break
	_check(shots == 0, "archer fired %d shot(s) through a solid wall (wall x=%.0f..%.0f)" % [
		shots, wall.position.x, wall.end.x])
	_note("wall=%s blocked_shots=%d" % [str(wall), shots])
	archer.queue_free()
	for child in _world.get_children():
		if child is Projectile:
			child.queue_free()
	await _frames(4)

	# The other half of the same bug: with a clear lane the arrow has to land.
	# It never did - Projectile disables its own body detection.
	_park_player(Vector2(wall.position.x - 400.0, _ledge_y() - 40.0))
	var shooter := _spawn("archer", Vector2(wall.position.x - 150.0, _ledge_y() - 44.0))
	var dealt := 0.0
	for i in 300:
		var before := _player.hp
		await get_tree().physics_frame
		dealt += maxf(0.0, before - _player.hp)
		# Keep the player alive: a single arrow would otherwise end the probe.
		_player.hp = minf(100000.0, _player.hp + 200.0)
		if dealt > 0.0:
			break
	_check(dealt > 0.0, "an archer with a clear lane never damaged the player (its arrows pass through)")
	_note("clear-lane archer damage=%.0f" % dealt)
	shooter.queue_free()
	for child in _world.get_children():
		if child is Projectile:
			child.queue_free()
	await _frames(2)


# --- 6. cells ---------------------------------------------------------------

## A body killed inside a wall must not drop its cell inside the wall.
func _probe_cells() -> void:
	print("\n--- 6. CELL DROPS ---")
	var wall: Rect2 = Rect2()
	var found := false
	for entry in _rects:
		var r: Rect2 = entry["rect"]
		if not bool(entry["oneway"]) and r.size.y > 120.0 and r.size.x < 140.0:
			wall = r
			found = true
			break
	if not _check(found, "no wall found to kill an enemy inside"):
		return
	_park_player(Vector2(wall.position.x - 300.0, _ledge_y() - 40.0))
	var enemy := _spawn("grunt", wall.get_center())
	await _frames(2)
	enemy.take_hit({"damage": 999.0, "knockback": 0.0, "source_pos": enemy.global_position})
	await _frames(30)
	var cells: Array = []
	for child in _world.get_children():
		if child is CellPickup:
			cells.append(child)
	_check(not cells.is_empty(), "a killed body dropped no cell")
	var buried := 0
	for cell in cells:
		if _inside_solid(cell.global_position):
			buried += 1
			print("    cell at %s is inside stone" % str(cell.global_position.round()))
	_check(buried == 0, "%d cell(s) spawned inside geometry and can never be collected" % buried)
	_note("cells=%d buried=%d" % [cells.size(), buried])
	for cell in cells:
		cell.queue_free()
	await _frames(2)


# --- 7. every kind ----------------------------------------------------------

func _probe_all_kinds() -> void:
	print("\n--- 7. EVERY KIND CONFIGURES AND SPAWNS ---")
	var ledge_y := _surface_below(_data["start"])
	_park_player(Vector2(_data["start"].x - 400.0, ledge_y - 40.0))
	for id in Data.enemies.keys():
		var cfg: Dictionary = Data.enemies[id]
		var enemy := ENEMY_SCENE.instantiate() as Enemy
		enemy.configure(str(id), cfg, 1.0)
		enemy.position = Vector2(_data["start"].x + 260.0, ledge_y - 60.0)
		_world.add_child(enemy)
		await _frames(20)
		var ok := true
		ok = _check(enemy.max_hp > 0.0, "%s: hp is %.1f" % [id, enemy.max_hp]) and ok
		ok = _check(enemy.get_node_or_null("BodyShape") != null, "%s: no collision body" % id) and ok
		ok = _check(enemy.visual != null, "%s: no visual" % id) and ok
		ok = _check(enemy.hitbox != null, "%s: no hitbox" % id) and ok
		for key in ["hp", "speed", "damage", "attack_range", "windup", "active", "recovery", "cooldown", "cells", "body_radius", "body_height"]:
			ok = _check(cfg.has(key), "%s: data/enemies.json is missing `%s`" % [id, key]) and ok
		print("  %-9s %-5s hp=%.0f dmg=%.0f" % [id, "PASS" if ok else "FAIL", enemy.max_hp, float(cfg.get("damage", 0.0))])
		enemy.queue_free()
		await _frames(2)


## Configured and spawned is not the same as working. The spitter has to put a
## pool on the floor; the leaper has to leave the ground and slam.
func _probe_new_kinds() -> void:
	print("
--- 7b. SPITTER / LEAPER BEHAVIOUR ---")
	var ledge := _ledge_y()

	_park_player(Vector2(_data["start"].x + 700.0, ledge - 40.0))
	var spitter := _spawn("spitter", Vector2(_data["start"].x + 960.0, ledge - 44.0))
	var pools := 0
	var hurt := 0.0
	for i in 420:
		var before := _player.hp
		await get_tree().physics_frame
		hurt += maxf(0.0, before - _player.hp)
		# Keep the player alive so the fight continues past the first hit.
		_player.hp = minf(100000.0, _player.hp + 200.0)
		for child in _world.get_children():
			if child.name == "GlobPool" and not child.has_meta("counted"):
				child.set_meta("counted", true)
				pools += 1
		if pools > 0 and hurt > 0.0:
			break
	_check(pools > 0, "the spitter never left a pool on the floor")
	_check(hurt > 0.0, "the spitter's glob/pool never damaged a standing player")
	_note("spitter pools=%d damage=%.0f" % [pools, hurt])
	spitter.queue_free()
	for child in _world.get_children():
		if child.name == "GlobPool" or child is Projectile:
			child.queue_free()
	await _frames(4)

	# Leaper: the player stands still, which is what the hop is aimed at.
	_park_player(Vector2(_data["start"].x + 700.0, ledge - 40.0))
	var leaper := _spawn("leaper", Vector2(_data["start"].x + 860.0, ledge - 40.0))
	var start_y: float = leaper.global_position.y
	var apex: float = start_y
	var hit := 0.0
	for i in 360:
		var before := _player.hp
		await get_tree().physics_frame
		apex = minf(apex, leaper.global_position.y)
		hit += maxf(0.0, before - _player.hp)
		_player.hp = minf(100000.0, _player.hp + 200.0)
		if hit > 0.0 and leaper.global_position.y > apex + 40.0:
			break
	_check(apex < start_y - 20.0, "the leaper never left the ground (apex y=%.0f, start %.0f)" % [apex, start_y])
	_check(hit > 0.0, "the leaper's slam never landed on a standing player")
	_note("leaper apex=%.0f px above its start, slam damage=%.0f" % [start_y - apex, hit])
	leaper.queue_free()
	await _frames(4)


# --- 8. budget --------------------------------------------------------------

func _probe_budget() -> void:
	print("\n--- 8. NODE BUDGET (13 bodies, all killed) ---")
	await _frames(4)
	var before := get_tree().get_node_count()
	var bodies: Array = []
	var ledge_y := _surface_below(_data["start"])
	_park_player(Vector2(_data["start"].x - 600.0, ledge_y - 40.0))
	for i in 13:
		bodies.append(_spawn("grunt", Vector2(_data["start"].x + 200.0 + float(i) * 26.0, ledge_y - 40.0)))
	await _frames(60)
	var peak := get_tree().get_node_count()
	for body in bodies:
		body.take_hit({"damage": 999.0, "knockback": 0.0, "source_pos": body.global_position})
	await _frames(120)
	# Cells live 14 s on purpose (they are loot); everything else must be gone.
	for child in _world.get_children():
		if child is CellPickup:
			child.queue_free()
	await _frames(120)
	var after := get_tree().get_node_count()
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(after <= before + 2, "node count grew from %d to %d after 13 bodies died" % [before, after])
	_check(orphans == 0, "%d orphan nodes left behind" % orphans)
	_note("nodes before=%d peak=%d after=%d orphans=%d" % [before, peak, after, orphans])


func _finish() -> void:
	if _failures == 0:
		print("\nAUDIT V2 OK")
	else:
		print("\nAUDIT V2 FAILED (%d)" % _failures)
	await _frames(10)
	get_tree().quit(0 if _failures == 0 else 1)
