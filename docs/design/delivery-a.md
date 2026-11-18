# Delivery A — implementation contract

Status: route, Passage and UI engineering are implemented. Current evidence is in [current-state](../agent/current-state.md); this contract is not test evidence. Human UI art/comprehension and 真人雙路線驗收 remain required, so Delivery A is not complete.

## Additive persistence / transaction packet

- Workload: local single-player document aggregate, incremental Profile v4→v5; no database, network, telemetry or new dependency.
- Profile remains the only persistent writer. Add delivered blueprint IDs, per-blueprint Cells investment, unlocked Mutation IDs and Forge Cells progress. Preserve original v4 bytes before first write, existing legacy snapshot, unknown fields/IDs and all existing currencies. No speculative conversion of Souls or stat power.
- Game owns carried blueprints/Cells, node counters, Passage claims and run lifecycle. RunBuild owns gold, gear instances, Scrolls, chosen Mutations and capacity. These never become permanent loadout. The later human-feedback [save-slot contract](save-slots.md) adds Profile v6 with three independent biome-entry/Passage checkpoints; ordinary in-biome combat is not a frame-by-frame save. Death/abandon/victory clears the checkpoint in the same permanent commit; interrupted Profile writes retain existing recovery.
- Blueprint pickup is run-owned until explicit Collector delivery. Delivery and investment save first, roll back on failure, then remove the carried blueprint or debit carried Cells synchronously. No await between commit and debit. Completion unlocks the real future loot/start pool; buying an already completed entry does nothing. Leftover carried Cells remain available for the Boss Forge.
- Forge is a separate permanent, capped Cells investment after a Boss. Its probability affects only subsequent actual loot creation; starting items and already-created offers are unchanged.
- Every transaction validates phase, live Player/build, IDs, ownership, capacity, positive amounts and funds. Partial amounts clamp to remaining progress, never overcharge. A failed save must not appear as a successful grant.
- v5 adds fields with safe defaults; no cleanup/removal of archived legacy data. Higher-version/read failure continues to block writes. Tests cover v4 backup, repeat reload, malformed/unknown values, save failures and interrupted temp recovery.

選擇保留單一 Profile 原子文件，因為所有永久交易在同一同步主執行緒完成，且原本已有 temp→rename 保護。
放棄新增資料庫與任意幀世界序列化；後續真人回饋已另行授權三槽與安全邊界恢復，範圍見save-slots契約。

## Passage and build

- One walkable Passage owns Collector, Mutation selection/reset, gear upgrade/reforge, Fountain, challenge rewards and continue. The selected destination remains Game-owned; no service chooses routes.
- Capacity rises to min(3, completed visits); initially one slot at the first Passage. Three free distinct effects: added outgoing power, reduced skill recharge, reduced incoming damage. A blueprint unlock adds kill healing. Selection free; reset costs escalating run gold. Projection is idempotent and never heals/refills gear by reapplying.
- Gold upgrade changes quality once; reforge deterministically cycles disclosed affixes. Both preserve UID/charges/current timer and validate before spending. All costs/effects are original data in `data/passage.json`.
- Fountain restores HP/flask once per completed visit at 0 BSC. Reopening the same Passage does not reset claims. Ordinary challenge rewards use node active time and the best consecutive ordinary-kill streak since entry; damage resets current streak. Boss challenge requires a defeated Boss and zero actual damage during that fight. Ordinary/Boss service lists differ and show failed, available, claimed states.
- Service inputs consume opening/closing keys, pause combat, show errors/locks/costs, restore focus, and never leak Q/E/1/2 into combat. HUD reflects chosen effects/capacity and blueprint carry risk.

選擇每訪問一次的補給／挑戰帳本，因為重開面板或重建視覺不應再發資源。
放棄新增 NPC 框架與未授權的擴充世界；UI 沿用已完成的全面重製與 2026-11-15 全遊戲多色授權，遵循 [UI system](ui-system.md) 的 MathArt tonal／semantic／biome 色彩與既有 modal，清楚表示可互動／鎖定與操作後果。

## Route boundary

Nine-visit primary route and one lawful cross-run alternative, three distinct Boss mechanisms, guarded atomic final victory/BSC1 unlock. No BSC1 gameplay or unauthorized world expansion. Preserve all existing regression assertions unless the tested contract genuinely changes, retaining legacy fixtures explicitly. End-to-end tests must use ordinary input, actual combat, physical traversal and actual pickup; no teleport, invulnerability, stat overrides or auto awards. Automated play and display captures are labelled automated; mandatory human signoff remains a separate unchecked gate.

Baseline rerun: `python tools/check.py --fast`, 22 steps, 162.82s, passed; `output/delivery-a-baseline-fast.log`. Audio exit reference warning still reproduced. This does not validate the later route/UI additions.
