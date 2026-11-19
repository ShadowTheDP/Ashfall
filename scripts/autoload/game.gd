extends Node
## Run state, score, combo tracking and rewards.
##
## Input actions and controller defaults live in project.godot. Interface owns
## runtime overrides, prompts and the last meaningful input device.

signal rewards_requested(choices: Array)

const COMBO_WINDOW := 1.6
const ROUTES := preload("res://scripts/systems/route_graph.gd")
const PERFECT_DODGE_TIME := 2.5
const PERFECT_DODGE_MULT := 1.25
## Combo is the only readout that says how a fight is going, and it used to
## climb silently. A milestone gets one line of text and one ring: enough to be
## felt at ten hits, short enough not to cover the next telegraph.
const COMBO_MILESTONES := [10, 20, 35, 50]

var player: Player = null
var fx_root: Node = null
var screen_fx_root: Node = null

var cells := 0
var kills := 0
var combo := 0
var combo_time := 0.0
var combo_pop := 0.0
var max_combo := 0
var perfect_dodges := 0

var wave := 0
var wave_total := 0
var enemies_left := 0

var run_time := 0.0
var run_over := false
var victory := false
## Why the ended run ended, recorded from the canonical end_run() call. It is
## presentation state only: no save, checkpoint or settlement payload carries
## it, and a victory always clears it.
var run_abandoned := false

var announce_text := ""
var announce_t := 0.0
var announce_max := 1.0
## Presentation severity of the current announcement. HUD reads this instead of
## sniffing an English prefix, so a translated error keeps its emphasis.
var announce_kind: StringName = &"info"

# Build state
var build: RunBuild
var damage_mult := 1.0
var edge_timer := 0.0
var leech := 0
## The two-colour build: boons raise their own colour, and a weapon scales with
## the colour it carries. It persists across floors and resets with the run.
var attr: Dictionary = {}
## Boons still owed by the current floor, from data/floors.json "reward".
var floor_rewards_left := 0
var reward_counts: Dictionary = {}
var reward_open := false
var auto_choose_rewards := false

# Boss
var boss: Enemy = null
var boss_defeated := false

# --- Meta progression -------------------------------------------------------
# floor_index is 1-based while inside a floor and 0 while in the hub.
var floor_index := 0
var floor_name := ""
var run_cells := 0          # unbanked; lost on death
var in_hub := true
var run_node_id := ""
var generator_revision := BiomeGen.LATEST_REVISION
var route_history: Array[String] = []
var defeated_bosses: Array[String] = []
var settlement_pending: Dictionary = {}
var run_keys: Array[String] = []
var carried_blueprints: Array[String] = []
var node_time := 0.0
var kill_streak := 0
var best_kill_streak := 0
var boss_damage := 0.0
var passage_snapshot: Dictionary = {}
var passage_claims: Dictionary = {}
var run_bsc := 0
var run_phase := "hub"
var flask_capacity := 0
var flask_charges := 0
var slice_complete := false
var exit_selected := false
var pending_destination := ""

# Presentation
var hurt_flash := 0.0
## Seconds until Main returns to the hub, set every frame by Main while a
## transition is pending and 0 otherwise. The HUD prints it so the end-of-floor
## and death overlays can say where the player is about to be instead of only
## offering a key that is about to stop working.
var hub_return_in := 0.0


func _process(delta: float) -> void:
	if not run_over and run_phase in ["biome", "transition", "arena"]:
		run_time += delta
	if not run_over and run_phase == "biome":
		node_time += delta
	combo_pop = maxf(0.0, combo_pop - delta * 4.0)
	announce_t = maxf(0.0, announce_t - delta)
	edge_timer = maxf(0.0, edge_timer - delta)
	hurt_flash = maxf(0.0, hurt_flash - delta)
	if combo_time > 0.0:
		combo_time -= delta
		if combo_time <= 0.0:
			combo = 0


func reset_run() -> void:
	build = null
	cells = 0
	kills = 0
	combo = 0
	combo_time = 0.0
	combo_pop = 0.0
	max_combo = 0
	perfect_dodges = 0
	wave = 0
	wave_total = 0
	enemies_left = 0
	run_time = 0.0
	run_over = false
	victory = false
	run_abandoned = false
	announce_text = ""
	announce_t = 0.0
	announce_max = 1.0
	announce_kind = &"info"
	damage_mult = 1.0
	edge_timer = 0.0
	leech = 0
	attr.clear()
	floor_rewards_left = 0
	reward_counts.clear()
	reward_open = false
	auto_choose_rewards = false
	boss = null
	boss_defeated = false
	hurt_flash = 0.0
	hub_return_in = 0.0
	floor_index = 0
	floor_name = ""
	run_cells = 0
	in_hub = true
	run_node_id = ""
	generator_revision = BiomeGen.LATEST_REVISION
	route_history.clear()
	defeated_bosses.clear()
	run_keys.clear()
	carried_blueprints.clear()
	_reset_visit()
	run_bsc = 0
	run_phase = "hub"
	flask_capacity = 0
	flask_charges = 0
	slice_complete = false
	exit_selected = false
	pending_destination = ""
	player = null
	Engine.time_scale = 1.0
	get_tree().paused = false


