extends SceneTree

var _failures := 0
var _player: CharacterBody3D
var _state


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _press(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	_player._unhandled_input(event)


func _press_reload(weapon: Node) -> void:
	if DisplayServer.get_name() == "headless":
		weapon._start_reload()
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var event := InputEventKey.new()
	event.keycode = KEY_R
	event.physical_keycode = KEY_R
	event.pressed = true
	weapon._unhandled_input(event)


func _model_bounds(model: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var inverse := model.global_transform.affine_inverse()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var bounds: AABB = (inverse * mesh.global_transform) * mesh.get_aabb()
		if first:
			result = bounds
			first = false
		else:
			result = result.merge(bounds)
	return result


func _run() -> void:
	_state = root.get_node("GameState")
	_state.reset()
	var scene := (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	_player = scene.get_node("Player") as CharacterBody3D
	await process_frame
	_assert(_state.smg_mag == 100 and _state.lmg_mag == 600 and _state.magnum_mag == 15, "new magazine sizes are 100, 600 and 15")
	_assert(_state.pistol_reserve == 600 and _state.rifle_reserve == 1800 and _state.magnum_reserve == 1500, "shared reserves and EC-127 reserve initialize correctly")
	var smg_data = load("res://scenes/weapons/smg.tres")
	smg_data.sync_from_config()
	_assert(is_equal_approx(smg_data.damage_body, 45.0) and is_equal_approx(smg_data.fire_interval, 0.06), "SMG deals 45 damage at 1000 RPM")
	var lmg_data = load("res://scenes/weapons/lmg.tres")
	lmg_data.sync_from_config()
	_assert(is_equal_approx(lmg_data.damage_body, 75.0) and is_equal_approx(lmg_data.fire_interval, 0.05), "LMG deals 75 damage at 1200 RPM")
	var magnum_data = load("res://scenes/weapons/magnum.tres")
	magnum_data.sync_from_config()
	_assert(is_equal_approx(magnum_data.damage_body, 150.0) and magnum_data.mag_size == 15, "Magnum deals 150 damage with a 15-round magazine")
	_press(KEY_2)
	_assert(_state.current_weapon == &"smg", "number 2 selects the SMG")
	var smg = _player.get_node("Camera3D/WeaponMount/SMG")
	_state.pistol_mag = 30
	var smg_fired: bool = smg._fire()
	_assert(smg_fired and _state.smg_mag == 99 and _state.pistol_mag == 30, "SMG consumes its own magazine, not the pistol magazine")
	_press(KEY_X)
	_assert(_state.fire_modes[&"smg"] == &"semi", "SMG enters semi-auto")
	_press(KEY_X)
	_assert(_state.fire_modes[&"smg"] == &"burst", "SMG enters three-round burst")
	_press(KEY_X)
	_assert(_state.fire_modes[&"smg"] == &"grenade", "SMG retains its underbarrel grenade mode")
	var grenades_before: int = _state.rifle_grenades
	var grenade_fired: bool = smg._fire_grenade()
	_assert(grenade_fired and _state.rifle_grenades == grenades_before - 1, "SMG consumes the shared grenade pool")
	_state.smg_mag = 17
	_state.pistol_reserve = 600
	_press_reload(smg)
	_assert(not smg._is_reloading and _state.smg_mag == 17 and _state.pistol_reserve == 600 and _state.rifle_grenades == grenades_before - 1, "SMG grenade mode ignores R without changing either ammunition pool")
	_state.smg_mag = 0
	_state.pistol_reserve = 600
	smg._on_weapon_reloaded(&"smg")
	_assert(_state.smg_mag == 100 and _state.pistol_reserve == 500, "SMG reloads from the shared EC-57 reserve")
	_state.fire_modes[&"smg"] = &"auto"
	_state.smg_mag = 80
	_press_reload(smg)
	_assert(smg._is_reloading, "SMG automatic mode still reloads with R")
	_press(KEY_5)
	_assert(_state.current_weapon == &"lmg", "number 5 selects the LMG")
	var lmg = _player.get_node("Camera3D/WeaponMount/LMG")
	_state.rifle_mag = 60
	var lmg_fired: bool = lmg._fire()
	_assert(lmg_fired and _state.lmg_mag == 599 and _state.rifle_mag == 60, "LMG consumes its own magazine, not the rifle magazine")
	_state.lmg_mag = 0
	_state.rifle_reserve = 1800
	lmg._on_weapon_reloaded(&"lmg")
	_assert(_state.lmg_mag == 600 and _state.rifle_reserve == 1200, "LMG reloads from the shared EC-68 reserve")
	_press(KEY_X)
	_assert(_state.fire_modes[&"lmg"] == &"burst", "LMG supports three-round burst without a grenade mode")
	_press(KEY_1)
	_press(KEY_1)
	_assert(_state.current_weapon == &"magnum", "number 1 repeats from pistol to Magnum")
	var magnum = _player.get_node("Camera3D/WeaponMount/Magnum")
	var magnum_fired: bool = magnum._fire()
	_assert(magnum_fired and _state.magnum_mag == 14, "Magnum consumes its own EC-127 magazine")
	_press(KEY_X)
	_assert(_state.fire_modes[&"magnum"] == &"semi", "Magnum remains semi-auto")
	_state.magnum_mag = 0
	_state.magnum_reserve = 1500
	magnum._on_weapon_reloaded(&"magnum")
	_assert(_state.magnum_mag == 15 and _state.magnum_reserve == 1485, "Magnum reloads from its independent EC-127 reserve")
	_press(KEY_3)
	var rifle = _player.get_node("Camera3D/WeaponMount/Rifle")
	_state.fire_modes[&"rifle"] = &"grenade"
	_state.rifle_mag = 13
	_state.rifle_reserve = 1800
	_press_reload(rifle)
	_assert(not rifle._is_reloading and _state.rifle_mag == 13 and _state.rifle_reserve == 1800, "rifle grenade mode ignores R without changing its ammunition display values")
	_state.fire_modes[&"rifle"] = &"auto"
	_press_reload(rifle)
	_assert(rifle._is_reloading, "rifle automatic mode still reloads with R")
	_assert(_player._ads_mount_targets[&"smg"].is_equal_approx(_player._ads_mount_targets[&"rifle"]) and _player._ads_mount_targets[&"lmg"].is_equal_approx(_player._ads_mount_targets[&"rifle"]), "SMG and LMG inherit the exact EM-68A optic center")
	_assert(_player._ads_mount_targets[&"magnum"].is_equal_approx(_player._ads_mount_targets[&"pistol"]), "Magnum inherits the exact EM-57P optic center")
	_press(KEY_2)
	_player._set_aiming(true)
	for frame in 20:
		_player._process(1.0 / 60.0)
	_assert(not _player._scope_view_models[&"smg"].visible and _player.get_node("Camera3D/WeaponMount/Rifle").visible, "SMG uses the validated EM-68A holographic scope")
	_assert(_player._optic_meshes[&"rifle"].node.mesh == _player._optic_meshes[&"rifle"].bored, "SMG and LMG use the open EM-68A optic mesh")
	_player._set_aiming(false)
	for frame in 20:
		_player._process(1.0 / 60.0)
	_assert(_player._scope_view_models[&"smg"].visible and not _player.get_node("Camera3D/WeaponMount/Rifle").visible, "hip fire restores the SMG model and hides the scope model")
	_assert(_player._optic_meshes[&"rifle"].node.mesh == _player._optic_meshes[&"rifle"].intact, "hip fire restores the intact EM-68A optic mesh")
	await process_frame
	await process_frame
	var minimap = scene.get_node("HUD/Minimap")
	_assert(minimap.visible and minimap._enemies.size() == 10, "range minimap displays all ten passive targets")
	_assert(minimap.get_node("View/Sub/MapTex").texture != null, "range minimap uses its rendered terrain texture")
	_assert(smg_data.hitscan_range == 90.0 and lmg_data.hitscan_range == 140.0 and magnum_data.hitscan_range == 120.0, "new weapon ranges synchronize from config")
	for entry in [["SMG", "EM68A"], ["LMG", "EM68A"], ["Magnum", "EM57P"]]:
		var model := _player.get_node("Camera3D/WeaponMount/" + entry[0] + "/ViewModel/" + entry[1]) as Node3D
		var bounds := _model_bounds(model)
		_assert(bounds.size.z > bounds.size.x, entry[0] + " model long axis points forward instead of sideways")
	var config = root.get_node("GameConfig")
	_assert(config.RIFLE_MAG == 60 and config.PISTOL_MAG == 30 and config.DMR_MAG == 60 and config.SHOTGUN_MAG == 32 and config.SPAS12_MAG == 8, "existing weapon values remain unchanged")
	await create_timer(2.1).timeout
	scene.queue_free()
	await process_frame
	print("test_new_weapon_platforms: %d assertion(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
