extends Node
## Real Main/biome plus deterministic combat fixtures; never touches live Profile.
var _main: Node
var _p: Player
var _checks := 0
var _fails := 0
var _capture := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Profile.require_test_profile():
		return
	_capture = DisplayServer.get_name() != "headless"
	await _frames(3)
	if not Data.is_node_ready():
		await Data.ready
	if not Interface.is_node_ready():
		await Interface.ready
	if not Sfx.is_node_ready():
		await Sfx.ready
	TranslationServer.set_locale("en")
	_check(TranslationServer.get_locale().begins_with("en"), "English fixture locale before Main scenarios: " + TranslationServer.get_locale())
	_main = $Main
	_check(Data.valid_gear(Data.gear), "gear schema accepted")
	var bad := Data.gear.duplicate(true)
	bad["start"][2] = "rusty_sword"
	_check(not Data.valid_gear(bad), "wrong starter category rejected")
	_test_instances()
	Profile.selected_weapon = "rusty_sword"
	Profile.unlocked_weapons.assign(["rusty_sword"])
	Profile.upgrades = {"vitality":4, "edge":4}
	Profile.skill_nodes.assign(Data.skill_nodes.keys())
	var legacy := Profile.upgrades.duplicate(true)
	_check(_main.start_node("ash_gate"), "enter real first biome")
	await _frames(4)
	_p = _main.player
	var build: RunBuild = Game.build
	_check(build != null and build.slots.size() == 5 and _p.max_hp == 132, "legal five-slot start without legacy HP")
	_presentation_semantics()
	_check(_p.passive_id == "none" and _p.armor_taken == 1 and _p.echo_every == 0, "legacy passive armor and skill tree excluded")
	_check(Game.floor_rewards_left == 0, "route room boons disabled")
	Game.apply_reward("vitality")
	_check(build.attributes.values() == [0, 0, 0], "legacy boon cannot stack on build")
	for i in 5:
		_check(build.definition(build.slots[i])["kind"] == RunBuild.SLOT_KINDS[i], "slot kind %d" % i)
	await _economy()
	await _long_comparison()
	_comparison_contracts()
	await _combat()
	await _modals_and_air_roll()
	await _transition_and_teardown(legacy)
	print("L3 BUILD OK (%d checks)" % _checks if _fails == 0 else "L3 BUILD FAILED (%d/%d)" % [_fails, _checks])
	if _fails > 0:
		get_tree().quit(1)
		return
	_main.hud._set_paused(true)
	await _key(KEY_Q)
	_check(false, "pause Q must quit; falling through means input did not exit")

func _test_instances() -> void:
	var b := RunBuild.new()
	b.start("fractal_edge", ["rusty_sword"])
	_check(b.slots[0]["id"] == "rusty_sword", "locked selection falls back to starter")
	var one := b.slots[2]
	var two := b.create("kunai", "etched", "quick")
	_check(b.equip(3, two) and not b.equip(0, two), "two skill copies legal, wrong category rejected")
	_check(not b.equip(2, two) and not b.equip(2, one.duplicate()) and not b.equip(-1, one) and not b.equip(5, one), "duplicate UID spoof and invalid slots rejected")
	_check(b.create("not_content").is_empty() and b.create("kunai", "fake").is_empty(), "unknown IDs quality rejected")
	_check(b.use(2) and one["charges"] == 1 and two["charges"] == 2, "independent same-content charge state")
	_check(b.use(2) and not b.use(2), "empty charge use fails")
	b.tick(0.25)
	var cd: float = one["cooldown"]
	var spare := b.create("aegis")
	_check(b.equip(2, spare) and b.equip(3, one) and one["cooldown"] == cd and one["charges"] == 0, "moving an instance retains cooldown and charges")
	b.tick(1.3)
	_check(one["charges"] == 1 and two["charges"] == 2, "recharge without refilling unrelated copy")
	_check(b.cooldown(two) < b.cooldown(one) and b.power(two) > b.power(one), "quality and quick affix affect resolved values")
	b.attributes.tactics = 8
	b.mutations.assign(["edge"])
	var state := b.checkpoint()
	var preview := b.scroll_projection("tactics", 10.5)
	_check(b.checkpoint() == state and preview.hp_after == 10.5, "Scroll preview cannot mutate build or heal")
	var before_stats := b.display_stats(two)
	_check(before_stats.value == Damage.compute(12 * b.power(two) * 1.12, 8, false, 1), "display uses current axis, quality, affix, Mutation and real damage rounding")
	b.attributes.tactics += 1
	_check(preview.max_after == b.health() and preview.affected[0].after.value == b.display_stats(b.slots[3]).value, "next point preview equals committed high-level state")
	_check(preview.affected[0].after.value - preview.affected[0].before.value < before_stats.value * 0.12, "marginal next point is not a fixed twelve percent")
	var charm := b.create("ash_charm", "etched", "keen")
	var hp_preview := b.replacement_projection(4, charm, 10.5)
	_check(b.equip(4, charm) and hp_preview.max_after == b.health() and hp_preview.hp_after == 10.5, "replacement max HP preview uses real health without healing")
	var uid: int = b.slots[0]["uid"]
	b.start("rusty_sword", ["rusty_sword"])
	_check(b.slots[0]["uid"] == uid, "starting twice cannot refill or recreate gear")

