# Ashfall 最終目標

本文件是產品成果的唯一清單。L0–L9 roadmap 已於 2026-11-16 廢除；視覺規格見 [ui-system.md](design/ui-system.md)。[roguelite-parity.md](design/roguelite-parity.md) 保留公開參考、差異盤點與設計理由。歷史文件中的固定五層、每房 boon、R 重開當層等描述是遷移來源，不是完成條件。

## 總目標

在 `C:/Users/user/Desktop/DC-like` 將 Ashfall 做成可從新存檔開始、以純鍵盤探索分岔 biome、建立局內 build、經 Passage 補給及永久解鎖、連續擊敗三個深度 Boss 並完成 0 BSC 首通的原創 roguelite。代表性主路為 6 個普通 biome 加 3 個 Boss visit；長期世界包含 15 個普通 biome 與 4 個 Boss 節點。以實際遊戲入口、逐步解鎖路線、隔離存檔測試、生成可達性、完整 run 與人工試玩共同驗收。

## 交付層次

| 交付 | 完成後玩家能做什麼 | 邊界 |
|---|---|---|
| A：0 BSC 首通 | 從起始區完成九訪問主路；有一組可實際選擇、分岔再合流的替代路線，以及完整局內 build、Passage、死亡和勝利循環 | 九節點名稱或自動通關 probe 單獨通過都不算完成 |
| B：完整無 DLC 世界 | 15 普通 biome／4 Boss 都有原創可玩內容；所有設計上可解鎖的分支能透過合法進度到達，且每條路線都有離開方式 | 不要求一輪逛完全部節點，也不要求 0 BSC 開放所有 BSC 門 |
| C：後續難度 | A/B 穩定後，再逐級完成 BSC 1–5 的敵人、補給、獎勵與門檻變化 | 目前是後續規劃；終局與免費／付費 DLC 邊界需先核對，不自動擴充 DLC |

沒有要求交付日期；以驗收里程碑推進，不用任意週數或 token 預算代替工作估算。

## 各部分最終目標

所有「部分完成」只代表已有可重用基礎。下表沒有任何一列可因資料欄位存在就直接標成已驗收。

