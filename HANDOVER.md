# Ashfall — Handover

> Read this first. It is the state of the project at the end of the session
> that added the hub, procedural floors, characters, weapons and the vertical
> level generator. `docs/PRODUCT.md` is the full business overview; this file
> is what changed, what is fragile, and what to do next.

---

## 0. Pick up here (2026-10-25)

**State:** `tools/check.ps1` green, 17 steps, `ALL CHECKS PASSED` in 478 s
(`-Fast` 100 s). Everything below is committed. Nothing is half-finished and
nothing is known-broken; the open items are judgement calls, not bugs.

**Read before touching anything:**
1. `docs/design/map-generation.md` — the generator contract. `data/rooms.json`
   is authored content; `LevelGen` only chooses and verifies. Two invariants
   (`MAX_UP` 100 px climb, `BODY_HEADROOM` 72 px between overlapping tops) are
   enforced and asserted by `gen_stats` + `climb_probe`.
2. `docs/design/impact.md` §2.1 — the four tier signatures.
3. `MEMORY.md` → "Stable Decisions" and "Verification Status".

**Three highest-value next tasks** (in order):
1. **Playtest the templates.** `tests/map_capture.tscn` renders a whole-floor
   overview plus one in-game shot per room for all five floors into
   `output/screenshots/map/`. Judge: is `well_double` fun, is the annex worth
   the climb, is 8-11 rooms per floor the right density. Then tune
   `data/rooms.json` / `data/floors.json` `beats` — not the generator.
2. **Give the beat sheet a branch.** It is still a 1-D sequence. A beat that
   forks and rejoins is the honest next step toward Dead Cells' concept graph;
   `_verify()`'s BFS already tolerates any topology, so the work is in
   `_pick_kinds()` / `_generate_once()` and in `Level`'s room-entry spawn.
3. **Annex enemies** — only after a spawn filter that provably keeps them
   killable. The annex is empty today on purpose (see §2.0).

**Commands.** `tools\check.ps1 -Fast` for the inner loop (~100 s),
`-Only "<step>"` for one step, a plain run before any commit. Visual:
`tests\map_capture.tscn`, `tests\meta_capture.tscn`,
`tests\impact_capture.tscn` (all need a display).

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
| Floors | 5 | 5600 / 6800 / 7000 / 8200 / 3400 px |
| Rooms per floor | 8 / 9 / 10 / 11 / 3 | beat sheet per floor, 6 kinds x 2-3 authored templates |
| Surfaces per floor | ~59 / 66 / 73 / 80 / 22 | slabs + decks + gallery + ladders + annexes |
| Enemies | 6 + boss | grunt, archer, charger, bulwark, spitter, leaper, warden |
| Enemies per floor | 9 / 11 / 13 / 17 / 5 | spitter + leaper spawn on 2-4 |
| Caches per floor | 3 / 3 / 3 / 3 / 2 | 1-2 of them are annex caches at 2x value |
| Playable bodies | 6 | square, octa, star, torus, helix, gyro |
| Weapons | 6 | edge, curve, lens, fractal, chain, orbit |
| Armour | 5 | none, plate, lattice, mantle, aegis shell |
| Upgrades | 7 cell + 2 soul | hp, damage, speed, knives, iframe, crit, cells; brutality, tactics cost souls |
| Skill nodes | 11 | 3 roots, 1 apex |
| Boons (in-run) | 7 | from `data/rewards.json`; 4 carry a colour |
| Boons per floor | 2 / 2 / 3 / 3 / 0 | `data/floors.json` `reward`, paid per cleared room |

---

## 2. What this session built

### 2.0 Session 5 — hand-authored room chunks, beat sheets, annexes

See `docs/design/map-generation.md` for the full contract. In short:

- **`data/rooms.json` (new).** 18 hand-authored room templates, 2-3 per kind,
  in the same data-driven style as every other content table. The generator no
  longer invents room interiors; it picks an authored tile for a room whose
  role and width fit, exactly the hybrid split Dead Cells' lead designer
  describes (fixed frame → hand-made tiles → per-level concept graph → fit).
- **`beats` in `data/floors.json` (new).** Each floor carries a role sequence
  (`entry / combat / climb / treasure / elite / exit`). The role decides which
  kinds may fill the room and how much of the enemy budget it asks for. Two
  seeds of one floor now read as the same place rearranged, not two unrelated
  corridors.
- **`_plan_enemies()` is a distribution, not a spray.** The total from
  `data/floors.json` is unchanged (the audits assert it); the heaviest bodies
  pick their rooms first, one per room, and the entry room is always empty.
  Boss floors' extra enemies finally spawn (floor 5's 3 grunts + 2 archers were
  dead data because `_plan_enemies` returned early).
- **Annex chambers (`_annexes`).** One or two rooms per floor grow a real
  destination two tiers above their own top deck, holding the floor's biggest
  cache (2x value). The upper route used to be continuous but pointless.
