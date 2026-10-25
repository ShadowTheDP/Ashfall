# 程序生成：beat sheet + 手寫房間模板（單色、MathArt）

本文件固定 Ashfall 地圖生成的做法、為什麼這樣做、以及放棄了什麼。
程式碼：`scripts/world/level_gen.gd`（純資料層）、`scripts/world/level.gd`
（碰撞與執行）、`data/rooms.json`（手寫模板）、`data/floors.json`（每層的
beat sheet）。測試：`tests/gen_stats.tscn`、`tests/audit_v1.tscn`、
`tests/audit_a3.tscn`、`tests/map_capture.tscn`。

---

## 1. 參考：Dead Cells 的六步混合法

Sebastien Bénard 的〈The Level Design of Dead Cells: a hybrid approach〉把
他們的流程拆成六步：固定框架 → 手寫房間 tiles → 每層的 concept graph →
依 graph 挑選合規的 tile → 依戰鬥房間長度決定敵人數量 → 配置掉落。核心論點
是「generation 只決定**哪一塊**手寫內容放在**哪裡**，不決定內容長什麼樣」。

Ashfall 採用同樣的分工，但用自己的資料格式重寫，沒有引用任何 Dead Cells
的程式、資料或美術：

| Dead Cells | Ashfall | 檔案 |
|---|---|---|
| 手寫房間 tile | 每種 room kind 2-3 個手寫模板 | `data/rooms.json` |
| concept graph | 每層的 beat sheet（role 序列） | `data/floors.json` `beats` |
| 依 node 挑合規房間 | `_pick_template()` 依 kind + 最小寬度挑 | `level_gen.gd` |
| 依戰鬥長度決定敵人數 | `_plan_enemies()` 依 role 權重分配**既有總數** | `level_gen.gd` |
| 地面/寶箱配置 | `_caches()`、`_annexes()` | `level_gen.gd` |
| 保證連通 | `_verify()` BFS + `_reach()`/`_headroom()` | `level_gen.gd` |

## 2. Beat sheet（每層的性格）

`data/floors.json` 每一層帶一個 `beats` 陣列，長度等於 `rooms`。
目前房間數 8 / 9 / 10 / 11 / 3（同一寬度下每間約 700 px），所以一層讀起來是
一連串緊湊的垂直房間，而不是一排寬闊大廳；代價是整包 `check.ps1` 從 ~350 s
變成 ~470 s。role
決定這一間房吃哪種 kind、以及吃多少敵人預算：

| role | kind 池 | 敵人權重 | 用途 |
|---|---|---:|---|
| `entry` | gate | 0.0 | 第一間。永遠空的：玩家要先讀懂關卡 |
| `combat` | gate / hall / bridge | 1.0 | 主戰 |
| `climb` | shaft / well | 0.45 | 垂直房，戰鬥之間換氣 |
| `treasure` | vault / bridge | 0.7 | 高處有加倍寶箱 |
| `elite` | hall / vault | 1.45 | 高強度，boss 層的前導房 |
| `exit` | hall | 1.0 | 有 gate 的最後一間 |

`roles[0]` 永遠被強制成 `entry`、`roles[last]` 永遠是 `exit`，資料寫錯也
不會生成出不連通的一層。

**為什麼**：舊版是「N 間隨機 kind 排成一列」，同一層換個 seed 就變成另一條
毫無關係的走廊。beat sheet 讓 seed 只改變「排法」，層的**性格**（哪裡該爬、
哪裡該打、哪裡有寶）是設計者寫的。
**放棄了什麼**：真正的手繪地圖。beat 的順序仍是一維的，沒有 Dead Cells 那種
非線性的多分支圖 —— 要做的話下一步是讓 beats 帶分支深度。

## 3. 房間模板（`data/rooms.json`）

每一種 kind 有 2-3 個手寫變體，格式：

```
["d", x, tier, w, oneway]   deck，頂面在 slab + tier*92；oneway 1 = 可從下方跳穿
["m", x, tier, w, h]        solid mass，頂面在 slab + tier*92，向下 h px；tier 可為小數
```

