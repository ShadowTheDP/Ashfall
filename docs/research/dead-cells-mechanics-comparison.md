# Dead Cells 詳細機制與 Ashfall 現況對照

> 歷史研究（2026-10-29）：下文「目前／未修復／本輪」及程式行號指研究當時，不是現行開工限制。其後 HP 顯示、Scroll 真實預覽與全面 UI 重製已完成工程驗證，真人理解／美術仍待確認；MECH-01 的成長／current HP 規則仍待獨立決策。UI 契約以 [ui-system](../design/ui-system.md) 為準，歷史建議不自動授權改公式。

研究日期：2026-10-29。起因：本輪真人試玩回報 Shop／Gear／Scroll／Chest 看不懂、Scroll 成長不符預期、最大血量增加時血量比例改變、HP 顯示不正確。

本輪交付是研究報告與問題紀錄。以下的「建議」「應驗收」尚未實作；本輪沒有修改遊戲玩法、UI 或玩家存檔。既有 Fast／Full 通過只代表當時檢查範圍，不能用來關閉這批新問題。

## 1. 先看結論

1. **UI-01 仍是正式可讀性問題。** Shop、Gear、Scroll、Chest 的用途、選項與操作結果不清楚，不能用「交易成功」代替「玩家看得懂」。
2. **你對 Scroll 的觀察有依據，但要分傷害與 HP。** Dead Cells 相同軸每增加 1 點，相關裝備傷害固定乘 **1.15**；因此絕對增加的傷害會越來越多。**HP 的下一點增幅則隨該軸點數增加而遞減**。目前 Ashfall 的傷害倍率為線性、各軸 HP 倍率也為線性，HP 再跨軸相乘；它的下一點 HP 相對收益也會下降，但曲線與 Dead Cells 不同，卡片還固定寫同一增幅。
3. **目前增加最大 HP 時，現有 HP 沒有同比例增加。** `_apply_loadout()` 只是重算最大 HP，然後 `hp = minf(hp, max_hp)`；原本滿血的人拿到加血 Scroll，反而變成缺血。這與你要求的比例不變不一致。
4. **HP 數字有可由程式直接推導的錯誤。** 目前 HP 用 `ceil(hp)`、最大 HP 用 `int(max_hp)`。例如實際滿血 `141.6 / 141.6`，可顯示成 **142 / 141**。
5. **HP 條也會誤導。** 每格向上計算；例如 7 格的血條，90% HP 仍點亮全部 7 格，看起來像滿血。
6. 裝備等級、雙屬性／無色裝備、詞綴連動、商店庫存、詛咒箱、Recovery、Mutation 成長等，仍有簡化或缺少的部分。下文逐項區分「實際錯誤」「設計差異」「尚未涵蓋的內容」，不把所有差異都當成 bug。

## 2. 研究口徑與證據限制

