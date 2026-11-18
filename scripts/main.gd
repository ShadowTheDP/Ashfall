extends Node2D
## Boots the prototype: world, actors, HUD, background and wave director.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const BACKGROUND_SHADER: Shader = preload("res://shaders/background.gdshader")
const VIGNETTE_SHADER: Shader = preload("res://shaders/vignette.gdshader")
const BLOOM_SHADER: Shader = preload("res://shaders/bloom.gdshader")

## "" auto-resolves: the test harnesses all set skip_title, and they want the
## original single-arena wave flow; the real game starts in the hub.
## "arena" | "hub" force one or the other.
@export var start_mode := ""
@export var skip_title := false
## Harness switch, same purpose as start_mode: the headless probes drive whole
## runs with no way to press a key, so a room reward is granted straight away
## instead of raising the picker (which pauses the tree and would hang them).
## A real run never sets this.
@export var auto_rewards := false

var world: Node2D
var arena: Arena
var player: Player
var encounter: Encounter
var hud: Hud
var reward_screen: RewardScreen
var title_screen: TitleScreen

# Meta layer. Both are loaded by path so this file still parses while the
# meta modules are being written in parallel.
var hub: Node = null
var level: Node = null
var archive: Node = null
var skill_tree: Node = null
var collector: Node = null
var passage: Node = null
var exploration_map: Node = null
var build_screen: Node = null
## The single SettingsScreen. Both the title and pause ask this owner for it;
## no page creates a second instance, so only one draft/transaction can exist.
var settings_screen: SettingsScreen = null
var _settings_owner := ""
var _terrain: Node = null
var _transition := 0.0
var _fade_rect: ColorRect = null
var _fade_tween: Tween = null
var _fade_armed := false
## Boons owed by rooms that cleared while a picker was already on screen.
var _owed_rewards := 0
## The gate has fired; the run is still at risk until the Collector is done.
var _cleared_floor := false
var _pending_checkpoint: Dictionary = {}
var _background_material: ShaderMaterial


func _ready() -> void:
	# A UI/test parent must not make the world run through modal pause.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	randomize()
	if start_mode.is_empty():
		start_mode = "arena" if skip_title else "hub"
	Game.reset_run()

	world = Node2D.new()
	world.name = "World"
	add_child(world)

	# The arena stage owns a solid GROUND box from y 0 to 160 plus five
	# platforms. It must NOT exist outside arena mode: in the hub its platforms
	# were invisible steps you could still jump onto, and on a generated floor
	# its ground box swallowed the player spawn so the level froze.
	if start_mode == "arena":
		_build_arena_stage()

	var hud_layer := CanvasLayer.new()
	hud_layer.name = "HudLayer"
	hud_layer.layer = 30
	add_child(hud_layer)
	hud = Hud.new()
	hud.name = "Hud"
	hud_layer.add_child(hud)
	hud.settings_requested.connect(_on_hud_settings_requested)
	exploration_map = preload("res://scripts/ui/exploration_map.gd").new()
	add_child(exploration_map)
	build_screen = preload("res://scripts/ui/build_screen.gd").new()
	add_child(build_screen)
	_ensure_settings()

	var reward_layer := CanvasLayer.new()
	reward_layer.name = "RewardLayer"
	reward_layer.layer = 40
	add_child(reward_layer)
	reward_screen = RewardScreen.new()
	reward_screen.name = "RewardScreen"
	reward_layer.add_child(reward_screen)

	Game.rewards_requested.connect(_on_rewards_requested)
	reward_screen.chosen.connect(_on_reward_chosen)

	if not skip_title:
		_show_title()

	var screen_fx_layer := CanvasLayer.new()
	screen_fx_layer.name = "ScreenFxLayer"
	screen_fx_layer.layer = 25
	add_child(screen_fx_layer)
	Game.screen_fx_root = screen_fx_layer

	_add_fullscreen_shader_layer(-10, BACKGROUND_SHADER)
	_set_background_palette("arena" if skip_title and start_mode == "arena" else "hub")
	_add_fullscreen_shader_layer(15, BLOOM_SHADER)
	_add_fullscreen_shader_layer(20, VIGNETTE_SHADER)
	_build_fade()

	if start_mode == "arena":
		encounter.start()


