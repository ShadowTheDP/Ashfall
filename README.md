# Ashfall（DC-like）

原創 roguelite / metroidvania 的**戰鬥手感原型**，用 Godot 4.7.2 製作。

本專案只借用「類型」（roguelite + 2D 動作 + 房間制）與公開的設計概念，
**不包含 Dead Cells 的程式碼、美術、音效、關卡或數值表**。所有角色與特效都是
程式即時繪製，所有音效都由 `tools/make_sfx.py` 合成。

> 專案位置：`C:\Users\user\Desktop\DC-like`
> 這是一個獨立專案，不位於 `Code-Project/Project/` 之下；治理文件沿用
> `Code-Project` 的專案層架構（README / AGENTS / MEMORY / current-state /
> Changing Description / output）。

---

## 1. 目前狀態：Milestone 0

**已經可以玩：**

| 系統 | 內容 |
|---|---|
| 戰鬥手感 | 三段劍連擊、攻擊緩衝、翻滾無敵幀、取消窗口、hitstop、擊退、受擊硬直、鏡頭震動 |
| 移動 | 加速/摩擦、可變跳躍高度、coyote time、跳躍緩衝、落地擠壓 |
| 敵人 | Husk（近戰）、Watcher（弓箭）、Ram（蓄力衝撞），全部有預警 |
| 戰鬥回饋 | 命中火花、斬擊弧、傷害數字、暴擊、連擊計數、音效 |
| 循環 | 3 波敵人、波間回血、細胞掉落與磁吸、死亡/通關結算、R 重來 |
| HUD | 生命、細胞、波次、剩餘敵人、連擊、計時、操作提示 |
| 其他 | 暫停（ESC）、低血量脈衝、程序化背景與霧、環境微粒 |

**刻意還沒有：**

- 房間拼接生成、Biome 規則（支柱 2）
- 完整 Build 系統：副武器、技能、突變、卷軸（支柱 3 只有資料骨架）
- 永久解鎖 / 難度層級（支柱 4）
- 符文閘門與 metroidvania 地圖（支柱 5）
- 存檔、商店、Boss、設定選單、手把重綁
- 匯出 preset 與 export templates（見第 7 節）

---

## 2. 快速開始

需求：Godot **4.7.2**（GL Compatibility 渲染器）。本機的引擎放在 `.tools/`
（已被 `.gitignore` 忽略，不進版控）。

```powershell
# 第一次：下載固定版本的 Godot 到 .tools\
powershell -ExecutionPolicy Bypass -File tools\fetch_godot.ps1

# 雙擊啟動（或從終端機）
.\play.bat

# 直接跑遊戲
.\.tools\Godot_v4.7.2-stable_win64.exe --path .

# 或開啟編輯器
.\.tools\Godot_v4.7.2-stable_win64.exe --editor --path .
```

也可以直接把 `project.godot` 拖進 Godot 編輯器，按 F5。

### 操作

| 動作 | 鍵盤 | 手把 |
|---|---|---|
| 移動 | `A` / `D` 或方向鍵 | 左類比 |
| 跳躍 | `Space` / `W` / `Up` | A |
| 攻擊 | `J` / `Z` | X |
| 翻滾 | `Shift` / `L` | B |
| 暫停 | `Esc` | Start |
| 重來（死亡或暫停時） | `R` | Back |
| 離開（暫停時） | `Q` | — |

**鍵盤完整保證**：所有操作都有鍵盤綁定，遊戲不需要滑鼠；
`scripts/autoload/game.gd` 也不再綁定任何滑鼠事件。手把是額外選項。

> 輸入動作在 `scripts/autoload/game.gd` 的 `_setup_input()` 以程式註冊，
> 不是寫在 `project.godot`。這是刻意的原型取捨，詳見 `MEMORY.md`。

---

## 3. 目錄結構與檔案角色

```text
DC-like/
├── project.godot              # 引擎設定、autoload、視窗與渲染器
├── icon.svg
├── AGENTS.md                  # agent 入口 + Ponytail 規則 + 遊戲專案例外
├── MEMORY.md                  # durable 決策、指令、風險
├── Changing Description.txt   # 唯一的專案變更紀錄
├── .gitignore
├── data/
│   ├── weapons.json           # 武器資料（目前：鏽劍三段）
│   └── enemies.json           # 敵人資料（husk / watcher / ram）
├── assets/audio/              # tools/make_sfx.py 產生的 wav
├── scenes/
│   ├── main.tscn              # 唯一關卡入口（只掛 main.gd）
│   ├── player.tscn            # Actor 根節點；子節點由程式組裝
│   └── enemy.tscn             # 同上
├── scripts/
│   ├── main.gd                # 啟動 world、HUD、背景、encounter
│   ├── autoload/
│   │   ├── data.gd            # JSON 資料表載入
│   │   ├── sfx.gd             # 音效池
│   │   ├── combat.gd          # hitstop / shake / FX 生成
│   │   └── game.gd            # run state、combo、輸入註冊
│   ├── systems/
│   │   ├── damage.gd          # 唯一的傷害公式
│   │   └── layers.gd          # 物理層 bit
│   ├── player/
│   │   ├── player.gd          # 移動與戰鬥狀態機（主要調參處）
│   │   ├── player_visual.gd   # 程序化角色繪製
│   │   └── player_camera.gd   # 跟隨、look-ahead、trauma shake
│   ├── enemies/
│   │   ├── enemy.gd           # 三種敵人共用狀態機
│   │   ├── enemy_visual.gd    # 程序化敵人繪製
│   │   ├── projectile.gd
│   │   └── cell_pickup.gd
│   ├── world/
│   │   ├── arena.gd           # 手工競技場（碰撞 + 繪製 + 出生點）
│   │   ├── motes.gd           # 環境微粒
│   │   └── encounter.gd       # 3 波敵人導演
│   ├── ui/hud.gd              # HUD / 暫停 / 結算
│   ├── fx/                    # 火花、斬擊、傷害數字、殘影、粒子
│   └── combat/hitbox.gd       # 近戰 hitbox（每揮只命中一次）
├── shaders/                   # 背景漸層 + 暗角
├── tests/                     # 無頭測試與截圖工具
├── tools/                     # 音效生成、檢查腳本
├── docs/
│   ├── agent/                 # 冷啟動與交接
│   └── design/                # 五根柱子、手感調參
└── output/                    # 截圖與匯出（gitignored）
```

