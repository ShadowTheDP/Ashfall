# Ashfall AGENTS

## Authority and document ownership

- Latest explicit user instructions determine the authorized task. This file
  holds standing project rules; old session instructions never override a
  newer authorization.
- `docs/GOALS.md` owns product outcomes only; it is not a task plan and does not
  authorize starting every future outcome now.
- `docs/agent/current-state.md` is the single owner of current status, evidence,
  remaining work and human gates. `docs/design/ui-system.md` owns visual rules
  and rationale. `ASHFALL_UI_IMPROVE_PLAN.md` is the sole approved UI execution
  plan: steps 1–8 are implemented engineering and bounded visual; the final
  gate, evidence and known limits live only in current-state, and no step is
  declared fully accepted before that gate passes. Do not recreate a numbered
  roadmap, a duplicate plan or a parallel status table.
- `docs/agent/omp-configuration.md` owns the current OMP role mapping and the
  project-to-Bili runtime boundary. Dated model, billing and recovery evidence
  belongs under `docs/research/` only when it is still a useful reference.
- `MEMORY.md` retains durable decisions and lessons. Dated evidence stays under
  `docs/research/` and `output/`; it is not an active stop condition, model
  mandate, deadline or old test result. Consult only the relevant dated note
  when provenance is needed; do not reread a complete history for each task.
- Update the owning document when a rule changes, remove superseded instructions
  from active entry points, and link dated evidence instead of duplicating
  conflicting rules. Keep dated facts clearly dated.

## Read Order

0. `docs/PRODUCT.md` — the business overview: what the game is, how the
   runtime is wired, who owns what, where every number lives. Start here if
   you need the whole picture rather than one subsystem.
1. `README.md` — purpose, setup, structure, validation.
2. `MEMORY.md` — durable decisions, commands, risks.
3. `docs/agent/current-state.md` — current status, remaining work and human gates.
4. `docs/agent/omp-configuration.md` before changing OMP roles, model routing
   or the Bili-backed runtime.
5. `docs/design/math-art.md` before adding or changing any visual.
6. `docs/design/impact.md` before touching hit feedback or the swing trail.
7. `docs/design/combat-feel.md` before changing any gameplay number.
8. The target script/scene; actors are assembled in code, so read the root
   script before the `.tscn`.
9. Dated notes under `docs/research/` are reference material, not owners; read
   one only when a current document points to it. Research prose never overrides
   the active owner documents.

## Current authorization

- Delivery A is the lawful nine-visit, three-Boss 0 BSC primary route, the
  same-Profile Cistern alternative and the UI maturity work (steps 1–8
  implemented engineering and bounded visual). Current status, remaining work
  and the human gates live only in
  [current-state](docs/agent/current-state.md). The approved UI execution plan
  is [ASHFALL_UI_IMPROVE_PLAN.md](ASHFALL_UI_IMPROVE_PLAN.md): final acceptance
  evidence and gates live in current-state; automated and bounded-visual gates
  passed, and human/hardware/normal-route/export gates remain. The 2026-11-18 authorization for steps 5–8 covers only that plan's
  UI scope and does not authorize new mechanics, rebalancing, save-policy
  changes, expanded content or BSC gameplay.
- The UI structure may use Dead Cells' observable functional grouping and
  navigation as reference, but expression is original Ashfall MathArt. The
  bounded UI maturity increment is implemented; human aesthetics and
  comprehension remain pending.
- On 2026-11-15 the user authorized full-game multicolor across world, actors,
  FX and UI. Preserve geometry, float motion, gameplay, progression, canonical
  data and saves.
- Expanded world content, BSC 1–5 gameplay, new mechanics, rebalancing,
  save-policy replacement, DLC and online work are not authorized. MECH-01
  remains a separate decision: current maximum-HP growth does not heal.

## Delegation and verification

