# Meta Layer Contract — Hub, Floors, Progression

> This file is the **interface contract** between parallel work streams.
> Read it fully before editing anything in the meta layer. If you need to
> change a signature listed here, change it here first and say so in your
> report — another worker may be calling it.

---

## 1. What is being built

Ashfall becomes a **run-based roguelite with a persistent hub**:

```
BOOT
 └─ TitleScreen            (existing, unchanged)
      └─ Enter → Hub       ← NEW: the lobby
           ├─ Stations     ← NEW: upgrade / archives / skill tree / loadout
           └─ Door → Floor 1
                └─ Floor N  ← NEW: procedurally generated
                     ├─ clear → exit door → Hub (bank cells, spend, descend)
                     ├─ die   → Hub (lose unbanked cells, keep banked)
                     └─ Floor 5 boss → Victory
```

- **Cells** drop in floors. On death you lose the cells you were carrying;
  cells banked in the hub are permanent.
- Floors are **finite**: 5 floors, the 5th is the boss. The game is winnable.
- Everything persists in `user://ashfall_profile.json`.

---

## 2. Files this contract owns

| Path | Owner | Purpose |
|---|---|---|
| `scripts/autoload/profile.gd` | **foundation (done)** | persistent save |
| `scripts/systems/geom3d.gd` | foundation (done) | 3D→2D projection — the Warden boss only |
| `data/characters.json` | foundation (done) | playable stat rows |
| `data/armor.json` | foundation (done) | armour slots |
| `data/upgrades.json` | foundation (done) | hub upgrades |
| `data/floors.json` | foundation (done) | floor table |
| `scripts/meta/hub.gd` | **W1** | hub world + stations |
| `scripts/meta/hub_ui.gd` | **W1** | station panels |
| `scripts/world/level.gd` | **W2** | one generated floor |
| `scripts/world/level_gen.gd` | **W2** | room graph generator |
| `scripts/player/weapon_visual.gd` | **W4** | per-weapon blade drawing |
| `scripts/systems/juice.gd` | **W5** | particle presets (extend) |
| `scripts/fx/*` (new files only) | **W5** | new effect types |
| `scripts/ui/archive_screen.gd` | **W6** | bestiary / weapon / armour archives |
| `scripts/ui/skill_tree.gd` | **W6** | skill tree |

**Do not touch** `scripts/main.gd`, `scripts/autoload/game.gd`,
`scripts/player/player.gd`, `scripts/world/encounter.gd` — the foundation
thread owns the flow wiring and will merge your hooks.

---

## 3. Profile API (already implemented)

```gdscript
Profile.cells            : int      # banked currency
Profile.souls            : int      # boss currency
Profile.upgrades         : Dictionary  # {"vitality": 3, "edge": 1, ...}
Profile.skill_nodes      : Array[String]
Profile.seen_enemies     : Array[String]
Profile.seen_weapons     : Array[String]
Profile.seen_armor       : Array[String]
Profile.unlocked_characters : Array[String]
Profile.unlocked_weapons    : Array[String]
Profile.unlocked_armor      : Array[String]
Profile.selected_character  : String
Profile.selected_weapon     : String
Profile.selected_armor      : String
Profile.best_floor       : int
Profile.total_kills      : int
Profile.deaths           : int
Profile.runs             : int
Profile.victories        : int

Profile.load_profile()             # idempotent; called by the autoload
Profile.save()                     # writes user://ashfall_profile.json
Profile.reset_profile()            # wipes and saves
Profile.bank(amount: int)          # add to banked cells, saves
Profile.spend(amount: int) -> bool # false if not enough
Profile.add_upgrade(id, levels)    # clamps to the data max
Profile.upgrade_cost(id) -> int    # next level price, -1 if maxed
Profile.upgrade_currency(id) -> String  # "cells" or "souls", read from the data row
Profile.can_afford_upgrade(id) -> bool
Profile.buy_upgrade(id) -> bool    # spends that currency, saves; false if short
Profile.has_skill(id) -> bool
Profile.add_skill(id) -> bool      # false if already owned / unaffordable
Profile.is_unlocked(kind, id) -> bool   # kind = "character" | "weapon" | "armor"
Profile.unlock(kind, id) -> bool
Profile.see(kind, id)              # kind = "enemy" | "weapon" | "armor"
Profile.bonus(stat: String) -> float    # aggregated permanent bonus
Profile.stats() -> Dictionary           # everything above, for the archive UI
```

