# Ashfall 業務文檔

> 版本 0.3.0 · Godot 4.7.2 · 單色 2D 動作原型
> 文件目的：讓任何接手的人（或 AI）在 30 分鐘內理解這個專案**做什麼、怎麼跑、
> 每一塊負責什麼、數值在哪裡、如何驗證**。

---

## 1. 產品定義

### 1.1 這是什麼

**Ashfall** 是一個原創的 roguelite / metroidvania **戰鬥手感原型**。
它不是商業完整的遊戲，而是一個「把打起來爽不爽這件事做到極致」的技術驗證——
今天已經能跑完一輪完整的 run（標題 → 大廳 → 5 層 → 勝利），並把永久進度寫進存檔。

| 項目 | 內容 |
|---|---|
| 類型 | 2D 橫向動作 / roguelite |
| 平台 | Windows（Godot 4.7.2，GL Compatibility） |
| 一輪長度 | 5 層（第 5 層是 Boss）；清層回大廳，死亡也回大廳 |
| 進度 | `Profile` 寫 `user://ashfall_profile.json`：cells / souls / 永久升級 / 技能節點 / 圖鑑 / 解鎖 |
| 操作 | **純鍵盤**，不需要滑鼠 |
| 美術 | 零外部資產。所有圖形由程式繪製，所有音效由 Python 合成 |
| 視覺 | **完全單色**（黑 / 白 / 灰），768×480 邏輯解析度，整數 ×2 放大 |
| 依賴 | 無第三方 runtime 套件 |

### 1.2 核心設計主張

1. **手感優先於內容。** 玩家 90% 的體驗來自打擊感，不是關卡數量。
2. **數學即美術。** 沒有貼圖、沒有精靈圖。所有形狀來自多邊形、星形、
   螺線、諧波、拋物線。這讓風格一致、零授權風險、改一個常數就換樣子。
3. **單色強迫可讀性。** 沒有顏色可以依賴，所以辨識必須靠**形狀、明度、
   輪廓粗細、動作**。這反過來讓每個元素都必須「長得像它自己」。
4. **流暢優先於像素對齊。** 角色與相機使用浮點座標，不做像素吸附。
   120 Hz 物理 + 插值，動作在任何刷新率下都平滑。

### 1.3 法律邊界

本專案**只借用類型與公開的設計概念**。不含任何 Dead Cells 的程式碼、
美術、音效、關卡或數值表。參考的是公開訪談與設計分析（見
`docs/design/impact.md` 文末來源）。

---

## 2. 系統架構

### 2.1 啟動流程

`start_mode` 預設 `""`，在 `_ready()` 裡解析：沒有 `skip_title` 就是 `"hub"`，
否則 `"arena"`。所以**正式遊戲是標題 → 大廳**，競技場只有測試 harness 會走到。

```
project.godot
  └─ run/main_scene = scenes/main.tscn
       └─ scripts/main.gd  (_ready)
            ├─ start_mode = "arena" if skip_title else "hub"
            ├─ Game.reset_run()
            ├─ world (Node2D)
            │    └─ [start_mode == "arena" 才有] Arena / Runes / Braziers / Motes / Player
            ├─ HudLayer      (layer 30)      HUD
            ├─ RewardLayer   (layer 40)      Boon 三選一
            ├─ TitleLayer    (layer 50)      標題畫面（skip_title 時不存在）
            ├─ ScreenFxLayer (layer 25)      全屏打擊回饋
            ├─ BackgroundLayer (-10) / BloomLayer (15) / VignetteLayer (20)
            └─ [start_mode == "arena" 才有] Encounter
```

**關鍵順序**：標題畫面在 `_ready()` 就把 `get_tree().paused = true`，
HUD 設為 `visible = false`；玩家按 `Enter` / `Space` / `J` 後才解除暫停、顯示 HUD，
並呼叫 `Main.enter_hub()`。

大廳模式下，`enter_hub()` / `start_floor()` 互換 `world` 裡的子節點：

```
Main.enter_hub()
  ├─ _clear_terrain()                      釋放上一份地形
  ├─ Hub（scripts/meta/hub.gd）            自己的 Player、牆、HubUi、下降門
  ├─ Hub.setup(Profile.best_floor)
  └─ _build_meta_screens()                 ArchiveScreen + SkillTree

Main.start_floor(n)
  ├─ _clear_terrain()
  ├─ 新的 Player
  ├─ Level.build(n, randi())               └─ LevelGen.generate(n, seed)
  └─ 重設相機 limits（大廳把 limits 拉寬過）
```

測試用 `.tscn` 設 `skip_title = true`（+ 可選 `auto_rewards`），直接進競技場模式。

### 2.2 五個 Autoload（全域單例）

| 名稱 | 檔案 | 職責 |
|---|---|---|
| `Data` | `scripts/autoload/data.gd` | 載入 `data/*.json`，提供 `weapons` / `enemies` / `rewards` / `floors` / `upgrades` / `skill_nodes` / `characters` / `armor` 字典 |
| `Profile` | `scripts/autoload/profile.gd` | **唯一的存檔讀寫**：cells / souls / 升級 / 技能 / 圖鑑 / 解鎖 / 統計，寫 `user://ashfall_profile.json` |
| `Sfx` | `scripts/autoload/sfx.gd` | 18 個音效池（16 個 AudioStreamPlayer 輪替）+ 32 秒音樂循環 |
| `Combat` | `scripts/autoload/combat.gd` | Hitstop、鏡頭震動、zoom punch、所有 FX 生成入口 |
| `Game` | `scripts/autoload/game.gd` | 單局狀態、連擊、boon、屬性色、樓層流程、輸入註冊、全域節點引用 |

