# Ashfall UI system — current spec

本文件只保留現行 UI 規格與理由。歷史階段、舊截圖帳本、灰階違規與失效位置已刪除。

第 1–8 步已完成工程實作與有限視覺；自動與有限視覺 gate 已 PASS，人類、硬體與 export 仍待，故不得把下列契約當成人類驗收通過。以下幾何、符號與文案是凍結來源的實際契約，不是計畫目標；也不改變鍵盤完整可用、MathArt、768×480 邏輯尺寸與 Profile 唯一 writer 等既有不變條件。

## 目標

UI 借用 Dead Cells 可觀察的功能分組與導覽，不複製其版面、文字、資產或動畫；表達必須是 Ashfall 原創 MathArt。玩家應在 768×480、鍵盤完整可用且不需滑鼠的條件下，先看懂現在能做什麼、代價與真實後果，再讀細節；手把走同一組語意與焦點，提示隨最後有效裝置切換。

視窗可縮放：設計尺寸仍是 768×480 邏輯，`aspect=keep` 與連續縮放只放大整張畫面；非 16:10 留黑邊，UI 不重排、不縮字。

參考來源只有一份：[Dead Cells UI reference atlas](../research/dead-cells-ui-reference-atlas-2026-11-04.md)。原圖與 manifest 留在既有 research／output；本文件不重貼大表、不嵌入原作圖片。

## 色彩與文字

- 世界、角色、FX、UI 共用 MathArt navy／slate／cream 明度層與語意色：Gold 焦點／Gold、mint 玩家、coral 危險／Brutality、violet Tactics、green 治療／Survival、cyan Cells／拾取。`axis_color(axis)` 是三軸唯一入口，biome palette 只提供地點氣氛。
- 色彩不能是唯一訊號：形狀、輪廓、文字、LOCKED／CHOSEN 與數字後果必須同時可讀。
- 必要文字與按鍵最小 11px；頁標 24、物件名 16、正文 13、必要次要文字／鍵帽 11，不另外縮字。多行間距用 `MathArt.ui_line_height(size)`，不得小於字型實際高度；危險、價格、確認與存檔失敗不可省略或縮小。
- 長文字用 `MathArt.ui_wrap(value, width, size)` 換行；單行空間不足用 `ui_short(value, width, size)` 加 `…`，不得硬切字形。`ui_heading` 只畫 96px 短規線，不用滿版標題線。
- 換行交給 TextServer 的 `TextParagraph`：中文在字元邊界、英文在單字邊界，明確換行與空白行保留；行首從 grapheme 邊界取回，內容不遺失。`ui_short` 只在 grapheme 邊界截斷後加 `…`。
- 排版結果依（文字、寬度、字級、locale）快取，上限 256 筆、滿了就整批清除；頁面每幀只查快取，不重新 shape 全文，locale 或字型變更自然換 key 重排。
- `MathArt.ui_wrap` 第一遍仍是原生自適應排版，沒有換掉正常路徑。只有實測超寬的行才用相同字級與寬度重建新的 `TextParagraph`，以 `MANDATORY | GRAPHEME_BOUND` 重排；正常單字、CJK、locale 與 256 筆快取行為不變。根因是引擎硬斷行後不重設 `word_count`，換行後才出現的長 token 可能溢出；不得為此加自製 parser 或手動 ASCII 切字。
- 選這個：只對實測超寬行做原生 grapheme-bound fallback，正常英文單字與中文換行不受影響；放棄：全域套用 grapheme flag，會把正常英文單字切開。
- 選這個：保留 TextServer 為唯一換行權威；放棄：自製 parser 或手動 ASCII 切分，行為會與引擎分岐且難以對齊 locale。
- 已執行的 retry 7 顯示 Archive 280-token、換行後出現的完整失敗原因可讀並能捲到終端，PASS；整體 product 仍在下一項 Skill fixture 失敗，尚無全數通過的宣稱。

## 文字字型與語言