func combo_hit() -> void:
	combo += 1
	combo_time = COMBO_WINDOW
	combo_pop = 1.0
	max_combo = maxi(max_combo, combo)
	if COMBO_MILESTONES.has(combo):
		announce(ContentText.of("UI_HIT_CHAIN", "{count} HIT CHAIN").format({"count": combo}), 0.85)
		Combat.shake(0.14)
		if is_instance_valid(player):
			Combat.ring(player.global_position + Vector2(0, -8), MathArt.WHITE, 34.0)


func combo_break() -> void:
	combo = 0
	combo_time = 0.0


func add_cells(amount: int) -> void:
	if run_over:
		return
	# Permanent GREED upgrades and the hub bank both read this counter, so the
	# multiplier is applied once here rather than at every drop site.
	var scaled := amount if build != null else int(roundf(float(amount) * (1.0 + Profile.bonus("cells"))))
	cells += scaled
	if not in_hub:
		run_cells += scaled


func add_kill(is_boss := false) -> void:
	if run_over:
		return
	kills += 1
	if is_boss and not run_node_id.is_empty() and boss_defeated and is_instance_valid(boss) and boss.hp <= 0.0 and boss.kind == run_node_id and not defeated_bosses.has(run_node_id):
		defeated_bosses.append(run_node_id)
	if build != null and not is_boss:
		kill_streak += 1
		best_kill_streak = maxi(best_kill_streak, kill_streak)
		if is_instance_valid(player) and player.hp > 0 and build.effect("heal_kill") > 0:
			player.heal(build.effect("heal_kill"))
	if leech > 0 and player != null:
		player.hp = minf(player.max_hp, player.hp + float(leech))


func note_damage_taken(amount: float) -> void:
	if amount <= 0 or run_over:
		return
	kill_streak = 0
	if is_instance_valid(boss) and not boss_defeated:
		boss_damage += amount


func _reset_visit() -> void:
	node_time = 0.0
	kill_streak = 0
	best_kill_streak = 0
	boss_damage = 0.0
	passage_snapshot.clear()
	passage_claims.clear()


func announce(text: String, duration: float = 1.3, kind: StringName = &"info") -> void:
	announce_text = text
	announce_t = duration
	announce_max = duration
	announce_kind = kind


## Save failures always carry the original Profile diagnostic after a localized
## prefix: the player gets an actionable line, the validator keeps the cause.
func announce_save_failed(extra := "") -> void:
	var text := ContentText.of("UI_ERR_SAVE_FAILED", "Save failed") + ": " + Profile.last_save_error
	if not extra.is_empty():
		text += " · " + extra
	announce(text, 3.0, &"error")


func final_ready() -> bool:
	if run_over or run_phase != "biome" or run_bsc != 0 or run_node_id != str(Data.route_graph.final) or not boss_defeated or not is_instance_valid(player) or player.hp <= 0.0:
		return false
	if route_history.size() != Data.route_graph.default_0_bsc_route.size() or route_history[0] != str(Data.route_graph.start) or route_history[-1] != run_node_id:
		return false
	for id: String in Data.route_graph.default_0_bsc_route:
		if str(Data.route_graph.nodes[id].kind) == "boss" and not defeated_bosses.has(id):
			return false
	for index in range(1, route_history.size()):
		var legal := false
		for edge: Dictionary in Data.route_graph.edges:
			if str(edge.from) == route_history[index - 1] and str(edge.to) == route_history[index] and ROUTES.lock_reason(edge, route_state()).is_empty():
				legal = true
		if not legal:
			return false
	return true


func retry_settlement() -> bool:
	if settlement_pending.is_empty():
		return true
	if not Profile.note_run(int(settlement_pending.kills), bool(settlement_pending.died), false):
		announce_save_failed()
		return false
	settlement_pending.clear()
	return true


