# 多存檔與局內檢查點

本輪依真人回饋新增三個獨立存檔與有限的局內恢復。Profile 是唯一寫入者，沿用同步 temp→rename、遷移備份、未知欄位保留與高版本拒寫，沒有新資料庫或依賴。

## 玩家操作與恢復範圍

- 標題 W/S 或上下鍵選 SAVE 1/2/3，Enter 繼續該槽；無檢查點時進大廳。N 再 N 確認放棄這一局，永久解鎖保留。Esc 取消確認，Q 離開。
- 遊玩中 Esc 暫停，T 回存檔選單；遊戲已暫停，切槽前不再前進。無法保存時顯示錯誤並留在原狀態，不能顯示假成功。
- 自動檢查點在正式 biome 入口、Passage 入口及成功的永久進度／Passage 交易。保存 HP、藥瓶、局內 Build、金錢、攜帶 Cells／藍圖、路線及服務領取狀態。
- biome 內普通戰鬥、走路與拾取不逐幀存檔；重開從該區域入口恢復，這個入口之後的局內進度會重來。已提交的永久進度另外保留於同一 Profile；繼續時門的永久 Rune 條件使用該槽已取得的進度。
- Passage 的裝備、Mutation、金錢、Fountain／challenge 領取同步保存；回讀不能重新領取或返還已花資源。死亡／放棄／勝利在同一原子永久提交中清除檢查點；失敗保留待結算並阻止跨槽。
- 生成升級對已知舊 v1 檢查點保留精確 legacy revision；不要求為本次空間變體放棄舊局。未知 revision／不符該 revision 的內容指紋仍拒絕並保留原檔；N/N 保留為玩家自選放棄操作，不作升級必要步驟。

## 檔案與 schema

- Profile VERSION6，舊槽一仍用 `user://ashfall_profile.json`，槽二／三為 `.slot2`／`.slot3`。隔離測試以 `ASHFALL_PROFILE_PATH` 基底套用相同規則；三個正式路徑都禁止被測試覆寫。
- v5 遷移新增空 `run_checkpoint`；保留原始備份、legacy snapshot、未知欄位與原有永久內容。高於 v6 或不可讀的檔案仍鎖寫。
- `Profile.select_slot()` 強制讀磁碟；測試永久狀態使用 `load_profile(true)`，普通 load 會早退。槽位切換不繼承上一槽的 Profile 字段、build 或待結算。
- `RunCheckpoint` 只負責封裝／驗證／還原局內資料；仍由 `Profile.save()` 寫入同一文件。檢查點含獨立版本與內容指紋，驗證 route／phase、九訪問 receipts、有限數值、keys／Runes、服務 claims、裝備種類與 UID 等，再準備世界；拒絕時不拆掉現有世界或覆寫檔案。
- `RunBuild.from_checkpoint()` 以同一 canonical dictionary 還原 registry／slots；UID 唯一，serial 延續。不能僅深拷貝五槽而產生與 registry 脫鉤的裝備。

## 交易邊界與故障行為

- `save()` 接受與永久提交相容的候選檢查點。Passage 投入 Blueprint／Forge 的永久成果與扣款後的局內 wallet 在同一提交中；保存失敗時都回滾。否則重開可拿到永久成果及原本的 Cells，造成可重複消費。
- 成功的永久 Rune／發現記錄保留，入口快照保持其進入點的局內資源；繼續時由同槽 Profile 提供永久 Rune 條件，不能從其他槽帶入。
- 場景轉換若檢查點寫入失敗，保留畫面、暫停並顯示可用的重試操作；不能偷偷當作已保存，也不能讓第一次入圖的活動世界繼續前進。
- 死亡／放棄結算失敗仍可由鍵盤 Enter 重試、Q 離開。待結算不能透過 T／標題切到其他槽付款。損壞檢查點的 N/N 恢復必須驗證 kills 類型，不能讓 null／array／dictionary 的整數轉換封死恢復入口。

選擇三個獨立 Profile 與入口／Passage 檢查點，因為可沿用現有原子提交和程式組裝世界，先讓長流程能分段驗證並避免永久成果與局內扣款分離。
放棄任意幀存檔、逐個敵人／掉落／投射物序列化、另建存檔服務或自動修補不相容內容；這些需要更大的世界狀態協定，本輪不以近似還原冒充完整中途存檔。

