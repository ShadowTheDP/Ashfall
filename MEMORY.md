# Ashfall Memory

## Purpose Snapshot

- `DC-like` / codename **Ashfall** is an original roguelite-metroidvania
  combat-feel prototype.
- It exists to prove the fight loop first; content and meta progression come
  later.
- No Dead Cells code, art, audio, levels, or extracted data. All visuals are
  drawn procedurally; all SFX are synthesized by `tools/make_sfx.py`.

## Stable Decisions

- **Engine:** Godot 4.7.2, GL Compatibility renderer.
- **Resolution:** 768x480 logical, window 1536x960, integer x2, `viewport`
  stretch. Bumped from 640x360 because the pixel grid was too coarse.
- **Motion first, not pixel snapping.** Characters and camera move on floats;
  there is no per-frame rounding. The trade is that a fast object can land on
  a half pixel; that is accepted in exchange for smooth motion.
- **Physics:** 120 Hz with `physics_interpolation=true`. Camera runs in
  `_physics_process` so interpolation carries it (Godot warns that Camera2D is
  forced to physics mode - that is expected and correct).
- **Monochrome (hard rule):** no hue anywhere. `MathArt` defines a fixed
  greyscale ramp (`INK..WHITE`) plus semantic aliases (`PLAYER`, `ENEMY`,
  `BOSS`, `PICKUP`). Readability comes from value contrast, outline weight and
  motion. `scripts/systems/math_art.gd` is the only place colours are defined.
- **Zero art assets:** every visual is drawn in `_draw()` through
  `scripts/systems/math_art.gd`. No textures, no `Sprite2D`. See
  `docs/design/math-art.md`. This is a hard rule, not a temporary state.
- **Weapons are functions:** Sine Edge is a straight blade driven by an angle
  function (readability comes from smear + overshoot, not from bending the
  blade); the finisher releases a travelling sine wave drawn as 1px columns;
  Kunai solves a ballistic `v0` and previews the parabola; Aegis is three
  concentric pixel rings plus six orbiting dots.
- **Player silhouette is a PLAIN SQUARE**: white body, black inset face, white
  core dot, 2px black keyline. No notch, no edge pip, no eyes - the user
  confirmed the tumble itself is readable enough, so all the extra marks were
  removed. Enemies have no eyes either.
- **Tumble:** every jump turns the square exactly 90 degrees
  (`face = (face + 1) % 4`), completed over 0.42 s; short hops finish the
  remaining quarter turn in 70 ms instead of snapping. Direction follows
  `facing`.
- **No limbs anywhere.** Enemies are plain polygons; a "hand" is a single dot.
  Legs and arms were removed from every draw function.
- **Grip sits on the square's front edge** (`facing * 13, -7`), not inside the
  body, and the blade angle mirrors with facing. Blade length lives in
  `data/weapons.json` (`blade`) and the hitbox is derived from it, so the drawn
  blade, the slash arc and the damage box are always the same numbers.
- **Impact is tiered** (`Combat.impact(point, direction, tier)`): tier 0/1/2/3
  drives hitstop 2/4/6/8 frames, shake, zoom punch and the spark/ring tables in
  `scripts/fx/impact_fx.gd`. Crits bump one tier. Multiple hits in one frame do
  not stack. Full spec: `docs/design/impact.md`.
- **Smear is drawn with DISCONNECTED STRAIGHT LINES, never a filled shape.**
  At 38-50 px blade length any solid crescent or wedge reads as a "mooncake".
  Four radial rows x three tangential streaks, each tangent to the blade path,
  plus a 3px tip streak. Broken lines cannot enclose a shape, so they read as
  speed. Do not reintroduce `draw_colored_polygon` bands here.
- **Grip is in the LOWER half of the square** (`facing * 13, +4`) and the sword
  rests pointing UP (`REST_ANGLE = -1.30` rad); swings run from up-back to
  front-down.
- **Pure flat 2D**: no squash, no stretch, no scale on any character. Player and
  enemies use rotation + translation only (`_body_scale()` returns ONE). Enemy
  lean reduced to +/-0.10-0.12 rad so rigid bodies tilt instead of folding.
- **The Watcher has no bow**: it attacks directly, with a contracting ring
  during windup and three orbiting satellite dots.
- **Screen-level feedback** (`scripts/fx/screen_punch.gd`, layer 25, below HUD):
  vignette pulse + two 2-frame scanline offsets + camera zoom punch 1.025.
  Never a full-screen invert or a persistent glitch filter.
- **Particles are Godot's own `CPUParticles2D`** (`scripts/systems/juice.gd`),
  not a hand-written simulator. The only hand-written part is a 6x6 white
  square texture generated at runtime, so the project still ships zero image
  assets. Presets: dust, land_dust, jump_burst, hit_sparks, shatter, pickup,
  block, dodge, telegraph.
