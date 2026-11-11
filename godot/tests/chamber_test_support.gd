## Legacy scenarios express a total load; production magazine fields stay containers.
extends RefCounted

const IDS := [&"rifle", &"pistol", &"g17", &"dmr", &"shotgun", &"spas12", &"smg", &"mpx", &"em57s2", &"lmg", &"magnum", &"em86s", &"em86b", &"em86d", &"em86m", &"em127g", &"em127m", &"em12g2"]


static func total(state, id: StringName) -> int:
	var mag := int(state.get(String(id) + "_mag"))
	return mag + (1 if IDS.has(id) and state.weapon_chambered.get(id, false) else 0)


static func set_total(state, id: StringName, rounds: int) -> void:
	if IDS.has(id):
		state.set(String(id) + "_mag", maxi(0, rounds - 1))
		state.weapon_chambered[id] = rounds > 0
	else:
		state.set(String(id) + "_mag", rounds)


static func chamber(state, id: StringName) -> int:
	return 1 if IDS.has(id) and state.weapon_chambered.get(id, false) else 0