func end_run(did_win: bool, abandoned: bool = false) -> bool:
	if run_over or (did_win and (in_hub or (not run_node_id.is_empty() and not final_ready()))):
		return false
	var saved := Profile.note_run(kills, not did_win and not abandoned, did_win, run_cells if did_win else 0, run_bsc if did_win and not run_node_id.is_empty() else -1)
	if not saved and did_win:
		announce_save_failed(ContentText.of("UI_SAVE_RETRY_EXIT", "Retry exit"))
		return false
	if not saved:
		settlement_pending = {"kills":kills, "died":not abandoned}
	run_over = true
	run_abandoned = abandoned and not did_win
	exit_selected = false
	pending_destination = ""
	run_phase = "ended"
	victory = did_win
	announce_t = 0.0
	Sfx.play("ui" if abandoned else ("wave" if did_win else "death"), -4.0)
	# The permanent receipt above commits before any carried reward is discarded.
	run_cells = 0
	flask_charges = 0
	run_keys.clear()
	carried_blueprints.clear()
	passage_snapshot.clear()
	passage_claims.clear()
	build = null
	if not run_node_id.is_empty():
		attr.clear()
		reward_counts.clear()
		damage_mult = 1.0
		leech = 0
	if not saved:
		announce_save_failed(ContentText.of("UI_SAVE_RETRY_ENTER", "Enter to retry"))
	return true


# --- Floor flow -------------------------------------------------------------

func start_floor(index: int) -> void:
	floor_index = maxi(1, index)
	in_hub = false
	if run_node_id.is_empty():
		run_phase = "biome"
	run_over = false
	victory = false
	run_abandoned = false
	# kills is NOT reset here. It is the run's kill count, and end_run()
	# persists it to Profile.total_kills; a per-floor reset meant a 5-floor
	# victory recorded only the Warden's single kill. reset_run() owns it.
	floor_rewards_left = int(Data.floors.get(str(floor_index), {}).get("reward", 0)) if build == null else 0
	if run_node_id.is_empty() and not Profile.note_floor_reached(floor_index):
		announce_save_failed()


func route_state() -> Dictionary:
	return {"runes": Profile.unlocked_runes, "keys": run_keys, "bsc": run_bsc}


func route_exits() -> Array[Dictionary]:
	var exits: Array[Dictionary] = []
	for edge: Dictionary in Data.route_graph.get("edges", []):
		if str(edge["from"]) != run_node_id:
			continue
		var row := edge.duplicate(true)
		row["reason"] = ROUTES.lock_reason(edge, route_state())
		if not Data.route_profiles.get("nodes", {}).has(str(edge["to"])) and str(row["reason"]).is_empty():
			row["reason"] = "LATER CHAPTER"
		exits.append(row)
	return exits


func exit_reason(id: String) -> String:
	if str(Data.route_graph["nodes"].get(run_node_id, {}).get("kind", "")) == "boss" and not boss_defeated:
		return "BOSS ALIVE"
	if id.is_empty() and run_node_id == str(Data.route_graph.final):
		return "" if final_ready() else "RUN INCOMPLETE"
	if bool(Data.biomes["biomes"].get(run_node_id, {}).get("slice_end", false)) and id.is_empty():
		return ""
	for edge in route_exits():
		if str(edge["to"]) == id:
			return str(edge["reason"])
	return "UNKNOWN EXIT"


func select_destination(id: String) -> bool:
	if run_phase != "biome" or run_over or exit_selected or not is_instance_valid(player) or player.hp <= 0.0 or not exit_reason(id).is_empty():
		return false
	pending_destination = id
	exit_selected = true
	passage_snapshot = {"time":node_time, "streak":best_kill_streak, "flawless":boss_defeated and boss_damage <= 0}
	if build != null:
		build.mutation_capacity = mini(int(Data.passage.mutation_reset.capacity), route_history.size())
	return true


func enter_node(id: String) -> bool:
	var cfg: Dictionary = Data.route_profiles.get("nodes", {}).get(id, {})
	if cfg.is_empty() or not retry_settlement():
		return false
	var fresh := run_node_id.is_empty()
	if fresh:
		if id != str(Data.route_graph["start"]) or not in_hub:
			return false
	else:
		if run_phase != "passage" or run_over or not exit_selected or id != pending_destination:
			return false
		var allowed := false
		for edge in route_exits():
			if str(edge["to"]) == id and str(edge["reason"]).is_empty():
				allowed = true
		if not allowed:
			return false
	if not Profile.discover_biome(id):
		announce_save_failed()
		return false
	if fresh:
		run_bsc = 0
		build = RunBuild.new()
		build.start(Profile.selected_weapon, Profile.unlocked_weapons)
		flask_capacity = int(Data.route_profiles["flask"]["capacity"])
		flask_charges = flask_capacity
	run_node_id = id
	_reset_visit()
	exit_selected = false
	pending_destination = ""
	route_history.append(id)
	run_phase = "biome"
	boss = null
	boss_defeated = false
	floor_name = str(Data.route_graph["nodes"][id]["name"]).to_upper()
	start_floor(int(cfg["floor_profile"]))
	return true


