# Ashfall Memory

Only durable project preferences and reusable lessons live here. Current status, tests and gates are not copied; use the owner documents below.

## Owners

- Standing rules, authorization, hard invariants, read order: [AGENTS.md](AGENTS.md).
- Product definition, architecture, data/number ownership: [PRODUCT.md](docs/PRODUCT.md).
- Current status, evidence, remaining work and human gates: [current-state](docs/agent/current-state.md).
- UI visual rules and page rationale: [ui-system](docs/design/ui-system.md).
- Pi/OMP roles, model pins and Bili boundary: [Pi configuration](docs/agent/pi-configuration.md), [OMP configuration](docs/agent/omp-configuration.md).
- Commands, launching and validation: [README.md](README.md), [launching.md](docs/launching.md).
- Historical provenance: dated reference material under [research](docs/research/); historical success is not this turn's test. Obsolete snapshots, plans and session logs are not retained as parallel authorities.

## User preferences

- Project Pi director uses an explicit blacklist, not an allowlist: preserve plugin activation and permit unfamiliar tools by default. Keep direct implementation and alternate delegation entries blocked; native Plan retains its own opt-in policy with web and official Bili tools enabled.

- Project Pi Plan mode allows web search, source checks and page retrieval by default through project-local Plan settings; keep editing, shell and implementation delegation blocked during planning. Do not apply this preference globally.
- Pi/OMP independent implementation defaults to three DeepSeek `ashfall-worker` instances; four or five when work truly separates, one for small/coupled work. Six shared child slots, one writer per file, one delegation level.
- Set project Pi/OMP DeepSeek worker thinking to `max` (OMP includes the `task` alias); keep other OMP roles and policies as configured. Only newly started workers pick this up; resumed runs can replay their recorded level.
- Codex implements directly by default; if delegation is needed, use DeepSeek only. Pi/OMP keep the coordinating parent and implementing children.
- Explain tradeoffs as quality, waiting time and spending. Do not add unauthorized features, rebalance or save-policy changes. Preserve inherited dirty changes and live saves; do not reset, revert, commit or push without an explicit request.
- Do not retry a failed context compression unchanged. A smaller range or a larger summary budget is a new configuration, not a retry.
- Adjust OMP configuration through its desktop UI where supported; do not infer live Bili budgets from disk.

## Durable implementation lessons