| ID／部分 | 最終目標 | 必須看到的完成證據 |
|---|---|---|
| G01 世界路線 | 以 biome node id、當輪路線歷史與明確終局控制 run；主路九訪問、三次 Boss，分支由 Rune／鑰匙／BSC 條件開啟；長期實現 15+4 節點 | 新存檔能完成主路；至少一組替代路線在遊戲中分岔、合流；合法進度可解鎖其餘節點；勝利不取決於資料列數或 `floor_index + 1` |
| G02 Biome 與房間生成 | 固定世界骨架 → biome concept graph → 手作 room modules → socket 拼接 → 敵人／loot 配置；具垂直探索、支路、特殊房與不同 biome 身分 | 同一 seed 可重現；graph 及實際碰撞均可達；鑰匙在門前可取得；每個 biome 的模板池、遭遇與探索目的有實機證據；普通出口可在仍有非必要敵人時使用 |
| G03 Rune 與探索能力 | Rune 在世界內由探索／精英／Boss 取得並永久保留，實際解鎖攀爬、牆面、破地／傳送類路線；鑰匙是當輪資源 | 從零 Rune 逐輪推演能取得所有規劃 Rune，沒有「先有此 Rune 才能拿到它」的循環；能力在真實碰撞中生效；死亡後 Rune 保留、鑰匙清除 |
| G04 移動與輸入 | 保留既有移動、跳躍、翻滾與 J/Z、K、L 的相容用途，加入空中翻滾、下砸、攀爬和完整鍵盤操作；新動作用公開對應按鍵 | A/D／方向鍵、Space、S+Space、Shift；1/2 武器、Q/E 技能、R 互動、F/H 治療、Tab 地圖、Esc 暫停均有真實輸入驗證；開 panel 的同一按鍵不觸發攻擊／購買／退出 |
| G05 戰鬥與手感 | 以原創武器、技能、盾防／格擋、翻滾、暴擊、狀態效果與敵人預警形成可讀戰鬥；保留 Ashfall 的連段、Perfect Dodge 與數學武器特色 | 預警、武器外形及 hitbox 一致；取消、無敵、冷卻、命中次數和傷害共用公式可驗證；真實 biome 的高低差也能命中；四級 impact 逐幀 capture 與人工試玩通過 |
| G06 局內裝備 | 兩個武器槽（盾牌佔其中一槽）、兩個技能槽及護符；裝備由本輪起始物、掉落、箱子與商店取得，支援替換、品質與詞綴 | 能以鍵盤使用兩武器／兩技能、檢查比較與替換；跨 biome／Passage 不丟 build、不重複疊加；死亡清局內裝備；解鎖只影響物品池，不永久保留上輪武器 |
| G07 Scroll 與 Mutation | 三條屬性軸由 Scroll 選擇成長；Mutation 是當輪最多三槽的規則變化，可於 Passage 選擇及重置 | 三屬性都能影響對應裝備與生命；Mutation 可用槽隨進度開放至三個，效果、費用與重置可驗證；轉場保留、死亡清除；屬性以各軸形狀、名稱與 MathArt 色彩（同時保留明度差）辨識 |
| G08 掉落、商店與經濟 | 分清 gold、攜帶 Cells 與永久解鎖投入；有 loot、商店、食物／補給、回收及裝備服務，支路給可理解的風險／收益 | 每種貨幣來源／支出可追溯；支付與回收不重複、不為負；掉落和價格由原創資料定義；可在一輪內完成拾取→比較→購買／替換／回收；大部分 gold 在死亡時失去，保留能力另有明確上限 |
| G09 Passage、Collector 與 Forge | 每個非終局 biome 轉場經可走動 Passage；Collector 接藍圖與 Cells、裝備服務花 gold、Guillain 類服務選 Mutation、0 BSC Fountain 補滿 HP／flask，Boss 後增加 Forge | 所有服務及出口可用鍵盤；Collector 支持逐步投入且已交付進度死亡後保留；未花 Cells 可帶去 Forge；品質升級影響之後掉落；挑戰門按該 Passage 類型提供時間／連殺／Boss 無傷條件，不要求每個 Passage 三種全有 |
| G10 敵人、精英與 Boss | 原創 biome 敵人池與精英遭遇；三個 Boss 深度、第一深度有替代 Boss，共四個可區分的 Boss 節點／遭遇 | 三深度與替代 Boss 都有不同可玩行為及預警；真實生成地形的傷害可命中；不靠重用 Warden 名稱湊數；必要戰鬥不軟鎖，非必要敵人不阻擋普通出口 |
| G11 死亡、重開與勝利 | 死亡結束整輪、計數一次、清 gear／Scroll／Mutation／鑰匙／未花 Cells，保留永久投入；勝利保留 residual Cells，首次 0 BSC 終局解鎖下一 BSC 與最終 Rune | 普通、Boss、轉場及晚到 pickup 的死亡都同一契約；正式 R 不重開當前 biome；主動重開回起始區並放棄局內資源；勝利／殘留 Cells 只能領一次；下一輪從起點開始 |
| G12 永久進度與存檔 | Profile 單一擁有永久 Rune、blueprint／Collector 進度、Forge 品質、BSC、圖鑑與統計；舊 v1/v2 進度可恢復且不靜默刪除 | 遷移前原檔備份或等價完整快照；舊 cells／souls／upgrade IDs／skill nodes／選擇／統計均有映射或封存；重複載入不重複轉換；壞檔／中斷可恢復；所有 probe 使用隔離 Profile |
| G13 起始區、HUD 與地圖 | 起始區管理新 run、已解鎖起始物和 BSC；HUD 顯示局內槽位／HP/flask／貨幣／屬性／Mutation／Boss；探索地圖與世界圖顯示已發現房間、出口、路線和鎖因 | 純鍵盤走完開局→探索→map→服務→下一 biome→結算；HUD 與真實 state 一致；未知區域不預洩；沒有 `FLOOR n/5`、幽靈 panel 或同鍵多 handler；舊角色／skill tree 轉換可追溯 |
| G14 MathArt、動畫與音訊 | 保留原創多色數學美術、正方形玩家／幾何敵人、無臉無肢、φ 比例、Juice 粒子與合成音訊；以 MathArt 的 tonal／semantic／biome 色彩搭配形狀、明度、輪廓與動作區分敵我、地形和互動。玩家深色內凹面與單一明亮核心點是既有方向／翻轉例外 | 新 biome、服務、裝備與所有狀態均遵守 MathArt；768×480 邏輯、可縮放視窗（初始 1536×960、aspect keep 連續縮放）、120 Hz 插值及物理相機不變；逐 biome／Boss／Passage capture 可讀；聲音不遮蓋攻擊預警 |
| G15 難度與解鎖 | 首先完成 0 BSC：補給完整、沒有 Malaise／Cells 倍率／BSC 門／距離型難度加成；之後逐級擴充 BSC 1–5，起始區選擇、開局後固定 | 0 BSC baseline 測試；首次終局只解鎖下一級一次；不可選未解鎖難度；後續每級的敵人／補給／門／獎勵／終局差異有資料及證據 |
| G16 驗證與可交付版本 | 同一入口能正常玩完、測試與人工證據一致、Windows 建置可獨立啟動；資料驅動內容可逐步擴充 | 所有新 route／save／combat／input checks 和適用的既有 checks 通過；每個已完成 biome／Boss／Passage 有 capture；代表主路與替代路線有人類鍵盤試玩紀錄；沒有未處理 script error 或阻塞；退出 leak 要定位後消除或記錄可重現原因；可用匯出模板時產出 build |

