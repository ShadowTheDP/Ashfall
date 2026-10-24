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
var _terrain: Node = null
var _transition := 0.0


func _ready() -> void:
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
		var title_layer := CanvasLayer.new()
		title_layer.name = "TitleLayer"
		title_layer.layer = 50
		add_child(title_layer)
		title_screen = TitleScreen.new()
		title_screen.name = "TitleScreen"
		title_layer.add_child(title_screen)
		title_screen.started.connect(_on_title_started)
		hud.visible = false

	var screen_fx_layer := CanvasLayer.new()
	screen_fx_layer.name = "ScreenFxLayer"
	screen_fx_layer.layer = 25
	add_child(screen_fx_layer)
	Game.screen_fx_root = screen_fx_layer

	_add_fullscreen_shader_layer(-10, BACKGROUND_SHADER)
	_add_fullscreen_shader_layer(15, BLOOM_SHADER)
	_add_fullscreen_shader_layer(20, VIGNETTE_SHADER)

	if start_mode == "arena":
		encounter.start()


func _build_arena_stage() -> void:
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


func _on_title_started() -> void:
	hud.visible = true
	if start_mode == "hub":
		enter_hub()


# --- Meta flow --------------------------------------------------------------
#
# The meta modules are loaded by path rather than preloaded so this file still
# compiles while they are being written, and so a missing module degrades to a
# clear runtime error instead of a parse failure.

func enter_hub() -> void:
	# The boot path already spawned an arena player and the hub builds its own,
	# so the original must be freed BEFORE _clear_terrain() nulls the reference.
	var previous := player
	_clear_terrain()
	if is_instance_valid(previous):
		previous.queue_free()
	Game.go_to_hub()
	Game.reset_run()
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


func _build_meta_screens() -> void:
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
	# API path.
	if _any_panel_open():
		return
	match id:
		"skill":
			if skill_tree != null:
				skill_tree.open()
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
	for screen in [archive, skill_tree]:
		if screen != null and screen.has_method("is_open") and screen.is_open():
			return true
	if hub != null and hub.has_method("is_open") and hub.is_open():
		return true
	return false


func _on_meta_screen_closed() -> void:
	if hub != null and hub.has_method("close_station"):
		hub.close_station()


func _on_descend(floor_index: int) -> void:
	# A fresh profile has best_floor 0; the first door still has to lead
	# somewhere, so the descent clamps to floor 1.
	start_floor(maxi(1, floor_index))


func start_floor(floor_index: int) -> void:
	var level_script: Script = _script("res://scripts/world/level.gd")
	if level_script == null:
		push_error("Main: level.gd missing")
		return
	_clear_terrain()

	player = PLAYER_SCENE.instantiate() as Player
	world.add_child(player)
	Game.fx_root = world

	level = level_script.new()
	level.name = "Level"
	world.add_child(level)
	_terrain = level
	Game.floor_name = str(Data.floors.get(str(floor_index), {}).get("name", "FLOOR %d" % floor_index))
	Game.start_floor(floor_index)
	level.build(floor_index, randi())
	if level.has_signal("cleared"):
		level.cleared.connect(_on_floor_cleared)
	if level.has_signal("player_died"):
		level.player_died.connect(_on_player_died)
	if level.has_signal("room_cleared"):
		level.room_cleared.connect(_on_room_cleared)
	if level.has_method("start_point"):
		player.position = level.start_point()

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
	player.camera.limit_top = -600
	player.camera.limit_bottom = 400

	hud.visible = true
	Game.announce(Game.floor_name, 1.4)


func _on_rooms_cleared_reward() -> void:
	# Deferred by _on_room_cleared: this pauses the tree, and the room clears
	# inside a physics signal flush.
	if Game.run_over or Game.reward_open:
		return
	# Headless probes drive the whole run without a UI; the flag they already
	# set for the arena path has to mean the same thing here.
	if auto_rewards or Game.auto_choose_rewards:
		Game.grant_random_reward()
		return
	Game.request_rewards(3)

func _on_room_cleared(_index: int) -> void:
	if Game.floor_rewards_left <= 0 or Game.run_over or Game.reward_open:
		return
	Game.floor_rewards_left -= 1
	call_deferred("_on_rooms_cleared_reward")

func _on_floor_cleared() -> void:
	Game.finish_floor()
	if Game.floor_index >= Game.max_floor():
		Game.end_run(true)
		_transition = 3.0
		return
	Game.announce("FLOOR CLEARED", 1.6)
	_transition = 1.6


func _on_player_died() -> void:
	Game.end_run(false)
	_transition = 2.2


func _process(delta: float) -> void:
	if _transition <= 0.0:
		return
	_transition -= delta
	if _transition <= 0.0 and start_mode == "hub":
		enter_hub()


func _clear_terrain() -> void:
	if is_instance_valid(_terrain):
		_terrain.queue_free()
	_terrain = null
	hub = null
	level = null
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


func _add_fullscreen_shader_layer(layer_index: int, shader: Shader) -> void:
	var layer := CanvasLayer.new()
	layer.layer = layer_index
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color.WHITE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = shader
	rect.material = material
	layer.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