func _build_arena_stage() -> void:
	Game.in_hub = false
	Game.run_phase = "arena"
	arena = Arena.new()
	arena.name = "Arena"
	world.add_child(arena)

	var runes := Runes.new()
	runes.name = "Runes"
	world.add_child(runes)

	var braziers := Braziers.new()
	braziers.name = "Braziers"
	world.add_child(braziers)

	var motes := Motes.new()
	motes.name = "Motes"
	world.add_child(motes)

	player = PLAYER_SCENE.instantiate() as Player
	player.position = Vector2(560.0, -40.0)
	world.add_child(player)
	Game.fx_root = world

	encounter = Encounter.new()
	encounter.name = "Encounter"
	add_child(encounter)
	encounter.world = world


func _show_title() -> void:
	_set_background_palette("hub")
	var layer := get_node_or_null("TitleLayer") as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "TitleLayer"
		layer.layer = 50
		add_child(layer)
	title_screen = TitleScreen.new()
	title_screen.name = "TitleScreen"
	layer.add_child(title_screen)
	title_screen.started.connect(_on_title_started)
	title_screen.settings_requested.connect(_on_title_settings_requested)
	hud.visible = false


func _on_title_started() -> void:
	hud.visible = true
	if is_instance_valid(title_screen) and title_screen.resume_requested:
		if not resume_checkpoint():
			return_to_title()
			title_screen.note = "CHECKPOINT UNAVAILABLE / ORIGINAL RETAINED"
	elif start_mode == "hub":
		enter_hub()
	elif start_mode == "arena":
		_set_background_palette("arena")


## Settings lives as one instance under Main, above every other UI layer. The
## caller keeps its pause and focus; this owner only raises and restores it.
func _ensure_settings() -> void:
	if is_instance_valid(settings_screen):
		return
	settings_screen = SettingsScreen.new()
	settings_screen.name = "SettingsScreen"
	add_child(settings_screen)
	settings_screen.closed.connect(_on_settings_closed)


func _settings_open() -> bool:
	return is_instance_valid(settings_screen) and settings_screen.is_open()


## The caller keeps its pause, focus and dirty state. Only its drawing is
## suppressed while Settings is up: the settings page owns the single backdrop,
## so a second full-page mask under it would duplicate text.
func _open_settings(owner_id: String) -> void:
	if _settings_open():
		return
	_settings_owner = owner_id
	match owner_id:
		"title":
			if is_instance_valid(title_screen): title_screen.queue_redraw()
		"pause":
			if is_instance_valid(hud): hud.queue_redraw()
	settings_screen.open()


func _on_title_settings_requested() -> void:
	_open_settings("title")


func _on_hud_settings_requested() -> void:
	_open_settings("pause")


func _on_settings_closed() -> void:
	# Returning restores the exact caller it was raised from; no page swap and
	# no pause toggle happen here.
	var owner_id := _settings_owner
	_settings_owner = ""
	match owner_id:
		"title":
			if is_instance_valid(title_screen): title_screen.queue_redraw()
		"pause":
			if is_instance_valid(hud): hud.queue_redraw()


func return_to_title() -> bool:
	if start_mode != "hub" or not Game.settlement_pending.is_empty():
		return false
	_transition = 0.0
	_pending_checkpoint.clear()
	hud.checkpoint_blocked = false
	hud.paused = false
	var previous := player
	_clear_terrain()
	_purge_world_fx()
	if is_instance_valid(previous): previous.queue_free()
	Game.reset_run()
	Game.fx_root = world
	_show_title()
	# Reached from the pause menu's T, so the player lands on slot choice; the
	# first title of a session still opens on the main view.
	if is_instance_valid(title_screen):
		title_screen.show_saves()
	return true


func _save_checkpoint(kind: String, seed_value := 0) -> bool:
	_pending_checkpoint = RunCheckpoint.capture(Game, kind, seed_value)
	if Profile.save(_pending_checkpoint):
		_pending_checkpoint.clear()
		return true
	hud.checkpoint_blocked = true
	hud._set_paused(true)
	return false