func drink_flask() -> bool:
	if in_hub or run_over or run_phase not in ["biome", "passage"] or not is_instance_valid(player):
		return false
	if flask_charges <= 0 or player.hp <= 0.0 or player.hp >= player.max_hp or player.state == Player.State.HURT:
		return false
	var hp := player.hp
	flask_charges -= 1
	player.heal(player.max_hp * float(Data.route_profiles["flask"]["heal_fraction"]))
	if run_phase == "passage" and not save_passage():
		flask_charges += 1
		player.hp = hp
		return false
	Sfx.play("reward", -12)
	return true


func service_ready() -> bool:
	return build != null and run_phase == "passage" and not run_over and not passage_snapshot.is_empty() and is_instance_valid(player) and player.hp > 0


func save_passage() -> bool:
	if not service_ready(): return false
	if Profile.save(RunCheckpoint.capture(self, "passage")):
		return true
	announce_save_failed()
	return false


func refill_flask() -> bool:
	Profile.last_save_error = ""
	if not service_ready() or run_bsc != 0 or passage_claims.has("fountain"):
		return false
	var hp := player.hp
	var charges := flask_charges
	passage_claims["fountain"] = true
	player.heal(player.max_hp)
	flask_charges = flask_capacity
	if save_passage(): return true
	player.hp = hp
	flask_charges = charges
	passage_claims.erase("fountain")
	return false


func deliver_blueprint(id: String) -> bool:
	if not service_ready() or not carried_blueprints.has(id):
		return false
	var checkpoint := RunCheckpoint.capture(self, "passage")
	checkpoint.state.carried_blueprints.erase(id)
	if not Profile.deliver_blueprint(id, checkpoint): return false
	carried_blueprints.erase(id)
	return true


func blueprint_investment(id: String, requested: int) -> int:
	var remaining := int(Data.passage.blueprints.get(id, {}).get("cost", 0)) - int(Profile.blueprint_cells.get(id, 0))
	return maxi(0, mini(mini(requested, run_cells), remaining))


func invest_blueprint(id: String, requested: int) -> int:
	if not service_ready() or requested <= 0:
		return 0
	var planned := blueprint_investment(id, requested)
	var checkpoint := RunCheckpoint.capture(self, "passage")
	checkpoint.state.run_cells -= planned
	var amount := Profile.invest_blueprint(id, planned, checkpoint)
	run_cells -= amount
	return amount


func boss_passage() -> bool:
	return str(Data.route_graph.nodes.get(run_node_id, {}).get("kind", "")) == "boss" and boss_defeated


func forge_investment(requested: int) -> int:
	return maxi(0, mini(mini(requested, run_cells), int(Data.passage.forge.cost) - Profile.forge_cells))


func invest_forge(requested: int) -> int:
	if not service_ready() or not boss_passage() or requested <= 0:
		return 0
	var planned := forge_investment(requested)
	var checkpoint := RunCheckpoint.capture(self, "passage")
	checkpoint.state.run_cells -= planned
	var amount := Profile.invest_forge(planned, checkpoint)
	run_cells -= amount
	return amount


func choose_mutation(id: String) -> bool:
	if not service_ready() or not Profile.mutation_available(id) or build.mutations.has(id) or build.mutations.size() >= build.mutation_capacity:
		return false
	build.mutations.append(id)
	player._apply_loadout()
	if save_passage(): return true
	build.mutations.erase(id)
	player._apply_loadout()
	return false


func reset_mutations() -> bool:
	if not service_ready(): return false
	var mutations := build.mutations.duplicate()
	var gold := build.gold
	var resets := build.mutation_resets
	if not build.reset_mutations(): return false
	player._apply_loadout()
	if save_passage(): return true
	build.mutations.assign(mutations)
	build.gold = gold
	build.mutation_resets = resets
	player._apply_loadout()
	return false


func craft(slot: int, reforge: bool) -> bool:
	if not service_ready() or slot < 0 or slot >= 4: return false
	var item := build.slots[slot]
	var previous := item.duplicate(true)
	var gold := build.gold
	if not build.craft(slot, reforge): return false
	player._apply_loadout()
	if save_passage(): return true
	item.clear()
	item.merge(previous)
	build.gold = gold
	player._apply_loadout()
	return false


func challenge_ids() -> Array:
	return Data.passage.boss_challenges if boss_passage() else Data.passage.ordinary_challenges