`Profile.bonus("hp")` / `("damage")` / `("speed")` / `("knives")` /
`("iframe")` / `("crit")` / `("cells")` / `("brutality")` / `("tactics")` are the
**only** way gameplay reads permanent upgrades. Do not read `Profile.upgrades`
directly outside the hub UI.

---

## 4. Data schemas

### 4.1 `data/characters.json`

```jsonc
"square": {
  "name": "SQUARE", "subtitle": "the first face",
  "hp": 120, "speed": 300, "jump": -630, "knives": 2,
  "body": "prism",        // archival: no renderer reads these three
  "sides": 4,             // archival
  "spokes": 0,            // archival
  "tone": "white",
  "passive": "none",      // none | glass | bulwark | dancer | hunter | echo
  "passive_text": "...",
  "cost": 0,
  "unlock_floor": 0
}
```

`body` / `sides` / `spokes` are **archival descriptors only**: no renderer reads
them. The player is always the plain square (`player_visual.gd`). The hub
CHARACTER panel reads `name`, `hp`, `speed`, `knives`, `passive_text`,
`cost` and `unlock_floor`; the archive has no character tab at all.
`passive` is applied by `player.gd`.

### 4.2 `data/armor.json`

```jsonc
"plate": {
  "name": "PLATE", "tone": "pale",
  "hp": 30, "damage_taken": 0.90, "speed": -20, "iframe": 0.0,
  "knives": 0, "text": "...", "cost": 0
}
```

### 4.3 `data/upgrades.json`

```jsonc
"vitality": {
  "name": "VITALITY", "stat": "hp", "per_level": 8, "max": 5,
  "cost": 30, "cost_step": 25, "text": "+8 MAX HP"
}
```

`cost_step` is added per level already owned. A row may add
`"currency": "souls"` — `brutality` and `tactics` do — and then
`Profile.upgrade_currency()` decides whether it is paid in cells or souls.

### 4.4 `data/floors.json`

```jsonc
"1": {
  "name": "THE ASH GATE", "rooms": 3, "width": 2400,
  "enemies": [["grunt", 3], ["archer", 1]],
  "boss": "", "palette": 0, "reward": 2
}
```

`reward` is the boon budget for the whole floor, spent one pick per cleared
room (see "Boon budget: one per cleared room").

---

## 5. Wiring the foundation thread will add

```gdscript
# game.gd
var floor_index := 0            # 1-based while in a floor, 0 in the hub
var floor_name := ""
var run_cells := 0              # unbanked; lost on death
var in_hub := true
signal floor_cleared
signal run_ended(victory: bool)

func start_floor(index: int) -> void
func finish_floor() -> void     # bank run_cells, back to hub
func end_run(victory: bool) -> void
```

Workers must **not** implement these; call them if needed.

---

## 6. Visual rules (unchanged, non-negotiable)

1. Everything drawn through `MathArt` primitives. No textures, no `Sprite2D`.
2. Monochrome only — colours from the `MathArt` ramp.
3. No limbs, no eyes. A hand is a single dot.
4. No squash / stretch. Weight comes from rotation, shadow, particles, camera.
5. Pseudo-3D exists for **exactly one actor: the Warden boss**
   (`EnemyVisual._draw_warden()`). The player and every other enemy stay flat
   polygons. Anything pseudo-3D must be built from projected solid polygons
   (`Geom3D`), never from pre-rendered art.
6. Keyboard only. Every new UI must be fully operable with arrows + Enter,
   and show its key hints on screen.

