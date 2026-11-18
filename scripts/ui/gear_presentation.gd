class_name GearPresentation
extends RefCounted
## Read-only player-facing reading of one RunBuild item.
##
## This is presentation, not combat: every damage/health number comes from
## RunBuild.display_stats(), every recharge from RunBuild.cooldown(), and every
## combo value from data/weapons.json. It never creates or retires an item,
## spends gold, ticks charges, touches Profile, or repairs a save. Callers that
## need the current-HP result of a replacement use RunBuild's projection API;
## describe() deliberately has no current_hp argument.
##
## Pure and side-effect free. Callers should refresh their presentation when the
## focused item, locale, or build changes; this helper keeps no cache because a
## mutable build/item would make cached text stale.

## data/gear.json carries no display names for qualities, statuses, playstyle prose, or kind/axis labels.
const QUALITY_EN := {"plain": "Plain", "etched": "Etched"}
const STATUS_EN := {"poison": "Poison"}
const KIND_EN := {"weapon": "Weapon", "skill": "Skill", "amulet": "Amulet"}
const AXIS_EN := {"brutality": "Brutality", "tactics": "Tactics", "survival": "Survival"}
const PLAYSTYLE_EN := {
	"rusty_sword": "Balanced three-hit combo; the finisher releases a wave.",
	"arc_saber": "Fast, wide slashes; lower damage per hit.",
	"kiss_precision": "Narrow, fast strikes with a higher crit multiplier.",
	"fractal_edge": "Slower swings; the heavy finisher releases a wave.",
	"chain_lash": "Longer reach, slower swings.",
	"orbit_rings": "Short, rapid combo; the first hit deals less damage.",
	"fold_shield": "Briefly guards one frontal hit, then counters in close range.",
	"kunai": "Automatically seeks the nearest enemy; flies in an arc.",
	"aegis": "Briefly blocks one hit and counters all nearby enemies.",
	"ash_charm": "Raises maximum HP; does not heal.",
}


static func describe(build: RunBuild, item: Dictionary) -> Dictionary:
	var details: Array[String] = []
	if item.is_empty():
		return _empty(details)
	var cfg: Dictionary = build.definition(item)
	if cfg.is_empty():
		return _empty(details)

	var kind := str(cfg.get("kind", ""))
	var name := ContentText.name("gear", str(item.get("id", "")), str(cfg.get("name", item.get("id", ""))))
	var stats: Dictionary = build.display_stats(item)
	var identity := _identity(build, item, cfg)
	var quality_affix := ContentText.of("UI_BUILD_QUALITY_AFFIX", "{quality} / {affix}").format({
		"quality": _quality_name(str(item.get("quality", ""))),
		"affix": _affix_name(item),
	})
	details.append(name)
	details.append(identity)
	details.append(quality_affix)
	if kind == "amulet":
		details.append(_amulet_stat(stats))
	else:
		details.append(_damage_stat(stats))

	if kind == "amulet":
		details.append(ContentText.of("UI_GEAR_AMULET_PASSIVE", "Passive; no charges or recharge."))
		details.append(ContentText.of("UI_GEAR_AMULET_NO_HEAL", "Raises maximum HP only; current HP is not restored."))
	elif cfg.get("action") == "melee":
		_append_melee(details, cfg)
	else:
		_append_charge_lines(item, stats, details)
		if cfg.get("action") == "shield":
			_append_guard(details, cfg, true)
		elif cfg.get("action") == "aegis":
			_append_guard(details, cfg, false)
		elif cfg.get("action") == "kunai":
			details.append(ContentText.of("UI_GEAR_KUNAI_TARGET", "Auto-targets the nearest enemy; the knife flies in an arc."))
			details.append(ContentText.of("UI_GEAR_KUNAI_CRIT", "Can crit when the target is exposed or backstabbed."))

	_append_affix(details, cfg, item)
	return {
		"name": name,
		"playstyle": _playstyle(str(item.get("id", ""))),
		"condition": _condition(kind, str(cfg.get("action", ""))),
		"headline": _headline(cfg, stats),
		"details": details,
	}


static func _empty(details: Array[String]) -> Dictionary:
	return {
		"name": ContentText.of("UI_STAT_EMPTY", "Empty"),
		"playstyle": "",
		"condition": "",
		"headline": "",
		"details": details,
	}