### 設計上的兩個刻意選擇

1. **Actor 由程式組裝**：`player.tscn` / `enemy.tscn` 只有根節點，
   CollisionShape、Hitbox、Visual、Camera 都在 `_ready()` 建立。
   好處是沒有序列化資源要同步、原型改動快；代價是編輯器場景樹看不到細節。
   等美術與正式場景進場時，再拆成完整 PackedScene。
2. **視覺與音效零外部資產**：角色與敵人是 `_draw()` 畫的，音效是 Python
   合成的。這讓整個 repo 沒有授權風險，也讓「改顏色/改形狀」不需要開繪圖軟體。

---

## 4. 資料驅動與調參入口

### 武器：`data/weapons.json`

每次攻擊的 `windup / active / recovery / cancel_at / lunge / damage /
knockback / hitstop / size / offset` 都在這裡。三段連擊的節奏也在這裡。

### 敵人：`data/enemies.json`

`hp / speed / damage / attack_range / windup / active / recovery / lunge /
cooldown / color / body_radius / body_height`，以及弓箭手的
`projectile_speed`、衝撞者的 `active` 衝刺時間。

### 角色移動：`scripts/player/player.gd` 的 `@export`

跑速、加速度、重力、跳躍初速、jump cut、coyote time、jump buffer、翻滾
速度/時間/無敵幀/冷卻、受擊擊退等。這些用 inspector 調最快，所以沒有放進 JSON。

### 傷害公式：`scripts/systems/damage.gd`

```text
最終傷害 = 基礎傷害 × (1 + 屬性 × 0.12) × 波次縮放 × (暴擊 ? crit_mult : 1)
```

目前屬性固定為 0（Build 系統尚未接上），暴擊條件是「敵人正在預警/攻擊/收招」
（`Enemy.is_exposed()`），所以玩家可以在敵人出手瞬間搶暴擊。

### 手感參數與理由

見 [`docs/design/combat-feel.md`](docs/design/combat-feel.md)。

---

## 5. 驗證

最快的方式：

```powershell
powershell -ExecutionPolicy Bypass -File tools\check.ps1
```

它會依序跑：

```powershell
# 1. 匯入資源 / 編譯腳本
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path . --import

# 2. 資料與傷害公式（無需場景）
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_tests.gd

# 3. 真實輸入的戰鬥探針（命中、傷害、死亡、掉落、i-frames）
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path . tests/combat_probe.tscn

# 4. 全流程 soak（三種敵人 AI + 三波 + 勝利）
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path . tests/soak.tscn
```

### 視覺截圖（需要顯示器）

```powershell
.\.tools\Godot_v4.7.2-stable_win64_console.exe --path . tests\capture_scene.tscn
```

輸出到 `output/screenshots/`（gitignored），包含 idle / run / air / attack /
combo / finisher / roll / bestiary / pause。這是開發時檢查畫面與 HUD 的主要方式。

---

## 6. 目前已知限制

- **一張手工競技場**，沒有房間生成；波次是固定陣列。
- **沒有存檔與 meta 進度**；每次啟動都是新 run。
- **沒有主選單/設定**；輸入綁定在執行時註冊，重綁要改程式。
- **沒有手把提示圖示**，手把可用但 HUD 只顯示鍵盤。
- **沒有匯出 preset**；要輸出 exe 需先安裝 export templates（約 1 GB）。
- 敵人站在平台上不會主動跳下；弓箭手會遠離玩家，可能走到平台邊緣掉下去。
- 遊戲內文字是英文（Godot 內建字型不含 CJK）；文件是中文。

---

## 7. 匯出成 exe（尚未設定，步驟備忘）

1. 編輯器 → `Editor → Manage Export Templates → Download and Install`。
2. `Project → Export → Add... → Windows Desktop`。
3. 建立 `output/build/` 作為匯出目標（不要覆蓋專案根）。
4. 發佈時可勾選 `Resources → Embed PCK` 變成單一 exe；開發期建議
   `.exe` + `.pck` 分離，更新內容不用重打包引擎。
5. Web 匯出適合早期給朋友試玩；手感仍以原生版為準。

---

## 8. 工作規則（給人與 agent）

- 先讀 `AGENTS.md`，再讀 `MEMORY.md` 與 `docs/agent/current-state.md`。
- 只改這個專案；不要碰 `Code-Project/` 的其他專案。
- 內容 schema（武器/敵人/房間資料）被視為「現在就該正確」的範圍，
  不受 Ponytail 的 YAGNI 裁決。
- 手感原型允許拋棄式程式碼，但放在 `tests/` 或明確標記，不要污染主線。
- 設計決策要留下「為什麼選這個、放棄了什麼」兩行，寫進
  `docs/design/` 或 `MEMORY.md`。
- 不要引入任何 Dead Cells 的資產、反編譯輸出或數值表。
- 每次完成一個有意義的階段，更新 `docs/agent/current-state.md`；
  重要變更才更新 `Changing Description.txt`。
