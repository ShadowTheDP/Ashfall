# Ashfall — Handover

> Read this first. It is the state of the project at the end of the session
> that added the hub, procedural floors, characters, weapons and the vertical
> level generator. `docs/PRODUCT.md` is the full business overview; this file
> is what changed, what is fragile, and what to do next.

---

## 1. Where the game is

Ashfall is a **run-based roguelite with a persistent hub**, built from
pure geometry, monochrome, keyboard-only, 768×480 at 2× zoom.

```
Title → Enter
  └─ HUB (walkable lobby, 1600 px)
       ├─ UPGRADES   (HubUi panel)      7 permanent upgrades
       ├─ SKILLS     (SkillTree)        11-node tree
       ├─ ARCHIVES   (ArchiveScreen)    3 tabs: bestiary / weapons / armour
       ├─ CHARACTER  (HubUi panel)      6 bodies
       └─ DOOR       floor picker → floor n
            └─ FLOOR 1..5   multi-deck, procedurally generated
                 ├─ clear → bank cells → back to hub
                 ├─ die   → lose unbanked cells → back to hub
                 └─ floor 5 boss (Warden) → victory
```

`Profile` saves to `user://ashfall_profile.json`.

### Content as it stands

| | count | notes |
|---|---:|---|
| Floors | 5 | 4200 / 5200 / 5600 / 6400 / 2600 px |
| Rooms per floor | 4 / 5 / 5 / 6 / 2 | 6 room archetypes |
| Enemies | 6 + boss | grunt, archer, charger, bulwark, spitter, leaper, warden |
| Enemies per floor | 6 / 9 / 10 / 13 / 6 | |
| Playable bodies | 6 | square, octa, star, torus, helix, gyro |
| Weapons | 6 | edge, curve, lens, fractal, chain, orbit |
| Armour | 5 | none, plate, lattice, mantle, aegis shell |
| Upgrades | 7 | hp, damage, speed, knives, iframe, crit, cells |
| Skill nodes | 11 | 3 roots, 1 apex |
| Boons (in-run) | 7 | from `data/rewards.json` |

---

## 2. What this session built

### 2.1 Persistent profile (`scripts/autoload/profile.gd`)
Single owner of the save file. Gameplay reads progression **only** through
`Profile.bonus(stat)`. Save writes `.tmp` then replaces, so an interrupted
write cannot truncate the profile.

### 2.2 Hub (`scripts/meta/hub.gd`, `hub_ui.gd`)
A walkable lobby, not a menu. Four stations plus a door. The door offers
`best_floor + 1` and `A/D` steps through every unlocked floor.

### 2.3 Procedural floors (`scripts/world/level_gen.gd`, `level.gd`)
The biggest change. A floor is **vertical**:

- A continuous bottom ledge runs the whole width.
- Rooms sit on slabs 0–96 px above it, and carry 2–5 decks at `TIER = 92` px.
- **Pass-through decks** (`one_way_collision`, `Layers.ONEWAY`) have a dashed
  underside; **solid masses** (walls, pillars, lips) have block courses.
- Six archetypes: `gate`, `hall`, `shaft`, `vault`, `bridge`, `well`.
- Pillars between rooms force the player up and over instead of holding right.

### 2.4 Pseudo-3D, boss only
`Geom3D` (3D→2D projection) is used **only** by `EnemyVisual._draw_warden()`.
The player and every normal enemy stay flat polygons — that is the game's
identity. `scripts/player/character_visual.gd` exists but is **not wired in**;
it is kept for a future where a character genuinely needs a rotating body.

### 2.5 Two new enemies
- **Spitter** (7-point star): lobs an arcing glob that leaves a damaging pool.
- **Leaper** (thin triangle): hops to the player's x and slams down.

### 2.6 Flasher FX
`Juice` gained `prism_burst`, `spiral_wake`, `rose_bloom`, `ash_rise`,
`critical_halo`. New scenes: `PrismFx`, `VortexFx`, `ConstellationFx`,
`ShockwaveFx`. `Combat.impact()` now adds one layer per tier instead of
scaling everything; `Combat.gather()` is the inward counterpart.

---

## 3. Bugs fixed this session (with causes)

These are worth reading before touching the same code.

