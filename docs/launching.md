# 啟動與驗證規範

所有命令從專案根目錄執行。正常遊戲使用正式 Profile；驗證與截圖使用隔離 Profile。

## 安裝 Godot

1. 從 Godot 官方網站下載 **4.7.2 stable** 的 Windows 64-bit 標準版（非 .NET）。
2. 解壓縮，讓 `.tools\Godot_v4.7.2-stable_win64.exe` 存在。
3. 雙擊 `play.bat`，或執行 `.\.tools\Godot_v4.7.2-stable_win64.exe --path .`。

`.tools\` 不進版本控制；`play.bat` 找不到固定檔名時會提示並結束，不會自動下載。`tools/fetch_godot.ps1` 是手動安裝輔助工具，執行前請自行檢查。

## 現行入口

| 用途 | 入口 | 契約 |
|---|---|---|
| 正常遊戲 | 雙擊 `play.bat` | 啟動固定版本 Godot，使用正式三槽 Profile |
| 編輯器 | `.\.tools\Godot_v4.7.2-stable_win64.exe --editor --path .` | 不執行自動驗證 |
| 查看驗證計畫與期限 | `python tools/check.py --list` | 不需已安裝 Godot；這是目前期限的唯一來源 |
| 短驗證 | `python tools/check.py --fast` | 隔離 Profile；實際期限以 `--list` 顯示為準 |
| 指定驗證 | `python tools/check.py --only <regex>` | 匹配 display name 或 test path；零匹配失敗 |
| 完整驗證 | `python tools/check.py` | 先查 `--list`，再跑完整檢查與 seed sweep |
| 視覺驗證 | `python tools/check.py --capture <name>` | 需顯示器；隔離存檔；只管理本次啟動的程序 |
| runner 自檢 | `python tests/check_runner_probe.py` | 真實短程序、期限、輸出與 owned-process 清理 |
| CLI 存檔路徑自檢 | `python tests/profile_path_probe.py` | 等價路徑、正式檔覆寫拒絕與 hash 核對 |

`--capture` 支援（依 `tools/check.py` 的註冊順序）：`title`、`scene`、`impact`、`world`、`bloom`、`meta`、`jump`、`hud`、`vine`、`saves`、`l3`、`l4`、`l5`、`l6`、`terminal`、`reward`、`burstside`、`ui-product`。`--capture` 不能與 `--only`、`--fast` 或 `--turbo` 併用；`--turbo` 只是 fixed-fps smoke，不能作驗收。畫面輸出在 `output/screenshots/`（gitignored、可覆寫）。

不要在文件複製目前期限。測試計畫改變後，以 `python tools/check.py --list` 的實際輸出為準。

## 安全與存檔

- Python 標準庫 runner 是唯一建議驗證入口，直接以參數陣列啟動固定 Godot；使用明確退出碼與規則式錯誤行判定。
- 測試 Profile 由 runner 放在唯一隔離路徑。正式 slot1／slot2／slot3 的覆寫被拒絕；測試不得改寫 live save。
- 逾時或清楚的 script/scene error 只停止本次 owned process；Windows Job Object 管理其子程序，不按映像名稱掃殺其他 Godot。
- 不可用關閉防毒、全專案排除、編碼命令隱藏啟動或管理員重跑來繞過問題。
- 若防毒要求重新啟動或隔離檔案，先保存其他工作，再由使用者透過防毒 UI 操作。

## 生成物與匯出

```powershell
python tools\make_sfx.py
python tools\make_music.py
```

兩者只用 Python 標準庫，離線重新生成 `assets/audio/*.wav`；生成物不要手改。專案目前沒有 export preset，也沒有獨立 exe；Windows 匯出未驗證。需要時先從編輯器 `Editor → Manage Export Templates` 安裝模板，再使用 `Project → Export → Add... → Windows Desktop`，輸出到 `output/build/`，不要覆蓋專案根。開發期用 `.exe` + `.pck` 分離；發佈才考慮 embed PCK。Web 版只適合早期試玩，手感以原生版為準。

## 靜態邊界

`play.bat` 只切到專案目錄並啟動 `.tools/` 的固定 Godot。`tools/fetch_godot.ps1` 是手動安裝工具，遊戲與 runner 不會自動執行。`make_sfx.py`、`make_music.py` 使用標準庫離線生成 WAV。migration 的讀取鎖 fixture 只暫時開啟指定測試檔，不改 ACL、權限或正式存檔。

這是啟動與原始碼行為審查，不是防毒通行保證、Godot 二進位簽章驗證或完整惡意程式掃描。

## 設計取捨

選擇原生參數、唯一臨時 Profile 與 owned-process 管理，因為驗證不能碰玩家存檔，錯誤也必須可診斷。不新增啟動框架，也不要求停用防毒、全專案排除或管理員權限；這些不改善驗證契約。