- **Animation priority order:** anticipation -> smear -> impact frame ->
  follow-through -> secondary motion. Concretely:
  - windup holds the blade at the coil angle (body squashes to 0.86 width);
  - the blade only travels during the active window;
  - one solid smear wedge (two on the finisher) with a 1px white leading edge;
  - 10-14 degree overshoot held 2 frames, then a 55/30/15 ease-out;
  - the tip lags the body by 1 frame and the body lags the blade by 1 frame.
- **Impact frame:** `Enemy.impact = 0.034s` (2 frames) renders the whole
  silhouette pure white, then a 1px white outline fades over `flash`.
  Never invert the whole screen.
- **Defensive feedback** lives in `scripts/fx/burst_fx.gd` (three modes:
  dodge / block / hurt). i-frame cues only flash on the FIRST and LAST frame of
  the invulnerable window - a continuous glow would hide the timing.
- **Enemy shape language:** sides encode threat tier — triangle (Husk),
  square (Ram), hexagon (Bulwark), pentagon+pentagram (Warden), circle/orbit
  (Watcher). Player alone uses curves (superellipse) because it is the only
  agent with intent.
- **Telegraphs show the real hit shape.** Archer arrows preview the exact
  ballistic path; the Warden's slam ring matches the shockwave radius.
- **Feel first:** movement and combat feedback are tuned before rooms, builds,
  or meta progression. This follows the five-pillar breakdown in
  `docs/design/pillars.md`.
- **Actors are code-built:** `player.tscn` / `enemy.tscn` are root-only;
  collision, hitbox, visual and camera are created in `_ready()`. This keeps
  the prototype free of serialized resource churn. Revisit when real art lands.
- **Content is data-driven:** `data/weapons.json` and `data/enemies.json`.
  Player movement stays as `@export` values in `player.gd` because it is tuned
  in the inspector.
- **Damage has one formula:** `scripts/systems/damage.gd`. Crit condition is
  "target is exposed" (windup/attack/recovery), implemented by
  `Player.is_crit_against` + `Enemy.is_exposed`.
- **Hitstop uses `Engine.time_scale`** at 0.06 for 45–100 ms, restored by
  `Combat` in real time. Loops run in an autoload with
  `PROCESS_MODE_ALWAYS`.
- **Camera:** 1.4× zoom, follow with look-ahead, trauma-based shake. Vignette
  is below the HUD (HUD layer 30) so UI colors stay accurate.
- **HUD text is English** because Godot's fallback font has no CJK glyphs.
  Documentation stays Chinese.
- **HUD sits above bloom** (HUD layer 30, bloom layer 15, vignette 20) so text
  stays crisp while the world glows.
- **Title screen pauses the tree** at `_ready()` and resumes on Enter/Space/J.
  Tests instantiate `main.tscn` with `skip_title = true`.
- **HUD font sizes are tuned for 768x480**: labels 8, values 9-12, headings
  11-14, announce 24, run-summary title 38. Nothing below 8 is used.
- **Boon picker is a real pause**: `get_tree().paused = true`, keyboard 1/2/3
  or arrows+Enter. The encounter resumes only after a choice.
- **Perfect Dodge:** rolling through an attack grants 2.5 s of +25% damage and
  refunds one kunai. It is the skill expression the combat loop is built around.
- **Bulwark front hits chip 1 hp** unless the hit is a crit (exposed or
  backstab). This teaches positioning instead of raw DPS.
- **Boss is not stunned by hits** (`boss` flag skips the HURT state and scales
  knockback to 0.12) so it cannot be stun-locked.
- **Music loop is mathematically seamless:** every oscillator frequency is an
  integer multiple of 1/32 Hz in `tools/make_music.py`.
- **Input actions are registered at runtime** in `game.gd._setup_input()`.
  This avoids serialized `InputEvent` blobs in `project.godot`.
  `shortcut: no in-game rebinding; move actions to project.godot when a settings
  screen or controller remap lands.`
- **Keyboard-only guarantee:** every action has a keyboard binding and the game
  does not bind or require the mouse. Pause/restart/quit are keyboard-only too.
  Do not introduce mouse-only actions. Gamepad support is additive.
- **Enemy spawns are split:** melee/charger use ground points, archers prefer
  platform points. This was changed after wave 1 sometimes spawned entirely on
  platforms.
- **One handmade arena, three authored waves.** Room generation is a later
  pillar, not a launch requirement.
- **Generated audio is reproducible:** `python tools/make_sfx.py`
  (22050 Hz mono 16-bit). Do not hand-edit WAVs.

## Canonical Commands

