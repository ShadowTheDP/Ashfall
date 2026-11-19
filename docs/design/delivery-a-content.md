# Delivery A: bounded route content

This content activates only the nine visits in `default_0_bsc_route` and the existing Canopy-unlocked Silt Cistern alternative. The world graph, thresholds, save schema, movement, gear catalog and existing five `floor_profile` mappings remain authoritative. No unauthorized expansion node receives a runtime profile.

Choose separate module tags and authored collision layouts because exploration should change the player's route and combat space, not just the biome name.
Reject copying external layouts or stat tables, granting every Rune, or enabling unfinished source biomes to make a test pass. All additions here are original Ashfall prototype content.

## Spaces and encounters

| Visit | Geometry and exploration | Encounters and resources |
| --- | --- | --- |
| Ash Gate | Existing fork, upper return and optional ability vaults. | Existing Husk/Watcher introduction; existing loot placements. |
| Hanging Gallery | Existing arch variants and elevated Canopy guard room. | Husk/Watcher/Leaper; guarded Canopy acquisition and existing caches. |
| Silt Cistern, alternative | Dedicated `cistern_*` modules replace the shared main-room candidates. Paired low shelves surround a thin basin crossing; the split ascends from the right and the merge returns by left shelves. | Husk/Spitter instead of Gallery's three-enemy mix. The Phase room has two guards, the lower crossing pays 6 Cells, the Canopy cache pays 16 and the Phase cache pays 24. The latter becomes usable after the actual Phase pickup. |
| Stone Ramparts | Existing keyed crossing and upper route. | Existing Husk/Bulwark and physical `rampart_key`/local lock. |
| Bridge Sentinel | Dedicated flat bridge arena and clear approaches. | `bridge_sentinel`, a dedicated boss ID for cleave, charge and travelling waves. Its defeat opens the onward Passage; this biome no longer declares `slice_end`. |
| Stilt Foundry | Extended two-lane route: lower press rooms and upper hoist join at a later merge. Broad gantry shelves have two combat variants. A Canopy detour sits above the upper lane. | Ram/Bulwark/Spitter; eight regular enemies across five rooms. Physical `foundry_key` is in the lower press, not at entry. The upper hoist pays 16 Cells; the Canopy casting cache pays 20. |
| Clock Spire | Shorter, denser ascent: lower and upper lanes reach a crown above the merge, then an upper-level exit. The crown has a one-way floor so ordinary jumps can enter from below. Two lower combat variants change the balcony side. | Watcher/Leaper; six regular enemies. Two guards protect the real `clock_rune` pickup in `upper`. Physical `clock_key` is in the crown. Crown cache 12 Cells, Canopy bell cache 18. |
| Clock Warden | Dedicated arena with two side balconies; the second candidate adds a higher pair while preserving the centre landing lane. | `clock_warden`, a dedicated boss ID for leap and projectile-lane patterns. No Rune is needed to use the low balconies or defeat it. |
| High Keep | Opposed courts joined by the existing type of ordinary stair split and return merge. Broad paired shelves and a colonnade variant provide space for shield and charge enemies. | Bulwark/Ram/Watcher; nine regular enemies. The lower court contains `court_key_left`, the upper court `court_key_right`. Both courts are reachable without an ability. Lower/upper caches pay 10/20 Cells; optional Canopy/Phase caches pay 22/28. |
| Silent Regent | Dedicated arena with two low side shelves and a clear central floor. | `silent_regent`, a dedicated boss ID for delayed columns and guard/sweep phases. Terminal victory and Homunculus award belong to the route runtime, not an unconditional room pickup. |

The main route still has six ordinary biomes and three boss visits. Replacing Gallery with Cistern changes geometry, enemies, permanent acquisition and cache yields; it does not add an extra visit. Ordinary enemies are encounters, not universal exit-clear requirements. Boss defeat remains mandatory.

## Loot, shops and progression

The new ordinary biomes retain `entry`, `split`, `lower`, `upper`, `merge` and `exit_main` room IDs. Existing `gear.json` placements therefore provide entry gold, a split Scroll, lower food, an upper chest, a merge shop and exit gear through the current owner. Equipment rolls and availability filtering remain with the gear/build runtime. No new loot-pool schema or unavailable item ID is introduced. Caches use the current Cell pickup path; encounter budgets add Cell and kill-gold opportunities without changing global prices, scaling or flask supply.

Foundry's extra lower room holds its route key; Spire's key is above the lower merge; Keep requires visits to both courts. These are physical pickups. They are not granted on entry and are not consumed by a local lock before a route edge checks them. Ramparts retains its legacy local key-door behavior. Keep uses the explicitly approved `keys` array with two `{id, room, at}` entries; all other keyed biomes retain the legacy singular `key` object. A biome must not declare both forms.