---

## 7. Verification each worker must run

```powershell
cd C:\Users\user\Desktop\DC-like
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path . --quit-after 3
```

Both must print **no** `SCRIPT ERROR` / `Parse Error`. Then run whatever
harness applies to your area and paste the tail of the output in your report.

---

## 8. Implementation notes (as built)

Deviations and load-bearing details that the next reader needs.

### Hub
- `Hub` builds its **own** player, walls and `HubUi`, so it is self-contained.
  `Main.enter_hub()` frees the arena player *before* `_clear_terrain()` nulls
  the reference, otherwise two squares are on screen.
- Station `J` press emits `station_opened(id)` and does **not** open a panel
  itself. `Main._on_station_opened()` routes: `skill` → `SkillTree`,
  `bestiary`/`weapons`/`armor` → `ArchiveScreen`, everything else → `HubUi`.
  Routing inside the hub raised two panels at once.
- Panels freeze the player's physics (`set_physics_process(false)`) because J
  is also the attack key, and `HubUi` ignores keys on the frame it opened.

### Floors
- `LevelGen` keeps a continuous bottom ledge at `BASE_Y = 150` under every
  room. A missed gap lands on stone instead of falling out of the world, and
  every step back up is ≤ 90 px. True void pits were rejected as unrecoverable.
- Reachability is BFS-verified per room with a 110 px up / 180 px across jump
  budget. 125 layouts (floors 1-5 × seeds 1-25) produce zero warnings.
- Floor 5 has one room, so it is simultaneously start, boss and exit.
- The camera clamps its **centre**, so `limit_bottom` must be at least one half
  viewport (240) below the deepest floor slab. 140 and 240 both cut the player
  off; 400 works.

### Pseudo-3D
- `Geom3D.draw_solid()` sorts faces back-to-front by averaged depth and shades
  by winding (see "Boss placement and face shading"). No culling pass is
  needed: back faces land in 0.05..0.30 and never compete with a front face.
- Base tone is pre-darkened by 0.18 in `enemy_visual.gd`: `draw_solid` lightens
  a face by up to +0.275, so an undarkened PALE base clamps every face to the
  same value and the solid goes flat.
- The Warden's prism is pre-rotated -90° on z so a vertex points up.
  `Geom3D.prism` starts at +x, and an unrotated pentagon reads as a diamond,
  not a column.

### Weapons
- `WeaponVisual.draw_blade()` stores the pose and emits geometry from its own
  `_draw()`. Godot forbids `draw_*` outside an item's own draw pass.
- `orbit` cannot draw one blade truly behind the hand (the hand belongs to
  `PlayerVisual`), so the trailing blade is drawn at 0.45 alpha.

### Effects
- `Combat.impact()` adds one layer per tier rather than scaling everything:
  tier≥1 phyllotaxis burst, tier≥2 directional `ShockwaveFx` + `critical_halo`,
  tier≥3 `ConstellationFx` + `rose_bloom`. `Combat.gather()` is the inward
  counterpart for telegraphs and deaths.
- `rose_bloom(petals=6)` renders 3 lobes: `r = cos(kθ)` closes at integer k and
  gives k lobes for odd k, 2k for even.

### The two-colour build

Weapons and boons carry an `attribute` colour; the run tracks how deep each
colour is and damage scales with it.

- `data/weapons.json`: every weapon has `"attribute"` — `brutality` for
  rusty_sword / fractal_edge / chain_lash, `tactics` for arc_saber /
  kiss_precision / orbit_rings.
- `data/rewards.json`: `edge` and `hunter` raise brutality, `ghost` and
  `armory` raise tactics, `vitality` / `swift` / `leech` carry no colour.
- `Game.attr` is a `Dictionary` of in-run colour levels. `start_floor()` and
  `reset_run()` both clear it, so colour never crosses a floor or a run.
