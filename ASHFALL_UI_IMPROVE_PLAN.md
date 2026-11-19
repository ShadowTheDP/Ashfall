# Ashfall UI 全面提升執行計畫

## Status（2026-11-18）

- 這是唯一現行的 UI 執行計畫。第 1–8 步已完成工程實作與有限視覺；最終 gate、證據與已知限制只以 [current-state](docs/agent/current-state.md) 為準，全部 PASS 前不宣稱驗收完成。
- 第 1–4 步（雙語文字層、共用輸入層、設定／偏好、戰鬥 HUD 與暫停 Build 摘要）與第 5–8 步（比較／商店、服務、地圖／存檔／結果、狀態回饋）已實作；自動與有限視覺 gate 已 PASS，人類美術／理解、真人雙路線與實體手把／Windows export 仍待驗收；native fixture 不是正常輸入。
- 實際狀態、證據與限制只以 [current-state](docs/agent/current-state.md) 為準。下文「已確認的現況」是實作前的規劃基線（證據截止 2026-11-16），描述當時的程式與缺口，不是今天的狀態；第 1–4 步的完成與第 5–8 步的實作已使其中部分描述過時。
- 第 5–8 步的詳細要求與驗收表仍有效；本次授權只涵蓋本計畫的 UI 範圍，不新增裝備、關卡、敵人、治療承諾、BSC 玩法或重平衡。

## Context

使用者要求以所附產品評論為參考，讓 Ashfall 的 UI 與操作體驗向 Dead Cells 靠近，保留不同的藝術表現。本計畫將以可觀察的資訊分組、選擇順序、導覽與回饋作參考，保留原創 MathArt；不把原作程式、資產或文字帶入。

使用者已確認「全部 UI 與操作體驗」：HUD、換裝、地圖、服務、存檔，加設定與完整手把選單流程；介面繁體中文／英文可切換，首次使用繁體中文。戰鬥、裝備數量與路線不變。

## 已確認的現況（實作前規劃基線，證據截止 2026-11-16）

- `docs/design/ui-system.md`：現有 UI 已有共用 surface、語意色、11px 最小必要文字、HUD／暫停分組、Scroll 與換裝、商店提示、Collector／Mutation、main／Saves 分頁、map browse／travel 分流。768×480 是設計尺寸；縮放不重排。
- `docs/agent/current-state.md`：既有成熟度增量已做 focused 工程驗證；人類美術與理解尚未通過。現存截圖不能證明動效，手把／Windows export 未驗證。
- `README.md`：目前沒有設定選單、中文 UI 或完整手把重綁；中文受現有 fallback 字型限制。Profile 是唯一遊戲進度持久化 writer，RunBuild 擁有局內裝備與錢包。
- 工作樹與系統在規劃期間唯讀；本文件是唯一執行計畫。程式入口與證據在規劃時逐項核對，之後第 1–4 步已依本計畫實作。
- `scripts/ui/build_screen.gd` 現在把 FIRST HIT／CHARGES／品質放在候選與目標卡片的主資訊；本輪已實際查看 `near-compare.png`、`near-ready.png`、`near-pause-entry.png`，確認仍缺玩法摘要與精簡的戰鬥 HUD。
- `scripts/autoload/game.gd::_setup_input()` 在 runtime 登記鍵盤與部分手把動作；多數 UI 先拒絕非 InputEventKey，故現有手把 binding 不能構成選單閉環。該函式註解已要求設定／重綁落地時移入 `project.godot` 並刪除 runtime 註冊。
- `scripts/systems/math_art.gd::ui_text/ui_wrap/ui_short/ui_key` 與部分 HUD／地圖／世界文字直接使用 `ThemeDB.fallback_font`。中文需統一字型來源與真實字寬；`scripts/world/level.gd::_draw_biome()` 直接繪製 room ID，是施工標籤的實際來源。
- 可重用原生 Godot TranslationServer、TextParagraph、ConfigFile；已讀官方文件。Noto Sans CJK TC Regular 官方檔約 16.4 MB，採 SIL OFL 1.1，可連同授權再散佈；不以作業系統字型保證中文可用。

## Approach

依序完成下列行為。第 1–2 步是共用基礎，第 3 步接入設定；其後 HUD／裝備與其他選單可在基礎介面固定後獨立施工，集中驗收時凍結來源。實作者重讀目標後修改；本輪 LSP 回報沒有 configured language server，執行時若仍沒有，使用檔案搜尋核對全部呼叫點。

### 1. 讓所有文字可用繁中閱讀，並維持同一套 MathArt

