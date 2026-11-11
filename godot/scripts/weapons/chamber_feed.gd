## 当前18枪的容器/膛弹迁移；GameState只保存状态，调用方广播既有弹药事件。
extends RefCounted


static func is_chambered(weapon_id: StringName) -> bool:
	return GameState.weapon_chambered.get(weapon_id, false) == true


static func has_round(weapon_id: StringName, magazine: int) -> bool:
	return magazine > 0 or is_chambered(weapon_id)


static func load_chamber(weapon_id: StringName, magazine_property: StringName) -> bool:
	if weapon_id not in GameConfig.CHAMBER_WEAPON_IDS or is_chambered(weapon_id):
		return false
	var magazine := int(GameState.get(magazine_property))
	if magazine <= 0:
		return false
	GameState.set(magazine_property, magazine - 1)
	GameState.weapon_chambered[weapon_id] = true
	return true


static func consume_round(weapon_id: StringName, magazine_property: StringName, automatic_feed: bool = true) -> bool:
	if weapon_id not in GameConfig.CHAMBER_WEAPON_IDS:
		var magazine := int(GameState.get(magazine_property))
		if magazine <= 0:
			return false
		GameState.set(magazine_property, magazine - 1)
		return true
	if automatic_feed:
		load_chamber(weapon_id, magazine_property)
	if not is_chambered(weapon_id):
		return false
	GameState.weapon_chambered[weapon_id] = false
	if automatic_feed:
		load_chamber(weapon_id, magazine_property)
	return true


static func refill_magazine(weapon_id: StringName, magazine_property: StringName, reserve_property: StringName, capacity: int) -> void:
	var magazine := int(GameState.get(magazine_property))
	var reserve := int(GameState.get(reserve_property))
	var take := mini(maxi(0, capacity - magazine), maxi(0, reserve))
	GameState.set(magazine_property, magazine + take)
	GameState.set(reserve_property, reserve - take)
	load_chamber(weapon_id, magazine_property)
