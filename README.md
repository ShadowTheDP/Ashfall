# Ashfall

**原創 2D 動作 roguelite，幾何風格，所有圖形由程式即時繪製。** 沒有外部美術資產，音效與音樂同樣由專案內腳本合成。從標題進入 Hub，展開一條九次區域訪問、三場 Boss 戰的主線；解鎖後可改走 Silt Cistern 替代路線，再合流。死亡或放棄會回到 Hub，勝利則結算永久進度。

Ashfall 目前是**開發中的可玩版本**，尚未提供獨立執行檔或發行版。主線、替代路線、三存檔槽與主要介面均已可用；真人試玩、實體手把與 Windows 匯出仍在驗證。

## 啟動（Windows）

需求：Windows 64-bit、Godot **4.7.2 stable**（標準版，非 .NET）、GL Compatibility 渲染。

1. 從 Godot 官方網站下載 4.7.2 stable 的 Windows 64-bit 版本。
2. 解壓縮，讓 `.tools\Godot_v4.7.2-stable_win64.exe` 存在（`.tools\` 不進版本控制）。
3. 雙擊 `play.bat`。引擎不在固定位置時，`play.bat` 會提示並結束，不會自動下載。

```powershell
.\play.bat

# 開編輯器
.\.tools\Godot_v4.7.2-stable_win64.exe --editor --path .
```

遊戲以 768×480 邏輯解析度繪製，初始視窗 1536×960，可自由縮放；非 16:10 比例以黑邊維持。安裝、啟動與存檔隔離細節見 [docs/launching.md](docs/launching.md)。

## 操作

核心操作全部可用鍵盤完成，不需要滑鼠。實際綁定位於 `project.godot` 的 InputMap；可在遊戲內 **設定 → Controls** 重新綁定鍵盤與手把按鍵。

| 動作 | 預設按鍵 |
|---|---|
| 移動 | `A` / `D` 或 `←` / `→` |
| 跳躍 | `Space` / `W` / `↑` |
| 攀爬／下降 | 牆面或藤蔓 `W` / `↑` 攀爬；藤蔓 `S` / `↓` 下降 |
| 下穿／下砸 | 地面或空中 `S` + `Space` |
| 攻擊（武器一） | `J` / `Z` / `1` |
| 武器二 | `2` |
| 技能一／二 | `Q` / `E`（相容 `K` / `L`） |
| 翻滾 | `Shift` |
| 互動／傳送 | `R` |
| 治療 | `F` 或 `H` |
| 地圖 | `Tab` |
| 暫停／返回 | `Esc` |
| 選單確認 | `Enter` 或 `Space` |

各面板的其餘快捷鍵會顯示在畫面按鍵列。手把的軟體綁定已就位，實體手把仍待驗證。

## 目前可玩內容

- 九次區域訪問、三場不同 Boss 戰的 0 BSC 主線，含 checkpoint 續玩與勝利結算。
- Silt Cistern 替代路線，同一存檔解鎖，取得不同藍圖後與主線合流。
- 三個獨立存檔槽、永久進度、局內 Build／裝備比較、商店與服務、地圖與雙語介面（繁體中文／英文）。
- 尚未提供：更高難度循環的完整玩法、無盡模式、連線、DLC 或關卡／數值擴充。

## 專案結構

```text
project.godot                 引擎、InputMap、視窗與渲染設定
play.bat                      雙擊啟動
scenes/main.tscn              唯一產品入口
scripts/main.gd               標題、Hub、轉場與結算
scripts/autoload/             Profile、Interface、Game
scripts/systems/              RunBuild、MathArt 與戰鬥系統
scripts/world/                biome／room 組裝與房間流程
scripts/ui/                   HUD、地圖、設定與各面板
data/*.json                   內容、數值與路線資料
tests/                        headless 測試與畫面擷取
tools/check.py                唯一驗證入口
docs/PRODUCT.md               產品、架構、數值與存檔契約
docs/design/                  操作手感、美術、路線等設計文件
docs/launching.md             安裝、啟動、驗證與匯出
```

內容與數值以 `data/*.json` 為唯一來源；架構與資料契約見 [docs/PRODUCT.md](docs/PRODUCT.md)，設計理由見 [docs/design/](docs/design/)。

## 開發

```powershell
python tools/check.py --list    # 列出目前檢查，不需 Godot
python tools/check.py --fast    # 短驗證，使用隔離存檔
python tools/check.py           # 完整驗證
```

驗證與存檔隔離規則見 [docs/launching.md](docs/launching.md)。

## 原創界線

本專案只借用類型與公開設計概念；不含任何 Dead Cells 的程式碼、美術、音效、關卡或數值表。內附 Noto Sans CJK TC 字型（SIL OFL 1.1）。
