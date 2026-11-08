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
	var config = root.get_node("GameConfig")
	state.reset()
	_assert(state.pistol_reserve == 3000 and config.PISTOL_RESERVE_MAX == 3000, "EC-57 starts with 3000 reserve and accepts pickups up to 3000")
	_assert(state.em57s2_mag == 200 and state.pistol_mag == 30 and state.smg_mag == 100, "EM-57S2 starts with 200 rounds while other EC-57 magazines retain their capacities")
	for id in [&"pistol", &"smg", &"em57s2"]:
		var data = load("res://scenes/weapons/%s.tres" % id)
		data.sync_from_config()
		_assert(data.reserve_size == 3000, "%s data uses the shared 3000-round EC-57 pool" % id)

	var scene := (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player = scene.get_node("Player")
	player._switch_weapon(&"em57s2")
	var weapon = player.get_node("Camera3D/WeaponMount/Em57s2")
	var ammo = scene.get_node("HUD")._weapon_ammo
	_assert(ammo.mag == 200 and ammo.reserve == 3000 and ammo.ammo_type == "EC-57", "EM-57S2 HUD shows 200 loaded and 3000 reserve")
	state.em57s2_mag = 0
	weapon._start_reload()
	await create_timer(weapon.weapon_data.reload_time + 0.1).timeout
	_assert(state.em57s2_mag == 200 and state.pistol_reserve == 2800 and not weapon._is_reloading, "empty timed reload moves exactly 200 rounds out of the shared reserve")
	_assert(ammo.mag == 200 and ammo.reserve == 2800, "reload refreshes the 200-round magazine and remaining reserve in the HUD")
	player._switch_weapon(&"pistol")
	_assert(ammo.mag == 30 and ammo.reserve == 2800, "switching to the pistol sees the same depleted EC-57 reserve")
	player._switch_weapon(&"smg")
	_assert(ammo.mag == 100 and ammo.reserve == 2800, "switching to EM-57S1 sees the same depleted EC-57 reserve")
	state.em57s2_mag = 0
	state.pistol_reserve = 73
	weapon._on_weapon_reloaded(&"em57s2")
	_assert(state.em57s2_mag == 73 and state.pistol_reserve == 0, "partial reserve reload does not create ammunition")
	state.pistol_reserve = 2990
	player._switch_weapon(&"pistol")
	player._switch_weapon(&"smg")
	var pickup = load("res://scripts/levels/pickup.gd").new()
	pickup.kind = &"pistol_ammo"
	scene.add_child(pickup)
	pickup._on_body_entered(player)
	_assert(state.pistol_reserve == 3000 and pickup._collected, "EC-57 pickup replenishes above the old 600-round limit and clamps to 3000")
	_assert(ammo.mag == 100 and ammo.reserve == 3000, "EM-57S1 HUD refreshes immediately when shared EC-57 ammo is picked up")
	state.pistol_reserve = 2990
	player._switch_weapon(&"em57s2")
	var smg2_pickup = load("res://scripts/levels/pickup.gd").new()
	smg2_pickup.kind = &"pistol_ammo"
	scene.add_child(smg2_pickup)
	smg2_pickup._on_body_entered(player)
	_assert(ammo.mag == 73 and ammo.reserve == 3000, "EM-57S2 HUD refreshes immediately when shared EC-57 ammo is picked up")
	var full_pickup = load("res://scripts/levels/pickup.gd").new()
	full_pickup.kind = &"pistol_ammo"
	scene.add_child(full_pickup)
	full_pickup._on_body_entered(player)
	_assert(state.pistol_reserve == 3000 and not full_pickup._collected, "full EC-57 reserve leaves the pickup available")
	scene.queue_free()
	await process_frame
	print("EC57_CAPACITY failures=", _failures)
	quit(1 if _failures else 0)