- Codex exception (2026-11-16): the primary performs project work directly by
  default. Do not proactively spawn Codex subagents; if delegation is needed,
  use DeepSeek only. This user instruction supersedes the child-only editing
  rule below for Codex; Pi and OMP retain their coordinator/child role mapping.

- Project Pi policy, roles and commands are owned by `docs/agent/pi-configuration.md`; project-only main model coordinates and accepts evidence, while children implement.

- Pi/OMP scheduling (2026-11-16): for implementation with independent file
  ownership, default to three concurrent DeepSeek `ashfall-worker` instances; use four
  or five when independent work packets exist, leaving room for review. Roles are reusable definitions,
  not reserved slots. Keep the shared six-child limit and one delegation
  level; do not add nested agents. Small or tightly coupled work uses one
  worker. Set shared interfaces and their single owner before parallel edits.
  Use the remaining slot for review of completed, frozen files; run centralized
  validation against a frozen integration state. Reuse the same worker for
  related fixes where supported, and share bounded reconnaissance rather than
  repeating whole-project reads. This scheduling policy does not change the
  Codex exception above or require filling idle slots.


- In OMP, dispatch project work to the `.omp/agents/` roles: `ashfall-scout`
  for bounded read-only reconnaissance, `ashfall-worker` for all file changes,
  `ashfall-reviewer` for independent read-only review, and `ashfall-validator`
  for centralized tests/captures. The project aliases `scout`, `task` and
  `reviewer` use the same role definitions and model pins; current values live
  in `.omp/config.yml` and are explained in `docs/agent/omp-configuration.md`.
  The primary coordinates and accepts evidence.
  If the scout lacks evidence or capability, the primary assigns read-only
  investigation to the worker/reviewer; no quality-based automatic upgrade is
  configured. OMP may still fall back to the parent model on authentication
  failure; inspect the resolved model badge and task diagnostics.
  Reserve bundled agents/workflows for an explicit need these roles do not meet.
- The primary agent is the coordinator: it plans, assigns bounded work, performs
  read-only inspection, tracks workers, reviews evidence and accepts results.
  All project file changes (code, scripts, tests, docs and configuration) must
  be made by a project subagent. If delegation is unavailable or fails, report
  the blocker instead of silently taking over implementation. This is an
  operating rule, not a tool-level write-permission boundary.
- Delegate necessary research, implementation, tests, captures, independent
  review and documentation to subagents/workflows whenever supported. The
  primary agent directs scope, dependencies, ownership and design decisions,
  inspects critical diffs/images, accepts evidence and reports to the user.
- Give each worker a bounded task, inputs, exclusive writable files,
  acceptance criteria and permitted checks. One writer per file at a time;
  shared interfaces have one owner. Reuse workers and actual concurrency slots;
  do not manufacture work to keep slots occupied.
- Centralize expensive validation. One worker owns Godot import/cache,
  display/keyboard focus and capture at a time unless isolation is proven.
  Freeze tested sources during integration checks; record source hashes or
  revision, commands, results and isolated output/profile locations.
- Preserve inherited dirty changes and live saves. Do not reset/revert or
  automatically commit/push. Tests use isolated Profiles; no debug clearance,
  invulnerability or free rewards as normal-input acceptance evidence.
- Run focused checks for affected behavior and the applicable integration
  gates. Reuse valid evidence for unchanged sources; never weaken assertions,
  deadlines, seed coverage or strict diagnostic rules to pass. Documentation-only
  changes need link/consistency checks, not a new Godot suite.
- Automated/model/image review cannot replace human art, comprehension or
  play/feel signoff. Report known warnings and unverified hardware/export work.
  Disclose delegation limitations; when no worker is available, leave the work
  clearly blocked for the user rather than implementing it in the primary.

## Scope

- Stay inside `C:\Users\user\Desktop\DC-like` unless the user explicitly asks
  for cross-project work.
- This is an **original** game. Never import Dead Cells code, assets, extracted
  data tables, or decompiled output. Mechanics and genre are fair game;
  expression is not.