func retry_checkpoint() -> bool:
	if _pending_checkpoint.is_empty() or not Profile.save(_pending_checkpoint):
		return false
	_pending_checkpoint.clear()
	hud.checkpoint_blocked = false
	hud._set_paused(false)
	return true


func resume_checkpoint() -> bool:
	var checkpoint := Profile.run_checkpoint.duplicate(true)
	if not RunCheckpoint.error(checkpoint).is_empty() or not Game.settlement_pending.is_empty(): return false
	var layout := {}
	if checkpoint.kind == "biome_entry":
		layout = Level.route_layout(str(checkpoint.state.run_node_id), int(checkpoint.seed), RunCheckpoint.generator_revision(checkpoint))
		if layout.is_empty(): return false
	var previous := player
	_clear_terrain()
	_purge_world_fx()
	if is_instance_valid(previous): previous.queue_free()
	if not RunCheckpoint.restore(Game, checkpoint): return false
	if checkpoint.kind == "biome_entry":
		start_floor(Game.floor_index, layout)
	else:
		player = PLAYER_SCENE.instantiate() as Player
		world.add_child(player)
		Game.run_phase = "transition"
		enter_passage(false)
	player.weapon_slot = int(checkpoint.weapon_slot)
	player._apply_loadout()
	player.hp = float(checkpoint.hp)
	hud.visible = true
	hud.paused = false
	Game.announce(ContentText.of("UI_CHECKPOINT_RESTORED", "CHECKPOINT RESTORED / SAVE {slot}").format({"slot": Profile.active_slot}), 1.8)
	return true


# --- Meta flow --------------------------------------------------------------
#
# The meta modules are loaded by path rather than preloaded so this file still
# compiles while they are being written, and so a missing module degrades to a
# clear runtime error instead of a parse failure.

func enter_hub() -> void:
	if not Game.retry_settlement():
		_transition = 0.0
		_fade_in()
		return
	_transition = 0.0
	_cleared_floor = false
	get_tree().paused = false
	Engine.time_scale = 1.0
	if is_instance_valid(collector):
		collector.queue_free()
	collector = null
	if hud != null:
		hud.paused = false
	# The boot path already spawned an arena player and the hub builds its own,
	# so the original must be freed BEFORE _clear_terrain() nulls the reference.
	var previous := player
	_clear_terrain()
	if is_instance_valid(previous):
		previous.queue_free()
	# A spitter's glob pool outlives its floor (it is parented to the world, not
	# to the level). A pool that landed in the last second of a floor sat at a
	# floor y that is inside the hub's walkable band and kept ticking 6 damage
	# on the new body with nothing on screen to explain it.
	_purge_world_fx()
	Game.reset_run()
	_set_background_palette("hub")
	var hub_script: Script = _script("res://scripts/meta/hub.gd")
	if hub_script == null:
		push_error("Main: hub.gd missing")
		return
	# Hub owns its own player, walls and HubUi layer, so it is self-contained:
	# nothing here has to build an actor for it.
	hub = hub_script.new()
	hub.name = "Hub"
	world.add_child(hub)
	_terrain = hub
	player = hub.get("player") as Player
	Game.fx_root = hub
	if hub.has_method("setup"):
		hub.setup(Profile.best_floor)
	if hub.has_signal("descend_requested"):
		hub.descend_requested.connect(_on_descend)
	if hub.has_signal("station_opened"):
		hub.station_opened.connect(_on_station_opened)
	_build_meta_screens()
	hud.visible = true
	Game.announce("ASHFALL", 1.2)
	_fade_in()


