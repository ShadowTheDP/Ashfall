# 數學即美術（Math as Art）— 多色 · 流暢優先版

這個專案的視覺**沒有貼圖、沒有精靈圖、沒有外部美術資產**。
所有形狀由 `_draw()` 與參數化曲線繪製；角色與相機保留浮點座標，**不做整數像素吸附**。
`scripts/systems/math_art.gd` 是唯一的視覺語言定義，所有場景都呼叫它。

唯一例外是文字字型：`assets/fonts/NotoSansCJKtc-Regular.otf`（Noto Sans CJK TC Regular，固定 commit `165c01b46ea533872e002e0785ff17e44f6d97d8`，SHA-256 `dce08bd4fd91aa8aa76ed8fea4b694c2dfb8550f67871e326843212ddbeb88b4`，SIL OFL 1.1）只負責把字畫清楚，不是美術資產；幾何、圖示、角色與 FX 仍全部由 MathArt 產生。`MathArt.ui_font()` 是唯一載入點，缺檔要 `push_error`，不得用系統字型冒充已交付的 CJK 字型。授權全文與字型內建著作權聲明見 `assets/fonts/OFL.txt`、`assets/fonts/PROVENANCE.md`。

## 0. 兩條硬規則（順序很重要）

### 規則一：流暢優先，不做像素吸附

| 項目 | 值 | 原因 |
|---|---|---|
| 邏輯解析度 | **768×480** | 640×360 的格子太粗，動作讀不出細節 |
| 視窗 | 初始 1536×960；可拖曳／最大化縮放 | 768×480 邏輯不變，畫面隨視窗連續縮放 |
| 拉伸 | `stretch/mode="viewport"` + `aspect="keep"` + `scale_mode="fractional"` | 16:10 以外留黑邊；非整數縮放換來自由視窗 |
| 取樣 | `default_texture_filter=1`（Linear） | 讓旋轉中的方塊邊緣不鋸齒 |
| 物理 | **120 Hz** + `physics_interpolation=true` | 高刷新率螢幕上動作才不會「一格一格」 |
| 相機 | 在 `_physics_process` 更新、浮點、**不取整** | 取整會讓整張畫面抖動 |

選 `fractional`：視窗可自由拖曳／最大化，768×480 邏輯與其他比例的黑邊不變。
放棄固定整數 ×2：非整數縮放會讓邊緣略軟；本專案以浮點運動優先，接受這項交換。

**角色與相機全部使用浮點座標，沒有任何 `roundf()`。**
代價是快速移動的物件可能落在半像素上；這是刻意的交換——用一點點銳利度
換取完全平滑的動作。Godot 會警告 `Camera2D overridden to physics process
mode`，這是預期行為，不要關掉。

### 規則二：多色由 MathArt 統一管理（2026-11-15）

使用者授權全遊戲多色：世界、角色、FX、UI 共用同一套語言，取代舊單色／世界色彩限制。
幾何、φ、浮點運動、玩法／進度與存檔契約不變；真人美術／理解與真人雙路線驗收仍待完成。

| 色彩入口 | 用途 |
|---|---|
| `INK`、`BG_*`、`STONE_*` 至 `PALE` | navy／slate／cream 明度層級；背景與介面保持安靜 |
| `BLACK` / `WHITE` | 最深輪廓與白色命中高光；確切值以 MathArt 為準 |
| `PLAYER` / `ENEMY` / `BOSS` | mint 玩家、coral 敵人、gold Boss；不被 biome 整體染色 |
| `PICKUP` / `CELL` / `GOLD` | cyan 拾取／Cells、gold 貨幣 |
| `ACCENT` / `DANGER` / `HEAL` / `FIRE` | gold 焦點、coral 危險、green 治療、amber 火光 |
| `axis_color(axis)` | brutality coral、tactics violet、survival green；未知軸回 `PALE` |
| `biome_color(id, role)` | 十個正式 biome 與 hub／passage／arena 的世界層次 |

biome roles：`background_top`、`background_mid`、`background_bottom`、`stone`、`edge`、`accent`、`far`、`near`。
未知 ID 回 ash_gate，未知 role 回 stone。顏色是渲染契約；不改 `data/*.json`，避免改動 checkpoint 的 canonical content stamp。