- 在 `scripts/systems/math_art.gd` 新增 `static func ui_font() -> Font`，統一文字繪製與字寬量測。隨專案加入新的 `assets/fonts/NotoSansCJKtc-Regular.otf` 及 `assets/fonts/OFL.txt`，只用 Regular 一個字重；來源固定官方 `notofonts/noto-cjk` commit `165c01b46ea533872e002e0785ff17e44f6d97d8` 的 `Sans/OTF/TraditionalChinese/NotoSansCJKtc-Regular.otf`，附同 commit 根目錄 `LICENSE` 與字型內 copyright notice。這是中文可交付所需的文字字型例外；幾何、圖示與美術仍完全經 MathArt，不引入原作字型或圖片。
- 保留 `ui_text/ui_wrap/ui_short/ui_key` 的公開參數；全部改用 `ui_font()`。`ui_wrap` 改用 Godot `TextParagraph` 的原生換行與 `get_line_range()` 取回每行文字，保留明確換行、中文標點與英文單字；過長單字才在 grapheme 邊界折行。`ui_short` 保留省略號且不可切半字形。結果仍為 Array[String]，既有使用者不改資料契約。每頁只在文字／選項／語言變更時重新組版，不能每幀重新 shape 全文。
- 新增 `data/localization/ui.csv`，欄為 `keys,en,zh_TW`，由 Godot 原生 Translation 匯入，在 `project.godot` 註冊兩個 locale；首次預設 `zh_TW`，英文回退 `en`，納入 Text Server 資料。靜態文字用 `tr("UI_...")`，動態字串使用命名 placeholder；內容名稱用 `GEAR_<ID>_NAME`／`WEAPON_<ID>_TEXT`／`BIOME_<ID>_NAME` 等穩定 key，ID 以大寫底線表示。不把翻譯寫回 canonical `data/*.json`，不改 content stamp。
- 統一術語：Gold＝金幣、Cells＝細胞、Scroll＝卷軸、Mutation＝突變、Collector＝收藏者、Forge＝鍛造、Passage＝中繼站、Blueprint＝藍圖、Brutality／Tactics／Survival＝暴虐／戰術／生存；「本局」與「永久」在所有頁面使用相同詞彙。裝備、敵人、地點的英文名稱沿用現有資料，繁中提供對應名稱；不能用自動 capitalize／ID replace 作玩家名稱。
- 遷移全部玩家可見文字，包括公告、錯誤原因、Rune／藍圖／出口／服務提示與既有 arena 選單。已確認直接 font 呼叫點為 `scripts/ui/{hud,build_screen,exploration_map}.gd`、`scripts/meta/{hub,passage}.gd`、`scripts/world/{level,progress_pickup}.gd`；其餘 UI 的 MathArt 呼叫也全部使用翻譯 key。實作時用搜尋 `ThemeDB\.fallback_font|draw_string\(|get_string_size\(` 逐一收斂到唯一 `ui_font()`；完整性檢查同時涵蓋 `scripts/player`、`scripts/enemies`、`scripts/world` 的顯示文字。原始診斷與檔案路徑不翻譯，顯示層加本地化可採取動作。
- 字級定為頁標 24、物件名 16、正文 13、必要次要文字／鍵帽 11；行距不得小於字型實際高度。長文換行或焦點詳情捲動，不縮小字級；危險／價格／確認／存檔失敗不可省略。重用 `ui_surface/ui_axis_emblem/ui_service/ui_gear/ui_select/ui_reveal`，焦點仍為 gold 短邊＋左軌，語意色仍走 `axis_color`。

選這個：一個隨遊戲交付的中文字型、原生翻譯與原生斷行，讓兩種語言有相同操作結果。放棄依賴 Windows SystemFont 與逐字硬切，避免開發機可讀、玩家機缺字。

### 2. 統一鍵盤與手把，保留各頁自己的狀態機

- 將 `scripts/autoload/game.gd::_setup_input()` 的既有鍵盤 action／別名搬入 `project.godot` 的 InputMap，刪除 `_enter_tree()` 中的登記呼叫與只為登記存在的 `_joy()`；不保留雙重註冊。保留所有現有鍵盤玩法 binding。原生 action 是唯一輸入來源，不另建命令系統。
- 新增跨場景 `scripts/autoload/interface.gd`，在 autoload 順序 `Data → Profile → Interface → Sfx → Combat → Game` 初始化。新 API 固定為 `signal presentation_changed`、`func apply_preferences(values: Dictionary) -> void`、`func pressed(event: InputEvent, action: StringName) -> bool`、`func prompt(action: StringName) -> String`；它只管理 locale、InputMap overrides、最後有效輸入裝置及提示，交易仍由原 owner 執行。沒有可重用的現存共用 UI action／裝置提示 owner，故新增此單一服務。
- 新 menu actions 固定為 `ui_nav_up/down/left/right`、`ui_accept`、`ui_back`、`ui_tab_prev/next`、`ui_detail_up/down`、`ui_secondary`。鍵盤方向＝WASD／方向鍵，確認＝Enter／小鍵盤 Enter／Space／J／Z，返回＝Esc，分頁＝PageUp／PageDown，詳情＝上／下，次操作＝X；各頁依下面規格區分選項方向與詳情方向。手把方向＝D-pad／左搖桿，確認 A、返回 B、分頁 LB／RB、詳情右搖桿上／下、次操作 X。`pressed` 忽略 release／鍵盤 echo，搖桿越過 0.5 才觸發一次、回到 0.25 內才重新武裝；不把漂移當導覽。Enter／Esc／方向鍵永遠可用於選單，不能因玩法重綁鎖死設定入口。
- 完整預設手把玩法：左搖桿與 D-pad 移動／攀爬，A 跳躍，B 翻滾，X 武器 1，LT 武器 2，Y 技能 1，LB 技能 2，RB 互動，RT 治療，View 地圖，Start 暫停。刪除舊的 Back＝restart，重開／放棄改走可聚焦的暫停項目。drop 與 climb_down 共用下方向，保持現有跳躍＋下方向玩法，不能把向上搖桿新增為跳躍。
- 修正 `scripts/player/player.gd::_space_jump()` 的實體 Space 依賴，以免重綁跳躍後、按上攀爬時無法跳離。新增內部 InputMap action `jump_explicit`：預設只綁 Space／手把 A；jump 的使用者 override 同步套用於此 action，既有 W／↑ jump 別名不加入。判斷維持 `_action_pressed("jump") and (Input.is_action_pressed("jump_explicit") or not Input.is_action_pressed("climb_up"))`；其呼叫點在 `_traversal_step()`，不改攀爬／下穿／下砸時序。
- 全面遷移以下已確認的 raw-key UI owner：`scripts/ui/{title_screen,hud,build_screen,exploration_map,archive_screen,skill_tree,reward_screen}.gd`、`scripts/meta/{hub,hub_ui,collector,passage}.gd`，以及 `scripts/world/{level,progress_pickup}.gd` 的互動入口；`run_loot.gd` 已走 interact，保留其 claim 入口。`Main._unhandled_input()` 保留 map／heal action。只有數字直選等鍵盤捷徑可保留 InputEventKey 分支，且不能是唯一操作路徑。
- 各頁仍自己處理 focus／scroll／confirm；共用服務不接管頁面或新增 modal stack。打開的 modal 先消耗事件，按鍵必須 release 後下一次 confirm 才能購買；關閉時照既有 `Game.player.suppress_actions()` 清掉穿透。延續 `Main._any_panel_open()`／`Hud._modal_open()`，把新設定頁納入。裝置切換只刷新鍵帽、不得重設 focus；手把拔除時若正在局內未暫停則暫停，接回不自動解除，鍵盤可直接續用。
- 所有鍵帽改由 action 生成；`MathArt.ui_key()` 的繪圖保留，由呼叫者提供 `Interface.prompt(action)`。採中性 A/B/X/Y、LB/RB/LT/RT、View/Start 文字與 MathArt 幾何鍵帽，不引入平台商標圖包。靜止搖桿與 release 不改最後輸入裝置。

