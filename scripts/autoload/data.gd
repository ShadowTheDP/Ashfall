extends Node
## Loads data-driven content tables once and shares them with gameplay code.

var weapons: Dictionary = {}
var enemies: Dictionary = {}
var rewards: Dictionary = {}
var characters: Dictionary = {}
var armor: Dictionary = {}
var upgrades: Dictionary = {}
var floors: Dictionary = {}
var skill_nodes: Dictionary = {}
var loaded := false


func _ready() -> void:
	load_all()


func load_all() -> void:
	weapons = _read_json("res://data/weapons.json")
	enemies = _read_json("res://data/enemies.json")
	rewards = _read_json("res://data/rewards.json")
	characters = _read_json("res://data/characters.json")
	armor = _read_json("res://data/armor.json")
	upgrades = _read_json("res://data/upgrades.json")
	floors = _read_json("res://data/floors.json")
	skill_nodes = _read_json("res://data/skill_nodes.json")
	loaded = not weapons.is_empty() and not enemies.is_empty()


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
