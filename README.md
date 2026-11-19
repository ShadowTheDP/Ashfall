# Ashfall（DC-like）

原創 roguelite／metroidvania 動作遊戲。只借類型與公開設計概念；不含 Dead Cells 的程式碼、美術、音效、關卡或數值表。角色、場景與特效都由 `scripts/systems/math_art.gd` 即時繪製，音效與音樂由 `tools/` 的 Python 腳本合成。

產品目標：[GOALS.md](docs/GOALS.md) · 目前狀態與人工 gate：[current-state](docs/agent/current-state.md) · 視覺規格：[ui-system](docs/design/ui-system.md) · 治理與硬約束：[AGENTS.md](AGENTS.md)。本 README 只負責目的、啟動、操作、入口與指令。

## 目前範圍

Delivery A 是合法九訪問、三 Boss 的 0 BSC 主路線，加上同一 Profile 的 Silt Cistern 替代路線與第 1–8 步 UI 成熟度增量；UI 已完成工程實作與有限視覺，最終 gate 見 [current-state](docs/agent/current-state.md)。擴充世界、BSC 1–5 玩法、新機制、重平衡、DLC、連線與替換存檔政策都未授權。

已核准且唯一的 UI 執行計畫：[ASHFALL_UI_IMPROVE_PLAN.md](ASHFALL_UI_IMPROVE_PLAN.md)。第 1–8 步（內附 CJK 字型與繁中／英文雙語文字層、原生 InputMap 共用輸入層與鍵盤／手把導覽、設定頁與偏好儲存、戰鬥 HUD 與暫停 Build 摘要、比較／商店、服務、地圖／存檔／結果與狀態回饋）已完成工程實作與有限視覺；最終 gate、證據與已知限制只以 [current-state](docs/agent/current-state.md) 為準；最終自動與有限視覺 gate 已 PASS（見 RESULT），人類、實體手把與 Windows export 仍待。第 1 步含 Collector 鬼影複核；第 2 步的 13 個 `--fast` 組別全數通過；第 3 步含原生匯入、headless／display 擷取與原生視窗；第 4 步以唯讀 `GearPresentation` 投影、正式 HUD 幾何，以及短鍵帽與計時器的實際畫面完成有限視覺驗收。

人類 UI 美術／理解與真人雙路線驗收仍待完成；自動測試、截圖與模型看圖不能代替。實際進度、證據與限制只看 [current-state](docs/agent/current-state.md)，人工流程見 [delivery-a-human-check](docs/agent/delivery-a-human-check.md)。歷史 UI 看圖入口是 [review-index.html](output/ui-maturity-2026-11-16/review-index.html)；第 4 步最終證據是 [step4-evidence.json](output/ui-product/step4-evidence.json)。兩者都不代替真人驗收。

## 啟動

需求：Godot **4.7.2**、GL Compatibility。引擎放在 `.tools/`（gitignored）。初始視窗 1536×960；遊戲以 768×480 邏輯解析度開啟，可拖曳縮放，16:10 以外的比例以黑邊維持。

```powershell
# 第一次：從 Godot 官方 4.7.2 release 下載並解壓到 .tools\
# 啟動、防毒與驗證規範：docs/launching.md

.\play.bat

# 直接跑遊戲
.\.tools\Godot_v4.7.2-stable_win64.exe --path .

# 開編輯器
.\.tools\Godot_v4.7.2-stable_win64.exe --editor --path .
```

專案根是 `C:\Users\user\Desktop\DC-like`。不要碰其他專案，也不要改 `.tools/`、`.godot/`、`output/` 或 `assets/audio/*.wav` 等生成物。

## 操作（完整鍵盤）

所有操作都有鍵盤綁定，不需要滑鼠；手把是附加路徑，軟體綁定已就位，但實體手把尚未驗證。實際註冊點是 `project.godot` 的原生 InputMap；`scripts/autoload/interface.gd` 只負責套用 locale／input 覆寫、最後裝置與提示文字，各頁仍自己處理焦點、捲動與確認。

