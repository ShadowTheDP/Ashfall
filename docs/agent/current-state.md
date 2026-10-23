# Current State

## Current Objective

Milestone 0 is complete: a runnable, original Dead-Cells-like combat prototype
with a full 3-wave loop. The next phase is feel iteration and breadth, not more
systems at once.

## What Exists

- One handmade arena (`Arena`) with ground, platforms, walls, ambient motes,
  parallax-ish pillars and fog.
- Player: run/air/roll/attack/hurt/dead state machine, 3-hit sword combo,
  input buffering, cancel windows, coyote time, jump buffer, variable jump
  height, roll i-frames, post-hit invulnerability, knockback, landing squash.
- Combat feedback: hitstop, camera trauma, slash arcs, hit sparks, damage
  numbers, crits, combo counter, low-health pulse, synthesized SFX.
- Enemies: Husk (melee), Watcher (projectile), Ram (charge), each with a
  visible telegraph and exposed/crit window.
- Loop: 3 authored waves, between-wave heal, cell drops with magnet, death and
  victory overlays, R to restart.
- HUD: health, cells, wave, hostiles, combo timer, run timer, control hints,
  pause menu.
- Data tables: `data/weapons.json`, `data/enemies.json`.

## Current Decisions

- Feel-first order; rooms/builds/meta are deliberately deferred.
- Actor scenes are root-only; children are built in code.
- Damage formula lives only in `Damage`; crits require an exposed enemy.
- Enemy spawn pools are split by type (melee=ground, archer=platform).
- HUD is above the vignette so UI colors are not dimmed.
- Input actions are runtime-registered; document the shortcut until a settings
  screen exists.
- Placeholder SFX are generated, not sourced.

## Structure Assumptions

- `scripts/autoload/` = cross-scene services.
- `scripts/systems/` = pure logic and constants.
- `scripts/player|enemies|world|fx|ui/` = feature code.
- `data/` = content numbers.
- `tests/` = headless checks and capture harnesses.
- `output/` = screenshots/builds (ignored).

## Next Likely Improvements

1. Tune the feel with a real playtest pass: attack commit length, hitstop
   duration, camera zoom, enemy windup vs. player roll timing.
2. Add one more melee enemy archetype that forces a different dodge (e.g.
   lunging stab or area slam) to stress the roll/cancel loop.
3. Add a second handcrafted arena and a doorway transition to test camera
   limits and room handoff before any generator work.
4. Add a minimal room-template data format and a hand-authored 3-room chain
   (pillar 2 first slice), without procedural generation yet.
5. Add a weapon-data-driven second weapon (ranged or heavy) to prove the schema
   before building the full Build system.
6. Add export presets and produce a Windows build once templates are installed.