## The shared presenter is read-only gameplay truth: names once, canonical
## damage/charges, one honest melee crit condition, and no economy mutation.
func _presentation_semantics() -> void:
	var probe := RunBuild.new()
	# The canonical start fills all five slots before any presentation reads
	# health/power; an empty probe cannot answer amulet projections.
	probe.start("rusty_sword", ["rusty_sword"])
	var wallet := probe.gold
	var ids: Array[String] = []
	for id in Data.gear.items:
		var cfg: Dictionary = Data.gear.items[id]
		if str(cfg.get("kind", "")) in RunBuild.SLOT_KINDS:
			ids.append(str(id))
	_check(ids.size() >= 10, "presenter fixture covers the shipped gear set")
	var playstyles := {}
	var melee_conditions := {}
	for id in ids:
		var item := probe.create(id, "etched" if id == "ash_charm" else "plain")
		_check(not item.is_empty(), "presenter fixture creates " + id)
		if item.is_empty():
			continue
		var uid := int(item.uid)
		var charges := int(item.charges)
		var state := probe.checkpoint()
		var info := GearPresentation.describe(probe, item)
		_check(probe.checkpoint() == state, "presenting one item cannot change the build: " + id)
		_check(info.has("name") and info.has("playstyle") and info.has("condition") and info.has("headline") and info.has("details"), "presenter exposes the fixed reading contract: " + id)
		for key in ["name", "playstyle", "condition", "headline"]:
			_check(str(info.get(key, "")).strip_edges().length() > 0, "%s has content: %s" % [key, id])
		var details: Array = info.get("details", [])
		_check(not details.is_empty(), "presenter keeps complete details: " + id)
		var joined := "\n".join(details)
		_check(joined.count(str(info.name)) == 1, "complete details name the object exactly once: " + id)
		_check(not str(info.headline).contains(str(info.name)), "headline never repeats the full name: " + id)
		playstyles[str(info.playstyle)] = true
		var cfg: Dictionary = probe.definition(item)
		var stats: Dictionary = probe.display_stats(item)
		var action := str(cfg.get("action", ""))
		if action == "melee":
			melee_conditions[str(info.condition)] = true
			_check(not joined.contains("CHARGES 1/1") and not joined.contains("RECHARGE "), "melee has no fake charge or recharge: " + id)
			var weapon: Dictionary = Data.weapons.get(str(cfg.get("weapon", "")), {})
			_check(str(info.headline).contains(str(int(stats.value))), "melee headline uses canonical first-hit damage: " + id)
			_check(str(info.headline).contains("%d-hit combo" % (weapon.get("combo", []) as Array).size()), "melee headline uses the canonical combo length: " + id)
			_check(str(info.headline).contains("%.1f" % float(weapon.get("crit_multiplier", 1.0))), "melee headline uses the canonical crit multiplier: " + id)
		elif action == "shield" or action == "aegis":
			_check(joined.contains("CHARGES 1/1"), "guard exposes its real charge: " + id)
			_check(str(info.headline).contains("%.2f" % probe.cooldown(item)), "guard headline uses real recharge: " + id)
			_check(str(info.condition).to_lower().contains("frontal" if action == "shield" else "nearby"), "guard condition describes its actual guard shape: " + id)
		elif action == "kunai":
			_check(joined.contains("CHARGES 2/2"), "Kunai exposes both real charges")
			_check(str(info.headline).contains("%.2f" % probe.cooldown(item)), "Kunai headline uses real recharge")
			_check(str(info.condition).to_lower().contains("auto-target"), "Kunai condition names its real target rule")
		elif str(cfg.get("kind", "")) == "amulet":
			var old_amulet: Dictionary = probe.slots[4]
			var old_bonus := float(probe.display_stats(old_amulet).value)
			var before_hp := probe.health()
			var projection := probe.replacement_projection(4, item, 10.0)
			var expected_delta := float(stats.value) - old_bonus
			_check(not is_zero_approx(expected_delta), "amulet fixture replaces a different max-HP bonus")
			probe.equip(4, item)
			_check(str(info.headline).contains("%.1f" % float(stats.value)), "amulet headline uses the canonical max-HP bonus")
			_check(joined.to_lower().contains("does not heal") or joined.to_lower().contains("not restored"), "amulet honestly says current HP is not restored")
			# replacement_projection returns the projected total only; the live
			# maximum is before_hp and the delta must include the replaced bonus.
			_check(is_equal_approx(projection.max_after - before_hp, expected_delta), "amulet projection delta uses the actual replaced bonus")
			_check(is_equal_approx(probe.health(), projection.max_after), "amulet equip reaches the projected maximum")
			_check(is_equal_approx(projection.hp_after, 10.0), "amulet projection never heals the current HP")
			probe.equip(4, old_amulet)
		_check(int(item.uid) == uid and int(item.charges) == charges, "presenter never changes item identity or charges: " + id)
	_check(playstyles.size() == ids.size(), "each shipped object keeps a distinct playstyle summary")
	_check(melee_conditions.size() == 1, "all six melee weapons share one condition")
	_check(probe.gold == wallet, "presentation never changes the run wallet")
	var enchanted := probe.create("rusty_sword", "etched", "quick")
	var enchanted_info := GearPresentation.describe(probe, enchanted)
	var enchanted_text := "\n".join(enchanted_info.details)
	_check(enchanted_text.contains("Etched"), "presenter reads the item's actual quality")
	_check(enchanted_text.contains(str(Data.gear.affixes["quick"].name)), "presenter reads the item's actual affix")
	_check(not enchanted_text.contains("RECHARGE ×") and not enchanted_text.contains("RECHARGE x"), "inert quick recharge is not claimed for melee")
	var empty := GearPresentation.describe(probe, {})
	_check(str(empty.name) == ContentText.of("UI_STAT_EMPTY", "Empty") and (empty.details as Array).is_empty(), "empty slot is localized with no invented details")
	var missing := GearPresentation.describe(probe, {"id": "not_a_gear", "quality": "plain", "affix": "none", "charges": 1, "cooldown": 0.0})
	_check(str(missing.name) == str(empty.name) and (missing.details as Array).is_empty(), "missing definition falls back to the empty slot without reading absent fields")