- **`_close_narrow_holes()`.** Two same-tier decks with a 40 px crack between
  them are a softlock trap (no body can land in the crack, and a player on the
  deck above is unreachable). The generator now closes any such crack.
- **Floors are longer and more compact.** 8 / 9 / 10 / 11 rooms instead of
  5 / 6 / 6 / 7 at the same widths (~700 px per room, ~59-80 surfaces), so a
  floor reads as a chain of compact vertical rooms rather than a row of wide
  halls. Cost: a plain `check.ps1` run went from ~350 s to ~470 s.
- **Floor 5 is three rooms** (3400 px): entry, elite, throne. Its declared
  enemy table now actually spawns in the approach room.
- **Annexes hold no enemies.** They are the reward, and a body up there would
  make an optional detour mandatory (the gate needs every body dead).
  `gen_stats` asserts it.
- **Cells picked up after the gate fires are banked on the spot**
  (`Game.bank_cells_now`). The bodies killed on the way to the gate drop cells
  into the 1.6 s transition, and the hub used to wipe that pile.
- **`tests/map_capture.tscn` (new).** Whole-floor overview plus one in-game
  shot per room, every floor — the visual witness for all of the above.
| Perfect dodge paid for a hit stopped by post-hit invulnerability | the reward was gated on `is_invulnerable()`, which is also true for the 0.55 s hurt tail | gated on `is_roll_invulnerable()` (the roll window only) |
| Dancer's EDGE buff was multiplied twice | `Game.perfect_dodge()` already scales by `perfect_dodge_scale`, and `take_hit` scaled again | 4x became the intended 2x; audit_a1 now asserts the exact value |
| A bulwark killed by a 1-damage shield chip popped at the last swing's tier | the shield branch never touched `last_tier` | chip sets `last_tier = 0` |
| Enemies spawned inside annex chambers | the spawn pass ran after `_annexes()` and offered a point above every platform | annex chamber, landing and walls are removed from the settle/surface set |
| A pillar's step deck could be drawn through an authored mass | one in-order draw pass put the late-appended deck over the earlier solid | `Level._draw()` paints every pass-through deck first, then every solid |
| The camera's top limit was a hardcoded -820 | a promise that goes stale the first time a template or annex grows | computed in `start_floor()` from the floor's own highest surface; audit_v3 checks the inequality |
| The builtin fallback layouts skipped the narrow-crack invariant | `_close_narrow_holes()` was only called from the template path | called on both paths, so a missing `data/rooms.json` cannot restore the trap |
| HUD cells plate froze at 0 in the arena fixture | it printed `run_cells`, which only exists on a floor | three-way rule (bank / run / run total) |
| End-of-floor overlay advertised a hub return that never happens in arena mode | the line was unconditional | printed only while `Game.hub_return_in > 0` |
| Pausing during the scene-change fade froze an opaque black screen | the veil sits above the HUD and Main's `_process` stops when paused | pause is refused while a hub return is pending |

Session 4 (previous) follows.

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

### Session 5 — the map, the feedback and the flow

