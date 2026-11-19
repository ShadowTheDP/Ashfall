# Dead Cells 系統對齊目標（Ashfall 原創內容）

2026-10-29 真人回報後的最新逐項研究見 [詳細機制比較](../research/dead-cells-mechanics-comparison.md)：Scroll 成長、HP 比例／顯示、裝備、經濟、戰鬥與永久進度。該報告是研究與待修事項，不是本文件下方歷史切片的重跑結果。

最終目標與完成標準統一記在 [GOALS.md](../GOALS.md)。本文件是歷史對照與設計理由；舊 L0–L9 roadmap 已於 2026-11-16 刪除，編號只供追溯。route 契約見 [route-runtime.md](route-runtime.md)，房間／能力／地圖見 [biome-graph.md](biome-graph.md)。下方表格與舊實機章節保留當時切片，不代表目前完成度。

## 核心目標

Ashfall 的 0 BSC、無 DLC 首通流程，要在**玩法結構與玩家決策**上對齊 Dead Cells：biome 路線選擇、biome 內房間圖、平台操作、雙武器／雙技能 build、拾取與商店、Passage、死亡風險、永久解鎖與 Boss 節奏。保留 Ashfall 的 MathArt 多色系統、原創角色／敵人／武器、合成音訊與內容數值。

Dead Cells 公開資料沒有包含所有現行內部生成參數；本文件把 0 BSC 首通作第一個可驗收範圍，DLC 與 BSC 1–5 為後續擴充，不假裝已完成。

## 對齊範圍

### Run 路線

- 新 run 從 Ashfall 原創的起始 biome 開始，不再以五個固定 Floor 組成唯一序列。
- 路線採資料驅動的深度／biome graph；玩家每次離開 biome 時，從當前可用出口選下一個 biome。
- Dead Cells 無 DLC 世界圖的公開基準是 15 個普通 biome 與 4 個 Boss biome；單輪每個深度只走一個可用節點。常見首通會造訪 6 個普通 biome 與 3 個 Boss biome，但不是每輪固定走同一條路。
- 0 BSC 的 acceptance path 必須保證可通關，並保留符合符文／鑰匙條件才打開的分支；符文在某輪取得後永久解鎖後續 run 的路線。
- Fresh Profile 不得一開始就顯示所有分支為可選：首次 route 由可用出口與本輪探索 gate 決定，符文解鎖後才擴張後續 run 的路線選擇。
- 代表性首通為 9 次 biome visit：6 個普通 biome、3 個 Boss biome；first-boss slot 有替代節點，完整世界圖仍包含 15 個普通 biome 與 4 個 Boss biome。
- Graph 包含保證可通關的主要路線、可選分支、Boss 節點及符文／鑰匙門檻。內容與名稱由 Ashfall 原創。
- Ashfall route data 的 `stage` 是確保邊前進的拓撲排序，可因支線跳號；HUD 的訪問深度應由實際 route history 計算，與參考遊戲的 stage-slot 分組及資料數值都不混用。
- 首通主路線的長度、Boss 間距、Passage 次數按無 DLC、0 BSC 的公開流程設計；不同解鎖狀態可以開出其他路線。

### Biome 內地圖

- 每個 biome 有獨立的 room template pool，模板描述用途、入口／出口 socket、碰撞與敵人／loot 候選位置。
- 每個 biome 的 concept graph 控制入口、出口、主路長度、戰鬥／探索／特殊房間比例、分支和回合節奏。
- 生成器只放置與 graph 節點、biome 標籤和 socket 相容的 Ashfall 模板；驗證 graph 連通、實際碰撞可達性、門／鑰匙可達、生成點安全與出口可抵達。
- 敵人與 loot 數量按房間用途與空間需求配置，不只從一份固定 floor enemy total 均分。
- 目前 `data/rooms.json` 的房型可作原型素材；不可假設它們已是完成的 biome-specific socket 模板。

### Passage 與經濟