- 唯一外部資產：`assets/fonts/NotoSansCJKtc-Regular.otf`（Noto Sans CJK TC Regular，固定 commit `165c01b46ea533872e002e0785ff17e44f6d97d8`，SHA-256 `dce08bd4fd91aa8aa76ed8fea4b694c2dfb8550f67871e326843212ddbeb88b4`）。這是本案核准的**窄例外**：只用於文字渲染；幾何、圖示與所有美術仍由 MathArt 產生，不引入外部圖示或美術字型。
- 授權與出處：SIL OFL 1.1，`assets/fonts/OFL.txt` 為同 commit 的原始授權，`assets/fonts/PROVENANCE.md` 記錄來源、雜湊與字型內建著作權聲明。只交付 Regular 一個字重。
- `MathArt.ui_font()` 是唯一載入點；缺檔或讀不到時必須 `push_error`，不得用系統 fallback 假裝中文字型已交付。玩家機不依賴作業系統字型。
- 語言：首次預設 `zh_TW`，`en` 為回退；`project.godot` 以 `internationalization/locale/translations` 註冊 Godot 原生 CSV 匯入產生的 `data/localization/ui.<locale>.translation`，並設定回退 locale 與 Text Server 資料。`data/localization/ui.csv`（欄位固定 `keys,en,zh_TW`，引號內可含換行）是唯一手寫來源；靜態文案用 `UI_*` key；內容名稱用 `<FAMILY>_<ID>_NAME`／`_TEXT`（id 不縮寫、不以 raw ID 當玩家名稱）；動態句用命名 placeholder。官方流程見 <https://docs.godotengine.org/en/stable/tutorials/i18n/localization_using_spreadsheets.html>。生成檔不手改、不當成執行期 fallback 機制。
- 這兩個生成資源必須與 `ui.csv` 一起交付：全新專案啟動時，`locale/translations` 的註冊清單即可直接解析，不需要任何執行期 fallback 或 bootstrap 程式碼。原生編輯器匯入會由 `ui.csv` 重建它們（首次實測 `--import` 6.76 s PASS；日期、大小與雜湊屬當次證據，不寫死在此文件），因此不得手改、不得以固定雜湊當版本條件、也不各自維護翻譯；唯一手寫來源仍是 `ui.csv`，且不自動提交，所有未提交變更由使用者審閱。
- 機器值（Profile 狀態、`lock_reason`、存檔錯誤原因）保持英文 canonical，只在顯示邊界翻譯；錯誤顯示為「本地化前綴＋原始可診斷原因」，不得吞掉原因或改寫比較用的值。
- 統一術語：Gold＝金幣、Cells＝細胞、Scroll＝卷軸、Mutation＝突變、Collector＝收藏者、Forge＝鍛造、Passage＝中繼站、Blueprint＝藍圖、Brutality／Tactics／Survival＝暴虐／戰術／生存；「本局」與「永久」全頁一致。

## Surface 與圖示

- `MathArt.ui_panel(canvas, rect, selected := false)`：安靜 `BG_0` 面；只有 selected 才加短 `ACCENT` 頂邊與 2px 左軌。
- `MathArt.ui_surface(canvas, rect, focused := false, opaque := false)`：第四個參數留給「卡片本身就是 surface」的頁面；compare、title、shop／Collector 卡片用 `opaque = true`。HUD 的不透明底板由 `_plate` 另行處理，不是這個參數。
- 每個 modal 只有一層 `INK` α0.82 遮罩；run-over 保留 α0.97。compare 只有一層遮罩，不再疊 page panel。
- 圖示只用 `ui_gear`、`ui_service`、`ui_axis`、`ui_axis_emblem` 與 `axis_color`；沒有貼圖、Sprite2D、icon sheet 或外部圖示。唯一外部資產是文字字型（見下節），不是美術。

## 頁面規則