### 3. 從標題與暫停都能完成設定，再返回原畫面

- 新增 `scripts/ui/settings_screen.gd`，`class_name SettingsScreen`，沿用 CanvasLayer＋MathArt 的頁面模式，API 為 `open() -> void`、`close() -> void`、`is_open() -> bool`、`signal closed`。`Main` 建立唯一 instance；標題及暫停分別發送 `settings_requested`，Main 開頁並記住 owner，close 後恢復原頁 focus。設定自行處理最上層 `_input`，呼叫者在 settings 可見時不處理輸入；返回不解除標題／暫停原有 pause，不觸發新的遊戲動作。
- `TitleScreen._draw_main/_move/_confirm` 改為五項：繼續／進入大廳、新一局、存檔、設定、離開。五行固定 `Rect2(52,190+i*43,306,39)`，單行動作＋短提示，保留右側 active-save 說明。Saves 仍為現有三槽，不新增遊戲模式入口。
- 設定頁使用既有 UI_PAGE：頂部分類「音效／畫面／操作／語言」，PageUp/Down／LB/RB 切分類；body y130–386，focus row 高 36，上下選列、左右調值；操作頁左右選鍵盤／手把欄，Enter/A 開該裝置的重綁等待。底部 y398 的三個可聚焦操作「套用／還原本頁預設／返回」與內容列連成上下導覽，左右選操作、Enter/A 執行；y428 顯示狀態、y452 顯示鍵帽。操作 action 清單超過可見行時捲動並顯示行號。
- 偏好與進度分離，但沿用 Profile 作唯一持久化 writer：在 `scripts/autoload/profile.gd` 新增 `var preferences: Dictionary`、`var last_preferences_error := ""`、`func load_preferences() -> void`、`func save_preferences(next: Dictionary) -> bool`；`_ready()` 先讀偏好再讀原三槽進度。偏好儲存在新 `user://ashfall_settings.cfg`，不升級 VERSION=6、不寫 run_checkpoint，也不受切槽／死亡／新局清空。
- ConfigFile schema 固定為 `[general] locale="zh_TW"`；`[audio] master=1.0, music=1.0, sfx=1.0`（0–1、UI 每次 0.05）；`[display] window_mode="windowed", vsync=true`（windowed／fullscreen）；`[input] keyboard={}, gamepad={}`（只存 overrides）。keyboard 值是 action→physical keycode；gamepad 值是 action→`{"type":"button","index":n}` 或 `{"type":"axis","index":n,"sign":-1|1}`。僅允許本計畫的 gameplay actions；選單安全鍵不允許重綁。
- 記憶體的 preferences／draft 依 general/audio/display/input 四層 Dictionary 對應 ConfigFile sections。Apply 時先 `InputMap.load_from_project_settings()` 再替換有 override 的該 action、該裝置 events；不要把新 binding 累加在舊 binding 後，取消則用 committed 值同樣重建。重綁允許的 action 清單即原 `_setup_input()` 的玩法 keys，內部 `jump_explicit` 不出現在使用者清單；move/climb/drop 的預設搖桿方向不會被 button override 清掉。
- 重綁流程：聚焦 action→Enter/A→等待下一個鍵／button／trigger；Esc/B 取消；新 binding 若與另一 gameplay action 衝突則顯示動作名並拒絕，保留原值。既有 drop/climb_down 以及鍵盤 W／↑ 的 jump/climb_up 預設別名屬明確允許的共享；不可把其他衝突靜默交換。按下用來進入等待狀態的 confirm 不算新 binding。搖桿方向維持預設，trigger 可綁 gameplay action；不必為左右搖桿引入校準頁。
- 所有變更先存 draft；音量與語言即時預覽，Apply 成功才取代 committed preferences。顯示模式在 Apply 後預覽 10 秒，確認保留才存檔，取消／逾時恢復舊模式。取消或離頁撤回未存變更。存檔使用 `.tmp`→rename，錯誤顯示「設定未儲存，原設定保留」，不誤用 `Profile.last_save_error` 影響遊戲結算；無法寫入可留在頁面重試或取消。
- 缺少偏好檔採預設、不自動建立；格式壞／欄位型別錯時記警告、對應欄採預設且讀取不覆寫原檔，只有使用者 Apply 才替換。locale 只接受 zh_TW/en，音量限有限數值並 clamp，未知 action／非法 input index 忽略。`ASHFALL_SETTINGS_PATH` 可指定隔離偏好；未指定但 `ASHFALL_PROFILE_PATH` 存在時用其旁的 `settings.cfg`；直接測試場景則用 PID 隔離檔，拒絕正式偏好路徑。`tools/check.py` 在自己的 temp directory 同時指定兩個 path。
- 偏好路徑只在 `_ready()` 依 env／測試場景算一次，不由會隨切槽改變的 `SAVE_PATH` 推導；`reset_profile()`／`_apply_defaults()` 不碰 preferences。隔離 guard 必須在讀取正式偏好前拒絕測試存取，獨立回報 `last_preferences_error`，不得設定 `_save_blocked` 讓遊戲進度一起鎖住。
- 在 `scripts/autoload/sfx.gd` 建立原生 Music／SFX buses 並 send 到 Master，音樂 player 與池分別走對應 bus。`Interface` 先套 locale／InputMap，Sfx 在建立 buses 後、播放音樂前再呼叫 `Interface.apply_preferences(Profile.preferences)` 套音量，避免初始化時 bus 尚不存在。百分比只控制 bus gain，0 明確 mute，保留現有每支音源的音量／pitch。視窗切換保留 768×480、fractional、aspect=keep 與初始視窗大小；不加入解析度、幀率或 gameplay-time 相關設定。headless 跳過實體 DisplayServer 模式變更，仍驗證保存與還原狀態。
- 顯示模式使用 Godot 原生 WINDOW_MODE_FULLSCREEN／WINDOW_MODE_WINDOWED，VSync 使用 VSYNC_ENABLED／VSYNC_DISABLED；預覽前保留視窗位置與尺寸，回復／離開全螢幕時還原。保持「只在重綁成功 Apply 後改 gameplay InputMap」；音量／語言的 draft 預覽不偷偷提交輸入 binding。

