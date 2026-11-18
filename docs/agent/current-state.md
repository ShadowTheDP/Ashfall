# Current State

Updated 2026-11-18. This is the single current status and remaining-work owner.
Product outcomes are in [GOALS](../GOALS.md); visual rules and rationale are in
[ui-system](../design/ui-system.md); governance and read order are in
[AGENTS](../../AGENTS.md); the sole UI execution plan is
[ASHFALL_UI_IMPROVE_PLAN](../../ASHFALL_UI_IMPROVE_PLAN.md).

## Scope

Delivery A targets the lawful nine-visit, three-Boss 0 BSC primary route and the
same-Profile Cistern alternative, with the completed UI maturity work. The
approved full UI improvement plan: steps 1–4 (bilingual text layer, shared input
layer, settings/preferences, combat HUD and pause build summary) are
engineering- and bounded-visual complete, with human review pending; steps 5–8
are not started. 本輪完成第 4 步即停止，未啟動 5–8；日後使用者要求接續時，沿用已核准計畫從第 5 步開始。 Expanded world content, BSC 1–5 gameplay, new
mechanics, rebalance, DLC and online work are not authorized. BSC1 being
unlocked is not BSC1 gameplay.

## Current status

- **UI plan steps 1–3 (2026-11-17): implemented; engineering PASS; human and
  controller review pending.** Step 1 pins Noto Sans CJK TC Regular as the only
  external asset, loads it solely through `MathArt.ui_font()`, uses native
  `TextParagraph` wrapping and ships `data/localization/ui.csv` through Godot's
  native CSV importer (`zh_TW` default, `en` fallback). Step 2 moves all gameplay
  bindings into `project.godot`'s native InputMap and migrates raw-key UI owners
  to the `Interface` autoload; `jump_explicit` keeps a rebound jump usable while
  climbing. Step 3 adds `SettingsScreen` (layer 62), the title's five actions and
  the pause action row, plus separate `user://ashfall_settings.cfg`
  preferences owned by `Profile` (`VERSION=6` and `run_checkpoint` untouched).
  Step-3 evidence: settings 93 checks, `step3-evidence.json` over 170 source
  files, 47 fresh capture frames and native-window probe `S3_NATIVE_OK`; live
  Profile hashes were unchanged. No physical controller, human navigation or
  motion-sequence claim is made.
- **UI plan step 4 (combat HUD and pause build summary, 2026-11-18):
  implemented; engineering and bounded-visual PASS; human/hardware pending.**
  `GearPresentation.describe()` is the single read-only presentation projection:
  exactly `name`／`playstyle`／`condition`／`headline` plus `details`, ten items,
  with no UID, wallet, charge, HP or Profile mutation. The formal combat
  survival cluster uses flask `Rect2(16,362,42,56)`, slot x
  `[66,124,190,248]`, charm `Rect2(314,362,36,56)`, axes baseline y434 and HP
  `Rect2(16,440,334,24)`. The minimap is `Rect2(588,346,164,84)` and the
  wallet/timer is `Rect2(554,432,198,32)` so two 11px lines at the measured
  16px line height fit without shrinking. Pause status／axes／Mutation use the
  same actual 16px pitch at baselines 334／350／366 (axis icons 344, labels
  350); the Mutation descender ends near 370, below the action row at y376.
  Full-page modals hide the combat HUD/announce layer; pause reads the
  presenter directly and its detail tail stays readable. Fresh captures show
  long `PgDn` unclipped with the timer below at 0.6, and short `LT`／`Y` at
  0.1／0.6 inside the cards. In 56px HUD space, the finite standard keycap
  labels `PgUp`／`PgDn`／`Bksp` preserve full 11px key identity without
  clipping or shrinking; other keys keep the OS fallback, and no separate
  formatter framework, binding change, InputMap change or Interface API change
  was introduced.

  Actual evidence: `output/ui-product/step4-evidence.json` covers 171 source
  files at SHA-256
  `fd4e3729bfce46f6b6114775227a3f1320035e95fc749f89adfbcb6218343752`.
  The narrow run exited 0 with settings 93 checks and product 392 checks in
  36.94 s; product capture passed 409 checks in 35.25 s with 64 PNGs (62 native
  768×480 plus 2 text-only 520×96); HUD capture passed 162 checks in 7.16 s
  with 21 PNGs; the measured long `PgUp` label width is 28 px and the timer
  sits below it. The L3 288-check result and `step4_narrow5` evidence were
  reused with the presenter source unchanged; the 6.76 s native import was also
  reused. Final frames are under `output/ui-product/step4/`; `step4-pre-timer-fix/` and
  `step4-pre-keylabel/` are retained failed visual history and do not override
  the accepted result. `data/localization/ui.csv` is unchanged at 798 rows and
  frozen SHA-256
  `e75a0594cfa4fe7f2b2642bb00c46f06c7a44b5e04cb3e18c648e7cfc8675bd7`
  (197 canonical non-UI English rows, 0 duplicate keys, 0 bad columns, 0
  named-placeholder mismatches). This is software evidence only: physical
  controller/disconnect, human comprehension/art, motion frames, full-surface
  HUD/pause/compare/settings resize and Windows export remain pending.