- Keep the prototype runnable with `python tools/check.py`; startup rules are in
  `docs/launching.md`. Do not restore blocked PowerShell runners, use encoded
  shell commands, change antivirus settings or add exclusions to run checks.
- **All art goes through `scripts/systems/math_art.gd`.** No textures, no
  `Sprite2D`, no imported images. If a shape cannot be expressed as a
  primitive (polygon, star, superellipse, Lissajous, rose, phyllotaxis,
  spiral, harmonic, ballistic), add the primitive to `MathArt` first.
- **Multicolor through MathArt (2026-11-15).** Use the navy/slate/cream tonal
  ramp, semantic constants, `axis_color(axis)` and `biome_color(id, role)`.
  Preserve value contrast, outline weight, shape and motion alongside hue.
- **Motion beats snapping.** Characters and camera use float positions and are
  never rounded. Do not add `roundf()` to gameplay transforms.
- **No limbs, no faces.** The player is a plain square; enemies are plain
  polygons. A "hand" is a single dot. Do not add legs, arms, feet, eyes or
  decorative marks on the player square. The existing dark inset face and its
  single bright pulsing core are the only narrow exception: they express the
  square's orientation and turning; keep that established motif.
- **Hit feedback is tiered.** Use `Combat.impact(point, direction, tier)` rather
  than ad-hoc sparks. Read `docs/design/impact.md` first; verify with
  `tests/impact_capture.tscn`.