func _build_meta_screens() -> void:
	# enter_hub() runs on every floor clear and every death, so without this the
	# world accumulated a fresh pair of CanvasLayers per visit (audit_v3 already
	# printed the growth; nothing asserted on it).
	for old in [archive, skill_tree]:
		if is_instance_valid(old):
			old.queue_free()
	archive = null
	skill_tree = null
	# Archives and the skill tree are their own CanvasLayers because they need
	# the full 768x480 and their own cursor geometry.
	var archive_script: Script = _script("res://scripts/ui/archive_screen.gd")
	if archive_script != null:
		archive = archive_script.new()
		archive.name = "ArchiveScreen"
		add_child(archive)
		if archive.has_signal("closed"):
			archive.closed.connect(_on_meta_screen_closed)
	var tree_script: Script = _script("res://scripts/ui/skill_tree.gd")
	if tree_script != null:
		skill_tree = tree_script.new()
		skill_tree.name = "SkillTree"
		add_child(skill_tree)
		if skill_tree.has_signal("closed"):
			skill_tree.closed.connect(_on_meta_screen_closed)


func _on_station_opened(id: String) -> void:
	# A panel opened while another is up would leave two Esc owners and one of
	# them unreachable. The hub already guards the key path; this guards the
	# API path - and it MUST release the freeze the hub applied, or the player is
	# left unable to move until some unrelated panel closes.
	if _any_panel_open():
		if hub != null and hub.has_method("close_station"):
			hub.close_station()
		return
	match id:
		"skill":
			if is_instance_valid(skill_tree):
				skill_tree.open()
			else:
				push_error("Main: required SkillTree is unavailable")
				Game.announce(ContentText.of("UI_SKILL_TREE_UNAVAILABLE", "SKILL TREE UNAVAILABLE"), 1.8, &"error")
				_on_meta_screen_closed()
			return
		"archive":
			if archive != null:
				# The archive owns its three tabs; the hub only picks the door.
				archive.open("enemy")
				return
	# Upgrades and character select live in the hub's own panel.
	var ui_field: Variant = hub.get("ui") if hub != null else null
	if ui_field != null and ui_field.has_method("open_station"):
		ui_field.open_station(id)


func _any_panel_open() -> bool:
	if _settings_open():
		return true
	for screen in [archive, skill_tree, exploration_map, build_screen]:
		if screen != null and screen.has_method("is_open") and screen.is_open():
			return true
	if hub != null and hub.has_method("is_open") and hub.is_open():
		return true
	return false


func _on_meta_screen_closed() -> void:
	if hub != null and hub.has_method("close_station"):
		hub.close_station()


func _on_descend(_floor_index: int) -> void:
	start_node(str(Data.route_graph["start"]))


func start_node(id: String) -> bool:
	var layout := Level.route_layout(id, randi(), Game.generator_revision)
	if layout.is_empty():
		Game.announce(ContentText.of("UI_ROUTE_UNAVAILABLE", "ROUTE UNAVAILABLE"), 1.2, &"error")
		return false
	if not Game.enter_node(id):
		return false
	start_floor(Game.floor_index, layout)
	if start_mode == "hub": _save_checkpoint("biome_entry", int(layout.seed))
	print("ROUTE ENTER ", JSON.stringify({"node":id, "visit":Game.route_history.size(), "seed":layout.seed, "bsc":Game.run_bsc, "keys":Game.run_keys, "runes":Profile.unlocked_runes}))
	return true


