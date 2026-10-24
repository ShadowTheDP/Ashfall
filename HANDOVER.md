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
| Floors | 5 | 5600 / 6800 / 7000 / 8200 / 2600 px |
| Rooms per floor | 5 / 6 / 6 / 7 / 2 | 6 room archetypes, two-tier |
| Surfaces per floor | ~29 / 36 / 35 / 42 / 10 | slabs + decks + gallery + ladders |
| Enemies | 6 + boss | grunt, archer, charger, bulwark, spitter, leaper, warden |
| Enemies per floor | 9 / 11 / 13 / 17 / 5 | spitter + leaper spawn on 2-4 |
| Caches per floor | 3 / 3 / 3 / 3 / 2 | cells on the high route |
| Playable bodies | 6 | square, octa, star, torus, helix, gyro |
| Weapons | 6 | edge, curve, lens, fractal, chain, orbit |
| Armour | 5 | none, plate, lattice, mantle, aegis shell |
| Upgrades | 7 cell + 2 soul | hp, damage, speed, knives, iframe, crit, cells; brutality, tactics cost souls |
| Skill nodes | 11 | 3 roots, 1 apex |
| Boons (in-run) | 7 | from `data/rewards.json`; 4 carry a colour |
| Boons per floor | 2 / 2 / 3 / 3 / 0 | `data/floors.json` `reward`, paid per cleared room |

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
identity. `scripts/player/character_visual.gd` was deleted: 316 lines, zero
references, and it contradicted the flat-square rule.

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

### Session 3 — the retry, the maps, the impact and the hub

| Area | Cause | Fix |
|---|---|---|
| R inside a floor skipped the floor and banked progress | `Hud._restart()` -> `reload_current_scene()` rebuilt Main -> title -> hub, and `Game.start_floor()` advances `Profile.best_floor` on ENTRY, so the door offered the next floor | `Main.restart_attempt()` replays the chosen floor; Profile is not touched. `tests/restart_probe.tscn` |
| A pillar could leave a 23 px crack | pillar was centred in the gap; a 28 px body cannot enter 23 px, so a fall there was final | `SLOT = 46` on the approach side, pillar flush against the next room |
| Spawns passed generation and failed the audit | generation used the room's own tallest body (21) while the audits use FALLBACK_BOX (25) | `SPAWN_HALF_MIN = 25`, linked to the audits by comment |
| The gallery could become a ceiling | connectors were placed before pillars existed | pillars first, then `_headroom()` rejects any surface < 72 px above another |
| Floors read as a row of set pieces | rooms were individually good but not linked | `_link_gallery` + `_stack_ladders` + `_caches` |

### Session 4 — the boss that could not hit you, and the rest of the static review

Two independent static reviews of the combat / enemy / generator code. Every
provable finding below is now fixed and covered.

| Area | Cause | Fix |
|---|---|---|
| **The Warden's slam dealt no damage on any real floor** | `projectile.gd setup_wave()` ended with an ABSOLUTE `position.y = -16.0`, overwriting the y the caller computed. On generated floors (slab y 54..150) both waves - the slam's only damage source - spawned 10..106 px above the player's head. `arena.gd` puts its ground at y = 0, the one place -16 is right, so `soak` passed | offset moved into the caller's vector; the absolute write is gone. `tests/boss_probe.tscn` |
| Finisher waves flew through pillars | `function_wave.gd` masked ENEMY only, and `_on_body_entered` had no world branch | mask `ENEMY \| WORLD`; a body without `take_hit` bursts and frees |
| The climb hop and the anti-stuck hop were dead code | both gated on `state == CHASE`, but `_tick_chase` also runs from `IDLE`, so a body that had never been hit never qualified | `_is_walking()` = IDLE or CHASE. `tests/climb_probe.tscn` |
| Four of six enemy kinds could not follow you onto the gallery | no upward impulse except the leaper's hop | cooldown-gated climb hop (>40 px above, <220 px across) |
| The Ram telegraphed from beyond its own reach | `attack_range 300` vs a ~220 px lunge + hitbox | 300 -> 210 |
| Finisher wave had a hardcoded damage | literal `8.0` in `player.gd` | `wave_damage` per weapon in `data/weapons.json` (= finisher x 0.33) |
| The Aegis counter passed `attr = 0` | literal | `attribute_level("tactics")` |
| A dead floor could ship | `level_gen.generate()` computed `reachable` and no runtime code read it; `_verify` only `push_warning`s | retry up to `MAX_GENERATE_ATTEMPTS = 8` until the layout verifies |
| `_take_point`'s cramped fallback spawned the enemy ON the player | the loop reassigned its answer every iteration of a farthest-first list, so it returned the nearest | returns the head of the list; `audit_v1` asserts it directly |
| A spitter's glob followed you into the hub | `GlobPool` is parented to `fx_root` (= world), not to the level, and `_purge_world_fx` could not name an inner class | group `hazard_pool`, purged with the other world FX |
| J on a second station froze the body | the unfreeze lived in `Hub`, which cannot see whether the owner raised anything | the owner closes the station it refused (`audit_a4`) |
| Every hub visit leaked two CanvasLayers | Archive + SkillTree rebuilt without freeing the old pair | free before rebuild; `audit_v3` now asserts the count instead of printing it |

