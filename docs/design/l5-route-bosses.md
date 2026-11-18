# L5 route boss integration contract

The isolated boss snapshot is integrated into Level and the ten-profile content catalog.
Runtime evidence is recorded in the current-state file. The snapshot
statements below explain the original bounded contribution, not current acceptance.

Choose three different spatial problems because the player should answer Bridge with
jump/roll timing, Clock with committed landing avoidance and height changes, and Regent
with movement between delayed columns followed by a rear punish or a recovery punish.
Reject homing, permanent armour and damage inflation as substitutes for distinct attacks.

`RouteBoss` extends `Enemy`: configure before adding it to the tree. Instantiate it only
for `bridge_sentinel`, `clock_warden`, `silent_regent`; keep the legacy Warden fixture on
Enemy. Use the exact kind ID as the configure argument, with that kind's enemy cfg.
The existing Enemy `boss` lifecycle owns Game.boss, died, Cells and kill bookkeeping;
route rewards/terminal settlement remain the parent's existing flow, not this controller.
The subclass takes a private config copy and forces boss=true and shield=false; MathArt
semantic colors own the current Boss render.
The kind-specific guard sets shield only around a hit in its guarded window.

Integration reach: the Level enemy factory/boss spawn mapping must construct RouteBoss
for these three IDs; content validation/catalog must accept the fields below; the runner
must register `tests/l5_boss_probe.tscn` with a measured bounded timeout. No other caller
needs a different signature: `configure(kind_id, config, hp_scale=1.0)` and `died(Enemy)`
are inherited. Level must own/free the boss on transition as it owns ordinary enemies.
All hazards are top-level children of that boss, so scene removal frees them. They do
not use Game.fx_root and do not require a new global purge group. Death disarms them
immediately; projectile callbacks also reject a dead/missing source or run-over.

Required positive numeric cfg keys are exposed by `RouteBoss.required_fields(kind_id)`:

| Scope | Fields | Fixture values only |
|---|---|---|
| All | hp, body_radius, body_height, speed | 500, 22, 60, 70 |
| All | damage, windup, active, recovery, cooldown | 16, 0.45, 0.28, 0.55, 0.7 |
| All | attack_range, knockback | 600, 220 |
| Bridge | charge_speed, shockwave_speed, shockwave_damage, wave_life | 480, 320, 12, 1.25 |
| Clock | leap_time, leap_speed | 0.65, 420 |
| Clock | lane_speed, lane_damage, lane_interval, lane_life | 280, 10, 0.4, 1.6 |
| Clock | lane_lower_height, lane_upper_height | 16, 64 above floor |
| Regent | column_width, column_height, column_spacing | 36, 110, 80 |
| Regent | column_delay, column_active, column_damage | 0.5, 0.3, 14 |

`attack_range` is the existing Enemy spelling (not `range`). `cells`, `name`, `boss` and
other standard Enemy/HUD metadata can remain in content normally. The numbers in the
last column are explicit probe fixtures, not a claim of shipped or human-balanced tuning.
Content should choose `column_spacing > column_width`, lower height near feet and upper
height above a grounded player's head, so the tests' intended safe spaces exist. Keep
windup readable and recovery punishable; no Player/acceptance changes are required.

At strictly below half HP the next attack uses a distinct pattern. A windup snapshots
its phase, facing, target and zones; crossing half HP cannot add unannounced lanes.
Bridge: cleave/charge/wave becomes charge/wave/cleave/wave. Clock: leap/two alternating
lanes becomes four alternating lanes/leap/four lanes. Regent: three columns/sweep becomes
five columns/guard/sweep. Guard suppresses exposure crits from the front; rear attacks
remain crit eligible and recovery has normal damage. Boss hits never cancel their state
or deflect their committed velocity. Base poison/death handling remains in use.

Floor queries use WORLD|ONEWAY from body height, with a depth derived from body height.
Columns only spawn where a ray finds a surface. Waves and lane projectiles use the
actual floor minus the configured/physical height, without absolute-Y writes. The
arenas must offer a continuous fighting surface: horizontal waves stay at their launch
height and ignore world collision (shared Projectile behavior). Leaps clamp horizontal
travel to leap_speed*leap_time, use Enemy.GRAVITY, and do not home. During flight only,
the boss excludes Player from its own motion mask so landing on the player's head cannot
replace the advertised floor landing. A wall or early raised-deck landing outside the
marked rectangle aborts damage; recovery restores the ordinary Player collision mask.

Every danger rectangle uses the same sizes/origins as its collision. Moving projectiles
advertise their swept corridor; world walls can shorten Clock's shot. Leap marks only
the landing hitbox. Floor columns retain their exact outline throughout their extra
delay. Shapes use MathArt tonal/semantic colors and PHI, hit effects use the inherited Combat path,
and particles use Juice. No faces, limbs, textures or particle simulation were added.

There are at most 12 owned live hazards. Projectiles live at most 6 seconds; column
delay+active is capped to 6 seconds. If content exceeds those caps, timing is clamped;
the hazard cap retires the oldest hazard. Use values below the caps for intended play.

Original snapshot validation request (subsequently executed by the parent; see
[current-state](../agent/current-state.md)):
import/compile, execute the isolated profile fixture scene,
then combat/soak/impact and route integration checks, display captures and human two-route play.
The fixture uses production Player, Hitbox and Projectile with deliberately controlled
placement, frozen player processing, and direct attack selection. It checks configured
damage in both directions, every attack type including upper lane, phase threshold and
patterns, committed attacks under repeated hits, translated floor geometry, hazard caps,
TTL expiration, death cleanup and scene removal. It is not a hands-off full-play pass.
The isolated snapshot had no engine/assets/cache. Its static-only result is superseded
by parent runtime tests and full keyboard runs; neither establishes human balance signoff.
