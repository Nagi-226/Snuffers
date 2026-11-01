extends SceneTree

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _run() -> void:
	var state = root.get_node("GameState")
	state.reset()
	_assert(state.spas12_mag == 8 and state.spas12_reserve == 40, "SPAS uses independent 12-gauge ammunition")
	_assert(not state.weapon_unlocked[&"spas12"], "SPAS starts locked")
	_assert(state.shotgun_mag == 32 and state.shotgun_reserve == 160, "EM-12G-1 ammunition is unchanged")
	var data := WeaponData.new()
	data.weapon_id = &"spas12"
	data.sync_from_config()
	_assert(data.mag_size == 8 and data.pellet_count == 8, "SPAS has an eight-round tube and eight pellets")
	_assert(data.hitscan_range == 35.0 and data.semi_fire_interval >= 0.8, "SPAS pump cadence and range")
	var weapon := (load("res://scenes/weapons/spas12.tscn") as PackedScene).instantiate()
	root.add_child(weapon)
	state.current_weapon = &"spas12"
	await process_frame
	await physics_frame
	_assert(weapon._pump_sleeve != null, "SPAS has an independent pump sleeve mesh")
	_assert(weapon._fire(), "SPAS fires")
	_assert(state.spas12_mag == 7 and state.spas12_reserve == 40, "SPAS consumes one shell per shot")
	_assert(state.shotgun_mag == 32 and state.shotgun_reserve == 160, "SPAS firing does not consume EC-12 ammunition")
	_assert(weapon._pump_left > 0.0, "firing starts the pump cycle")
	state.spas12_mag = 2
	state.spas12_reserve = 5
	weapon._start_reload()
	weapon._start_reload()
	await create_timer(root.get_node("GameConfig").SPAS12_RELOAD_SHELL_TIME + 0.1).timeout
	_assert(state.spas12_mag == 3 and state.spas12_reserve == 4, "reload inserts exactly one shell per interval")
	await create_timer(root.get_node("GameConfig").SPAS12_RELOAD_SHELL_TIME * 6.0).timeout
	_assert(state.spas12_mag == 7 and state.spas12_reserve == 0, "reload stops when reserves empty without duplication")
	_assert(not weapon._is_reloading, "reload leaves its active state")
	state.spas12_mag = 2
	state.spas12_reserve = 5
	weapon._start_reload()
	await create_timer(0.15).timeout
	state.current_weapon = &"rifle"
	root.get_node("Events").weapon_switched.emit(&"rifle")
	await create_timer(root.get_node("GameConfig").SPAS12_RELOAD_SHELL_TIME + 0.2).timeout
	_assert(state.spas12_mag == 2 and state.spas12_reserve == 5, "switching cancels reload before the first shell")
	weapon.queue_free()
	await process_frame
	var player := Node3D.new()
	player.add_to_group(&"player")
	root.add_child(player)
	var pickup := (load("res://scenes/levels/pickup.tscn") as PackedScene).instantiate()
	pickup.kind = &"spas12"
	root.add_child(pickup)
	pickup._on_body_entered(player)
	await process_frame
	_assert(state.weapon_unlocked[&"spas12"] and state.current_weapon == &"spas12", "rack pickup unlocks and equips SPAS")
	print("test_spas12: %d assertion(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