## 必須採用的流程定義

1. **選路與 Passage**：正式目標是 biome 內不同出口各自對應目的地／鎖定條件，玩家離開時選路，Passage 承接已選的轉場與服務。第一個遷移版本可暫以 Passage 出口列表驗證 route；這只是過渡，不是最終空間選路驗收。
2. **普通關卡與戰鬥門**：普通出口不要求殺光整個 biome；Boss、必要精英或明確戰鬥房可以有局部封鎖。原本「annex 不能有敵人」的限制須隨此契約重新評估，不能永久沿用全層清怪前提。
3. **實際取得與圖推演**：`rune_rewards`／`key_rewards` 是內容承諾，不能在進入 node 時自動當成玩家已拾取。驗證要包含實際取得點、守衛、門檻與跨輪永久進度；全解鎖 BFS 不等於 fresh Profile 可逐步解鎖。
4. **兩種深度**：graph 的 `stage` 作拓撲排序，可以跳號；HUD 的 visit depth 應取實際訪問序號，不能把 `stage = 11` 顯示成玩家第 11 次訪問。
5. **永久與局內**：active BSC 選擇可由 Profile 記住，下輪開始後將難度固定在 run state；局內裝備、gold、Scroll、Mutation、keys 不寫成永久 loadout。既有 Souls／stat ladder／身體被動先保存，再依實作的對應規則遷移。

## 完成證據與停止條件

每個 G 項目完成時，記錄實際入口／場景、seed、隔離 Profile、測試結果與 capture；人工試玩尚未完成就保留未驗收，不用百分比或 screenshot 數量代替功能證據。

交付 A 必須同時滿足：新存檔九訪問主路能勝利、另一條已合法解鎖的分支可合流完成、0 BSC 的兩武器／兩技能／三屬性／三 Mutation 上限與 Passage 服務可玩、死亡／勝利永久進度不相混。交付 B 另需所有 19 個節點有內容及合法解鎖證據，不能只通過圖檢查。

只有遇到會刪除／貶損既有玩家進度、需要改 MathArt／鍵盤／渲染硬邊界、公開來源矛盾到影響實際規則，或新增 DLC／線上服務範圍時，才停止依賴工作並提出具體選項。一般實作順序、可逆程式修改與隔離測試按已授權範圍繼續。

## 範圍與設計取捨

選擇公開的 Dead Cells 流程與生成分工作為玩法目標，因為它們提供清楚的探索、局內 build 和死亡風險；原創數值、房間、物品、敵人、美術與聲音由 Ashfall 自行設計。
放棄複製原作程式、實際 room／level data、資產、數值表和 UI 皮膚；也不把彩色像素風、DLC、多人、雲端、排行榜或重做引擎列入這次目標。

選擇以 A／B／C 分階段交付，因為可玩閉環先驗證 ownership 與節奏，完整世界再驗證內容與跨輪解鎖。
放棄一次製作 19 個外觀不同但流程未接通的場景；代價是早期 slice 會重用部分原創內容，且必須明確標為過渡實作。

## 公開參考

- [Dead Cells Steam：玩法概述與畫面](https://store.steampowered.com/app/588650/Dead_Cells/)
- [Biomes](https://deadcells.wiki.gg/wiki/Biomes)／[世界圖](https://deadcells.wiki.gg/wiki/Biomes_map)
- [Passage](https://deadcells.wiki.gg/wiki/Passage)／[Mutations](https://deadcells.wiki.gg/wiki/Mutations)
- [Controls](https://deadcells.wiki.gg/wiki/Controls)／[Runes and upgrades](https://deadcells.wiki.gg/wiki/Runes_and_upgrades)
- [Currency](https://deadcells.wiki.gg/wiki/Currency)／[Boss Stem Cells](https://deadcells.wiki.gg/wiki/Boss_Stem_Cells)
- [Sébastien Bénard：The Level Design of Dead Cells](https://deepnight.net/tutorial/the-level-design-of-dead-cells-a-hybrid-approach/)（本輪重新核對；固定骨架、目的房／biome pools、concept graph、相容組裝與敵人配置）

公開畫面用於比較畫面內資訊與空間用途；操作時序、數值、難度和路線鎖需要文字來源及實機驗證，不能由截圖推定。具體 mob／room 數與未公開生成參數仍由 Ashfall 原創，不假稱一比一還原。
