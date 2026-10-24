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

## 1. 目前狀態

**現在跑的是一輪完整的 roguelite：標題 → 大廳 → 第 1–5 層 → 回大廳，永久進度寫在
`user://ashfall_profile.json`。全部鍵盤操作。**

| 系統 | 內容 |
|---|---|
| 啟動路徑 | `scenes/main.tscn` → `scripts/main.gd`。`start_mode` 預設 `""`，沒設 `skip_title` 時解析成 `"hub"`，所以**正式遊戲是標題 → 大廳**，不是競技場。Arena + Encounter + Runes/Braziers/Motes 只在 `start_mode == "arena"` 時建立，今天等於只有測試 harness |
| 標題畫面 | 玫瑰窗 + Lissajous + phyllotaxis 的數學標題；期間整棵樹暫停，`Enter` / `Space` / `J` 開始 |
| 大廳（Hub） | 1600 px 可行走大廳，4 座站台 + `x=1560` 的下降門。靠近（REACH 70）+ `J` 開站台：**UPGRADES**（HubUi 列表）、**SKILLS**（技能樹 11 節點）、**ARCHIVES**（3 分頁 bestiary/weapons/armour）、**CHARACTER**（6 種身體）。門：`A`/`D` 在 1..`best_floor+1` 之間切換樓層，`J` 下降。同一時間只開一個面板（`Main._any_panel_open()`） |
| 關卡生成 | `main.start_floor()` 先釋放上一份地形、開新 `Player`，再 `Level.build(floor, randi())` → `LevelGen.generate()`：垂直多層，連續底邊 + 高 0–96 px 的石板、每層 `TIER = 92` px、2–5 層；單向平台（可往上穿過，虛線底緣）與實心塊並存；6 種房間原型 gate/hall/shaft/vault/bridge/well；房間之間有柱子強迫垂直移動；BFS 驗證可達 |
| 樓層流程 | 進入房間矩形 → 生成該房敵人；全層敵人清空 → 出口門開啟；走進門柱（`\|dx\| < 62`、`\|dy\| < 260`）→ 發 `cleared` |
| 結算 | 清層 → `Game.finish_floor()` 立刻入帳 → 大廳；死亡 → `Game.end_run(false)`，未入帳的 cells 消失 → 大廳；清完第 5 層 → `Game.end_run(true)`，入帳 + 1 soul → 大廳 |
| 戰鬥手感 | 三段正弦劍、攻擊緩衝、翻滾無敵幀、取消窗口、hitstop、擊退、受擊硬直、鏡頭震動；狀態機 IDLE/RUN/AIR/ROLL/ATTACK/HURT/DEAD |
| 移動 | 300 px/s、跳躍 −630、coyote 0.10 s、jump buffer 0.12 s、翻滾 640→200 px/s 0.30 s、i-frames 0.03–0.24 s |
| 武器（函數） | **J** 正弦劍（三段，第三段釋放行進波）、**K** 拋物線飛刀（自動解彈道）、**L** Aegis 極座標護盾（格擋 + 反擊波）。6 把武器，每把帶 `attribute`：brutality（紅）或 tactics（紫） |
| 防禦 | 翻滾無敵幀（首尾各 1 幀白框提示）、Aegis 格擋（實心扇形→擴散環）、受擊 4 射線、**Perfect Dodge**（i-frames 內被命中：8 射線 + 2 幀凍結 + 25% 增傷 2.5 秒 + 返還一把飛刀） |
| 敵人 | 7 種：Husk（三角，近戰）、Watcher（圓+軌道，拋物線箭）、Ram（方，衝撞）、Bulwark（六角，正面免疫）、Spitter、Leaper、**The Warden**（五角+五芒星 Boss） |
| 局內 Build | 兩色 build：boon 升自己那色的等級，武器依 `attribute` 縮放（`Damage.ATTR_SCALE = 0.12`／級）。每層的 boon 預算來自 `data/floors.json` 的 `reward`（2/2/3/3/0），**每清一個房間發一次**，鍵盤 `1`/`2`/`3` 或方向鍵+Enter，標題讀 `ROOM CLEARED` |
| 永久進度 | `Profile`：cells、souls、9 種升級（7 個用 cells、brutality/tactics 用 souls）、11 個技能節點、3 本圖鑑、6 種身體 / 6 把武器 / 5 件護甲的解鎖與選擇、`best_floor`、統計 |
| HUD | 生命、細胞、飛刀充能、Aegis 冷卻、`FLOOR n / 5` 與剩餘敵人、Boss 血條、連擊環、Perfect Dodge 計數、Build 摘要（真的列出拿過的 boon） |
| 視覺 | **768×480 單色**（整數 x2 = 1536×960）；零貼圖，全部 `MathArt` 幾何繪製 |
| 動畫 | 蓄力 → 實心 smear → 2 幀白色 impact → 10–14° overshoot → 二次運動延遲 |
| 角色 | **玩家是正方形**，每次跳躍翻轉 90° 落在新的一面；敵人全是純多邊形，**沒有手腳**，手是一個點 |
| 粒子 | Godot 內建 `CPUParticles2D`（`scripts/systems/juice.gd`），9 種預設 |
| 打擊感 | 四級強度（2/4/6/8 幀 hitstop）、方向性火花、擴張環、1 幀白閃、斷開弧線斬痕（`SlashFx`）、zoom punch、暗角脈衝 |
| 音效 | 18 個程式合成 SFX + 32 秒無縫數學音樂循環 |