`Profile` 是唯一讀寫存檔的節點，遊戲玩法永遠不直接碰存檔：
戰鬥讀的是 `Player._apply_loadout()`，而那裡只呼叫 `Profile.bonus(stat)`。
存檔用「先寫 `.tmp` 再 rename」：寫到一半中斷也不會毀掉舊檔，
不會出現一份被截斷、把整份進度清空的存檔。
`_sanitize()` 會丟掉資料表已經不認得的 id，並把升級等級 clamp 到 `max`。

`Game` 同時持有：
- `Game.player` — 當前玩家
- `Game.fx_root` — 世界層特效容器（大廳時指向 Hub）
- `Game.screen_fx_root` — 全屏特效容器（layer 25）

### 2.3 模組職責表

| 目錄 | 檔案 | 職責 |
|---|---|---|
| `scripts/systems/` | `math_art.gd` | **視覺語言**：幾何 primitive、灰階調色盤、繪圖 helper |
| | `juice.gd` | **粒子預設**：包裝 Godot 的 `CPUParticles2D`，9 種配方 |
| | `damage.gd` | **唯一傷害公式**（`ATTR_SCALE = 0.12`） |
| | `geom3d.gd` | 3D→2D 投影，只有 Warden Boss 用 |
| | `layers.gd` | 物理層 bit 常數 |
| `scripts/meta/` | `hub.gd` | **大廳**：1600 px 可行走地面、4 座站台、下降門與樓層選擇 |
| | `hub_ui.gd` | **UPGRADES / CHARACTER 面板**：列表 + 卡片、購買/解鎖/選擇 |
| `scripts/player/` | `player.gd` | 移動狀態機、三段劍、飛刀、Aegis、翻滾、翻面跳躍、`_apply_loadout()` |
| | `player_visual.gd` | 玩家繪製：正方形、劍、斬痕、Aegis 環、翻滾 |
| | `weapon_visual.gd` | 6 種武器幾何（curve / lens / fractal / chain / orbit） |
| | `player_camera.gd` | 跟隨、look-ahead、trauma 震動、zoom punch |
| `scripts/enemies/` | `enemy.gd` | 七種敵人共用狀態機 + Boss 三種攻擊模式 |
| | `enemy_visual.gd` | 幾何原型繪製、預警、受擊輪廓 |
| | `projectile.gd` | 拋物線投射物（箭 / 飛刀 / 震波） |
| | `cell_pickup.gd` | 細胞掉落與磁吸 |
| `scripts/combat/` | `hitbox.gd` | 近戰 hitbox（每揮只命中一次） |
| | `function_wave.gd` | 第三段釋放的正弦行進波 |
| `scripts/world/` | `level.gd` | **一層**：把 `LevelGen` 的佈局變成碰撞與石頭，管房間觸發、出口門、`room_cleared` / `cleared` / `player_died` |
| | `level_gen.gd` | **關卡生成**：純資料 `(floor, seed)` → 房間、石板、柱子、出生點、BFS 驗證 |
| | `arena.gd` | ⚠ **競技場模式專用**（手感 fixture，只有 harness 會走到）：地形資料 + 碰撞 + 幾何繪製 |
| | `encounter.gd` | ⚠ **競技場模式專用**：4 波導演 + Boon 流程 |
| | `braziers.gd` / `runes.gd` / `motes.gd` | 競技場模式的背景裝飾（火盆 / 符文 / 微粒） |
| `scripts/ui/` | `hud.gd` | HUD、暫停、結算、Boss 血條、Build 摘要 |
| | `reward_screen.gd` | 鍵盤三選一 Boon（`ROOM CLEARED` / `WAVE CLEARED`） |
| | `archive_screen.gd` | **ARCHIVES**：bestiary / weapons / armour 三分頁 |
| | `skill_tree.gd` | **SKILLS**：11 節點、前置依賴、cells 付費 |
| | `title_screen.gd` | 數學標題畫面 |
| `scripts/fx/` | `impact_fx.gd` | **分級打擊特效**（火花 + 環 + 白閃 + 多邊形） |
| | `screen_punch.gd` | 全屏暗角脈衝 + 掃描帶 |
| | `slash_fx.gd` | 獨立斬擊弧 |
| | `hit_spark.gd` / `ring_fx.gd` / `shatter_fx.gd` | 火花 / 環 / 碎裂 |
| | `burst_fx.gd` | 閃避 / 格擋 / 受擊三種爆發 |
| | `afterimage.gd` | 翻滾殘影 |
| | `damage_number.gd` | 飄浮傷害數字 |
| | `parabola_fx.gd` | 拋物線虛線預覽 |
| `shaders/` | `background.gdshader` | 對數螺線背景 + 光源池 |
| | `bloom.gdshader` | 螢幕空間輝光（nearest 取樣） |
| | `vignette.gdshader` | 四階 Bayer 暗角 |

---

## 3. 遊戲循環

### 3.1 正式循環

