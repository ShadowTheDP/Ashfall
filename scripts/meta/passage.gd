class_name Passage
extends Node2D
## Services between the biome exit and its already selected destination.
signal collector_requested
signal service_requested(id: String)
signal continued

## English display content for service ids, which are machine values. CSVs
## replace it once loaded; collector reuses it for its page heading.
const SERVICE_NAME_EN := {
	"collector": "Collector", "mutation": "Mutation", "craft": "Craft",
	"forge": "Forge", "challenge": "Challenge", "fountain": "Fountain",
	"continue": "Continue",
}

const WIDTH := 1440.0 * MathArt.PHI
const COLLECTOR_X := 144.0 * MathArt.PHI
const MUTATION_X := COLLECTOR_X * 2.0
const CRAFT_X := COLLECTOR_X * 3.0
const FORGE_X := COLLECTOR_X * 4.0
const CHALLENGE_X := COLLECTOR_X * 5.0
const FOUNTAIN_X := WIDTH * MathArt.INV_PHI
const EXIT_X := WIDTH - 144.0
const REACH := 70.0
var _far := MathArt.biome_color("passage", "far")
var _stone := MathArt.biome_color("passage", "stone")
var _edge := MathArt.biome_color("passage", "edge")


func _ready() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	for rect in [Rect2(-32, 0, WIDTH + 64, 160), Rect2(-32, -300, 32, 300), Rect2(WIDTH, -300, 32, 300)]:
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		collision.shape = shape
		collision.position = rect.get_center()
		body.add_child(collision)
	add_child(body)


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if Game.run_over or Game.run_phase != "passage" or not is_instance_valid(Game.player) or Game.player.hp <= 0:
		return
	if not Interface.pressed(event, &"interact"):
		return
	var at := Game.player.global_position
	if absf(at.y + 24) > REACH:
		return
	if absf(at.x - COLLECTOR_X) < REACH:
		Game.player.suppress_actions()
		collector_requested.emit()
	elif absf(at.x - FOUNTAIN_X) < REACH:
		Game.player.suppress_actions()
		var restored := Game.refill_flask()
		if restored:
			Game.announce(ContentText.of("UI_PASSAGE_RESTORED", "Health and flask restored"), 1.8)
		elif not Profile.last_save_error.is_empty():
			# Actionable prefix, raw diagnostic reason; severity travels as a kind.
			Game.announce(ContentText.of("UI_ERR_SAVE_FAILED", "Save failed") + ": " + Profile.last_save_error, 1.8, &"error")
		else:
			Game.announce(ContentText.of("UI_PASSAGE_FOUNTAIN_USED", "Fountain already used"), 1.8)
	elif absf(at.x - EXIT_X) < REACH and Game.exit_selected:
		Game.player.suppress_actions()
		continued.emit()
	else:
		var found := false
		for station in _stations():
			if station[1] in ["mutation", "craft", "forge", "challenge"] and absf(at.x - float(station[0])) < REACH:
				Game.player.suppress_actions()
				service_requested.emit(str(station[1]))
				found = true
				break
		if not found:
			return
	get_viewport().set_input_as_handled()


## Station display name: the service id stays a machine value, never shown raw.
static func service_name(id: String) -> String:
	return ContentText.name("service", id, str(SERVICE_NAME_EN.get(id, "")))


func _stations() -> Array:
	var stations := [[COLLECTOR_X, "collector"], [MUTATION_X, "mutation"], [CRAFT_X, "craft"], [CHALLENGE_X, "challenge"], [FOUNTAIN_X, "fountain"], [EXIT_X, "continue"]]
	if Game.boss_passage():
		stations.append([FORGE_X, "forge"])
	return stations