### HUD 與暫停
- 左下是一組生存區：flask `Rect2(16,362,42,56)`；四件可操作裝備 `Rect2(x,362,56,56)`，x 固定 `[66,124,190,248]`，兩武器與兩技能中間保留分組空隙；護符 `Rect2(314,362,36,56)`；三軸小列 baseline y434；HP `Rect2(16,440,334,24)`。`equipment_rects()` 仍是五個裝備槽的唯一幾何入口，flask 不加入該陣列。短名稱可 `…`，完整名稱在暫停頁；近戰不顯示假 1/1 或假充能，盾／技能才顯示真實 charges／cooldown。
- 右下 minimap `Rect2(588,346,164,84)`；wallet／timer `Rect2(554,432,198,32)`，底部不超過 y464。兩者使用不透明底板，避免世界幾何被讀成 UI；Boss 血條獨立。兩行 11px 使用實際 `MathArt.ui_line_height(11)` 的 16px 基線步距，Gold 與本局攜帶 Cells 分行；一般戰鬥不顯示 Visit／BSC 第二行，移到 map／pause。
- 選這個：wallet／timer 保留計畫的 554／432／198 寬位與 11px 兩行，把高度改為 32，讓 16px 行距的兩個 line box 完整呈現，文字不被裁切也不縮級。
- 放棄：沿用計畫原本的 26px 高；兩個 11px／16px 行距的基線無法在 26px 內完整呈現，只能裁切或縮字，違反「關鍵文字不縮小」規則。
- 全頁 modal（build／map／Collector／archive／skill／hub panel／settings／reward／title）開啟時，`Hud._draw()` 不再繪製戰鬥 equipment／vitals／wallet／minimap／announce，世界只在單層 α0.82 遮罩後；頁面自己提供錢包與操作。pause 與結果頁只畫自己的一套資訊。
- 暫停用 WEAPONS／SKILLS／PASSIVE 分組與五個裝備焦點；右側先玩法摘要再完整機制／詞綴／數值，Controls 不再接在裝備長文末端。詳情捲動區固定 `Rect2(328,176,388,136)`；狀態／三軸／Mutation 使用實際 11px 行高 16px 的基線 334／350／366（軸圖示在 344、標籤在 350），Mutation 的 11px descender 約到 370，仍在操作列頂端 y376 之上。這是與 wallet `Rect2(554,432,198,32)` 相同的實際字型高度修正，不縮字。
- 裝備摘要只由 `GearPresentation.describe(build, item)` 的唯讀投影產生：`name`／`playstyle`／`condition`／`headline` 與 `details` 都取自 canonical `RunBuild`、`Data` 與既有 combo 資料，不建立第二份傷害、充能或交易計算。空槽／缺 definition 回本地化空槽且不讀缺失欄位；完整名稱只在 details 出現一次，critical 機制不被截斷。
- 鍵帽由 action 生成；在 56px HUD 卡內，`PgUp`／`PgDn`／`Bksp` 使用有限、標準且無歧義的縮寫，保留 11px 完整鍵身分，不裁切也不縮字；其他按鍵沿用 OS／既有標籤 fallback。這不是另一套 formatter framework，binding／InputMap／Interface API 不變。長短提示與真實卡片冷卻文字依實際卡片位置配置，不以重疊或縮字換取空間。
- 底部操作列固定五項：繼續、設定、存檔、放棄本局、離開，位置 `Rect2(52+i*134,376,128,28)`。X（手把同為 X）切換裝備／操作列焦點；左右移焦點、上下捲詳情，Enter／A 執行操作列，Esc／B 返回最近一層或繼續。裝備區 Enter／A 移到操作列的繼續，不直接放棄；既有 T／Q／S 捷徑保留，但不得是唯一入口。
- checkpoint 儲存失敗時，操作列改為四項：「重試儲存／回復檢查點／設定／離開」，四項都可聚焦；不能先解除暫停。
- 選這個：暫停頁操作列讓局內動作都有可聚焦入口，重綁與手把導覽永遠有真實路徑，存檔失敗也能就地重試。
- 放棄：把 T／Q／S 熱鍵與裝備詳情末端附帶的 Controls 當成唯一入口；它們無法用手把焦點抵達，也讓閱讀與操作混在一起。

### Scroll 與比較
- Scroll 是三張 212×242 軸卡，位置 `Rect2(52+n*226,110,212,242)`；選中卡連到真實 build 投影，Enter 才消耗，NO HEAL 基線在卡內相對 y232。
- Scroll 詳情三行在 y386／402／418，最後一行不越過 y440 的 key band；body 在卡內重排，不縮字。
- 比較頁（已實作）：候選卡 `Rect2(52,110,664,164)`，左欄先玩法、條件與真實 headline，右欄只放價格、選中槽回收額、交易後餘額與不足額；付款順序固定先付原價、再回收舊件。目標卡 `Rect2(52+n*338,294,326,104)`（單槽時寬 664），只留槽名、同類 headline 差額、短玩法與真實充能；完整明細收斂到共用底部兩行（y416／432，顯示範圍在 y287），鍵列統一 y452。`BuildScreen.item_details()`／`_gear_lines()` 與其字串解析已退場，`Hud` 直接使用 `GearPresentation.describe()`；`tests/l3_build_probe.gd` 只移除過時 helper 斷言，probe 仍是預設 gate。
- 選這個：讓「怎麼玩、換哪槽、付多少」在同一視線完成；放棄：每張卡各自捲動並固定刪行，使同一事實分散在版面各處。
- 比較只改 UI 投影，不寫 canonical UID／charges／wallet；價格、回收、餘額與錯誤都來自同一交易入口；不足原價時即使回收後足夠也不得先買。

