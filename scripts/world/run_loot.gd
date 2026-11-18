class_name RunLoot
extends Node2D
## A terrain-owned offer. All commits validate the originating run and consume once.

## English display content for ids that no canonical table names. CSV rows
## replace it once loaded; these are fallbacks, never translations.
const LOOT_NAME_EN := {
	"gold": "Gold", "food": "Food", "scroll": "Scroll", "chest": "Chest",
	"shop": "Shop", "gear": "Gear",
}
const QUALITY_NAME_EN := {"plain": "Plain", "etched": "Etched"}
const AXIS_NAME_EN := {"brutality": "Brutality", "tactics": "Tactics", "survival": "Survival"}

var kind := "gear"
var item: Dictionary = {}
var amount := 0
var cost := 0
var consumed := false
var owner_build: RunBuild

func _ready() -> void:
	owner_build = Game.build
	add_to_group("run_loot")

## An offer left on the floor dies with its terrain, so its unclaimed instance
## must not stay in the run inventory. Only the captured owner is touched: a new
## run restarts UIDs at 1, so owning through `Game.build` could retire a live item.
func _exit_tree() -> void:
	if consumed or owner_build == null or item.is_empty() or not owner_build.owns(item):
		return
	for slot in owner_build.slots.size():
		if is_same(owner_build.slots[slot], item):
			return
	owner_build.retire(item)

func available() -> bool:
	return not consumed and owner_build != null and owner_build == Game.build and not Game.run_over and Game.run_phase == "biome" and is_instance_valid(Game.player) and Game.player.hp > 0

func _process(_delta: float) -> void:
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not available() or get_tree().paused or not Interface.pressed(event, &"interact"):
		return
	if Game.player.global_position.distance_to(global_position) > float(Data.traversal["interact_reach"]):
		return
	get_viewport().set_input_as_handled()
	Game.player.suppress_actions()
	if kind in ["gold", "food"]:
		claim()
	else:
		get_tree().call_group("build_screen", "open", self)

func claim(slot := -1, recycle := false) -> bool:
	if not available() or owner_build.gold < cost:
		return false
	if kind == "scroll":
		if slot < 0 or slot > 2:
			return false
		owner_build.attributes[owner_build.attributes.keys()[slot]] += 1
	elif kind == "food":
		if Game.player.hp >= Game.player.max_hp:
			return false
		Game.player.heal(Game.player.max_hp * float(Data.gear["economy"]["food_heal"]))
	elif kind == "gold":
		owner_build.gold += amount
	else:
		if not owner_build.owns(item):
			return false
		if recycle:
			if cost > 0:
				return false # Unsold stock is not the player's to recycle.
			owner_build.gold += owner_build.recycle_value(item)
			owner_build.retire(item)
		else:
			if slot < 0 or slot >= owner_build.slots.size():
				return false
			var old := owner_build.slots[slot]
			if not owner_build.equip(slot, item):
				return false
			owner_build.gold += owner_build.recycle_value(old)
			owner_build.retire(old)
	owner_build.gold -= cost
	consumed = true
	Game.player.suppress_actions()
	Game.player._apply_loadout()
	Sfx.play("reward", -10)
	visible = false
	queue_free()
	return true