func _economy() -> void:
	var found := {}
	for loot: RunLoot in get_tree().get_nodes_in_group("run_loot"):
		found[loot.kind] = loot
	for kind in ["gold", "scroll", "chest", "shop", "food", "gear"]:
		_check(found.has(kind), "real biome places " + kind)
	var gold: RunLoot = found["gold"]
	await _place(gold.global_position)
	await _key(KEY_R)
	_check(Game.build.gold == 40, "R collects world gold")
	var scroll: RunLoot = found["scroll"]
	await _place(scroll.global_position)
	var hp := _p.hp
	var damage_before := Damage.compute(10, _p.attribute_level("tactics"), false, 1)
	await _key(KEY_R)
	_check(_main.build_screen.is_open() and get_tree().paused, "Scroll opens modal")
	await _shot("scroll-entry")
	await _key(KEY_D)
	_check(_main.build_screen._index == 1 and not scroll.consumed, "Scroll focus responds during entry without committing")
	await _shot("scroll-entry-selected")
	await _key(KEY_A)
	var held := InputEventKey.new()
	held.physical_keycode = KEY_ENTER
	held.pressed = true
	held.echo = true
	Input.parse_input_event(held)
	await _frames(1)
	_check(not scroll.consumed and Game.build.attributes.values() == [0, 0, 0], "held Enter cannot consume Scroll through key repeat")
	var released := InputEventKey.new()
	released.physical_keycode = KEY_ENTER
	Input.parse_input_event(released)
	await _shot("scroll")
	var charges: int = Game.build.slots[2]["charges"]
	await _key(KEY_Q)
	await _key(KEY_E)
	_check(Game.build.slots[2]["charges"] == charges, "Q/E do not leak through Scroll picker")
	await _key(KEY_2)
	_check(_main.build_screen.is_open() and Game.build.attributes.tactics == 0 and not scroll.consumed, "2 previews tactics without spending Scroll")
	await _key(KEY_ENTER)
	_check(not _main.build_screen.is_open() and Game.build.attributes.tactics == 1 and Game.build.attributes.survival == 0, "Enter applies selected tactics once, not weapon two")
	await _shot("scroll-confirmed")
	_check(_p.guard_t == 0 and _p.hp == hp and _p.max_hp > 132 and Damage.compute(10, _p.attribute_level("tactics"), false, 1) > damage_before, "Scroll scales matching damage and max HP without free healing")
	var hp_max := _p.max_hp
	_p._apply_loadout()
	_p._apply_loadout()
	_check(_p.max_hp == hp_max, "build projection idempotent")
	var chest: RunLoot = found["chest"]
	await _place(chest.global_position)
	var replacement := chest.item
	var old: Dictionary = Game.build.slots[1]
	var old_value := Game.build.recycle_value(old)
	var coins: int = Game.build.gold
	await _key(KEY_R)
	await _shot("compare")
	await _key(KEY_2)
	await _shot("compare-target-two")
	await _key(KEY_ENTER)
	await _shot("compare-confirmed")
	_check(is_same(Game.build.slots[1], replacement) and not Game.build.owns(old) and Game.build.gold == coins + old_value, "full weapon slots replace selected instance and recycle old once")
	var shop: RunLoot = found["shop"]
	# Show the shop card in the captures, not the tail of the previous chest
	# replacement message.
	Game.announce_t = 0.0
	await _place(shop.global_position)
	await _shot("shop-world-affordable")
	Game.build.gold = 0
	await _shot("shop-world-unaffordable")
	var prepay_target := 2 if Game.build.definition(shop.item)["kind"] == "skill" else 0
	var prepay_credit := Game.build.recycle_value(Game.build.slots[prepay_target])
	Game.build.gold = shop.cost - 1
	_check(prepay_credit > 0 and shop.cost - 1 + prepay_credit >= shop.cost, "fixture credit could fake affordability if applied up front")
	await _key(KEY_R)
	var prepay_slots := Game.build.slots.duplicate()
	await _key(KEY_ENTER)
	_check(str(_main.build_screen._note).contains("NEED") and Game.build.gold == shop.cost - 1 and Game.build.slots == prepay_slots and not shop.consumed, "full price is required before any recycle credit applies")
	Game.build.gold = 0
	var before := Game.build.slots.duplicate()
	await _key(KEY_X)
	_check(str(_main.build_screen._note).contains("UNSOLD"), "Shop explains rejected recycling")
	await _key(KEY_ENTER)
	_check(str(_main.build_screen._note).contains("NEED") and not Game.announce_text.begins_with("BOUGHT"), "unaffordable offer shows required gold and never announces success")
	await _shot("shop-rejected")
	_check(not shop.consumed and Game.build.gold == 0 and Game.build.slots == before, "insufficient funds and unsold recycling reject atomically")
	# The geometry checks below need a quiet announcement band; a previous
	# purchase may still be showing its short-lived feedback.
	Game.announce_t = 0.0
	# Tooltip geometry through the production function. The camera runs in physics
	# and does not move while the tree is paused, so sampling a paused tree would
	# report the previous camera position; settle the real transform instead.
	var was_paused := get_tree().paused
	get_tree().paused = false
	var safe := Rect2(16, 16, 736, 320)
	await _place(shop.global_position)
	var near_point := shop.get_global_transform_with_canvas() * Vector2.ZERO
	var near := shop.shop_tip_rect()
	_check(safe.encloses(near) and safe.has_point(near_point), "shop tip stays inside the safe area beside a visible stock")
	await _place(shop.global_position + Vector2(0, 220))
	var high_point := shop.get_global_transform_with_canvas() * Vector2.ZERO
	var below := shop.shop_tip_rect()
	_check(high_point.y - 174.0 < safe.position.y, "fixture really leaves no room above the stock")
	_check(safe.encloses(below) and below.position.y > high_point.y, "stock high on screen flips the card below with its top edge back at the item")
	var clamped := 0
	for dx in [-360.0, -180.0, 180.0, 360.0]:
		await _place(shop.global_position + Vector2(float(dx), 0))
		var point := shop.get_global_transform_with_canvas() * Vector2.ZERO
		var card := shop.shop_tip_rect()
		_check(safe.encloses(card), "shop tip stays inside the safe area at offset %d" % int(dx))
		if point.x - 152.0 < safe.position.x or point.x - 152.0 > safe.end.x - card.size.x:
			clamped += 1
		_check(card.position.x == clampf(point.x - 152.0, safe.position.x, safe.end.x - card.size.x), "the card tracks the sampled stock horizontally")
	_check(clamped > 0, "at least one sampled stock position actually needed the horizontal clamp")
	# A live announcement owns the band around 30% height; the tip must stay
	# clear of it. When neither side can hold the whole card, the tip is
	# deferred (empty rect) rather than covering the message; the world stock,
	# its price and R comparison stay available. Sample actual screen heights
	# so the fit and deferred branches both execute.
	var hub_return := Game.hub_return_in
	Game.hub_return_in = 0.0
	Game.announce("BOUGHT / 2", 4.0)
	var spoke := shop.announcement_rect()
	_check(spoke.has_area() and safe.encloses(spoke), "announcement band is measurable inside the safe area")
	# The stock itself may sit above the safe band (the reported y=5 case); the
	# contract is the card staying inside it. Place the fixture through its
	# actual canvas transform so each sampled screen height is real, not a
	# guessed world offset that camera settling can move.
	var below_fit := 0
	var deferred := 0
	var shop_at := shop.global_position
	var canvas := get_viewport().get_canvas_transform()
	for screen_y: float in [5.0, 153.0, 240.0, 345.0]:
		shop.global_position = canvas.affine_inverse() * Vector2(384, screen_y)
		var announced_point := shop.get_global_transform_with_canvas() * Vector2.ZERO
		var announced := shop.shop_tip_rect()
		if not announced.has_area():
			deferred += 1
			continue
		_check(safe.encloses(announced), "announced shop tip stays inside the safe area at stock y %.0f" % announced_point.y)
		_check(not announced.intersects(spoke.grow(2.0)), "announced shop tip never covers the live announcement at stock y %.0f" % announced_point.y)
		if announced.position.y > announced_point.y:
			below_fit += 1
	shop.global_position = shop_at
	_check(below_fit > 0 and deferred > 0, "samples cover a real below-stock fit and the deferred no-fit case")
	Game.announce_t = 0.0
	Game.hub_return_in = hub_return
	if was_paused:
		get_tree().paused = true
	await _place(shop.global_position)
	var target := 2 if Game.build.definition(shop.item)["kind"] == "skill" else 0
	var sale := shop.item
	old = Game.build.slots[target]
	old_value = Game.build.recycle_value(old)
	Game.build.gold = shop.cost
	await _key(KEY_ENTER)
	_check(is_same(Game.build.slots[target], sale) and Game.build.gold == old_value, "exact-price purchase charges once, refunds old")
	_check(Game.announce_text.begins_with("BOUGHT"), "success only follows committed purchase; announce=" + str(Game.announce_text) + " locale=" + TranslationServer.get_locale())
	await _key(KEY_ENTER)
	_check(Game.build.gold == old_value, "rapid confirmation after close cannot buy again")
	var gear: RunLoot = found["gear"]
	var worth := Game.build.recycle_value(gear.item)
	coins = Game.build.gold
	_check(gear.claim(-1, true) and not gear.claim(-1, true) and Game.build.gold == coins + worth, "same-frame double recycle pays once")
	var food: RunLoot = found["food"]
	_p.hp = _p.max_hp
	_check(not food.claim() and not food.consumed, "full-health food stays in world")
	# Relocate at full health, then wound the player immediately before the
	# real interact event; 18 physics frames at 1 HP could otherwise die or
	# take chip damage before the food is eligible.
	await _place(food.global_position)
	_p.hp = 1
	var food_available := food.available()
	await _key(KEY_R)
	var food_state := "freed/consumed" if not is_instance_valid(food) else "available=%s consumed=%s" % [str(food.available()), str(food.consumed)]
	var food_actual := "hp=%.3f max=%.3f food_available_before=%s food=%s phase=%s" % [_p.hp, _p.max_hp, str(food_available), food_state, Game.run_phase]
	_check(is_equal_approx(_p.hp, 1 + _p.max_hp * 0.25), "R consumes food and heals actual player", food_actual)
	_p.hp = _p.max_hp
	for axis in [0, 2]:
		var more := RunLoot.new()
		more.kind = "scroll"
		_main.level.add_child(more)
		_check(more.claim(axis) and not more.claim(axis), "single-consume Scroll axis %d" % axis)
	_check(Game.build.attributes.values() == [1, 1, 1], "all three independent Scroll axes")
	var amulet := RunLoot.new()
	amulet.item = Game.build.create("ash_charm", "etched", "keen")
	_main.level.add_child(amulet)
	var cap := _p.max_hp
	hp = _p.hp
	_check(amulet.claim(4) and _p.max_hp > cap and _p.hp == hp, "amulet replacement changes actual max HP without healing")
	coins = Game.build.gold
	_check(not amulet.claim(4) and Game.build.gold == coins, "same-frame replacement cannot recycle old gear twice")
	await _offer_lifecycle()