### 4. 戰鬥只顯示即時可用性，暫停才展開 Build

- 新增純顯示 helper `scripts/ui/gear_presentation.gd`，`class_name GearPresentation`，API `static func describe(build: RunBuild, item: Dictionary) -> Dictionary`，回傳 `name/playstyle/condition/headline/details`（前四者 String，details 為 Array[String]）。它只讀 `definition/display_stats/cooldown/level` 與 canonical weapon combo 資料，沒有建立 UID／扣錢／補充能／寫 Profile 的副作用。現有顯示分散在 `BuildScreen.item_details/_gear_lines` 與 shop tip，沒有共用玩法摘要，故新增；不建立第二份戰鬥計算器。
- 寫入十件物品的雙語玩法摘要：rusty_sword＝均衡三連斬、尾段放波；arc_saber＝快速寬幅斬擊；kiss_precision＝窄幅快斬、較高暴擊倍率；fractal_edge＝出手較慢、重尾段波；chain_lash＝較長範圍、較慢；orbit_rings＝短節奏連斬、首擊較低；fold_shield＝短時間擋正面一擊、近身反擊；kunai＝自動索敵的弧線飛刀；aegis＝短時間擋一擊並反擊周圍；ash_charm＝提高最大 HP、不治療。六把近戰的 condition 都必須誠實說「敵人出招暴露或背刺時暴擊」，不可寫成六種獨有暴擊條件；技能／盾說明充能恢復，護符說明不回血。速度／傷害／倍率由實際定義取得，不把示例數字硬編成新規則。
- 改 `scripts/ui/hud.gd` 的正式 RunBuild 路徑：生存群聚收至左下。flask `Rect2(16,362,42,56)`；四件可操作裝備 `Rect2(x,362,56,56)`，x 固定 `[66,124,190,248]`，兩武器與兩技能中間保留分組空隙；護符 `Rect2(314,362,36,56)`；三軸小列 baseline y434；HP `Rect2(16,440,334,24)`。保留 `equipment_rects()` 作唯一幾何入口並更新其消費者。圖示、實際動作鍵、充能刻度與尚餘秒數是主資訊，移除卡內完整裝備名、重複 READY 標籤及近戰的假充能／假 NO RECHARGE TIMER。
- 近戰顯示裝備圖形＋動作鍵，不顯示 1/1；盾／技能才依 canonical charges/cooldown 顯示刻度，空充能變暗、明文剩餘秒數，0 秒與未就緒不可只靠顏色區分。flask 顯示實際剩餘／容量。HP 重用 `health_readout/health_segment_fill` 的小數與滿血判定，不因版面改成假滿血。三軸數字留在 HP 上緣的小列，圖形＋等級；詳細加成搬到暫停。
- 導覽群聚改為 minimap `Rect2(588,346,164,84)`、錢包與計時在 `Rect2(554,438,198,26)` 內兩行 11px；Gold 與本局攜帶 Cells 明確區分。一般戰鬥不顯示 Visit/BSC 第二行，把它移到 map／pause；地點名在進區時用現有 announce 短暫顯示。Boss HP 維持頂部獨立長條，名稱與玩家 HP 不競爭。
- `Hud._draw()` 在全頁 modal（build／map／Collector／archive／skill／hub panel／settings／reward／title）開啟時不再繪製戰鬥 equipment/vitals/wallet/minimap/announce；世界保留在單層 α0.82 mask 後，頁面自己提供錢包與操作。解決目前 compare y428 鍵帽與背後 y440 HP 重疊。pause 與結果頁也只畫自己的一套資訊。
- 暫停保留現有 WEAPONS／SKILLS／PASSIVE 分組與五個裝備 focus，右側先顯示第 5 步的玩法摘要，再顯示完整機制／詞綴／數值；移除把 Controls 附在裝備長文末端的做法。詳情捲動區固定 `Rect2(328,176,388,136)`，狀態／三軸／Mutation 在 y334–362。底部新增可聚焦操作列：繼續、設定、存檔、放棄本局、離開，`Rect2(52+i*134,376,128,28)`；X 切換裝備／操作列焦點（手把也是 X），左右移焦點、上下捲詳情，Enter/A 執行操作列項目；裝備區 Enter/A 移至操作列的繼續，不直接放棄。Esc/B 一律返回最近一層或繼續。既有 T/Q/S 等捷徑保留但不得是唯一入口。
- checkpoint 儲存失敗時，操作列前兩項改「重試儲存／回到上一 checkpoint」，其餘設定／離開仍可到；不能先解除暫停。正常放棄沿用現有失去／保留雙區確認，不新增結算政策；失敗保留 checkpoint 並顯示重試。