static func _identity(build: RunBuild, item: Dictionary, cfg: Dictionary) -> String:
	var kind := _kind_label(str(cfg.get("kind", "")))
	if not cfg.has("attribute"):
		return ContentText.of("UI_GEAR_IDENTITY_PASSIVE", "{kind} / {passive}").format({
			"kind": kind,
			"passive": ContentText.of("UI_GEAR_PASSIVE", "PASSIVE"),
		})
	return ContentText.of("UI_GEAR_IDENTITY", "{kind} / {axis} {level}").format({
		"kind": kind,
		"axis": _axis_label(str(cfg.attribute)),
		"level": build.level(item),
	})


static func _damage_stat(stats: Dictionary) -> String:
	return ContentText.of("UI_BUILD_DAMAGE_LINE", "{label} {value} / NORMAL DAMAGE").format({
		"label": ContentText.stat_label(str(stats.label)),
		"value": "%d" % int(stats.value),
	})


static func _amulet_stat(stats: Dictionary) -> String:
	return ContentText.of("UI_BUILD_MAX_HP_BONUS", "MAX HP BONUS +{hp}").format({
		"hp": "%.1f" % float(stats.value),
	})


static func _append_melee(details: Array[String], cfg: Dictionary) -> void:
	details.append(ContentText.of("UI_GEAR_MELEE_NO_CHARGE", "No charge system; attacks follow the combo timing."))
	var weapon: Dictionary = Data.weapons.get(str(cfg.get("weapon", "")), {})
	var combo: Array = weapon.get("combo", [])
	details.append(ContentText.of("UI_GEAR_MELEE_COMBO_HEAD", "{count}-hit combo (base damage):").format({
		"count": combo.size(),
	}))
	details.append(ContentText.of("UI_GEAR_MELEE_TIMING_NOTE", "Timings are windup / active / recovery."))
	for i in combo.size():
		var hit: Dictionary = combo[i]
		var timing := "%.2f/%.2f/%.2f" % [
			float(hit.get("windup", 0.0)),
			float(hit.get("active", 0.0)),
			float(hit.get("recovery", 0.0)),
		]
		var size: Array = hit.get("size", [0.0, 0.0])
		var offset: Array = hit.get("offset", [0.0, 0.0])
		# The hitbox is centred at offset.x, so its forward edge is the reach.
		var reach := float(offset[0]) + float(size[0]) * 0.5
		details.append(ContentText.of("UI_GEAR_MELEE_HIT", "Hit {index}: {damage} base · {timing}s · reach {reach}px").format({
			"index": i + 1,
			"damage": "%d" % int(hit.get("damage", 0)),
			"timing": timing,
			"reach": "%d" % int(round(reach)),
		}))
	details.append(ContentText.of("UI_GEAR_MELEE_CRIT", "Crit ×{mult} when the enemy is exposed or backstabbed.").format({
		"mult": "%.1f" % float(weapon.get("crit_multiplier", 1.0)),
	}))
	var wave := float(weapon.get("wave_damage", 0.0))
	if wave > 0.0:
		details.append(ContentText.of("UI_GEAR_MELEE_WAVE", "Finisher releases a wave (base {damage}).").format({
			"damage": "%.1f" % wave,
		}))


static func _append_charge_lines(item: Dictionary, stats: Dictionary, details: Array[String]) -> void:
	var charges := int(item.get("charges", 0))
	var capacity := int(stats.capacity)
	details.append(ContentText.of("UI_BUILD_CHARGES_LINE", "CHARGES {charges}/{capacity} / {state}").format({
		"charges": charges,
		"capacity": capacity,
		"state": ContentText.of("UI_HUD_READY", "READY") if charges > 0 else ContentText.of("UI_HUD_EMPTY", "EMPTY"),
	}))
	details.append(ContentText.of("UI_BUILD_RECHARGE_LINE", "RECHARGE {cooldown}s / NEXT {next}s").format({
		"cooldown": "%.2f" % float(stats.cooldown),
		"next": "%.2f" % float(item.get("cooldown", 0.0)),
	}))


static func _append_guard(details: Array[String], cfg: Dictionary, frontal: bool) -> void:
	var key := "UI_GEAR_GUARD_FRONTAL" if frontal else "UI_GEAR_GUARD_ANY"
	var english: String = "Guard {duration}s; blocks one frontal hit, then counters within {radius}px." if frontal else "Guard {duration}s; blocks one hit, then counters within {radius}px."
	details.append(ContentText.of(key, english).format({
		"duration": "%.2f" % float(cfg.get("duration", 0.0)),
		"radius": "%d" % int(cfg.get("radius", 0.0)),
	}))
	details.append(ContentText.of("UI_GEAR_COUNTER_NO_CRIT", "The counter cannot crit."))