## An offer destroyed unclaimed must not leave its instance in the run inventory;
## an offer that is already equipped elsewhere must survive, and a stale owner
## from a previous run must never retire a live item that reused the same UID.
func _offer_lifecycle() -> void:
	var build := Game.build
	var unclaimed := RunLoot.new()
	unclaimed.item = build.create("arc_saber", "etched", "keen")
	_main.level.add_child(unclaimed)
	var dropped := unclaimed.item
	_check(build.owns(dropped), "unclaimed offer owns its instance before exit")
	unclaimed.queue_free()
	await get_tree().process_frame
	_check(not build.owns(dropped), "unclaimed offer retires its instance when its terrain dies")
	var kept := RunLoot.new()
	kept.item = build.create("arc_saber")
	_main.level.add_child(kept)
	var equipped := kept.item
	_check(build.equip(0, equipped), "offer instance can be equipped elsewhere")
	kept.queue_free()
	await get_tree().process_frame
	_check(build.owns(equipped) and is_same(build.slots[0], equipped), "equipped instance survives an unclaimed offer exit")
	var recycled := RunLoot.new()
	recycled.item = build.create("arc_saber")
	_main.level.add_child(recycled)
	var sold := recycled.item
	var coins := build.gold
	var worth := build.recycle_value(sold)
	_check(recycled.claim(-1, true) and build.gold == coins + worth and not build.owns(sold), "recycle pays once and retires")
	await get_tree().process_frame
	_check(build.gold == coins + worth, "recycled offer does not pay again on exit")
	var live := build.create("arc_saber")
	var stale := RunBuild.new()
	stale.start("rusty_sword", ["rusty_sword"])
	stale._serial = int(live["uid"]) - 1
	var stale_offer := RunLoot.new()
	_main.level.add_child(stale_offer)
	stale_offer.owner_build = stale
	stale_offer.item = stale.create("arc_saber")
	_check(stale_offer.item["uid"] == live["uid"] and build.owns(live), "old and new builds can reuse a UID")
	var stale_item: Dictionary = stale_offer.item
	stale_offer.queue_free()
	await get_tree().process_frame
	_check(build.owns(live) and not stale.owns(stale_item), "stale offer exits without touching the live build")