參考：主 agent 已觀看公開 wiki [Prisoners' Quarters](https://deadcells.wiki.gg/wiki/Prisoners%27_Quarters) 的 teal／navy／cyan 與 [Promenade of the Condemned](https://deadcells.wiki.gg/wiki/Promenade_of_the_Condemned) 的 turquoise／violet 實際截圖。觀察冷色前後景、暖光與角色的分離，不匯入任何圖片／原作幾何或宣稱相同 build。

為什麼選這個：冷色空間分層搭配局部暖光，可讓地點有氣氛；固定語意色讓玩家、危險和資源跨 biome 仍可辨識。
放棄了什麼：全屏單一染色和所有元素同樣飽和，因為會混淆深度、角色與互動焦點。

**色相是補充線索**：仍以明度對比、輪廓粗細、形狀、文字與動作表達狀態；不以顏色作唯一辨識。

`MathArt.px_*` 是**平滑（不吸附）的舊別名層**，只服務既有的呼叫點。
新程式碼請直接用 `poly / ring / arc / line / disc / glow`。

#### Historical neutral integration — 2026-11-06

以下是舊單色規則下的實測紀錄，不是現行色彩要求或本輪驗證。2026-11-15 已移除 HUD 的中性材質實作釘選，改驗實際轉場／還原的 biome palette 行為。

2026-11-06 integration correction: `Main._add_fullscreen_shader_layer()` supplies
`MathArt.INK / BG_0 / INK` to the background material's top/mid/bottom shades.
The only production creation path now overrides the inherited unequal-RGB shader
fallbacks; HUD probes assert the actual material parameters. Raw integrated HUD
and map native/owned-client PNGs are checked over every pixel in
`output/ui-refinement-map-2026-11-04/integration/pixel-neutrality-final.json`.

Choose the existing MathArt ramp at the material owner because all actual
background creation is centralized there, preserving geometry and motion.
Reject a new renderer abstraction, shader rewrite and image desaturation;
shader source ownership was not needed for this narrow correction.


## 1. 為什麼這樣做

| 目標 | 做法 |
|---|---|
| 零授權風險 | 沒有第三方資產，全部由程式生成 |
| 改一個常數就換風格 | 顏色、比例、段數都在資料或常數裡 |
| 風格一致 | 全部圖形來自同一組 primitive，不會「拼貼感」 |
| 可測試 | 常數與公式可以寫進 `run_tests.gd` 驗證 |
| 極小體積 | 沒有美術檔，整個 repo 只有程式與音效 |

## 2. 核心常數

| 常數 | 值 | 用途 |
|---|---|---|
| `PHI` | 1.618033988749895 | 黃金比例，用於內外層縮放 |
| `INV_PHI` | 0.618033988749895 | 1/φ，用於嵌套圖形 |
| `GOLDEN_ANGLE` | 2.399963229728653 | 黃金角，用於粒子與火花方向 |

**φ 的用法**：任何「內層」圖形都是外層的 `1/φ`。
六角盾、五角王冠、卡片圖示、平台刻線都用同一條規則。

**黃金角的用法**：火花射線、微粒分佈、餘燼上升都用
`angle = i * 2.399963...`，這是自然界最均勻的無理數間距。

## 3. 圖形詞彙

| 函式 | 數學 | 出現在哪 |
|---|---|---|
| `ngon(n, r)` | 正 n 邊形 | 六角基座、方形 Ram、五角王、HUD 裝飾 |
| `star(n, r, r2)` | 星形（2n 點交替） | 暴擊火花、玫瑰窗、五芒星王 |
| `superellipse(rx, ry, e)` | \|x/a\|^e + \|y/b\|^e = 1 | 門／出口輪廓（`level.gd` 的 exit 繪製） |
| `lissajous(t, a, b, δ)` | x=sin(at+δ), y=sin(bt) | 標題畫面 |
| `rose(t, k)` | r = R·cos(kθ) | 火盆火焰 |
| `phyllotaxis(i, s)` | r = s√i, θ = i·137.5° | 微粒、餘燼、火花方向 |
| `spiral(R, turns)` | 對數螺線 r = R·e^(−bθ) | 羊角、boon 圖示 |
| `ballistic_velocity(...)` | 拋物線解 | 飛刀、弓箭、拋物線預覽 |

## 4. 角色即圖形

| 角色 | 幾何原型 | 理由 |
|---|---|---|
| **玩家** | **正方形**：mint 語意本體 + 2px 深色外框 + 深色內凹方塊（inset 5.5）+ 明亮脈動核心點 | 純幾何，沒有任何肢體。核心點是翻面方向與脈動的既定語意；除此之外**沒有裝飾小點、缺口或眼睛** |
| **Husk** | 三角形（3） | 最原始的攻擊性；尖角向前 |
| **Watcher** | 圓 + 橢圓軌道 | 距離、循環、觀測 |
| **Ram** | 正方形（4） | 穩定、笨重、直線衝撞 |
| **Bulwark** | 六角形（6） | 蜂巢／盾牌結構，正面免疫 |
| **Warden** | 五角形 + 五芒星（5） | 儀式、王權、非人 |

**形狀語言**：邊數越多 = 越接近「秩序／儀式」；邊數越少 = 越接近「原始／暴力」。
玩家是唯一畫成**完美正方形 + 空心內凹面**的角色，這正是 90° 翻滾讀得出來的原因。
單一明亮核心點是內凹面的一部分，不是第二種裝飾符號。2026-11-15 使用者決定保留它，
因為翻滾時可提供方向與生命節奏，同時仍維持無臉、無肢體的最小剪影。
放棄移除核心點：那會讓既有動作簽名失去一層可讀性，還會迫使已驗證的玩家畫面重做。
（角色不使用 `MathArt.superellipse`；正式 biome 的 exit 門洞用它畫出自己的輪廓。）

## 5. 武器即函數

| 武器 | 數學形式 | 表現 |
|---|---|---|
| **Sine Edge**（J，三段） | 刀刃是**一條線**（端點由角度函數驅動） | 動畫由 `SlashFx` 的斷開虛線與 overshoot 承擔，不是靠刀刃變形 |
| **第三段終結** | 把正弦「釋放」成行進波 `sin(kx − ωt)` | 以 1px 像素柱陣列繪製，穿透多個敵人 |
| **Kunai**（K） | 拋物線 `p(t) = p₀ + v₀t + ½gt²` | 自動解出 `v₀` 命中最近敵人，並顯示虛線軌跡 |
| **Aegis**（L） | 三個同心像素環 + 6 個繞行光點 | 格擋 + 反擊波 |

**關鍵設計**：武器的「手感」直接對應它的數學行為。
正弦劍是週期性的（連段節奏）、飛刀是拋物線（要預判）、
Aegis 是徑向場（有明確範圍）。

## 6. 敵人攻擊的數學

| 敵人 | 預警（telegraph） | 攻擊 |
|---|---|---|
| Husk | 圓弧 `draw_arc` 隨進度擴張 | 矩形 hitbox + 擊退 |
| Watcher | 拋物線虛線預覽（實際彈道） | 用同一個 `ballistic_velocity` 射出 |
| Ram | 水平線性長條 | 等速衝刺，撞牆進入 recovery |
| Bulwark | 六角盾脈衝環 | 正面減傷至 1，背後/暴擊正常 |
| Warden | 三種：扇形、直線、同心環 | 橫斬 / 衝撞 / 震波（`sin` 波形投射物） |

**公平性原則**：預警必須畫出「真實的攻擊形狀」。
弓箭手的虛線就是它真正會飛的路徑；王的花瓣環就是震波的範圍。

## 7. 場景

- **玫瑰窗**：12 條輻射線 + 12 角星，半透明，只在背景。
- **石柱**：矩形 + 六角柱頭 + 每兩根一個刻印六角。
- **旗幟**：五邊形布 + 三角徽記。
- **地面**：72 px 網格（φ 相關刻度）、正弦上緣、碎石用 phyllotaxis。
- **平台**：正弦上緣 + φ 刻度（0, 0.382, 0.618, 1）。
- **火盆**：六角基座 + 三層玫瑰線火焰 + phyllotaxis 餘燼。
- **符文**：5 個漂浮多邊形，緩慢旋轉。
- **微粒**：90 個，位置由 phyllotaxis 決定，運動是諧波漂移。

## 8. 後處理（像素版）

| 層 | 內容 | 像素處理 |
|---|---|---|
| layer −10 | 背景漸層 + 對數螺線場 | 只加極輕微 dither（±0.003），不做大幅量化 |
| layer 15 | Bloom | `filter_nearest`，只取樣 2–4 px 鄰域，只讓高光溢出 |
| layer 20 | 暗角 | Bayer 4×4 量化成 5 階，邊緣是硬階梯 |
| layer 30 | HUD | 不受 bloom 影響，文字保持銳利 |
| layer 40 | 獎勵選擇 | 同上 |
| layer 50 | 標題畫面 | 同上 |

**為什麼 HUD 在 bloom 之上**：避免 UI 文字發光糊掉，同時讓遊戲世界的
高光有輝光。這是「用 shader 做後處理」而非「用大量粒子」的取捨。

## 9. 音效與音樂的數學

- **音效**：`tools/make_sfx.py` 用掃頻正弦、單極濾波噪音、指數包絡合成。
- **音樂**：`tools/make_music.py` 產生 32 秒無縫循環。
  所有振盪器頻率都是 `整數 / 32 Hz`，所以循環點沒有相位跳變。
  鐘聲分音比為 1 : 2.4 : 3.7 : 5.1（非諧和，金屬感）。

## 9. 攻擊動畫的像素規格

60 fps 下，以「可讀性 > 細節」排序：

| 階段 | 幀數 | 做法 |
|---|---|---|
| Anticipation | 依段數（`windup` 0.03–0.26 s） | 刀尖收到 `_coil_angle()`（起始角再反向 0.38 rad）；**身體不變形**，只有 −0.22 rad × facing 的 wind-up 扭轉 |
| Active | `active` 0.05–0.11 s | 刀刃在此期間才真正掃過；尾跡由 `SlashFx` 的斷開虛線承擔（見 `impact.md` §4） |
| 尾跡 | 0.13 s（≈8 幀） | 4 段斷開弧、單一半徑 = 刀長、寬 1.2→2.6 px、alpha 0.42→1.0，亮端在前 |
| Overshoot | 2 幀 | 超過目標角 0.18 rad（第三段 0.26 rad） |
| Recovery | 剩餘幀 | 用 55 / 30 / 15 三段 ease-out 回正，不是線性 |
| 二次運動 | 全程 | 刀尖比身體慢 1 幀，身體比刀慢 1 幀 |

**方形翻滾（本作核心動作）**：

| 項目 | 值 |
|---|---|
| 每次跳躍轉幾度 | **正好 90°**，`tumble_to += facing × π/2` |
| 轉完時間 | 0.42 s（比滯空時間略短，落地前已回正） |
| 短跳（提前放開） | 落地後 70 ms 內補完剩餘 1/4 圈，不硬 snap |
| 方向 | 依 `facing`（向右順時針、向左逆時針） |
| 變形 | **沒有**。純平面 2D，方塊永遠不縮放 |
| 面標記 | **沒有面標記**。翻滾本身就是「換了一面」的唯一線索 |

**純平面 2D**：整個遊戲沒有任何 squash / stretch。

- 玩家 `_body_scale()` 直接回傳 `Vector2.ONE`——方塊永遠不變形。
- 重量感來自**旋轉、三層 20 邊形影子、粒子與相機**，不是來自壓扁剪影。
- 敵人也一樣：只傾斜 0.06–0.12 rad（windup / hurt / 移動），從不縮放。
- 這是刻意的交換：26 px 的方形一旦變形，90° 翻滾就會糊掉，而翻滾才是本作的
  動作簽名。跑動的節奏改由旋轉承擔（`sin(_t × 15) × 0.10` 的 rocking）。

**Impact frame**：敵人被擊中時 `impact = 0.034s`（2 幀）整個輪廓變純白，
之後 0.10s 內只剩 2px 白色外框淡出。**不做整屏反相**，那會毀掉可讀性。

**防禦回饋**（`scripts/fx/burst_fx.gd`）：

| 事件 | 規格 |
|---|---|
| Perfect Dodge | 8 條 1px 白色射線，半徑 4→9 px，3 幀，外加 2 幀凍結 |
| Aegis 格擋 | 第 1 幀實心白色扇形（`PALE_DIM` 填充 + `WHITE` 描邊），之後 4 幀環形擴散 6→16 px，全白 |
| 受到攻擊 | 4 條 `WHITE` 射線在**接觸邊緣**（不遮住角色中心），4 幀 |

**i-frame 提示**：翻滾無敵只在**開始與結束各 1 幀**顯示白色外框，
中間不顯示。持續發光會讓玩家無法判斷時機。

## 10. 如何擴充

新增一個視覺元素時：

1. 先問「這是哪個 primitive？」——多邊形、星形、螺線、諧波、拋物線。
2. 用 `MathArt.poly / ring / arc / line / disc / glow` 繪圖，**不要**直接用 `draw_circle` / `draw_arc`。
   （`px_*` 只是舊呼叫點的平滑別名，新程式碼不要再用。）
3. 用 φ 或黃金角決定大小與間距，不要用隨機數（除非是刻意的雜訊）。
4. 加一個 `run_tests.gd` 檢查，如果它是常數或公式。
5. 在 `output/screenshots/` 驗證一次（截圖是 768×480 的真實輸出）。

**不要做**：不要引入貼圖、不要用 `Sprite2D`、不要為了「更好看」而破壞
幾何一致性。風格來自約束，不是來自更多元素。

**但可以做**：一般粒子用 Godot 內建的 `CPUParticles2D`（見
`scripts/systems/juice.gd`）。粒子系統不需要自己寫——引擎已經有發射形狀、
生命曲線、阻尼、縮放曲線與一次性爆發。我們只提供數值，以及一張執行時
生成的 6×6 白色方塊貼圖，所以專案仍然是零外部美術資產。

`ShatterFx` 是輪廓幾何碎片的窄例外：它繼續自行更新 shard 的位移與旋轉，
因為破裂必須沿著被擊中輪廓拆成可辨認的碎面；一般煙塵、火花、拾取與命中
粒子仍走 `Juice.*`。2026-11-15 使用者決定保留這個例外，讓幾何破碎維持原創
形狀語言。放棄改用通用粒子預設：那會失去輪廓碎裂的辨識，並擴張這次政策整理
到 runtime 重寫。