- `Player.attribute_level(colour)` = `Game.attr[colour] + Profile.bonus(colour)`;
  `weapon_attr_level()` is the same for the equipped weapon. It feeds
  `Hitbox.attr`, `FunctionWave.attr` and `Projectile.attr`.
- `Damage.compute(damage, attr, crit, crit_mult)` multiplies by
  `1 + attr * ATTR_SCALE` (`ATTR_SCALE = 0.12`) on top of crits, so one level is
  +12%.
- A kunai is always tactics: `Player._throw_knife()` sets
  `Projectile.attr = attribute_level("tactics")` whatever the blade is.
- The soul sink: `data/upgrades.json` gained `brutality` and `tactics` rows
  (`per_level` 1, `max` 5, `cost` 1 with `cost_step` 1, `"currency": "souls"`).
  `Profile.upgrade_currency()` / `can_afford_upgrade()` / `buy_upgrade()` are
  the only path that spends souls.

### Boon budget: one per cleared room

`data/floors.json` `"reward"` (2 / 2 / 3 / 3 / 0) is **not** spent at the exit.
A floor banks its cells the moment it is cleared, so an exit picker had nothing
left to pay for. `Game.start_floor()` loads the budget into
`Game.floor_rewards_left`, `Level` emits `room_cleared(index)`, and
`Main._on_room_cleared()` decrements the budget and defers the picker — the
room clears inside a physics signal flush and the picker pauses the tree. Floor
5 pays no boons at all.

### Pseudo-3D is boss-only

`enemy_visual.gd` `_draw_warden()` is the **only** caller of `Geom3D`. The
player is a flat square and every other enemy is a flat polygon — that is the
game's identity, and a rotating solid body destroyed it.

Two things the Warden needs that a small body does not:

- `draw_solid(..., contrast)` — the default 0.55 flattens five facets on a
  40 px body into one grey mass. The Warden passes **1.15**.