func _long_comparison() -> void:
	var build := Game.build
	var screen: Node = _main.build_screen
	var original_name: String = Data.gear.items.arc_saber.name
	var original_affix: String = Data.gear.affixes.venom.name
	Data.gear.items.arc_saber.name = "Arc Saber / A Very Long Equipment Name That Must Remain Fully Readable Without Smaller Type"
	Data.gear.affixes.venom.name = "Venom / Poison On Every Hit / Extended Boundary Description"
	var loot := RunLoot.new()
	loot.item = build.create("arc_saber", "etched", "venom")
	_main.level.add_child(loot)
	var coins := build.gold
	build.gold = 999999
	screen.open(loot)
	await _frames(2)
	var lines: Array[String] = screen._detail_lines
	_check(lines.size() > screen._detail_rows, "long comparison overflows the shared detail band")
	var joined := "".join(lines)
	_check(Data.gear.items.arc_saber.name in joined, "long comparison retains the complete name in scrollable details")
	_check(lines[0] == ContentText.of("UI_BUILD_CANDIDATE", "FOUND / CANDIDATE"), "shared details label the candidate block")
	_check(joined.contains(screen._slot_name(0)), "shared details label the selected target slot")
	for line in lines:
		_check(MathArt.ui_font().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x <= 664, "actual font stays inside comparison details")
	var en_details := joined
	TranslationServer.set_locale("zh_TW")
	await _frames(2)
	var zh_details := "".join(screen._detail_lines)
	_check(zh_details != en_details and zh_details.contains(screen._slot_name(0)), "bilingual details keep owner labels while rewrapping")
	TranslationServer.set_locale("en")
	await _frames(2)
	var en_again := "".join(screen._detail_lines)
	_check(screen._detail_count > 0 and en_again == en_details, "English locale round trip keeps full non-empty canonical details (count %d, rows %d)" % [screen._detail_count, screen._detail_rows])
	await _shot("compare-long-top")
	var detail_last: int = int(screen._detail_count) - int(screen._detail_rows)
	for i in detail_last + 1: await _key(KEY_DOWN)
	_check(screen.visible and screen._detail_scroll > 0 and screen._detail_scroll == detail_last, "keyboard reaches final detail without spilling into actions (count %d, scroll %d, rows %d)" % [screen._detail_count, screen._detail_scroll, screen._detail_rows])
	await _shot("compare-long-bottom")
	var kept_uid := int(build.slots[0]["uid"])
	var kept_charges := int(build.slots[0]["charges"])
	var kept_hp := _p.hp
	await _key(KEY_ESCAPE)
	_check(not loot.consumed and build.gold == 999999 and not get_tree().paused, "long detail cancel restores gameplay without transaction")
	_check(int(build.slots[0]["uid"]) == kept_uid and int(build.slots[0]["charges"]) == kept_charges and is_equal_approx(_p.hp, kept_hp), "cancel deletes no instance, charge or HP")
	loot.queue_free()
	var originals: Array = build.slots.duplicate()
	Data.gear.items.arc_saber.name = Data.gear.items.arc_saber.name.repeat(4)
	build.equip(0, build.create("arc_saber"))
	build.equip(1, build.create("arc_saber"))
	build.equip(2, build.create("kunai"))
	build.equip(3, build.create("kunai"))
	_check(build.scroll_projection("tactics", _p.hp).affected.size() == 4, "four distinct same-axis gear instances benefit in long Scroll fixture")
	var scroll := RunLoot.new()
	scroll.kind = "scroll"
	_main.level.add_child(scroll)
	screen.open(scroll)
	await _key(KEY_2)
	await _frames(2)
	_check(screen._detail_count > screen._detail_rows, "long equipped names overflow Scroll details in the fixture")
	var scroll_last: int = int(screen._detail_count) - int(screen._detail_rows)
	for i in scroll_last + 1: await _key(KEY_DOWN)
	_check(screen.visible and screen._detail_scroll == scroll_last and not scroll.consumed, "Scroll detail keyboard reaches final row without committing (count %d, scroll %d, rows %d)" % [screen._detail_count, screen._detail_scroll, screen._detail_rows])
	await _shot("scroll-long-bottom")
	await _key(KEY_ESCAPE)
	for slot in 4: build.equip(slot, originals[slot])
	scroll.queue_free()
	build.gold = coins
	Data.gear.items.arc_saber.name = original_name
	Data.gear.affixes.venom.name = original_affix

