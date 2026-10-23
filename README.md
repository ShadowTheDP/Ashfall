# Ashfall（DC-like）

原創 roguelite / metroidvania 的**戰鬥手感原型**，用 Godot 4.7.2 製作。

本專案只借用「類型」（roguelite + 2D 動作 + 房間制）與公開的設計概念，
**不包含 Dead Cells 的程式碼、美術、音效、關卡或數值表**。
所有角色、敵人、場景與特效都是**程式即時繪製的數學圖形**；
所有音效與背景音樂都由 `tools/` 下的 Python 腳本合成。

> 專案位置：`C:\Users\user\Desktop\DC-like`
> 獨立專案，不在 `Code-Project/Project/` 之下；治理文件沿用 `Code-Project`
> 的專案層架構（README / AGENTS / MEMORY / current-state /
> Changing Description / output）。

---

## 1. 目前狀態：Milestone 1

**已經可以玩（全部鍵盤操作）：**

| 系統 | 內容 |
|---|---|
| 標題畫面 | 玫瑰窗 + Lissajous + phyllotaxis 的數學標題，Enter 進入 |
| 戰鬥手感 | 三段正弦劍、攻擊緩衝、翻滾無敵幀、取消窗口、hitstop、擊退、受擊硬直、鏡頭震動 |
| 武器（函數） | **J** 正弦劍（三段，第三段釋放行進波）、**K** 拋物線飛刀（自動解彈道）、**L** Aegis 極座標護盾（格擋 + 反擊波） |
| 防禦 | 翻滾無敵幀、Aegis 格擋、受擊後無敵、**Perfect Dodge**（翻滾穿過攻擊 → 25% 增傷 2.5 秒） |
| 敵人 | Husk（三角，近戰）、Watcher（圓+軌道，拋物線箭）、Ram（方，衝撞）、Bulwark（六角，正面免疫）、**The Warden**（五角+五芒星 Boss） |
| Build | 波間三選一（7 種 boon：生命/傷害/移速/無敵幀/飛刀/吸血/暴擊），鍵盤 1/2/3 或方向鍵+Enter |
| 循環 | 4 波（3 普通 + Boss）、波間回血、細胞掉落磁吸、死亡/通關結算、R 重來 |
| HUD | 生命、細胞、飛刀充能、Aegis 冷卻、波次、Boss 血條、連擊環、Perfect Dodge 計數、Build 摘要 |
| 視覺 | 零貼圖，全部 `MathArt` 參數化繪製；bloom + 暗角 + 對數螺線背景 |
| 音效 | 18 個程式合成 SFX + 32 秒無縫數學音樂循環 |

**刻意還沒有：**

- 房間拼接生成、Biome 規則（支柱 2）
- 完整 Build 系統：副武器格、技能格、突變、卷軸三色（目前是 7 種通用 boon）
- 永久解鎖 / 難度層級 / 存檔（支柱 4）
- 符文閘門與 metroidvania 地圖（支柱 5）
- 商店、設定選單、手把重綁、匯出 preset

---

## 2. 快速開始

需求：Godot **4.7.2**（GL Compatibility 渲染器）。引擎放在 `.tools/`
（已被 `.gitignore` 忽略）。

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

### 操作（完整鍵盤，不需要滑鼠）

| 動作 | 鍵盤 | 手把（額外） |
|---|---|---|
| 移動 | `A` / `D` 或 `←` / `→` | 左類比 |
| 跳躍 | `Space` / `W` / `↑` | A |
| 正弦劍（三段） | `J` / `Z` | X |
| 拋物線飛刀 | `K` | Y |
| Aegis 護盾 | `L` | LB |
| 翻滾 | `Shift` | B |
| 暫停 | `Esc` | Start |
| 重來（死亡或暫停時） | `R` | Back |
| 離開（暫停時） | `Q` | — |
| 標題畫面開始 | `Enter` / `Space` / `J` | — |
| 選擇 boon | `1` / `2` / `3`，或 `←` `→` + `Enter` | — |

**鍵盤完整保證**：所有操作都有鍵盤綁定，遊戲不綁定也不要求滑鼠。
`scripts/autoload/game.gd` 的 `_setup_input()` 是唯一註冊點；手把只是附加。

---

## 3. 目錄結構與檔案角色