- 每個非終局 biome 的轉場進入可操作的 Passage，而不是直接疊一個 Collector modal 後自動進下一層；最終 Boss 的勝利另由終局流程處理。
- 0 BSC Passage 提供 Collector、Mutation 選擇／替換、裝備處理與完整回血／flask 補給；Boss 後的適用 Passage 額外處理 Forge 類升級。時間、連殺與 Boss 無傷挑戰依 Passage 類型配置，不要求每個 Passage 三種都有。
- Cells 在 run 內攜帶；未花 Cells 死亡時失去，Collector／Forge 已花費的 Cells 與解鎖保留。勝利後剩餘 Cells 以 Residual Cells 留至下一輪，不等同一般死亡入庫。死亡也清除局內 gear、scroll、mutations 與大部分 gold。
- 正式目標由 biome 內對應目的地／鎖條件的實體出口負責選路，Passage 承接已選轉場與服務；遷移第一階段可暫在 Passage 用鍵盤出口列表驗證 graph，後續必須完成空間出口。

### 戰鬥與 build

- 每輪可攜帶兩個武器槽（盾牌佔其中一槽）、兩個技能槽及護符；裝備可由 biome 內掉落、箱子與商店取得，支持替換、回收、詞綴及數值成長。
- Build 採三條角色屬性軸、biome 內 Scroll 類選擇與三個 Passage Mutation 槽；所有效果、物品、敵人和數值都必須是 Ashfall 自己的內容資料。
- 保留 Ashfall 的 J/Z、K、L 等現有鍵位作相容操作；新增功能使用 Dead Cells 公開鍵盤映射：1/2 武器、Q/E 技能、R 互動、F/H 治療、Tab 地圖。新用途不得讓舊鍵位在原有情境失效。

### 移動與死亡

- 保留現有鍵位與動作，補上 Down+Jump 的空中下砸、Jump+Roll 空中翻滾、可攀爬物上下移動及探索地圖。
- S+Space 在地面維持下穿單向平台；空中觸發下砸。舊有地面翻滾仍可用 Shift；空中 Shift 加入跳躍／翻滾的 Dead Cells 動作。
- 死亡結束整輪；局內裝備、Scroll／Mutation 與未花 Cells 清除，藍圖、符文、Collector 解鎖和其他永久進度保留。不得保留「R 重開目前 biome 並繞過死亡」的正式流程。

### 難度進度

- 第一個完整驗收目標是 0 BSC 無 DLC 首通；每個 Passage 的 Health Fountain 都完全補滿 HP 與 flask charges，Malaise、細胞倍數、BSC 鎖門與距離型敵人 scaling 關閉。
- 首次擊敗最終 Boss 後解鎖 BSC 1 與最後一個 traversal Rune；BSC 於起始區選擇，並作為後續 run 的難度設定。
- 後續才加入 BSC 1–5 的敵人池／行為／密度、補給限制、門與進階內容；Profile schema 先避免把舊 `best_floor` 當成 difficulty progression。

### Profile 相容

- 現有 Profile v1 有 `cells`、`souls`、永久 stat upgrades、`skill_nodes`、角色／武器／護甲解鎖與選擇、`best_floor` 及統計；新 schema 不得讓 `_sanitize()` 把這些未知欄位或 ID 靜默刪除。
- 遷移要先保留 v1 原始資料（Profile 內版本化 legacy snapshot 或明確備份），再映射可對應的 blueprints／runes／Boss Cells；沒有等價物的欄位先封存，未經確認不得直接清零或假裝已等價轉換。
- Profile v3 已在 L0 加上原始備份、immutable legacy snapshot、所有版本的 retired ID 封存與 future-version 寫入保護；舊 bonus 暫時保留。Rune/BSC 欄位沿用，但 L1 只接 canopy Rune 與固定 0 BSC，不把切片結尾當正式勝利。
- 新 run-scoped gear、scrolls、mutations、keys、BSC 必須與永久 Profile 欄位分開存放；死亡只清 run-scoped 狀態與未花 Cells。

## 歷史對比（L2 當時）

