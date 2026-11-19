# L3 — 局內 build、戰鬥槽與經濟

> 主體保留L3交付時的設計；Mutation／Forge 與 Profile v6 已在後續實作，不應把下方歷史「未啟用／未實作」當成現況。最新 UI 契約見末節、[UI system](ui-system.md)。

## Ownership 與生命週期

- `Game.build: RunBuild` 是正式 route 的唯一局內 owner。`Game.enter_node()` 第一次成功時建立；驗證失敗不改原場景／run。Hub preview、Arena、legacy fixtures 沒有 build，沿用舊投影。
- `RunBuild` 持有五槽（weapon、weapon、skill、skill、amulet）、本輪 UID registry、每件 charges/cooldown、三屬性、gold，以及未啟用的 `mutations`／`mutation_capacity`。盾牌佔武器槽；不同副本不共用狀態。用 dictionary identity 拒絕偽造 UID、重複裝備、錯種類和越界。
- `Main` 保留同一 Player 跨 Passage／biome；`_apply_loadout()` 只重建投影，不重建 instance、不補充 charges、不免費回血。死亡／放棄清空 build；晚到舊 loot 以 originating-build identity 與 run/alive guard 拒絕。
- Profile 只提供已解鎖的起始武器選擇；其餘四件是資料中明示的免費起始內容。鎖住／未知選擇回退 Rusty Sword。Profile v4、legacy snapshot、升級／角色／護甲／技能資料都不刪除。正式 route 不套 legacy stat、passive、armor、skill-tree 或每房 boon；Hub 顯示 legacy power 提示，route Collector 不出售無作用的 legacy power。

選擇讓 Game 擁有一份可識別的 run build，因為跨場景保留和重複套用必須有同一真實來源。
放棄把 Profile 裝備欄加長或另加背包系統；前者混淆永久／局內所有權，後者超過五槽替換需求。

## 原創資料與公式

`data/gear.json` 定義 10 個 item ID、五件 starter、品質、詞綴、Scroll、狀態、價目、掉落池和房間放置。近戰 combo／時序仍只在 `data/weapons.json`。`Data.valid_gear()` 驗證 content references、種類、action、數值、池與 placements。

- `power = quality.power + affix.power`：plain 1.0、etched 1.15；Keen +0.10。Quick 乘冷卻 0.80；Venom 施加 poison。
- 傷害仍走 `Damage.compute`，每匹配屬性級 +0.12 係數。近戰用武器屬性；Kunai 使用自己的 tactics／品質／詞綴快照，不讀目前手持武器加成；盾防／Aegis counter 用自己的 survival。
- `max_hp = 120 × (1 + B×0.10) × (1 + T×0.08) × (1 + S×0.14) + amulet.hp × power`。初始 Ash Charm +12，故 HP 132。Scroll／護符替換只改上限，現有 HP 只會 clamp。
- Fold Shield：前方 0.30 秒防禦、0.75 秒冷卻、反擊 base 8／radius 80；背後不能擋。Aegis：全向 0.45 秒、冷卻 3.45 秒、反擊 base 10／radius 118。
- Kunai：2 charges，逐次 1.5 秒補充，base 12、速度 820。每件 item 自己計時；換槽／重套不刷新。Passage 保留當前值並停戰鬥時鐘。
- Poison：每 0.5 秒 base 3（套用施加物屬性），2 秒；再次施加刷新期限、不建立疊層 timer。實際 Enemy 的 tick／HP 驗證，不只是欄位。
- 金幣：地圖起點 40、敵死一次 +8；品質價格 plain ×1、etched ×1.5 向上取整；回收 floor(price ×0.35)；食物回復上限 25%，滿血不消耗。

選擇這組小型原創數值以驗證裝備角色、經濟閉環及屬性隔離；保留既有 Damage／Combat.impact／Juice。
放棄參考遊戲數值表和提前加入 Mutation 效果／Forge；這些數字尚未經人工平衡驗收，後續 Passage 服務當時仍未實作。

