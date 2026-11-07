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


func _run() -> void:
	var ids: Array[StringName] = [&"em127g", &"em12g2"]
	var missing := false
	for weapon_id in ids:
		var exists := ResourceLoader.exists("res://scenes/weapons/%s.tscn" % weapon_id) and ResourceLoader.exists("res://scenes/weapons/%s.tres" % weapon_id)
		_assert(exists, "%s has a scene and data resource" % weapon_id)
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
	_assert(_state.em127g_mag == 30 and _state.em12g2_mag == 64, "EM-127G and EM-12G-2 magazines initialize to 30 and 64")
	_assert(_state.magnum_reserve == 1500 and _state.shotgun_reserve == 160, "EC-127 and EC-12 use their existing shared reserves")
	_assert(_state.fire_modes[&"em127g"] == &"semi" and _state.fire_modes[&"em12g2"] == &"auto", "Gauss is semi-auto and EM-12G-2 starts full-auto")
	var gauss_data = load("res://scenes/weapons/em127g.tres")
	gauss_data.sync_from_config()
	_assert(is_equal_approx(gauss_data.damage_body, 450.0) and gauss_data.mag_size == 30 and gauss_data.reserve_size == 1500, "EM-127G deals 450 damage with 30 rounds and shared EC-127")
	var shotgun_data = load("res://scenes/weapons/em12g2.tres")
	shotgun_data.sync_from_config()
	_assert(shotgun_data.pellet_count == 12 and is_equal_approx(shotgun_data.damage_body, 30.0) and shotgun_data.mag_size == 64, "EM-12G-2 fires twelve 30-damage pellets from a 64-round drum")
	_assert(is_equal_approx(shotgun_data.fire_interval, 60.0 / 650.0) and shotgun_data.hitscan_range == 50.0, "EM-12G-2 fires at 650 RPM with a 50m maximum range")

	var target = scene.get_node("RangeFacilities/Targets/CloseTarget")
	_player.get_node("Camera3D").look_at(target.global_position + Vector3(0, 1, 0))
	_player._switch_weapon(&"em127g")
	var gauss = _player.get_node("Camera3D/WeaponMount/Em127g")
	target.health = 500.0
	target.scale = Vector3(3, 3, 3)
	var gauss_damage := [0.0]
	var game_events = root.get_node("Events")
	var on_gauss_damage = func(amount: float, _head: bool): gauss_damage[0] = amount
	game_events.damage_dealt.connect(on_gauss_damage)
	gauss.weapon_data.spread_hip = 0.0
	gauss.weapon_data.spread_aim = 0.0
	var gauss_fired: bool = gauss._fire()
	game_events.damage_dealt.disconnect(on_gauss_damage)
	target.scale = Vector3.ONE
	_assert(gauss_fired and is_equal_approx(gauss_damage[0], 450.0) and _state.em127g_mag == 29, "EM-127G deals its full 450 damage on a real hit")
	_state.em127g_mag = 0
	_state.magnum_reserve = 1500
	gauss._on_weapon_reloaded(&"em127g")
	_assert(_state.em127g_mag == 30 and _state.magnum_reserve == 1470, "EM-127G reloads from shared EC-127")
	_player._set_aiming(true)
	for frame in 20:
		_player._process(1.0 / 60.0)
		gauss._process(1.0 / 60.0)
	_assert(_player._dmr_scope.visible and _player._dmr_tactical.visible and not gauss._view_model.visible, "EM-127G uses the full-screen tactical scope and hides the weapon")
	_assert(_player._em86s_zoom_index == 0 and is_equal_approx(_player._camera.fov, 17.5), "EM-127G starts at 16x")
	_assert(_player._dmr_scope_material.get_shader_parameter("center_style") > 0.5, "EM-127G uses the EM-86S diamond center")
	_player._adjust_em86s_zoom(1)
	_player._process(1.0 / 60.0)
	_assert(_player._em86s_zoom_index == 1 and is_equal_approx(_player._camera.fov, 8.75), "EM-127G wheel selects 32x")
	_player._adjust_em86s_zoom(1)
	_player._process(1.0 / 60.0)
	_assert(_player._em86s_zoom_index == 2 and is_equal_approx(_player._camera.fov, 4.375), "EM-127G wheel selects 64x")
	_player._adjust_em86s_zoom(1)
	_assert(_player._em86s_zoom_index == 2, "EM-127G magnification clamps at 64x")
	_player._adjust_em86s_zoom(-1)
	_player._process(1.0 / 60.0)
	_assert(_player._em86s_zoom_index == 1 and is_equal_approx(_player._camera.fov, 8.75), "EM-127G backward wheel returns to 32x")
	_player._set_aiming(false)
	_player._set_aiming(true)
	for frame in 20:
		_player._process(1.0 / 60.0)
	_assert(_player._em86s_zoom_index == 0 and is_equal_approx(_player._camera.fov, 17.5), "EM-127G resets to 16x on a new ADS hold")
	_player._dmr_tactical.size = Vector2(1920, 1080)
	_player._dmr_tactical._refresh_range()
	_player._dmr_tactical._refresh_targets()
	_assert(not _player._dmr_tactical._range_text.contains("---") and not _player._dmr_tactical._targets.is_empty(), "EM-127G retains target tracking and ranging")
	_player._cycle_fire_mode()
	_assert(_state.fire_modes[&"em127g"] == &"semi", "EM-127G remains semi-auto")

	_player._set_aiming(false)
	_player._switch_weapon(&"em12g2")
	var shotgun = _player.get_node("Camera3D/WeaponMount/Em12g2")
	target.health = 500.0
	_player.get_node("Camera3D").look_at(target.global_position + Vector3(0, 1, 0))
	var damage_report := [0.0]
	var events = root.get_node("Events")
	var on_damage = func(amount: float, _head: bool): damage_report[0] = amount
	events.damage_dealt.connect(on_damage)
	var shotgun_fired: bool = shotgun._fire()
	events.damage_dealt.disconnect(on_damage)
	_assert(shotgun_fired and is_equal_approx(damage_report[0], 360.0) and _state.em12g2_mag == 63, "EM-12G-2 deals 360 total damage when all twelve pellets hit")
	_state.em12g2_mag = 0
	_state.shotgun_reserve = 160
	shotgun._on_weapon_reloaded(&"em12g2")
	_assert(_state.em12g2_mag == 64 and _state.shotgun_reserve == 96, "EM-12G-2 reloads from shared EC-12")
	_player._cycle_fire_mode()
	_assert(_state.fire_modes[&"em12g2"] == &"semi", "EM-12G-2 full-auto switches to semi-auto")
	_player._cycle_fire_mode()
	_assert(_state.fire_modes[&"em12g2"] == &"auto", "EM-12G-2 semi-auto returns to full-auto")
	_state.is_aiming = true
	_assert(is_equal_approx(shotgun._spread_for_distance(14.0), 0.0) and shotgun._spread_for_distance(16.0) > 0.0, "EM-12G-2 starts pellet spread beyond the same 15m threshold")
	_state.is_aiming = true
	for frame in 20:
		_player._process(1.0 / 60.0)
		shotgun._process(1.0 / 60.0)
	_assert(not _player._dmr_scope.visible and shotgun._view_model.visible and _player._ads_reticle.mode == &"shotgun", "EM-12G-2 uses the EM-68A-style holographic reticle")
	var optic_pair: Dictionary = _player._optic_meshes.get(&"em12g2", {})
	_assert(not optic_pair.is_empty() and optic_pair.node.mesh == optic_pair.bored, "EM-12G-2 ADS uses its open optic model")
	_assert(_player.get_node("Camera3D/WeaponMount/Rifle").visible and not shotgun.get_node("ViewModel/Arms").visible, "EM-12G-2 ADS uses the validated EM-68A view without duplicate arms")
	_player._set_aiming(false)
	for frame in 20:
		_player._process(1.0 / 60.0)
		shotgun._process(1.0 / 60.0)
	_assert(not optic_pair.is_empty() and optic_pair.node.mesh == optic_pair.intact, "EM-12G-2 hip fire restores the intact optic model")
	for weapon_id in ids:
		var model := _player.get_node("Camera3D/WeaponMount/" + weapon_id.to_pascal_case() + "/ViewModel/Weapon") as Node3D
		var bounds := AABB()
		var first := true
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			var local_bounds: AABB = (model.global_transform.affine_inverse() * (mesh as MeshInstance3D).global_transform) * (mesh as MeshInstance3D).get_aabb()
			bounds = local_bounds if first else bounds.merge(local_bounds)
			first = false
		_assert(bounds.size.z > bounds.size.x, "%s model points forward" % weapon_id)
	var audio = (load("res://scripts/ui/audio_manager.gd") as GDScript).new()
	root.add_child(audio)
	var children_before: int = audio.get_child_count()
	events.weapon_fired.emit(&"em127g")
	var rail_player := audio.get_child(audio.get_child_count() - 1) as AudioStreamPlayer
	_assert(audio.get_child_count() == children_before + 1 and rail_player.stream == audio._get_stream(&"railgun") and rail_player.stream != audio._get_stream(&"rifle"), "EM-127G uses its own heavy railgun sound")
	audio.queue_free()
	var config = root.get_node("GameConfig")
	_assert(config.MAGNUM_DAMAGE_BODY == 150.0 and config.SHOTGUN_FIRE_INTERVAL == 0.12 and config.EM86B_DAMAGE_BODY == 120.0 and config.EM86S_DAMAGE_BODY == 240.0, "existing weapon values remain unchanged")
	scene.queue_free()
	await process_frame
	print("test_heavy_platforms: %d assertion(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
