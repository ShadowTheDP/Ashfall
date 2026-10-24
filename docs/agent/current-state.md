# Current State

## Current Objective

Milestone 3 is complete: **768x480 monochrome**, motion-first rendering with
float transforms and 120 Hz physics interpolation. The player is a square that
tumbles 90 degrees per jump and lands on a new face; enemies are plain polygons
with no limbs; all particles come from Godot's `CPUParticles2D`. Next is human
playtest tuning, then breadth.

## What Exists

- **Title screen** (`TitleScreen`): rose window + Lissajous + phyllotaxis +
  log spiral; pauses the tree, ENTER starts the run.
- **Player**: run/air/roll/attack/hurt/dead state machine, 3-hit sine sword,
  input buffering, cancel windows, coyote time, jump buffer, variable jump
  height, roll i-frames, post-hit invulnerability, landing squash.
- **Weapons as functions**:
  - `J` Sine Edge — 3-hit combo; the blade is a straight line driven by an
    angle function, and the finisher releases `FunctionWave` (a travelling
    sine wave drawn as 1px columns, piercing).
  - `K` Kunai — `MathArt.ballistic_velocity()` solves `v0` for the nearest
    enemy, `ParabolaFx` previews the arc, `Projectile` integrates gravity.
  - `L` Aegis — three concentric pixel rings + six orbiting dots; blocks a hit
    and fires a close-range counter pulse.
- **Perfect Dodge**: rolling through an attack grants 2.5 s of +25% damage and
  refunds one kunai; tracked and shown in the run summary.
- **Enemies** (shape language): Husk (triangle), Watcher (circle + orbit,
  ballistic arrows with real path preview), Ram (square charge), Bulwark
  (hexagon, front hits chip 1 hp unless crit/backstab), **The Warden**
  (pentagon + pentagram boss with cleave / charge / shockwave).
- **Boons**: 7 keyboard-picked upgrades between waves (`data/rewards.json`),
  applied in `Game.apply_reward()`.
- **Loop**: 4 waves (3 normal + boss), between-wave heal, cell drops with
  magnet, death/victory overlays, R to restart.
- **HUD**: health, cells, kunai charges, Aegis cooldown, wave, boss bar,
  combo ring, Perfect Dodge / EDGE timer, build summary.
- **Visual system**: `MathArt` pixel primitives everywhere (`px_rect`,
  `px_circle`, `px_ring`, `px_arc`, `px_line`, `px_poly`); no anti-aliased
  drawing is reachable. Dithered vignette, tight nearest-filtered bloom.
- **Rendering pipeline**: 768x480 logical, x2 integer upscale, linear filter,
  120 Hz physics + interpolation, float camera in `_physics_process`, no
  rounding anywhere in gameplay transforms.
- **Monochrome**: one greyscale ramp in `MathArt`; no hue anywhere.
- **Player is a plain square**: white body, black inset face, white core dot,
  2px keyline. No notch, no pip, no eyes (removed after playtest feedback).
  Tumble completes in 0.42 s; short hops settle in 70 ms.
- **Weapon geometry is unified**: grip on the front edge, blade length from
  `data/weapons.json`, hitbox derived from the same number, slash arc centred
  on the grip.
- **Impact is tiered**: `Combat.impact()` with hitstop 2/4/6/8 frames, tiered
  spark/ring tables, zoom punch, vignette pulse and 2-frame scanline offset.
  Spec: `docs/design/impact.md`.
- **No limbs**: enemies are plain polygons; hands are dots.
- **Particles**: `scripts/systems/juice.gd` wraps `CPUParticles2D` with nine
  presets (dust, land_dust, jump_burst, hit_sparks, shatter, pickup, block,
  dodge, telegraph).
- **Combat animation**: anticipation coil + body squash, one solid smear wedge
  (two on the finisher), 2-frame white impact silhouette on enemies, 10-14 deg
  overshoot with a 55/30/15 ease-out, 1-frame secondary lag on tip and body.
