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
	_assert(state.em86_reserve == 4500, "shared EC-86 reserve starts with 4500 rounds")
	for id in [&"em86s", &"em86b", &"em86d", &"em86m"]:
		var data = load("res://scenes/weapons/%s.tres" % id)
		_assert(data.reserve_size == 4500, "%s resource defaults to 4500 EC-86 rounds" % id)
		data.sync_from_config()
		_assert(data.reserve_size == 4500, "%s synchronized data uses 4500 EC-86 rounds" % id)
	var scene := (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player = scene.get_node("Player")
	player._switch_weapon(&"em86m")
	var weapon = player.get_node("Camera3D/WeaponMount/Em86m")
	var ammo = scene.get_node("HUD")._weapon_ammo
	_assert(ammo.mag == 500 and ammo.reserve == 4500 and ammo.ammo_type == "EC-86", "EM-86M HUD shows 500 loaded and 4500 reserve")
	state.em86m_mag = 0
	weapon._start_reload()
	await create_timer(weapon.weapon_data.reload_time + 0.1).timeout
	_assert(state.em86m_mag == 500 and state.em86_reserve == 4000 and not weapon._is_reloading, "empty timed reload moves exactly 500 rounds from reserve")
	_assert(ammo.mag == 500 and ammo.reserve == 4000, "reload updates the magazine and shared reserve in the HUD")
	for id in [&"em86s", &"em86b", &"em86d"]:
		player._switch_weapon(id)
		_assert(ammo.mag == 45 and ammo.reserve == 4000, "%s sees the same depleted EC-86 reserve" % id)
	state.em86m_mag = 0
	state.em86_reserve = 73
	weapon._on_weapon_reloaded(&"em86m")
	_assert(state.em86m_mag == 73 and state.em86_reserve == 0, "partial EC-86 reserve reload does not create ammunition")
	scene.queue_free()
	await process_frame
	print("EC86_CAPACITY failures=", _failures)
	quit(1 if _failures else 0)