func challenge_available(id: String) -> bool:
	if not service_ready() or not challenge_ids().has(id) or passage_claims.has(id):
		return false
	var cfg: Dictionary = Data.passage.challenges[id]
	match id:
		"time": return float(passage_snapshot.time) <= float(cfg.seconds)
		"streak": return int(passage_snapshot.streak) >= int(cfg.kills)
		"flawless": return bool(passage_snapshot.flawless)
	return false


func claim_challenge(id: String) -> bool:
	if not challenge_available(id):
		return false
	var gold := build.gold
	var earned := cells
	var wallet := run_cells
	passage_claims[id] = true
	build.gold += int(Data.passage.challenges[id].gold)
	add_cells(int(Data.passage.challenges[id].cells))
	if save_passage(): return true
	build.gold = gold
	cells = earned
	run_cells = wallet
	passage_claims.erase(id)
	return false


func create_loot(pool_id: String, seed_value: int) -> Dictionary:
	if build == null or not Data.gear.loot_pools.has(pool_id):
		return {}
	var pool: Array = Data.gear.loot_pools[pool_id].filter(func(row: Dictionary) -> bool: return Profile.gear_available(str(row.id)))
	if pool.is_empty():
		pool = [{"id":"rusty_sword", "quality":"plain", "affix":"none"}]
	var row: Dictionary = pool[posmod(seed_value, pool.size())]
	var quality := str(row.quality)
	if float(posmod(hash(str(seed_value) + "/forge"), 10000)) / 10000.0 < Profile.forge_chance():
		quality = str(Data.passage.forge.quality)
	return build.create(str(row.id), quality, str(row.affix))


func max_floor() -> int:
	return Data.floors.size()


# --- Combat multipliers -----------------------------------------------------

func total_damage_mult() -> float:
	var mult := damage_mult * (1.0 + build.effect("damage") if build != null else 1.0)
	if edge_timer > 0.0:
		mult *= PERFECT_DODGE_MULT
	return mult


func perfect_dodge() -> void:
	# The DANCER passive doubles the window and lets it stack twice, so a good
	# dodge chain keeps the buff alive instead of merely refreshing it.
	var scale := 1.0
	if is_instance_valid(player):
		scale = player.perfect_dodge_scale
	var gained := PERFECT_DODGE_TIME * scale
	var cap := PERFECT_DODGE_TIME * scale * (2.0 if scale > 1.5 else 1.0)
	edge_timer = minf(cap, edge_timer + gained)
	perfect_dodges += 1
	if player != null:
		player.refund_knife()
		var at := player.global_position + Vector2(0, -8)
		Combat.dodge_burst(at)
		Juice.dodge(Game.fx_root, at)
	Combat.shake(0.14)
	# A 2-frame freeze sells the read without a screen flash.
	Combat.hitstop(0.033)
	Sfx.play("dodge", -5)
	announce(ContentText.of("UI_PERFECT_DODGE", "PERFECT DODGE"), 0.6)


# --- Rewards ----------------------------------------------------------------

func request_rewards(count: int = 3) -> void:
	var ids: Array = Data.rewards.keys()
	ids.shuffle()
	var choices: Array = ids.slice(0, mini(count, ids.size()))
	reward_open = true
	rewards_requested.emit(choices)


func apply_reward(id: String) -> void:
	if build != null:
		return # Legacy boons never stack with the route build.
	var data: Dictionary = Data.rewards.get(id, {})
	if data.is_empty():
		push_error("Unknown reward: " + id)
		return
	match id:
		"vitality":
			if player != null:
				player.max_hp += 20.0
				player.heal(20.0)
		"edge":
			damage_mult += 0.12
		"swift":
			if player != null:
				player.max_speed *= 1.08
		"ghost":
			# The cap used to be 0.28, which made this boon a no-op for the
			# GLASS character (already 0.32). The cap now sits above every
			# reachable value so the boon always does something.
			if player != null:
				player.roll_iframe_end = minf(0.40, player.roll_iframe_end + 0.03)
		"armory":
			if player != null:
				player.add_knife_max()
		"leech":
			leech += 1
		"hunter":
			if player != null:
				player.crit_bonus += 0.15
	var colour := str(data.get("attribute", ""))
	if not colour.is_empty():
		attr[colour] = int(attr.get(colour, 0)) + 1
	reward_counts[id] = int(reward_counts.get(id, 0)) + 1
	reward_open = false
	Sfx.play("reward", -6)


func grant_random_reward() -> void:
	var ids: Array = Data.rewards.keys()
	if ids.is_empty():
		return
	ids.shuffle()
	apply_reward(ids[0])

