## SIG516沿用长枪命中/原弹匣；保存物理冷却余量保持850RPM。
extends LongGunController


func _tick_weapon(delta: float) -> void:
	_fire_cooldown -= maxf(delta, 0.0)
	if _is_reloading or _current_fire_mode() != &"auto" or not _trigger_held:
		_fire_cooldown = maxf(_fire_cooldown, 0.0)
		return
	while _fire_cooldown <= 0.0:
		var remainder := _fire_cooldown
		if not _try_fire():
			_fire_cooldown = 0.0
			return
		_fire_cooldown += remainder


func _on_weapon_switched(weapon_id: StringName) -> void:
	_trigger_held = false
	_burst_left = 0
	_fire_cooldown = 0.0
	super._on_weapon_switched(weapon_id)
