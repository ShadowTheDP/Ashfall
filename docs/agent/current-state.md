# Current State

## Current Objective

Milestone 2 is complete: the whole game renders as **640x360 pixel art** with
integer upscaling, and combat animation follows the standard action-game frame
order (anticipation -> smear -> impact -> follow-through -> secondary motion).
Next is human playtest tuning, then breadth.

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
- **Pixel pipeline**: 640x360 logical, x2 integer upscale, nearest filter,
  camera zoom 1.0, rounded camera position, no camera rotation.
- **Combat animation**: anticipation coil + body squash, one solid smear wedge
  (two on the finisher), 2-frame white impact silhouette on enemies, 10-14 deg
  overshoot with a 55/30/15 ease-out, 1-frame secondary lag on tip and body.
- **Defensive feedback**: `BurstFx` covers perfect dodge (8 rays, 3 frames +
  2-frame freeze), Aegis block (solid sector then expanding ring) and taking a
  hit (4 red rays at the contact edge).
- **Audio**: 18 synthesized SFX + a 32 s mathematically seamless music loop.

## Current Decisions

- Art must go through `MathArt.px_*`; no textures, no `Sprite2D`, and no
  anti-aliased draw calls. Style comes from constraint, not from more elements.
- The camera never rotates and its position is rounded every frame; any
  sub-pixel motion is a bug at 640x360.
- HUD text uses whole-pixel baselines and sizes 6-28.
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

1. Real playtest tuning pass: attack commit length, hitstop duration, Warden
   telegraph readability, Aegis cooldown, and whether the smear frames read
   clearly at x2.
2. A second weapon function with a different curve (e.g. a Lissajous flail or
   a rose-petal area attack) to prove the weapon schema generalizes.
3. A second handcrafted arena and a doorway transition before any generator
   work (pillar 2 first slice).
4. Room-template data format + a hand-authored 3-room chain, no randomness yet.
5. Replace the 7 generic boons with the three-attribute (red/purple/green)
   scroll system once there are enough weapons to scale.
6. Export presets and a Windows build once templates are installed.