```
標題  (整棵樹暫停；Enter / Space / J 開始)
  ↓
大廳 HUB
  ├─ UPGRADES   cells / souls 買永久升級
  ├─ SKILLS     11 節點技能樹
  ├─ ARCHIVES   bestiary / weapons / armour
  ├─ CHARACTER  6 種身體
  └─ 下降門     A/D 選層（1..best_floor+1），J 下樓
  ↓
第 1 層 → 第 2 層 → 第 3 層 → 第 4 層 → 第 5 層
  ├─ 清層     finish_floor() 立刻入帳 → 回大廳
  ├─ 死亡     end_run(false)，未入帳的 cells 消失 → 回大廳
  └─ 清完第 5 層  end_run(true)，入帳 + 1 soul → 回大廳
```

### 3.2 大廳（Hub）

| 項目 | 值 / 行為 |
|---|---|
| 地面寬度 | 1600 px（牆外還有碰撞） |
| 站台 | 4 座：UPGRADES `x=210`、SKILLS `x=520`、ARCHIVES `x=830`、CHARACTER `x=1140` |
| 互動 | 靠近 `REACH = 70` px 內按 `J` / `Enter`；開面板時凍結玩家物理 |
| 下降門 | `x = 1560`；`A`/`D` 在 `1..best_floor+1` 之間步進，`J` 下降 |
| 互斥 | 同時只能開一個面板（`Main._any_panel_open()`）；Esc 只關當下那個 |
| 樓層起點 | `Hub.setup(Profile.best_floor)`：預設指向「下一個沒去過的層」 |

### 3.3 樓層（Level / LevelGen）

```
main.start_floor(n)
  ├─ _clear_terrain()                 釋放上一份地形
  ├─ 新 Player                        （permanent loadout 重新套用）
  ├─ Level.build(n, randi()) → LevelGen.generate(n, seed)
  └─ 重設相機 limits                  （大廳把 limits 拉寬過）
```

**幾何**：垂直、多層。

| 常數 / 概念 | 值 |
|---|---|
| 連續底邊 | 整條寬度都存在，是最後的安全網 |
| 石板高度 | 房間位於底邊上方 `0–96` px（再高就從底邊爬不上去） |
| `TIER` | `92` px（層與層的垂直間隔） |
| 層數 | 每房 2–5 層 |
| 單向平台 | 可從下方跳穿、從上面站；虛線底邊就是「可穿過」的提示 |
| 實心塊 | 石板、柱子、天花塊，必須繞過或翻上去 |
| 房間原型 | 6 種：`gate` / `hall` / `shaft` / `vault` / `bridge` / `well` |
| 柱子 | 房間之間的柱不可跳過，強迫用房間的平台往上再往前 |
| 可達性 | 生成後 BFS 驗證：終點不可達就告警，不發一層死關 |

**★ 房間與樓層流程**

```
進入房間矩形 → 生成該房敵人（避開玩家 160 px；Boss 用 boss_at 專用車道）
  房內最後一隻死 → room_cleared(index)
     └─ Main：floor_rewards_left--，>0 就升起 boon 選擇器（RewardScreen）
全層敵人清空 → 出口門開啟（轉速變快、變白）
走進門柱 |dx| < 62、|dy| < 260 → cleared
   ├─ Game.finish_floor()：run_cells 立刻入帳
   ├─ 未到第 5 層 → announce FLOOR CLEARED，轉場後回大廳
   └─ 第 5 層 → Game.end_run(true)：入帳 + 1 soul
```

### 3.4 局內 build（兩色）

- 每把武器帶 `attribute`：`brutality`（紅）或 `tactics`（紫）；飛刀永遠算 tactics。
- 帶 `attribute` 的 boon（EDGE / HUNTER = brutality，GHOST / ARMORY = tactics）
  會讓 `Game.attr[colour] += 1`。
- `Player.weapon_attr_level()` = 局內該色 boon 數 + `Profile.bonus(colour)`（souls 升級），
  餵給 `Damage.compute(base, attr, ...)`，每級 `ATTR_SCALE = 0.12`。
- boon 預算在 `data/floors.json` 的 `reward`（2/2/3/3/0），**每清一房花一個**；
  進層時重設，也就在 `Game.start_floor()` 清空 `Game.attr`。
- HUD 的 build 面板列 `Game.reward_counts`，所以它現在真的會顯示拿過的 boon。

### 3.5 競技場模式（harness fixture，不是遊戲）

`start_mode == "arena"` 才成立的舊流程：

```
Wave 1  3 × Husk
  ↓ 清空 → 回血 25 → Boon 三選一
Wave 2  2 × Husk + 1 × Watcher
  ↓ 清空 → 回血 25 → Boon 三選一
Wave 3  2 × Husk + 1 × Bulwark
  ↓ 清空 → 回血 25 → Boon 三選一
Wave 4  The Warden (Boss)
  ↓
FLOOR CLEARED  或  YOU DIED
```

- 波次資料：`scripts/world/encounter.gd` 的 `WAVES` 常數（4 波）
- 敵人生命縮放：`1 + 0.08 × wave_index`（Boss 固定 1.0）
- 出生點：近戰 / 衝撞用地面點，弓箭手優先用平台點；避開玩家 190 px 以內
- 教學意義：Wave 1 連段/翻滾、Wave 2 讀拋物線、Wave 3 繞背、Wave 4 綜合
- `arena.gd` / `encounter.gd` 頂部的註解寫的就是「ARENA MODE ONLY」

---

## 4. 玩家能力

### 4.1 操作表（全鍵盤）