選這個：戰鬥場景用符號與即時狀態，閱讀與流程放在暫停。放棄常駐完整名稱與資料表式 HUD，避免玩家在出手時讀規格。

### 5. 先說怎麼玩，再說換掉什麼與花多少

- `BuildScreen._draw_comparison()` 改為候選 `Rect2(52,110,664,164)`、目標 `Rect2(52+n*338,294,326,104)`（單槽寬 664）。候選左側 436px：圖示 32px、名稱 16px 最多兩行、玩法 13px 最多兩行、條件、普通首擊／反擊／單發／HP；右側 196px 專門顯示購買價、該選中槽回收額、交易後餘額與不足金額。目標只顯示名稱、同類 headline 差額、簡短玩法與真實充能；品質／軸等級／詞綴列為次要。
- 移除 card 內各自捲動的 `_gear_lines()` 與固定刪掉前四行的 `item_details()` 字串解析。完整 details 改為候選／選中目標的共享明細，在 y282 顯示「詳情 a–b／N」，底部 y416／432 可見兩行，底部鍵列統一 y452、鍵帽底≤471；上下／右搖桿捲動、左右換替換槽。長名字保留兩行省略，完整名字只在共享詳情出現一次。`Hud` 改直接使用 `GearPresentation.describe()`，`tests/l3_build_probe.gd` 原呼叫 item_details／_gear_lines 的斷言改成真正的裝備語意與可讀性斷言；不保留相容 alias。
- `GearPresentation.describe()` 對 empty／無 definition 的 item 回傳本地化「空槽」與空 details，不讀取缺失欄位；合法資料的翻譯缺 key 時回既有英文內容並記警告，不能把 raw key 顯示給玩家。canonical 數值仍走 Data／RunBuild 的既有驗證，不在 presentation 自行修補壞存檔。
- 金額維持既有「先付足原價，再回收原裝備」：不足不得把回收額當先行折扣。焦點槽改變時餘額立即更新；Enter/A 才執行原 `offer.claim()`；X 只回收免費候選、不能回收未售商品。取消／預覽不改 UID、charges、wallet、HP。不同 action 不顯示誤導的紅綠同列差額，改明文「用途不同」；護符用 `replacement_projection()` 顯示最大 HP 與當前 HP 的真結果。
- Scroll 保留三張 212×242 卡與 `scroll_projection()`；卡片先顯示會強化的已裝備物品圖示／名稱，再顯示等級、實際傷害變化與最大 HP。每張卡用現有 `ui_axis_emblem` 在背景畫 radius=76、alpha=0.10 的淡軸徽，保留前景小徽；「最大 HP 增加、當前 HP 不回復」固定可見，沒有受益裝備時明文說仍有 HP 增長。底部詳情 y386 起三行、key band y440 保留，不填固定百分比。
- `scripts/world/run_loot.gd` 保留 screen-space `shop_tip_rect()` 304×154、clamp／flip／公告衝突 defer。tooltip 依序為物件名→玩法兩行→真實 headline→價格與 interact 比較；只在 footer 顯示一次價錢，不再重複 header 價格。世界下方的價格保留（tooltip 不出現時仍能選）；不加入自動選槽／購買／商店刷新。商店與免費掉落共用同一份 GearPresentation，收據反映實際 claim 結果。

### 6. 每個服務先說作用範圍，再說當下結果

- `scripts/meta/collector.gd::_draw_ui/_row/_draw_service` 保留現有服務入口與交易函式；頁眉固定指出花費的是「本局金幣／攜帶細胞」、效果是「本局／永久」、何時落到 checkpoint。狀態用名稱＋短文字＋圖形區分：可用、尚缺條件、已選、已擁有、完成、資源不足；不能把鎖定和已購買都只變暗。空清單顯示「尚未有可交付藍圖」或該服務的真實空狀態，保留 Back。
- Collector 沿用左四列＋右聚焦大物件構圖：右側先放 GearPresentation 的用途或 Mutation 的實際效果，再放投入／總費用與真實下一步；未取得藍圖只解釋取得條件。局部投入只更新進度和收據；`_draw_unlock()` 僅在既有持久化成功條件成立後出現，Enter/A、Esc/B 都只關掉成功層並消耗事件，不可再次投入。
- Mutation 保留全寬 reset row／已選槽／三效果行。新增 `MathArt.ui_mutation(canvas: CanvasItem, at: Vector2, id: String, radius: float, tone: Color) -> void`，依現有 `Data.passage.mutations[id]` 中 damage／cooldown／damage_taken／heal_kill 決定不同圖形：三角刃／斷環／六角殼／四瓣；全部由現有 primitive 組合。頁面 logo 仍用 ui_service，效果列不再共用一個符號。選擇行先說觸發與效果，已選用明文；reset 啟用後先顯示本次真實費用與會清空的名稱、再確認，取消不扣款，不改容量／效果／免費三項的規則。
- Craft 沿用 `craft_projection()` 顯示當前→付款後、支付額與支付後 Gold，並固定寫「保留現有充能與剩餘冷卻」。Reforge 說清楚將變成哪個實際詞綴，禁止寫成隨機機率。Forge 保留永久 future-loot 的品質機率與刻度，明文「不改身上裝備」。Challenge 卡保留實際條件、達成／失敗／已領狀態，領完只展示已持久化結果；fountain 保持世界內互動提示而非新增全頁服務。
- Hub 的 Upgrades／Characters、Archives、Skills 沿用現有清單／分類／節點，翻譯名稱與條件；以明文區分已擁有／已裝備／可解鎖／尚缺條件。Archives 右側先放物件輪廓、戰術用途與取得資訊，數值在下；Skills 保留 nearest-node 導覽與真實效果。若某既有項目只作用於 arena，根據實際 consumer 標明該作用範圍，不改成在正式 RunBuild 生效，也不新增內容承諾。Reward 保留三選一、把「會改變什麼」放在卡片第一段，底部同樣可 A/B 完成。