**刻意還沒有：**

- 匯出 preset（沒有 exe；見 §7）
- CJK 字型，所以遊戲內文字是英文，沒有中文 UI
- 第二隻 Boss（只有第 5 層的 The Warden）
- 無盡模式 / 難度層級
- metroidvania 閘門（符文門、地圖）
- 房間插座式拼接生成：`LevelGen` 是「底邊 + 石板 + 房間」的程序生成，不是手工房間模組拼接
- 多存檔槽（單一 `user://ashfall_profile.json`）
- 商店、設定選單、手把重綁

---

## 2. 快速開始

需求：Godot **4.7.2**（GL Compatibility 渲染器）。引擎放在 `.tools/`
（已被 `.gitignore` 忽略）。建議螢幕至少 1536×960，因為視窗以整數 ×2 開啟。

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
| 大廳：開站台（靠近時） | `J` / `Enter` | — |
| 大廳：下降（門口） | `J` / `Enter` | — |
| 大廳：切換樓層（門口） | `A` / `D` 或 `←` `→` | — |
| 面板內：移動 / 確認 / 關閉 | 方向鍵或 `WASD` / `J` `Enter` `Space` / `Esc` | — |
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
│   ├── floors.json            # 5 層：名稱、寬度、房間數、敵人表、reward 預算
│   ├── weapons.json           # 6 把武器（三段 combo + attribute 顏色）
│   ├── enemies.json           # 7 種敵人（grunt/archer/charger/bulwark/spitter/leaper/warden）
│   ├── rewards.json           # 7 種局內 boon
│   ├── upgrades.json          # 9 種永久升級（7 個 cells + brutality/tactics souls）
│   ├── skill_nodes.json       # 11 節點技能樹
│   ├── characters.json        # 6 種可選身體（hp/speed/jump/passive）
│   └── armor.json             # 5 件護甲
├── assets/audio/              # tools/make_sfx.py + make_music.py 產生
├── scenes/
│   ├── main.tscn              # 唯一入口（只掛 main.gd）
│   ├── player.tscn            # Actor 根節點；子節點由程式組裝
│   └── enemy.tscn             # 同上
├── scripts/
│   ├── main.gd                # 啟動、標題、大廳/樓層切換、boon 預算、層間轉場
│   ├── autoload/
│   │   ├── data.gd            # JSON 資料表載入
│   │   ├── profile.gd         # ★ 唯一的存檔讀寫：永久解鎖、升級、技能、圖鑑
│   │   ├── sfx.gd             # 音效池 + 音樂循環
│   │   ├── combat.gd          # hitstop / shake / FX 生成
│   │   └── game.gd            # run state、combo、boon、樓層流程、輸入註冊
│   ├── systems/
│   │   ├── math_art.gd        # ★ 視覺語言：多邊形/星形/螺線/諧波/拋物線
│   │   ├── damage.gd          # 唯一的傷害公式（含 ATTR_SCALE）
│   │   ├── juice.gd           # 粒子預設（包裝 CPUParticles2D）
│   │   ├── geom3d.gd          # 3D→2D 投影（Warden Boss 用）
│   │   └── layers.gd          # 物理層 bit
│   ├── meta/
│   │   ├── hub.gd             # 大廳：可行走地面、4 站台、下降門、樓層選擇
│   │   └── hub_ui.gd          # UPGRADES / CHARACTER 面板（列表 + 卡片）
│   ├── player/
│   │   ├── player.gd          # 移動、三段劍、飛刀、Aegis、Perfect Dodge、loadout
│   │   ├── player_visual.gd   # 程序化角色（正弦劍、Lissajous 圍巾）
│   │   ├── weapon_visual.gd   # 6 種武器幾何（curve/lens/fractal/chain/orbit）
│   │   └── player_camera.gd   # 跟隨、look-ahead、trauma shake
│   ├── enemies/
│   │   ├── enemy.gd           # 七種敵人 + Boss 三種攻擊模式
│   │   ├── enemy_visual.gd    # 幾何原型 + 真實彈道預覽
│   │   ├── projectile.gd      # 拋物線投射物 / 震波
│   │   └── cell_pickup.gd
│   ├── combat/
│   │   ├── hitbox.gd          # 近戰 hitbox（每揮只命中一次）
│   │   └── function_wave.gd   # 第三段釋放的正弦行進波
│   ├── world/
│   │   ├── level.gd           # 一層：碰撞、房間觸發、出口門、room_cleared/cleared
│   │   ├── level_gen.gd       # 純資料關卡生成（(floor, seed) → 佈局，BFS 驗證）
│   │   ├── arena.gd           # ⚠ 競技場模式專用（手感 fixture）
│   │   ├── encounter.gd       # ⚠ 競技場模式專用：4 波導演
│   │   ├── braziers.gd        # 玫瑰線火焰 + phyllotaxis 餘燼（arena 專用）
│   │   ├── runes.gd           # 漂浮多邊形符文（arena 專用）
│   │   └── motes.gd           # phyllotaxis 微粒場（arena 專用）
│   ├── ui/
│   │   ├── hud.gd             # HUD / 暫停 / 結算 / Boss 血條 / Build 摘要
│   │   ├── reward_screen.gd   # 鍵盤三選一 boon（ROOM/WAVE CLEARED）
│   │   ├── archive_screen.gd  # ARCHIVES：bestiary / weapons / armour 三分頁
│   │   ├── skill_tree.gd      # SKILLS：11 節點、需前置、cells 付費
│   │   └── title_screen.gd    # 數學標題畫面
│   └── fx/                    # 火花、斬擊、傷害數字、殘影、粒子、環、碎裂、拋物線
├── shaders/                   # 背景螺線場、bloom、暗角
├── tests/                     # 無頭測試與截圖工具
├── tools/                     # 音效/音樂生成、Godot 下載、檢查腳本
├── docs/
│   ├── PRODUCT.md             # 業務文檔：產品定義、架構、循環、數值、驗證
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
3. **數學是唯一視覺語言，而且是單色、流暢優先的**：邏輯解析度 768×480、
   整數 ×2、浮點座標（不做像素吸附）、120 Hz 物理 + 插值、完全沒有色相。
   見 [`docs/design/math-art.md`](docs/design/math-art.md)。