func _comparison_contracts() -> void:
	var build := Game.build
	var screen: Node = _main.build_screen
	var saved: Dictionary = build.slots[1]
	var shield := build.create("fold_shield")
	var offer := RunLoot.new()
	offer.item = build.create("aegis")
	_main.level.add_child(offer)
	var previous_offer: RunLoot = screen.offer
	build.slots[1] = shield
	screen.offer = offer
	# Both display COUNTER; only canonical action identity proves they differ.
	var line: String = screen._target_headline(1, shield)
	_check(not line.contains("→") and line.contains("Different actions"), "same display label with different canonical actions never gets a numeric delta: " + line)
	_check(screen._recycle_credit({}) == 0 and screen._recycle_credit({"id": "not_a_gear"}) == 0, "empty and missing definitions fabricate no recycle credit")
	_check(screen._gear_display_name({}) == ContentText.of("UI_STAT_EMPTY", "Empty"), "empty slot reads as localized Empty in the shared presenter path")
	build.slots[1] = saved
	screen.offer = previous_offer
	offer.queue_free()


func _combat() -> void:
	# Fixture placement only: real Level, player key path, enemy collision/AI/status ticks.
	await _place(_main.level.start_point() + Vector2(240, 0))
	for enemy: Enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
		enemy.position.x += 5000
	var build: RunBuild = Game.build
	var weapon_data := Data.weapons.duplicate(true)
	# Unequal axes expose accidental scaling from the currently selected weapon.
	build.attributes = {"brutality":1, "tactics":4, "survival":7}
	build.equip(0, build.create("rusty_sword", "etched", "venom"))
	build.equip(1, build.create("fold_shield", "etched", "keen"))
	build.equip(2, build.create("kunai", "etched", "venom"))
	build.equip(3, build.create("aegis"))
	_p._apply_loadout()
	_p.facing = 1
	var enemy := Enemy.new()
	enemy.configure("grunt", Data.enemies["grunt"], 24)
	enemy.position = _p.position + Vector2(38, 0)
	_main.level.add_child(enemy)
	enemy.hp = 1000
	enemy.facing = -1
	enemy.set_physics_process(false)
	var expected := Damage.compute(float(Data.weapons.rusty_sword.combo[0].damage) * build.power(build.slots[0]), 1, false, 1)
	await _key(KEY_1)
	await _frames(24)
	_check(enemy.hp < 1000 and enemy.poison_left > 0, "1 melee hits real biome Enemy and applies poison: hp %.1f poison %.2f player %s enemy %s state %d lock %.2f attack %.2f" % [enemy.hp, enemy.poison_left, _p.position, enemy.position, _p.state, _p._action_lock, _p.attack_t])
	_check(1000 - enemy.hp == expected, "real melee resolves gear quality and brutality exactly once")
	_check(Data.weapons == weapon_data, "instance projection never mutates content tables")
	await _shot("combat")
	Combat.cancel_hitstop()
	await _frames(45)
	_p.suppress_actions()
	_p.set_state(Player.State.IDLE)
	await _frames(18)
	enemy.position = _p.position + Vector2(65, 0)
	var ehp := enemy.hp
	expected = Damage.compute(12 * build.power(build.slots[2]), 4, _p.is_crit_against(enemy), 1.5)
	await _key(KEY_Q)
	await _frames(30)
	_check(build.slots[2]["charges"] == 1 and ehp - enemy.hp == expected, "Q projectile uses its own tactics/quality, not held weapon scaling")
	Combat.cancel_hitstop()
	ehp = enemy.hp
	enemy.set_physics_process(true)
	enemy.state = Enemy.EState.HURT
	enemy.state_t = -10
	await _frames(70)
	_check(enemy.hp < ehp, "poison deals timed damage on real enemy")
	enemy.set_physics_process(false)
	_p.invuln = 0
	_p.roll_iframe_t = 999
	_p.set_state(Player.State.IDLE)
	await _frames(10)
	await _key(KEY_2)
	var hp := _p.hp
	ehp = enemy.hp
	enemy.position = _p.position + Vector2(40, 0)
	enemy.facing = -1
	enemy._begin_attack()
	await _frames(6)
	_check(_p.hp == hp and enemy.hp == ehp - Damage.compute(8 * build.power(build.slots[1]), 7, false, 1) and _p.guard_t == 0, "2 directional shield blocks and counters with survival and quality")
	Combat.cancel_hitstop()
	build.slots[1]["charges"] = 1
	await _key(KEY_2)
	enemy.position = _p.position - Vector2(40, 0)
	enemy.facing = 1
	enemy._begin_attack()
	await _frames(6)
	_check(_p.hp == hp - float(enemy.cfg.damage), "shield does not block real rear hitbox")
	enemy.hitbox.disable()
	Combat.cancel_hitstop()
	await _frames(55)
	_p.invuln = 0
	enemy.position = _p.position + Vector2(40, 0)
	ehp = enemy.hp
	await _key(KEY_E)
	hp = _p.hp
	enemy.position = _p.position - Vector2(40, 0)
	enemy.facing = 1
	enemy._begin_attack()
	await _frames(6)
	_check(_p.hp == hp and enemy.hp == ehp - Damage.compute(10 * build.power(build.slots[3]), 7, false, 1) and build.slots[3]["charges"] == 0, "E Aegis spends independent skill and blocks/counters with survival")
	Combat.cancel_hitstop()
	await _frames(8)
	var cd: float = build.slots[3]["cooldown"]
	await _key(KEY_L)
	_check(build.slots[3]["charges"] == 0 and build.slots[3]["cooldown"] <= cd, "L alias cannot bypass active cooldown")
	_check(build.slots[2]["charges"] == 2, "elapsed gameplay recharges Kunai without refilling Aegis")
	await _key(KEY_K)
	_check(build.slots[2]["charges"] == 1, "K compatibility uses skill slot one")
	await _frames(35)
	for key in [KEY_J, KEY_Z]:
		_p.set_state(Player.State.IDLE)
		await _key(key)
		_check(_p.state == Player.State.ATTACK, "legacy attack alias %d state %d t %.2f lock %.2f hp %.1f paused %s" % [key, _p.state, _p.attack_t, _p._action_lock, _p.hp, get_tree().paused])
		await _frames(45)
	Combat.cancel_hitstop()
	_p.suppress_actions()
	_p.set_state(Player.State.IDLE)
	await _frames(18)
	build.equip(1, build.create("arc_saber", "etched", "keen"))
	enemy.position = _p.position + Vector2(40, 0)
	ehp = enemy.hp
	await _key(KEY_2)
	await _frames(24)
	_check(enemy.hp < ehp and _p.weapon_slot == 1, "2 fires replacement melee weapon in second slot")
	Combat.cancel_hitstop()
	await _frames(40)
	build.equip(2, build.create("kunai"))
	build.equip(3, build.create("kunai", "plain", "quick"))
	await _key(KEY_Q)
	await _key(KEY_E)
	_check(build.slots[2]["charges"] == 1 and build.slots[3]["charges"] == 1 and build.slots[2]["cooldown"] > build.slots[3]["cooldown"], "Q/E act on distinct copies with independent cooldowns")
	var coins: int = build.gold
	enemy.take_hit({"damage":10000})
	enemy.take_hit({"damage":10000})
	_check(build.gold == coins + int(Data.gear.economy.kill_gold), "enemy death pays gold once")
	build.attributes = {"brutality":1, "tactics":1, "survival":1}
	_p._apply_loadout()
	Combat.cancel_hitstop()
	enemy.queue_free()

