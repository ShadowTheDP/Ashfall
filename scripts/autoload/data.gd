extends Node
## Loads data-driven content tables once and shares them with gameplay code.

const ROUTE_GRAPH := preload("res://scripts/systems/route_graph.gd")
const BIOME_GENERATOR := preload("res://scripts/world/biome_gen.gd")
## Traditional Chinese is the first-use language; en is the fallback for rows
## without zh_TW text. Both locales are registered in project.godot
## (internationalization/locale/translations) and imported by Godot's native
## CSV importer; the step-2 settings page owns switching after boot.
const DEFAULT_LOCALE := "zh_TW"

var weapons: Dictionary = {}
var gear: Dictionary = {}
var passage: Dictionary = {}
var enemies: Dictionary = {}
var rewards: Dictionary = {}
var characters: Dictionary = {}
var armor: Dictionary = {}
var upgrades: Dictionary = {}
var floors: Dictionary = {}
var route_graph: Dictionary = {}
var route_profiles: Dictionary = {}
var biomes: Dictionary = {}
var room_modules: Dictionary = {}
var traversal: Dictionary = {}
var generation_spatial: Dictionary = {}
## Hand-authored room chunks (data/rooms.json), keyed by room kind. The
## generator picks one per room; see level_gen._build_room().
var rooms: Dictionary = {}
var skill_nodes: Dictionary = {}


func _ready() -> void:
	TranslationServer.set_locale(DEFAULT_LOCALE)
	load_all()


func load_all() -> void:
	weapons = _read_json("res://data/weapons.json")
	gear = _read_json("res://data/gear.json")
	assert(valid_gear(gear), "Invalid data/gear.json")
	passage = _read_json("res://data/passage.json")
	assert(valid_passage(passage), "Invalid data/passage.json")
	enemies = _read_json("res://data/enemies.json")
	assert(valid_route_bosses(enemies), "Invalid route boss configuration")
	rewards = _read_json("res://data/rewards.json")
	characters = _read_json("res://data/characters.json")
	armor = _read_json("res://data/armor.json")
	upgrades = _read_json("res://data/upgrades.json")
	floors = _read_json("res://data/floors.json")
	route_graph = _read_json("res://data/route_graph.json")
	route_profiles = _read_json("res://data/route_profiles.json")
	biomes = _read_json("res://data/biomes.json")
	room_modules = _read_json("res://data/room_modules.json")
	traversal = _read_json("res://data/traversal.json")
	generation_spatial = _read_json("res://data/generation_spatial_v2.json")
	for error in BIOME_GENERATOR.validate_spatial(generation_spatial, biomes, room_modules):
		push_error("Data: invalid spatial generation: " + error)
	for error in BIOME_GENERATOR.validate(biomes, room_modules):
		push_error("Data: invalid biome modules: " + error)
	var route_errors: PackedStringArray = ROUTE_GRAPH.validate(route_graph)
	for error in route_errors:
		push_error("Data: invalid route graph: " + error)
	rooms = _read_json("res://data/rooms.json")
	skill_nodes = _read_json("res://data/skill_nodes.json")


func valid_route_bosses(table: Dictionary) -> bool:
	for id: String in RouteBoss.KINDS:
		if not table.get(id) is Dictionary:
			return false
		var cfg: Dictionary = table[id]
		for key: String in RouteBoss.required_fields(id):
			if typeof(cfg.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(cfg[key])) or float(cfg[key]) <= 0.0:
				return false
		if not cfg.get("boss", false):
			return false
	return float(table.bridge_sentinel.wave_life) <= RouteBoss.MAX_HAZARD_TTL and float(table.clock_warden.lane_life) <= RouteBoss.MAX_HAZARD_TTL and float(table.clock_warden.lane_upper_height) > float(table.clock_warden.lane_lower_height) and float(table.silent_regent.column_delay) + float(table.silent_regent.column_active) <= RouteBoss.MAX_HAZARD_TTL and float(table.silent_regent.column_spacing) > float(table.silent_regent.column_width)