| 動作 | 按鍵 |
|---|---|
| 移動 | `A` / `D` 或 `←` / `→` |
| 跳躍 | `Space` / `W` / `↑` |
| 武器一／二（盾也用武器槽） | `1` / `2`；武器一相容 `J` / `Z` |
| 技能一／二 | `Q` / `E`，相容 `K` / `L` |
| 翻滾（每次離地一次） | `Shift` |
| 互動／治療 | `R`／`F` `H` |
| 暫停／返回 | `Esc` |
| 放棄該局 | 暫停：`Enter` 開確認再 `Enter` 提交；死亡：`Enter` 重試 |
| 暫停詳情／回標題／離開 | `1`–`5` 選裝備、`↑`/`↓` 捲動；`T` 回標題（落在 Saves）、`Q` 離開 |
| 標題 main 動作 | `W`/`S` 選 Continue／Enter Hub、New run、Saves、Quit；`Enter` 開啟 |
| 標題 Saves 三槽 | `A`/`D` 或 `W`/`S` 選槽；`Enter` 開啟；`Esc` 返回 main |
| 覆蓋 checkpoint 的新局 | `N` 後再按 `N` 或 `Enter` 確認；`Esc` 取消 |
| 大廳站台／下降門 | 靠近按 `J` / `Enter` |
| 地圖／世界圖 | `Tab` 開關，`←`/`→` 切頁，`Esc` 關閉 |
| 藤蔓／牆面 | 靠近 `W`/`↑` 攀爬；藤蔓 `S`/`↓` 下降；`Space` 跳離 |
| 下穿／下砸 | 地面 `S+Space` 下穿 one-way；空中 `S+Space` 下砸 |
| Checkpoint 傳送 | 近已啟用點按 `R`；地圖 `↑`/`↓` 選點、`Enter` 確認 |
| Scroll | `1`/`2`/`3` 或 `A`/`D` 預覽，`Enter` 提交；`↑`/`↓` 捲詳情 |
| 裝備比較／替換 | `R` 開；`1`/`2` 或 `A`/`D` 選槽；`Enter` 替換＋回收；`X` 回收候選；`Esc` 離開 |
| Passage 服務 | `W`/`S` 或 `↑`/`↓` 選列；`Enter` 提交；`Space`/`Esc` 返回 |

鍵盤焦點與取消語意由各面板常駐按鍵列顯示；不要加 mouse-only 操作。

## 檔案入口

```text
project.godot                 引擎、autoload、視窗與渲染設定
play.bat                      雙擊啟動
AGENTS.md                     治理、read order、授權與硬約束
ASHFALL_UI_IMPROVE_PLAN.md    唯一 UI 執行計畫（1–8 工程與有限視覺完成；最終 gate 見 current-state）
MEMORY.md                     持久偏好與可重用實作教訓
data/*.json                   canonical 武器、敵人、房間、路線與經濟資料
scenes/main.tscn              唯一產品入口
scripts/main.gd               標題、Hub、node 轉場、Passage 與結算流程
scripts/autoload/profile.gd   唯一持久存檔 writer
scripts/autoload/interface.gd locale／input 覆寫、最後裝置與操作提示
scripts/autoload/game.gd      run state、路線與資源
scripts/systems/run_build.gd  局內裝備 UID、charges、三軸與 wallet
scripts/systems/math_art.gd   唯一視覺語言與幾何 primitive
scripts/world/biome_gen.gd    正式 biome／room module 組裝
scripts/world/level.gd        房間啟動、碰撞、掉落、出口與 discovery
scripts/ui/                   HUD、地圖、標題、獎勵與其他面板
scripts/ui/settings_screen.gd 設定頁、草稿／預覽與重綁流程
scripts/ui/gear_presentation.gd 裝備玩法摘要的唯讀顯示投影
scripts/meta/                 Hub、Passage、Collector 與永久進度
tests/                        headless checks、fixtures 與 capture probes
tools/check.py                唯一驗證入口與檢查計畫
docs/                         GOALS、PRODUCT、design／agent 契約與研究參考
output/                       gitignored 截圖、報告與匯出
```

`data/*.json` 是內容與數值的 canonical 來源；不要在 script 重抄武器表、敵人 stats 或路線契約。資料 schema、生成、存檔與 runtime ownership 見 [PRODUCT.md](docs/PRODUCT.md) 與 `docs/design/*.md`。舊五層 `data/floors.json`／`rooms.json`、`LevelGen` 與 arena 只保留給 legacy fixtures，不是正式完成標準。

畫面與手感：768×480 邏輯、可縮放視窗（初始 1536×960）、120 Hz physics、`physics_interpolation=true`、浮點座標；玩家是正方形，敵人是純多邊形，沒有手腳或臉。詳細理由見 [math-art](docs/design/math-art.md)、[combat-feel](docs/design/combat-feel.md) 與 [impact](docs/design/impact.md)。

