extends Node
## Persistent profile: banked currency, permanent upgrades, skill nodes,
## archives and unlocks. Saved to `user://ashfall_profile.json`.
##
## This is the ONLY place that reads or writes the save file. Gameplay reads
## permanent progression exclusively through `Profile.bonus()` so a single
## upgrade id can feed several stats without touching combat code.

const SAVE_PATH := "user://ashfall_profile.json"
const VERSION := 1

var cells := 0
var souls := 0
var upgrades: Dictionary = {}
var skill_nodes: Array[String] = []
var seen_enemies: Array[String] = []
var seen_weapons: Array[String] = []
var seen_armor: Array[String] = []
var unlocked_characters: Array[String] = []
var unlocked_weapons: Array[String] = []
var unlocked_armor: Array[String] = []
var selected_character := "square"
var selected_weapon := "rusty_sword"
var selected_armor := "none"
var best_floor := 0
var total_kills := 0
var deaths := 0
var runs := 0
var victories := 0
var _loaded := false


func _ready() -> void:
	load_profile()


# ---------------------------------------------------------------- save / load

## Idempotent by default; `force` re-reads the file (tests, future "reload save").
func load_profile(force: bool = false) -> void:
	if _loaded and not force:
		return
	_loaded = true
	if not FileAccess.file_exists(SAVE_PATH):
		_apply_defaults()
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_apply_defaults()
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_apply_defaults()
		return
	var d: Dictionary = parsed
	cells = int(d.get("cells", 0))
	souls = int(d.get("souls", 0))
	upgrades = _to_dict(d.get("upgrades", {}))
	skill_nodes = _to_strings(d.get("skill_nodes", []))
	seen_enemies = _to_strings(d.get("seen_enemies", []))
	seen_weapons = _to_strings(d.get("seen_weapons", []))
	seen_armor = _to_strings(d.get("seen_armor", []))
	unlocked_characters = _to_strings(d.get("unlocked_characters", []))
	unlocked_weapons = _to_strings(d.get("unlocked_weapons", []))
	unlocked_armor = _to_strings(d.get("unlocked_armor", []))
	selected_character = str(d.get("selected_character", "square"))
	selected_weapon = str(d.get("selected_weapon", "rusty_sword"))
	selected_armor = str(d.get("selected_armor", "none"))
	best_floor = int(d.get("best_floor", 0))
	total_kills = int(d.get("total_kills", 0))
	deaths = int(d.get("deaths", 0))
	runs = int(d.get("runs", 0))
	victories = int(d.get("victories", 0))
	_sanitize()


func _apply_defaults() -> void:
	cells = 0
	souls = 0
	upgrades.clear()
	skill_nodes.clear()
	seen_enemies.clear()
	seen_weapons.clear()
	seen_armor.clear()
	unlocked_characters = ["square"]
	unlocked_weapons = ["rusty_sword"]
	unlocked_armor = ["none"]
	selected_character = "square"
	selected_weapon = "rusty_sword"
	selected_armor = "none"
	best_floor = 0
	total_kills = 0
	deaths = 0
	runs = 0
	victories = 0


func _sanitize() -> void:
	# A save from an older build must never leave the player with a loadout
	# that no longer exists.
	if unlocked_characters.is_empty():
		unlocked_characters = ["square"]
	if unlocked_weapons.is_empty():
		unlocked_weapons = ["rusty_sword"]
	if unlocked_armor.is_empty():
		unlocked_armor = ["none"]
	if not unlocked_characters.has(selected_character):
		selected_character = unlocked_characters[0]
	if not unlocked_weapons.has(selected_weapon):
		selected_weapon = unlocked_weapons[0]
	if not unlocked_armor.has(selected_armor):
		selected_armor = unlocked_armor[0]


func save() -> void:
	var payload := {
		"version": VERSION,
		"cells": cells,
		"souls": souls,
		"upgrades": upgrades,
		"skill_nodes": skill_nodes,
		"seen_enemies": seen_enemies,
		"seen_weapons": seen_weapons,
		"seen_armor": seen_armor,
		"unlocked_characters": unlocked_characters,
		"unlocked_weapons": unlocked_weapons,
		"unlocked_armor": unlocked_armor,
		"selected_character": selected_character,
		"selected_weapon": selected_weapon,
		"selected_armor": selected_armor,
		"best_floor": best_floor,
		"total_kills": total_kills,
		"deaths": deaths,
		"runs": runs,
		"victories": victories,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Profile: cannot write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()


func reset_profile() -> void:
	_apply_defaults()
	save()


# ------------------------------------------------------------------ currency

func bank(amount: int) -> void:
	if amount <= 0:
		return
	cells += amount
	save()


func spend(amount: int) -> bool:
	if amount <= 0:
		return true
	if cells < amount:
		return false
	cells -= amount
	save()
	return true


func add_souls(amount: int) -> void:
	souls = maxi(0, souls + amount)
	save()


# ------------------------------------------------------------------ upgrades

func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))


func upgrade_max(id: String) -> int:
	var cfg: Dictionary = Data.upgrades.get(id, {})
	return int(cfg.get("max", 1))


