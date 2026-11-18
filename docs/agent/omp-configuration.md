# DC-like 的 OMP 分工與設定

更新：2026-11-18。本文擁有 DC-like 專案 OMP 分工與 Bili 連線邊界；Pi 端配置由 [pi-configuration.md](pi-configuration.md) 擁有。Dated runtime probes 只留在 `output/`，不在此重貼。

## 兩份配置的邊界

- 專案配置是 [`.omp/config.yml`](../../.omp/config.yml) 與 [`.omp/agents/`](../../.omp/agents/)；只控制 DC-like 的模型、角色、並發與禁用項。
- Bili 摘要服務設定在 `C:\Users\user\.config\billion-context\billion-context.json`，不屬 OMP 專案配置。修改後已啟動的服務需要 reload 或重啟；不能拿隔離 port 的結果冒充正式程序。
- OMP 的 `maxConcurrency=6` 是平台自己的上限；Codex 的主 agent 加三個子 agent slots 是另一套容量，兩者不互相校正。

## 當前模型分工

`modelRoles` 的 `default`、`slow`、`plan` 都是 `magpie/a6api-codex/gpt-6.1-sol`，`smol` 是 `magpie/a6api-deepseek/deepseek-v4.1-flash-1017`。`agentModelOverrides` 有七項最高優先級 pin：

| 角色 | 模型 | 工作 |
|---|---|---|
| `scout`、`ashfall-scout` | DeepSeek v4.1 Flash，低思考 | 有界唯讀調查、追呼叫關係、整理風險 |
| `task`、`ashfall-worker` | DeepSeek v4.1 Flash，max 思考 | 在指定檔案與範圍內實作、補測試和文件 |
| `reviewer`、`ashfall-reviewer` | GPT-6.1 Sol，高思考 | 獨立審查、找缺陷與缺證據 |
| `ashfall-validator` | DeepSeek v4.1 Flash，低思考 | 集中執行已安排的測試、截圖與輸入驗證 |

`scout`、`task` 與 `reviewer` 是 OMP 內建常用名稱的專案別名，內容與 `ashfall-*` 相同；日後修改要同步。`task.maxConcurrency=6`、`maxRecursionDepth=1`、`maxRuntimeMs=3600000`、`showResolvedModelBadge=true`。只禁用 `security-reviewer`、`seance`、`sonic`；子代理不能再往下派工。

## 載入與既有會話

Worker 思考級別只把 `ashfall-worker` 與同內容的 `task` 設為 `max`；其餘維持 scout／validator 的 low、reviewer 的 high、主代理預設 high。新派出的 child 才使用當前 pin；preflight reload 不會更新已啟動的 child，也不能用「檔案已改」推定舊 child 已變更。

獨立實作預設同時派三個 DeepSeek `ashfall-worker`；有更多互不重疊工作包時派四至五個，留位給審查；小事或高度耦合的修改用一個。六槽由所有角色實例共用，不是每個角色保留一槽。主代理先定共用介面及唯一 owner，再分配獨立可寫檔案、輸入與驗收條件；整合驗證前凍結來源，Godot／cache／視窗／截圖由單一 validator 集中處理。

`reviewer` 與 `ashfall-reviewer` 的 `tools` 是 `read/grep/glob/lsp`，工作指示禁止改檔和跑測試。這是專案檔案的唯讀審查角色，不是作業系統沙箱。使用者已停用遠端記憶服務，專案不依賴它。

## Bili 與摘要邊界

現行 shared 契約與 Pi 共用：

- DeepSeek 摘要 recipe 明確設定 `contextWindow=1048576`、`outputTokens=32768`、`stream=true`；空 recipe 會退回 128K/8K。
- target／total 上限 600,000 ms，target 不得超過 total；並發四、`maxSummaryBytes=65536`。
- `promptCache.routing=auto`；config PUT 與單純 reload 的行為不同，配置成功不等於上游採用 key。
- OMP adapter 會快取註冊時的 `maxToolDurationMs`；後端 reload 不會刷新已註冊工具。需要重新載入擴充套件或重開／恢復會話。工具逾時後先查 status／日誌，只補未完成範圍。
- 不能從磁碟版本、關閉的 port 或 routed requests 推斷 live 狀態；compression credit 是折疊量，不是帳單節省。

Provider cache 的單次低命中率不能證明 cache 損壞；Bili stamp、穩定的 `promptCacheKey` 與摘要失敗是不同層。要判斷 cache，需要原始 requests、usage 與同一 prefix 的相鄰比較，也不能承諾下一次命中率。

## 平常操作

建議在 DC-like 目錄新開 OMP 會話，讓當前角色與 Bili runtime 重新載入；既有 child 不保證立即更新。用 `/agents` 看角色，`/hub` 或 `/subagents` 看工作中的 child，`/model` 看解析模型，`/plan 任務` 處理大改動。若在 Magpie 改全域預設，專案 pin 仍優先；不要在兩邊反覆改同一項設定。

## 證據

Dated 證據保留在 `output/omp-bili-runtime-fix-2026-11-15/`、`output/bili-repair-2026-11-17/` 與 `output/omp-*`，只作歷史探測，不取代 live runtime 查詢。