func start_floor(floor_index: int, prepared: Dictionary = {}) -> void:
	var level_script: Script = _script("res://scripts/world/level.gd")
	if level_script == null:
		push_error("Main: level.gd missing")
		return
	# Preserve the run's body while replacing terrain and transient effects.
	var previous := player
	var continuing_run := not Game.in_hub and is_instance_valid(previous) and previous.get_parent() == world
	_clear_terrain()
	_purge_world_fx()

	if continuing_run:
		player = previous
	else:
		if is_instance_valid(previous):
			previous.queue_free()
		player = PLAYER_SCENE.instantiate() as Player
		world.add_child(player)
	Game.fx_root = world

	level = level_script.new()
	level.name = "Level"
	world.add_child(level)
	_terrain = level
	if Game.run_node_id.is_empty():
		Game.floor_name = str(Data.floors.get(str(floor_index), {}).get("name", "FLOOR %d" % floor_index))
		Game.start_floor(floor_index)
	else:
		level.route_node = Game.run_node_id
	level.build(floor_index, randi(), prepared)
	_set_background_palette(Game.run_node_id if not Game.run_node_id.is_empty() else "legacy_%d" % floor_index)
	_owed_rewards = 0
	_cleared_floor = false
	if level.has_signal("cleared"):
		level.cleared.connect(_on_floor_cleared)
	if level.has_signal("exit_chosen"):
		level.exit_chosen.connect(_on_exit_chosen)
		level.map_requested.connect(_open_map)
	if level.has_signal("player_died"):
		level.player_died.connect(_on_player_died)
	if level.has_signal("room_cleared"):
		level.room_cleared.connect(_on_room_cleared)
	if level.has_method("start_point"):
		player.relocate(level.start_point())

	# The hub widened the camera limits for its long flat floor; the level has
	# to reset them or the view clamps at the hub's edges.
	var width := 2400.0
	var data: Variant = level.get("data")
	if typeof(data) == TYPE_DICTIONARY and data.has("width"):
		width = float(data["width"])
	# Floor geometry lives at y 60..150 and the vault reaches y -560. The
	# camera clamps its CENTRE, so the bottom limit must be at least one half
	# viewport (240) below the deepest floor or the player renders off-screen.
	player.camera.limit_left = -120
	player.camera.limit_right = int(width) + 120
	# The top limit is COMPUTED from the floor's own highest surface. Annex
	# chambers reach five tiers above a slab, and the camera clamps its CENTRE,
	# so a hardcoded number is a promise that goes stale the first time a template
	# or an annex grows: -820 had 131 px of slack and nothing checked it. Half a
	# viewport is 240/0.86 = 279 px.
	var highest := 0.0
	var rooms: Variant = data.get("rooms", []) if typeof(data) == TYPE_DICTIONARY else []
	for room in (rooms as Array):
		for entry in ((room as Dictionary).get("platforms", []) as Array):
			highest = minf(highest, (entry as Rect2).position.y)
	player.camera.limit_top = int(minf(-600.0, highest - 279.0 - 40.0))
	player.camera.limit_bottom = int(maxf(400, (data["bounds"] as Rect2).end.y + 280)) if data.has("bounds") else 400

	hud.visible = true
	# Route nodes and legacy floors each keep one canonical English name; the
	# display layer resolves the same BIOME_/FLOOR_ rows the HUD uses.
	Game.announce(ContentText.name("biome", Game.run_node_id, Game.floor_name) if not Game.run_node_id.is_empty() else ContentText.name("floor", str(Game.floor_index), Game.floor_name), 1.4)
	_fade_in()


func _on_rooms_cleared_reward() -> void:
	if not Game.run_node_id.is_empty() and Game.run_phase != "biome":
		return
	# Deferred by _on_room_cleared: this pauses the tree, and the room clears
	# inside a physics signal flush.
	if Game.run_over:
		return
	# Headless probes drive the whole run without a UI; the flag they already
	# set for the arena path has to mean the same thing here.
	if Game.floor_rewards_left <= 0:
		return
	# A picker already on screen cannot take a second request, so the owed boon
	# waits in _owed_rewards and is paid from _on_reward_chosen. Bailing out
	# here instead dropped it: two rooms cleared by one finisher wave paid one
	# boon and left floor_rewards_left stuck with no room left to clear.
	if Game.reward_open:
		_owed_rewards += 1
		return
	Game.floor_rewards_left -= 1
	if auto_rewards or Game.auto_choose_rewards:
		Game.grant_random_reward()
		_pay_owed_rewards()
		return
	Game.request_rewards(3)


## Pays boons that arrived while a picker was up. Called after every pick and
## every auto-grant, so the debt can never outlive the floor.
func _pay_owed_rewards() -> void:
	if _owed_rewards <= 0 or Game.run_over:
		return
	if Game.floor_rewards_left <= 0:
		_owed_rewards = 0
		return
	_owed_rewards -= 1
	Game.floor_rewards_left -= 1
	if auto_rewards or Game.auto_choose_rewards:
		Game.grant_random_reward()
		_pay_owed_rewards()
		return
	Game.request_rewards(3)