---

## 4. 資料驅動與調參入口

### 樓層：`data/floors.json`
五層：`name / rooms / width / enemies / boss / palette / reward`。
`reward` 是該層總共發幾個 boon（2/2/3/3/0），由 `Main` 按「每清一房扣一」花完。

| 層 | 名稱 | 寬度 | 房間 | 敵人 | reward |
|---|---|---:|---:|---:|---:|
| 1 | THE ASH GATE | 4200 | 4 | 6 | 2 |
| 2 | THE HOLLOW STAIR | 5200 | 5 | 10 | 2 |
| 3 | THE GEAR VAULT | 5600 | 5 | 11 | 3 |
| 4 | THE QUIET FOUNDRY | 6400 | 6 | 15 | 3 |
| 5 | THE WARDEN'S THRONE | 2600 | 2 | 5 + Boss | 0 |

### 武器：`data/weapons.json`
每段攻擊的 `windup / active / recovery / cancel_at / lunge / damage /
knockback / hitstop / size / offset / tier / blade`；每把武器另外有
`attribute`（`brutality` 或 `tactics`）與 `crit_multiplier`。

### 敵人：`data/enemies.json`
`hp / speed / damage / attack_range / windup / active / recovery / lunge /
knockback / cooldown / cells / color / body_radius / body_height`，外加
`shield`（Bulwark）、`boss` / `knockback_scale` / `shockwave_*` / `charge_speed`（Warden）、
`projectile_speed`（Watcher）。