x、w 是房間寬度的比例。所有模板都遵守兩個不變量，且由程式保證：

1. 每一層面都在「爬上來的那一層面」一次跳躍（<= `MAX_UP` 100 px）之內。
2. 任兩個重疊表面的**頂面**至少相距 `BODY_HEADROOM` (72 px)。
   注意這比對的是頂面：一個 26 px 的實心塊放在上一層（92 px）時，實際淨空
   是 66 px，而這正是 `SPAWN_LIFT` 調參的對象（見 `level_gen.gd` 的註解）。

**為什麼**：模板是「手感」的載體。`hall_gallery_run` 的整片 90% 高台、
`well_double` 的兩道牆之間的口袋、`bridge_high_line` 的上層捷徑，這些是
設計判斷，不是隨機能生出來的。
**放棄了什麼**：房間內部的隨機性。同一個模板每次長得一樣；變化來自模板數量
（目前 18 個）與擺放順序。

### 3.1 窄縫自動關閉

`_close_narrow_holes()`：同一 tier 上兩個 one-way deck 之間若出現
`0 < gap < SLOT+12`（58 px）的窄縫，會把左邊那片延伸過去填平。
**為什麼**：玩家站在高台上、下方是一道 40 px 的縫時，任何近戰敵人都上不去，
而 gate 要求全滅 → 這是真的 softlock。`_reach()` 不看遮蔽物，抓不到這種情形，
所以由生成階段直接保證。`tests/climb_probe.tscn` 是這個不變量的見證。

## 4. Annex：上層路線的目的地

`_annexes()` 每層在 1-2 間房的**既有最高平台**上再長兩層（一層 rung、一層
240 px 寬的房間），房間裡放這層最貴的寶箱（2×`value`），兩側有矮牆。

**為什麼**：gallery 讓上層「連貫」，但沒有「目的地」——走上層只是換條路走。
annex 讓爬上去有回報，且它接在房間自己已經在爬的路線上，不是旁邊另外架一道
梯子。
**放棄了什麼**：annex 裡沒有敵人。要放的話得先證明那隻敵人可被殺，否則
`enemies_remaining()` 永遠不會歸零。目前只放寶箱。
其他細節：annex 的柱位會被 `_in_annex_span()` 排除（巨柱本來會穿過房間）；
相機上限由 `main.start_floor()` 依「最高表面 + 半個視窗」計算（audit_v3 直接
檢查這個不等式，不再寫死 -600）。

## 5. 敵人分配

`_plan_enemies()` 只決定**既有總數**放在哪一間，不增不減（audit_a3/v2 直接
驗證 `enemies_remaining()` 等於 `data/floors.json` 的總和）。重體（bulwark /
charger / warden）先選房間、每間最多一隻；`entry` 永遠是 0。
**為什麼**：把 3 隻 grunt 平均丟進每一間，就是「每間房都一樣難」。
**放棄了什麼**：真正的 LFD "AI Director" 動態調整。這裡是靜態的 beat 權重。

## 5.1 撿到的細胞在 gate 開啟後直接入庫

`Game.bank_cells_now`：gate 一開，這趟就再也輸不掉了，所以此時撿到的細胞
直接 `Profile.bank()`，不再進 `run_cells`。走往 gate 的路上殺掉的敵人會掉細胞，
而那段 1.6 s 的過場以前會把這堆一起清掉。

## 6. 驗證

| 檢查 | 內容 |
|---|---|
| `LevelGen._verify()` | 從起點 BFS 所有表面；房間 slab 或任何 deck 不可達 → 重試（最多 8 次）|
| `gen_stats` | 100 個 (floor, seed)：寬度、房間數、gallery 數、cache 數、annex 數、雙倍寶箱存在 |
| `audit_v1` | 40 seeds × 5 層的實際走位、單向平台、gate 柱狀判定 |
| `audit_a3` | spawn 不埋進地形、gate 可達、房間可進入 |
| `climb_probe` | 近戰敵人真的爬得上 gallery |
| `map_capture` | 每層全景 + 每間房截圖（需顯示器）|