func map_snapshot() -> Dictionary:
	var markers: Array = []
	for service in _stations():
		# Service stations are places, not traversal gates: any non-teleport,
		# non-exit kind draws as a place ring, and only exits machine-decode reason.
		markers.append({"pos": Vector2(float(service[0]), -24), "kind": "gate", "label": service_name(str(service[1])).to_upper(), "reason": ContentText.of("UI_PASSAGE_MARK_USED", "Used").to_upper() if service[1] == "fountain" and Game.passage_claims.has("fountain") else ""})
	return {"rooms": [{"id": "passage", "bounds": Rect2(0, -320, WIDTH, 320), "cleared": true}], "edges": [], "pads": [], "markers": markers, "player": Game.player.global_position, "name": ContentText.of("UI_PASSAGE_MAP_NAME", "Passage").to_upper()}


func _draw() -> void:
	var font := MathArt.ui_font()
	MathArt.px_rect(self, Rect2(0, -320, WIDTH, 320), _far)
	MathArt.line(self, Vector2(0, 0), Vector2(WIDTH, 0), _edge, 3.0)
	for station in _stations():
		var x := float(station[0])
		var near: bool = is_instance_valid(Game.player) and Game.player.global_position.distance_to(Vector2(x, -24)) < REACH
		var shade := MathArt.HEAL if station[1] == "fountain" else (MathArt.CELL if station[1] == "collector" else (MathArt.TACTICS if station[1] == "mutation" else MathArt.ACCENT))
		if not near:
			shade = shade.darkened(0.20)
		MathArt.poly(self, MathArt.ngon(6, 28.0, -PI * 0.5, Vector2(x, -40)), _stone, shade, 2)
		MathArt.ring(self, Vector2(x, -40), 28.0 * MathArt.INV_PHI, shade, 1.5)
		var label := service_name(str(station[1])).to_upper()
		if station[1] == "fountain" and Game.passage_claims.has("fountain"):
			label += " / " + ContentText.of("UI_PASSAGE_MARK_USED", "Used").to_upper()
		if x == EXIT_X:
			if Game.pending_destination.is_empty():
				label = ContentText.of("UI_PASSAGE_END_OF_ROUTE", "End of route slice").to_upper()
			else:
				var node: Dictionary = Data.route_graph["nodes"][Game.pending_destination]
				label = ContentText.name("biome", Game.pending_destination, str(node["name"])).to_upper()
		draw_string(font, Vector2(x - 100, -96), label, HORIZONTAL_ALIGNMENT_CENTER, 200, 12, shade)
		if near:
			if station[1] == "fountain":
				var used := Game.passage_claims.has("fountain")
				MathArt.px_rect(self, Rect2(x - 132, -192, 264, 84), MathArt.INK)
				MathArt.ui_service(self, Vector2(x - 104, -158), "fountain", 18)
				MathArt.ui_text(self, Vector2(x - 74, -167), ContentText.of("UI_PASSAGE_USED", "Already used") if used else ContentText.of("UI_PASSAGE_RESTORE", "Restore HP + flask"), 13, MathArt.WHITE)
				# The world prompt states both what is spent and where the result
				# lands before the player presses interact.
				MathArt.ui_text(self, Vector2(x - 74, -147), ContentText.of("UI_S6_FOUNTAIN_SCOPE", "This run · once per Passage"), 11, MathArt.LIGHT_DIM)
				MathArt.ui_text(self, Vector2(x - 74, -127), ContentText.of("UI_S6_FOUNTAIN_SAVED", "Saved; cannot be used again") if used else ContentText.of("UI_S6_FOUNTAIN_SAVE_HINT", "{action} to restore · saved at this Passage").format({"action": Interface.prompt(&"interact")}), 11, MathArt.PALE)
			draw_string(font, Vector2(x - 100, -72), Interface.prompt(&"interact"), HORIZONTAL_ALIGNMENT_CENTER, 200, 11, MathArt.PALE)
	for i in 9:
		var x := float(i + 1) * WIDTH / 10.0
		MathArt.line(self, Vector2(x, -320), Vector2(x, -160), _stone, 2)