### Boon：`data/rewards.json`
`name / desc / color`，部分帶 `attribute`（`brutality` / `tactics`）決定它升哪一色；
效果在 `Game.apply_reward()` 裡（目前 7 種）。

### 永久進度：`data/upgrades.json` / `data/skill_nodes.json`
升級：`stat / per_level / max / cost / cost_step / currency`（預設 `cells`，
`brutality` 與 `tactics` 是 `souls`）。技能節點：`stat / per_level / cost / requires / at`。
兩者都只透過 `Profile.bonus(stat)` 進到戰鬥。

### 身體與護甲：`data/characters.json` / `data/armor.json`
身體：`hp / speed / jump / knives / passive / cost / unlock_floor`。
護甲：`hp / damage_taken / speed / iframe / knives / cost`。
`Player._apply_loadout()` 把兩者加上 `Profile.bonus()` 後寫進 `@export`。

### 角色：`scripts/player/player.gd` 的 `@export`
跑速、加速度、重力、跳躍、coyote、buffer、翻滾、受擊、飛刀、Aegis。
這些是**基準值**：實際值由 `_apply_loadout()` 依 body / 護甲 / 永久升級覆寫（可重複呼叫，不會累加）。

### 傷害公式：`scripts/systems/damage.gd`

```text
最終傷害 = 基礎傷害 × (1 + 屬性等級 × 0.12) × (暴擊 ? crit_mult : 1)

基礎傷害 = 武器段傷害 × Game.total_damage_mult() × permanent_damage_mult
屬性等級 = 局內該色 boon 數 + Profile.bonus(colour)（souls 升級）
```

`Damage.compute(base, attr, crit, crit_mult, scale = 1.0)` 是唯一入口，
`ATTR_SCALE = 0.12`。暴擊條件：敵人處於預警/攻擊/收招（`is_exposed`），
**或**玩家在其背後（`is_backstabbed_by`）。Perfect Dodge 期間 `total_damage_mult()`
額外 ×1.25。飛刀固定算 tactics。

### 手感參數與理由
見 [`docs/design/combat-feel.md`](docs/design/combat-feel.md)。

---

## 5. 驗證

```powershell
powershell -ExecutionPolicy Bypass -File tools\check.ps1
```

依序執行（今天實跑：`ALL CHECKS PASSED`，exit 0）：