```text
DC-like/
├── project.godot              # 引擎設定、autoload、視窗與渲染器
├── icon.svg
├── play.bat                   # 雙擊啟動
├── AGENTS.md                  # agent 入口 + Ponytail 規則 + 遊戲專案例外
├── MEMORY.md                  # durable 決策、指令、風險
├── Changing Description.txt   # 唯一的專案變更紀錄
├── data/
│   ├── weapons.json           # 武器資料（正弦劍三段）
│   ├── enemies.json           # 敵人資料（husk/watcher/ram/bulwark/warden）
│   └── rewards.json           # 7 種 boon
├── assets/audio/              # tools/make_sfx.py + make_music.py 產生
├── scenes/
│   ├── main.tscn              # 唯一關卡入口（只掛 main.gd）
│   ├── player.tscn            # Actor 根節點；子節點由程式組裝
│   └── enemy.tscn             # 同上
├── scripts/
│   ├── main.gd                # 啟動 world、HUD、標題、背景、encounter
│   ├── autoload/
│   │   ├── data.gd            # JSON 資料表載入
│   │   ├── sfx.gd             # 音效池 + 音樂循環
│   │   ├── combat.gd          # hitstop / shake / FX 生成
│   │   └── game.gd            # run state、combo、boon、輸入註冊
│   ├── systems/
│   │   ├── math_art.gd        # ★ 視覺語言：多邊形/星形/螺線/諧波/拋物線
│   │   ├── damage.gd          # 唯一的傷害公式
│   │   └── layers.gd          # 物理層 bit
│   ├── player/
│   │   ├── player.gd          # 移動、三段劍、飛刀、Aegis、Perfect Dodge
│   │   ├── player_visual.gd   # 程序化角色（正弦劍、Lissajous 圍巾）
│   │   └── player_camera.gd   # 跟隨、look-ahead、trauma shake
│   ├── enemies/
│   │   ├── enemy.gd           # 五種敵人 + Boss 三種攻擊模式
│   │   ├── enemy_visual.gd    # 幾何原型 + 真實彈道預覽
│   │   ├── projectile.gd      # 拋物線投射物 / 震波
│   │   └── cell_pickup.gd
│   ├── combat/
│   │   ├── hitbox.gd          # 近戰 hitbox（每揮只命中一次）
│   │   └── function_wave.gd   # 第三段釋放的正弦行進波
│   ├── world/
│   │   ├── arena.gd           # 手工競技場（碰撞 + 幾何繪製 + 出生點）
│   │   ├── braziers.gd        # 玫瑰線火焰 + phyllotaxis 餘燼
│   │   ├── runes.gd           # 漂浮多邊形符文
│   │   ├── motes.gd           # phyllotaxis 微粒場
│   │   └── encounter.gd       # 4 波 + Boss + boon 流程
│   ├── ui/
│   │   ├── hud.gd             # HUD / 暫停 / 結算 / Boss 血條
│   │   ├── reward_screen.gd   # 鍵盤三選一 boon
│   │   └── title_screen.gd    # 數學標題畫面
│   └── fx/                    # 火花、斬擊、傷害數字、殘影、粒子、環、碎裂、拋物線
├── shaders/                   # 背景螺線場、bloom、暗角
├── tests/                     # 無頭測試與截圖工具
├── tools/                     # 音效/音樂生成、Godot 下載、檢查腳本
├── docs/
│   ├── agent/                 # 冷啟動與交接
│   └── design/                # 五根柱子、手感調參、數學美術
└── output/                    # 截圖與匯出（gitignored）
```

### 三個刻意的設計選擇

1. **Actor 由程式組裝**：`player.tscn` / `enemy.tscn` 只有根節點，
   CollisionShape、Hitbox、Visual、Camera 都在 `_ready()` 建立。
   好處是沒有序列化資源要同步；代價是編輯器場景樹看不到細節。
2. **零外部資產**：角色與敵人是 `_draw()` 畫的，音效是 Python 合成的。
   沒有授權風險，改顏色/形狀不需要開繪圖軟體。
3. **數學是唯一視覺語言**：所有圖形都經過 `MathArt`，見
   [`docs/design/math-art.md`](docs/design/math-art.md)。

---

## 4. 資料驅動與調參入口

### 武器：`data/weapons.json`
每段攻擊的 `windup / active / recovery / cancel_at / lunge / damage /
knockback / hitstop / size / offset`。

### 敵人：`data/enemies.json`
`hp / speed / damage / attack_range / windup / active / recovery / lunge /
cooldown / color / body_radius / body_height`，外加
`shield`（Bulwark）、`boss` / `shockwave_*` / `charge_speed`（Warden）、
`projectile_speed`（Watcher）。