```powershell
# Run
.\.tools\Godot_v4.7.2-stable_win64.exe --path .

# Verify everything
powershell -ExecutionPolicy Bypass -File tools\check.ps1

# Inner loop: ~77 s, skips the seed sweeps and the end-to-end run
powershell -ExecutionPolicy Bypass -File tools\check.ps1 -Fast

# One step, substring match, no --import
powershell -ExecutionPolicy Bypass -File tools\check.ps1 -Only audit

# Individual checks
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_tests.gd
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path . tests\combat_probe.tscn
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path . tests\soak.tscn

# Screenshots (needs a display)
.\.tools\Godot_v4.7.2-stable_win64_console.exe --path . tests\capture_scene.tscn

# Regenerate SFX
python tools\make_sfx.py
```

## Verification Status (2026-10-24)

`powershell -ExecutionPolicy Bypass -File tools\check.ps1` -> ALL CHECKS
PASSED, exit 0, 17 steps, 424 s:

| Step | Result |
|---|---|
| import / compile | ok |
| `run_tests.gd` | 118 checks |
| `combat_probe.tscn` | ok |
| `reward_probe.tscn` | ok (now also asserts the colour reaches the weapon) |
| `soak.tscn` | ok (arena mode, 4 waves + Warden) |
| `esc_probe.tscn` | 0 failures |
| `floor_probe.tscn` | ok |
| `boss_probe.tscn` | the Warden's slam spawns waves at its feet on 4 floor-5 seeds |
| `climb_probe.tscn` | grunt / charger / bulwark close a 162 px gap to a high deck |
| `run_probe.tscn` | 0 failures, 5 floors -> victory; asserts each floor's boon budget and that a cleared room grants one |
| `audit_a1` combat / weapons | ok |
| `audit_a2` save / economy | 123 checks |
| `audit_a3` floors / spawns | 5 floors x 15 seeds |
| `audit_a4` UI / input | 226 checks |
| `audit_v1` vertical traversal | 5 floors x 40 seeds |
| `audit_v2` enemies / encounters | ok (asserts spitter + leaper spawn from data) |
| `audit_v3` run flow / progression | 163 checks |

Visual harnesses need a display: `capture_scene` (13 shots), `impact_capture`
(20 frame-by-frame), `meta_capture` (14 hub/floor/archive), `title_capture`,
`jump_capture`. Output goes to `output/screenshots/`.

### Timing and how to make it fast

A plain `check.ps1` run is **~350 s** on this machine, and almost none of it is
the assertions: every step is a separate Godot process (~1 s boot each), and
several probes simulate real time on purpose (they walk a player across a
4200-6400 px floor at 300 px/s, or wait out the hub transitions).

Measured, descending: `audit_a3` 118 s, `audit_v1` 36-58 s, `soak` 39 s,
`audit_v3` 39 s, `audit_v2` 21 s, `run_probe` 16 s, `audit_a1` 17 s,
`audit_a4` 11 s, `combat_probe` 8 s, `import` 5-7 s, `floor_probe` 4 s,
`reward_probe` 2 s, `audit_a2` 1 s, `run_tests` 1 s.

Three levers, cheapest first:

| Flag | Wall time | Use it for |
|---|---|---|
| `-Only "<substring>"` | 1-20 s | one step, no `--import`; the inner loop |
| `-Fast` | 77 s | everything except the seed sweeps + end-to-end run |
| (none) | ~350 s | the commit gate |
| `-Turbo` | ~120 s | SMOKE ONLY - see the warning below |

`-Turbo` adds `--fixed-fps 120`, which runs frames as fast as the CPU allows
instead of in real time (soak 39 s -> 13 s). **It can report false failures**:
`audit_v2` failed with "two grunts shared one silhouette" because the crowd
separation needs real frames to resolve. It never produced a false pass in
testing, but a false failure wastes a debugging session, so commit on a plain
run.

Do not "fix" a slow step by shortening its wait loops into fixed frame counts:
`audit_a3` and `run_probe` both used to assume one frame was enough and both
flaked under load. Wait for the *condition*, not for a frame count.

## Fixtures Hide Bugs in the Coordinate They Fix (2026-10-24)

`arena.gd` puts its ground at **y = 0**. `projectile.gd setup_wave()` used to
end with an absolute `position.y = -16.0`, which is correct there and nowhere
else. On a generated floor (slab y 54..150) it put the Warden's shockwaves -
the slam's only damage source - 10..106 px above the player's head, so the
final boss could not hurt anyone. `soak`, the only test that fights the boss,
builds the arena, so it passed for months.

Rule: **any test that builds the arena is blind to floor-relative maths.** If a
value is meant to be an offset, pass it as one and never write it as an
absolute. `tests/boss_probe.tscn` builds a real `Level` for exactly this.

## Known Risks / Limits

- No export templates installed, so no `.exe` has been produced yet.
- Input map is runtime-only; the editor's Input Map panel is empty.
- `godot --script` runs without autoload globals; tests that need the scene
  (probe/soak) must run as scenes, not as `--script`.