## 操作與交易

- 1/2 直接使用兩武器；Q/E 使用兩技能。J/Z 是武器一，K/L 是技能一／二。Shift 允許每次離地一次 air roll，落地重置。原地面下穿／空中 dive／climb 保留。
- R 互動。Scroll 用1/2/3、A/D或左右選預覽，Enter才提交；Up/Down捲詳情。裝備比較選相容槽後Enter替換並自動回收舊件，X只回收免費候選，Esc離開。沒有額外背包：五槽滿時用比較替換。
- 商店必須先付得起完整售價，不能預借舊件回收額；檢查後一次扣款／換件／回收。未售商品不能 X 套利；每個 offer 消耗一次，同幀重複互動拒絕。
- 地图、Scroll、比較、暫停與legacy reward picker擁有各自輸入；Q只在暫停／終局退出，不穿透。HUD五槽只留按鍵／幾何辨識／短名稱／充能與回充；品質、詞綴、normal傷害、CD、屬性／Mutation在暫停單項詳情。暫停與比較共用RunBuild真實顯示投影；近戰標FIRST HIT，盾／Aegis標COUNTER，Kunai標HIT；不是DPS，包含常駐build加成，排除crit／status／條件性Edge。秒數仍讀同一`cooldown(item)`，不能讀錯副本或另算一套。
- 所有新圖形使用 MathArt tonal／semantic／biome 色彩、primitive 與 PHI；保留明度、形狀和文字層級，無貼圖或新增粒子模擬。

選擇戰鬥只留按鍵、裝備辨識與可用狀態，因為秒數／詞綴／屬性常駐會搶走交戰注意力；需要比較時在既有暫停詳情讀完整資訊。
放棄導入插畫圖示、另一套背包／全域Theme或改寫全部繪圖式UI；保留 MathArt 幾何與原本鍵盤modal所有權。

## 本輪證據與限制

`tests/l3_build_probe.tscn` 77 checks：真實 Main／Biome、鍵盤事件、碰撞 hitbox／projectile、敵人 HP／poison tick、盾防方向、逐件冷卻、Scroll／食物／滿槽替換／交易／回收、轉場、死亡、放棄、最後 pause-Q 真實退出。戰鬥及能力個案有 fixture 定位／固定敵人；不是一整輪人工遊玩。`biome_play_probe` 48 項另覆蓋真實移動、dive／climb／Rune／modal。

`python tools/check.py --fast`及display l3 77項是上述L3輪次的歷史證據；不作本UI輪通過依據。

## 2026-11-02 顯示投影與決策契約

- `RunBuild.display_stats()`重用`Damage.compute`、`health`、`cooldown`及當前品質／詞綴／匹配軸／常駐Mutation；`replacement_projection()`／`scroll_projection()`使用只讀計算副本，不改live slots／UID／wallet／checkpoint。候選與現裝在同一build基準、同種動作才可解讀數值差。
- Scroll明示下一點受益槽位、真實normal傷害與max/current HP；現規則只提高上限、不回血，預告NO HEAL；MECH-01比例政策獨立，UI修復沒有改公式。
- HP文字max向上取整；未滿current向下取整，正值小於1仍顯示1，0為0，真滿分子=分母；FULL/HURT用raw值判斷。血條每格按ratio部分填充，不能用ceil讓未滿全亮。
- 本輪isolated Fast32/224.65s及L3 display103／HUD65通過；before/after、長內容與真實按鍵路徑已於該輪檢查。模型視覺審查不等於真人理解／真人雙路線驗收；未重跑本輪Full。

選擇原owner提供無副作用投影與一致顯示契約，因為預覽不能另寫一套可能漂移的玩法公式。
放棄重平衡／維持HP比例、新背包及整套UI遷移；它們不是本輪授權的顯示修復。
