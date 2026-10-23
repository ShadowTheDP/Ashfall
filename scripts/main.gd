extends Node2D
## Boots the prototype: world, actors, HUD, background and wave director.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const BACKGROUND_SHADER: Shader = preload("res://shaders/background.gdshader")
const VIGNETTE_SHADER: Shader = preload("res://shaders/vignette.gdshader")

var world: Node2D
var arena: Arena
var player: Player
var encounter: Encounter
var hud: Hud


func _ready() -> void:
	randomize()
	Game.reset_run()

	world = Node2D.new()
	world.name = "World"
	add_child(world)

	arena = Arena.new()
	arena.name = "Arena"
	world.add_child(arena)

	var motes := Motes.new()
	motes.name = "Motes"
	world.add_child(motes)

	player = PLAYER_SCENE.instantiate() as Player
	player.position = Vector2(230.0, -40.0)
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

	_add_fullscreen_shader_layer(-10, BACKGROUND_SHADER)
	_add_fullscreen_shader_layer(20, VIGNETTE_SHADER)

	encounter.start()


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