- Enemy AI hops up to a player more than 40 px above it (cooldown-gated), but
  it does not path around a wall: `climb_probe` proves a 162 px gap closes,
  not that every gallery is reachable from every spot.
- `Enemy._die` defers `CellPickup` creation because death happens inside a
  physics signal flush. Keep that defer if the death flow is refactored.
- The reward screen is a `CanvasLayer` child of `Main`, not an autoload, so
  `reload_current_scene()` resets it correctly.
- `Projectile.gravity` was renamed to `gravity_accel` to avoid shadowing
  `Node2D` members; keep the name.
- Tests that need autoloads must run as scenes. `--script` runs have no
  autoloads.
- Screenshot and soak harnesses are dev-only; they are not part of the game
  boot path.
- `MathArt.px_*` still exists as an alias layer but now draws SMOOTHLY; it no
  longer snaps. Code that assumes integer positions must use its own rounding.
- The camera warning "Camera2D overridden to physics process mode due to use
  of physics interpolation" is expected; do not silence it by moving the
  camera back to `_process`, that reintroduces jitter.
- The player spawns at x=560 in open ground; the old spawn was under a
  platform and a full jump clipped its head.
- Subagent audits live in `output/agent-reports/` (gitignored). They are
  read-only findings; re-run them rather than trusting stale line numbers.

## Build Wiring (2026-10-24)

- **A run is a sequence of floors, not of waves.** `Encounter` (the arena wave
  director) only exists when `start_mode == "arena"`, which today means the
  test harnesses. Do not add gameplay features to it; they will not run.
- **Boons are paid per cleared room.** `data/floors.json` `"reward"` is the
  floor's budget; `Level.room_cleared(index)` -> `Main._on_room_cleared()`
  decrements `Game.floor_rewards_left` and defers the picker. Paying them at
  the exit gate would be pointless: `Game.finish_floor()` already banked the
  cells and the run is over.
- **`Game.auto_choose_rewards` / `Main.auto_rewards` exist only for headless
  probes.** They grant a random boon instead of raising a picker that would
  pause the tree and hang a test with no keyboard.
- **Two-colour build.** A weapon carries `attribute` (`brutality` /
  `tactics`) in `data/weapons.json`; coloured boons raise `Game.attr`; the
  total is `Game.attr[colour] + Profile.bonus(colour)` and feeds
  `Damage.compute(damage, attr, ...)` via `Hitbox.attr` / `FunctionWave.attr`
  / `Projectile.attr`. A kunai is always tactics. Nothing may hardcode `0`
  for that argument again - that was the bug that made `attribute` a label.
- **Souls are the permanent half of the build.** `data/upgrades.json` rows
  can set `"currency": "souls"`; `Profile.upgrade_currency()` decides the
  wallet and `can_afford_upgrade()` decides the row's dim state. A row must
  never read as a cell price when it spends souls - the price suffix (`C` /
  `S`) is the only cue.
- **`_apply_loadout()` must stay idempotent.** It rebuilds `roll_iframe_end`,
  `crit_bonus`, `armor_taken`, `aegis_cooldown_scale`, `perfect_dodge_scale`
  and `echo_every` from constants; every one of them used to use `+=` and
  would compound on a second call.
- **Monochrome means `r == g == b`.** The ramp is now strictly neutral; the
  old `#08090b`-style values were ~10% blue and were a real violation of the
  rule, not a stylistic choice. `data/rewards.json` is `#c9c9c9`, not
  `#c9d6e2`.

## Drawing Loops Must Be Bounded (2026-10-24)

- **A per-frame draw loop may never be driven by unbounded game state.**
  `Hud._hp_segments()` counted segments from `player.max_hp` and the bar drew
  one rect per segment. `audit_a3` sets `max_hp = 1e9` to survive its walk, so
  the loop ran ~5e7 times and a single frame took **42 seconds** - the audit
  looked like a hang, and a mod or a debug value would have done the same to
  the real game. The count is now `clampi(..., 4, MAX_HP_SEGMENTS)`.
- Before you add a loop to a `_draw()`, ask what its upper bound is and who can
  raise it.
- **Read `Game.player` with `is_instance_valid`, not `!= null`.** Between a
  floor being torn down and the next body existing, `Game.player` is a freed
  reference; every read becomes an engine error, and error spam is the
  slowest thing in a headless run.
- Two diagnostics that made this findable in minutes: a per-step millisecond
  print inside the failing test function, and
  `Time.get_ticks_msec()` around a single `await get_tree().process_frame`.

## Cold-Start Order

`README.md` → `HANDOVER.md` → `AGENTS.md` → `MEMORY.md` →
`docs/agent/current-state.md` → `docs/design/math-art.md` →
`docs/design/impact.md` → `docs/design/combat-feel.md` → target script.