### 商店
- 世界商品保留 name、price 與 `R`；提示卡最多 304×154，跟隨真實商品並 clamp 在 `Rect2(16,16,736,320)` 安全區。
- 若即時公告與提示衝突，且商品上方、下方都放不下，提示延後（defer）；公告與購買資訊都不遮住。提示只畫，`R` 仍開原本 compare，不新增購買路徑。
- 提示內容（已實作）：依序物件名→玩法兩行→真實 headline→價格與互動比較；價錢只在 footer 出現一次，不重複 header 價格，資金不足顯示明文差額；世界下方的價格保留，讓提示被 defer 時仍可交易。
- 提示深度（已實作）：提示 `z_index` 5，位於世界互動物件提示 Label 的 4 之上、HUD Canvas 的 30 之下；原因是不透明的 304×154 提示曾被傳送點提示從 headline 處畫穿。只有 `run_loot` ready-shop 的深度改變，交易、玩法與幾何不變。
- 選這個：只調單一提示深度，遮住世界提示但不蓋 HUD；放棄：把所有世界標籤降層或加通用 tooltip manager，會影響所有提示且是不必要的抽象。
- 選這個：提示先回答「這是什麼」，交易細節留給同一 compare 入口；放棄：header／footer 重複價格與逐卡規格並列。

### Collector 與 Mutation
- Collector 是四列高資訊列表與分次進度；解鎖卡是 UI-only，只在 blueprint cost 已真正持久化成功後出現（正費用、無 `Profile.last_save_error`、saved cells 已達 cost）。卡片開啟期間吞掉所有按鍵，Continue 才返回；partial／failure 仍用文字 receipt。
- Mutation 是全寬頁；`RESET ALL` 第一列，三個效果列在後，長效果在既有 detail band 捲動；不改效果、容量或 reset 價格。
- 服務頁眉（已實作）固定三個事實：花費資源（本局金幣／攜帶細胞／免費）、效果範圍（本局／永久）、落盤時機（立即／此 Passage checkpoint）；`MathArt.ui_state` 提供六態名稱＋短文字＋圖形，鎖定與已購買不得只靠變暗區分。Mutation 用 `MathArt.ui_mutation`，依 damage／cooldown／damage_taken／heal_kill 畫三角刃／斷環／六角殼／四瓣；空狀態 reset 明說本次花費 0、不可購買，非空狀態把確認放在最近一層；reset 先顯示本次真實費用與會清空的名稱，餘額不足不得假成功、不得扣款，取消不扣。Craft 顯示當前→付款後、支付額與支付後 Gold，並固定寫明保留現有充能與冷卻。
- 選這個：先講作用範圍與落盤，再講當下結果；放棄：只靠變暗與單一服務符號暗示狀態。

### 標題與存檔
- main 是五個動作的短列表（繼續／進入大廳、新一局、存檔、設定、離開）＋右側 active-save 面板；五行固定在 `Rect2(52,190+i*43,306,39)`，單行動作加短提示。`W/S` 選動作，Enter／A 開啟；`Saves` 仍是 index 2。
- 設定從標題與暫停都能開；Main 建立唯一 `SettingsScreen` 實例並記住呼叫頁，關閉後恢復原頁焦點；設定開啟期間呼叫頁不處理輸入，返回不解除原暫停，也不產生新的遊戲動作。
- `Saves` 是獨立三張橫向卡頁；`A/D` 或 `W/S` 選槽，Enter 開啟，Esc 返回。
- 從 run 暫停按 `T` 直接落在 Saves；本 session 第一次開標題落在 main。`TitleScreen.show_saves()` 只切 UI；返回標題仍走既有保存流程。
- 新局覆蓋 checkpoint 要二次確認：`N, N` 或 `N, Enter`；Esc 取消。只有真正 `Profile` 寫入成功才顯示成功。
- 標題右面板（已實作）：`Rect2(378,102,338,74)` 放 `MathArt.ui_brand`＋三軸輪廓的靜態原創構圖，半徑 ≤32、無 idle pulse；三槽卡 glyph 由 `ui_service` 對應空槽／Hub／checkpoint／protected。Saves 每卡固定槽號→地點／Hub→可繼續方式→保留邊界，損壞／新版本／受保護／空槽與「非空但不可恢復」各有明文原因；`Profile.slot_summary()` 的 `resume_error` 是 canonical validation 的顯示投影，只影響啟用與原因，`blocked`／`select_slot` 政策不變，標題保留 presence-based 拒絕。
- 結果頁（已實作）：順序為死亡／放棄／通關→結果是否已保存→失去／保留→下一步；統計縮為次要，存檔失敗先於慶祝並提供可聚焦焦點 id「pending retry／clean return／quit」，按鈕列 `Rect2(52+i*134,424,128,28)`；五列原始原因在 `Rect2(52,242,664,100)`，可用真實上下鍵捲動、不截斷。成功放棄的結算用 ephemeral `Game.run_abandoned` 標記（實際 `end_run(false,true)` 後設定、新局重置），只影響文案與焦點，不進序列化、不改 `VERSION`／存檔政策／內容資料。
- 選這個：存檔頁先回答「能不能繼續、會失去什麼」，結果頁先回答「有沒有保存」；放棄：把非空槽一律叫可繼續、截斷失敗原因，或把放棄誤顯示成死亡。