- **Defensive feedback**: `BurstFx` covers perfect dodge (8 rays, 3 frames +
  2-frame freeze), Aegis block (solid sector then expanding ring) and taking a
  hit (4 red rays at the contact edge).
- **Audio**: 18 synthesized SFX + a 32 s mathematically seamless music loop.

## Current Decisions

- Art must go through `MathArt`; no textures, no `Sprite2D`. Style comes from
  constraint, not from more elements.
- Monochrome is a hard rule; readability is engineered through value contrast,
  keyline weight and motion.
- Motion fluidity beats pixel snapping: no rounding of gameplay transforms.
- HUD text sizes 8-38, laid out on a proportional grid at 768x480.
- Weapons and enemy telegraphs express their actual math (ballistic preview,
  sine wave, radial field).
- Keyboard-only is a hard requirement; gamepad is additive.
- Feel-first order; rooms/builds/meta are deliberately deferred.
- Actor scenes are root-only; children are built in code.
- Damage formula lives only in `Damage`; crits require an exposed enemy or a
  backstab.
- HUD renders above bloom so text stays crisp.
- Boss is immune to stun-lock (`boss` flag).
- Tests run as scenes when they need autoloads; `--script` has no autoloads.

## Structure Assumptions

- `scripts/autoload/` = cross-scene services.
- `scripts/systems/` = pure logic, constants, and the `MathArt` visual language.
- `scripts/player|enemies|world|ui|fx|combat/` = feature code.
- `data/` = content numbers.
- `tests/` = headless checks and capture harnesses.
- `output/` = screenshots/builds (ignored).

## Next Likely Improvements

1. Real playtest tuning pass on impact: is a light hit distinct enough from a
   finisher; does the crescent smear read as a blade trail; is the zoom punch
   too strong; do the scanlines feel like a glitch rather than damage.
2. A second weapon function with a different curve (e.g. a Lissajous flail or
   a rose-petal area attack) to prove the weapon schema generalizes.
3. A second handcrafted arena and a doorway transition before any generator
   work (pillar 2 first slice).
4. Room-template data format + a hand-authored 3-room chain, no randomness yet.
5. Replace the 7 generic boons with the three-attribute (red/purple/green)
   scroll system once there are enough weapons to scale.
6. Export presets and a Windows build once templates are installed.

## Latest

- `docs/PRODUCT.md` written: full business overview (product definition,
  runtime graph, module ownership table, game loop, all combat/enemy numbers,
  data flow, audio, validation matrix, hard rules, known limits, milestones).
- Blade geometry: one tapered quad instead of two parallel lines (the L-shape).
- Smear: three concentric thin arcs with a **0.32 rad gap before the blade**.
  The gap is load-bearing - if the trail touches the tip, blade + trail read
  as an L again. Do not reduce it below 0.28.
- Warden pentagram is now inscribed on the body's own five vertices
  (`ngon(5, r*1.15, -PI*0.5, Vector2(0,1))`, chord i -> i+2) and drawn
  **after** the body fill, otherwise the fill hides it. Crown ticks removed.
- Shadows (player + enemies) are three stacked 20-gons, cumulative centre
  density ~0.30, no hard rectangle anywhere.

## Session end (maps, impact, hub)

All work committed. **Read `HANDOVER.md` at the repo root before anything
else.**

State: `tools/check.ps1` green (17 steps). Floors are now large two-tier
spaces (5600-8200 px, 5-7 rooms, 29-42 surfaces each), the hub is a layered
room rather than a platform, and combat feedback has a heavier top end.

This session:

1. **Fixed R inside a floor.** `Hud._restart()` called
   `reload_current_scene()`, which rebuilt Main -> title -> hub, and because
   `Game.start_floor()` advances `Profile.best_floor` on ENTRY, the door then
   offered the next floor: a retry banked progression and skipped a floor.
   `Main.restart_attempt()` now replays the chosen floor through
   `Game.reset_run()` (Game-only state; Profile untouched), frees the previous
   body, purges stale projectiles and cancels the pending transition.
   Regression: `tests/restart_probe.tscn` (paused retry and dead retry).