### Boon：`data/rewards.json`
`name / desc / color`，效果在 `Game.apply_reward()` 裡（目前 7 種）。

### 角色：`scripts/player/player.gd` 的 `@export`
跑速、加速度、重力、跳躍、coyote、buffer、翻滾、受擊、飛刀、Aegis。

### 傷害公式：`scripts/systems/damage.gd`

```text
最終傷害 = 基礎傷害 × (1 + 屬性 × 0.12) × 波次縮放 × boon 倍率 × (暴擊 ? crit_mult : 1)
```

暴擊條件：敵人處於預警/攻擊/收招（`is_exposed`），**或**玩家在其背後
（`is_backstabbed_by`）。Perfect Dodge 期間額外 ×1.25。

### 手感參數與理由
見 [`docs/design/combat-feel.md`](docs/design/combat-feel.md)。

---

## 5. 驗證

```powershell
powershell -ExecutionPolicy Bypass -File tools\check.ps1
```

依序執行：

```powershell
# 1. 匯入資源 / 編譯腳本
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path . --import

# 2. 資料、傷害公式、數學常數與彈道解（111 checks）
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_tests.gd

# 3. 真實輸入的戰鬥探針（命中、傷害、死亡、掉落、i-frames）
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path . tests\combat_probe.tscn

# 4. 鍵盤 boon 選擇器（暫停、1/2/3、方向鍵+Enter、效果）
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path . tests\reward_probe.tscn

# 5. 全流程 soak（五種敵人 + 4 波 + Boss + 勝利 + boon）
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path . tests\soak.tscn
```

### 視覺截圖（需要顯示器）

```powershell
# 標題畫面 + Enter 驗證
.\.tools\Godot_v4.7.2-stable_win64_console.exe --path . tests\title_capture.tscn

# 遊戲畫面
.\.tools\Godot_v4.7.2-stable_win64_console.exe --path . tests\capture_scene.tscn
```

輸出到 `output/screenshots/`：`00_title`、`01_idle`、`02_run`、`03_air`、
`04_attack`、`05_combo`、`06_finisher`、`06b_function_wave`、`07_roll`、
`08_kunai`、`09_aegis`、`10_bestiary`、`11_reward`、`12_pause`。

---

## 6. 目前已知限制

- **一張手工競技場**，沒有房間生成；波次是固定陣列。
- **沒有存檔與 meta 進度**；每次啟動都是新 run。
- **沒有設定選單**；輸入綁定在執行時註冊，重綁要改程式。
- 敵人站在平台上不會主動跳下；弓箭手會遠離玩家，可能走到平台邊緣掉下去。
- 遊戲內文字是英文（Godot 內建字型不含 CJK）；文件是中文。
- Bloom 是螢幕空間近似，不是真正的 HDR 管線。
- 匯出 preset 尚未建立。

---

## 7. 匯出成 exe（尚未設定）

1. 編輯器 → `Editor → Manage Export Templates → Download and Install`。
2. `Project → Export → Add... → Windows Desktop`。
3. 匯出到 `output/build/`（不要覆蓋專案根）。
4. 發佈時可勾選 `Resources → Embed PCK` 變成單一 exe；開發期建議
   `.exe` + `.pck` 分離。
5. Web 匯出適合早期給朋友試玩；手感仍以原生版為準。

---

## 8. 工作規則（給人與 agent）

- 先讀 `AGENTS.md`，再讀 `MEMORY.md` 與 `docs/agent/current-state.md`。
- 只改這個專案；不要碰 `Code-Project/` 的其他專案。
- 內容 schema（武器/敵人/boon/房間資料）視為「現在就該正確」的範圍，
  不受 Ponytail 的 YAGNI 裁決。
- **視覺只能透過 `MathArt`**；不要引入貼圖或 `Sprite2D`。
- **鍵盤優先**：任何新操作都必須有鍵盤綁定。
- 手感原型允許拋棄式程式碼，但放在 `tests/` 或明確標記。
- 設計決策要留下「為什麼選這個、放棄了什麼」兩行，寫進
  `docs/design/` 或 `MEMORY.md`。
- 不要引入任何 Dead Cells 的資產、反編譯輸出或數值表。
- 每次完成一個有意義的階段，更新 `docs/agent/current-state.md`；
  重要變更才更新 `Changing Description.txt`。