| Area | Cause | Fix |
|---|---|---|
| Floor picker at the hub door did nothing on the second press | A/D are also the movement keys, and movement is polled (`Input.get_axis`), so consuming the key did not stop the body: the same press walked the player out of the door's REACH | picker moved to **Q / E**, which are unbound; audit_v3 now drives both |
| Roll i-frames past 0.30 s did not exist | the gate was `state == ROLL and roll_t <= roll_iframe_end` while the ROLL state ends at `roll_time` 0.30, so armour + GHOST + GLASS (up to 0.43) were clipped - a purchased upgrade that provably did nothing | `roll_iframe_t` counts from the roll's start and is independent of the state; `is_invulnerable()` uses it |
| Every melee hit's sparks/ring/flash spawned inside the PLAYER | `Hitbox` sent `"point": global_position` - the attacker's own centre - while the damage number popped on the enemy | the point is `body.global_position`; the player's own hurt spark moved to the contact edge |
| Kill feedback ignored the hit that killed | `_die()` always used tier 1 (2 for a boss) | the killing hit's tier is stored in `last_tier` and used, so a finisher kill is the loudest thing in a fight |
| Being hit felt identical for 6 damage and 18 | one fixed 0.09 s freeze / 0.6 shake for every source | scales with damage; only a heavy hit adds the screen punch |
| Per-weapon `hitstop` in `data/weapons.json` was dead data | nothing read `info["hitstop"]`; only `tier` did | field removed from the data and the two doc tables, with a note pointing at the tier table |
| Finisher wave spawned 1 px inside the floor | the 88x68 box bottom sat at origin+24 while the player's feet are at origin+23 | raised to origin-18 |
| Roll cancelled into an attack skipped its own cooldown | `_tick_roll` exited into `_start_attack` without setting `roll_cd` | set before the cancel |
| Archer / spitter retreat walked off ledges | `hold = -facing * speed` bypassed `_gate()` | goes through the ledge gate like every other intent |
| Two rooms clearing in one frame paid one boon | the second deferred call bailed on `reward_open` and never decremented | the owed boon waits in `_owed_rewards` and is paid from `_on_reward_chosen` |
| A spitter's pool followed the player into the hub | `enter_hub()` never purged the world's hazard pools (only `start_floor()` did) | `_purge_world_fx()` runs on the way into the hub |
| A death after the gate banked the floor was recorded as a loss | `finish_floor()` leaves the level running for 1.6 s | `Main._cleared_floor` makes that death a plain exit instead of `end_run(false)` |
| `Profile.total_kills` recorded only the last floor | `start_floor()` zeroed `run_kills`, which `end_run()` persists | reset lives only in `reset_run()` |
| Cache placement was not reproducible per seed | `_caches()` trimmed with a global-RNG `shuffle()` | seeded index pick; annex caches are kept first and unconditionally |
| HUD read `CELLS 0` in the hub | the plate printed `Game.cells`, a run counter, while the hub header printed `Profile.cells` | hub shows the bank, a floor shows what the run has earned (what a death forfeits) |
| Hub station never refreshed the body | a purchase writes Profile only | `Hub._on_panel_closed()` re-runs `_apply_loadout()` |
| Title screen advertised Q QUIT / R / Esc that did nothing | the title is a modal the HUD deliberately ignores | Q quits, the dead hints are gone |
| HUD hint strip contradicted an open panel | `_draw_hints` was unconditional | hidden while a modal is open; the hub line is contextual |
| Skill tree said "NEED n CELLS" when the blocker was a prerequisite | cost was tested before parents | parents first |
| "LEFT/RIGHT PAGE" printed on a single-page list | hint was unconditional | only printed when `pages > 1` |
| End-of-floor overlay offered R while a timer took the player to the hub | no countdown anywhere | `Game.hub_return_in` is printed under the headline and in the overlay |

Session 4 (previous) follows.

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
AUDIT V3 OK (165 checks)             run flow, floor picker (Q/E), camera limits
ALL CHECKS PASSED
```

Visual harnesses (need a display):

```
tests/capture_scene.tscn    13 gameplay shots
tests/impact_capture.tscn   20 frame-by-frame impact shots
tests/meta_capture.tscn     14 hub/floor/archive shots
tests/map_capture.tscn      whole-floor overview + one shot per room, every floor
tests/title_capture.tscn    title
tests/jump_capture.tscn     tumble frames
```

Output goes to `output/screenshots/` (gitignored).

**Timing.** A plain run is **~478 s** (it was ~350 s before the floors went from
5-7 rooms to 8-11; `audit_v1` alone is ~185 s because it walks every room of 40
seeds x 5 floors), and almost none of it is assertions: each step is its own
Godot process (~1 s boot x 17) and several probes simulate real time on purpose
(walking a player across a 5600-8200 px floor at 300 px/s, or waiting out the
hub transitions).

```powershell
# Inner loop, one step, no --import
powershell -ExecutionPolicy Bypass -File tools\check.ps1 -Only audit_a3
# Everything except the seed sweeps + end-to-end run: ~100 s
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

1. **Playtest the templates.** `gen_stats` proves shape and reachability across
   100 layouts; nobody has judged whether `well_double` is fun or whether the
   annex is worth the climb. `map_capture` is the tool for that judgement.
2. **Annex enemies.** The annex is empty on purpose (an unreachable body would
   block the gate). With a proven spawn filter it could hold one ranged body.
3. **A branch in the beat sheet.** Beats are still a 1-D sequence; the honest
   next step toward Dead Cells' graph is a beat that forks and rejoins.
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
                    rooms.json                    (authored room templates)
tests/              run_tests.gd  combat_probe  reward_probe  soak
                    esc_probe  floor_probe  run_probe
                    audit_a1..a4  audit_v1..v3
                    capture_scene  impact_capture  meta_capture
                    map_capture   title_capture  jump_capture
tools/              check.ps1  fetch_godot.ps1  make_sfx.py  make_music.py
docs/               PRODUCT.md  agent/  design/  (design/map-generation.md
                    is the generator contract)
```

## 9. Reading order for the next person

1. `docs/PRODUCT.md` — the whole picture
2. `docs/design/map-generation.md` — the generator contract (beat sheets,
   authored templates, annexes, the two invariants) **before touching level_gen**
3. `docs/design/meta.md` — hub / floors / progression contract
4. `docs/design/math-art.md` — visual language
5. `docs/design/impact.md` — combat feel, especially §2.1 (tier signatures),
   §7 (the trail) and §8
6. `AGENTS.md` → `MEMORY.md` → `docs/agent/current-state.md`