### Session 2 — things that existed but were unreachable

| Area | Cause | Fix |
|---|---|---|
| A run never offered a boon | `Game.request_rewards()` had one caller, in `Encounter`, which is only built when `start_mode == "arena"` | `Level.room_cleared` -> `Main` spends `data/floors.json` `reward` per cleared room |
| Clearing a room would have crashed | `Main._on_reward_chosen()` called `encounter.resume_after_reward()` unconditionally; `encounter` is null on a floor | guarded with `is_instance_valid` |
| `attribute` was a label | every `Damage.compute()` call site passed `0` for `attr` | `Hitbox.attr` / `FunctionWave.attr` / `Projectile.attr` fed from `Player.weapon_attr_level()` |
| Souls were unspendable | victory paid `+1`, nothing consumed it | `brutality` / `tactics` upgrades priced in souls; `Profile.upgrade_currency()` |
| spitter + leaper never spawned | present in `enemies.json`, absent from every floor | added to floors 2, 3, 4 |
| `_apply_loadout()` compounded | `roll_iframe_end +=`, `crit_bonus +=` | rebuilt from `BASE_ROLL_IFRAME_END` / `BASE_BONUS` constants; passives reset first |
| "monochrome" was ~10% blue | ramp `#08090b`… and two hardcoded UI greys | every value now `r == g == b` |
| 316 lines of dead renderer | `character_visual.gd` never wired in | deleted |

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
TESTS OK (118 checks)                run_tests.gd
PROBE OK                             combat probe
REWARD OK                            boon picker (+ colour reaches the weapon)
SOAK OK                              4 waves + boss + victory (arena mode)
ESC TEST OK (0 failures)             hub panels open/close/buy
FLOOR PROBE OK                       hub -> floor handoff, player can move
BOSS PROBE OK                        the Warden's slam lands on 4 floor-5 seeds
CLIMB PROBE OK                       grunt / charger / bulwark reach a high deck
RUN PROBE OK (0 failures)            5 floors -> victory -> hub, boon budget per floor
AUDIT A1 OK                          weapons / passives / armour / death
AUDIT A2 OK (123 checks)             save round-trip, economy edges, souls wallet
AUDIT A3 OK                          floor x seed reachability, spawns, gate
AUDIT A4 OK (226 checks)             key ownership, text fit
AUDIT V1 OK (0 failures)             vertical traversal, one-way, softlocks
AUDIT V2 OK                          decks, spitter, leaper from data, cells
AUDIT V3 OK (163 checks)             run flow, floor picker, state leaks
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

**Timing.** A plain run is **~350 s**, and almost none of it is assertions:
each step is its own Godot process (~1 s boot x 14) and several probes simulate
real time on purpose (walking a player across a 4200-6400 px floor at 300 px/s,
or waiting out the hub transitions).

```powershell
# Inner loop, one step, no --import
powershell -ExecutionPolicy Bypass -File tools\check.ps1 -Only audit_a3
# Everything except the seed sweeps + end-to-end run: ~77 s
powershell -ExecutionPolicy Bypass -File tools\check.ps1 -Fast
# Smoke only (fixed-fps 120, ~120 s). Can report FALSE FAILURES (audit_v2
# crowd separation). Never a commit gate.
powershell -ExecutionPolicy Bypass -File tools\check.ps1 -Turbo
```

Never shorten a wait loop into a fixed frame count to save time: `audit_a3` and
`run_probe` both did and both flaked under load. Wait for the condition.

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
9. **Generated surfaces must be gated by `_reach()` and `_headroom()`.** The
   map macro layer may only ADD surfaces; the BFS verification and the spawn
   filter are what keep a bigger map from shipping a softlock. Constants that
   describe a body (SPAWN_HALF_MIN 25, SPAWN_RADIUS 20, BODY_HEADROOM 72) must
   stay equal to the audits' numbers.