| 動作 | 按鍵 | 手把 |
|---|---|---|
| 移動 | `A` `D` / `←` `→` | 左類比 |
| 跳躍 | `Space` `W` `↑` | A |
| 正弦劍（三段） | `J` `Z` | X |
| 拋物線飛刀 | `K` | Y |
| Aegis 護盾 | `L` | LB |
| 翻滾 | `Shift` | B |
| 暫停 | `Esc` | Start |
| 重來 | `R` | Back |
| 離開（暫停時） | `Q` | — |
| 開始 / 選 Boon | `Enter` / `1` `2` `3` | — |
| 大廳：開站台 / 下降（靠近時） | `J` `Enter` | — |
| 大廳：切換樓層（門口） | `A` `D` / `←` `→` | — |
| 面板內：移動 / 確認 / 關閉 | 方向鍵或 `WASD` / `J` `Enter` `Space` / `Esc` | — |

輸入在 `game.gd._setup_input()` **執行時註冊**，不寫在 `project.godot`。
`shortcut: 沒有遊戲內重綁；等設定選單出現時再搬進 project.godot。`

### 4.2 移動數值

| 參數 | 值 | 說明 |
|---|---:|---|
| 跑速 | 300 px/s | |
| 地面加速 | 3200 | 0.094 s 到全速 |
| 地面摩擦 | 3600 | 0.083 s 停下 |
| 空中加速 | 2100 | |
| 上升重力 | 1800 | 跳躍頂點約 0.35 s |
| 下降重力 | 2500 | 落地更乾脆 |
| 跳躍初速 | −630 | 高度約 110 px |
| 放開跳躍 | ×0.48 | 可變跳躍高度 |
| Coyote time | 0.10 s | 6 幀 |
| Jump buffer | 0.12 s | 7 幀 |
| 頂點滯留 | 重力 ×0.45，最多 70 ms | |

### 4.3 翻面跳躍

**這是本作的核心視覺機制。**

```
每次跳躍：face = (face + 1) % 4
旋轉：正好 90°，依 facing 決定順時針或逆時針
時間：0.42 s 轉完（比滯空略短，落地前已回正）
短跳：落地後 70 ms 內補完剩餘 1/4 圈，不硬 snap
```

正方形轉 90° 後外觀相同，但**動作本身**（旋轉過程、影子、粒子）足以
傳達「換面」。使用者已確認可讀。

### 4.4 三段劍（Sine Edge）

| 段 | 傷害 | 前搖 | 有效 | 收招 | 取消點 | 擊退 | hitstop | 刀刃長 | tier |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 11 | 0.06 | 0.07 | 0.15 | 55% | 170 | 45 ms | 38 | 0 |
| 2 | 13 | 0.08 | 0.07 | 0.17 | 55% | 190 | 50 ms | 40 | 1 |
| 3 | 24 | 0.15 | 0.09 | 0.26 | 62% | 430 | 85 ms | 50 | 3 |

- 暴擊倍率 1.7×
- 第三段額外釋放 `FunctionWave`（正弦行進波，8 傷害，可穿透）
- 攻擊中可翻滾取消，也可預先排隊下一段

### 4.5 飛刀（Kunai）

- 傷害 12、速度 820、重力 900
- 用 `MathArt.ballistic_velocity()` **反解 `v₀`** 命中最近敵人
- 發射前顯示虛線軌跡
- 2 發充能，1.5 s 回 1 發

### 4.6 Aegis

- 0.45 s 有效，3.0 s 冷卻
- 格擋一次傷害
- 成功格擋 → 118 px 反擊波（10 傷害）

### 4.7 Perfect Dodge

- 在翻滾無敵幀（0.03–0.24 s）內被命中
- 效果：+25% 傷害持續 2.5 s、返還一把飛刀、8 條射線、2 幀凍結

### 4.8 Boon（7 種）

| ID | 名稱 | 顏色 | 效果 |
|---|---|---|---|
| `vitality` | VITALITY | — | +20 最大生命，回 20 |
| `edge` | EDGE | brutality | +12% 傷害 |
| `swift` | SWIFT | — | +8% 移速 |
| `ghost` | GHOST | tactics | +30 ms 翻滾無敵 |
| `armory` | ARMORY | tactics | +1 飛刀充能 |
| `leech` | LEECH | — | 每次擊殺回 1 血 |
| `hunter` | HUNTER | brutality | +15% 暴擊傷害 |

效果實作在 `Game.apply_reward()`，顏色寫在 `data/rewards.json` 的 `attribute`。
有顏色的 boon 同時會 `Game.attr[colour] += 1`，那一色的武器就因此變強（見 3.4）。
發放不是「波間三選一」，而是**每清一房一次**，預算來自 `data/floors.json` 的 `reward`。

---

## 5. 敵人

### 5.1 形狀語言

**邊數 = 威脅層級**（例外：Spitter 用凹星表示「不是近戰威脅」，
Leaper 用細長三角表示「它會離地」）；玩家是唯一的正方形。

| 敵人 | 幾何 | 行為 | 教學點 |
|---|---|---|---|
| Husk | **三角形 (3)** | 近戰追擊 | 連段、翻滾 |
| Watcher | **圓 + 軌道** | 保持距離，拋物線射擊 | 走位、讀彈道 |
| Ram | **正方形 (4)** | 長預警直線衝撞 | 預判、側閃 |
| Bulwark | **六角形 (6)** | 正面免疫，需繞背 | 位置、暴擊 |
| Spitter | **七點星（凹形）** | 手上聚攏一顆球，命中地面留腐觸池 | 地形控制、不要站住 |
| Leaper | **細長三角** | 向上跳躍砸地，只在落地那一幀開 hitbox | 打高處、讀預警弧 |
| The Warden | **五角形 + 五芒星 (5)** | 橫斬 / 衝撞 / 震波 | 綜合 |

