extends Node2D
## Boots the prototype: world, actors, HUD, background and wave director.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const BACKGROUND_SHADER: Shader = preload("res://shaders/background.gdshader")
const VIGNETTE_SHADER: Shader = preload("res://shaders/vignette.gdshader")
const BLOOM_SHADER: Shader = preload("res://shaders/bloom.gdshader")

@export var skip_title := false

var world: Node2D
var arena: Arena
var player: Player
var encounter: Encounter
var hud: Hud
var reward_screen: RewardScreen
var title_screen: TitleScreen


func _ready() -> void:
	randomize()
	Game.reset_run()

	world = Node2D.new()
	world.name = "World"
	add_child(world)

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

	encounter.start()


func _on_title_started() -> void:
	hud.visible = true


func _on_rewards_requested(choices: Array) -> void:
	reward_screen.open(choices)


func _on_reward_chosen(_id: String) -> void:
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