func valid_gear(table: Dictionary) -> bool:
	for key in ["items", "qualities", "affixes", "scrolls", "statuses", "economy", "loot_pools"]:
		if not table.get(key) is Dictionary or table[key].is_empty():
			return false
	if not table.get("start") is Array or table["start"].size() != 5 or not table.get("placements") is Array or float(table.get("base_hp", 0)) <= 0:
		return false
	for axis in ["brutality", "tactics", "survival"]:
		if not table.scrolls.get(axis) is Dictionary or float(table.scrolls[axis].get("hp", 0)) <= 0:
			return false
	for id in table["items"]:
		if not table.items[id] is Dictionary:
			return false
		var cfg: Dictionary = table.items[id]
		if cfg.get("kind") not in ["weapon", "skill", "amulet"] or float(cfg.get("price", -1)) < 0 or not cfg.get("name") is String:
			return false
		if cfg.kind == "amulet":
			if float(cfg.get("hp", 0)) <= 0:
				return false
			continue
		if not table.scrolls.has(cfg.get("attribute", "")):
			return false
		if cfg.get("action") == "melee":
			if cfg.kind != "weapon" or not weapons.has(cfg.get("weapon", "")):
				return false
		else:
			if cfg.get("action") not in (["shield"] if cfg.kind == "weapon" else ["kunai", "aegis"]):
				return false
			for key in ["damage", "cooldown"]:
				if float(cfg.get(key, 0)) <= 0:
					return false
			if int(cfg.get("charges", 1)) < 1:
				return false
			for key in (["speed"] if cfg.action == "kunai" else ["duration", "radius"]):
				if float(cfg.get(key, 0)) <= 0:
					return false
	for i in 5:
		var cfg: Dictionary = table.items.get(table.start[i], {})
		if cfg.get("kind") != ["weapon", "weapon", "skill", "skill", "amulet"][i] or not cfg.get("starter", false):
			return false
	for cfg in table.qualities.values():
		if not cfg is Dictionary or float(cfg.get("power", 0)) <= 0 or float(cfg.get("price", 0)) <= 0:
			return false
	for cfg in table.affixes.values():
		if not cfg is Dictionary or float(cfg.get("cooldown", 1)) <= 0 or (cfg.has("status") and not table.statuses.has(cfg.status)):
			return false
	for cfg in table.statuses.values():
		if not cfg is Dictionary:
			return false
		for key in ["damage", "interval", "duration"]:
			if float(cfg.get(key, 0)) <= 0:
				return false
	for pool in table.loot_pools.values():
		if not pool is Array or pool.is_empty():
			return false
		for row in pool:
			if not row is Dictionary or not table.items.has(row.get("id", "")) or not table.qualities.has(row.get("quality", "")) or not table.affixes.has(row.get("affix", "")):
				return false
	for row in table.placements:
		if not row is Dictionary or row.get("kind") not in ["gold", "food", "gear", "chest", "shop", "scroll"] or not row.get("offset") is Array or row.offset.size() != 2 or not row.get("room") is String:
			return false
		if row.kind in ["gear", "chest", "shop"] and not table.loot_pools.has(row.get("pool", "")):
			return false
	return table.qualities.has("plain") and table.affixes.has("none") and float(table.economy.get("recycle_fraction", -1)) >= 0 and float(table.economy.recycle_fraction) < 1 and float(table.economy.get("food_heal", 0)) > 0 and float(table.economy.get("kill_gold", -1)) >= 0


func valid_passage(table: Dictionary) -> bool:
	for key in ["blueprints", "mutations", "mutation_reset", "craft", "forge", "challenges"]:
		if not table.get(key) is Dictionary or table[key].is_empty():
			return false
	if int(table.get("investment_step", 0)) <= 0 or int(table.mutation_reset.get("capacity", 0)) != 3:
		return false
	for cfg in table.blueprints.values():
		if not cfg is Dictionary or int(cfg.get("cost", 0)) <= 0 or not cfg.get("name") is String:
			return false
		if cfg.get("kind") not in ["gear", "mutation"] or not (gear.items if cfg.kind == "gear" else table.mutations).has(cfg.get("target", "")):
			return false
		if not cfg.get("at") is Array or cfg.at.size() != 2 or not cfg.get("biome") is String or not cfg.get("room") is String:
			return false
	for cfg in table.mutations.values():
		if not cfg is Dictionary or not cfg.get("name") is String or not cfg.get("text") is String:
			return false
		for key in cfg:
			if key not in ["name", "text", "starter", "damage", "damage_taken", "cooldown", "heal_kill"]:
				return false
		if float(cfg.get("damage_taken", 0)) <= -1 or float(cfg.get("cooldown", 0)) <= -1 or float(cfg.get("heal_kill", 0)) < 0:
			return false
	for cfg in [table.mutation_reset, table.craft]:
		for key in cfg:
			if key not in ["qualities", "affixes"] and int(cfg[key]) <= 0:
				return false
	# RunBuild reads these members directly, so an absent key would pass the loop
	# above and then fail at runtime in the Collector instead of at load time.
	for key in ["cost", "step", "capacity"]:
		if int(table.mutation_reset.get(key, 0)) <= 0:
			return false
	for key in ["upgrade_cost", "reforge_cost", "reforge_step"]:
		if int(table.craft.get(key, 0)) <= 0:
			return false
	for key in ["qualities", "affixes"]:
		if not table.craft.get(key) is Array or table.craft[key].is_empty():
			return false
		for id in table.craft[key]:
			if not gear[key].has(id):
				return false
	if int(table.forge.get("cost", 0)) <= 0 or not gear.qualities.has(table.forge.get("quality", "")) or not table.forge.get("thresholds") is Array:
		return false
	var previous := 0
	for row in table.forge.thresholds:
		if not row is Dictionary or int(row.get("cells", 0)) <= previous or int(row.cells) > int(table.forge.cost) or float(row.get("chance", -1)) < 0 or float(row.chance) > 1:
			return false
		previous = int(row.cells)
	for key in ["ordinary_challenges", "boss_challenges"]:
		if not table.get(key) is Array or table[key].is_empty():
			return false
		for id in table[key]:
			if id not in ["time", "streak", "flawless"] or not table.challenges.has(id):
				return false
	for cfg in table.challenges.values():
		if not cfg is Dictionary or not cfg.get("name") is String or not cfg.get("text") is String or int(cfg.get("gold", -1)) < 0 or int(cfg.get("cells", -1)) < 0:
			return false
	return float(table.challenges.get("time", {}).get("seconds", 0)) > 0 and int(table.challenges.get("streak", {}).get("kills", 0)) > 0


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Data: cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Data: %s is not a JSON object" % path)
		return {}
	return parsed