Canopy remains sourced from Gallery; Phase remains sourced from Cistern. `clock_rune` is sourced from the Spire guard room as declared by RouteGraph. Ground remains assigned to Bone Ossuary and Climb to Sleeping Engine; those source biomes belong to the unauthorized world expansion and stay inactive. Neither Rune is awarded, required on the Delivery A base path, nor used as evidence of fresh-profile reachability. Earlier optional Ground/Climb vaults remain optional future rewards. RouteGraph's BSC, Rune and key thresholds are unchanged.

Choose optional Canopy rewards and a late Phase cache because both abilities have legal acquisitions within the bounded content.
Reject relocating Ground/Climb or bypassing their world prerequisites; Delivery A proves a first clear and the Cistern alternative, while complete global acquisition remains Delivery B.

## Dimensions and original numbers

Geometry retains the 640 × 276 lattice, 32 px floor slabs, 13 px one-way decks and 92 px ordinary stair rise. New broad shelf widths use 244.46 px (approximately `640 × INV_PHI²`); Cistern's centre span is 151.08 px (approximately `640 × INV_PHI³`). Existing narrow shelves retain their 160 px unit. Every non-Phase connector has coincident world socket points and opposing normals for every compatible module pair.

The actual Player capsule is radius 14, height 46. Shelf rises remain below SurfaceReach's conservative 100 px cap; clearance around floor landings exceeds its 72 px requirement. The Spire merge's north socket and crown's south socket describe an ordinary jump passage, not a Rune edge. Its lower landing is on the final 184 px stair, with the crown another 92 px above it. The crown floor is deliberately one-way: a solid ceiling would prevent entry from below. Real CharacterBody2D play remains a required integration check.

Each new boss arena has one clear spawn at local `[400, -38]`. Body heights of 64/60/68 and radii of 20/18/22 fit the floor and central opening. Boss configs include Enemy's body, combat and reward fields plus canonical color metadata; MathArt semantic colors own the current render while the legacy `warden` config is preserved.

| Boss | HP | Damage | Speed | Base windup / active / recovery / cooldown | Cells |
| --- | ---: | ---: | ---: | --- | ---: |
| Bridge Sentinel | 440 | 18 | 76 | 0.68 / 0.18 / 0.62 / 0.80 s | 14 |
| Clock Warden | 620 | 19 | 98 | 0.70 / 0.16 / 0.68 / 0.85 s | 20 |
| Silent Regent | 820 | 22 | 60 | 0.82 / 0.22 / 0.78 / 1.05 s | 30 |

Bridge starts near the existing 380 HP Warden baseline, with slower charge/waves (490/410 px/s) and a longer base tell. Clock trades a smaller body and faster movement for 280 px/s projectiles and a 170 px leap rise, retaining recovery for retaliation. Regent moves slowly and offers longer base tells; health and damage rise to account for the intervening Scrolls, gear and full 0 BSC Passage supplies. These are original starting hypotheses, not a claim of balance acceptance. The common `boss` flag and 0.12 knockback multiplier retain resistance to ordinary hitstun and displacement.

Choose moderate health growth and readable base tells because later fights should test distinct patterns while still exposing punish windows.
Reject inflating ordinary enemy stats, changing Player numbers, or copying another game's scaling; pattern-specific timings and hitboxes are owned by RouteBoss and require runtime verification.

## Isolated content snapshot evidence (historical)

The bounded findings below predate integration; human balance remains unaccepted.

Only `data/biomes.json`, `data/route_profiles.json`, `data/room_modules.json`, `data/enemies.json` and this document change in this content snapshot. Module schema version remains 1; the only new biome field contract is the explicitly approved optional `keys` array. Strict validation, generation, physical pickups and map markers for this array preserve the first-key legacy alias. RouteBoss dispatch and phase-specific config fields are separate responsibilities.

Static checks passed across 45 modules, 83 room/module candidates, 89 edge/module combinations, 210 enemy-body spawn checks, 8 physical-key candidate positions and 54 inherited loot-marker positions. They also checked complete route-key declarations, legal guarded Rune sources, walk-only main graphs, original five profile mappings and the exact 10-node content boundary. A separate Python translation of the current SurfaceReach arc/support rules passed all 13 module combinations for Cistern, Bridge and the five new biomes in 26 ability states (empty and Canopy + Phase), checking required rooms, physical keys and global enemy spawns. This translation is static geometry evidence, not an execution of the Godot validator. Loot marker support is distinct from full Player-body reachability; the inherited split Scroll sits near the edge of its closed Ground seal.

The snapshot has no engine/assets/cache. No Godot process, physics suite, playthrough, capture or save operation was run. Runtime verification must cover strict schema negatives for `keys`, seeded generation and SurfaceReach over the expanded catalog, actual Player movement through the Spire crown and Cistern basin/stairs, both court pickups before the final exit, existing five-node regressions, all three bosses and the two complete route variants. Static evidence does not establish human balance or complete route acceptance.