func _modals_and_air_roll() -> void:
	await _place(_main.level.start_point())
	var charges: int = Game.build.slots[2]["charges"]
	await _key(KEY_TAB)
	_check(_main.exploration_map.is_open(), "map opens during route")
	await _key(KEY_Q)
	await _key(KEY_1)
	await _key(KEY_2)
	_check(Game.build.slots[2]["charges"] == charges and _p.state != Player.State.ATTACK and _p.guard_t == 0, "map owns combat keys")
	await _key(KEY_ESCAPE)
	await _frames(8)
	await _key(KEY_ESCAPE)
	_check(get_tree().paused, "pause owns input")
	await _key(KEY_E)
	await _key(KEY_1)
	_check(_p.state != Player.State.ATTACK, "pause combat keys do not attack")
	await _key(KEY_ESCAPE)
	await _frames(8)
	_p.relocate(_main.level.start_point() + Vector2(400, -220))
	await _frames(18)
	_p.roll_cd = 0
	await _key(KEY_SHIFT)
	_check(_p.state == Player.State.ROLL and _p._air_roll_used, "Shift performs one air roll: state %d used %s floor %s pos %s cd %.2f lock %.2f paused %s" % [_p.state, _p._air_roll_used, _p.is_on_floor(), _p.position, _p.roll_cd, _p._action_lock, get_tree().paused])
	await _frames(38)
	_p.roll_cd = 0
	await _key(KEY_SHIFT)
	_check(_p.state != Player.State.ROLL, "second airborne roll rejected")
	await _frames(75)
	_check(_p.is_on_floor() and not _p._air_roll_used, "landing resets air roll budget")

