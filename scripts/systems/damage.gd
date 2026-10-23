class_name Damage
## Single place for the damage formula. Everything that deals damage goes
## through here so balance changes stay in one function.

const ATTR_SCALE := 0.12


static func compute(base: float, attr: int, crit: bool, crit_mult: float, scale: float = 1.0) -> int:
	var value := base * (1.0 + float(attr) * ATTR_SCALE) * scale
	if crit:
		value *= crit_mult
	return maxi(1, int(round(value)))
