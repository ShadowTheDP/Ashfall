# 啟動與驗證規範

所有命令從專案根目錄執行。正常遊戲使用正式 Profile；驗證與截圖使用隔離 Profile。

## 現行入口

| 用途 | 入口 | 契約 |
|---|---|---|
| 正常遊戲 | 雙擊 `play.bat` | 啟動固定版本 Godot，使用正式三槽 Profile |
| 編輯器 | `.\.tools\Godot_v4.7.2-stable_win64.exe --editor --path .` | 不執行自動驗證 |
| 查看驗證計畫與各步期限 | `python tools/check.py --list` | 不需已安裝 Godot；這是 current per-step deadline 的唯一來源 |
| 短驗證 | `python tools/check.py --fast` | 隔離 Profile；實際期限以 `--list` 顯示為準 |
| 指定驗證 | `python tools/check.py --only <regex>` | 匹配 display name 或 test path；零匹配失敗 |
| 完整驗證 | `python tools/check.py` | 先查 `--list`，再跑完整步驟與 seed sweep |
| 視覺驗證 | `python tools/check.py --capture <name>` | 需顯示器；隔離存檔；只管理本次啟動的程序 |
| runner 自檢 | `python tests/check_runner_probe.py` | 真實短程序、期限、輸出與 owned-process 清理 |
| CLI 存檔路徑自檢 | `python tests/profile_path_probe.py` | 等價路徑、正式檔覆寫拒絕與 hash 核對 |

`--capture` 支援 `title`、`scene`、`impact`、`meta`、`bloom`、`jump`、`world`、`hud`、`vine`、`saves`、`l3`、`l4`、`l5`、`l6`、`terminal`、`reward`、`burstside`。`--turbo` 只是 fixed-fps smoke，不能作驗收。

不要在文件複製目前期限。測試計畫改變後，以 `python tools/check.py --list` 的實際輸出為準；歷史 log 中的秒數只證明當時執行結果。

## 安全與存檔

- Python 標準庫 runner 是唯一建議驗證入口，直接以參數陣列啟動固定 Godot；使用明確退出碼與規則式錯誤行判定。
- 測試 Profile 由 runner 放在唯一隔離路徑。正式 slot1／slot2／slot3 的覆寫被拒絕；測試不得改寫 live save。
- 逾時或清楚的 script/scene error 只停止本次 owned process；Windows Job Object 管理其子程序，不按映像名稱掃殺其他 Godot。
- 不可用關閉防毒、全專案排除、編碼命令隱藏啟動或管理員重跑來繞過問題。
- 若防毒要求重新啟動或隔離檔案，先保存其他工作，再由使用者透過防毒 UI 操作。

## 靜態邊界

`play.bat` 只切到專案目錄並啟動 `.tools/` 的固定 Godot。`tools/fetch_godot.ps1` 是手動安裝工具，遊戲與 runner 不會自動執行。`make_sfx.py`、`make_music.py` 使用標準庫離線生成 WAV。migration 的讀取鎖 fixture 只暫時開啟指定測試檔，不改 ACL、權限或正式存檔。

這是啟動與原始碼行為審查，不是防毒通行保證、Godot 二進位簽章驗證或完整惡意程式掃描。

## Historical evidence (not current rules)

以下日期與數字是已發生的事故或診斷紀錄。它們不解釋目前 per-step 期限，也不授權恢復舊 runner。

- **2026-10-27 Avast：** 使用者回報 `IDP.HELU.PSE95`，對象是已退役的 `tools/check.ps1`／PowerShell 啟動鏈。當時入口含 encoded command、ExecutionPolicy bypass 與名稱掃殺；現行 Python runner 已移除這些行為。
- **2026-11-06 import gate：** `--import` 本身會等待資源掃描後退出；舊 runner 曾省略多餘的 `--quit`。當時修正與失敗比較保存在 `output/ui-refinement-map-2026-11-04/verification/`。
- **2026-11-15 import diagnosis：** 兩次舊期限嘗試分別在約 10 秒停在 import／editor teardown，沒有明確 script error。使用者其後授權以較寬的 import-only runner margin診斷；一次 focused run 原生完成 5.54 秒、exit 0。詳細 argv、log 與隔離 Profile 在 [`output/color-2026-11-15/import-deadline-adjustment.json`](../output/color-2026-11-15/import-deadline-adjustment.json)。兩次歷史失敗保留，根因未由較快成功單獨證明。
- **歷史完整套件：** 舊 Fast/Full、V1、display 與 timeout 紀錄只存在 dated logs／history，不能代替目前 `--list` 計畫或本輪結果。

## 設計取捨

選擇原生參數、唯一臨時 Profile 與 owned-process 管理，因為驗證不能碰玩家存檔，錯誤也必須可診斷。放棄恢復被攔截的 PowerShell 鏈、停用防毒或新增啟動框架；這些不改善驗證契約。