- **Presentation-only result state:** `Game.run_abandoned` is set only after a successful abandon settlement and reset on a new run so result copy says abandon rather than death. Presentation flags like this stay out of serialization, `VERSION`, save policy and content data; no second outcome owner.
- **Display-only resume diagnostics:** `Profile.slot_summary()` may expose canonical-validation results such as `resume_error` for save cards; they change only enablement and reason text, never `blocked`, `select_slot` or the save payload.
- **Adaptive wrap fallback:** `MathArt.ui_wrap` keeps its native adaptive first pass; only measured over-wide lines rebuild a fresh `TextParagraph` at the same size and width with `MANDATORY | GRAPHEME_BOUND`, preserving normal word/CJK/locale behavior and the 256-entry cache. The engine does not reset `word_count` after a hard break, so a long token appearing after a newline can still overflow — never add a homemade parser or manual ASCII splitting. Retry 7 proved the Archive 280-token post-newline reason reads fully and scrolls to terminal, but product still fails at the next Skill fixture, so there is no full-pass claim.
- **Localized name snapshots:** never cache a translated display name and feed it through another translation lookup; derive the canonical `Data.name` per draw and give each screen its own fresh localization context. The EN map header leaked ZH until the cached snapshot was removed.
- **RunLoot retirement:** an unclaimed world instance retires from its captured `owner_build` in `_exit_tree`, never through `Game.build`; a new run restarts UIDs at 1. Do not retire equipped or consumed gear. `BuildScreen.close()` must null its offer before terrain frees the node.
- **Input/modal lock:** opening a panel consumes the triggering input and pauses combat. Allow the idle action-lock registration before asserting the next event. `Main` is pausable; an `ALWAYS` test/UI parent must not keep simulating the world while a map or panel is paused.
- **Passage validation:** `valid_passage()` must validate every member `RunBuild` reads directly, including `mutation_reset.cost/step/capacity` and `craft.upgrade_cost/reforge_cost/reforge_step`; presence-only checks can pass a document that later raises invalid access. Legal zero-valued challenge fields are allowed.
- **Geometry offsets:** generated floors are floor-relative; never turn an offset into an absolute coordinate. Close narrow same-height seams by extending one-way decks after macro assembly and before spawn/cache/reach, preserving solid footprints.
- **Collision-only fixtures:** a `Level` fixture that bypasses `build()` must hide the node before entering the tree; multicolor drawing requires the palette initialized by `build()`.
- **GDScript narrowing:** `if not event is InputEventKey: return` does not narrow a parameter declared `event: InputEvent`. Use `var key: int = (event as InputEventKey).physical_keycode`. Per-file `--check-only --script` sweeps report false autoload errors; do not use them as a clean compile gate.
- **Fixture honesty:** when a bounded UI probe needs run state a fresh run has not earned, seed it in an explicitly labelled fixture, restore fields the skipped path writes (for example `Game.passage_snapshot`), and still drive real keyboard events. Label it fixture evidence, never normal-run acceptance.
- **Projectile field:** `projectile.gd` uses `gravity_accel`, not `gravity`, because the latter shadows `Node2D`. Keep `monitorable = true` while body detection is required.
- **Map discovery:** an unlocked edge does not discover its target. Unknown rooms, services and checkpoints must stay hidden.
- **Test isolation:** never write the live Profile from tests; use the runner's isolated Profile and verify slot hashes/absence after native checks that could write. Details are owned by AGENTS and the save design contract.
- **Timeouts:** cold class registration and standalone fixture startup are real boundaries. Keep import-first sequencing and existing gates; inspect the stop point, seed and source instead of raising a deadline to hide a hang.
- **Diagnostics:** ordinary `ERROR:`, script/scene failures, nonzero exits and timeouts cannot be accepted as green. Known WAV shutdown references and Camera2D interpolation warnings remain visible; no zero-warning claim is established.

## Orchestration notes

- Bili has a shared backend config and a separate client manifest cache. Reloading the backend does not refresh `maxToolDurationMs` already registered by Pi/OMP; reload the extension or reopen/resume the client. A timed-out batch may still create blocks, so inspect status/logs and retry only failed ranges in smaller batches.
- Bili summary recipes have their own context/output budgets. An empty DeepSeek recipe can fall back to 128K/8K even when the model advertises 1M, so the shared recipe must explicitly set 1,048,576 context, 32,768 output and streaming. Budgets are capped at a 600,000 ms total, and target cannot exceed total. Compression credit is folded context, not realized billing savings.
- Shared `promptCache.routing` is `auto` for relay cache affinity. A config PUT can refresh `opts.promptCache` while a bare reload does not; configuration acceptance does not prove an upstream cache hit. Measure cached/input usage separately.
- Do not infer live Bili state from disk alone: package presence, a closed port or routed requests do not prove compression. Check applied blocks and distinguish compression credit from savings. Current role/model/budget contracts are owned by [Pi configuration](docs/agent/pi-configuration.md) and [OMP configuration](docs/agent/omp-configuration.md).
- Native workflow and direct role dispatch share the six-slot scheduler; do not build another scheduler. A native resume returns a new runId: track it and keep the parent alive until terminal. Preflight reload updates new children only; an already-running child keeps its loaded role. Formal Bili state, version and effective budget must come from the live runtime.
- Automated completion notifications are result events, not new user requests. Read the result, reconcile it with the current objective and account for failed runs before wrapping up.
- 2026-11-18 docs cleanup keeps one UI execution plan and one status owner. Removed duplicate plans, root compatibility pointers, history snapshots and obsolete research/session logs instead of preserving a second archive authority. Dated acceptance evidence stays in `output/`; rationale for cleanup lives in current-state, not in a new log.

## Evidence routes

- Current status and accepted evidence: [current-state](docs/agent/current-state.md); step-4 manifest `output/ui-product/step4-evidence.json`.
- Final UI implementation and focused validation: `output/ui-product/`.
- Dated audits, color and configuration research that remains useful: `docs/research/` and the paths linked from current-state.
- UI visual review index: `output/ui-maturity-2026-11-16/review-index.html`; it is a user view, not status authority.