### 7. 地圖、世界提示、存檔與結果不再露出開發骨架

- `scripts/world/level.gd::_draw_biome()` 刪除直接繪 room id 的那一行；SPLIT／UPPER／LOWER／MERGE 不再出現在世界。canonical room id、生成／發現狀態與 map_snapshot 完全保留。出口、能力門、互動物件改顯示翻譯後名稱與實際 action 鍵，不以內部 ID 當名詞。Climb／Ground 等未在可玩範圍正常取得的能力，照實顯示尚不可用的條件，不藉 UI 開放能力。
- `ExplorationMap` 保留 browse 無 sidebar、teleport 有六行目的地 sidebar。區域圖只顯示 discovered rooms，依已探索包圍盒縮放並保留 24px padding；單房時放大至地圖主區中央但不超過等效 1:1 logical 比例。世界圖沿用只顯示已發現節點，不揭露未知出口或獎勵。左上兩行顯示地點／已發現範圍，定位點／出口／服務各用現有 MathArt 形狀＋legend；頁底固定返回與分頁鍵。
- map 導覽固定：左右＝區域／世界分頁，上下＝teleport 目標（browse 不移動目標），PageUp/Down 或 LB/RB＝長內容翻頁；確認只在有效 travel source 與合法目標存在時執行既有 teleport，其餘顯示原因。關閉不解除其他 owner 的 pause。手把 View 可從正常世界開／關圖。
- Saves 保留三張橫卡，但每張資訊固定為槽號→地點／Hub→可繼續方式→保留邊界。損壞／新版本／受保護／空槽各有不同明文原因；禁止 UI 讀錯就新建／清除。新局覆寫 checkpoint 保留現有兩次確認與 permanent unlocks 保留說明，手把需釋放 A 後第二次 A，B 取消。`Profile.slot_summary().label` 的 EMPTY 與其他機器值不翻譯後再比較，只翻譯最後的顯示文字。
- Title 保留左動作右存檔；在右面板上方空間 `Rect2(378,102,338,74)` 加一個 `MathArt.ui_brand`＋三軸輪廓的靜態原創構圖，半徑≤32、不增加 idle pulse；三槽卡的 glyph 用 `ui_service` 分別對應空槽／Hub／checkpoint／protected，不能用隨機裝飾暗示不存在的存檔能力。畫面主角是 Ashfall 的幾何標誌與選中存檔，無需重造背景世界。
- Run-over 沿用現有 mask、統計與 settlement，只重排文案優先序：死亡／放棄／通關→結果是否已保存→失去／保留兩組→下一步。統計縮為次要；存檔失敗始終先於慶祝，提供可聚焦「重試結果儲存／離開」。正式勝利寫「0 BSC 路線完成；BSC 1 已解鎖，目前尚不可遊玩」，不給不可用的進階開始按鈕；不更動自動回 Hub 的倒數與流程時序。
- 防止翻譯破壞邏輯：Profile/RunCheckpoint 狀態、狀態比較用字串保持機器值，在顯示邊界用翻譯 key；`Game.announce(text: String, duration: float = 1.3, kind: StringName = &"info") -> void` 增加新狀態 `announce_kind`，保存失敗的呼叫傳 `&"error"`，HUD 判斷 kind，刪除 `begins_with("SAVE FAILED")`。已確認錯誤公告呼叫在 `autoload/game.gd`、`meta/passage.gd`、`world/progress_pickup.gd`；其餘 announce 呼叫在 main、encounter、level、build_screen、exploration_map，繼續走同一 API。長原因顯示本地化前綴＋原始可診斷原因，不能吞掉錯誤。

### 8. 把每種狀態的回饋接到真實動作

- 全頁只用一個 backdrop；成功 acknowledgement 是最近一層，Back 只退這一層。沿用 `ui_reveal` 100ms／`ui_select` 120ms，輸入與 focus 先變、更換選項會中斷前 tween；設定預覽倒數照 wall-clock，不受 hitstop／paused time scale 影響。新 settings layer 固定 62，其他層維持現有主頁順序。
- 每個可執行動作都要有明確結果：成功說已完成的變更，資源不足說還差多少，條件未達說缺什麼，存檔失敗說未保存及重試入口。重用 Sfx 現有 ui 音效，不新增音樂或 combat feedback。選中不等於已購買／已選擇；沒有狀態改變不播放解鎖成功層。
- 各語言／輸入裝置共享同一份真實 projection、price、readiness 與交易入口。新 presenter、SettingsScreen、Interface 不持有另一份 canonical build；頁面關閉後只留下既有系統實際提交的結果。


## Critical files & anchors

以下是容易誤改的共享契約，行號只供定位，實作前重讀：