## 回歸與驗收

`save_slots_probe` 使用隔離磁碟與實際鍵盤，覆蓋三槽、v5 遷移／高版本、入口與Passage往返、canonical identity、資源／claims、防止損壞還原與拒寫回滾、N/N損壞恢復。`terminal_failure_probe` 覆蓋待結算時的 Enter/Q/T。`profile_path_probe.py` 驗證全部正式槽 hash 保持不變。

`l6_input_play` 在首輪勝利後強制磁碟重載再進合法 Cistern，提供正常輸入的跨存檔永久進度證據。這仍是自動化，真人雙路線簽核維持未取得。

## 2026-11-06 generator compatibility envelope

`RunCheckpoint.VERSION` remains 1. A new optional envelope field,
`generator_revision`, identifies a whole run. Missing revision resolves only to
`legacy_v1`; malformed/unknown values reject before restoration. New reset runs
use explicit `spatial_v2`. The exact known original eight-table stamp is
`6e650d44b82df4dffbc159894f441eab687f38594d6b01852a67ade3953b15e0`.
Both the current original tables and the saved legacy content must match it.
No arbitrary historical hash is accepted and no saved stamp is rewritten.
The eight original tables and original traversal JSON remain byte-identical.

The `spatial_v2` stamp includes the run revision, explicit
`authored_spatial_v2` algorithm revision, all eight original tables,
`data/generation_spatial_v2.json` and `Data.traversal`. A generation algorithm or
traversal contract change therefore requires an explicit revision/content
change. Old entry Continue reconstructs the legacy canonical layout; old
Passage Continue and all later biome/transaction checkpoints retain
`legacy_v1` until that run ends. `Game.reset_run()` alone selects newest again.
Capture carries the revision outside the old state FIELDS, so unchanged Passage
candidate clones retain it and rollback never changes the run context.

Profile's permanent schema, raw backups, temp→rename atomic writer, migration,
N/N policy, failure retry, unknown-field retention and live-save ownership do
not change. Unsupported checkpoints remain untouched. This implementation does
not deserialize arbitrary worlds or introduce a migration framework; future
changes to the protected old tables need a separately verified version context.

The genuine pre-adaptation fixture
`tests/fixtures/generation_legacy_v1.json` was captured by the centralized root
Godot owner from actual Main/Profile entry and settled Passage transactions,
with forced disk reload, original entry/Gallery-seed17 canonical layouts and
15 baseline source hashes. Its immutable SHA256 is
`f36efd0dfe7f85d955fb16dfd5653995ed405e462408a31c93e3881f2ca41397`.
The root evidence is
`output/ui-refinement-map-2026-11-04/legacy-v1/pre-adaptation-v1.json`, with
`capture.command.json` recording exit 0 / 2.95s on the unadapted runtime.
The initial capture attempt and its correction remain separately recorded;
this is historical fixture evidence, not a pass of upgraded restoration.

`tests/generation_revision_probe.gd` exercises new entry restoration, exact old
entry reconstruction, old Passage continuation, subsequent legacy checkpoints,
unknown revisions/stamps, traversal stamping, failed-save rollback, unchanged
permanent payload and preflight failure preserving Hub/route/Profile bytes.
Central integration passed36 checks plus the existing128-check save-slot probe.
`tests/fixtures/generation_legacy_transition_v1.json` has been removed; it had
zero code references. Its bytes are preserved at
`output/ui-refinement-map-2026-11-04/integration/legacy-transition.json`. The
upgraded probe replays that recorded formal caller and compares its actual level
geometry/spawns/graph/keys/rewards and forced-reload checkpoint
seed/revision, not just a direct generator result. The original `generation_legacy_v1.json`
input above remains live and byte-identical. JSON numeric
representation is normalized without numeric tolerance. Complete capture/source
provenance and runtime logs are in the integration evidence directory; three live
Profile hashes/absence states remain unchanged. Full routes and human acceptance
remain pending the independent integration gate.

Choose an exact legacy context plus one explicit new revision because old runs
must reconstruct their original world without weakening fingerprint checks.
Reject missing→newest defaults, checkpoint deletion, stamp substitution and
forcing abandonment; none preserves the promised old biome or Passage run.
