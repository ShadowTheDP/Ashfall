# L2：房間圖、能力與地圖契約

歷史設計（原 L2-01..05）：保留當時五個 runtime biome 的生成設計與驗收記錄；舊 roadmap 已刪除，編號只供追溯。其後擴充為十個 runtime profiles，目前內容、狀態與人工 gate 以 [route-runtime.md](route-runtime.md) 及 [current-state](../agent/current-state.md) 為準，不假稱完成 19 節點或人工手感驗收。

## 2026-11-04 有界升級授權與待驗契約

2026-11-04 使用者採納了一項有界的精修／生成指令，把當時純 UI 工作擴至 Delivery A biome 內部的房間圖／空間組裝變化。該階段現已完成並屬歷史；後續 2026-11-15 全遊戲多色授權另行取代舊色彩限制。世界路線、九訪問、三 Boss、合法 Cistern、Rune／key／出口及敵人／經濟總預算仍不變，且不開未授權的擴充世界、BSC 1–5 或 19 節點。

準備保存現有 generator／表／tests／tools／docs 原始 bytes 與十個 profiles 的 seeds1..32 實測 signature／耗時，見 `output/ui-refinement-map-2026-11-04/`。Ash Gate 是第一個 pilot；authored 合法布局候選或有界 placement 的最小方案由基線缺口決定，準備階段不預選通用 solver。空間 signature 排除 template／敵人名稱，保留房間身份、位置、bounds、socket／edge 模式及實體幾何，不能把換模板數當新布局數。

canonical layout 同時供 Level、spawn、collision、map、loot、checkpoint 與出口使用。schema/socket／footprint／clearance／SurfaceReach 及真實 Player 物理驗證保留；圖連通和 metrics 不是正常兩路線行走證明。相同 seed／revision 可重現，無合法候選須有界失敗且保留舊 scene/run state。

`RunCheckpoint` v1 八表 stamp 不含算法版本或 traversal；新生成不能默默改變舊 Continue。缺 revision 的 checkpoint 應綁定原算法／原內容，新 run 才明示新 revision，Passage 續入也保留該 revision。具體版本／資料策略須由 generation/save owner 實作並以隔離舊 v1 fixture 證明；不得放寬 stamp、刪 checkpoint、清永久資料或要求玩家放棄舊 run。這是驗收契約，不是已實作兼容層。

選擇先量測再做可達、可恢復的 Ash Gate pilot，因為探索差異必須保住原存檔與平台碰撞。
放棄固定格位換 template 的假多樣性、Unity 依賴、無界搜尋及未驗證自動遷移。

## 資料與生成（目前繼承實作）

- `data/room_modules.json`：原創房間模組，明確尺寸／biome tags／roles、實心與單向碰撞、帶方向的 socket／落腳點、enemy／loot 候選點。
- `data/biomes.json`：每個 biome 的 concept graph、格位、模組角色、支路／合流／獎勵／能力室、出口、門與 key／Rune 取得點。數值與版型為 Ashfall 原創。
- `BiomeGen` 只選擇合法模組並平移既有碰撞；walk socket 必須位置重合、朝向相反，vine／phase／break 路線需明確標記模式與能力。
- 所有正式 biome 使用新生成器；舊 `LevelGen.generate(floor, seed)` 保留為既有物理與 Boss 測試 fixture。相同 node／seed 重現相同房間／敵人配置。
- 舊 BFS 僅是表面幾何關係。新驗證另檢查碰撞／落腳點、能力狀態與 key-before-door，並以實際角色行走／跳躍／攀爬測試證明分岔與合流，不把幾何 BFS 當物理證明。
- 驗證先把同一薄樓板按牆／低天花／門切成連通表面，能力邊必須先到來源並有安全目標支持面；key 與出口使用實際座標，不因 room id 相同便算可達。敵人用資料中的實際寬高檢查 spawn slots／clearance。
- schema 缺必填欄位、錯型、socket 不相容、重複 gate ID 或碰撞不可達均拒絕；Main 在改寫 run history／釋放原場景之前預先生成，失敗保持原狀。

## 出口與 Passage

每個目的地有 biome 內的獨立實體出口；以短二維距離互動，不能從不同樓層誤選。Game 在 biome 階段重新驗證出口、鎖因與 Boss 條件，保存 pending destination；route history 只在到達新 biome 後增加。死亡／放棄清 pending。