- **Resizable window (2026-11-17): implemented and real-window validated
  (title content only).** `project.godot` sets `window/size/resizable=true`,
  `stretch/aspect=keep` and `scale_mode=fractional`; 1536×960 is only the
  initial size and the logical viewport stays 768×480. Real OS resizes at
  1152×720, 1280×720 with side bars, and maximize/restore passed; project and
  live Profile hashes were unchanged. Evidence:
  [validation](../../output/window-resize-2026-11-17/validation.md). HUD/pause
  scaling and manual feel remain unverified.
- **UI maturity (§§1–9): implemented and focused-engineering verified; human
  art/comprehension still pending.** Shared surfaces, HUD/pause grouping,
  Scroll and comparison, screen-space shop tip, Collector true-unlock card,
  full-width Mutation, title main/saves split, map browse/travel split, 11px hub
  labels and the formal-route one-way cue are in source and covered by the
  step-1–4 evidence above.
- **Project cleanup (2026-11-18):** removed the duplicate Chinese-name
  UI plan, the root handover/changelog compatibility pointers, `docs/history/`
  and obsolete research/session snapshots. The canonical plan now carries a
  dated pre-implementation baseline and defers actual status here. In the same
  freeze, retired five-floor probes and their archive were deleted (not kept as
  a second coverage authority), the unused
  `tests/fixtures/generation_legacy_transition_v1.json` was removed with bytes
  preserved under `output/`, and retired-path references were corrected in
  README, AGENTS, PRODUCT, save design and this file. No runtime, gameplay,
  save-policy or output evidence was changed. Environment checks on the frozen
  tree passed: Python runner 20 tests, profile-path 36 tests with live
  profiles/settings unchanged, Pi director probes 86/6/45, Godot `--fast` exit 0
  with all 13 groups passed in 160.40 s (4 seeds), and focused settings 93 /
  product 392 exit 0 in 40.71 s. An aggregate of 302 files (project.godot plus
  scripts/shaders/data/scenes/tests) kept SHA-256
  `3098c4d7b60e2238a1ef61c79ff0bff71a45eebb32ed3c57dedefdf3c22e2f59`
  unchanged before/after, and live profiles/preferences were unchanged. Main's
  final local link scan covered 26 documents / 120 links with 0 broken.
  Detailed logs and manifests:
  [RESULT.md](../../output/project-cleanup-2026-11-18/RESULT.md). Human/hardware
  and known-warning limitations below are unchanged.
- **Check policy:** the default runner is 13 latest-only checks; extras are
  `--only` opt-ins, and retired-path probes are deleted rather than archived.
  `--fast` uses four seeds, not 32. Per-step limits are owned by
  `python tools/check.py --list`.

## Remaining work

1. **UI plan steps 5–8 (not started):** 本輪完成第 4 步即停止，未啟動 5–8；日後使用者要求接續時，沿用已核准計畫從第 5 步開始。 Step 5 begins with the
   build comparison/shop work: retire `BuildScreen.item_details` and
   `_gear_lines`, and migrate the legacy L3 assertions to the presenter
   semantics. Steps 5–8 must not be described as implemented now. Steps 1–4 are
   engineering- and bounded-visual complete, with human/hardware review still
   pending.
2. **真人雙路線驗收:** one lawful nine-visit primary victory followed by the
   lawful same-Profile Cistern victory, with short readability, difficulty and
   rhythm feedback. Use [delivery-a-human-check](delivery-a-human-check.md);
   automated play and screenshots cannot sign it.
3. **Human UI review:** unprompted comprehension of skill readiness, replacement
   and wallet, Scroll effects, run-scoped versus permanent Passage results,
   modal cancellation and the save boundary. Aesthetic satisfaction is separate.
4. **Generated-content dual-route evidence:** complete ordinary-input evidence
   for the current generation revision; do not treat an earlier slice as proof.
5. **Known limits:** Camera2D / audio shutdown / GLES3 MSAA / MbedTLS warnings
   remain; physical controller including disconnect, human art/comprehension,
   motion-frame evidence, full-surface HUD/pause/compare/settings resize and
   Windows export are unverified. The retired five-floor `terrain_regression_probe`
   seam gap was not replaced; `LevelGen` remains a legacy fallback. The exact
   runtime proof is software only and makes no hardware claim.

## Evidence

- Step 4 final manifest and accepted frames:
  [step4-evidence.json](../../output/ui-product/step4-evidence.json) and
  `output/ui-product/step4/`; `step4-pre-timer-fix/` and
  `step4-pre-keylabel/` remain explicit failed visual history.
- Step 3 manifest and captures: `output/ui-product/step3-evidence.json`,
  `output/ui-product/settings-window/manifest.json`.
- Step 1–2 product captures and headless probe evidence: `output/ui-product/`
  (mutable review output; the dated runs above are the record).
- Historical UI-maturity review index (user view, not status authority):
  [review-index.html](../../output/ui-maturity-2026-11-16/review-index.html).
- Window validation: [validation.md](../../output/window-resize-2026-11-17/validation.md).

## Invariants

`Profile` is the sole persistent save writer; `RunBuild` owns run gear/UIDs,
charges, axes and wallet. Biome entries resume at the entrance; Passage resumes
committed service/build/claim state. All art uses `MathArt`; the player keeps
its dark inset and one bright core. Keyboard access is mandatory. Tests use
isolated Profiles and preserve the inherited dirty tree and live saves.
