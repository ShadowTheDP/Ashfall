# DC-like 的 Pi 配置

更新：2026-11-18。這份文件擁有本專案 Pi 的角色、操作方式與驗證邊界；OMP 設定由 [omp-configuration.md](omp-configuration.md) 擁有。Dated runtime evidence 只留在 `output/` 與必要的研究註記，不在此重貼。

## 角色與分工

主代理讀資料、安排工作、檢查結果；實作交給 worker，獨立審查交給 reviewer，昂貴測試和 Godot 視窗集中交給 validator。四個自訂角色都在本專案 [.pi/agents](../../.pi/agents)，不裝成全局角色。

| 工作 | 模型 | 思考設定 | 工具範圍 |
|---|---|---|---|
| 主代理 | Magpie `a6api-codex/gpt-6.1-sol` | high | 讀取、搜尋、派工與驗收 |
| `ashfall-scout` | Magpie `a6api-deepseek/deepseek-v4.1-flash-1017` | low | 只讀專案 |
| `ashfall-worker` | 同上 DeepSeek | max | 指定檔案的編輯與 shell |
| `ashfall-reviewer` | 同上 6.1 Sol | high | 只讀獨立審查 |
| `ashfall-validator` | 同上 DeepSeek | low | 集中執行測試、生成證據；Godot MCP 僅限三個資料查詢 |

每個角色預設最長一小時，不准再生下一層子代理。director 採黑名單，拒絕主代理直接寫檔、shell、codemode 和繞過專案角色的派工入口；其他插件工具預設放行，仍受插件自身政策控制。直接派工六槽由 director 控制；工作流使用原生六槽排程，兩種派工不混跑。這不是作業系統沙箱，人工 slash 和子代理 shell 屬受信任操作。

Worker thinking 固定為 `max`；只保證新開的 worker run 使用它，已在執行的 child 與 resume 可能沿用舊 session 的層級。

## 派工與審查

角色是可重複派出的定義，不是每種角色各佔一槽。獨立實作預設同時派三個 DeepSeek `ashfall-worker`；有更多互不重疊工作包時派四至五個，留位給審查；小事或高度耦合只用一個。總上限六個子代理，一個 delegation level，不允許嵌套。

主代理先指定共用介面與唯一 owner，再分配互不重疊的檔案、輸入與驗收條件。調查結論共用，相關修正沿用同一 worker。整合驗證前凍結受測來源，由單一 validator 執行昂貴測試、Godot 與截圖；有影響的修正後重新凍結再驗。

原生 workflow 與直接派工都走 pi-subagents；有依賴的任務用原生 workflow 的 `runs.run`／`runs.all`，獨立任務可用 parallel。工作流內不指定子任務 `async:true`。審批摘要不是完整安全邊界，這是協作政策。

## Plan

Plan 預設允許專案讀取、`tool_search`、`web_enable`、`web_search`、`source_check`、`fetch_content` 和 `get_search_content`；寫檔、shell 和實作派工仍禁止。設定由 [.pi/pi-plan-mode.json](../../.pi/pi-plan-mode.json) 擁有；[ashfall-plan.ts](../../.pi/extensions/ashfall-plan.ts) 以原生 Plan 插件的 `settingsPath` 載入它。`.pi/settings.json` 停用同一 package 的自動 extension，避免重複註冊。

`/plan <需求>` → `/plan show` → `/plan implement` 是建議流程；完整互動 implement 路徑未經人工驗收。Plan 內禁止啟動、恢復或追問實作子代理。改設定後重開本專案 Pi 才會完全生效；既有計畫可能保留原工具選擇，先 `/plan exit` 再重開。

## 本地記憶

使用者已關閉 Magpie Memory。本專案不依賴遠端記憶服務；記憶使用 [MEMORY.md](../../MEMORY.md)，目前狀態由 [current-state](current-state.md) 擁有。

## Bili 邊界