10. **A retry is not a run.** `restart_attempt()` may touch `Game` state only;
   any `Profile` call there re-introduces the bug it was written to fix.
9. Keyboard only, hints always visible.
10. Impact goes through `Combat.impact()`. Particles go through `Juice.*`.
11. **Monochrome means `r == g == b`.** No hue, no "almost grey". Any new
    colour must be authored neutral.
12. **Never pass `0` for the attribute level.** `Damage.compute(damage, attr,
    ...)` is the two-colour build; a hardcoded zero silently deletes it.
13. **Boons are paid per cleared room**, from `data/floors.json` `reward`.
    The exit gate is too late: `Game.finish_floor()` already banked the run.
14. **`_apply_loadout()` stays idempotent.** Rebuild accumulators from
    constants; never `+=` onto an exported default.
15. **Arena mode is a fixture.** `Arena`, `Encounter`, `Runes`, `Braziers`,
    `Motes` are built only when `start_mode == "arena"` (tests). Gameplay
    features added there never reach a player.

---

## 6. Fragile spots / known limits

| Risk | Detail |
|---|---|
| ~~`_apply_loadout()` is one-shot~~ | fixed: every accumulator is rebuilt from a constant now |
| Hub camera limits | the hub widens `camera.limit_*`; `Main.start_floor()` must reset them or the view clamps at the hub's edges |
| `--check-only --script` is unreliable | autoload globals are missing, so it reports false `Identifier not found: Game`. Verify by running a scene, not a single script |
| Level draw cost | ~500 specks + cracks per floor, drawn once and never re-queued. Fine now; watch it if floors get wider |
| No export preset | Godot export templates (~1.28 GB) are not downloaded |
| English only | no CJK font, so no Chinese UI |
| Weapon unlock cost | weapons use `unlock_cost`, armour/characters use `cost`; `Profile.unlock` reads both |
| `rose_bloom(petals=6)` | renders 3 lobes — `r = cos(kθ)` closes at integer k |
| `Main.auto_rewards` | harness-only switch; it bypasses the picker, so a real run must never set it |
| Boon cadence is unplayed | rooms pay a boon the moment they are cleared; nobody has judged whether that interrupts the climb |
| Souls cap out early | two soul upgrades x 5 levels = 10 souls, and a clear pays 1 |
| No save-slot UI | one profile, `user://ashfall_profile.json` |
| `Hub.is_open()` covers `HubUi` only | the archive/tree are separate layers; `Main._any_panel_open()` is the real guard |
| A fixture that agrees with a hardcoded coordinate hides every bug in it | the boss slam was only ever tested in `arena.gd`, whose ground is at y = 0 - the one place the wrong absolute `-16` is right. Any test that builds the arena is blind to floor-relative maths; use `boss_probe` (a real `Level`) |
| The boss is probe-covered, not playthrough-covered | `boss_probe` proves the slam spawns waves at the warden's feet on 4 seeds; nobody has fought it on a generated floor |
| Enemy body is now PALE | `enemy_visual.gd _body_fill()` used `MathArt.STONE`, which is the floor's own value, so enemies dissolved on stone. If you change the floor's fill, re-check the enemy against it |

---

## 7. Next steps (highest value first)

1. **Playtest the two-tier maps.** The generator proves reachability (75 seeds
   in audit_a3, 200 in audit_v1, 100 in gen_stats) and a physical walk per
   floor, but nobody has judged whether the upper route is *legible* or whether
   the caches are worth the detour.
2. **The far plane of a floor is still too dark** — the ambience pass ran out
   of budget. `_draw_vault()` is the place.
3. **Boon cadence at the new size.** A 7-room floor pays 3 boons; with 5-7
   rooms that is one reward every other room. Judge it before changing it.
4. **Give souls a longer runway** (10 souls exists today) and a second boss.
5. **Export preset** if a distributable build is wanted.

## 8. Map of the code

```
scripts/autoload/   data.gd  profile.gd  game.gd  combat.gd  sfx.gd
scripts/systems/    math_art.gd  geom3d.gd  juice.gd  damage.gd  layers.gd
scripts/meta/       hub.gd  hub_ui.gd
scripts/world/      level.gd  level_gen.gd                    (the real loop)
                    arena.gd  encounter.gd  braziers.gd  runes.gd  motes.gd
                                                         (arena-mode fixture)
scripts/player/     player.gd  player_visual.gd  weapon_visual.gd
                    player_camera.gd
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