Passage 只有服務和已選目的地的繼續門，不再選路。進新 node 必須符合 pending destination；第一 Boss 後繼續正式路線，最終勝利須符合九訪問／三 Boss 契約，不以早期第一 Boss 切片完成代替。

## 能力與鑰匙

- Canopy：靠近藤蔓按 W/Up 攀爬、S/Down 下降，Space 跳離；未取得時不能附著。主路與首次 Canopy 取得房不以 Canopy 自我鎖住。
- Climb：貼牆朝牆移動並按 Up 可攀牆，Space 可跳離；離開牆、受傷、死亡／轉場解除攀爬。
- 空中 S+Space 優先進下砸，地面 S+Space 保留下穿單向平台。下砸本身不要求 Rune；只有 Ground Rune 能破壞標記的地板，普通地板永不被破壞。
- Phase：R 啟用成對的相位標記；需要 Phase Rune、活著且安全的目標落腳點。傳送後清速度／攀爬／下穿狀態並重設插值，不修改 HP、Cells 或永久進度。
- 普通 checkpoint 與 Phase 不同：checkpoint 不要求 Rune，啟用後可從另一個 checkpoint 的地圖選單返回；Tab 從任意位置開圖只能瀏覽，不提供任意位置免費傳送。
- Keys 為當輪資源；實體 key 門消耗一次 key，開啟狀態保留至離開 biome，重複互動不重複扣除。鑰匙位於門之前的可達房間；非必要敵人不阻擋普通出口。
- 當前正式路線內的 Rune 取得包括 Gallery 的 Canopy、Cistern 的 Phase 與 Clock Rune，最終合法勝利取得 Homunculus；具體來源見 [route-runtime.md](route-runtime.md)。Climb／Ground 的操作與守衛拾取契約以物理 fixture 驗證；其正常來源屬未授權的擴充世界，不能以測試授予冒充玩家已能取得。

## 探索與輸入

房間以真正二維 bounds 啟動，discovered 與 cleared 分開。Tab 開／關地圖，Left/Right 切 biome／世界圖，Up/Down 選已啟用 checkpoint，Enter 只在 checkpoint 互動模式傳送；Esc 只關閉地圖。未知房間、服務與未發現傳送點不揭露。

地圖為 modal，開啟時凍結世界；F/H、J/K/L、Space、R、Enter 不穿透至治療／攻擊／下穿／選路／放棄。僅在活著且 biome／Passage 正常狀態可開圖，轉場與其他 modal 不可疊開。永久世界發現紀錄寫入 Profile，局部 room discovery 只屬本次 biome。

## 驗收

L2 當時結果：32 seeds ×5 biomes ×16 Rune 狀態的 sweep 為 2759 checks／0 failures；真實 120 Hz 物理與輸入 48／0（display capture 同樣通過）；雙路線108／0，V3 flow-only52／0。這些不是最新整合測試數字，當前證據見 [current-state](../agent/current-state.md)。`output/screenshots/biome/` 保存該階段分岔、探索／世界圖、藤蔓、破地、鎖門／開門；這些是自動輸入證據，人工手感仍未驗收。

隔離存檔：模組／socket schema 反例、相同 seed 重現、五 biome 的能力狀態 sweep、blocked landing／牆阻擋、實際角色分岔合流、疊層房分別啟動、Rune 拾取前後、key 消耗、實體出口留敵、Passage 固定目的地、地圖隱藏未知／modal／checkpoint，以及死亡／放棄 pending 清理。

