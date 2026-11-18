class_name RunBuild
extends RefCounted
## Only the run owns gear identity, charges, Scrolls and money. No Profile writes.
const SLOT_KINDS := ["weapon", "weapon", "skill", "skill", "amulet"]
var slots: Array[Dictionary] = [{}, {}, {}, {}, {}]
var attributes := {"brutality":0, "tactics":0, "survival":0}
var mutations: Array[String] = []
var mutation_capacity := 0
var mutation_resets := 0
var gold := 0
var _serial := 0
var _items: Dictionary = {}

func create(id: String, quality := "plain", affix := "none") -> Dictionary:
	var cfg: Dictionary = Data.gear["items"].get(id, {})
	if cfg.is_empty() or not Data.gear["qualities"].has(quality) or not Data.gear["affixes"].has(affix):
		return {}
	_serial += 1
	var item := {"uid":_serial, "id":id, "quality":quality, "affix":affix,
		"charges":int(cfg.get("charges", 1)), "cooldown":0.0}
	_items[_serial] = item
	return item

func start(selected: String, unlocked: Array[String]) -> void:
	if not _items.is_empty():
		return
	var ids: Array = Data.gear["start"].duplicate()
	if unlocked.has(selected) and Data.gear["items"].has(selected) and Data.gear["items"][selected].get("kind") == "weapon":
		ids[0] = selected
	for i in ids.size():
		slots[i] = create(str(ids[i]))

func owns(item: Dictionary) -> bool:
	return not item.is_empty() and _items.has(item.get("uid", -1)) and is_same(_items[item["uid"]], item)

func equip(slot: int, item: Dictionary) -> bool:
	if slot < 0 or slot >= slots.size() or not owns(item) or definition(item).get("kind") != SLOT_KINDS[slot]:
		return false
	for i in slots.size():
		if i != slot and is_same(slots[i], item):
			return false
	slots[slot] = item
	return true

func definition(item: Dictionary) -> Dictionary:
	return Data.gear["items"].get(str(item.get("id", "")), {})

func power(item: Dictionary) -> float:
	return float(Data.gear["qualities"][item["quality"]]["power"]) + float(Data.gear["affixes"][item["affix"]].get("power", 0))

func cooldown(item: Dictionary) -> float:
	return float(definition(item).get("cooldown", 0)) * float(Data.gear["affixes"][item["affix"]].get("cooldown", 1)) * (1.0 + effect("cooldown") if definition(item).get("kind") == "skill" else 1.0)

func level(item: Dictionary) -> int:
	return int(attributes.get(str(definition(item).get("attribute", "")), 0))

func price(item: Dictionary) -> int:
	return int(ceil(float(definition(item)["price"]) * float(Data.gear["qualities"][item["quality"]]["price"])))

func recycle_value(item: Dictionary) -> int:
	return int(floor(price(item) * float(Data.gear["economy"]["recycle_fraction"])))

func retire(item: Dictionary) -> void:
	_items.erase(item.get("uid", -1))

func use(slot: int) -> bool:
	if slot < 0 or slot >= 4 or slots[slot].is_empty():
		return false
	var item := slots[slot]
	if int(item["charges"]) <= 0:
		return false
	item["charges"] -= 1
	if float(item["cooldown"]) <= 0:
		item["cooldown"] = cooldown(item)
	return true

func tick(delta: float) -> void:
	for item: Dictionary in _items.values():
		var cap := int(definition(item).get("charges", 1))
		if int(item["charges"]) >= cap:
			continue
		item["cooldown"] = maxf(0, float(item["cooldown"]) - delta)
		if float(item["cooldown"]) <= 0:
			item["charges"] += 1
			if int(item["charges"]) < cap:
				item["cooldown"] = cooldown(item)

func health() -> float:
	var value := float(Data.gear["base_hp"])
	for id: String in attributes:
		value *= 1.0 + float(attributes[id]) * float(Data.gear["scrolls"][id]["hp"])
	return value + float(definition(slots[4]).get("hp", 0)) * power(slots[4])

func effect(key: String) -> float:
	var value := 0.0
	for id in mutations:
		value += float(Data.passage.mutations.get(id, {}).get(key, 0))
	return value

func reset_cost() -> int:
	return int(Data.passage.mutation_reset.cost) + mutation_resets * int(Data.passage.mutation_reset.step)

func reset_mutations() -> bool:
	if mutations.is_empty() or gold < reset_cost():
		return false
	gold -= reset_cost()
	mutations.clear()
	mutation_resets += 1
	return true

func craft_cost(slot: int, reforge: bool) -> int:
	if slot < 0 or slot >= slots.size() or not owns(slots[slot]):
		return -1
	var item := slots[slot]
	var cfg: Dictionary = Data.passage.craft
	if reforge:
		return int(cfg.reforge_cost) + int(item.get("reforges", 0)) * int(cfg.reforge_step)
	return int(cfg.upgrade_cost) if cfg.qualities.find(item.quality) < cfg.qualities.size() - 1 else -1

func craft(slot: int, reforge: bool) -> bool:
	var cost := craft_cost(slot, reforge)
	if cost < 0 or gold < cost:
		return false
	var item := slots[slot]
	var cfg: Dictionary = Data.passage.craft
	gold -= cost
	if reforge:
		item.affix = cfg.affixes[(cfg.affixes.find(item.affix) + 1) % cfg.affixes.size()]
		item["reforges"] = int(item.get("reforges", 0)) + 1
	else:
		item.quality = cfg.qualities[cfg.qualities.find(item.quality) + 1]
	return true

