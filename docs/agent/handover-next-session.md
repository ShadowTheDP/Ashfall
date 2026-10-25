# Handover — quality pass, not yet started

Written at the end of a session that could not load the newly installed
extensions. **No code was changed in this session.** The tree is clean at
`f2fbda7`.

## Where things stand

- Last commit: `f2fbda7` "Boss that could not hit you, finisher waves through
  walls, dead climb code, and a readable far plane". Working tree clean.
- `tools/check.ps1` was green on that commit: **ALL CHECKS PASSED, 17 steps,
  424 s, exit 0**.
- Read `HANDOVER.md` §3 before fixing anything — every bug already found is
  tabulated there with its cause. Do not re-report those.
- The game may still be running as `Ashfall (DC-like) (DEBUG)`, PID 13980.
  Kill it before running the capture harnesses (they need the display and the
  window steals frames).

## What this session established (verified, do not re-derive)

1. **The extensions are installed correctly and do load** — a session started
   at 14:18 today has `web_search`, `source_check`, `fetch_content`,
   `get_search_content` in its own system prompt. The packages were installed
   2026-10-25 13:45/13:48; the long-running session began 2026-10-24 06:47
   UTC, so it never picked them up. Extensions load at session start only.
2. **`pi-btw` registers a slash command, not a tool** — its absence from the
   tool list is expected.
3. **`pi-dynamic-workflow`'s `workflow` tool is registered lazily on first
   `/workflow` use** (`src/index.ts` header comment), so it is also absent by
   design until then. It overlaps `pi-subagents`' own scripted workflow; pick
   one, do not run both.
4. **Background subagents DO get the web tools; foreground ones do not.**
   A `researcher` launched with `async: true` used `web_search` (Exa)
   successfully. The same agent with `async: false` failed with "child tools
   were unavailable: web_search, fetch_content, ...". Use `async: true` for
   any research child, and `bg_wait` / the completion notice to collect it.
5. `curl` works from bash (`api.github.com`, `duckduckgo.com` both 200), so
   network research is possible without the extension — but do not call it
   `web_search`.

## The task that was requested and not started

Owner asked for a full quality pass: find unreported bugs, then raise the
whole player-facing experience. Priorities in their words, in order:

1. Flow defects first: soft-lock, skipped floors, lost progress, save
   anomalies, unreachable map, unclear controls, combat that does not work.
2. Map generation: big enough, coherent route, vertical layer worth exploring.
3. Combat feedback with clear tiers for hit / heavy / crit / kill / hurt /
   block / dodge / boss moves — impactful without covering information.
4. Hub composition, scene depth, motion, particle ambience.
5. Controls / HUD / rewards / progress / transitions / summary clarity and
   consistency.

Constraints: monochrome, `MathArt` only, procedural, keyboard-only, 768x480,
120 Hz + interpolation, float movement, particles via `Juice.*`, impact via
`Combat.impact()`. Reuse existing systems. No external assets. Test with real
runs and seeds; look at actual screenshots. Do not wait for per-item approval.

## Leads this session found but did NOT verify

These are unconfirmed. Verify before acting; none has been reproduced.

- `Hud._draw_run_over()` prints `Game.cells` (whole-run total) while only
  `run_cells` is forfeited on death, so the death summary may disagree with
  what actually banked.
- `Game.reset_run()` sets `run_over = false`, and `Main.restart_attempt()`
  calls it. Check whether pressing R on the death screen revives a finished
  run into a playable-but-unbanked state instead of replaying the floor.
- `Hud._unhandled_input()` calls `get_tree().quit()` on `Q` with no save call.
  `bank()`/`spend()` save individually, so the exposure may be nil — confirm.
- `Main._process()` only enters the hub when `start_mode == "hub"`, so a
  non-hub transition may never resolve.

## Suggested first moves

```
# 1. confirm the baseline is still green before touching anything
powershell -ExecutionPolicy Bypass -File tools\check.ps1 -Fast      # ~77 s

# 2. read the already-fixed list so nothing is re-reported
#    HANDOVER.md §3, §5 (hard rules), §6 (fragile spots)

# 3. then work in batches: fix -> targeted -Only <step> -> full check at the end
```

Keep `-Turbo` out of any commit decision (it produces false failures in
`audit_v2`). Do not edit the tree while a plain `check.ps1` is running.

## Files a future session will need

- `AGENTS.md` — read order and hard rules (read it first).
- `HANDOVER.md` — session log; §3 is the bug table, §6 the fragile spots.
- `MEMORY.md` — durable decisions, plus the "fixtures hide bugs in the
  coordinate they fix" note (the boss slam bug).
- `docs/agent/current-state.md` — what was last worked on.
- `docs/design/math-art.md`, `impact.md`, `combat-feel.md` — before touching
  visuals or any gameplay number.