func _draw() -> void:
	if consumed:
		return
	var tint := MathArt.GOLD if kind in ["gold", "chest"] else (MathArt.HEAL if kind == "food" else (MathArt.TACTICS if kind == "scroll" else MathArt.PICKUP))
	if kind == "shop" and owner_build != null and not item.is_empty():
		var cfg := owner_build.definition(item)
		MathArt.ui_gear(self, Vector2.ZERO, str(cfg.get("action", "amulet")), 17, MathArt.axis_color(str(cfg.get("attribute", "survival"))), str(item.id))
		MathArt.ui_text(self, Vector2(-72, 34), "%d %s" % [cost, _unit("gold")], 13, MathArt.GOLD, 144, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var sides := 4 if kind == "chest" else 6
		MathArt.poly(self, MathArt.ngon(sides, 12, PI / 4), MathArt.INK, tint, 2)
		MathArt.ring(self, Vector2.ZERO, 12 * MathArt.INV_PHI, tint, 1)
	if available() and Game.player.global_position.distance_to(global_position) <= float(Data.traversal["interact_reach"]):
		if kind == "shop":
			_draw_shop_tip()
		else:
			MathArt.ui_text(self, Vector2(-140, -26), ContentText.of("UI_WORLD_HINT_TAKE_GENERIC", "{action}  {kind}").format({"action": Interface.prompt(&"interact"), "kind": loot_name(kind).to_upper()}), 11, MathArt.WHITE, 280, HORIZONTAL_ALIGNMENT_CENTER)


## The HUD announcement band in logical screen space, mirroring
## Hud._draw_announce: wrapped at 640 px from x=64 around 30% height, with real
## font line height per line. Empty while no announcement owns the screen. Hud also paints a wider
## SAVE FAILED backdrop and, while returning to the hub, one extra 11 px line;
## include that line so the shop card does not cover it.
func announcement_rect() -> Rect2:
	if Game.announce_t <= 0.0 or Game.announce_text.is_empty():
		return Rect2()
	var lines := MathArt.ui_wrap(Game.announce_text, 640.0, 24).size()
	if lines <= 0:
		return Rect2()
	var height := MathArt.ui_line_height(24) * float(lines) + 12.0
	if Game.hub_return_in > 0.05:
		height += 26.0
	return Rect2(64.0, 120.0, 640.0, height)


## Logical screen-space card for the stock tip, clamped into the safe area.
## Pure geometry so the shape can be asserted without reading pixels. Returns
## an empty rect while an announcement owns the band and neither side can hold
## the whole card clear of it: the detail card then waits for the announcement
## to expire instead of covering it. The world stock and its price stay drawn,
## and R still opens the comparison page, so only the nearby detail card is
## deferred.
func shop_tip_rect() -> Rect2:
	var point: Vector2 = get_global_transform_with_canvas() * Vector2.ZERO
	var size := Vector2(304, 154)
	var safe := Rect2(16, 16, 736, 320)
	var spoke := announcement_rect()
	var x := clampf(point.x - size.x * 0.5, safe.position.x, safe.end.x - size.x)
	for y: float in [point.y - 174.0, point.y + 20.0]:
		var card := Rect2(Vector2(x, y), size)
		if safe.encloses(card) and (not spoke.has_area() or not card.intersects(spoke.grow(2.0))):
			return card
	if spoke.has_area():
		return Rect2()
	return Rect2(Vector2(x, clampf(point.y - 174.0, safe.position.y, safe.end.y - size.y)), size)


## The shop's details belong to the object, not to a separate form: one card in
## logical screen space, clamped to the safe area, still pointing at the stock.
## Buying is unchanged - interact opens the same comparison page.
func _draw_shop_tip() -> void:
	if owner_build == null or item.is_empty():
		return
	var cfg := owner_build.definition(item)
	if not cfg.has("name"):
		return
	var card := shop_tip_rect()
	if not card.has_area():
		return
	var to_screen := get_global_transform_with_canvas()
	var point: Vector2 = to_screen * Vector2.ZERO
	draw_set_transform_matrix(to_screen.affine_inverse())
	# Pointer first, so the card paints over its own join.
	var anchor_x := clampf(point.x, card.position.x + 16.0, card.end.x - 16.0)
	if card.end.y <= point.y - 4.0:
		MathArt.poly(self, PackedVector2Array([Vector2(anchor_x - 8, card.end.y), Vector2(anchor_x + 8, card.end.y), Vector2(anchor_x, card.end.y + 10)]), MathArt.BG_0, MathArt.STONE_HI, 1)
	elif card.position.y >= point.y + 4.0:
		MathArt.poly(self, PackedVector2Array([Vector2(anchor_x - 8, card.position.y), Vector2(anchor_x + 8, card.position.y), Vector2(anchor_x, card.position.y - 10)]), MathArt.BG_0, MathArt.STONE_HI, 1)
	else:
		# The stock is behind the card: a stub outside the edge, never a line through text.
		var edge := card.end.y + 6.0 if point.y > card.get_center().y else card.position.y - 6.0
		MathArt.line(self, Vector2(anchor_x, edge), Vector2(anchor_x, edge + (6.0 if point.y > card.get_center().y else -6.0)), MathArt.STONE_HI, 1)
	MathArt.ui_surface(self, card, true, true)
	var stats := owner_build.display_stats(item)
	var attribute := str(cfg.get("attribute", "survival"))
	MathArt.ui_gear(self, card.position + Vector2(28, 36), str(cfg.get("action", "amulet")), 16, MathArt.axis_color(attribute), str(item.id))
	MathArt.ui_text(self, card.position + Vector2(52, 20), loot_name("shop").to_upper(), 11, MathArt.LIGHT_DIM)
	MathArt.ui_text(self, card.position + Vector2(card.size.x - 120, 20), ContentText.of("UI_PRICE_AMOUNT", "{amount} {unit}").format({"amount": cost, "unit": _unit("gold")}), 11, MathArt.GOLD, 104, HORIZONTAL_ALIGNMENT_RIGHT)
	var names := MathArt.ui_wrap(ContentText.name("gear", str(item.id), str(cfg.name)), 236, 16)
	for i in mini(2, names.size()):
		MathArt.ui_text(self, card.position + Vector2(52, 42 + i * MathArt.ui_line_height(16)), names[i] + ("…" if i == 1 and names.size() > 2 else ""), 16, MathArt.PALE)
	var mains := ContentText.of("UI_STAT_READOUT", "{label} {value}").format({"label": ContentText.stat_label(str(stats.label)), "value": stats.value})
	if cfg.kind != "amulet" and int(stats.capacity) > 1:
		mains += " · " + ContentText.of("UI_GEAR_CHARGES", "Charges {have}/{capacity}").format({"have": int(item.charges), "capacity": int(stats.capacity)})
	MathArt.ui_text(self, card.position + Vector2(16, 86), mains, 13, MathArt.PALE, 272)
	MathArt.ui_text(self, card.position + Vector2(16, 103), ContentText.of("UI_GEAR_TRAITS", "{quality} · {axis}").format({"quality": quality_name(str(item.quality)), "axis": axis_name(attribute)}), 11, MathArt.LIGHT_DIM)
	var affix: Dictionary = Data.gear.affixes.get(item.affix, {})
	if not affix.is_empty():
		MathArt.ui_text(self, card.position + Vector2(16, 118), ContentText.name("affix", str(item.affix), str(affix.get("name", ""))), 11, MathArt.LIGHT_DIM, 272)
	var action := ContentText.of("UI_SHOP_COMPARE", "{action} compare · {amount} {unit}").format({"action": Interface.prompt(&"interact"), "amount": cost, "unit": _unit("gold")})
	var tone := MathArt.PALE
	if owner_build.gold < cost:
		action = ContentText.of("UI_SHOP_NEED_GOLD", "Need {amount} more {unit}").format({"amount": cost - owner_build.gold, "unit": _unit("gold")})
		tone = MathArt.DANGER
	MathArt.ui_text(self, card.position + Vector2(16, 139), action, 13, tone)
	if names.size() > 2:
		MathArt.ui_text(self, card.position + Vector2(card.size.x - 120, 139), ContentText.of("UI_SHOP_FULL_DETAILS", "{action} full details").format({"action": Interface.prompt(&"interact")}), 11, MathArt.LIGHT_DIM, 104, HORIZONTAL_ALIGNMENT_RIGHT)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Currency unit, so a count and its unit are localized separately.
func _unit(kind: String) -> String:
	return ContentText.of("UI_UNIT_GOLD", "Gold") if kind == "gold" else ContentText.of("UI_UNIT_CELLS", "Cells")


## Offer kind, quality and axis names: ids stay machine values and never reach
## the card. The collector reuses the quality name for its craft rows.
static func loot_name(id: String) -> String:
	return ContentText.name("loot", id, str(LOOT_NAME_EN.get(id, "")))


static func quality_name(id: String) -> String:
	return ContentText.name("quality", id, str(QUALITY_NAME_EN.get(id, "")))


static func axis_name(id: String) -> String:
	return ContentText.name("axis", id, str(AXIS_NAME_EN.get(id, "")))