### 設定
- `SettingsScreen`（`scripts/ui/settings_screen.gd`，`class_name SettingsScreen`，layer 62）固定對外 API 為 `open() / close() / is_open() / closed`；頁面狀態（`page_index`、`draft`、`committed`、`capture_active` 等）供輸入與測試讀取，不是第二份 canonical 進度。Main 建立唯一實例，標題與暫停以 `settings_requested` 開頁並記住 owner。關閉回到原頁原焦點、維持原 pause；設定可見時呼叫頁不處理輸入。Main 的 `_any_panel_open()` 與 `Hud._modal_open()` 把它算成開啟頁，最上層 `_input` 由設定自己消耗。
- 頂部分類固定「音效／畫面／操作／語言」，四頁籤在 y104（`Rect2(52+i*167,104,163,24)`），PageUp／PageDown 或 LB／RB 切換；body y130–386，focus row 高 36，上下選列、左右調值（音量每次 0.05）。操作頁左右選鍵盤／手把欄，Enter／A 進入該裝置的重綁等待。底部 y398 三個可聚焦操作「套用／還原本頁預設／返回」（`Rect2(52+i*220,398,208,28)`）與內容列連成上下導覽，左右選操作、Enter／A 執行；y440 顯示狀態，y452 顯示鍵帽。操作 action 清單超出可見行時捲動並顯示行號；狀態詳情超出高度時也可捲動到尾端，顯示目前範圍／總數，不縮字。
- 偏好與進度分離，但 Profile 仍是唯一持久化 writer：`preferences`、`last_preferences_error`、`load_preferences()`、`save_preferences(next)`；檔案是 `user://ashfall_settings.cfg`，不升 `VERSION=6`、不寫 `run_checkpoint`、不受切槽／死亡／新局清空。ConfigFile 固定 `[general] locale`、`[audio] master/music/sfx`（0–1）、`[display] window_mode/vsync`、`[input] keyboard/gamepad`（只存 overrides）。keyboard 值為 action→physical keycode；gamepad 值為 action→`{"type":"button","index":n}` 或 `{"type":"axis","index":n,"sign":-1|1}`。只允許 gameplay actions，選單安全鍵不可重綁；內部 `jump_explicit` 不在清單，搖桿移動方向維持預設。
- 所有變更先進 draft；試聽／預覽只替換 draft 的 locale／audio（顯示模式預覽另加 draft display），input 維持 committed，重綁在套用成功前不生效。套用先 `InputMap.load_from_project_settings()`，再替換有 override 的該 action、該裝置 events，不在舊 binding 上累加；取消用 committed 值同樣重建。顯示模式在套用後預覽 10 秒（wall-clock），確認保留才存檔並提交 input，取消／逾時恢復舊模式與原視窗位置尺寸；headless 跳過實體 DisplayServer 變更。
- 重綁流程：聚焦 action→Enter／A→等待下一個鍵／button／trigger；Esc／B 取消；新 binding 與另一 gameplay action 衝突時顯示動作名並拒絕，保留原值。既有 drop／climb_down 與鍵盤 W／↑ 的 jump／climb_up 共享是唯一允許的重疊，不靜默交換。按下進入等待的 confirm 不算新 binding。
- 缺少偏好檔採預設、不自動建立；壞檔／欄位型別錯記警告、該欄回預設且讀取不覆寫原檔，只有使用者套用才替換。locale 只接受 `zh_TW`／`en`，音量限有限數值並 clamp，未知 action／非法 input index 忽略。`ASHFALL_SETTINGS_PATH` 可指定隔離偏好；未指定但有 `ASHFALL_PROFILE_PATH` 時用其旁 `settings.cfg`；直接測試場景用 PID 隔離檔並拒絕正式偏好路徑。偏好路徑只在 `_ready()` 決定，`reset_profile()`／`_apply_defaults()` 不碰 preferences；偏好錯誤獨立回報，不設 `_save_blocked` 鎖住遊戲進度。
- 存檔用 `.tmp`→rename；失敗顯示「設定未儲存，保留原設定」，留在頁面可重試或取消，不誤用 `Profile.last_save_error` 影響遊戲結算。Sfx 建立原生 Music／SFX buses send 到 Master，音樂 player 與池走對應 bus；百分比只控制 bus gain，0 明確 mute，保留各音源原音量／pitch。