func _on_room_cleared(_index: int) -> void:
	# Two rooms can clear in the same frame, and both deferred calls land before
	# either picker sets reward_open. Spending the budget here would then pay one
	# boon for two rooms; the decrement therefore lives in the deferred call.
	if Game.floor_rewards_left <= 0 or Game.run_over:
		return
	call_deferred("_on_rooms_cleared_reward")

func _on_exit_chosen(id: String) -> void:
	if id.is_empty() and Game.run_node_id == str(Data.route_graph.final):
		if Game.end_run(true):
			_cleared_floor = true
			_transition = 0.0
		else:
			level._cleared_emitted = false
		return
	if not Game.select_destination(id):
		return
	_on_floor_cleared()


func _on_floor_cleared() -> void:
	if _cleared_floor or Game.run_over or Game.in_hub or (not Game.run_node_id.is_empty() and not Game.exit_selected):
		return
	_cleared_floor = true
	Game.run_phase = "transition"
	if Game.run_node_id.is_empty() and Game.floor_index >= Game.max_floor():
		Game.end_run(true)
		_transition = 3.0
		return
	Game.announce(ContentText.of("UI_ENTERING_PASSAGE", "ENTERING PASSAGE"), 1.6)
	_transition = 1.6


func enter_passage(save_checkpoint := true) -> void:
	if Game.run_phase != "transition" or Game.run_over or not is_instance_valid(player) or player.hp <= 0.0:
		return
	if Game.run_node_id.is_empty():
		enter_hub()
		return
	var body := player
	_clear_terrain()
	_purge_world_fx()
	player = body
	Game.run_phase = "passage"
	_set_background_palette("passage")
	var script := _script("res://scripts/meta/passage.gd")
	passage = script.new()
	world.add_child(passage)
	_terrain = passage
	passage.collector_requested.connect(_open_collector)
	passage.service_requested.connect(_open_service)
	passage.continued.connect(_on_passage_continued)
	player.traversal_world = null
	player.relocate(Vector2(96, -24))
	player.camera.limit_left = 0
	player.camera.limit_right = int(passage.WIDTH)
	player.camera.limit_top = -400
	player.camera.limit_bottom = 180
	_cleared_floor = false
	_owed_rewards = 0
	Game.hub_return_in = 0.0
	_fade_in()
	if save_checkpoint: _save_checkpoint("passage")


func _on_passage_continued() -> void:
	if Game.run_phase != "passage" or Game.run_over or not Game.exit_selected:
		return
	var id := Game.pending_destination
	if id.is_empty():
		if not bool(Data.biomes["biomes"].get(Game.run_node_id, {}).get("slice_end", false)):
			return
		Game.slice_complete = true
		Game.end_run(false, true)
		Game.announce(ContentText.of("UI_ROUTE_SLICE_COMPLETE", "ROUTE SLICE COMPLETE"), 2.2)
		_transition = 2.2
		return
	start_node(id)


func _open_map(teleport_mode := false) -> void:
	if Game.run_over or Game.run_phase not in ["biome", "passage"] or _transition > 0 or get_tree().paused or Game.reward_open or _any_panel_open() or is_instance_valid(collector) or not is_instance_valid(player) or player.hp <= 0:
		return
	exploration_map.open(level if Game.run_phase == "biome" else passage, teleport_mode)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		_open_map()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("heal") and not get_tree().paused and not Game.reward_open and not _any_panel_open() and not is_instance_valid(collector):
		Game.drink_flask()
		get_viewport().set_input_as_handled()


func _open_collector() -> void:
	_open_service("collector")


func _open_service(id: String) -> void:
	if is_instance_valid(collector) or _any_panel_open():
		return
	if id not in ["collector", "mutation", "craft", "forge", "challenge"] or (id == "forge" and not Game.boss_passage()):
		return
	var collector_script := _script("res://scripts/meta/collector.gd")
	if collector_script == null:
		push_error("Main: collector.gd missing")
		return
	collector = collector_script.new()
	collector.service = id
	collector.name = "Collector"
	add_child(collector)
	collector.continued.connect(_on_collector_continued)
	# Opening an in-place service must not restart the black scene-change veil.
	_fade_to(0.0, 0.24)


func _on_collector_continued() -> void:
	collector = null
	if is_instance_valid(player):
		player.suppress_actions()