## 驗證

`python tools/check.py` 是唯一入口；目前預設是最新路徑的 **13 個檢查**，不是舊的完整清單。`--list` 免 Godot 列出目前計畫與期限；`--only` 以不分大小寫的正則匹配名稱或路徑，零個匹配會失敗。不要用舊的秒數或舊 `ALL CHECKS PASSED` 當現在證據。

```powershell
# 看目前檢查與期限（不需 Godot）
python tools/check.py --list

# 日常 focused / 內圈
python tools/check.py --only profile_migration_probe
python tools/check.py --fast

# 目前預設
python tools/check.py

# Runner 與 Profile 路徑安全
python tests/check_runner_probe.py
python tests/profile_path_probe.py

# 重新生成音效／音樂
python tools\make_sfx.py
python tools\make_music.py
```

- 其他 probe 用 `--only` opt-in，900s L6 與 focused Passage 也是 opt-in。九個只測退役五層生成器的 probe 已刪除，不再註冊；歷史 bytes 只在 `output/` 的 dated 證據。
- `--fast` 只把 generation sweep 改成 **4 seeds**（完整預設 **32 seeds**）；其他 probe 是否執行只由 `--only` 決定。
- 測試使用隔離 Profile；`tools/check.py` 拒絕把 live Profile 當測試目標。不要手動覆寫、刪除或重置 live saves。
- 腳本／場景錯誤、普通 `ERROR:`、非零退出與 timeout 都不能算通過。已知 WAV 關閉參考與 Camera2D interpolation warning 仍會出現；沒有 zero-warning 主張。
- 文件變更只需 link／consistency 檢查，不必跑 Godot；改 runtime 或 UI 時只跑受影響的 focused check，再跑適用的整合 gate。

視覺截圖需要顯示器，使用隔離存檔，不進 headless gate：

```powershell
python tools/check.py --capture title
python tools/check.py --capture scene
python tools/check.py --capture impact
python tools/check.py --capture meta
python tools/check.py --capture bloom
python tools/check.py --capture l4
python tools/check.py --capture hud
python tools/check.py --capture saves
python tools/check.py --capture l6
python tools/check.py --capture ui-product
```

輸出在 `output/screenshots/`（mutable；需要凍結證據時看 pass manifest 與 owned captures）。完整 launching、capture alias 與 Profile 隔離規則見 [launching.md](docs/launching.md)。

## 匯出

目前沒有 export preset，也沒有 exe；Windows export 尚未驗證。設定時從編輯器 `Editor → Manage Export Templates` 安裝模板，`Project → Export → Add... → Windows Desktop`，輸出到 `output/build/`，不要覆蓋專案根。開發期用 `.exe` + `.pck` 分離；發佈才考慮 embed PCK。Web 版只適合早期試玩，手感仍以原生版為準。

## 已知限制

雙語文字層已接線：首次預設繁體中文、英文為回退，內附 Noto Sans CJK TC，原生翻譯由 `data/localization/ui.csv` 匯入；設定頁、偏好儲存、介面語言切換與重綁已通過 STEP 3 工程驗收（原生匯入、headless／display 擷取與原生視窗），第 4 步 HUD／暫停 Build 摘要已通過工程與有限視覺驗收，但仍無實體手把（含拔除）、真人導覽、音訊關閉參考、motion frames 或 HUD／pause／compare／settings 全表面視窗縮放證據。BSC 1 只解鎖、不能選來玩；沒有無盡模式、任意幀世界存檔或完整擴充世界。Camera2D、audio shutdown、GLES3 MSAA、MbedTLS warning、Windows export 憑證、實體 controller 與 zero-warning 仍未驗證。最新邊界以 [current-state](docs/agent/current-state.md) 為準，不要從舊文件複製狀態。

## 工作規則

每次有意義的階段更新 [current-state](docs/agent/current-state.md)；狀態、證據與限制以它為唯一 owner。所有美術走 MathArt，粒子走 `Juice.*`（`ShatterFx` 的輪廓碎片是窄例外），鍵盤存取不可退化，`Profile` 是唯一存檔 writer。不要 reset／revert／commit／push 未經要求，也不要引入 Dead Cells 資產、反編譯輸出或數值表。完整治理、委派與硬約束見 [AGENTS.md](AGENTS.md)。
