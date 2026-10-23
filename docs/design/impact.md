# 打擊感規格（單色）

本文件固定「命中瞬間到底發生什麼事」。所有數值以 768×480 邏輯像素、60 fps
計（`1f = 16.7 ms`），速度為 px/s。**沒有顏色**，所以全部靠形狀、明度、
方向與時間。

規格來源見文末；數值是本專案的調參起點，不是任何遊戲的內部參數。

---

## 1. 強度分級

每一擊都有 `tier`，寫在 `data/weapons.json` 的每一段攻擊裡：

| tier | 名稱 | 誰用 | hitstop | 鏡頭震動 | zoom punch | 全屏回饋 |
|---:|---|---|---:|---:|---:|---|
| 0 | LIGHT | 第一段 | 2f (33 ms) | 0.16 | 無 | 無 |
| 1 | MEDIUM | 第二段 | 4f (67 ms) | 0.30 | 無 | 無 |
| 2 | HEAVY | 擊殺 / Boss | 6f (100 ms) | 0.52 | 0.45 | 有 |
| 3 | FINISHER | 第三段 | 8f (133 ms) | 0.72 | 0.75 | 有 |

暴擊自動升一級（上限 3）。**同一幀命中多個目標不疊加**，取最高級。

---

## 2. 命中瞬間的三層

`scripts/fx/impact_fx.gd`，由 `Combat.impact(point, direction, tier)` 生成。

### 第 1 層：白色閃光（1–2 幀）

| tier | 尺寸 |
|---:|---:|
| 0 | 10 px |
| 1 | 13 px |
| 2 | 18 px |
| 3 | 24 px |

命中後 **33 ms** 內是一個「十字 + 方塊」，alpha 由 1 線性降到 0。
只作用在接觸點，**不做整屏反相**。

### 第 2 層：擴張環

| tier | 最大半徑 | 持續 | 線寬 |
|---:|---:|---:|---|
| 0 | 18 px | 5f | 2→0.75 px |
| 1 | 24 px | 6f | 2→0.75 px |
| 2 | 36 px | 8f | 2→0.75 px |
| 3 | 54 px | 10f | 2→0.75 px |

tier ≥ 2 時多一圈 `1/φ` 的內環。**圓心是接觸點**，不是角色中心。

### 第 3 層：方向性火花

| tier | 數量 | 長度 | 初速 | 壽命 |
|---:|---:|---:|---:|---:|
| 0 | 8 | 9 px | 250 | 0.13 s |
| 1 | 10 | 13 px | 330 | 0.15 s |
| 2 | 12 | 19 px | 430 | 0.18 s |
| 3 | 16 | 27 px | 560 | 0.21 s |

- 以**命中法線**為中心扇出 ±80°，不是均勻全向。
- 速度曲線 `1 - (1-k)^2.4`：大部分位移在前 3 幀完成。
- alpha：`1.0` 到 35%，之後 `0.55 → 0`。
- 頭部有 2×2 px 白點。

---

## 3. 全屏層（tier ≥ 2）

`scripts/fx/screen_punch.gd`，掛在 `ScreenFxLayer`（layer 25，低於 HUD）。

| 效果 | 參數 |
|---|---|
| 暗角脈衝 | 邊緣 alpha 0 → 0.10–0.20，1 幀到峰值，8–22 幀歸零。**中心保持清晰** |
| 掃描帶 | 1–2 條 1–2 px 水平帶，各偏移 ±2–4 px，只存活 **2 幀** |
| zoom punch | 相機 zoom ×1.025，2 幀到位，5 幀 ease 回原值 |

**不做**：整屏反相、常駐故障濾鏡、全屏位移。

---

## 4. 揮擊本體

`scripts/player/player_visual.gd` 的 `_draw_smear`。

**最重要的規則：不要畫任何連續的填充形狀。**
刀刃長 38–50 px 時，任何實心扇形或新月都會變成「月餅」。
所以斬擊只用**斷開的直線**表達：

