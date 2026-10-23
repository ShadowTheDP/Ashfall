# Ashfall Agent Start Here

This is a standalone Godot 4 combat prototype, not part of the `Code-Project`
workspace. The project-level docs follow that workspace's conventions so a cold
agent can continue from files alone.

## Entry Order

1. `README.md` — what the game is, how to run it, file roles, known limits.
2. `AGENTS.md` — scope, commands, Ponytail rules and the three game exceptions.
3. `MEMORY.md` — durable decisions, canonical commands, verification status.
4. `docs/agent/current-state.md` — the current objective and next steps.
5. `docs/design/combat-feel.md` before changing gameplay numbers.
6. `docs/design/pillars.md` before adding a new system.
7. The target script. Actors are assembled in code, so read the root script
   before the `.tscn`.

## Boundaries

- Original work only. No Dead Cells code, art, audio, level data, or extracted
  tables. Genre and mechanics are fine; expression is not.
- Work inside this project. Do not modify `C:\Users\user\Desktop\Code-Project`
  unless the user explicitly asks.
- Do not hand-edit `.godot/`, `.tools/`, `output/`, or generated WAVs.
- Keep the prototype runnable headless at every meaningful commit.

## Quick Verification

```powershell
powershell -ExecutionPolicy Bypass -File tools\check.ps1
```

If a change touches feel, also run the capture scene and inspect
`output/screenshots/`:

```powershell
.\.tools\Godot_v4.7.2-stable_win64_console.exe --path . tests\capture_scene.tscn
```