func _transition_and_teardown(legacy: Dictionary) -> void:
	var build: RunBuild = Game.build
	var id := _p.get_instance_id()
	var item: Dictionary = build.slots[2]
	item["charges"] = 0
	item["cooldown"] = 1.0
	var hp := _p.hp
	build.gold = 23
	build.mutations.assign(["edge"])
	build.mutation_capacity = 1
	_check(Game.select_destination("hanging_gallery"), "legal exit selected")
	_main._on_floor_cleared()
	_main.enter_passage()
	_check(Game.build == build and _main.player.get_instance_id() == id and is_same(build.slots[2], item) and item["charges"] == 0 and _p.hp == hp, "Passage preserves body gear HP cooldown")
	_check(_main.start_node("hanging_gallery"), "Passage enters actual next biome")
	_check(Game.build == build and _main.player.get_instance_id() == id and build.gold == 23 and build.attributes.values() == [1, 1, 1] and build.mutations == ["edge"], "next biome keeps all run build state")
	await _frames(3)
	var late: RunLoot = get_tree().get_first_node_in_group("run_loot")
	_p.invuln = 0
	_p.guard_t = 0
	_p.aegis_t = 0
	_p.roll_iframe_t = 999
	_p.take_hit({"damage":100000})
	_check(Game.run_over and Game.build == null and not late.claim(), "real death clears build and rejects late loot")
	_check(Profile.upgrades == legacy, "legacy save ownership unchanged")
	Combat.cancel_hitstop()
	_main.enter_hub()
	await _frames(3)
	_check(_main.start_node("ash_gate"), "new run after death")
	_check(Game.build != build and Game.build.gold == 0 and Game.build.attributes.values() == [0, 0, 0] and Game.build.mutations.is_empty() and Game.build.slots[2]["charges"] == 2, "fresh start has no previous run state")
	_main.restart_attempt()
	_check(Game.build == null and Game.run_phase == "hub", "pause abandon clears run build")
	await _frames(120) # Let death FX, deferred terrain frees and their timers release.

func _place(at: Vector2) -> void:
	_p.relocate(at)
	await _frames(18)

func _key(code: int) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		if _capture: print("L3 INPUT %dms key=%d pressed=%s" % [Time.get_ticks_msec(), code, str(down)])
		await _frames(2)
		await get_tree().process_frame

func _frames(count: int) -> void:
	for n in count:
		await get_tree().physics_frame

func _shot(label: String) -> void:
	if not _capture:
		return
	var dir := "res://output/screenshots/l3"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	await get_tree().process_frame
	_main.hud.queue_redraw()
	_main.build_screen._canvas.queue_redraw()
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(dir + "/" + label + ".png") == OK, "capture " + label)
	await _physical_capture(label)
	print("L3 FRAME %dms %s selected=%d y=%.3f" % [Time.get_ticks_msec(), label, _main.build_screen._index, _main.build_screen._canvas.position.y])
	if "entry" not in label and OS.get_environment("ASHFALL_CAPTURE_ACK_DIR").is_empty(): await get_tree().create_timer(0.08, true).timeout

func _check(ok: bool, message: String, actual: Variant = null) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		if actual != null:
			message += " (actual: %s)" % str(actual)
		push_error("L3 BUILD FAIL: " + message)
		get_tree().quit(1)

func _physical_capture(label: String) -> void:
	var directory := OS.get_environment("ASHFALL_CAPTURE_ACK_DIR")
	if directory.is_empty(): return
	var path := directory.path_join(label + ".json")
	var deadline := Time.get_ticks_msec() + 1500
	while not FileAccess.file_exists(path) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(FileAccess.file_exists(path), "owned physical capture acknowledgement: " + label)