官方 Bili 由使用者在 Magpie 管理；專案不固定附著 port、不包 wrapper、不改全局設定。摘要服務的 shared 設定在 `C:\Users\user\.config\billion-context\billion-context.json`，不屬 Pi／OMP 專案配置。

2026-11-18 的現行契約：

- 摘要 recipe 明確設定 DeepSeek `contextWindow=1048576`、`outputTokens=32768`、`stream=true`；空 recipe 會退回 128K/8K，不能拿模型的 1M 宣稱已生效。
- target／total 時限以官方上限 600,000 ms 為上限，target 不得超過 total；並發四、`maxSummaryBytes=65536`。這些是後端設定，不等於每個已註冊客戶端已刷新 manifest。
- `promptCache.routing=auto` 由使用者要求開啟；config PUT callback 會刷新 `opts.promptCache`，單獨 reload 不會。配置成功不等於上游採用 key 或命中率改善。
- 工具逾時可能發生在後端仍繼續工作時；先讀 status／日誌，只重試未完成範圍。`t0:error` 與真正的長度拒絕 `invalid_summary` 是不同問題；compression credit 是折疊量，不是帳單節省。
- 不能從磁碟版本、關閉的 port 或 routed requests 推斷 live 狀態；需要 query 實際 runtime。全域 npm 與 Pi 自管套件可能不同步，版本以 live `bili --version` 為準。

## Godot MCP

[.pi/mcp.json](../../.pi/mcp.json) 固定本地 Godot MCP 包與 Godot 4.7.2 路徑；伺服器預設 hidden，只對 `get_godot_version`、`list_projects`、`get_project_info` 設 direct。三項已用真實 stdio MCP 查詢成功；不透過 MCP 開遊戲、開編輯器、匯入、改場景或更新 UID。hidden 是曝光設定，不是作業系統沙箱。

## 怎麼用

```powershell
Set-Location 'C:\Users\user\Desktop\DC-like'
pi.cmd
```

| 指令 | 用途 |
|---|---|
| `/director` | 看本專案權限、四種角色與六槽限制 |
| `/subagents-fleet`、`/subagents` | 子代理工作與管理入口 |
| `/plan <需求>`、`/plan show`、`/plan implement` | 產生、查看、執行計畫 |
| `/plan save`、`/plan exit` | 保存會話計畫；exit 取消並丟棄 ready／saved／active plan |
| `/run ashfall-worker <明確任務>` | 人工直接派工備用入口 |
| `/subagents-stop`、`/subagents-steer` | 人工停止／追問；長任務強制停止尚未驗證 |
| `/subagents-models`、`/subagent-cost` | 看模型選項與用量 |
| `/mcp` | MCP 連線與曝光管理 |
| `/model`、`/thinking` | Pi 原生主代理設定，不會同步修改角色固定模型 |

平衡質量、等待與花費：獨立實作預設三個 DeepSeek worker，可拆分時用四至五個；小事只派一個。主代理與 reviewer 用較強模型把關，實作與查檔交 DeepSeek。修改角色或派工說明後重開本專案會話；只改 `/model` 不會讓所有角色一起換模型。

## 驗證與限制

- 固定包、四角色真實解析與 resource resolver 已確認；真實 DeepSeek worker 以固定模型與 thinking 完成隔離 marker 寫入，父會話保持存活至 terminal 後得到原生 `attested`。這是子代理自證，不是獨立 reviewer 驗收。
- 真實長任務強制停止、steer、reviewer 模型呼叫和子代理 Godot 呼叫尚未驗收；四角色原生工具 allowlist 與空 extensions 已解析，但不宣稱完整 OS 隔離。
- 證據保留在 `output/pi-configuration-2026-11-15/`、`output/pi-six-slot-workflow-2026-11-16/`、`output/pi-native-workflow-2026-11-16/`、`output/pi-plan-web-2026-11-17/` 與 `output/pi-director-blacklist-2026-11-17/`；不作現行 live 壓縮或付費吞吐保證。