| 元素 | 做法 |
|---|---|
| 主體 | 4 圈 × 3 段的**斷開直線**，每段沿刀刃的切線方向飛出 |
| 半徑分布 | 0.55 / 0.70 / 0.86 / 1.02 倍刀長（由內到外） |
| 落後量 | 內圈落後 72%，外圈在刀尖上 |
| 長度 | 7–20 px，越靠前越長 |
| alpha | 0.75 → 0.25，越靠後越淡 |
| 尖端主線 | 3 px 白線 + 1 px 純白核心，沿刀刃正前方 26 px |
| 數學點綴 | 3 個黃金角間距的點，落在 0.60 倍刀長處 |
| 刀尖延遲點 | 1 幀前的刀尖位置，45% alpha |

**為什麼用斷線**：斷開的直線無法圍出形狀，只能讀成「速度」。這是唯一
在 38–50 px 半徑下不會變成月餅的畫法。

**握點**：在方塊**下半部**的前緣 `(facing × 13, +4)`，劍靜止時**朝上**
（`REST_ANGLE = -1.30` rad）。揮擊由「上後方」掃到「前下方」。

---

## 5. 握點與比例（幾何對齊）

原本的三個問題與修正：

| 問題 | 修正 |
|---|---|
| 手點在方塊內部 `(7,-7)`，劍看起來從身體裡長出來 | 握點移到**前緣** `(facing × 13, -7)`，並隨朝向鏡射 |
| 可見刀刃 24 px，但 hitbox 到 72–85 px | 刀刃長度寫進 `data/weapons.json` 的 `blade`（38/40/50），hitbox 由它推導 |
| SlashFx 圓心偏離手點 14–17 px，半徑也不對 | 圓心 = 握點，半徑 = 刀刃長度 |

**幾何關係**（`data/weapons.json`）：

```
reach = hand_x + blade + 5        // 手點 13，刀刃 38 → reach 56
size  = [reach, 52 或 60]
offset = [reach / 2, -7]
```

所以畫出來的刀尖、斬擊弧、傷害判定三者是同一組數字。

---

## 6. 其他回饋

| 事件 | 內容 |
|---|---|
| 擊殺 | 輪廓碎片 12 片（Boss 24）+ tier 1–2 impact + 粒子 + punch |
| 格擋 | 10 條短火花 + 4 亮點（`Juice.block`）+ 環 + tier 0 impact |
| 完美閃避 | 8 射線（3 幀）+ 2 幀凍結 + 粒子 + `EDGE +25%` |
| 受擊 | 4 條紅→白射線在**接觸邊緣** + 10 幀受擊硬直 + 全屏白閃 0.10 alpha |

---

## 7. 十件讓打擊變「爽」的事（依重要性）

1. 接觸點必須是**真的碰撞點**，誤差 ≤ 2 px。
2. 目標剪影 2 幀純白，之後 2 px 白框淡出。
3. hitstop 依 tier 分 2/4/6/8 幀，多目標不疊加。
4. 火花從接觸點沿法線扇出，至少 8 根、初速 ≥ 250 px/s。
5. 擴張環在 5–10 幀內完成。
6. 刀痕與命中火花**分層**：前者沿刀路，後者從接觸點噴。
7. 擊退在前 3–5 幀看得見。
8. 鏡頭震動分級：普通 ≤ 2 px，重擊 ≤ 4 px。
9. 殘影 ≤ 2 個、總壽命 ≤ 3 幀，不要糊成白塊。
10. 擊殺碎片沿輪廓取樣，與一般受擊的細火花明確區隔。

---

## 8. 常見錯誤與對應修正

