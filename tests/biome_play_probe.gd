extends Node
## Real 120-Hz body movement proves the fork; later relocations isolate abilities.
var _main: Node
var _checks := 0
var _fails := 0
var _capture := false



func _ready() -> void:
	if not Data.is_node_ready():
		await Data.ready
	if not Interface.is_node_ready():
		await Interface.ready
	if not Sfx.is_node_ready():
		await Sfx.ready
	TranslationServer.set_locale("en")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = $Main
	assert(Profile.SAVE_PATH != "user://ashfall_profile.json")
	_capture = DisplayServer.get_name() != "headless" or OS.get_cmdline_user_args().has("--capture")
	Profile.reset_profile()
	await get_tree().process_frame
	_main.enter_hub()
	var old_spawns: Array = Data.room_modules["modules"]["entry"]["spawns"]
	var hub_body := Game.player
	Data.room_modules["modules"]["entry"].erase("spawns")
	_check(not _main.start_node("ash_gate") and Game.in_hub and Game.route_history.is_empty() and Game.player == hub_body, "invalid schema leaves Hub and run state untouched")
	Data.room_modules["modules"]["entry"]["spawns"] = old_spawns
	var socket: Dictionary = Data.room_modules["modules"]["entry"]["sockets"]["east"]
	var old_point: Array = socket["point"].duplicate()
	socket["point"][1] += 1
	_check(not _main.start_node("ash_gate") and Game.in_hub and Game.route_history.is_empty() and Game.player == hub_body, "incompatible geometry refuses before transition")
	socket["point"] = old_point
	_main._on_descend(1)
	await _frames(20)
	Game.player.invuln = 1000
	Game.floor_rewards_left = 0
	var level: Node = _main.level
	_check(str(level.data.get("generator_revision", "")) == BiomeGen.LATEST_REVISION, "first formal route uses the latest spatial generator")
	var ids: Dictionary = level.data["room_ids"]
	_check(level.map_snapshot()["rooms"].size() == 1, "fresh map hides all unknown rooms")
	var split: Dictionary = level.data.rooms[ids["split"]]
	var stairs: Array = split.platforms.duplicate()
	stairs.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.y > b.position.y)
	await _walk((stairs[0] as Rect2).position.x + 40)
	for stair: Rect2 in stairs:
		var landing_x := clampf(Game.player.global_position.x, stair.position.x + 40, stair.end.x - 40)
		await _hop(landing_x, stair.position.y)
	var upper: Dictionary = level.data.rooms[ids["upper"]]
	await _walk((upper.rect as Rect2).get_center().x)
	_check(level._room_entered[ids["upper"]] and not level._room_entered[ids["lower"]], "actual stair jumps enter upper fork without entering overlapping lower room")
	await _shot("upper_fork")
	var merge: Dictionary = level.data.rooms[ids["merge"]]
	await _walk((merge.rect as Rect2).position.x + 100)
	_check(level._room_entered[ids["merge"]], "upper fork physically rejoins main graph")
	await _key(KEY_TAB)
	_check(_main.exploration_map.is_open() and get_tree().paused and not Game.player.can_process(), "Tab opens discovery map and freezes player processing")
	var at := Game.player.global_position
	var hp := Game.player.hp
	var charges := Game.flask_charges
	var knives := Game.player.knife_charges
	await _frames(24) # Outlast the action lock; pause must freeze the world itself.
	for code in [KEY_F, KEY_H, KEY_J, KEY_K, KEY_L, KEY_SPACE, KEY_R, KEY_ENTER]:
		await _key(code)
	_check(Game.player.global_position == at and Game.player.hp == hp and Game.flask_charges == charges and Game.player.knife_charges == knives and not Game.exit_selected, "map consumes healing/combat/jump/interaction/Enter: pos %s -> %s, hp %.1f -> %.1f, flask %d -> %d, knives %d -> %d, exit %s, paused %s" % [str(at), str(Game.player.global_position), hp, Game.player.hp, charges, Game.flask_charges, knives, Game.player.knife_charges, str(Game.exit_selected), str(get_tree().paused)])
	await _shot("discovery_map")
	await _key(KEY_RIGHT)
	await _shot("world_map")
	await _key(KEY_ESCAPE)
	_check(not get_tree().paused and not _main.hud.paused, "map Esc closes only map")

	# Ability isolation uses world positions; it is not evidence of earning these in the full world.
	await _place(Vector2(24, 126))
	Input.action_press("move_left")
	Input.action_press("climb_up")
	await _frames(70)
	_check(Game.player.global_position.y > -80, "fresh profile cannot climb to wall vault")
	_release()
	await _fixture_rune("climb_rune", int(ids["upper"]))
	await _place(Vector2(24, 126))
	Input.action_press("move_left")
	Input.action_press("climb_up")
	await _climb_to(-160)
	_check(Game.player.global_position.y < -150 and level._room_entered[ids["wall_vault"]], "Climb Rune physically traverses wall at %s, state %d, wall %s" % [str(Game.player.global_position), Game.player.state, str(Game.player.is_on_wall())])
	_release()
	await _key(KEY_SPACE)
	await _frames(20)
	_check(Game.player.state != Player.State.CLIMB and Game.player.global_position.x > 20, "wall jump detaches from wall")

	var vine_stand := Vector2.ZERO
	for edge: Dictionary in level.data.graph:
		if edge.mode == "vine" and edge.to == "canopy_vault":
			vine_stand = upper.sockets[edge.from_socket].stand
	_check(vine_stand != Vector2.ZERO, "Canopy source uses generated socket landing")
	var canopy_floor: float = level.data.rooms[ids["canopy_vault"]].rect.position.y
	var upper_floor: float = upper.rect.position.y
	await _place(vine_stand)
	Input.action_press("climb_up")
	await _frames(100)
	_release()
	_check(not level._room_entered[ids["canopy_vault"]], "Canopy vault remains inaccessible before Rune")
	Profile.unlock_rune("canopy_rune")
	await _place(vine_stand)
	Input.action_press("climb_up")
	await _climb_to(canopy_floor - 25)
	_release()
	_check(level._room_entered[ids["canopy_vault"]] and Game.player.global_position.y < canopy_floor + 2, "Canopy Rune climbs vine into vault")
	await _shot("canopy_vault")
	# Finish the climb, release W on the deck, then descend using the real S key.
	Input.action_press("climb_up")
	await _frames(24)
	_release()
	await _frames(12)
	var top_y := Game.player.global_position.y
	_check(Game.player.is_on_floor() and top_y < canopy_floor - 18, "vine climb finishes on the upper deck")
	var down := InputEventKey.new()
	down.physical_keycode = KEY_S
	down.keycode = KEY_S
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(45)
	down = down.duplicate()
	down.pressed = false
	Input.parse_input_event(down)
	await get_tree().process_frame
	await _frames(2) # Observe the released key after Godot has consumed its buffered event.
	_check(Game.player.global_position.y > top_y + 48 and Game.player.state == Player.State.CLIMB, "S alone descends through vine's upper one-way deck")
	var resting_y := Game.player.global_position.y
	await _frames(16)
	_check(absf(Game.player.global_position.y - resting_y) < 2, "releasing S holds position on vine: %.3f -> %.3f state=%d velocity=%s" % [resting_y, Game.player.global_position.y, Game.player.state, Game.player.velocity])
	await _shot("canopy_s_descent")
	Input.action_press("climb_down")
	await _frames(160)
	_release()
	await _frames(28)
	_check(Game.player.global_position.y > upper_floor - 74 and Game.player.is_on_floor() and Game.player.state != Player.State.CLIMB and Game.player.get_collision_mask_value(4) and Game.player.get_collision_mask_value(1) and Game.player.drop_through_t == 0, "vine descent catches lower landing and restores one-way collision")
	await _shot("canopy_descent")

	var seal: Node = level._gates["ground_seal"]
	await _dive()
	_check(not seal.unlocked and Game.player.global_position.y < 160, "unupgraded dive cannot break marked ground")
	await _fixture_rune("ground_rune", int(ids["lower"]))
	await _dive()
	_check(seal.unlocked and level._room_entered[ids["ground_vault"]], "Ground Rune dive opens physical floor and reaches vault")
	await _shot("ground_vault")
	await _walk(736)
	_check(level._active_pads.has("ground_vault"), "physically reached checkpoint activates")
	await _key(KEY_R)
	_check(_main.exploration_map.is_open() and not _main.exploration_map._source.is_empty(), "checkpoint interaction enables map travel")
	await _key(KEY_ENTER)
	await _frames(4)
	_check(not _main.exploration_map.is_open() and Game.player.global_position.distance_to(level.data["start"]) < 20 and Game.player.velocity.length() < 60 and Game.player.drop_through_t == 0, "checkpoint return resets velocity and traversal state")

	_check(Game.select_destination("silt_cistern"), "fixture selects legal Cistern edge")
	Game.run_phase = "passage"
	_check(_main.start_node("silt_cistern"), "fixture enters Cistern")
	await _frames(20)
	Game.player.invuln = 1000
	Game.floor_rewards_left = 0
	level = _main.level
	var source: Dictionary = {}
	for pad: Dictionary in level.data["pads"]:
		if str(pad["kind"]) == "phase":
			source = pad
			break
	var target := _pad(level, str(source["pair"]))
	await _place(source["pos"])
	await _key(KEY_R)
	_check(Game.player.global_position.distance_to(source["pos"]) < 12, "Phase pair refuses without Rune")
	await _fixture_rune("phase_rune", int(level.data["rune_room"]))
	await _place(source["pos"])
	var blocker := StaticBody2D.new()
	blocker.collision_layer = Layers.WORLD
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(36, 60)
	shape.shape = box
	blocker.add_child(shape)
	blocker.position = target["pos"]
	level.add_child(blocker)
	await _frames(2)
	_check(not level.teleport_to(str(target["id"]), str(source["id"])), "occupied landing refuses teleport")
	blocker.queue_free()
	await _frames(3)
	hp = Game.player.hp
	var cells := Game.run_cells
	await _key(KEY_R)
	await _frames(3)
	_check(Game.player.global_position.distance_to(target["pos"]) < 12 and Game.player.hp == hp and Game.run_cells == cells, "Phase Rune R travels safely without changing resources")

	_check(Game.select_destination("stone_ramparts"), "fixture selects Ramparts")
	Game.run_phase = "passage"
	_check(_main.start_node("stone_ramparts"), "fixture enters Ramparts")
	await _frames(20)
	Game.player.invuln = 1000
	Game.floor_rewards_left = 0
	level = _main.level
	var gate: Node = level._gates["rampart_lock"]
	var gate_rect: Rect2 = gate.spec["rect"]
	await _place(Vector2(gate_rect.position.x - 45, 126))
	Input.action_press("move_right")
	await _frames(40)
	_release()
	await _key(KEY_R)
	_check(not gate.unlocked and Game.player.global_position.x < gate_rect.position.x, "missing key physically blocks required door")
	_check(level._interaction_hint(Game.player.global_position).contains("Rampart Key"), "key door explains its physical lock")
	await _shot("key_door_locked")
	await _place(level.data["key"]["pos"])
	await _key(KEY_R)
	_check(Game.run_keys.has("rampart_key"), "world key requires interaction")
	await _place(Vector2(gate_rect.position.x - 45, 126))
	await _key(KEY_R)
	await _frames(3)
	_check(gate.unlocked and not Game.run_keys.has("rampart_key") and gate.try_open(), "key is consumed once; repeated opening is idempotent")
	await _walk(gate_rect.end.x + 60)
	_check(Game.player.global_position.x > gate_rect.end.x, "opened key door admits actual body")
	await _shot("key_door")
	await _deck_frame()
	print("BIOME PLAY %s (%d checks, %d failures)" % ["OK" if _fails == 0 else "FAILED", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_main) or not is_instance_valid(_main.level):
		return
	for enemy: Enemy in _main.level._alive:
		enemy.set_physics_process(false)


func _walk(x: float) -> void:
	for n in 500:
		_drive(x)
		if n > 8 and Game.player.is_on_floor() and absf(Game.player.velocity.x) < 1:
			Input.action_press("jump")
		else:
			Input.action_release("jump")
		await get_tree().physics_frame
		if absf(Game.player.global_position.x - x) < 8:
			break
	_release()
	await _frames(12)
	_check(absf(Game.player.global_position.x - x) < 26, "walk %.0f reached %s" % [x, str(Game.player.global_position)])


func _hop(x: float, floor_y: float) -> void:
	# A fresh physics tick separates the previous release from this press.
	await _frames(2)
	Input.action_press("jump")
	for n in 110:
		_drive(x)
		await get_tree().physics_frame
		if n > 8 and Game.player.is_on_floor() and absf(Game.player.global_position.y + 23 - floor_y) < 8:
			break
	_release()
	_check(absf(Game.player.global_position.y + 23 - floor_y) < 8, "jump reaches tier %.0f at %s" % [floor_y, str(Game.player.global_position)])


func _climb_to(y: float) -> void:
	for n in 240:
		await get_tree().physics_frame
		if Game.player.global_position.y < y:
			return


func _drive(x: float) -> void:
	var delta := x - Game.player.global_position.x
	Input.action_release("move_left")
	Input.action_release("move_right")
	if absf(delta) > 12:
		Input.action_press("move_right" if delta > 0 else "move_left")


func _release() -> void:
	for action in ["move_left", "move_right", "jump", "drop", "climb_up", "climb_down"]:
		Input.action_release(action)


func _place(at: Vector2) -> void:
	_release()
	Game.player.relocate(at)
	await _frames(18)


func _dive() -> void:
	await _place(Vector2(960, 0))
	Input.action_press("drop")
	await _key(KEY_SPACE)
	await _frames(48)
	_release()


func _fixture_rune(id: String, index: int) -> void:
	var level: Node = _main.level
	# Climb/Ground sources are debug guard fixtures until their L5/L7 biomes ship.
	level._rune_room = index
	level.data["rune"] = id
	var rect: Rect2 = level.data["rooms"][index]["rect"]
	await _place(rect.position + Vector2(320, -24))
	_check(not Profile.unlocked_runes.has(id) and not is_instance_valid(level.rune_pickup), "entering guard room does not grant " + id)
	for enemy: Enemy in level._alive.duplicate():
		if int(enemy.get_meta("room", -1)) == index:
			enemy.take_hit({"damage": 1.0e6, "crit": true, "source_pos": enemy.position - Vector2(40, 0)})
	Combat.cancel_hitstop()
	await _frames(4)
	_check(is_instance_valid(level.rune_pickup), "guard reveals real " + id + " pickup")
	await _place(level.rune_pickup.position)
	await _key(KEY_R)
	await _frames(2)
	_check(Profile.unlocked_runes.has(id), "R picks up " + id)


## Same frame, same deterministic formal room: the latest spatial generator's
## solid ground and one genuine one-way deck. One relocation is fixture setup;
## every motion below comes from real input, never injected velocity.
func _deck_frame() -> void:
	var level: Node = _main.level
	_check(str(level.data.get("generator_revision", "")) == BiomeGen.LATEST_REVISION, "deck frame samples the latest formal revision")
	var chosen := {}
	for entry: Dictionary in level.data.rooms:
		var solid := Rect2()
		for rect: Rect2 in entry["ground"]:
			if rect.size.y <= 32.0 and rect.size.x > solid.size.x:
				solid = rect
		var oneway := Rect2()
		var flags: Array = entry["oneway"]
		for i in (entry["platforms"] as Array).size():
			var deck: Rect2 = entry["platforms"][i]
			# Latest schema: ground[] is solid, platforms[i] is one-way here.
			if bool(flags[i]) and deck.size.x >= 80.0 and deck.position.y < solid.position.y - 40.0 and solid.position.y - deck.position.y < 100.0 and deck.size.x > oneway.size.x:
				oneway = deck
		var overlap := minf(solid.end.x, oneway.end.x) - maxf(solid.position.x, oneway.position.x)
		if overlap >= 100.0:
			chosen = {"solid": solid, "oneway": oneway}
			break
	if chosen.is_empty():
		_check(false, "formal room draws solid ground and a one-way deck within jump reach")
		return
	var solid: Rect2 = chosen["solid"]
	var oneway: Rect2 = chosen["oneway"]
	var body: Player = Game.player
	var x := clampf(oneway.get_center().x, solid.position.x + 60.0, solid.end.x - 60.0)
	await _place(Vector2(x, solid.position.y - 40.0))
	_check(body.is_on_floor() and absf(body.global_position.y + 23.0 - solid.position.y) < 3.0, "body lands on the room's solid ground")
	var canvas: Transform2D = level.get_global_transform_with_canvas()
	var view := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	_check(view.has_point(canvas * solid.get_center()) and view.has_point(canvas * oneway.get_center()), "solid ground and one-way deck share one captured frame")
	await _shot("one_way_pair")
	# Real jump: a one-way deck lets the body rise through from below.
	Input.action_press("jump")
	var peak := body.global_position.y
	for n in 30:
		await get_tree().physics_frame
		peak = minf(peak, body.global_position.y)
	Input.action_release("jump")
	_check(peak < oneway.position.y - 6.0, "real jump rises through the one-way deck: peak %.1f deck %.1f" % [peak, oneway.position.y])
	await _frames(60)
	_check(body.is_on_floor() and absf(body.global_position.y + 23.0 - oneway.position.y) < 3.0, "the same fall lands on the one-way deck")
	# Real S+Space drop-through on the one-way deck.
	Input.action_press("drop")
	await _frames(2)
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	await _frames(60)
	Input.action_release("drop")
	_check(body.global_position.y > oneway.end.y + 4.0, "S+Space drops through the one-way deck")
	_check(body.is_on_floor() and absf(body.global_position.y + 23.0 - solid.position.y) < 3.0, "the solid ground catches the drop")
	# The same S+Space on solid ground cannot pass: solid blocks it.
	Input.action_press("drop")
	await _frames(2)
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	await _frames(40)
	Input.action_release("drop")
	_check(body.is_on_floor() and absf(body.global_position.y + 23.0 - solid.position.y) < 3.0, "S+Space cannot drop through solid ground")
	_release()


func _pad(level: Node, id: String) -> Dictionary:
	for pad: Dictionary in level.data["pads"]:
		if str(pad["id"]) == id:
			return pad
	return {}


func _key(code: int) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await get_tree().process_frame


func _frames(count: int) -> void:
	for n in count:
		await get_tree().physics_frame


func _shot(label: String) -> void:
	if not _capture:
		return
	var dir := "res://output/screenshots/biome"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/" + label + ".png")


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("BIOME PLAY FAIL: " + message)
		get_tree().quit(1)