- `scripts/autoload/profile.gd`：`_ready/slot_path/select_slot/reset_profile/save`；preferences 要獨立路徑與錯誤欄，不能污染三槽 payload、checkpoint 與 `_save_blocked`。
- `scripts/player/player.gd`：`_space_jump/_traversal_step`；重綁與手把跳離必須走明確 jump binding，不能硬依賴 Space。
- `scripts/systems/run_build.gd`：`display_stats/replacement_projection/scroll_projection/craft_projection`；重用原計算，不把顯示模型變成第二個 canonical owner。
- `scripts/main.gd`：`_show_title/return_to_title/_any_panel_open/_on_station_opened`；Settings 應回到呼叫頁且維持原 pause，Main 的既有 checkpoint／場景切換仍是唯一流程入口。
- `docs/research/dead-cells-ui-reference-atlas-2026-11-04.md`：各頁圖錄與來源；`output/ui-maturity-2026-11-16/review-index.html` 的 existing AFTER 是基線，STALE 圖只能參考結構，不當新驗收證據。

## Verification

本節是第 5–8 步與後續重驗的證明清單。第 1–4 步已取得的證據、日期與限制記在 [current-state](docs/agent/current-state.md)；不要把下表當成全部 PASS，也不代表最終 gate 已全部通過。第 5–8 步的驗證以本輪凍結後的日誌與 manifest 為準，不把舊版證據當成新結果。

### 自動行為檢查與既有契約

在專案根目錄、Godot 4.7.2 可用時，由唯一 validator 執行；`tools/check.py` 自動建立隔離 Profile 與偏好檔。先新增 `tests/settings_probe.gd/.tscn` 與 `tests/ui_product_probe.gd/.tscn`，註冊 runner opt-in 各 30／60 秒，並新增 capture alias `ui-product` 指向後者，display deadline 60 秒。fixtures 可明確標記並設置測試 state，但每個選擇、取消、confirm 與重綁都要透過真實 InputEvent 驅動。

| 行為／輸入 | 必須觀察到的結果 |
|---|---|
| 沒有偏好檔→啟動 | 第一幀繁中；字型含設定／裝備／鍛造等實際 glyph；畫面沒有 UI_KEY 或缺字框；尚未 Apply 不建檔。 |
| 音量 Music=0、SFX>0→Apply→重讀 | 音樂 bus mute、SFX 不 mute；偏好保存，三槽進度 bytes 與 run_checkpoint 未變。恢復預設再取消則回原 committed 值。 |
| 切到英文→返回前不 Apply；之後另次 Apply en→重啟 | 取消回繁中；保存後重啟英文；切槽／reset_profile 不清掉語言或音量。 |
| 設定路徑改成 fixture 目錄造成寫入失敗；壞 cfg／非法 locale／NaN 音量 | 原偏好 bytes、進度 bytes、舊模式不變，顯示未儲存；壞讀取只採預設／警告，不覆寫；能取消或重試。測試正式偏好路徑被拒絕且不鎖進度存檔。 |
| 重綁跳躍至有效新鍵、攀爬中按該鍵／A；與攻擊衝突的 binding；重設預設 | 有效新鍵能跳離；衝突拒絕且原 binding 不變；取消 capture 不變；預設全部舊鍵／別名恢復。B/Esc 等安全導航不能失效。 |
| Title→Settings→返回、pause→Settings→返回 | 回原頁原 focus；Title 與 pause 都仍暫停；沒有攻擊／互動／購買穿透。五項 title 中 Saves 仍 index 2。 |
| 只用合成 JoypadButton／Motion 走 Title、Saves、Hub、所有服務、map、Archives、Skills、Scroll、compare、reward、pause、Settings、結果重試 | 每頁可進、選、確認、退；焦點看得見；提示改手把且鍵盤可隨時接手。LT 能用武器 2、RT 能治療、View 開圖、Start 暫停；軸 0.1 漂移不移 focus，超 0.5 只走一步，回 0.25 內才能下一步。 |
| HP=0、0.1、70.8、141.59／141.6；技能 ready／半回充／empty；近戰 | 保留原 health_readout 真值，小數血量不假滿；技能狀態與真充能一致；近戰沒有 1/1 假提示。全頁 compare 出現時戰鬥 HUD 不露在按鍵列下。 |
| 購物 Gold=price-1、price、price+10；切兩個替換槽；取消／重按 held confirm | 不足原價必拒絕，即使回收後夠也不能先買；成功按原 claim 扣原價再回收；預覽／取消不動 uid、charges、HP、Gold；held confirm 不連買。 |
| Scroll 同軸四件裝備、受傷角色、護符替換、長雙語名字／詞綴 | projection 等於真正提交結果；最大 HP 成長不治療；所有受益件可讀；細節能捲到底，價格／錯誤／按鍵不被遮住。 |
| Collector 局部投入／完成／故意寫入失敗；Mutation 選擇與取消 reset；craft／forge／challenge | 僅持久化完成才出成功層；局部與失敗不假解鎖；reset 取消零扣款；同一交易入口決定費用／效果；重領不給第二份獎勵。 |
| 死亡／放棄／勝利儲存失敗及 retry；三槽 empty/protected/corrupt/checkpoint | 不顯示假已保存，不清掉舊 checkpoint；兩次確認覆寫與取消仍有效；結果的 BSC1 文案不承諾可玩。 |

既有 `tests/l3_build_probe.gd` 中依賴已刪顯示 helper 的部分，改測近戰／盾／技能／護符各自真語意；保留買不起、UID、充能、交易、投影與存檔斷言。`hud_readability_probe` 改用實際 `MathArt.ui_font()` 量寬，更新新幾何但保留不重疊／對比／HP 邊界斷言。含英文文案契約的既有 fixture 在開始時明確 `TranslationServer.set_locale("en")` 並 refresh presentation，維持既有英文回歸；新 product fixture 必須跑 zh_TW 與 en，而非把所有測試默認英文。

來源凍結後依序執行，各組一次；失敗修正後只重跑受影響組，未變來源可沿用有效結果：