公開參考：[Sébastien Bénard 的生成設計文章](https://deepnight.net/tutorial/the-level-design-of-dead-cells-a-hybrid-approach/)明確分為固定世界、手作且依 biome／目的區分的 tiles、concept graph、相容隨機組裝、敵人配置與 loot。L2 對齊這個分工；當前共用部分模板、簡化 encounter 和未完成交易仍是差距，不能宣稱一比一重現現行內部生成。

選擇獨立的模組圖生成與薄樓板，因為舊連續厚地基會埋住疊層路線；仍重用 Level 的角色、敵人、拾取與測試接點。
放棄用裝飾假裝房間分支、用預填全部 Rune 證明 fresh 進度，或繼續在 Passage 改目的地；代價是本輪要同步遷移流程 probes，完整能力取得內容屬未授權的後續擴充世界。

## 2026-11-06 isolated generation lane: authored spatial revision

The bounded implementation adds `data/generation_spatial_v2.json` with three
explicit spatial embeddings for each of the seven ordinary Delivery A profiles.
`low_fork` preserves the old embedding, `long_fork` uses authored combat/guard
modules of width `640 × PHI = 1035.5417528` and moves downstream rooms by the
matching width, and `high_fork` raises the upper branch and its attached rewards
by one 276px tier. Taller split/merge modules use ordinary 92px stair rises.
Clock Spire retains its crown above the lower merge; Foundry retains both lower
press and upper hoist crossings. Cistern retains its split slab and ability
rewards. Boss arenas remain controlled. Conceptual edges, room IDs, roles,
enemy/cache budgets, physical keys, Rune sources and route exits are unchanged.
This is three spatial embeddings per ordinary profile, not three topologies.

`BiomeGen.generate()` defaults to `spatial_v2` for direct generation tools.
`generate_checked()` returns layout, revision, variant, attempted candidate count
and errors. Selection is `posmod(seed, variant_count)`; there is exactly one
authored attempt and no fallback, rotation, reflection, runtime module scaling,
unbounded search or position jitter. JSON stores full original module geometry;
its small node overrides can change only grid and compatible template pools.
Original pools are fixed before versioned modules are added, so a new hall cannot
accidentally enter an unrelated room's pool. The legacy assembly body, RNG seed
and original successful candidate ordering remain available as `legacy_v1`.

Canonical room origins/bounds, slab width, collision surfaces, sockets, enemy
spawns, caches, keys, checkpoints, exits and inherited local loot offsets all
come from the same generated coordinates. Footprints reject positive-area
intersections and allow shared boundaries; the existing support slabs may occupy
the 32px immediately below a room footprint. Collision envelopes and cardinal
socket directions/modes are checked before accepting a new layout. Existing
SurfaceReach still checks actual bodies, headroom, one-way arcs, physical keys,
markers and ability states; it is not a real Player movement proof.

Choose small authored embeddings because the measured baseline has one embedding
per profile, and a wider crossing/high branch creates a measurable route cost
without introducing a general solver or changing progression.
Reject a socket-search framework and cosmetic template-only variation because
neither is needed to address the measured spatial repetition.

Lane evidence: `python tests/generation_schema_probe.py` passes seven profiles,
21 distinct authored embeddings and six rejected static defects. The genuine
pre-upgrade metrics fixture records seed 1/17 for all ten profiles in
`tests/fixtures/generation_baseline_layouts_v1.json`; its provenance names the
full BEFORE raw evidence SHA256. `generation_spatial_probe.gd` compares those
canonical layouts and checks bounded failures. Central integration subsequently
passed spatial82, revision36, original32-seed/16-Rune5479 checks in32.76s,
and high/low/long physical fixtures55/52/52 inside30s each. The bounded ordinary
Ash Gate/Gallery input diagnostic earned Canopy; it is not full-route acceptance.
AFTER320-layout/1600-check metrics passed34.67s inside35s, with ordinary
embeddings1→3 and topology unchanged. Generation median36.04ms versus14.30ms
before is a measured cost. The map gallery, metrics, source hashes and complete
failure ledger are in `output/ui-refinement-map-2026-11-04/integration/`.
Complete ordinary dual routes and human play/feel/two-route acceptance remain pending
independent integrated review; static or physical fixtures cannot sign them.


## Central verification performance repair — 2026-11-06

The failed18s A4 records prompted measured validation/preparation work, without
changing its assertions/deadline. Spatial schema validation now checks every
original/versioned module and invariant biome once, then every affected biome
for each authored variant. Preparing a variant copies only the changed biome
and dictionary containers; it does not mutate the shared source tables. The
legacy assembly body, RNG/candidate order, revision and JSON tables are intact.
New regressions include malformed unused original/versioned modules, an invalid
other biome/variant, invalidating module overrides and input immutability.

Same-fixture timings:21-variant validation222.220→38.101ms and preparation
23.874→12.864ms; median generation of30 cases16.821→16.283ms. Every one of
those30 complete canonical layouts matched exactly, and the20 genuine legacy
layouts remain covered. These measurements do not attribute every observed A4
timeout to validation. Native A4 subsequently passed362 checks/13.947s within
its original18s; all failed attempts remain in the verification directory.

Choose invariant validation once plus exhaustive per-variant biome checks
because the same module schemas were repeatedly scanned without changing.
Reject mutable-dictionary success caches, skipped unused content, weaker
assertions and longer deadlines; they would hide invalid data or performance.