- 參考現行 PC 規則，以社群維護的 [Official Dead Cells Wiki（wiki.gg）](https://deadcells.wiki.gg/) 為主要詳細機制來源，並用開發者公開 patch notes 校對版本變化。Wiki 名稱含 Official，但不是公開的引擎原始碼或完整內部規格。
- 主要比較 Ashfall 現階段的 **0 BSC／普通模式**。高 BSC、Daily Run、Custom／Assist、DLC 特例會另外標出，不能直接當作首通缺陷。本輪詳細覆蓋 Scroll、HP、裝備、拾取／商店／寶箱、戰鬥生存、永久進度與路線獎勵；不是每件武器、每個敵招與每個 DLC 的全量百科。
- 舊攻略有版本問題。例如 [2017 年 Update 5][S26] 的「三軸首點都是 +50% HP」不能當現行公式；舊版 Legendary 的雙最高屬性相加，也不能套到現行規則。
- Dead Cells 的公開 Wiki 明確提供傷害、最大 HP、裝備、商店與 Recovery 等規則；**沒有在本輪找到涵蓋所有來源的「最大 HP 改變時 current HP 一律如何重算」一手規格**。本報告將「保留比例」列為使用者對 Ashfall 的明確要求；不把它冒稱為已完成 Dead Cells 實機逐幀驗證的通用定律。
- Ashfall 現況以當前資料與實際呼叫路徑核對，主要入口是 [RunBuild](../../scripts/systems/run_build.gd)、[RunLoot](../../scripts/world/run_loot.gd)、[Player](../../scripts/player/player.gd)、[HUD](../../scripts/ui/hud.gd)、[BuildScreen](../../scripts/ui/build_screen.gd)、[Game](../../scripts/autoload/game.gd)、[gear.json](../../data/gear.json)、[passage.json](../../data/passage.json)。
- Dead Cells 的數學式與數值在這裡用於**分析與對照**。若後續改 Ashfall，仍使用原創內容與自主平衡，不搬用對方程式、資產、掉落表或房間資料。

## 3. Scroll／三屬性：實際怎樣成長

### 3.1 基本定義

| 項目 | Dead Cells 公開規則 | Ashfall 當前狀態 | 對玩家的影響 |
|---|---|---|---|
| 三屬性起點 | Brutality／Tactics／Survival 各從 **1** 開始 | `attributes` 各從 **0** 開始，記錄本輪增加量 | 0 本身不是錯；比較公式必須先換算，不能少算或多算一點 |
| 普通 Scroll of Power | 在三種屬性中選 **一種 +1** | 已有三選一 Scroll | 基礎決策存在 |
| 雙屬性 Scroll | 只提供指定兩種屬性；選其中一種 +1 | 未見雙屬性 Scroll 的候選約束 | 目前每次都能自由補主屬性，少了被迫補副軸、換取 HP 的決策 |
| 雙屬性生成傾向 | 偏向玩家較低的兩軸；**精確權重未公開** | 未實作此種 Scroll 類型 | 不能直接聲稱等機率，更不應憑空填權重 |
| 加成對象 | 卷軸增加角色屬性；裝備依自身 scaling 屬性使用相應值 | 每件裝備只有單一 `attribute` | 需要讓玩家看懂「此點會強化哪幾個已裝備物品」 |
| HP 與傷害 | 每一點同時影響該軸裝備傷害與角色最大 HP，兩者公式不同 | 也同時影響，但公式簡化 | 同一張卡片不能只寫抽象的「buff」 |
| 持續時間 | 本輪屬性，死亡後重置；不等於永久升級 | RunBuild 管理本輪屬性，跨 biome 保留、run 結束重建 | 結構已有 |
| Scroll Fragments | **3 BSC 起**出現，四片換一點 | 未做；目前只玩 0 BSC | 後期擴充項，不能列為 0 BSC 必須修好的錯誤 |

來源：[Stats][S1]。

### 3.2 傷害：固定百分比，指數累積

Dead Cells 的單軸裝備傷害倍率：

```text
S = 當前使用的屬性等級，起始 S = 1
傷害倍率 = 1.15^(S - 1)

若 n = 本輪比起始增加的該軸點數：
傷害倍率 = 1.15^n
```

每一點都是在**當前傷害**上再增加 15%。不會因為已經有很多同軸點數，就把「下一點的相對傷害收益」降成 5% 或 3%。

Ashfall 當前的屬性部分：

```text
n = attributes[該裝備的 attribute]
屬性傷害倍率 = 1.0 + 0.12 * n
```

這是每點增加「基礎傷害的 12%」。其他品質／詞綴倍率存在，但不會把這條線性曲線變成指數曲線。固定同一件裝備，只比較屬性部分：

| 已增加同軸點數 n | Dead Cells 倍率 | Ashfall 倍率 | Ashfall 下一點相對目前傷害 | Dead Cells 下一點相對目前傷害 |
|---:|---:|---:|---:|---:|
| 0 | 1.0000 | 1.00 | +12.000% | +15% |
| 1 | 1.1500 | 1.12 | +10.714% | +15% |
| 2 | 1.3225 | 1.24 | +9.677% | +15% |
| 5 | 2.0114 | 1.60 | +7.500% | +15% |
| 10 | 4.0456 | 2.20 | +5.455% | +15% |
| 15 | 8.1371 | 2.80 | +4.286% | +15% |
| 20 | 16.3665 | 3.40 | +3.529% | +15% |

例：基礎 100 傷害，不計任何其他乘區。Dead Cells 的第 1 點增加 15、第 2 點增加 17.25；到了第 20 點，增加量遠大於起始。Ashfall 每一點仍只增加 12。

**判斷：MECH-01 是真實規則差異。** 若目標是相同的 build 決策，不能只改卡片文字；要一起審視屬性曲線、敵人 HP、每路線 Scroll 數、裝備強度與 Boss 戰長度。採用乘法成長的結構，也不代表必須照搬 15% 這個數字。

### 3.3 HP：各軸分別遞減，再相乘

Dead Cells 基礎 HP 為 100。忽略 Mutation 等額外修正時：

```text
nB = Brutality - 1
nT = Tactics - 1
nS = Survival - 1

max_hp = round(100 * fB(nB) * fT(nT) * fS(nS))
```

Wiki 公開的分軸函式：

```text
fB(n) = 1 + (897/1360)*n - (13/1360)*n²   ，0 <= n <= 34
       = 12.375                         ，n > 34

fT(n) = 1 + (49/96)*n - (1/96)*n²        ，0 <= n <= 24
       = 7.25                           ，n > 24

fS(n) = 1 + (833/1180)*n - (7/1180)*n²    ，0 <= n <= 59
       = 22                             ，n > 59
```

下一點實際給多少 HP，不是直接讀函式係數：

```text
該軸下一點的相對最大 HP 增幅 = f(n + 1) / f(n) - 1
```

下表由公開函式計算，保留未整數化的百分比；遊戲卡片與最終整數 HP 會有取整差異：

| 同軸已增加點數 n | 下一點 Brutality HP | 下一點 Tactics HP | 下一點 Survival HP |
|---:|---:|---:|---:|
| 0 | +65.000% | +50.000% | +70.000% |
| 1 | +38.235% | +31.944% | +40.479% |
| 2 | +26.821% | +23.158% | +28.318% |
| 5 | +13.659% | +12.025% | +14.623% |
| 10 | +6.910% | +5.761% | +7.787% |
| 15 | +4.155% | +2.970% | +5.091% |
| 20 | +2.582% | +1.183% | +3.630% |

重要含義：

- 同一軸投得越多，下一點的相對 HP 收益通常越低。
- 三軸分別計算成長，再把倍率相乘。沒有投過的副軸，第一點仍有很高的 HP 收益。
- 主軸的傷害每點仍乘 1.15，所以為了輸出通常集中主軸；不能選主軸的雙屬性 Scroll，才容易形成補 HP 的副軸選擇。
- HP 曲線到平台後不再增加，不代表該屬性的傷害也停止增加。這些是不同上限。
- 固定最終三軸與其他修正時，三軸相乘的次序不改變理論最終最大 HP；逐次取整與即時現有血量則是另一個問題。

來源：[Stats：Health scaling／Multipliers' Derivation][S1]。本輪數學重算核對了三軸第一點及三個平台值；沒有逐格實測 Dead Cells 的整數顯示。

### 3.4 Ashfall 現在的 HP 與 Scroll 預覽

當前資料：

```text
base_hp = 120
每張 Brutality 的 hp 係數 = 0.10
每張 Tactics 的 hp 係數 = 0.08
每張 Survival 的 hp 係數 = 0.14
起始 Ash Charm 的 hp = 12

RunBuild 的基礎最大 HP 部分：
120 * (1 + 0.10*nB) * (1 + 0.08*nT) * (1 + 0.14*nS)
    + 護符基礎HP * 護符power
```

這是正式 `Game.build != null` 路徑的 HP；該路徑會返回，不會再套用下方 legacy 玩家分支的裝甲／舊 Profile HP。下列起始例子的護符為 plain、無 power 詞綴，所以護符 HP 為 12。

- **目前已是三軸相乘**；差異在每軸使用 `1 + 係數*n`，而非 Dead Cells 的分軸二次曲線與平台。
- 其他兩軸與護符固定時，相同軸每張增加固定的絕對最大 HP；分母越來越大，所以下一點的相對 HP 百分比會自然遞減。
- 其他軸成長又會改變本軸每點增加的絕對 HP。例如先拿 B 再拿 T，最大 HP 為 `120*1.10*1.08+12 = 154.56`，不是把兩軸係數相加。
- Scroll UI 直接把資料中的係數顯示成 HP 百分比，沒有依目前整個 build 重算。
- 即使保留現在公式，**文字也可能不等於「相對目前最大 HP 實際增加多少」**。

只用起始護符，未投點時 `max_hp = 132`：

| 選第一張 | 新最大 HP | 實際增加 | 相對原 132 的增幅 | 資料／目前卡片使用的係數 |
|---|---:|---:|---:|---:|
| Brutality | 144 | 12 | +9.091% | 10% |
| Tactics | 141.6 | 9.6 | +7.273% | 8% |
| Survival | 148.8 | 16.8 | +12.727% | 14% |

如果只投同一軸、另外兩軸仍為 0，始終保留起始 +12 HP 護符，目前 Ashfall 的下一點 HP 實際收益也會變：

| 同軸已增加點數 n | Ashfall 下一點 B HP | Ashfall 下一點 T HP | Ashfall 下一點 S HP |
|---:|---:|---:|---:|
| 0 | +9.091% | +7.273% | +12.727% |
| 1 | +8.333% | +6.780% | +11.290% |
| 2 | +7.692% | +6.349% | +10.145% |
| 5 | +6.250% | +5.333% | +7.778% |
| 10 | +4.762% | +4.211% | +5.600% |
| 20 | +3.226% | +2.963% | +3.590% |

因此準確說法是：**目前已經有依點數改變的 HP 相對收益，畫面沒有把它算出來；成長曲線也不是 Dead Cells 那一條。** 同樣地，卡片固定寫 `MATCHING DAMAGE +12%`，但表 §3.2 顯示第二點起相對目前傷害已不是 +12%。最終單次傷害還會由 `Damage.compute()` 取整且至少為 1，倍率表不是每次命中的精確整數結果。

**判斷：這同時涉及 MECH-01 和 UI-01。** 應先選定公式，再用「選前 build → 選後 build」的同一套結算產生預覽；不要在 UI 另寫一套固定數字。

## 4. 最大 HP、現有 HP 與血條

### 4.1 使用者要求的比例不變

令：

```text
old_max = 變更前最大 HP
old_hp  = 變更前現有 HP
ratio   = old_hp / old_max
new_max = 變更後最大 HP
new_hp  = ratio * new_max
```

當變更來源是 Scroll、護符、被動或其他「變更最大 HP 的 build 操作」時，這條規則能使：

| 變更前 | 新最大 HP | 保留比例後 | 當前只 clamp 的結果 |
|---|---:|---|---|
| 100 / 100，100% | 150 | 150 / 150，100% | 100 / 150，66.7% |
| 50 / 100，50% | 150 | 75 / 150，50% | 50 / 150，33.3% |
| 50 / 100，50% | 80 | 40 / 80，50% | 50 / 80，62.5% |

這也能避免反覆換高／低 HP 裝備、靠只保留絕對血量而改變百分比的問題。

Ashfall 現在的呼叫鏈：

```text
RunLoot.claim()
→ 改 attributes 或 equip
→ Game.player._apply_loadout()
→ 重算 max_hp
→ hp = minf(hp, max_hp)
```

Scroll、裝備替換與會重套 build 的服務應共同審查；只修 Scroll 的單一路徑會漏掉其他來源。

**邊界必須另外定義：** 新 run 初始滿血、讀取存檔恢復既有 HP、Fountain 明確補滿、治療增加現有 HP、死亡狀態。這些不應因共用 `_apply_loadout()` 而被當成一般裝備變更。零最大 HP／無效存檔應由既有邊界驗證處理。

**證據標記：** 這一節是使用者要求的 Ashfall 不變量與實作差距。Dead Cells 所有加 HP 來源的精確整數補償／特殊例外，本輪沒有取得完整一手規格，不聲稱已全部驗證。

### 4.2 可直接重算的 Ashfall 例子

只取起始裝備，不含額外修正：

```text
開始：hp = 132，max_hp = 132
選 Tactics：max_hp = 120 * 1.08 + 12 = 141.6
現在：hp 仍是 132
比例：100% → 約 93.2203%

如果開始為 66 / 132，也就是 50%：
現在變成 66 / 141.6，約 46.6102%
按使用者要求則應為 70.8 / 141.6，仍為 50%
```

**MECH-02：已確認現碼不滿足比例不變。** 尚未修改。

### 4.3 HP 數字錯誤

[HUD](../../scripts/ui/hud.gd) 的目前格式：

```text
ceil(player.hp) / int(player.max_hp)
```

`max_hp` 是浮點數，而這兩種取整方式不一致：

```text
實際：141.6 / 141.6
畫面：142 / 141
```

這不是 Dead Cells 平衡選擇，也不是玩家誤解；是 Ashfall 自己的顯示一致性錯誤。

後續至少應保證：

- 可見現有 HP 不會大於可見最大 HP。
- 真實滿血時，文字與血條都表示滿血。
- 真實缺血時，主血條不把剩餘比例畫成完全滿血。
- 顯示採整數或小數可以自主選擇，但同一個 HP 狀態必須使用一致規則。
- 浮點 gameplay 狀態與顯示取整應分離；不能為修 UI 把角色 transform 或物理改成整數。

### 4.4 分段血條錯誤

目前大意：

```text
segments = round(max_hp / 20)
lit = ceil(hp / max_hp * segments)
```

`141.6 / 20` 會畫成 7 格。當 HP 比例是 90% 時：

```text
ceil(0.90 * 7) = 7
```

仍全亮。這種量化能提示「尚存一點生命」，但不能精確表示剩餘 HP。後續可保留 MathArt 分段外觀，讓最後一格按剩餘比例填充，或另用連續比例表達；具體視覺仍待 UI 工作與真人覆驗。

**UI-02：數字取整和血條量化是兩個獨立子問題。** 本輪公式自查已重現，不等於已在當前遊戲畫面錄到該狀態。

## 5. 裝備、傷害與 build

### 5.1 裝備槽與屬性

| 機制 | Dead Cells | Ashfall 現況 | 判斷 |
|---|---|---|---|
| 基礎持有 | 兩武器槽、兩技能槽、護符；盾佔武器槽 | 已有同樣五槽結構，1／2、Q／E | 決策骨架已有 |
| 雙手武器 | 特定物品同時佔兩武器槽 | 目前未見雙手裝備契約 | 內容擴充項 |
| Backpack | 永久解鎖後可帶備用武器；一般不能直接從包內使用，相關 Mutation 有特例 | 未實作 | 目前小型內容不必優先補 |
| 單屬性裝備 | 只使用自身的 scaling 屬性 | 每件物品單一 `attribute` | 基礎已有 |
| 雙屬性裝備 | **取兩軸較高者**，不相加 | 未支援 | 若加入，UI 必須顯示當前實際使用哪軸 |
| 無色裝備 | 使用三軸最高者 | 未支援 | 不能以普通品質倍率冒充無色 |
| 現行 Legendary | 使用最高軸，帶物品專屬 Legendary affix；有自己的品質優勢 | 只有 plain／etched | 缺特殊裝備決策；不要使用舊版「最高兩軸相加」規則 |
| 護符 | 可帶屬性點及其他修正；屬性點反映在相關成長上 | 起始 Ash Charm 主要提供固定 +12 HP | 現有護符決策簡化 |

來源：[Gear][S2]、[Stats][S1]、[Mechanics：Two-handed weapons／Backpack][S3]。

### 5.2 Gear level 與 quality 是不同軸

Dead Cells：

- 羅馬數字為 **gear level**，與 biome、來源、難度等有關。
- 品質 `+`／`++`／`S`／`L` 是另一軸，會增加有效 gear power。
- 典型品質對 gear power：普通 +0、`+` +2、`++` +4、`S`／`L` +6。
- 例如 Wiki 的 **IV++**：level 4 加品質 +4，gear power 8，對應公開表的 +129% 傷害與 3 個 affix slots。
- gear power 與 affix 數量也有關，不能把品質理解成只加一個固定百分比。

Ashfall：

```text
plain.power = 1.0
etched.power = 1.15
```

目前沒有正式 gear level／gear power 軸，品質主要是倍率。`keen` 又加 power、`quick` 改 cooldown、`venom` 加 poison。

**差異：** 後期裝備變強的維度較少，換裝容易成為「同一招數字略大」。這不是單純把 `etched` 改名為 `S` 就能解決；若加入等級，來源、UI、價值、回收、Forge、存檔驗證都要一起定義。

來源：[Gear][S2]。

### 5.3 當前 Ashfall 的品質、詞綴與價格精確關係

```text
power = quality.power + affix.power
price = ceil(item.base_price * quality.price)
recycle = floor(price * 0.35)
技能 cooldown = base_cooldown * affix.cooldown * (1 + Mutation cooldown修正)
```

例如 etched + keen 的 power 是 `1.15 + 0.10 = 1.25`；不是 `1.15 * 1.10 = 1.265`。當前價格公式沒有計入 affix，換詞綴本身不改變 `price()`；這與 Dead Cells 的 affix cost impact 不同。

目前重鑄按設定 affix 陣列依序輪換，並隨該物品重鑄次數加價，不是完整隨機詞綴池。這個結果是否保留可以另定，但服務介面應如實說明。

### 5.4 暴擊、DPS 與特效

| 機制 | Dead Cells | Ashfall 現況／需注意 |
|---|---|---|
| 暴擊觸發 | 很多武器依位置、狀態、連段或目標條件必定暴擊，不是統一的隨機爆擊率 | 有背刺、暴露、perfect-dodge／EDGE 等條件；與原創武器內容相關，不能一律視為缺少 |
| 暴擊數值 | 每件武器的普攻／暴擊基礎值與條件可不同 | 需要顯示該武器的實際條件，不能只寫「暴擊更強」 |
| DPS | 攻擊傷害與完整動畫／連段時間共同決定；另受命中條件與狀態影響 | `describe()` 的 `HIT` 對近戰只取 combo 第一擊、非暴擊值，沒有用完整連段時間算 DPS；不能把它當完整戰鬥收益 |
| 技能 | 不只有傷害，還有冷卻、持續、部署、控制、彈藥等 | 現有 Kunai／Aegis 有 charges／cooldown 等；比較卡需要顯示與操作相關的部分 |
| 换装 | 高面板值不必然比較好，可能損失暴擊條件或詞綴連動 | 目前候選與現裝缺少清楚的逐項差異；屬 UI-01 核心 |

來源：[Gear][S2]、[Weapons][S4]、[Skills][S5]、[Shields][S6]。本輪不逐件搬寫對方武器招式與數值表。

### 5.5 詞綴與狀態連動

Dead Cells 的 affix 有適用類型、必要 tag、排斥 tag、互斥 affix 等限制；不是每件物品都能抽到每個效果。常見決策包含「施加某狀態」與「對該狀態目標增傷」的跨槽配合。

| 狀態／機制 | Dead Cells 公開規則 | Ashfall 現況 |
|---|---|---|
| Poison | 持續傷害，可多層，沒有一般堆疊層數上限；被毒敵人死亡可傳播毒 | 目前單一計時／tick 方案；未形成同樣的多層與傳播系統 |
| Bleed | 可堆疊；到 **5 層**時把剩餘應造成傷害一次爆出 | 無同類完整系統 |
| Freeze | 控制目標；再受傷可解凍，解凍後有減速；火與既有 DoT 有特定互動 | 無同類完整系統 |
| Root／stun | 有不同的移動／行動限制，不能統一當成同一個停止計時器 | 目前主要靠原創戰鬥狀態與暴露等判定 |
| Oil + fire | 可形成額外燃燒連動；環境水體也會影響部分狀態 | 未實作此類完整元素／環境關係 |
| 對狀態目標增傷 | affix 能讓別槽施加狀態成為輸出條件 | 當前 affix 僅 none／keen／quick／venom，組合有限 |

Ashfall 毒資料為 `damage=3`、`interval=0.5`、`duration=2.0`。需要另審視持續傷害是否使用與施加來源相符的裝備／屬性倍率；不能把固定 tick 文字當成完整實際 DPS。

**判斷：** 差異會影響 build 深度，但不應在修 HP 顯示時順手擴建整個狀態系統。

來源：[Affixes][S7]、[Status effects][S8]。

## 6. 生存、治療與戰鬥機制

| 項目 | Dead Cells 公開規則 | Ashfall 當前差異／確認點 |
|---|---|---|
| Recovery／Rally | 受傷後約 **80%** 本次失血成為短暫可追回區；基本延遲約 **0.08 秒**，之後每秒按最大 HP 的 **30%** 消退 | 未見可追回 HP 池／倒數；現有 heal 與受傷直接減血不能等同 Recovery |
| Recovery 回復量 | 普通規則下傷害可轉回 **12%** 的回血，每次命中另有本次原始失血 **20%** 上限；技能一般不觸發，特定版本有例外 | 尚無此系統；若做，必須區分武器、技能、DoT 與來源，不能直接所有 damage 都回血 |
| One-hit protection | HP **高於 25%** 時吃到致命一擊，通常留 **1 HP**；基礎冷卻 **45 秒**，喝藥或補滿可重置 | `take_hit()` 目前直接扣至 0 後死亡，未見這個保護判定 |
| Flask | 普通用藥回 **60% 最大 HP**，回復效果在約 **1 秒**內完成；Wiki 另列動作 duration **0.67 秒**、lock **0.5 秒**，不能把回復時間當動作鎖定；常規最多 4 次，Mutation／特殊模式可改變 | 現有 flask 有容量／次數、使用階段與治療數值，原創數字需另做手感驗收，不因不同就當 bug |
| Food | 常規小／大食物約 **15%／50% 最大 HP**；稀有／特殊食物另有例外 | 現在單一 food，`food_heal=0.25`，即 25% 最大 HP |
| Shield block | 主動舉盾減免依盾而異；不等同成功 parry | 現有 Fold Shield 主要是限時、正面反擊契約，未形成完整持盾減傷層 |
| Parry | 點按嘗試 parry；持續舉盾約 **0.37 秒**後轉入 block。空揮後約 **0.6 秒**不能再次 block／parry；成功則免除該次可反擊傷害並可立即再用。Wiki 另註持續按盾最初 **0.2 秒**仍可自動 parry，不能將這些時間合成一個通用窗 | 有正面 `guard_t` 判定與 counter；窗長、方向、投射物等為原創實作，應讓玩家能辨識 |
| Roll | 滾動約 **0.4 秒**；再啟動有約 **0.37 秒**冷卻。能躲多種攻擊，但地面尖刺、部分爆炸／地波等不能靠滾避開 | 有獨立 roll iframe timer、空中 roll、完美閃避；精確可避傷害類型仍應寫成規則，不應推論「翻滾時一切無敵」 |
| Combo 與 roll | roll 不會直接重置武器連段 | 現有取消／連段屬原創手感；需針對實際武器驗證，不能僅用相同秒數宣稱對齊 |
| Breach／stagger | 命中有獨立防禦崩解／打斷累積，受招式抗性與敵人 tier 影響 | 已有暴露、受擊狀態與特定 Boss guard，但不等於完整 breach 系統 |
| 受傷後短暫保護 | 與 roll、盾、OHP 等是不同來源的保護 | 現碼分開判 roll、invuln、guard、aegis，再扣血；這個分工可沿用，但玩家提示仍要可讀 |

來源：[Mechanics][S3]、[Health Flask][S9]、[Pickups][S10]、[Shields][S6]。

以上秒數為來源列出的常規值，不能把動作持續、無敵有效窗、動作結束後可再輸入時間混成同一個參數。Ashfall 有不同移動尺度與動畫語言，應對齊可預期的操作規則，再自己調整原創數值。

## 7. 商店、掉落、回收與寶箱

### 7.1 商店與經濟

| 項目 | Dead Cells | Ashfall 現況 | 差異／待辦 |
|---|---|---|---|
| 商店庫存 | 一般有 **三件**候選，能直接觀察商品與價格；食物商店另有角色 | 目前 `shop` placement 產生單件 offer | 缺少同一間商店內的橫向比較 |
| Shop Categories | 永久解鎖後按屬性類別選庫存 | 未實作 | 後續擴充，不影響現在先把單件交易講清楚 |
| Restock | 永久解鎖後最多刷新 **5 次**；現行 Wiki 列為刷新本身免費，但每次讓庫存商品價格增加原價的 **40%** | 未實作 | 不要沿用舊版「先付刷新費」的說法；不是當前 UI 問題的必要前置 |
| 金幣價格 | 受物品基價、gear level、quality、affix 影響 | 有物品基價、品質價格倍率等；維度較少 | 比較卡至少應顯示本次支付、現有金幣、餘額 |
| 回收 | 永久解鎖 Recycling；I／II 一般為物品價值約 **7%／15%** | 直接使用 `recycle_fraction=0.35` | 35% 是 Ashfall 原創值，不是 Dead Cells 的公開規則 |
| 未裝備物品 | 可決定保留、替換、丟棄／回收 | 裝上新物品時舊物品自動回收並 retire；不能保留地上等稍後換回 | 這是一項會影響選擇後果的規則差異，UI 必須提前告知 |
| 未買商品回收 | 不能把商店庫存當自己的物品回收換錢 | 現有 `cost > 0` 時拒絕 recycle | 這個邊界已有 |
| 交易提交 | 金幣不足不能取得物品；物品不能重領 | RunLoot 有 available／owner_build／consumed／gold 檢查 | 功能邊界已有，但不代表交易介面易懂 |

來源：[Shop][S11]、[Gear：Gear value／Recycling prices][S2]、[Runes and upgrades][S12]。

### 7.2 箱子與特殊獎勵

| 類型 | Dead Cells | Ashfall 現況 |
|---|---|---|
| 一般寶箱 | 隨機裝備等獎勵，可有特殊事件；需要先區分「開箱」與「決定如何處理掉落」 | 現有 `chest` 主要是另一種免費 gear offer，使用同一 BuildScreen；不構成獨立的開箱資訊流程 |
| 詛咒寶箱 | 高收益、附 curse；常規詛咒需殺 **10** 名合格敵人清除，詛咒中受傷可致死；特殊效果／Mutation 另有例外 | 未實作 curse，也未做相應風險收益 UI |
| 詛咒箱收益 | 典型包含 Scroll、無色裝備與金幣等，和一般箱不同 | 沒有對應特殊箱型 |
| Legendary altar | 特殊裝備祭壇，通常要先處理其附近守衛／保護範圍 | 未實作 |
| Challenge Rift | 找到隱藏入口，開獎勵後要完成陷阱路線；獎勵含 Scroll／護符等 | 目前 Passage challenge 是條件達成後領款；不是這種平台陷阱挑戰 |
| 隱藏食物／金幣 | 牆面／地面秘密、星號敵人、支路等鼓勵探索 | 現有地圖分支、金幣／food／gear 擺放；秘密與事件種類仍少 |

來源：[Chests][S13]、[Cursed chest][S14]、[Mechanics：Curse][S3]、[Gear][S2]、[Challenge Rifts][S15]。

**UI-01 的重點：** 「Shop」「Chest」「Gear」是來源／情境，不是足以讓玩家決定的說明。玩家需要先知道物品能做什麼、將替換什麼、要付多少、舊物品如何處理，再確認結果。

## 8. Mutation、Cells、藍圖與 Forge

| 機制 | Dead Cells 公開結構 | Ashfall 現況 | 判斷 |
|---|---|---|---|
| Mutation 槽 | 常規上限 **3**；通常在 Passage 逐步選取 | 已有三槽與 Passage 選擇 | 決策骨架已有 |
| Mutation 成長 | 部分隨指定屬性成長，且可能有各自上限；部分無色／通用，不隨軸成長 | 現有 Mutation 主要是資料定義的固定 modifier | 不能把所有 Mutation 都當常數，或都套同一條傷害公式 |
| Mutation 重置 | 花金幣重選，重置有成本／遞增規則 | 已有 reset，採 Ashfall 自定費用 | 結構已有，價格不需照搬 |
| 藍圖取得 | 取得並帶至 Collector 交付；只拿到而未交付就死亡，通常無法保留 | 已有 carried_blueprints 與 Collector 交付 | 需讓玩家分辨「已拾到」和「已永久交付」 |
| Cells | run 中攜帶，死亡丟失未花部分；投入已解鎖項的進度可保留 | 已有 run／Profile 分工與原子提交 | 結構已有；顯示要清楚哪部分已落袋 |
| Collector | Cells 解鎖武器／技能／Mutation／通用升級；有部分投資 | 已有藍圖成本與部分投資 | 內容量仍小，不能宣稱等量內容 |
| Legendary Forge | Boss 後用 **Cells** 永久提高未來掉落的 `+`／`++`／`S` 品質機率 | 現有永久 Forge 主要是 etched 進程 | 結構簡化；不等於立即把手上全部裝備升級 |
| Minor Forge | 用 **金幣**處理本輪指定物品的品質／affix | 已有升級／reforge 服務 | UI 要與永久 Forge 分開說明，否則容易混淆 |
| 改品質與洗詞綴 | 是不同操作；現行版本提升品質不一定重新洗 affix | 當前服務規則需逐項明示 | 不能寫成一個含糊的「強化」按鈕 |
| Rune | 永久能力解鎖，後續 run 可開新路線 | 已有 canopy／phase 等與實體 gate，部分更完整內容在後續階段 | 有對應結構，仍要用合法來源／下一輪驗收 |

來源：[Mutations][S16]、[The Collector][S17]、[The Blacksmith][S18]、[The Blacksmith's Apprentice][S19]、[Runes and upgrades][S12]。

部分「永久解鎖」改變的是物品出現池、使用機會或品質分布，不是無限永久疊高角色攻防。Ashfall 舊 Profile 的歷史 bonus 與新循環相容已有遷移規則；本輪沒有清除或重新解釋玩家舊資料。

## 9. 難度、補給、路線與挑戰獎勵

| 項目 | Dead Cells 公開規則／方法 | Ashfall 現況 | 差異／注意 |
|---|---|---|---|
| 世界骨架 | 固定 biome 連接與解鎖條件，每輪沿可用分支前進；不是任意拼成一張完全無規則世界圖 | 資料化 route graph、實體出口、鑰匙／Rune、三 Boss 主路 | 骨架已有，當前可玩內容仍是有界子集 |
| Biome 內生成 | 手作房間／模組，依用途、入口出口與 biome graph 組裝 | BiomeGen／room modules／role／socket | 方法已有，密度與房型變化仍需人類體驗判定 |
| Scroll 配額 | 路線、biome 與難度影響可取得點數；高難度還有 fragments、特殊來源 | 現有 placement／profile 報酬比較固定、Scroll 類型少 | 要調成長曲線，必須同時知道整輪可得多少點 |
| 敵人強度 | 依 biome／tier／BSC 等；**現行規則不應沿用早期「撿 Scroll 就把普通敵人一起加強」的說法** | 正式 `level.gd` 配置敵人時傳 `hp_scale=1.0`，敵人／profile 用原創內容；legacy encounter 另有波次倍率 | 不要把 legacy fixture 的波次成長當正式 route 的 Scroll scaling |
| 0 BSC Fountain | 適用 Passage 的 Fountain 會補滿 HP 與 flask | 已有 0 BSC、每 Passage 一次的完整補給 | 結構符合首通目標 |
| 高 BSC 補給 | 1 BSC 起補給逐步限制；2 BSC 沒有完整 Fountain、但可有單次補充；4／5 BSC 常規 Fountain／單次補充更受限／消失 | 固定 0 BSC；解鎖 BSC1 並不代表已能玩 BSC1 | 留待既定後期難度工作，不冒充已完成 |
| BSC 成長 | Boss Cell 不是只有敵人 HP 倍率；敵池、行為、密度、補給、門與後期機制也變化 | 尚未做可玩的高 BSC | 不是本輪 HP 修正的附帶範圍 |
| Malaise | 現行主要為 **5 BSC** 的額外壓力系統 | 未做 | 不屬 0 BSC 缺陷 |
| 時間門 | 適用 Passage 達時限才可開；各段有不同累計時間；預設部分安全區／商店等不計時 | 目前按 `node_time` 與資料門檻算本節點速度挑戰 | 「單節點限時」和「整輪累計到指定段落」是不同規則 |
| 無傷連殺門 | 多數段落為 **60** 連殺，首區典型 **30**；達過門檻後再受傷，仍保留該門資格 | 已有 kill_streak／best_kill_streak 與領取契約，門檻為原創資料 | 要確保使用歷史最佳而非只看當下 streak；具體獎勵仍簡化 |
| Boss 無傷門 | Boss 段落全程無傷，通常獎勵一件 Legendary，另有金幣／Cells | 有 flawless 條件與領款，沒有完整 Legendary 報酬層 | 條件結構有，回報內容不同 |
| 挑戰回報 | 時間／連殺門常有三選一裝備祭壇及資源 | 目前主要簡化為資源條件獎勵 | 少了與換裝連動的選擇 |
| 死亡 | 結束該 run；未提交資源與局內 build 失去，已永久投入的進度保留 | 已有死亡／勝利結算與持久化邊界 | 需要以 UI 清楚交代保留／失去內容 |
| 繼續遊戲 | 保存進行中 run，不是死亡後保留局內 build；精確世界快照頻率依遊戲實作 | Ashfall 保存 biome 入口／Passage；區域內未提交進度重來，非任意幀世界快照 | 既有刻意範圍，要讓玩家事先知道；本輪未改 |

來源：[Biomes][S20]、[Boss Stem Cell][S21]、[Time, killstreak and no-hit doors][S22]、[Malaise][S23]、[開發者 Update 1.1 patch notes][S24]、[原 lead designer 的地圖生成文章][S25]。

高難度的逐區 fragment 數、個別 DLC 路線、全部敵人／Boss 招式、每件武器表與各版本存檔觸發點，未在本輪逐一實機驗證；它們不應混入已確認的 0 BSC 問題。

## 10. 這次 UI 問題具體要記住什麼

以下是後續介面必須讓玩家回答的問題，**不是本輪已完成的設計稿**。

| 畫面 | 玩家現在看不懂的決策 | 後續必須明確的資訊 |
|---|---|---|
| Scroll | 選哪一軸？現在到底增多少？哪些裝備受益？ | 三軸目前點數、選後點數、實際 HP 前後、受益槽、主屬性傷害前後；選擇與確認要分明 |
| Gear 拾取 | 是武器、技能還是護符？可以放哪？換了損失什麼？ | 物品用途、招式／觸發條件、合法替換槽、現裝與候選的實際差異、冷卻／充能、舊物品去向 |
| Shop | 是否買得起？按確認會扣什麼？舊裝備會不會消失？ | 商品、價格、現有金幣、交易後餘額、替換後結果；買不起狀態及原因；不應只顯示內部 kind |
| Chest | 是開箱、挑戰還是裝備比較？拿走後能不能返回？ | 來源／風險、已開或未開、實際掉落、拿取／替換／回收的分步結果 |
| HP | 目前到底剩幾成？加血為何變缺血？ | 數字與條形同一比例；HP 上限成長與實際回血分清楚；滿血不能顯示大於上限 |
| Passage 服務 | 花的是 Gold 還是 Cells？改本輪還是永久？ | 資源名稱、這次成本、立即結果、持續範圍；Collector／兩種 Forge 不可混淆 |

共通要求：

- 全部可用鍵盤完成，焦點／選項／確認／取消清楚可見。
- 玩家看到的是用途與後果，而非 `kind`、`power x1.288` 等內部資料。
- 小型主 HUD 保持必要資訊；深入比較可放拾取／暫停／服務介面。
- 維持 Ashfall 的 MathArt、灰階、原創幾何；用明暗、形狀與標籤表達三軸與選取狀態，不引入彩色或對方素材。
- 自動檢查只能證明文字邊界、焦點與交易；**看不看得懂仍須請使用者實際覆驗**。

## 11. 建議問題順序與狀態

優先級表示建議後續處理順序，不代表本輪已獲指示實作所有系統。

| 編號 | 問題 | 類別 | 建議順序 | 本輪狀態 |
|---|---|---|---|---|
| UI-02a | HP 分子／分母取整不一致，可能 current > max | 明確顯示錯誤 | P1 | 現碼與數學重現已確認，未修 |
| UI-02b | 缺血時分段條仍全滿 | 明確可讀性問題 | P1 | 現碼與數學重現已確認，未修 |
| MECH-02 | build 改最大 HP 不保留比例 | 不符合使用者要求 | P1 | 呼叫鏈已確認，未修 |
| UI-01 | Shop／Gear／Scroll／Chest 無法理解 | 真人可讀性問題 | P1 | 已記入長期記憶與驗收清單，待設計／實作／真人覆驗 |
| MECH-01a | Scroll 顯示係數不等於目前 build 實際增幅 | 預覽與結算差異 | P1 | 已計算起始護符例，未修 |
| MECH-01b | 傷害線性成長，非固定相對收益 | 規則／平衡決策 | P2 | 已列數學比較；需與整輪點數、敵人 HP 一起定案 |
| MECH-01c | HP 每軸線性倍率再相乘，與公開二次曲線／平台不同 | 規則／平衡決策 | P2 | 現有相對收益也會遞減；已列兩者曲線，未選 Ashfall 新數值 |
| BUILD-01 | 缺雙屬性 Scroll 與雙屬性／無色裝備 | build 決策深度 | P2 | 差距已列，未實作 |
| BUILD-02 | gear level、品質、affix 維度較少 | 內容／經濟設計 | P2 | 差距已列，未實作 |
| BUILD-03 | Mutation 與狀態連動較少 | build 決策深度 | P2 | 差距已列，未實作 |
| ECON-01 | 單件商店、舊裝備自動回收、箱子情境簡化 | 規則與 UI | P2 | 行為已確認，需決定是否保留並清楚告知 |
| COMBAT-01 | 缺 Recovery／OHP 等生存層 | 戰鬥設計 | P2 | 呼叫路徑未見實作；不作為 HP 顯示 bug 的附帶改動 |
| ROUTE-01 | 時間門計時範圍與挑戰回報不同 | 路線風險收益 | P2 | 規則差異已列 |
| LATER-01 | 高 BSC／fragment／Malaise／完整 DLC 等 | 已知後期範圍 | 依 GOALS 的 A/B/C 授權 | 不列入當前 0 BSC 修錯完成條件 |

## 12. 後續真正修正時的驗收案例

這是建議驗收矩陣，**本輪沒有執行這些遊戲內新案例，也沒有把它們標成通過**。

| 測項 | 需要成立的結果 |
|---|---|
| 滿血拿三軸 Scroll | 每種操作後仍滿血；數字不超上限，血條不表示缺血 |
| 半血拿 Scroll | current／max 比例在浮點容差內保持；預覽與實際一致 |
| 低血／小數 HP | 不會顯示 0 HP 卻存活、滿血 current > max，或缺血仍畫滿主條 |
| 換高 HP 護符再換回 | 比例符合選定規則，不可反覆換裝憑空回血 |
| Mutation 改 HP／重置 | 與 Scroll／護符使用一致的最大 HP 變更規則 |
| 無 HP 影響的換裝／洗詞綴 | 現有 HP 不漂移，不重複套加成 |
| 同軸第 1／5／10／20 點 | damage、max HP、卡片預覽與同一個最終公式一致 |
| 雙屬性／無色（若加入） | 取合法最高軸，切軸後即時更新；不把兩軸相加 |
| Shop 買不起／取消 | 不扣款、不 retire 現裝、不消耗商品，焦點與原因清楚 |
| Shop／Gear 確認替換 | 清楚說明金額、目標槽、舊裝去向；只能提交一次 |
| Chest 開箱與挑選 | 玩家知道已開箱、拿到什麼、尚未提交什麼；離開後行為符合規則 |
| Passage 補給與讀檔 | Fountain 明確補滿；讀檔恢復已保存 HP，不再次比例換算或多回血 |
| Scroll 後保存再續玩 | 已存屬性與 HP 一致，不因 `_apply_loadout()` 重套而二次增長 |
| 死亡／新 run／跨槽 | 局內增益按既有契約清除，各存檔不串資料 |
| 真人只用鍵盤 | 使用者能說出「為何選它、付出什麼、變強哪裡」，再算 UI-01 覆驗 |

## 13. 本輪完成與未完成

完成：公開資料網搜及頁面讀取；核對目前資料、屬性／裝備／拾取／HUD／服務的呼叫路徑；重算傷害曲線、三軸 HP 函式第一點與平台值；用當前起始裝備公式推導 HP 比例及兩項顯示問題；記下真人 UI 問題與後續驗收。

未做：修改遊戲程式、選定 Ashfall 的新平衡值、重設介面、操作 Dead Cells 實機逐幀比對、重跑 Godot 完整測試、替使用者填真人通過。無新增玩法變更，因此既有 Full／Fast 不在本輪重跑。

設計理由：選擇先把資料來源、現碼行為與使用者要求分開列明，因為這能先判斷是明確錯誤還是需要選擇的玩法規則。
放棄在報告階段直接套用 Dead Cells 全套數字或同時擴建所有系統，因為這會改變 Ashfall 整輪平衡，也超出本輪「先看詳細比較」的要求。

## 14. 來源索引

以下均在本輪網搜／讀取，精確版本差異與公開資料空白見 §2。

| 編號 | 來源 | 本報告用途 |
|---|---|---|
| S1 | [Stats](https://deadcells.wiki.gg/wiki/Stats) | 起始三軸、15% 傷害、HP 三條函式、雙屬性／無色、fragments |
| S2 | [Gear](https://deadcells.wiki.gg/wiki/Gear) | 等級／品質／gear power、護符、Legendary、價格、回收 |
| S3 | [Mechanics](https://deadcells.wiki.gg/wiki/Mechanics) | Recovery、OHP、roll、breach、curse、backpack、環境互動 |
| S4 | [Weapons](https://deadcells.wiki.gg/wiki/Weapons) | 武器種類與條件式輸出 |
| S5 | [Skills](https://deadcells.wiki.gg/wiki/Skills) | 技能、部署、冷卻等決策 |
| S6 | [Shields](https://deadcells.wiki.gg/wiki/Shields) | block／parry 區分與常規時窗 |
| S7 | [Affixes](https://deadcells.wiki.gg/wiki/Affixes) | 詞綴生成限制、增傷條件、護符屬性 |
| S8 | [Status effects](https://deadcells.wiki.gg/wiki/Status_effects) | poison、bleed、freeze、oil／fire 等 |
| S9 | [Health Flask](https://deadcells.wiki.gg/wiki/Health_Flask) | 喝藥回復量、耗時、容量 |
| S10 | [Pickups](https://deadcells.wiki.gg/wiki/Pickups) | food 與資源 |
| S11 | [Shop](https://deadcells.wiki.gg/wiki/Shop) | 三件商品、分類、refresh、食物商店 |
| S12 | [Runes and upgrades](https://deadcells.wiki.gg/wiki/Runes_and_upgrades) | 永久能力、Recycling、商店升級 |
| S13 | [Chests](https://deadcells.wiki.gg/wiki/Chests) | 一般箱子與特殊事件 |
| S14 | [Cursed chest](https://deadcells.wiki.gg/wiki/Cursed_chest) | curse 箱的收益／風險 |
| S15 | [Challenge Rifts](https://deadcells.wiki.gg/wiki/Challenge_Rifts) | 可選陷阱區與開箱後逃離契約 |
| S16 | [Mutations](https://deadcells.wiki.gg/wiki/Mutations) | 三槽、屬性成長、重置 |
| S17 | [The Collector](https://deadcells.wiki.gg/wiki/The_Collector) | 藍圖、Cells、永久解鎖 |
| S18 | [The Blacksmith](https://deadcells.wiki.gg/wiki/The_Blacksmith) | 永久品質機率 Forge |
| S19 | [The Blacksmith's Apprentice](https://deadcells.wiki.gg/wiki/The_Blacksmith%27s_Apprentice) | 局內金幣升級／reforge |
| S20 | [Biomes](https://deadcells.wiki.gg/wiki/Biomes) | 區域與 tier／路線結構 |
| S21 | [Boss Stem Cell](https://deadcells.wiki.gg/wiki/Boss_Stem_Cell) | 難度與補給改變 |
| S22 | [Time, killstreak and no-hit doors](https://deadcells.wiki.gg/wiki/Timed_door) | 累計限時、30／60 streak、Boss 無傷獎勵 |
| S23 | [Malaise](https://deadcells.wiki.gg/wiki/Malaise) | 5 BSC 機制範圍 |
| S24 | [官方 Update 1.1 patch notes](https://deadcells.com/patchnotes/11) | 排除早期 Scroll 直接帶動敵人 scaling 的過時說法 |
| S25 | [The level design of Dead Cells: a hybrid approach](https://deepnight.net/tutorial/the-level-design-of-dead-cells-a-hybrid-approach/) | 公開地圖生成方法 |
| S26 | [官方 Update 5 patch notes](https://deadcells.com/patchnotes/5) | 2017 舊規則與當時 Scroll HP 百分比顯示修正；**不是現行數值依據** |

補充交叉參考：[Scrolls, Gear and Scaling Reference](https://teemo.dev/game-design/dead-cells/systems/scrolls-gear-and-scaling-reference/)。這是第三方整理，不高於 Wiki／開發者原始說明；其表格衝突提示用來辨識公開資料不一致，不當作實機驗證。

[S1]: https://deadcells.wiki.gg/wiki/Stats
[S2]: https://deadcells.wiki.gg/wiki/Gear
[S3]: https://deadcells.wiki.gg/wiki/Mechanics
[S4]: https://deadcells.wiki.gg/wiki/Weapons
[S5]: https://deadcells.wiki.gg/wiki/Skills
[S6]: https://deadcells.wiki.gg/wiki/Shields
[S7]: https://deadcells.wiki.gg/wiki/Affixes
[S8]: https://deadcells.wiki.gg/wiki/Status_effects
[S9]: https://deadcells.wiki.gg/wiki/Health_Flask
[S10]: https://deadcells.wiki.gg/wiki/Pickups
[S11]: https://deadcells.wiki.gg/wiki/Shop
[S12]: https://deadcells.wiki.gg/wiki/Runes_and_upgrades
[S13]: https://deadcells.wiki.gg/wiki/Chests
[S14]: https://deadcells.wiki.gg/wiki/Cursed_chest
[S15]: https://deadcells.wiki.gg/wiki/Challenge_Rifts
[S16]: https://deadcells.wiki.gg/wiki/Mutations
[S17]: https://deadcells.wiki.gg/wiki/The_Collector
[S18]: https://deadcells.wiki.gg/wiki/The_Blacksmith
[S19]: https://deadcells.wiki.gg/wiki/The_Blacksmith%27s_Apprentice
[S20]: https://deadcells.wiki.gg/wiki/Biomes
[S21]: https://deadcells.wiki.gg/wiki/Boss_Stem_Cell
[S22]: https://deadcells.wiki.gg/wiki/Timed_door
[S23]: https://deadcells.wiki.gg/wiki/Malaise
[S24]: https://deadcells.com/patchnotes/11
[S25]: https://deepnight.net/tutorial/the-level-design-of-dead-cells-a-hybrid-approach/
[S26]: https://deadcells.com/patchnotes/5