static func _append_affix(details: Array[String], cfg: Dictionary, item: Dictionary) -> void:
	var affix: Dictionary = Data.gear.affixes.get(str(item.get("affix", "none")), {})
	var can_attack: bool = cfg.get("kind") != "amulet"
	var has_recharge: bool = cfg.get("kind") == "skill" or cfg.get("action") == "shield"
	if affix.has("status"):
		if can_attack:
			details.append(ContentText.of("UI_BUILD_STATUS_LINE", "{status} ON HIT / SEPARATE DAMAGE").format({
				"status": ContentText.name("status", str(affix.status), str(STATUS_EN.get(str(affix.status), affix.status))),
			}))
		else:
			details.append(ContentText.of("UI_GEAR_AFFIX_STATUS_INERT", "Status on hit has no effect: this item does not attack."))
	if affix.has("power"):
		details.append(ContentText.of("UI_BUILD_AFFIX_POWER", "AFFIX: +{percent}% BASE POWER (INCLUDED)").format({
			"percent": roundi(float(affix.power) * 100),
		}))
	if affix.has("cooldown"):
		if has_recharge:
			details.append(ContentText.of("UI_BUILD_AFFIX_COOLDOWN", "AFFIX: RECHARGE x{mult} (INCLUDED)").format({
				"mult": "%.2f" % float(affix.cooldown),
			}))
		else:
			details.append(ContentText.of("UI_GEAR_AFFIX_COOLDOWN_INERT", "Recharge ×{mult} has no effect: this item has no recharge.").format({
				"mult": "%.2f" % float(affix.cooldown),
			}))


static func _playstyle(id: String) -> String:
	var key := "UI_GEAR_PLAY_%s" % id.to_upper()
	return ContentText.of(key, str(PLAYSTYLE_EN.get(id, "")))


static func _condition(kind: String, action: String) -> String:
	if action == "melee":
		return ContentText.of("UI_GEAR_COND_MELEE", "Crit when the enemy is exposed during an attack or recovery, or struck from behind.")
	if action == "shield":
		return ContentText.of("UI_GEAR_COND_SHIELD", "Blocks one frontal hit during the guard window, then counters.")
	if action == "aegis":
		return ContentText.of("UI_GEAR_COND_AEGIS", "Blocks one hit during the guard window and counters all nearby enemies.")
	if action == "kunai":
		return ContentText.of("UI_GEAR_COND_KUNAI", "Auto-targets the nearest enemy; can crit when the target is exposed or backstabbed.")
	if kind == "amulet":
		return ContentText.of("UI_GEAR_COND_AMULET", "Passive; always active.")
	return ""


static func _headline(cfg: Dictionary, stats: Dictionary) -> String:
	var kind := str(cfg.get("kind", ""))
	if kind == "amulet":
		return _amulet_stat(stats)
	var label := ContentText.stat_label(str(stats.label))
	var value := "%d" % int(stats.value)
	if cfg.get("action") == "melee":
		var weapon: Dictionary = Data.weapons.get(str(cfg.get("weapon", "")), {})
		return ContentText.of("UI_GEAR_HEAD_MELEE", "{label} {value} · Crit ×{mult} · {count}-hit combo").format({
			"label": label,
			"value": value,
			"mult": "%.1f" % float(weapon.get("crit_multiplier", 1.0)),
			"count": (weapon.get("combo", []) as Array).size(),
		})
	if cfg.get("action") == "shield" or cfg.get("action") == "aegis":
		return ContentText.of("UI_GEAR_HEAD_GUARD", "{label} {value} · Guard {duration}s · Recharge {cooldown}s").format({
			"label": label,
			"value": value,
			"duration": "%.2f" % float(cfg.get("duration", 0.0)),
			"cooldown": "%.2f" % float(stats.cooldown),
		})
	return ContentText.of("UI_GEAR_HEAD_SKILL", "{label} {value} · {charges} charges · Recharge {cooldown}s").format({
		"label": label,
		"value": value,
		"charges": int(stats.capacity),
		"cooldown": "%.2f" % float(stats.cooldown),
	})


static func _kind_label(kind: String) -> String:
	return ContentText.of("UI_GEAR_KIND_%s" % kind.to_upper(), str(KIND_EN.get(kind, kind)))


static func _axis_label(attribute: String) -> String:
	return ContentText.name("axis", attribute, str(AXIS_EN.get(attribute, attribute))).to_upper()


static func _quality_name(quality: String) -> String:
	return ContentText.name("quality", quality, str(QUALITY_EN.get(quality, quality)))


static func _affix_name(item: Dictionary) -> String:
	var affix: Dictionary = Data.gear.affixes.get(str(item.get("affix", "none")), {})
	return ContentText.name("affix", str(item.get("affix", "none")), str(affix.get("name", item.get("affix", "none"))))