| 階段 | 目標 | 驗證什麼 |
|---|---|---|
| import | `--import` | 資源匯入、腳本編譯 |
| run_tests | `tests/run_tests.gd` | 資料表、傷害公式、數學常數、彈道解（**111 checks**） |
| combat_probe | `tests/combat_probe.tscn` | 真實輸入的命中、傷害、死亡、i-frames |
| reward_probe | `tests/reward_probe.tscn` | 鍵盤 boon 選擇器（暫停、1/2/3、方向鍵+Enter） |
| soak | `tests/soak.tscn` | 競技場模式全流程：全部敵人 + 4 波 + Boss + 勝利 |
| esc_probe | `tests/esc_probe.tscn` | 大廳面板開/關/購買、Esc 只關一個 panel |
| floor_probe | `tests/floor_probe.tscn` | 大廳 → 樓層的交接（相機 limits、地形釋放） |
| run_probe | `tests/run_probe.tscn` | 完整 run：5 層 → 勝利 |
| audit_a1 | `tests/audit_a1.tscn` | 戰鬥 / 武器 |
| audit_a2 | `tests/audit_a2.tscn` | 存檔 / 經濟（**123 checks**） |
| audit_a3 | `tests/audit_a3.tscn` | 層 / 出生點（5 層 × 15 seeds） |
| audit_a4 | `tests/audit_a4.tscn` | UI / 輸入（**226 checks**） |
| audit_v1 | `tests/audit_v1.tscn` | 垂直可達性（5 層 × 40 seeds） |
| audit_v2 | `tests/audit_v2.tscn` | 敵人 / 遭遇 |
| audit_v3 | `tests/audit_v3.tscn` | run 流程 / 進度（**162 checks**） |

單獨跑某一項：

```powershell
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_tests.gd
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path . tests\run_probe.tscn
```

### 視覺截圖（需要顯示器，不進 headless 驗證）

```powershell
.\.tools\Godot_v4.7.2-stable_win64_console.exe --path . tests\title_capture.tscn    # 標題
.\.tools\Godot_v4.7.2-stable_win64_console.exe --path . tests\capture_scene.tscn    # 遊戲畫面
.\.tools\Godot_v4.7.2-stable_win64_console.exe --path . tests\impact_capture.tscn   # 逐幀打擊
.\.tools\Godot_v4.7.2-stable_win64_console.exe --path . tests\jump_capture.tscn     # 逐幀翻面
.\.tools\Godot_v4.7.2-stable_win64_console.exe --path . tests\meta_capture.tscn     # 大廳與 meta 面板
```

輸出到 `output/screenshots/`（gitignored）。

---

## 6. 目前已知限制

- **單一存檔槽**：只有 `user://ashfall_profile.json`，沒有多槽、沒有備份回滾。
- **輸入只能改程式**：綁定在 `game.gd._setup_input()` 執行時註冊，沒有設定選單。
- **敵人不會為了追擊而跳下平台**（卡牆時只會反向加一次小跳）；弓箭手仍可能走到平台邊緣掉下去。
- **沒有中文 UI**：Godot 內建字型不含 CJK，遊戲內文字是英文；文件是中文。
- **沒有第二隻 Boss**：只有第 5 層的 The Warden；也沒有無盡模式 / 難度層級。
- **匯出 preset 尚未建立**（沒有 exe）。
- Bloom 是螢幕空間近似，不是真正的 HDR 管線。

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
- **不要新增色相**；所有顏色必須來自 `MathArt` 的灰階梯度。
- **不要為角色加手腳或眼睛**；手是一個點，臉不存在。玩家是純正方形。
- **打擊感規格見 `docs/design/impact.md`**；改動前先讀，改動後跑
  `tests/impact_capture.tscn` 逐幀檢查。
- 粒子用 `Juice.*`（包裝 `CPUParticles2D`），不要自己寫粒子模擬。
- **鍵盤優先**：任何新操作都必須有鍵盤綁定。
- 手感原型允許拋棄式程式碼，但放在 `tests/` 或明確標記。
- 設計決策要留下「為什麼選這個、放棄了什麼」兩行，寫進
  `docs/design/` 或 `MEMORY.md`。
- 不要引入任何 Dead Cells 的資產、反編譯輸出或數值表。
- 每次完成一個有意義的階段，更新 `docs/agent/current-state.md`；
  重要變更才更新 `Changing Description.txt`。
