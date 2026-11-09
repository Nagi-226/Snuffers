extends RifleController


## 雷霆独立保留冷却余量，避免 60Hz 把 700RPM 量化为 600RPM。
func _tick_weapon(delta: float) -> void:
	_fire_cooldown -= delta
	_burst_left = 0
	if _current_fire_mode() != &"auto" or not _trigger_held:
		_fire_cooldown = maxf(_fire_cooldown, 0.0)
		return
	while _fire_cooldown <= 0.0:
		var remainder := _fire_cooldown
		if not _try_fire():
			_fire_cooldown = 0.0
			return
		_fire_cooldown += remainder