本輪重新核對原 lead designer 的 [生成設計文章](https://deepnight.net/tutorial/the-level-design-of-dead-cells-a-hybrid-approach/)。它描述固定世界骨架、依 biome／用途設計的手作 tiles、每 biome concept graph、入口／出口相容組裝，再配置敵人與 loot；屬公開設計說明，不代表公開了現行全部內部參數。L2 沿此分工推進，沒有把資料欄位存在當成內容全部完成。

| 部分／目標 | 公開參考中的決策結構 | L2 當時狀態 | 後續處理 |
|---|---|---|---|
| 世界路線 G01 | 固定世界連接、Rune 解鎖分支、Boss 節奏 | 五 node、兩支四訪問路線，biome 內實體出口先決定目的地 | 九訪問三 Boss 與其餘節點內容：後續內容（未授權） |
| 房間生成 G02 | 手作且按 biome／用途區分的模組，以 concept graph 約束組裝 | 五 biome 各有 graph、tag／role／socket、上下支路合流及真實碰撞檢查 | 仍共用部分骨架／模板；獨立 biome 身分、密度與遭遇：後續內容（未授權） |
| Rune／key G03 | 永久探索能力打開後續路線，key 為局內條件 | Canopy／Phase 正式守衛拾取；藤蔓、牆面、Ground 破地、Phase 及一次消耗 key 門 | Climb／Ground 操作與拾取 fixture 通過，正常來源 biome 未製作：後續內容（未授權） |
| 操作／戰鬥 G04/G05 | 平台探索與戰鬥同時成立，動作需可預期、可取消、可辨識 | 保留 J/Z/K/L；R、F/H、Tab、下砸、攀爬、鍵盤 map modal 已接 | 空中 roll、1/2、Q/E、裝備實例與新技能及手感已實作；真人手感待驗收 |
| 局內 build G06/G07 | 兩武器／兩技能／護符、三屬性 Scroll、最多三 Mutation | 現況仍固定 J/K/L 與兩屬性房間 boon | 上述裝備槽、輸入、Scroll 與 Mutation 已在後續工作實作；剩餘為真人驗收 |
| 經濟 G08 | 探索支路讓玩家作 loot／購買／替換／回收的風險收益決策 | Cells／cache／run keys；graph 已支持 shop／elite／reward 房用途 | gold、真實交易／裝備比較、loot／回收已實作；精英特性屬後續內容 |
| Passage G09 | 承接選定目的地，提供補給與局內／永久服務 | 走動 Passage、固定目的地繼續門、legacy Collector、0-BSC 完整 HP/flask refill | Mutation、blueprint Collector、Forge、裝備服務／挑戰門已於後續實作 |
| 敵人／Boss G10 | 各 biome 遭遇與三深度 Boss／替代首 Boss | 現有普通敵人池，第一 Boss 仍暫用 Warden | 新遭遇、必要精英及其餘獨立 Boss：後續內容（未授權） |
| 死亡／勝利 G11 | 死亡結束整輪，局內資源清除，永久投入保留 | death／abandon／late pickup 一致；沒有 R 同 biome 復活捷徑 | 真正終局、residual Cells、下一 BSC 與新 gear 清理已於後續實作 |
| 永久存檔 G12 | Rune／解鎖／品質／難度與局內 build 分離 | Profile v4，raw backup／legacy snapshot／retired ID／future-version 保護及世界發現 | blueprint／Forge 替代與舊 bonus 映射已於後續實作 |
| 起始區／HUD／map G13 | 已發現房間、出口／路線與傳送資訊支援探索 | Tab 局部／世界圖、未知隱藏、疊層 discovery、checkpoint 受位置限制；Passage 地圖 | 新槽位／裝備比較／屬性 HUD 已實作；起始 BSC 選擇屬後續內容 |
| 視聽 G14 | 空間、敵人、互動與預警可讀 | 維持 MathArt tonal／semantic／biome 色彩、純幾何、Juice、768×480、120 Hz 插值；明度、形狀和文字同時保留可讀性 | biome 身分／新服務／Boss 視聽與人工可讀性：各內容輪與人工驗收 |
| 難度 G15 | 首先完成 0 BSC，再擴張難度 | run 固定0，Passage 完整補給，切片結尾不冒充首通／BSC | 完整終局與 BSC 1–5 屬後續範圍 |
| 驗證 G16 | 真入口、合法進度與實際操作都需證據 | 生成2759/0、物理48/0、雙路線108/0、限定流程52/0；display 圖已檢視 | 人工手感、全順序慢測／舊長距離 walk、退出資源警告、export：後續驗收 |

上述裝備槽、輸入、Scroll、Mutation、Passage 服務與終局已在後續工作實作；此段不再是指令。剩餘是真人雙路線驗收與 UI 理解／美術簽核。

L2 標記完成僅指五節點工程交付；G02/G03 的完整內容與 G16 人工驗收仍部分完成。生成器的四項缺口已用反例重現並修正；55秒超時的完整 V3 不計通過，另跑約20秒 flow-only 得52/52。

## 歷史實機與公開畫面对比（L0 前的遷移基準）

以下記錄原五層版本；其提及的舊 h*.png captures 已清理，不能作 L2 畫面證據。

本輪以隔離 Profile 啟動正常 `scenes/main.tscn`，並以 display capture 檢查 Hub、站點、Floor 1/3/5 和房間。Steam 公開畫面與 Wiki biome map 作為參考，不複製其色彩、素材或 room layout：

- [Dead Cells Steam gameplay screenshots](https://store.steampowered.com/app/588650/Dead_Cells/) 顯示實際戰鬥是在連續的 side-scrolling、垂直 platform 空間中發生，平台、敵人、環境危險和 traversal 同時出現在一個可讀畫面；Ashfall 的實機 Floor capture 有可用的跳台／柱體／敵人，但仍是單一長 floor 的大段房間與 `FLOOR 1/5` HUD。
- [Official Wiki biome map](https://deadcells.wiki.gg/wiki/Biomes_map) 顯示固定世界骨架、分層分支、Boss 節點和符文／鑰匙連接；Ashfall 新 `route_graph.json` 已有 15 biome／4 boss 的資料層，但實機仍走 `data/floors.json` 的五個整數 floor，沒有 map、出口選擇或 node-id runtime。
- [Official Wiki Passage](https://deadcells.wiki.gg/wiki/Passage) 列出每次 biome 之間的可操作 Passage：Collector、Blacksmith's Apprentice、Guillain、Health Fountain；Boss 後另有 Legendary Forge。Ashfall capture 的 `THE COLLECTOR` 仍是單一暫停 modal，只能買 7 個永久屬性升級並按 Space 進下一個固定 floor。
- 本輪直接 capture 發現 Hub 的 `close_station()` 沒有清掉 `HubUi._open_id`，會令後續 SKILLS／CHARACTER 被上一個 UPGRADES panel 攔截；已修正為先關閉 HubUi，再恢復玩家。修正後 `meta_capture` 顯示 SKILL TREE、ARCHIVES、CHARACTER 正確切換，`Audit A4` 226 checks 通過。

### 逐項結論

| 面向 | 實機現況 | 與 Dead Cells 的差異 | 優先級 |
|---|---|---|---|
| 世界路線 | route graph 只在資料層；runtime 是 5 floor 線性序列 | 沒有可選出口、map、node-id、完整 Boss 節奏 | P0 |
| Biome 地圖 | 單一 floor 內已有物理 BFS、分層平台和 authored rooms | 沒有 biome-specific room graph、socket、房間分支／回合和 route gate | P1 |
| Passage | Collector 暫停 modal | 缺 Mutation、Forge、重鑄／升級、補 HP/flask、挑戰門、出口選擇 | P0 |
| Build | 固定 J/K/L、永久選擇裝備、房間 boon | 缺雙武器／雙技能 run slots、三屬性 Scroll、三 Mutation、掉落／詞綴／商店 | P1 |
| 操作 | A/D、Space、S+Space、J/K/L、Shift、Esc | 缺 1/2、Q/E、R interact、F/H heal、Tab map、air-roll、dive、climb | P1 |
| 死亡 | 一般 death 已清 run Cells；clear transition death 已補正 | 正式 HUD 仍保留 R retry，會繞過死亡成本與重建 run build | P0 |
| 永久成長 | cells/souls/stat upgrades/skill tree/characters，Profile v2 欄位已加 | 新 Rune/BSC 尚未被 gameplay 使用；舊 stat ladder 尚未映射成 blueprint/forge | P1 |
| 0 BSC | 尚無 runtime BSC／Passage refill | 未驗證 full refill、Boss Cell 解鎖、victory residual cells | P1 |
| 視覺 | 灰階 MathArt、幾何角色、可讀 HUD | Dead Cells 是彩色像素美術；這是刻意的 Ashfall 邊界，不是待修 parity | 不做 |

## 歷史 L1 切片決策（L2 已接空間出口）

原 L0／L1 與後續 route 已實作並記錄自動驗收證據；以下兩支是歷史切片，不是目前待辦。人工手感驗收仍待做。

必須實際完成兩支再合流：

- 新存檔：`ash_gate → hanging_gallery → stone_ramparts → bridge_sentinel`。
- 取得 canopy Rune 後下一輪：`ash_gate → silt_cistern → stone_ramparts → bridge_sentinel`。

兩支各四次訪問、共五個獨立 node；第一條直線單獨通過不能算 branch/rejoin。當時 Passage 選路列表為過渡；L2 已改由 biome 空間出口決定目的地。全部 19 節點與 BSC 1–5 屬未授權的擴充世界，不因本切片完成而計作交付。

## 遷移順序

目標編號見 [GOALS G01–G16](../GOALS.md)，不在這裡複製另一份長期待辦。

## 邊界與驗收

- 使用 Dead Cells 公開的玩法規則與關卡生成方法作為目標，不複製其程式碼、實際 room layout、敵人／loot 數值表、音效或美術素材。
- 只以測試證明 graph/path 可行，不把 BFS pass 當成人類遊玩節奏已成立；每條主要路線仍要人工試玩。
- 目前的五層 floor probes、線性 HUD route strip、Collector 獨立 modal、`best_floor` gate 和 Floor 2/5 Warden 排列都不是新流程的驗收依據，須依新 graph contract 取代或重新定義。

## 設計取捨

選擇 biome graph + Ashfall 手作 room modules，因為這能對齊公開的 Dead Cells 生成分工，同時讓每個 room 仍有明確用途、socket 和路線節奏。
放棄逐房照搬既有 Dead Cells 地圖、敵人／掉落數值與 audio；代價是 Ashfall 必須自行完成內容創作與平衡，而不是只換表面美術。

選擇先做 Profile v2 的加法式 schema，因為目前沒有足夠等價物可無損重映射舊進度，且 route runtime 尚未使用新欄位。
放棄在本階段刪除 Souls、stat upgrades、skill tree 或 `best_floor`；這些先保留，待實際替代內容與玩家存檔轉換規則一併驗收。

選擇以 `stage` 作拓撲順序、route history 作實際訪問序號，因為不同支線可跳過 optional node，兩者需要分開表示。
放棄直接照抄參考遊戲的 stage-slot 編號或用最大 `stage` 當 run 長度；代價是 HUD 與路線驗證必須讀各自正確的狀態。

## 參考

- [Building the Level Design of a procedurally generated Metroidvania: a hybrid approach](https://www.gamedeveloper.com/design/building-the-level-design-of-a-procedurally-generated-metroidvania-a-hybrid-approach-)
- [Dead Cells Wiki: Biomes](https://deadcells.wiki.gg/wiki/Biomes)
- [Dead Cells Wiki: Passage](https://deadcells.wiki.gg/wiki/Passage)
- [Dead Cells Wiki: Controls](https://deadcells.wiki.gg/wiki/Controls)
- [Dead Cells Wiki: Mutations](https://deadcells.wiki.gg/wiki/Mutations)
- [Dead Cells Wiki: Boss Stem Cells](https://deadcells.wiki.gg/wiki/Boss_Stem_Cells)