| Area | Cause | Fix |
|---|---|---|
| Invisible arena in hub / stuck floor | `Arena` built unconditionally; its solid `GROUND` box (y 0→160) swallowed the floor spawn | `_build_arena_stage()` only when `start_mode == "arena"` |
| Every run was floor 1 | door emitted `floor_available` (best_floor) forever | `floor_target = best_floor + 1` + picker |
| Archive doors duplicated | 3 stations opened the same 3-tab panel | one ARCHIVES station |
| Esc trapped in UPGRADES | `Hud._unhandled_input` consumed Esc before the panel; a paused panel stops receiving input | panels use `_input()` + `PROCESS_MODE_ALWAYS`; HUD returns early while a panel `is_open()` |
| Boss invisible | `_face_shade` scored faces by fill ratio, so side quads out-shone the cap; at contrast 1.15 the cap went near-black | winding-based shading: front 0.62–0.92, back 0.05–0.30 |
| Boss embedded in a platform | generic spawn points are tuned for a 42 px husk | `LevelGen.boss_spawn()` + `data["boss_at"]` |
| Enemies fell off decks forever | no ledge awareness | `_ground_ahead()` / `_may_walk()` / `_gate()` in `enemy.gd` |
| Crowd pinned a body | separation push exceeded the body's own speed | clamp push to `speed * 0.6` |
| **Arrows/globs passed through everything** | `Projectile._ready` set `monitorable = false`, which in 4.7 also stops the area detecting bodies | `monitorable = true` |
| Spitter never left a pool | `if _glob == null: return` — a freed Object compares equal to `null`, so it returned on exactly the frame the glob died | `_glob_fired` flag |
| Leaper's hop was a stumble | lift clamp floor was 24 px | floor raised to 74 px |
| ECHO / DANCER / HUNTER passives did nothing | declared, never read | implemented in `player.gd` + `Game.perfect_dodge()` + `Hitbox` crit hook |
| Every body spawned at 120 hp | `hp = max_hp` ran before `_apply_loadout()` | reordered |
| Save with `null` crashed the load | `int(null)` | `_to_int()` guard, `JSON.new().parse()` |

### Four floor-design softlocks that had to be designed out

1. A wall **on a room boundary** — the player could never enter the room.
2. A step deck that **did not touch** its pillar — a drop in between, and the
   pillar top is out of reach from the ledge.
3. Gaps computed **before** vertical offsets — a room 26 px up and 185 px away
   sat outside the 161 px budget.
4. A **point-sized exit gate** — a player standing on a deck above the door
   never triggered it. The gate is now a column (`|dx| < 62`, `|dy| < 260`).

---

## 4. Validation

```powershell
powershell -ExecutionPolicy Bypass -File tools\check.ps1
```

```
TESTS OK (111 checks)
PROBE OK          combat probe
REWARD OK         boon picker
SOAK OK           4 waves + boss + victory
ESC TEST OK       hub panels open/close/buy
FLOOR PROBE OK    hub → floor handoff, player can move
RUN PROBE OK      5 floors → victory → hub, economy intact
AUDIT A1 OK       weapons / passives / armour / death
AUDIT A2 OK       save round-trip, economy edges (110 checks)
AUDIT A3 OK       floor × seed reachability, spawns, gate
AUDIT A4 OK       key ownership, text fit (224 checks)
AUDIT V1 OK       vertical traversal, one-way, softlocks
AUDIT V2 OK       decks, spitter, leaper, archer, cells
AUDIT V3 OK       run flow, floor picker, state leaks (162 checks)
ALL CHECKS PASSED
```

Visual harnesses (need a display):

```
tests/capture_scene.tscn    13 gameplay shots
tests/impact_capture.tscn   20 frame-by-frame impact shots
tests/meta_capture.tscn     14 hub/floor/archive shots
tests/title_capture.tscn    title
tests/jump_capture.tscn     tumble frames
```

Output goes to `output/screenshots/` (gitignored).

---

## 5. Hard rules (do not break)

1. Everything drawn through `MathArt`. No textures, no `Sprite2D`.
2. Monochrome only — colours from the `MathArt` ramp. No hue.
3. No limbs, no eyes. A hand is a single dot.
4. No squash / stretch. Weight comes from rotation, shadow, particles, camera.
5. The player is a **flat square**. Pseudo-3D is for the Warden only.
6. The swing trail has **one owner** (`SlashFx`) and is **disconnected dashes**
   on a single radius. Never concentric bands; never let it touch the blade.
7. `_coil_angle()` must go through `_mirror()`, or a left-facing swing sweeps
   ~5 rad and the trail becomes a band.