- The pentagram is inscribed on the cap that faces the camera (chosen by
  averaging the cap's depths), and it is drawn in **INK, not white**. The cap
  is the lightest face, so a bright sigil disappears into it; a dark one reads
  as carved.

### Modal panels own Esc

`HubUi`, `ArchiveScreen` and `SkillTree` use `_input()`, not
`_unhandled_input()`. The HUD also listens for Esc and sits later in the tree,
so unhandled input reached the HUD first: Esc paused the game instead of
closing the panel, and a paused panel stopped receiving input entirely, which
is what trapped the player in UPGRADES.

`Hud._unhandled_input()` additionally returns early while any panel
`is_open()`, so a pause can never happen underneath a modal.

`tests/esc_probe.tscn` is the regression test: it opens all six stations,
closes each with Esc, asserts the tree is not paused and the player is not
frozen, and checks that Enter still buys an upgrade. It runs inside
`tools/check.ps1`.

### Arena stage is arena-mode only

`Main._ready()` used to build `Arena` unconditionally. `Arena` owns a solid
`GROUND` box from y 0 to 160 plus five platforms, and nothing ever freed it.
Consequences:

- **In the hub**, its platforms were invisible steps the player could still
  jump onto.
- **On a generated floor**, its ground box swallowed the spawn point, so the
  player was stuck inside collision and could not move at all (`dx = 0`).

`_build_arena_stage()` now runs only when `start_mode == "arena"`, which is
also the only mode that creates `Encounter`. `tests/floor_probe.tscn` asserts
`dx > 5` after a descend and fails loudly on a paused tree, a scaled
`time_scale`, or a null player.

### One door per screen

The hub used to have six stations, three of which (BESTIARY / WEAPONS /
ARMOR) opened the same three-tab `ArchiveScreen`. Every door reached all three
tabs, which read as a bug. There are now four stations:

| station | screen |
|---|---|
| UPGRADES | `HubUi` panel |
| SKILLS | `SkillTree` |
| ARCHIVES | `ArchiveScreen` (three tabs inside) |
| CHARACTER | `HubUi` panel |

`HubUi._rows()` no longer carries duplicate bestiary/weapon/armour lists; the
archive owns them. `Main._on_station_opened("archive")` opens the BESTIARY tab
and the player tabs across from there.

### Boss placement and face shading

Two bugs that only showed on floor 5:

- **The boss was invisible.** `Geom3D._face_shade()` scored a face by its fill
  ratio (area / bounding box). A pentagon cap scores ~0.7 while a side quad
  scores ~0.95, so the sides came out *brighter than the top* and, at contrast
  1.15, the caps were pushed to near-black. Shading is now **winding-based**:
  front faces land in 0.62..0.92, back faces in 0.05..0.30, and the fill ratio
  only modulates inside its own band.
- **The boss was embedded in a platform.** Room spawn points are chosen for a
  42 px husk. `LevelGen.boss_spawn()` now picks the lane in the room with the
  widest gap between platform centres and lifts 44 px off the slab, exposed as
  `data["boss_at"]`; `Level._enter_room()` uses it instead of the generic point.

### Probe notes

`tests/audit_a3.gd` samples the enemy count **before** any physics frame. A
one-room floor (the boss arena) starts the player inside the only room, so the
first `_physics_process` enters it and spawns — correct, not a leak. The probe
therefore asserts `build()` spawned nothing and that
`pending + already_spawned == planned`.

### Vertical floors

A floor is no longer a corridor. `LevelGen` builds rooms with 2-5 decks at
`TIER = 92` px apart, and two surface kinds:

| kind | collision | visual |
|---|---|---|
| pass-through deck | `one_way_collision = true`, on `Layers.ONEWAY` | thin, bright top edge, **dashed underside** |
| solid mass | ordinary `Layers.WORLD` box | thick, block courses |

The dashed underside is load-bearing: it is the only cue that says "jump up
through this one". Do not remove it.

Six room kinds: `gate` (route split), `hall` (column capitals + gallery),
`shaft` (5-rung zigzag climb), `vault` (two chambers, solid floors with a
hole), `bridge` (stepping stones at two heights), `well` (a solid wall inside
the room, climbed over).

Floors are 4200-6400 px wide, 4-6 rooms, 6-13 enemies.

### Four softlock traps that had to be designed out

These all produced a floor the player could not finish:

1. **A wall on a room boundary.** `pit` put solid lips at `rect.position.x`
   and `rect.end.x`. The player could never step into the room, so its
   enemies never spawned and the gate never opened. `well` puts its wall at
   `w * 0.44`, inside the room.
2. **A step that does not touch its pillar.** The approach deck sat 96 px
   before the pillar, leaving a drop between them. From the ledge the pillar
   top (126-176 up) is out of reach because the apex is 110. The step is now
   `left - step_w` so it abuts the pillar, and pillar height is capped at 176
   so the climb from the step is 84 px.
3. **Gaps computed before offsets.** A gap was chosen independently of the
   height change, so a room 26 px up and 185 px away sat outside the 161 px
   budget. Offsets are now generated first and the gap is clamped to
   `JUMP_LENGTH * (1 - 0.45 * up / JUMP_HEIGHT) - 14`.
4. **A point-sized exit gate.** Multi-deck rooms put the player on a gallery
   directly above the door; a distance test to one point never fired. The
   gate is now a column: `|dx| < 62 and |dy| < 260`.

`tests/audit_a3.gd` drives the real player right through every floor and
asserts it reaches the gate; `LevelGen._verify()` BFS-checks 300 layouts
(floors 1-5 x seeds 1-60) with zero unreachable rooms.

### Camera

`PlayerCamera.BASE_ZOOM = 0.86`. At 1.0 the view is 480 px tall, which shows
a slab and one deck but not the shaft above it. 0.86 shows ~558 px.

### Floor picker

`Hub.setup(best_floor)` sets `floor_target = best_floor + 1`. The door shows
`FLOOR n / top` and `A/D` steps within `1..best_floor+1`, so a late-game
player can farm an earlier floor. Sending the player back to floor 1 forever
was the bug that made every run "floor 1 again".