func upgrade_cost(id: String) -> int:
	var cfg: Dictionary = Data.upgrades.get(id, {})
	if cfg.is_empty():
		return -1
	var level := upgrade_level(id)
	if level >= int(cfg.get("max", 1)):
		return -1
	return int(cfg.get("cost", 30)) + int(cfg.get("cost_step", 25)) * level


func buy_upgrade(id: String) -> bool:
	var cost := upgrade_cost(id)
	if cost < 0:
		return false
	if not spend(cost):
		return false
	upgrades[id] = upgrade_level(id) + 1
	save()
	return true


func add_upgrade(id: String, levels: int = 1) -> void:
	upgrades[id] = clampi(upgrade_level(id) + levels, 0, upgrade_max(id))
	save()


## Aggregated permanent bonus for one gameplay stat.
## stats: hp, damage, speed, knives, iframe, crit, cells
func bonus(stat: String) -> float:
	var total := 0.0
	for id in upgrades.keys():
		var cfg: Dictionary = Data.upgrades.get(id, {})
		if cfg.is_empty():
			continue
		if str(cfg.get("stat", "")) != stat:
			continue
		total += float(cfg.get("per_level", 0)) * float(upgrade_level(id))
	for node_id in skill_nodes:
		var node: Dictionary = Data.skill_nodes.get(node_id, {})
		if node.is_empty():
			continue
		if str(node.get("stat", "")) != stat:
			continue
		total += float(node.get("per_level", 0))
	return total


# -------------------------------------------------------------------- skills

func has_skill(id: String) -> bool:
	return skill_nodes.has(id)


func skill_available(id: String) -> bool:
	if has_skill(id):
		return false
	var node: Dictionary = Data.skill_nodes.get(id, {})
	if node.is_empty():
		return false
	for parent_id in node.get("requires", []):
		if not has_skill(str(parent_id)):
			return false
	return true


func buy_skill(id: String) -> bool:
	if not skill_available(id):
		return false
	var node: Dictionary = Data.skill_nodes.get(id, {})
	if not spend(int(node.get("cost", 40))):
		return false
	skill_nodes.append(id)
	save()
	return true


func add_skill(id: String) -> bool:
	if has_skill(id):
		return false
	skill_nodes.append(id)
	save()
	return true


# ------------------------------------------------------------------ archives

func see(kind: String, id: String) -> void:
	var list := _archive(kind)
	if id.is_empty() or list.has(id):
		return
	list.append(id)
	save()


func has_seen(kind: String, id: String) -> bool:
	return _archive(kind).has(id)


func _archive(kind: String) -> Array:
	match kind:
		"enemy":
			return seen_enemies
		"weapon":
			return seen_weapons
		"armor":
			return seen_armor
	return seen_enemies


# ------------------------------------------------------------------- unlocks

func is_unlocked(kind: String, id: String) -> bool:
	match kind:
		"character":
			return unlocked_characters.has(id)
		"weapon":
			return unlocked_weapons.has(id)
		"armor":
			return unlocked_armor.has(id)
	return false


func unlock(kind: String, id: String) -> bool:
	var table: Dictionary = _unlock_table(kind)
	if table.is_empty():
		return false
	var cfg: Dictionary = table.get(id, {})
	if cfg.is_empty():
		return false
	if is_unlocked(kind, id):
		return false
	# Weapons carry "unlock_cost"; armour and characters carry "cost".
	var price := int(cfg.get("cost", cfg.get("unlock_cost", 0)))
	if not spend(price):
		return false
	_unlock_list(kind).append(id)
	save()
	return true


func unlock_free(kind: String, id: String) -> void:
	if is_unlocked(kind, id):
		return
	_unlock_list(kind).append(id)
	save()


func _unlock_table(kind: String) -> Dictionary:
	match kind:
		"character":
			return Data.characters
		"weapon":
			return Data.weapons
		"armor":
			return Data.armor
	return {}


func _unlock_list(kind: String) -> Array:
	match kind:
		"character":
			return unlocked_characters
		"weapon":
			return unlocked_weapons
		"armor":
			return unlocked_armor
	return unlocked_characters


func select(kind: String, id: String) -> void:
	if not is_unlocked(kind, id):
		return
	match kind:
		"character":
			selected_character = id
		"weapon":
			selected_weapon = id
		"armor":
			selected_armor = id
	save()


# ------------------------------------------------------------- run bookkeeping

func note_floor_reached(index: int) -> void:
	if index > best_floor:
		best_floor = index
		save()


func note_run(kills: int, died: bool, won: bool) -> void:
	runs += 1
	total_kills += maxi(0, kills)
	if died:
		deaths += 1
	if won:
		victories += 1
	save()


func stats() -> Dictionary:
	return {
		"cells": cells,
		"souls": souls,
		"upgrades": upgrades.duplicate(),
		"skill_nodes": skill_nodes.duplicate(),
		"seen_enemies": seen_enemies.duplicate(),
		"seen_weapons": seen_weapons.duplicate(),
		"seen_armor": seen_armor.duplicate(),
		"best_floor": best_floor,
		"total_kills": total_kills,
		"deaths": deaths,
		"runs": runs,
		"victories": victories,
	}


# ------------------------------------------------------------------- helpers

func _to_strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for item in value:
		out.append(str(item))
	return out


func _to_dict(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var out := {}
	for key in value:
		out[str(key)] = int(value[key])
	return out