8. The dashed underside of a pass-through deck is the only cue that says "jump
   up through this". Do not remove it.
9. Keyboard only, hints always visible.
10. Impact goes through `Combat.impact()`. Particles go through `Juice.*`.

---

## 6. Fragile spots / known limits

| Risk | Detail |
|---|---|
| `_apply_loadout()` is one-shot | `roll_iframe_end` / `crit_bonus` use `+=`; calling it again on a live player compounds them |
| Hub camera limits | the hub widens `camera.limit_*`; `Main.start_floor()` must reset them or the view clamps at the hub's edges |
| `--check-only --script` is unreliable | autoload globals are missing, so it reports false `Identifier not found: Game`. Verify by running a scene, not a single script |
| Level draw cost | ~500 specks + cracks per floor, drawn once and never re-queued. Fine now; watch it if floors get wider |
| No export preset | Godot export templates (~1.28 GB) are not downloaded |
| English only | no CJK font, so no Chinese UI |
| Weapon unlock cost | weapons use `unlock_cost`, armour/characters use `cost`; `Profile.unlock` reads both |
| `rose_bloom(petals=6)` | renders 3 lobes — `r = cos(kθ)` closes at integer k |
| No save-slot UI | one profile, `user://ashfall_profile.json` |
| `Hub.is_open()` covers `HubUi` only | the archive/tree are separate layers; `Main._any_panel_open()` is the real guard |

---

## 7. Next steps (highest value first)

1. **Playtest the vertical floors.** The generator is verified reachable and
   the player can cross every floor, but nobody has judged whether the climb
   *feels* good. Tune `TIER`, `MAX_UP` and the pillar frequency from
   `level_gen.gd`.
2. **Add the new enemies to `floors.json`.** They exist and are audited but no
   floor spawns them yet. Add `["spitter", n]` / `["leaper", n]` to floors 2–4.
3. **Wire `character_visual.gd` or delete it.** It is dead code right now.
   If characters are meant to stay flat, delete the file to avoid confusion.
4. **Boon pool is still the 7 in-run boons.** With 6 weapons and 6 bodies, a
   weapon-specific boon pool would give the runs more identity.
5. **Add a second boss** for a second victory condition, or an endless mode
   after floor 5.
6. **Export preset** if a distributable build is wanted.

---

## 8. Map of the code

```
scripts/autoload/   data.gd  profile.gd  game.gd  combat.gd  sfx.gd
scripts/systems/    math_art.gd  geom3d.gd  juice.gd  damage.gd  layers.gd
scripts/meta/       hub.gd  hub_ui.gd
scripts/world/      level.gd  level_gen.gd  arena.gd  encounter.gd
                    braziers.gd  runes.gd  motes.gd
scripts/player/     player.gd  player_visual.gd  weapon_visual.gd
                    character_visual.gd (UNUSED)  player_camera.gd
scripts/enemies/    enemy.gd  enemy_visual.gd  projectile.gd  cell_pickup.gd
scripts/combat/     hitbox.gd  function_wave.gd
scripts/ui/         hud.gd  title_screen.gd  reward_screen.gd
                    archive_screen.gd  skill_tree.gd
scripts/fx/         impact_fx.gd  screen_punch.gd  slash_fx.gd  ring_fx.gd
                    burst_fx.gd  shatter_fx.gd  afterimage.gd
                    damage_number.gd  parabola_fx.gd
                    prism_fx.gd  vortex_fx.gd  constellation_fx.gd  shockwave_fx.gd
data/               weapons.json  enemies.json  rewards.json
                    characters.json  armor.json  upgrades.json
                    floors.json  skill_nodes.json
tests/              run_tests.gd  combat_probe  reward_probe  soak
                    esc_probe  floor_probe  run_probe
                    audit_a1..a4  audit_v1..v3
                    capture_scene  impact_capture  meta_capture
                    title_capture  jump_capture
tools/              check.ps1  fetch_godot.ps1  make_sfx.py  make_music.py
docs/               PRODUCT.md  agent/  design/
```

## 9. Reading order for the next person

1. `docs/PRODUCT.md` — the whole picture
2. `docs/design/meta.md` — hub / floors / progression contract + every
   load-bearing detail discovered this session
3. `docs/design/math-art.md` — visual language
4. `docs/design/impact.md` — combat feel, especially §7 (the trail) and §8
5. `AGENTS.md` → `MEMORY.md` → `docs/agent/current-state.md`