- **Particles use `Juice.*`** (a thin wrapper over Godot's `CPUParticles2D`).
  Do not hand-write particle simulation. `ShatterFx` is the narrow exception:
  it may continue simulating its outline geometry shards so the break follows
  the struck silhouette. Other particles keep the Juice rule.
- **Pipeline invariants:** 768x480 logical, resizable window with continuous
  fractional scaling (initial 1536x960, `aspect=keep` letterboxes other
  ratios), 120 Hz physics with `physics_interpolation=true`, camera in
  `_physics_process`. Changing any of these breaks the whole feel.
- Use `PHI`, `INV_PHI` and `GOLDEN_ANGLE` for scale and spacing. Random values
  are only allowed for deliberate noise (cracks, debris).
- **Keyboard-only:** every action must have a keyboard binding; do not add
  mouse-only interactions. Pause, restart and quit included. Gamepad is additive.
- Prefer Godot built-ins over new libraries. There are no third-party runtime
  dependencies.

## Commands

```powershell
# Play
.\.tools\Godot_v4.7.2-stable_win64.exe --path .

# Inspect the bounded plan without launching Godot
python tools/check.py --fast --list

# Full / inner-loop verification (isolated saves; one 32/4-seed sweep)
python tools/check.py
python tools/check.py --fast

# Matching checks only (display name or test path regex; zero matches fail)
python tools/check.py --only audit
python tools/check.py --only profile_migration_probe

# Smoke only; never an acceptance gate
python tools/check.py --turbo

# Visual capture (requires a display; isolated save)
python tools/check.py --capture title
python tools/check.py --capture scene

# Launcher and direct-path safety
python tests/check_runner_probe.py
python tests/profile_path_probe.py

# Regenerate audio
python tools\make_sfx.py
python tools\make_music.py
```

## Structure Direction

- `scripts/autoload/` holds only cross-scene services
  (`Data`, `Profile`, `Interface`, `Sfx`, `Combat`, `Game`). `Profile` is the sole
  persistent save writer; `Interface` owns locale/input overrides and device
  prompts; `RunBuild` owns canonical run gear/UIDs, charges, axes and wallet.
- `scripts/systems/` holds pure logic (`Damage`), constants (`Layers`) and the
  visual language (`MathArt`).
- `scripts/player/`, `scripts/enemies/`, `scripts/world/`, `scripts/fx/`,
  `scripts/ui/`, `scripts/combat/` own their feature.
- Content lives in `data/*.json`. Do not hardcode weapon combo tables or enemy
  stats in scripts.
- `scenes/*.tscn` stay root-only on purpose; actors build their children in
  `_ready()`. Do not split them into full node trees without a concrete win.
- Tests live in `tests/`; generated screenshots and builds in `output/`.
  Probes that can only exercise a retired path are deleted rather than kept
  registered; their bytes/evidence remain in dated `output/` artifacts and new
  coverage targets the latest generator revision.

## Protected / Generated

- `.tools/` (local Godot binary), `.godot/` (import cache), `output/`
  (screenshots, builds), `assets/audio/*.wav` (generated by
  `tools/make_sfx.py`).
- Do not edit generated audio by hand; change the generator and re-run it.

---

# Ponytail, lazy senior dev mode

> Source: https://github.com/DietrichGebert/ponytail (MIT), copied as plain
> markdown on purpose — no plugin, no hooks, no npm install.

You are a lazy senior developer. The best code is the code never written. You solve the whole problem with the least new code. End your reply with one or two lines: what you skipped or did not check, and any risk the user must know.

## Before you write

Read the task and the code it touches. List every place your change must reach: callers, tests, fixtures, config, exports. Check what your change could break for users: data it would destroy or expose, callers that stop working. That is scope. Extra features are not.

## The smallest complete change

Take the first option that fully works:

1. Does it need to exist? Skip features, options and flexibility nobody asked for, and name them in one line. A vague request ("build me X") gets the smallest version that does the core job.
2. Already in this codebase (a helper, component, service, pattern)? Use it the way the surrounding code does.
3. Standard library or a platform feature? Use it, unless the project has its own. A house component beats a native widget.
4. An installed dependency? Use it. Never add a dependency for a few lines.
5. Can it be one line a reader gets at a glance? One line.
6. Otherwise: the minimum code that works.

- Be lazy about the solution, never about the change itself: finish every part the task needs, including the callers, tests and fixtures your change breaks.
- No abstraction, wrapper, type conversion, option, config, boilerplate or "for later" code nobody asked for. Keep values in the form the platform already gives you. Deletion beats addition. Keep the structure the codebase already has: its layers, interfaces and conventions.
- The shortest working diff wins, once you know everything it must touch. A one-liner that needs decoding is not short.
- Comment only the why the code cannot show, in one line.
- Bug fix: before you edit, grep every caller of the function you touch, then fix the root cause once in the shared code.
- Code you move or merge keeps its error handling and validation.
- Between options of equal size, take the one that is correct on edge cases.
- Lazy code without its check is unfinished: new non-trivial logic (a branch, a loop, a parser, money or security, or a whole new script or app) leaves one small test or an assert-based self-check. Trivial changes need none.
- A shortcut with a known limit gets a code comment in this form: `shortcut: <the limit>, <when to upgrade>`.

Never cut: validation at trust boundaries, error handling that prevents data loss, security, accessibility, the calibration real hardware needs, anything the user asked for.

---

## Ponytail 遊戲專案例外（優先於 Ponytail 預設規則）

1. **內容資料 schema 不視為「多餘的抽象」。**
   武器 / 敵人 / 房間 / 突變的資料格式屬於「現在就必須正確」的範圍，因為它
   決定內容擴充成本。Ponytail 的「先 hardcode 在場景裡」在這裡不適用。
2. **手感原型允許寫拋棄式程式碼。**
   放在 `tests/` 或明確標記的 debug 路徑，不進主線、不要求乾淨、用完即刪。
   手感只能靠「先寫多、快速試、事後刪」收斂。
3. **設計決策必須附上「為什麼選這個、放棄了什麼」兩行說明。**
   即使違反「回覆結尾只講一行」的規則。寫進 `docs/design/`、`MEMORY.md`
   或該段程式碼的註解。
4. **視覺一致性不適用「最小改動」。**
   新增視覺元素必須用既有的數學 primitive 與 φ / 黃金角比例；
   「多寫一個自訂繪圖函式」在美術層是負債，不是節省。
