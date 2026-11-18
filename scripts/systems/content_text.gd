class_name ContentText
extends RefCounted
## The one translation contract for player-visible text.
##
## Rows live in data/localization/ui.csv, keyed by stable names
## (<FAMILY>_<ID>_NAME, <FAMILY>_<ID>_TEXT, UI_ROW, UI_MACHINE_<SLUG>). English
## content in data/*.json stays canonical, so a missing row falls back to the
## English source instead of ever showing the raw key. Machine strings
## (Profile status, lock reasons, save errors) are never rewritten at their
## source; only this display boundary translates them.

## Family -> row prefix. Families are lowercase call-site names; ids are the
## stable machine ids from data/*.json and are upper-snaked into the key.
const PREFIX := {
	"enemy": "ENEMY",
	"gear": "GEAR",
	"weapon": "WEAPON",
	"armor": "ARMOR",
	"biome": "BIOME",
	"mutation": "MUTATION",
	"upgrade": "UPGRADE",
	"character": "CHARACTER",
	"skill": "SKILL",
	"challenge": "CHALLENGE",
	"reward": "REWARD",
	"blueprint": "BLUEPRINT",
	"rune": "RUNE",
	"key": "KEY",
	"axis": "AXIS",
	"quality": "GEAR_QUALITY",
	"affix": "GEAR_AFFIX",
	"status": "STATUS",
	"service": "SERVICE",
	"station": "HUB_STATION",
	"loot": "LOOT",
	"floor": "FLOOR",
}


static var _warned: Dictionary = {}


## RunBuild.display_stats().label stays a canonical English enum (it is compared
## between items); pages map it through here for display.
const STAT_ROWS := {
	"EMPTY": "UI_STAT_EMPTY",
	"MAX HP": "UI_STAT_MAX_HP",
	"FIRST HIT": "UI_STAT_FIRST_HIT",
	"COUNTER": "UI_STAT_COUNTER",
	"HIT": "UI_STAT_HIT",
}


static func stat_label(label: String) -> String:
	var key: String = STAT_ROWS.get(label, "")
	return of(key, label) if not key.is_empty() else label


static func of(key: String, english: String) -> String:
	var value := TranslationServer.translate(key)
	if value.is_empty() or value == key:
		# One warning per key, not per frame: a page redraw must not flood the log.
		if not _warned.has(key):
			_warned[key] = true
			push_warning("ContentText: missing row %s; showing English source" % key)
		return english
	return value


static func name(family: String, id: String, english: String) -> String:
	return english if _is_english() else of("%s_%s_NAME" % [str(PREFIX.get(family, family.to_upper())), id.to_upper()], english)


static func text(family: String, id: String, english: String) -> String:
	return english if _is_english() else of("%s_%s_TEXT" % [str(PREFIX.get(family, family.to_upper())), id.to_upper()], english)


## Canonical English is the runtime value (names can be mutated in fixtures and
## saves), so the English locale echoes it instead of looking a row up.
static func _is_english() -> bool:
	return TranslationServer.get_locale().begins_with("en")


## RouteGraph.lock_reason() returns machine text ("BSC 1", "CANOPY RUNE",
## "FOUNDRY KEY"). Only this display boundary translates it; the machine value
## stays comparable. Rune/key ids keep their _rune/_key suffix when reversed, so
## the lookup is the same stable id ContentText.name() uses, never a capitalized
## guess. Unknown reasons fall back to the existing UI_MACHINE_* rows.
static func lock_reason(reason: String) -> String:
	if reason.is_empty():
		return ""
	if reason.begins_with("BSC "):
		return of("UI_MACHINE_BSC", "BSC {level}").format({"level": reason.substr(4).strip_edges()})
	var id := reason.to_lower().replace(" ", "_")
	if id.ends_with("_rune"):
		return of("RUNE_%s_NAME" % id.to_upper(), reason)
	if id.ends_with("_key") or id.ends_with("_key_left") or id.ends_with("_key_right"):
		return of("KEY_%s_NAME" % id.to_upper(), reason)
	return machine(reason)


## Machine values are compared and persisted in English; only their display
## form is translated. The slug keeps the existing UI_MACHINE_* row names.
static func machine(raw: String) -> String:
	var slug := ""
	for character in raw.to_upper():
		if (character >= "A" and character <= "Z") or (character >= "0" and character <= "9"):
			slug += character
		elif not slug.is_empty() and not slug.ends_with("_"):
			slug += "_"
	return of("UI_MACHINE_" + slug.trim_suffix("_"), raw)