### 5.2 數值表

| 敵人 | HP | 速度 | 傷害 | 攻擊距離 | 前搖 | 有效 | 收招 | 冷卻 | 細胞 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Husk | 42 | 92 | 9 | 48 | 0.40 | 0.12 | 0.42 | 0.35 | 1 |
| Watcher | 34 | 74 | 7 | 460 | 0.52 | 0.10 | 0.46 | 1.45 | 1 |
| Ram | 70 | 68 | 14 | 300 | 0.62 | 0.34 | 0.58 | 1.9 | 2 |
| Bulwark | 95 | 55 | 12 | 62 | 0.55 | 0.14 | 0.50 | 0.65 | 2 |
| Spitter | 38 | 62 | 8 | 420 | 0.62 | 0.10 | 0.50 | 1.7 | 1 |
| Leaper | 46 | 104 | 12 | 240 | 0.50 | 0.12 | 0.45 | 1.2 | 1 |
| **Warden** | **380** | 78 | 18 | 110 | 0.60 | 0.16 | 0.55 | 0.70 | 12 |

**出場樓層**（`data/floors.json`）：Spitter 在第 3、4 層，Leaper 在第 2、4 層。
兩隻都真的會生成，不是「有資料但沒有關卡用到」。

### 5.3 特殊規則

- **Bulwark 盾**：正面非暴擊只掉 1 HP。繞背或抓預警才能正常傷害。
- **Warden 不被硬直**：`boss` flag 跳過 HURT 狀態，擊退只有 12%。
- **Watcher 沒有弓**：直接攻擊，蓄力時一個環收縮到圓周，加 3 個繞行衛星點。
- **Spitter 的球**：`projectile_speed = 560`，命中或落地留下 `pool_time = 2.4` 秒的
  腐觸池（`pool_damage = 6`、`pool_radius = 30`）；池子活得比 Spitter 本身久。
- **Leaper 的 hop**：`hop_speed = 420`、`hop_rise = 260`，空中不追蹤，
  落地那一幀才開 hitbox；預警弧就是它要去的點。
- **所有人**：沒有手腳、沒有眼睛。手是一個點。

### 5.4 預警（Telegraph）

所有預警都畫出**真實的攻擊形狀**：

| 敵人 | 預警 |
|---|---|
| Husk | 扇形弧線隨進度擴張 |
| Watcher | 拋物線虛線（就是實際彈道）+ 收縮環 |
| Ram | 水平長條隨進度伸長 |
| Bulwark | 盾前扇形脈衝 |
| Spitter | 球的實際拋物軌跡（`_draw_glob_prediction`） |
| Leaper | 跳躍弧線（`_draw_hop_prediction`）+ 收縮的蓄力彈簧 |
| Warden | 三種：扇形（橫斬）/ 直線（衝撞）/ 同心環（震波） |

---

## 6. 打擊感系統

**完整規格見 `docs/design/impact.md`。** 這裡只列架構。

### 6.1 四級強度

| tier | 名稱 | hitstop | 震動 | zoom punch | 全屏 |
|---:|---|---:|---:|---:|---|
| 0 | LIGHT | 2f (33ms) | 0.16 | — | — |
| 1 | MEDIUM | 4f (67ms) | 0.30 | — | — |
| 2 | HEAVY | 6f (100ms) | 0.52 | 0.45 | ✓ |
| 3 | FINISHER | 8f (133ms) | 0.72 | 0.75 | ✓ |

暴擊自動升一級。同一幀多目標不疊加。

### 6.2 每次命中的三層

```
Combat.impact(point, direction, tier)
  ├─ ImpactFx
  │    ├─ 白色閃光（1–2 幀，10/13/18/24 px 十字）
  │    ├─ 擴張環（18/24/36/54 px，5–10 幀）
  │    ├─ 旋轉多邊形（tier≥2，5 或 6 邊，內接 1/φ 內框）
  │    └─ 方向性火花（8/10/12/16 條，沿命中法線 ±80°）
  ├─ 鏡頭震動（trauma）
  ├─ Zoom punch（tier≥2，×1.025）
  └─ ScreenPunch（tier≥2，暗角脈衝 + 掃描帶）
```

### 6.3 斬痕（Smear）

**核心規則：不畫任何連續填充形狀。**

刀刃 38–50 px 時，任何實心扇形或弧帶都會變成「月餅」。所以：

```
斬痕 = 三層同心細弧，但與刀刃之間留 0.32 rad 空隙
       + 最後 1/3 加亮
       + 3 條後方切線小短線（脫離弧線）
       + 3 個黃金角點綴
       + 刀尖延遲點（1 幀前位置）
```

**空隙是關鍵**：如果斬痕碰到刀尖，刀 + 斬痕會連成一個 L 形。

### 6.4 粒子

`scripts/systems/juice.gd` 包裝 Godot 的 `CPUParticles2D`，9 種預設：

`dust` / `land_dust` / `jump_burst` / `hit_sparks` / `shatter` / `pickup` / `block` / `dodge` / `telegraph`

只提供數值與一張執行時生成的 6×6 白色方塊貼圖，**專案仍是零外部美術資產**。

### 6.5 全屏層

`ScreenFxLayer`（layer 25，低於 HUD）：
- 暗角脈衝（中心保持清晰）
- 1–2 條掃描帶，偏移 ±2–4 px，只活 **2 幀**
- **不做**整屏反相、常駐故障濾鏡