func _on_player_died() -> void:
	_cleared_floor = false
	Game.end_run(false)
	_transition = 2.2


func _process(delta: float) -> void:
	if _transition <= 0.0:
		Game.hub_return_in = 0.0
		return
	_transition -= delta
	Game.hub_return_in = maxf(0.0, _transition)
	# Fall to black over the last fifth of a second instead of cutting: the
	# floor is torn down between frames and the swap used to read as a dropped
	# frame rather than as leaving a place.
	if not _fade_armed and _transition <= 0.2:
		_fade_armed = true
		_fade_out(0.2)
	if _transition <= 0.0 and start_mode == "hub":
		if _cleared_floor and not Game.run_over:
			enter_passage()
		else:
			enter_hub()


## Scene-change veil. It never pauses the tree and the tween ignores
## time_scale, so a hitstop cannot freeze the screen half-faded.
func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.name = "FadeLayer"
	layer.layer = 45
	add_child(layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(MathArt.INK, 0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade_rect)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _fade_in(duration := 0.24) -> void:
	_fade_armed = false
	if _fade_rect == null:
		return
	# Snap to black, then open: a new floor is revealed, never cut to.
	_fade_rect.color.a = 1.0
	_fade_to(0.0, duration)


func _fade_out(duration := 0.2) -> void:
	_fade_to(1.0, duration)


func _fade_to(alpha: float, duration: float) -> void:
	if _fade_rect == null:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_ignore_time_scale(true)
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_fade_rect, "color:a", alpha, duration)


## Anything still flying belongs to the floor being left. Hub._build_player()
## does this on the way in; a retry never passes through the hub.
func _purge_world_fx() -> void:
	for node in world.get_children():
		if node is Projectile or node is FunctionWave:
			node.set_physics_process(false)
			if node is Area2D:
				(node as Area2D).monitoring = false
			node.queue_free()
	for node in world.get_children():
		if node.is_in_group("hazard_pool"):
			node.queue_free()


## Explicit pause-menu abandonment returns to the start, never this biome.
func restart_attempt() -> void:
	if start_mode != "hub":
		get_tree().reload_current_scene()
		return
	if not Game.in_hub and not Game.run_over:
		Game.end_run(false, true)
	enter_hub()


func _clear_terrain() -> void:
	if is_instance_valid(collector):
		collector.queue_free()
		collector = null
		get_tree().paused = false
	if is_instance_valid(build_screen) and build_screen.is_open():
		build_screen.close()
	if is_instance_valid(exploration_map) and exploration_map.is_open():
		exploration_map.close()
	if is_instance_valid(player):
		player.traversal_world = null
	if is_instance_valid(_terrain):
		_terrain.process_mode = Node.PROCESS_MODE_DISABLED
		_terrain.queue_free()
	_terrain = null
	hub = null
	level = null
	passage = null
	player = null


func _script(path: String) -> Script:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Script


func _on_rewards_requested(choices: Array) -> void:
	reward_screen.open(choices)


func _on_reward_chosen(_id: String) -> void:
	# The arena director is the only thing waiting on a pick; on a floor the
	# picker unpauses itself in RewardScreen._pick(). Calling into a null
	# encounter here is what would have crashed the first cleared room.
	if encounter != null and is_instance_valid(encounter):
		encounter.resume_after_reward()
	_pay_owed_rewards()


func _add_fullscreen_shader_layer(layer_index: int, shader: Shader) -> void:
	var layer := CanvasLayer.new()
	layer.layer = layer_index
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color.WHITE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = shader
	if shader == BACKGROUND_SHADER:
		_background_material = material
	rect.material = material
	layer.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _set_background_palette(id: String) -> void:
	if _background_material == null:
		return
	_background_material.set_shader_parameter("shade_top", MathArt.biome_color(id, "background_top"))
	_background_material.set_shader_parameter("shade_mid", MathArt.biome_color(id, "background_mid"))
	_background_material.set_shader_parameter("shade_bottom", MathArt.biome_color(id, "background_bottom"))
	_background_material.set_shader_parameter("light_color", MathArt.biome_color(id, "accent"))
