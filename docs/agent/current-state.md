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