| 症狀 | 原因 | 修正 |
|---|---|---|
| 打起來像在戳空氣 | 火花從敵人中心出現 | 改用 `info["point"]`（真實接觸點） |
| 每一下都一樣重 | 沒有 tier 分級 | 用 `data/weapons.json` 的 `tier` |
| 畫面被白光吃掉 | 整屏反相 / 大面積白閃 | 只反轉目標輪廓，全屏只做暗角 |
| 斬擊像一個實心圓 | 扇形填滿整個揮擊角 | 改新月 + 只畫已走過的那一段 |
| 劍從身體裡長出來 | 握點在方塊內部 | 握點放前緣 |
| 打得到但看起來打不到 | hitbox 與刀長不一致 | 用 `blade` 推導 hitbox |
| 淡灰長尾糊成一團 | 火花壽命太長 | 火花 ≤ 0.21 s，碎片 ≤ 0.5 s |

---

## 參考

畫面特徵觀察（不代表其內部數值）：**Dead Cells** 的受擊閃白與擊退、
**Katana Zero** 的斬線與停頓、**Hyper Light Drifter** 的方向性斬弧、
**Blasphemous** 的重擊面積與碎裂、**Hollow Knight** 的短促接觸火花、
**Celeste** 的殘影與塵點、**Nuclear Throne** 的擊退與屏震、
**Enter the Gungeon** 的命中粒子、**Skul** 的輕重攻擊視覺階差、
**Hades** 的分層斬痕、**Guilty Gear** 的大型 hit spark、
**Street Fighter** 的強度分級 hitstop。

- [Juice it or lose it — Jonasson & Purho](https://www.youtube.com/watch?v=Fy0aCDmgnxg)
- [The Art of Screenshake — Vlambeer](https://www.youtube.com/watch?v=AJdEqssNZ-U)
- [Eight Hit Stop Techniques — Sakurai](https://www.youtube.com/watch?v=tycbMSjDDLg)
- [Why Fighting Games Have Hitstop — Sajam](https://www.youtube.com/watch?v=KL5MNHGs5Fg)
- [Game Feel — Steve Swink](https://www.routledge.com/Game-Feel-A-Game-Designers-Guide-to-Virtual-Sensation/Swink/p/book/9780123743282)

## 7. The smear has exactly one owner

`SlashFx` (`scripts/fx/slash_fx.gd`) is the **only** thing that draws the
swing trail. `PlayerVisual._draw_smear()` is intentionally empty.

This was not always true, and the duplication was the actual cause of the
"mooncake" and of the trail fusing with the blade into an L:

- `SlashFx` drew three **concentric bands** (4 px, 3 px, 1 px) across a
  2.1-2.9 rad arc. At 38-50 px radius that is a filled crescent.
- `PlayerVisual._draw_smear()` drew a second, independently-phased arc from
  the grip. Two arcs with different origins overlapped into one solid shape.

Rules that now hold:

1. **One radius, one owner.** Trail = `SlashFx` dashes on the tip's radius.
2. **Dashes, never bands.** 4 dashes over a 0.95-1.35 rad span, widths
   1.2 -> 2.6 px, alpha 0.42 -> 1.0 (bright end leads).
3. **The trail never touches the blade.** It ends 0.30 rad short, and it
   lives behind the blade, so blade + trail cannot read as an L.
4. **Span is capped, not proportional.** `arc` is a constant per combo step.
   Scaling it with the live swept angle made long swings produce giant arcs.
5. **`_coil_angle()` must go through `_mirror()`.** Without it a left-facing
   swing travels ~5 rad instead of ~3.2 and the whole trail becomes a band.
   This bug was invisible on the first two combo steps (they happened to
   land near the mirrored value) and only showed on the third.

## 8. Shadows

Both player and enemies use three stacked 20-gons (scales 1.00 / 0.72 / 0.42,
alpha 0.14 / 0.16 / 0.18). Cumulative centre density is about 0.30 and it
fades to nothing at the rim. A `Rect2` shadow was tried and rejected: a
hard-edged black bar reads as a rendering bug, and the cast is already
straight-edged enough.
