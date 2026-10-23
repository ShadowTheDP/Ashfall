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
| `scripts/systems/geom3d.gd` | foundation (done) | 3D→2D projection for pseudo-3D bodies |
| `data/characters.json` | foundation (done) | playable bodies |
| `data/armor.json` | foundation (done) | armour slots |
| `data/upgrades.json` | foundation (done) | hub upgrades |
| `data/floors.json` | foundation (done) | floor table |
| `scripts/meta/hub.gd` | **W1** | hub world + stations |
| `scripts/meta/hub_ui.gd` | **W1** | station panels |
| `scripts/world/level.gd` | **W2** | one generated floor |
| `scripts/world/level_gen.gd` | **W2** | room graph generator |
| `scripts/player/character_visual.gd` | **W3** | pseudo-3D body rendering |
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
Profile.has_skill(id) -> bool
Profile.add_skill(id) -> bool      # false if already owned / unaffordable
Profile.is_unlocked(kind, id) -> bool   # kind = "character" | "weapon" | "armor"
Profile.unlock(kind, id) -> bool
Profile.see(kind, id)              # kind = "enemy" | "weapon" | "armor"
Profile.bonus(stat: String) -> float    # aggregated permanent bonus
Profile.stats() -> Dictionary           # everything above, for the archive UI
```

`Profile.bonus("hp")` / `("damage")` / `("speed")` / `("knives")` /
`("iframe")` / `("crit")` / `("cells")` are the **only** way gameplay reads
permanent upgrades. Do not read `Profile.upgrades` directly outside the hub UI.

---

## 4. Data schemas

### 4.1 `data/characters.json`

```jsonc
"square": {
  "name": "SQUARE", "subtitle": "the first face",
  "hp": 120, "speed": 300, "jump": -630, "knives": 2,
  "body": "prism",        // prism | octa | star | torus | helix | gyro
  "sides": 4,             // geometry recipe parameter
  "spokes": 0,
  "tone": "white",
  "passive": "none",      // none | glass | bulwark | dancer | hunter | echo
  "passive_text": "...",
  "cost": 0,
  "unlock_floor": 0
}
```

`body` selects the pseudo-3D silhouette drawn by `character_visual.gd`.
`passive` is applied by the foundation thread in `player.gd`.

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

### 4.4 `data/floors.json`

```jsonc
"1": {
  "name": "THE ASH GATE", "rooms": 3, "width": 2400,
  "enemies": [["grunt", 3], ["archer", 1]],
  "boss": "", "palette": 0, "reward": 2
}
```

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
5. Pseudo-3D is allowed and encouraged for **characters and props**, but it
   must be built from projected wireframe/solid polygons (`Geom3D`), not from
   pre-rendered art.
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
- `CharacterVisual` culls back faces by 3D normal. Without it the torus draws
  ~96 quads and the whole body turns into a grey smudge.
- Base tone is pre-darkened by 0.15: `Geom3D.draw_solid` lightens a face by up
  to +0.275, so a WHITE base clamps every face to white and the form vanishes.
- `prism` and `gyro` are pre-rotated 45° on z, otherwise `Geom3D.prism` reads
  as a diamond rather than the square the game's identity depends on.

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

### Pseudo-3D is boss-only

`CharacterVisual` (`scripts/player/character_visual.gd`) is **not wired in**.
The player and every normal enemy stay flat polygons — that is the game's
identity, and a rotating solid body destroyed it. `enemy_visual.gd`
`_draw_warden()` is the only caller of `Geom3D`.

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