---

## 7. 視覺系統

**完整規格見 `docs/design/math-art.md`。**

### 7.1 解析度與渲染

| 項目 | 值 |
|---|---|
| 邏輯解析度 | 768×480 |
| 視窗 | 1536×960（整數 ×2） |
| 拉伸 | `viewport` + `scale_mode=integer` |
| 材質過濾 | Linear |
| 物理 | 120 Hz + `physics_interpolation=true` |
| 相機 | `zoom=1.0`，浮點位置，不取整 |

### 7.2 灰階梯度

所有顏色來自 `MathArt`，**嚴格中性灰（`r == g == b`）**，沒有任何色相偏移：

```
BLACK      #000000   純黑（描邊）
INK        #0a0a0a   背景最深
BG_0..2    #111111 → #1b1b1b → #252525
STONE_DIM  #333333
STONE      #404040   地形 / 內凹面
STONE_HI   #5b5b5b   地形邊線 / 行走線
MID_DIM    #707070
MID        #808080   次要文字
LIGHT_DIM  #a0a0a0
LIGHT      #bdbdbd   敵人本體
PALE_DIM   #d5d5d5   盾牌 / 敵人輪廓
PALE       #e3e3e3   Boss
WHITE_DIM  #f2f2f2
WHITE      #ffffff   玩家 / 命中高光
```

語意別名：`PLAYER = WHITE`、`PLAYER_CORE = INK`、`ENEMY = LIGHT`、
`ENEMY_RIM = PALE_DIM`、`BOSS = PALE`、`PICKUP = WHITE`、`DANGER = WHITE`、
`SHIELD = PALE_DIM`。

資料裡也不允許有色相：`data/rewards.json` 的 `color` 全部是中性灰（`#c9c9c9` 等），
`data/enemies.json` 的 `color` 也一樣。

### 7.3 幾何 primitive

| 函式 | 數學 | 用途 |
|---|---|---|
| `ngon(n, r)` | 正 n 邊形 | 敵人本體、HUD 裝飾 |
| `star(n, r1, r2)` | 星形 | 暴擊火花、玫瑰窗、五芒星 |
| `superellipse` | \|x/a\|^e+\|y/b\|^e=1 | 保留 |
| `lissajous` | x=sin(at+δ), y=sin(bt) | 標題畫面 |
| `rose` | r=R·cos(kθ) | 火盆火焰 |
| `phyllotaxis` | r=s√i, θ=i·137.5° | 微粒、餘燼、火花 |
| `spiral` | r=R·e^(−bθ) | 羊角、boon 圖示 |
| `harmonic_wave` | y=A·sin(kx+φ) | 保留 |
| `ballistic_velocity` | 拋物線解 | 飛刀、弓箭 |

### 7.4 角色繪製

**玩家**：白框正方形 + 黑色內凹面 + 白色核心點 + 2px 黑描邊。
- 握點在**下半部前緣** `(facing×13, +4)`
- 劍靜止**朝上**（`REST_ANGLE = -1.30` rad）
- 劍是**單一漸細四邊形**（底 4.2px → 尖 0.7px），只有一側有 1px 高光

**敵人**：純多邊形 + 內凹 + 手點。沒有腿、沒有手臂、沒有眼睛。

**陰影**：三層堆疊橢圓（20 邊形），累積中心密度約 0.30，邊緣淡出。

---

## 8. 資料驅動

### 8.1 內容資料（`data/*.json`）

| 檔案 | 內容 | 誰讀 |
|---|---|---|
| `floors.json` | 5 層：`name / rooms / width / enemies / boss / palette / reward` | `Game.start_floor()`、`LevelGen._floor_config()`、`Hud` |
| `weapons.json` | 每段攻擊的時序、傷害、hitbox、`tier`、`blade`，加 `attribute` / `crit_multiplier` | `Player._open_hitbox()`、`PlayerVisual._blade_length()` |
| `enemies.json` | 7 種敵人的數值與行為旗標 | `Enemy.configure()` |
| `rewards.json` | Boon 的名稱、描述、顏色、`attribute` | `RewardScreen`、`Game.apply_reward()` |
| `upgrades.json` | 9 種永久升級（含 souls 定價的 brutality / tactics） | `Profile.upgrade_*()` / `HubUi` |
| `skill_nodes.json` | 11 節點技能樹（`requires` 前置） | `Profile.skill_available()`、`SkillTree` |
| `characters.json` | 6 種可選身體（hp / speed / jump / knives / passive） | `Player._apply_loadout()`、`HubUi` |
| `armor.json` | 5 件護甲（hp / damage_taken / speed / iframe / knives） | `Player._apply_loadout()`、`ArchiveScreen` |

**武器 hitbox 由刀刃長度推導**：

```
reach  = hand_x + blade + 5     // 13 + 38 + 5 = 56
size   = [reach, 56 / 64 / 68]
offset = [reach / 2, +4]
```

所以畫出來的刀尖、斬擊弧、傷害判定是同一組數字。每把武器也自己帶
`shape`（`curve` / `lens` / `fractal` / `chain` / `orbit`）給 `WeaponVisual` 畫幾何。

### 8.2 程式內常數