func checkpoint() -> Dictionary:
	return {"slots":slots.duplicate(true), "attributes":attributes.duplicate(),
		"mutations":mutations.duplicate(), "mutation_capacity":mutation_capacity,
		"mutation_resets":mutation_resets, "gold":gold, "serial":_serial}


static func _count(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0 and float(value) == floorf(float(value)) and float(value) <= 4294967295.0


static func from_checkpoint(data: Dictionary) -> RunBuild:
	if typeof(data.get("slots")) != TYPE_ARRAY or data.slots.size() != 5 or typeof(data.get("attributes")) != TYPE_DICTIONARY or typeof(data.get("mutations")) != TYPE_ARRAY:
		return null
	for field in ["mutation_capacity", "mutation_resets", "gold", "serial"]:
		if not _count(data.get(field)): return null
	if int(data.mutation_capacity) > int(Data.passage.mutation_reset.capacity) or data.mutations.size() > int(data.mutation_capacity): return null
	var build := RunBuild.new()
	for axis: String in build.attributes:
		if not _count(data.attributes.get(axis)): return null
		build.attributes[axis] = int(data.attributes[axis])
	for id: Variant in data.mutations:
		if typeof(id) != TYPE_STRING or not Data.passage.mutations.has(id) or build.mutations.has(id): return null
		build.mutations.append(id)
	for i in 5:
		if typeof(data.slots[i]) != TYPE_DICTIONARY: return null
		var item: Dictionary = data.slots[i].duplicate(true)
		var cfg: Dictionary = Data.gear.items.get(str(item.get("id", "")), {})
		if cfg.get("kind") != SLOT_KINDS[i] or not Data.gear.qualities.has(str(item.get("quality", ""))) or not Data.gear.affixes.has(str(item.get("affix", ""))): return null
		if not _count(item.get("uid")) or not _count(item.get("charges")) or not _count(item.get("reforges", 0)): return null
		if typeof(item.get("cooldown")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(item.cooldown)) or float(item.cooldown) < 0: return null
		var uid := int(item.uid)
		if uid < 1 or build._items.has(uid) or int(item.charges) > int(cfg.get("charges", 1)): return null
		item.uid = uid
		item.charges = int(item.charges)
		item.cooldown = float(item.cooldown)
		build._items[uid] = item
		build.slots[i] = item
		build._serial = maxi(build._serial, uid)
	build._serial = maxi(build._serial, int(data.serial))
	build.mutation_capacity = int(data.mutation_capacity)
	build.mutation_resets = int(data.mutation_resets)
	build.gold = int(data.gold)
	return build


func display_stats(item: Dictionary) -> Dictionary:
	if item.is_empty():
		return {"label":"EMPTY", "value":0.0, "cooldown":0.0, "capacity":0}
	var cfg := definition(item)
	if cfg.kind == "amulet":
		return {"label":"MAX HP", "value":float(cfg.get("hp", 0)) * power(item), "cooldown":0.0, "capacity":0}
	var base := float(Data.weapons[cfg.weapon].combo[0].damage) if cfg.action == "melee" else float(cfg.damage)
	return {"label":"FIRST HIT" if cfg.action == "melee" else ("COUNTER" if cfg.action in ["shield", "aegis"] else "HIT"),
		"value":Damage.compute(base * power(item) * (1.0 + effect("damage")), level(item), false, 1),
		"cooldown":cooldown(item), "capacity":int(cfg.get("charges", 1))}


func _display_projection() -> RunBuild:
	var next := RunBuild.new()
	next.slots = slots.duplicate()
	next.attributes = attributes.duplicate()
	next.mutations = mutations.duplicate()
	return next


func replacement_projection(slot: int, item: Dictionary, current_hp: float) -> Dictionary:
	var next := _display_projection()
	next.slots[slot] = item
	return {"max_after":next.health(), "hp_after":minf(current_hp, next.health())}


func scroll_projection(axis: String, current_hp: float) -> Dictionary:
	if not attributes.has(axis):
		return {}
	# Read-only projection reuses the real health/damage calculators; no live mutation.
	var next := _display_projection()
	next.attributes[axis] += 1
	var affected: Array[Dictionary] = []
	for i in slots.size():
		if definition(slots[i]).get("attribute", "") == axis:
			affected.append({"slot":i, "before":display_stats(slots[i]), "after":next.display_stats(slots[i])})
	return {"axis":axis, "before":attributes[axis], "after":next.attributes[axis],
		"max_before":health(), "max_after":next.health(), "hp_after":minf(current_hp, next.health()), "affected":affected}


func craft_projection(slot: int, reforge: bool) -> Dictionary:
	var cost := craft_cost(slot, reforge)
	if cost < 0:
		return {}
	# A validated deep copy keeps preview crafting away from canonical live items.
	var next := RunBuild.from_checkpoint(checkpoint())
	next.gold = maxi(gold, cost)
	if not next.craft(slot, reforge):
		return {}
	return {"item":next.slots[slot], "before":display_stats(slots[slot]), "after":next.display_stats(next.slots[slot]), "cost":cost}
