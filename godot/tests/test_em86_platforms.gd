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


func _wheel(button: MouseButton) -> void:
	if DisplayServer.get_name() == "headless":
		_player._adjust_em86s_zoom(1 if button == MOUSE_BUTTON_WHEEL_UP else -1)
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	_player._unhandled_input(event)


func _run() -> void:
	var ids: Array[StringName] = [&"em86s", &"em86b", &"em86d"]
	var missing := false
	for weapon_id in ids:
		var exists := ResourceLoader.exists("res://scenes/weapons/%s.tscn" % weapon_id) and ResourceLoader.exists("res://scenes/weapons/%s.tres" % weapon_id)
		_assert(exists, "%s has a game scene and data resource" % weapon_id)
		missing = missing or not exists
	if missing:
		quit(1)
		return

	_state = root.get_node("GameState")
	_state.reset()
	root.size = Vector2i(1920, 1080)
	var scene := (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	_player = scene.get_node("Player") as CharacterBody3D
	await process_frame
	_assert(_state.em86s_mag == 45 and _state.em86b_mag == 45 and _state.em86d_mag == 45, "all EM-86 magazines initialize to 45")
	_assert(_state.em86_reserve == 900, "shared EC-86 reserve initializes to 900")
	_assert(_state.fire_modes[&"em86b"] == &"burst" and _state.fire_modes[&"em86s"] == &"semi" and _state.fire_modes[&"em86d"] == &"semi", "EM-86B starts in burst and both precision rifles are semi-auto")

	var expected_damage := {&"em86s": 240.0, &"em86b": 120.0, &"em86d": 180.0}
	for weapon_id in ids:
		var data = load("res://scenes/weapons/%s.tres" % weapon_id)
		data.sync_from_config()
		_assert(is_equal_approx(data.damage_body, expected_damage[weapon_id]) and data.mag_size == 45 and data.reserve_size == 900, "%s has its specified damage, magazine and EC-86 reserve" % weapon_id)
		_player._switch_weapon(weapon_id)
		_assert(_state.current_weapon == weapon_id, "%s is selectable in the range" % weapon_id)
		var node_name := weapon_id.to_pascal_case()
		var weapon = _player.get_node("Camera3D/WeaponMount/" + node_name)
		var fired: bool = weapon._fire()
		_assert(fired and int(_state.get(weapon_id + "_mag")) == 44, "%s consumes its own magazine on a real shot" % weapon_id)
		_state.set(weapon_id + "_mag", 0)
		_state.em86_reserve = 900
		weapon._on_weapon_reloaded(weapon_id)
		_assert(int(_state.get(weapon_id + "_mag")) == 45 and _state.em86_reserve == 855, "%s reloads 45 rounds from the shared EC-86 pool" % weapon_id)

	_player._switch_weapon(&"em86b")
	var battle = _player.get_node("Camera3D/WeaponMount/Em86b")
	battle._fire_cooldown = 0.0
	battle._try_fire()
	_assert(is_equal_approx(battle._fire_cooldown, 60.0 / 900.0), "EM-86B burst fires at 900 RPM")
	_player._cycle_fire_mode()
	_assert(_state.fire_modes[&"em86b"] == &"semi", "EM-86B burst switches to semi-auto")
	_player._cycle_fire_mode()
	_assert(_state.fire_modes[&"em86b"] == &"auto", "EM-86B semi-auto switches to auto")
	battle._fire_cooldown = 0.0
	battle._try_fire()
	_assert(is_equal_approx(battle._fire_cooldown, 60.0 / 650.0), "EM-86B auto fires at 650 RPM")
	_player._cycle_fire_mode()
	_assert(_state.fire_modes[&"em86b"] == &"grenade", "EM-86B auto switches to its underbarrel grenade")
	_state.em86b_mag = 20
	_state.em86_reserve = 900
	var hud_ammo = scene.get_node("HUD")._weapon_ammo
	var grenades_before: int = _state.rifle_grenades
	var grenade_fired: bool = battle._fire()
	_assert(grenade_fired and hud_ammo.mag == 20 and hud_ammo.reserve == 900 and hud_ammo.grenade_stock == grenades_before - 1, "EM-86B grenade preserves EC-86 HUD and only consumes EC-40P")
	battle._start_reload()
	_assert(not battle._is_reloading and _state.em86b_mag == 20 and _state.em86_reserve == 900, "EM-86B grenade mode ignores reload")
	_player._cycle_fire_mode()
	_assert(_state.fire_modes[&"em86b"] == &"burst", "EM-86B grenade mode wraps to burst")

	_player._switch_weapon(&"em86s")
	_player._set_aiming(true)
	for frame in 20:
		_player._process(1.0 / 60.0)
	var sniper = _player.get_node("Camera3D/WeaponMount/Em86s")
	_assert(_player._dmr_scope.visible and _player._dmr_tactical.visible and not sniper._view_model.visible, "EM-86S uses the full-screen tactical scope and hides its weapon")
	_assert(is_equal_approx(_player._camera.fov, 35.0) and _player._em86s_zoom_index == 0, "EM-86S starts at 8x magnification")
	_assert(_player._dmr_scope_material.get_shader_parameter("center_style") > 0.5, "EM-86S replaces the center circle with a diamond")
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_player._process(1.0 / 60.0)
	_assert(_player._em86s_zoom_index == 1 and is_equal_approx(_player._camera.fov, 17.5), "first forward wheel selects 16x")
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_player._process(1.0 / 60.0)
	_assert(_player._em86s_zoom_index == 2 and is_equal_approx(_player._camera.fov, 8.75), "second forward wheel selects 32x")
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_assert(_player._em86s_zoom_index == 2, "EM-86S magnification clamps at 32x")
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_player._process(1.0 / 60.0)
	_assert(_player._em86s_zoom_index == 1 and is_equal_approx(_player._camera.fov, 17.5), "backward wheel returns to 16x")
	_player._set_aiming(false)
	_player._set_aiming(true)
	for frame in 20:
		_player._process(1.0 / 60.0)
	_assert(_player._em86s_zoom_index == 0 and is_equal_approx(_player._camera.fov, 35.0), "a new ADS hold resets EM-86S to 8x")
	var target = scene.get_node("RangeFacilities/Targets/CloseTarget")
	target.health = root.get_node("GameConfig").INFANTRY_HP
	_player.get_node("Camera3D").look_at(target.global_position + Vector3(0, 1, 0))
	_player._dmr_tactical.size = Vector2(1920, 1080)
	_player._dmr_tactical._refresh_range()
	_player._dmr_tactical._refresh_targets()
	_assert(not _player._dmr_tactical._range_text.contains("---") and not _player._dmr_tactical._targets.is_empty(), "EM-86S retains live ranging and target tracking")

	_player._switch_weapon(&"em86d")
	for frame in 20:
		_player._process(1.0 / 60.0)
	var heavy_dmr = _player.get_node("Camera3D/WeaponMount/Em86d")
	_assert(_player._dmr_scope.visible and not heavy_dmr._view_model.visible and is_equal_approx(_player._camera.fov, 35.0), "EM-86D uses the same full-screen 8x scope as EM-68D")
	_assert(_player._dmr_scope_material.get_shader_parameter("center_style") < 0.5, "EM-86D keeps the original circular center")
	_player._cycle_fire_mode()
	_assert(_state.fire_modes[&"em86d"] == &"semi" and _state.fire_modes[&"em86s"] == &"semi", "EM-86D and EM-86S remain semi-auto")

	_player._switch_weapon(&"em86b")
	for frame in 20:
		_player._process(1.0 / 60.0)
	_assert(not _player._dmr_scope.visible and battle._view_model.visible and _player._ads_reticle.mode == &"dmr", "EM-86B keeps its weapon visible with the cross circle-dot reticle")
	for weapon_id in ids:
		var node_name := weapon_id.to_pascal_case()
		var model_path := "Camera3D/WeaponMount/" + node_name + "/ViewModel/Weapon" if weapon_id != &"em86b" else "Camera3D/WeaponMount/Em86b/ViewModel/EM68A"
		var model := _player.get_node(model_path) as Node3D
		var bounds := AABB()
		var first := true
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			var local_bounds: AABB = (model.global_transform.affine_inverse() * (mesh as MeshInstance3D).global_transform) * (mesh as MeshInstance3D).get_aabb()
			bounds = local_bounds if first else bounds.merge(local_bounds)
			first = false
		_assert(bounds.size.z > bounds.size.x, "%s model points forward rather than sideways" % weapon_id)
	var config = root.get_node("GameConfig")
	_assert(config.RIFLE_FIRE_INTERVAL == 0.075 and config.SMG_FIRE_INTERVAL == 0.06 and config.LMG_FIRE_INTERVAL == 0.05 and config.DMR_DAMAGE_BODY == 90.0 and config.MAGNUM_DAMAGE_BODY == 150.0, "existing weapon values remain unchanged")
	scene.queue_free()
	await process_frame
	print("test_em86_platforms: %d assertion(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
