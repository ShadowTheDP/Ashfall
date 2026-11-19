# Route runtime 執行契約

歷史設計：原 route 契約；舊 roadmap 已刪除，編號只供追溯。房間／能力／地圖見 [biome-graph.md](biome-graph.md)，永久交易見 [delivery-a.md](delivery-a.md)，內容及 Boss 見 [delivery-a-content.md](delivery-a-content.md)、[l5-route-bosses.md](l5-route-bosses.md)。

## 狀態與責任

`Game` 擁有 run node／history／keys／固定0BSC／flask／run_phase，以及 RunBuild 與待結算資料。`Main` 擁有場景轉換；`Level` 報實體出口／死亡／房間事件。Game 在轉場前驗證並保存目的地，Passage 只報服務與固定目的地的繼續請求。Collector 不決定下一 node。

主路為 Ash Gate → Hanging Gallery → Stone Ramparts → Bridge Sentinel → Stilt Foundry → Clock Spire → Clock Warden → High Keep → Silent Regent。Gallery 實際取得 Canopy Rune 後，另一輪可以 Silt Cistern 替換 Gallery，再在 Ramparts 合流。十個 profiles、兩條九訪問路線；stage 只作拓撲排序，HUD visit 來自歷史長度。未製作的 node 顯示未開放，不能選入。

三個 Boss 使用不同 RouteBoss 行為和預警，舊 Warden 留給 legacy fixtures。普通 biome 不要求全圖清怪；Boss 出口要求 Boss 真實死亡。Canopy／Phase／Clock Rune 由守衛與拾取物提供；foundry／clock／兩把 court key 都是實體局內拾取。Ground／Climb 正常來源屬未授權的擴充世界，A 路線不依賴它們。進 node 不自動給獎。Main 在改 run state／釋放地形前先生成驗證新圖，失敗保留原場景與進度。

## 永久與局內

Profile v6 延續 raw backup、legacy_snapshot、未知欄位／ID 封存及 higher-version／讀取失敗拒寫保護。v4→v5 增加已交付藍圖、分次 Cells、Mutation 解鎖與 Forge；v5→v6 增加三個獨立槽與局內檢查點，見 [save-slots.md](save-slots.md)。舊 Souls／stats／skill tree／角色／護甲資料保留，正式 route 的 build 不疊加 legacy power。已持有舊武器仍可選用；新藍圖武器不能從 Archives 繞過交付／投入直接購買。

永久：Profile 貨幣、舊資料、圖鑑／統計、Rune、世界發現、已提交藍圖投入／Forge、合法 BSC1 解鎖。局內：攜帶 Cells／藍圖、gold、五槽裝備／冷卻／充能、Scroll、Mutation、keys、flask、路線歷史。轉場保留同一玩家與 build，死亡／放棄清除局內部分。已提交永久進度保留；晚到 pickup 不補回終局資源。關閉應用後可由同槽的 biome 入口／Passage 檢查點續玩；區內戰鬥、位置與拾取不逐幀保存。永久 temp recovery 與局內檢查點是不同機制，恢復範圍和拒寫行為以 [save-slots.md](save-slots.md) 為準。

最終勝利要求實際九訪問合法歷史、三個 Boss 死亡及最終 node。Profile 單次提交統計、殘留 Cells、首次0BSC的BSC1與最終 Rune；成功才正式結束 run，重複 signal 不重複獎勵。保存失敗保留可重試結算，不允許重開吞掉待提交資料。死亡／放棄同樣只結算一次，放棄不冒充死亡。BSC1僅顯示解鎖，下一 run 仍固定0BSC。

## Passage 與輸入

一個可走動 Passage owner 管 Collector、Mutation、craft、challenge、Fountain 和繼續門；Boss 後增加 Forge。每訪問的時間／普通連殺／Boss傷害快照與 claim ledger 防止重入多領。0BSC Fountain 每訪問補滿一次。逐步投資／品質／Mutation 效果和費用由 data/passage.json 定義。

R互動，F/H治療，1/2武器，Q/E技能，Tab地圖，Esc暫停；Hub／Passage保留J／Enter。面板先消耗輸入並暫停玩家，同鍵不購買或攻擊。暫停／終局 Enter 放棄或返回Hub，R不重開當層。每次按鍵測試必須給新modal完成idle registration的機會，不能在同一physics批次斷言尚未派發的事件。

## 驗收界線

圖推演不是世界拾取證明；fixture 的強制位置／傷害不算通關。Boss probes 驗證實際傷害／階段／清理及原子結算邊界；自動操作只發正常鍵盤事件，讀取狀態導航／戰鬥，不改 actor 位置、HP、數值、獎勵或流程。記錄 seed、鍵、build、收益、永久進度及 capture；自動操作不能替代 GOALS G16／真人雙路線驗收。

選擇保留單一轉場與保存owner，因為同一條路線的裝備、交易、失敗重試必須一致。
放棄任意幀世界存檔、全部19節點和高BSC擴張；既有入口／Passage 檢查點保留，交付A先完成合法0BSC循環，人工簽核前不宣稱 route 驗收完成。

## 2026-11-06 generation revision routing

`Game.generator_revision` belongs to the run and resets to `spatial_v2` only
with `reset_run()`. Main passes it to destination preparation before
`Game.enter_node()` or old-scene destruction. Level's fallback build also passes
the run revision; direct `Level.route_layout()` calls default to newest for
independent generation tools. Schema, socket, footprint or SurfaceReach failure
returns an empty destination with revision/variant diagnostics and preserves the
current world and route. Passage retains the same revision and selected
physical-exit destination through every subsequent biome and checkpoint.

The save owner resolves a missing checkpoint revision to `legacy_v1` before
preparing a resumed entry, then restores that revision after resetting the run.
Unknown revisions and mismatched stamps reject before clearing the scene.
Profile remains the only persistent writer; run revision is carried by the
checkpoint envelope, including all Passage transaction candidates.

Choose explicit run context because seed-only regeneration must reproduce old
entries and continue old Passage runs on the original algorithm.
Reject defaulting missing revisions to latest or changing route history to make
a new embedding load. Central integration passed revision36, save-slot128 and
Passage111 focused checks, including actual legacy continuation against the
pre-upgrade formal-caller golden. The bounded ordinary Ash Gate/Gallery journey
passed7557 checks and earned Canopy without changing the input driver. These
results do not release Fast/Full, complete dual routes or human acceptance.