```text
python tools/check.py --list
python tests/check_runner_probe.py
python tests/profile_path_probe.py
python tools/check.py --only "Import assets|settings_probe|ui_product_probe"
python tools/check.py --fast
python tools/check.py --only "world_map_probe|collector_display_probe|profile_selection_probe|reward_probe|esc_probe|audio_lifetime_probe"
```

`--fast` 的既有 13 項涵蓋 biome／save slots／terminal／HUD／build／Passage／Boss／route；不另外重跑同一批 focused gates。新字型首次 import 仍遵守原 30 秒 deadline，不因匯入慢而放寬診斷／期限；新 probe 的預期故障只針對該案例的已知訊息精確處理，不能 whitelist 一般 ERROR。此次不需要 900 秒雙路線操作測試，沒有 gameplay／route 變動。

### 實際畫面與完整操作證明

- 另在可見 display 執行 `python tools/check.py --capture ui-product`。fixture 依序實際開啟 title／saves／settings 各分類、ready／partial／empty HUD、Boss HUD、pause／abandon、Scroll、兩槽 compare、買不起 shop、Collector partial/unlocked/error、Mutation full/reset、craft/forge/challenge、map browse/travel/single-room、Hub／Archives／Skills／reward、death/victory/save-failed。每畫面保存 768×480 原生 frame，檔名包含 locale、裝置、場景與狀態，放在新的 `output/ui-product/` 證據目錄。
- 詳細狀態在 zh_TW 與 en 都 capture；裝置變化至少在 title／settings／pause／compare／map 各拍 keyboard 與 gamepad 提示。使用正式字型最長名稱與詞綴 fixture，加上沒有內容、受保護、買不起、已擁有、成功、失敗、取消。拒絕只檢字串長度或只看 key 存在的「可讀性」測試。
- 同一正式程序在初始 1536×960、手動 resize 1152×720、1280×720 黑邊、maximize／restore 下走查 title、HUD、pause、compare、settings。用系統截圖保存實際 window 成像；不可把 768 圖 resize 後標成 1536 視覺驗證。全螢幕切換可操作、10 秒不確認恢復舊模式，回視窗仍保留先前尺寸。headless probe 只驗狀態，不聲稱驗證 DisplayServer 實際模式。
- 為 modal reveal 與焦點連切各保存至少 t=0／50／100／150ms 的連續 frames 或短錄影，確認 focus 先改、動畫可中斷、文字不閃白、按鍵不等動畫。沿用真實 wall-clock；不以靜態截圖宣稱動效通過。
- 接一支真實手把走「標題→設定改音量→回 Hub→進區→拾取／買物／Scroll→暫停→地圖→返回」及服務頁選擇／取消，再測拔除後鍵盤接手。合成輸入通過不能聲稱硬體通過；沒有硬體則明記 pending，保留已完成軟體證據，不偽造結果。

### 人類可理解性的完成條件

給未讀規格的人看實際畫面並操作，先不解釋系統：能指出兩技能何時可用；說出新裝備怎麼用、換掉哪槽、付多少、回收多少與餘額；知道 Scroll 不回血；區分 Collector／Forge 永久與 Mutation／craft 本局效果；知道從 checkpoint 恢復會失去哪些較新戰鬥進度；能用手把關閉最近一層、切語言與調音量。每項保留錯誤理解與修正後複核，不能用代理看圖或測試 PASS 替代。美術滿意另請使用者實際審圖；在此之前只能宣稱工程通過，不能宣稱「已達 Dead Cells 級」。

## Assumptions & contingencies

- 已定範圍為全 UI／設定／雙語／手把閉環；預設繁中，可切英文。這輪用 UI 改善理解與操作，不新增裝備、關卡、敵人、治療承諾或 BSC 玩法；評論中 build 深度、生成探索、世界／音樂內容的問題仍需另外授權。
- 本計畫的字型例外限 Noto CJK 文字渲染。實作時同步修正 `docs/design/ui-system.md` 的「外部字型」禁令與相關 active entry 限制為此窄例外，仍禁止外部圖示與美術。官方固定來源不可下載時，不換來源或依賴 OS 字型冒充完成；先完成其餘可達工作並明記字型交付阻塞。
- 已確認的 Dead Cells 參考為公開圖錄的可觀察資訊層級／導航；靜態圖沒有證實原作動效，採 Ashfall 既有 100／120ms 規格。原圖、字型、動畫、文案與像素樣式不進遊戲。使用者可以於審查覆寫繁中術語與美術喜好，實作者不自行變更本計畫的玩法範圍。
- 鍵盤永遠完整可用，手把加入全部正式 UI 路徑；無真實硬體／可見 display 時分別保留硬體／視覺驗收 pending，不將合成事件或 headless 通過當成替代。Windows 發行包不在此 UI 計畫，不能以這輪通過宣稱已完成一般玩家發行交付。

參考來源：專案 [UI 規範](docs/design/ui-system.md) 與 [Dead Cells 圖錄](docs/research/dead-cells-ui-reference-atlas-2026-11-04.md)；[Noto 字型固定檔](https://github.com/notofonts/noto-cjk/blob/165c01b46ea533872e002e0785ff17e44f6d97d8/Sans/OTF/TraditionalChinese/NotoSansCJKtc-Regular.otf)、[同版 OFL](https://github.com/notofonts/noto-cjk/blob/165c01b46ea533872e002e0785ff17e44f6d97d8/LICENSE)；Godot 官方 [Translation](https://docs.godotengine.org/en/stable/tutorials/i18n/internationalizing_games.html)、[TextParagraph](https://docs.godotengine.org/en/stable/classes/class_textparagraph.html)、[ConfigFile](https://docs.godotengine.org/en/stable/classes/class_configfile.html)。

