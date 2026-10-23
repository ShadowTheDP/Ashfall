# Ashfall Memory

## Purpose Snapshot

- `DC-like` / codename **Ashfall** is an original roguelite-metroidvania
  combat-feel prototype.
- It exists to prove the fight loop first; content and meta progression come
  later.
- No Dead Cells code, art, audio, levels, or extracted data. All visuals are
  drawn procedurally; all SFX are synthesized by `tools/make_sfx.py`.

## Stable Decisions

- **Engine:** Godot 4.7.2, GL Compatibility renderer, 1280×720 base,
  `canvas_items` stretch. No .NET, no third-party runtime dependencies.
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

## Verification Status (2026-10-23)

- `run_tests.gd`: 53 data/formula checks pass.
- `combat_probe.tscn`: combo damage 11/13/24 → 42 hp husk dies on the 4th
  swing; cells + kill counted; hurt i-frames and roll i-frames verified.
- `soak.tscn`: archer and charger damage an invincible player; all 3 waves
  clear; victory, 10 kills, no script errors.
- `capture_scene.tscn`: 9 screenshots render correctly on an RTX 4060 with
  OpenGL Compatibility.

## Known Risks / Limits

- No export templates installed, so no `.exe` has been produced yet.
- Input map is runtime-only; the editor's Input Map panel is empty.
- `godot --script` runs without autoload globals; tests that need the scene
  (probe/soak) must run as scenes, not as `--script`.
- Enemy AI does not jump between platforms; archers can walk off a ledge.
- `Enemy._die` defers `CellPickup` creation because death happens inside a
  physics signal flush. Keep that defer if the death flow is refactored.
- Screenshot and soak harnesses are dev-only; they are not part of the game
  boot path.

## Cold-Start Order

`README.md` → `AGENTS.md` → `MEMORY.md` →
`docs/agent/current-state.md` → `docs/design/combat-feel.md` → target script.