| 位置 | 內容 |
|---|---|
| `player.gd` 的 `@export` / `const` | 移動、翻滾、戰鬥、飛刀、Aegis 的調參值；echo passive 的延遲 |
| `level_gen.gd` 的 `const` | `TIER = 92`、`JUMP_HEIGHT / JUMP_LENGTH`、房間原型權重與最小寬度 |
| `level.gd` 的 `const` | `DOOR_REACH = 62`、`DOOR_HEIGHT = 260`、`SAFE_DISTANCE`、5 組 palette |
| `hub.gd` 的 `const` | `WIDTH = 1600`、`DOOR_X = 1560`、`REACH = 70`、4 座站台 |
| `arena.gd` 的 `const` | 地形 rect、出生點（**競技場模式專用**） |
| `encounter.gd` 的 `WAVES` | 波次編排（**競技場模式專用**） |
| `impact_fx.gd` 的 `const` 陣列 | 四級打擊特效表 |
| `combat.gd` 的 `TIER_*` | hitstop / 震動 / punch 分級 |

### 8.3 傷害公式（唯一入口）

`scripts/systems/damage.gd`：

```
最終傷害 = 基礎傷害 × (1 + 屬性等級 × ATTR_SCALE) × (暴擊 ? crit_mult : 1)

ATTR_SCALE = 0.12
基礎傷害   = 武器段傷害 × Game.total_damage_mult() × permanent_damage_mult
屬性等級   = Player.weapon_attr_level()
           = Game.attr[武器顏色] + Profile.bonus(武器顏色)
```

`Damage.compute(base, attr, crit, crit_mult, scale = 1.0)` 是唯一入口；
`scale` 目前沒有呼叫者傳值（預設 1.0）。飛刀永遠算 tactics。

暴擊條件：敵人處於預警 / 攻擊 / 收招，**或**玩家在其背後。
Perfect Dodge 期間 `Game.total_damage_mult()` 額外 ×1.25。

---

## 9. 音訊

### 9.1 音效（18 個，全部程式合成）

`tools/make_sfx.py` 用掃頻正弦、單極濾波噪音、指數包絡合成，
輸出 22050 Hz 單聲道 16-bit WAV。

`swing` `hit` `crit` `roll` `jump` `land` `hurt` `death` `pickup` `shoot`
`ui` `wave` `throw` `block` `dodge` `slam` `boss` `reward`

### 9.2 音樂（32 秒無縫循環）

`tools/make_music.py`：

- 所有振盪器頻率都是 `整數 / 32 Hz`，所以循環點沒有相位跳變
- 鐘聲分音比 `1 : 2.4 : 3.7 : 5.1`（非諧和，金屬感）
- 低頻脈衝每 2 秒一次

---

## 10. 驗證

### 10.1 一鍵驗證

```powershell
powershell -ExecutionPolicy Bypass -File tools\check.ps1
```

依序執行 15 個階段（今天實跑：`ALL CHECKS PASSED`，exit 0）：

| 階段 | 指令 | 驗證什麼 |
|---|---|---|
| 1 | `--import` | 資源匯入、腳本編譯 |
| 2 | `--script tests/run_tests.gd` | **111** 項資料 / 公式 / 數學常數檢查 |
| 3 | `tests/combat_probe.tscn` | 真實輸入的命中、傷害、死亡、i-frames |
| 4 | `tests/reward_probe.tscn` | 鍵盤 Boon 選擇器 |
| 5 | `tests/soak.tscn` | 競技場模式：全部敵人 + 4 波 + Boss + 勝利 |
| 6 | `tests/esc_probe.tscn` | 大廳面板開/關/購買；Esc 只關一個 panel |
| 7 | `tests/floor_probe.tscn` | 大廳 → 樓層交接（相機 limits、地形釋放） |
| 8 | `tests/run_probe.tscn` | 完整 run：5 層 → 勝利 |
| 9 | `tests/audit_a1.tscn` | 戰鬥 / 武器 |
| 10 | `tests/audit_a2.tscn` | 存檔 / 經濟（**123 checks**） |
| 11 | `tests/audit_a3.tscn` | 層 / 出生點（5 層 × 15 seeds） |
| 12 | `tests/audit_a4.tscn` | UI / 輸入（**226 checks**） |
| 13 | `tests/audit_v1.tscn` | 垂直可達性（5 層 × 40 seeds） |
| 14 | `tests/audit_v2.tscn` | 敵人 / 遭遇 |
| 15 | `tests/audit_v3.tscn` | run 流程 / 進度（**162 checks**） |

### 10.2 視覺驗證（需顯示器，不進 headless 驗證）

```powershell
# 標題畫面 + Enter 驗證
.\.tools\Godot_v4.7.2-stable_win64_console.exe --path . tests\title_capture.tscn

# 遊戲畫面
.\.tools\Godot_v4.7.2-stable_win64_console.exe --path . tests\capture_scene.tscn

# 逐幀打擊截圖（輕擊 + 終結技）
.\.tools\Godot_v4.7.2-stable_win64_console.exe --path . tests\impact_capture.tscn

# 跳躍逐幀（驗證翻面）
.\.tools\Godot_v4.7.2-stable_win64_console.exe --path . tests\jump_capture.tscn

# 大廳與 meta 面板
.\.tools\Godot_v4.7.2-stable_win64_console.exe --path . tests\meta_capture.tscn
```

輸出到 `output/screenshots/`（gitignored）。

### 10.3 目前狀態

```
TESTS OK (111 checks)
PROBE OK    REWARD OK    SOAK OK
ESC TEST OK    FLOOR PROBE OK    RUN PROBE OK
AUDIT A1..A4 OK    AUDIT V1..V3 OK
ALL CHECKS PASSED
```

---

## 11. 開發流程