2. **Map macro layer** (`level_gen.gd`): `_link_gallery` bridges gaps at the
   height of each room's own upper deck, `_stack_ladders` adds climbable rungs
   where a pillar is not, `_caches` puts cell caches on high decks. All three
   are gated by the same `_reach()` predicate the BFS uses, plus a new
   `_headroom()` guard (a generated surface may not become a ceiling over
   another at < 72 px) and a `_inside_any()` spawn filter. Witness:
   `tests/gen_stats.tscn` (100 layouts).
3. **Pillar placement** now leaves a 46 px slot on the approach side, flush
   against the next room: it used to leave a 23 px crack a 28 px body could
   not enter, which was a real softlock (audit_a3's walk cases caught it).
4. **Spawn clearance** aligned with the audits' FALLBACK_BOX (`SPAWN_HALF_MIN`
   25). Generation used the room's own tallest body (21 for grunts) while the
   audits check 25, so a point 24 px under a deck passed generation and failed
   the audit.
5. **Impact** (`impact_fx.gd`, `combat.gd`, `enemy_visual.gd`, `juice.gd`):
   per-tier shape language, crit halo, kill implosion, directional block
   shell, boss telegraphs. Eight new `Juice` presets (ember_drift,
   shaft_motes, debris_poly, kill_implosion, speed_lines, block_shell,
   boss_slam).
6. **Hub** (`hub.gd`): far vault + arches, light shaft with motes, hanging
   chains and censers, rose wheel, floor inlay, a real foreground colonnade,
   and brighter stations.
7. **Panels** (`hub_ui.gd`, `skill_tree.gd`, `archive_screen.gd`) and the
   **HUD** (`hud.gd`) rebuilt on a φ grid with plates, segmented health,
   tally-based floor progress and timer arcs.
8. **Cell caches** are pickups that rest in place (`CellPickup.resting`).

Immediate follow-ups:
1. Playtest the new maps: is the upper route legible, are the caches worth the
   detour, does the room-by-room boon cadence still feel right at 5-7 rooms?
2. The far plane of a floor is still dark; the level ambience pass ran out of
   time there.
3. Combo / EDGE / boss HUD plates are verified statically only - the capture
   harness never has a combo or a boss in frame.

## Session (bug hunt on combat + generator, art readability)

State: `tools/check.ps1` green (17 steps, 424 s). Two independent static
reviews of the combat / enemy / generator code were read and every provable
finding fixed. New probes: `tests/boss_probe.tscn` (the Warden's slam lands on
four floor-5 seeds) and `tests/climb_probe.tscn` (grunt / charger / bulwark
close a 162 px gap to a high deck).

The one that matters: **the final boss could not damage the player on any real
floor.** `projectile.gd setup_wave()` ended with an absolute `position.y =
-16.0` that overwrote the caller's y, so both shockwaves - the slam's only
damage source - spawned 10..106 px above the player's head on every generated
floor. The arena fixture puts its ground at y = 0, which is the one place -16
is correct, so `soak` passed. Lesson: a fixture that agrees with a hardcoded
coordinate hides every bug in that coordinate.

Also fixed: finisher waves flew through pillars; the climb and anti-stuck hops
were gated on a state that untouched bodies never enter (dead code); four of
six enemy kinds could not follow the player onto the gallery; the Ram
telegraphed from beyond its own reach; the finisher wave had a hardcoded
damage; `level_gen` computed a reachability verdict nobody read (a dead floor
could ship); `_take_point`'s cramped fallback spawned the enemy on top of the
player; a spitter glob followed the player into the hub; J on a second station
froze the body; every hub visit leaked two CanvasLayers.

Art: enemies are PALE with an INK core (their old fill was the floor's own
value, so they dissolved on stone); the slash trail is thick enough to see;
the floor's far wall reaches the walkable line and carries a value gradient,
masonry and real niches; chains end inside the frame instead of above it; the
hub foreground colonnade sits in the gaps between stations.

Next:
1. Playtest the boss on floor 5 for real - it is still only probe-covered.
2. The combo / EDGE / boss HUD plates are still verified statically only.