### 地圖
- browse 以地圖為主：沒有側欄，兩行 place window；checkpoint travel 才有六列側欄。兩者共用同一列 clamp 與鍵盤焦點。
- 只顯示已發現的房間、服務與 checkpoint；未知內容不洩漏，鎖定原因用文字說明。沒有任意傳送。
- 世界與出口（已實作）：`level._draw_biome()` 不再繪 room id；出口、能力門與互動物件顯示翻譯後名稱與實際 action 鍵，未在可玩範圍取得的能力如實說明條件；地圖與世界共用 `Level.teleport_refusal` 判斷，拒絕理由一致。區域圖只畫 discovered、padding 24px、比例上限 1:1，單房放大置中；左上兩行顯示地點／已發現範圍，legend 固定玩家／傳送點／出口／地點與鎖定樣式。
- 名稱與 locale（已實作）：EN 地圖標題曾因 `Level.floor_name` 快照快取 ZH，之後走 `ContentText.name` 的 EN 查詢仍回 ZH；現在每次繪製由 canonical `Data.name` 重新取用，`Passage` 使用自己的新 locale context 重取。
- 選這個：canonical 名稱每次繪製重新投影；放棄：快取已翻譯字串快照，locale 切換後會顯示舊語言。
- 選這個：只呈現已確認的地圖事實並保留方向感；放棄：以內部 ID 或未知出口裝飾。

### One-way 與動效
- 正式路線 one-way 只改外觀：1px 虛線底邊（7px on／13px step）＋低 alpha accent sliver；solid 平台保留實線底邊。碰撞、drop-through、生成與存檔不動。
- modal reveal 100ms、selection 120ms；焦點立即換位，輸入先生效，tween 可被下一鍵中斷。沒有新 idle 旋轉、脈衝或全屏閃白；靜圖不證明 motion 序列。
- 回饋（已實作）：全頁只有一層 backdrop，成功 acknowledgement 是最上一層，Back 只退這一層；Archive／Skill 失敗用固定在地化 receipt 加可捲動原始診斷，不加 `SAVE FAILED:` 之類前綴字串比對；每個失敗都要給可執行下一步。`Game.announce_kind`、`SettingsScreen` layer 62 與顯示模式 10 秒 wall-clock 預覽是第 1–4 步已落地的基線，本輪維持並驗證，不重複實作。
- 選這個：先改狀態再播動效，失敗一律能看到下一步；放棄：以動效代替狀態、把錯誤只留成一行前綴。

## 取捨

選擇以大語意物件、安靜 surface、單一焦點與真實交易後果構成頁面，因為玩家要在低解析與戰鬥壓力下快速做選擇；放棄每頁同一左列表／右文字殼、裝飾框線、複製原作美術，以及用自動截圖代替真人理解。
選這個：把 canonical build／交易／存檔狀態投影成唯讀顯示，讓玩家在同一頁先看到真實後果；放棄：另養一份 UI 專用 state、把預測當成已承諾，或讓 UI 反向擁有進度。
選這個：所有失敗都保留原始診斷並給可執行下一步；放棄：用前綴字串、截斷行數或裝飾動畫掩蓋失敗。