### 11.1 環境

```powershell
# 第一次：下載固定版 Godot 到 .tools\
powershell -ExecutionPolicy Bypass -File tools\fetch_godot.ps1

# 啟動
.\play.bat
```

### 11.2 目錄慣例

| 路徑 | 用途 | 進版控 |
|---|---|---|
| `scripts/` | 全部 GDScript | ✓ |
| `data/` | JSON 內容資料 | ✓ |
| `scenes/` | 只有根節點的場景 | ✓ |
| `shaders/` | GLSL | ✓ |
| `tests/` | 無頭測試 + 截圖工具 | ✓ |
| `tools/` | 生成腳本、檢查腳本 | ✓ |
| `docs/` | 設計與交接文件 | ✓ |
| `.tools/` | Godot 執行檔 | ✗ |
| `.godot/` | 匯入快取 | ✗ |
| `output/` | 截圖、建置產物 | ✗ |

### 11.3 改動驗證矩陣

| 改動類型 | 最低驗證 |
|---|---|
| JSON 資料 / 傷害公式 / 屬性縮放 | `tests/run_tests.gd` |
| 玩家攻擊 / 受擊 / 翻滾 | `tests/combat_probe.tscn` |
| 敵人 AI / 波次 / 掉落（競技場） | `tests/soak.tscn` |
| 樓層生成 / 出生點 / 可達性 | `tests/audit_a3.tscn` + `tests/audit_v1.tscn` |
| 大廳 / 面板 / 輸入互斥 | `tests/esc_probe.tscn` + `tests/audit_a4.tscn` |
| 存檔 / 經濟 / 升級定價 | `tests/audit_a2.tscn` |
| 完整 run 流程 | `tests/run_probe.tscn` + `tests/audit_v3.tscn` |
| HUD / 相機 / shader | `tests/capture_scene.tscn` + 看截圖 |
| 打擊特效 | `tests/impact_capture.tscn` + 看逐幀 |
| 跳躍 / 翻面 | `tests/jump_capture.tscn` |

### 11.4 硬性規則（違反會破壞整體風格）

1. **視覺只能透過 `MathArt`**。不引入貼圖、不用 `Sprite2D`。
2. **不新增色相**。所有顏色來自 `MathArt` 灰階梯度。
3. **角色沒有手腳、沒有眼睛**。手是一個點。
4. **不為角色加變形**（squash / stretch）。純平面 2D，只有旋轉與位移。
5. **斬痕不能是連續填充形狀**。用斷開的細弧 + 切線。
6. **斬痕與刀刃之間要留空隙**，否則會連成 L 形。
7. **鍵盤優先**。任何新操作都必須有鍵盤綁定。
8. **粒子用 `Juice.*`**，不要自己寫粒子模擬。
9. **打擊用 `Combat.impact()`**，不要各自寫火花。

---

## 12. 已知限制

| 限制 | 影響 | 可能解法 |
|---|---|---|
| 單一存檔槽（`user://ashfall_profile.json`） | 不能多檔案 / 回滾 | 加槽位選擇與備份 |
| 沒有難度層級 / 無盡模式 | 清完 5 層就只剩刷 | 加難度等級或 endless 樓層 |
| 只有一隻 Boss（第 5 層的 The Warden） | 後期變化少 | 每層 boss，或第 3 層加一隻中王 |
| 沒有設定選單 | 輸入不能重綁 | 把輸入搬進 `project.godot` + UI |
| 敵人不會為了追擊而跳平台 | 弓箭手可能掉下去 | 加跳躍 AI |
| 沒有匯出 preset | 無法產出 exe | 下載 export templates（1.28 GB） |
| 遊戲內文字是英文 | 中文玩家要適應 | 加 CJK 字型 |
| Bloom 是螢幕空間近似 | 不是真 HDR | 可接受 |

---

## 13. 里程碑歷史

| 版本 | 內容 |
|---|---|
| **M0** | 單一競技場、3 波、3 敵人、完整手感回饋、HUD、死亡/勝利 |
| **M1** | 標題畫面、Boss、Bulwark、7 種 Boon、數學美術、音樂 |
| **M2** | 像素風階段（解析度在 M3 定為 768×480）、動作遊戲動畫語法（蓄力→smear→impact→overshoot） |
| **M3** | 768×480 單色、120 Hz + 插值、翻面正方形、無手腳、CPUParticles2D |
| **M4** | 四級打擊感、方向性火花、全屏回饋、握點修正 |
| **M5** | 斬痕改斷線、握點下移劍朝上、純平面 2D、弓箭手不畫弓、數學元素 |
| **M6** | Meta 層：`Profile` 存檔、大廳 4 站台、5 層生成、兩色 build、souls |

---

## 14. 文件索引

| 文件 | 內容 |
|---|---|
| `README.md` | 專案入口、快速開始、目錄結構 |
| `AGENTS.md` | AI agent 工作規則、硬性約束 |
| `MEMORY.md` | 持久決策、指令、風險、驗證狀態 |
| `docs/agent/current-state.md` | 當前目標與下一步 |
| `docs/design/pillars.md` | 五根柱子與里程碑規劃 |
| `docs/design/math-art.md` | **視覺語言完整規格** |
| `docs/design/impact.md` | **打擊感完整規格** |
| `docs/design/combat-feel.md` | 手感調參表與理由 |
| `docs/design/meta.md` | meta 層（大廳 / 樓層 / 進度）的介面契約 |
| `Changing Description.txt` | 變更紀錄 |
