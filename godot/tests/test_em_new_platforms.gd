extends SceneTree

var _failures := 0
var _player: CharacterBody3D
var _state
var _scene: Node3D


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _settle_weapon(weapon: Node) -> void:
	for frame in 20:
		_player._process(1.0 / 60.0)
		weapon._process(1.0 / 60.0)


func _run() -> void:
	var ids: Array[StringName] = [&"em57s2", &"em86m", &"em40t1"]
	var missing := false
	for weapon_id in ids:
		var exists := ResourceLoader.exists("res://scenes/weapons/%s.tscn" % weapon_id) \
			and ResourceLoader.exists("res://scenes/weapons/%s.tres" % weapon_id) \
			and ResourceLoader.exists("res://assets/models/weapons/%s_viewmodel.glb" % weapon_id)
		_assert(exists, "%s has a scene, data resource and game model" % weapon_id)
		missing = missing or not exists
	if missing:
		quit(1)
		return

	_state = root.get_node("GameState")
	_state.reset()
	root.size = Vector2i(1920, 1080)
	_scene = (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	_player = _scene.get_node("Player") as CharacterBody3D
	await process_frame

	_assert(_state.em57s2_mag == 150 and _state.em86m_mag == 500 and _state.em40t1_mag == 20, "new magazines initialize to 150, 500 and 20")
	_assert(_state.pistol_reserve == 600 and _state.em86_reserve == 900 and _state.rifle_grenades == 200, "EC-57, EC-86 and EC-40 use the existing shared reserves")
	_assert(_state.fire_modes[&"em57s2"] == &"auto" and _state.fire_modes[&"em86m"] == &"auto" and _state.fire_modes[&"em40t1"] == &"semi", "default fire modes are auto, auto and semi-only")

	var expected := {
		&"em57s2": {"damage": 45.0, "mag": 150, "reserve": 600, "rpm": 1200.0},
		&"em86m": {"damage": 180.0, "mag": 500, "reserve": 900, "rpm": 800.0},
	}
	for weapon_id in [&"em57s2", &"em86m"]:
		var spec: Dictionary = expected[weapon_id]
		var data = load("res://scenes/weapons/%s.tres" % weapon_id)
		data.sync_from_config()
		_assert(is_equal_approx(data.damage_body, spec.damage) and data.mag_size == spec.mag and data.reserve_size == spec.reserve, "%s has its specified damage, magazine and shared reserve" % weapon_id)
		_assert(is_equal_approx(data.fire_interval, 60.0 / spec.rpm) and is_equal_approx(data.semi_fire_interval, 60.0 / spec.rpm) and is_equal_approx(data.burst_fire_interval, 60.0 / spec.rpm), "%s uses its specified RPM in every available hitscan mode" % weapon_id)
		_player._switch_weapon(weapon_id)
		_assert(_state.current_weapon == weapon_id, "%s is selectable in the range" % weapon_id)
		var weapon = _player.get_node("Camera3D/WeaponMount/" + weapon_id.to_pascal_case())
		var target = _scene.get_node("RangeFacilities/Targets/CloseTarget")
		target.health = 1000.0
		target.scale = Vector3(2, 2, 2)
		_player.get_node("Camera3D").look_at(target.global_position + Vector3(0, 1, 0))
		weapon.weapon_data.spread_hip = 0.0
		weapon.weapon_data.spread_aim = 0.0
		var report := [0.0]
		var events = root.get_node("Events")
		var on_damage = func(amount: float, _head: bool): report[0] = amount
		events.damage_dealt.connect(on_damage)
		var fired: bool = weapon._fire()
		events.damage_dealt.disconnect(on_damage)
		target.scale = Vector3.ONE
		_assert(fired and is_equal_approx(report[0], spec.damage) and int(_state.get(weapon_id + "_mag")) == spec.mag - 1, "%s deals its exact damage and consumes its own magazine" % weapon_id)
		_state.set(weapon_id + "_mag", 0)
		if weapon_id == &"em57s2":
			_state.pistol_reserve = 600
		else:
			_state.em86_reserve = 900
		weapon._start_reload()
		_assert(weapon._is_reloading, "%s starts its real timed reload" % weapon_id)
		await create_timer(data.reload_time + 0.1).timeout
		_assert(not weapon._is_reloading, "%s finishes its real timed reload" % weapon_id)
		var shared_after: int = _state.pistol_reserve if weapon_id == &"em57s2" else _state.em86_reserve
		_assert(int(_state.get(weapon_id + "_mag")) == spec.mag and shared_after == spec.reserve - spec.mag, "%s reloads a full magazine from its shared ammunition pool" % weapon_id)
		var model = weapon.get_node("ViewModel/EM68A") as Node3D
		_assert(model.scene_file_path.contains("%s_viewmodel" % weapon_id), "%s uses its own generated first-person model" % weapon_id)
		var muzzle = weapon.get_node("ViewModel/EM68A/Muzzle") as Marker3D
		_assert((muzzle.global_position - weapon.global_position).dot(-_player._camera.global_basis.z) > 0.0, "%s muzzle points ahead of the camera" % weapon_id)

	_player._switch_weapon(&"em57s2")
	_player._cycle_fire_mode()
	_assert(_state.fire_modes[&"em57s2"] == &"semi", "EM-57S-2 auto switches to semi")
	_player._cycle_fire_mode()
	_assert(_state.fire_modes[&"em57s2"] == &"burst", "EM-57S-2 semi switches to three-round burst")
	var smg = _player.get_node("Camera3D/WeaponMount/Em57s2")
	smg._fire_cooldown = 0.0
	smg._try_fire()
	_assert(is_equal_approx(smg._fire_cooldown, 0.05), "EM-57S-2 burst fires at 1200 RPM")
	_player._cycle_fire_mode()
	_assert(_state.fire_modes[&"em57s2"] == &"auto", "EM-57S-2 burst wraps directly to auto without a grenade mode")
	smg._view_offset = 0.0
	_player._set_aiming(true)
	_settle_weapon(smg)
	_assert(not _player._dmr_scope.visible and smg._view_model.visible and _player._ads_reticle.mode == &"smg", "EM-57S-2 uses the EM-57S-1 holographic reticle with its own visible model")
	var smg_marker = smg.get_node("ViewModel/OpticAim") as Marker3D
	var smg_local: Vector3 = _player._camera.global_transform.affine_inverse() * smg_marker.global_position
	_assert(Vector2(smg_local.x, smg_local.y).length() < 0.001, "EM-57S-2 physical optic is centered on the camera axis")
	var smg_optic: Dictionary = _player._optic_meshes.get(&"em57s2", {})
	_assert(not smg_optic.is_empty() and smg_optic.node.mesh == smg_optic.bored, "EM-57S-2 ADS uses the transparent-lens model")
	_player._set_aiming(false)
	_settle_weapon(smg)
	_assert(not smg_optic.is_empty() and smg_optic.node.mesh == smg_optic.intact, "EM-57S-2 hip fire restores the intact model")

	_player._switch_weapon(&"em86m")
	_player._cycle_fire_mode()
	_assert(_state.fire_modes[&"em86m"] == &"semi", "EM-86M auto switches to semi")
	_player._cycle_fire_mode()
	_assert(_state.fire_modes[&"em86m"] == &"auto", "EM-86M semi wraps directly to auto with no burst or grenade mode")
	var mg = _player.get_node("Camera3D/WeaponMount/Em86m")
	mg._fire_cooldown = 0.0
	mg._try_fire()
	_assert(is_equal_approx(mg._fire_cooldown, 0.075), "EM-86M fires at 800 RPM")
	mg._view_offset = 0.0
	_player._set_aiming(true)
	_settle_weapon(mg)
	_assert(not _player._dmr_scope.visible and mg._view_model.visible and _player._ads_reticle.mode == &"em86b", "EM-86M uses the EM-86B circle-dot reticle with its own visible model")
	var mg_marker = mg.get_node("ViewModel/OpticAim") as Marker3D
	var mg_local: Vector3 = _player._camera.global_transform.affine_inverse() * mg_marker.global_position
	_assert(Vector2(mg_local.x, mg_local.y).length() < 0.001, "EM-86M physical sight is centered on the camera axis")
	_player._set_aiming(false)

	var launcher_data = load("res://scenes/weapons/em40t1.tres")
	launcher_data.sync_from_config()
	var config = root.get_node("GameConfig")
	_assert(launcher_data.mag_size == 20 and launcher_data.reserve_size == 200 and launcher_data.kind == WeaponData.Kind.HITSCAN, "EM-40T-1 has a 20-round magazine and shared EC-40 reserve with semi trigger semantics")
	_assert(is_equal_approx(launcher_data.projectile_speed, config.GRENADE_PROJECTILE_SPEED) and is_equal_approx(launcher_data.projectile_gravity, config.GRENADE_GRAVITY) and is_equal_approx(launcher_data.projectile_max_range, config.GRENADE_MAX_RANGE), "EM-40T-1 uses the exact underbarrel projectile ballistics")
	_assert(is_equal_approx(launcher_data.explode_radius, config.GRENADE_EXPLODE_RADIUS) and is_equal_approx(launcher_data.explode_kill_radius, config.GRENADE_EXPLODE_KILL_RADIUS) and is_equal_approx(launcher_data.explode_kill_damage, config.GRENADE_EXPLODE_KILL_DAMAGE) and is_equal_approx(launcher_data.explode_damage, config.GRENADE_EXPLODE_DAMAGE) and is_equal_approx(launcher_data.explode_falloff_factor, config.GRENADE_EXPLODE_FALLOFF_FACTOR), "EM-40T-1 uses the exact underbarrel explosion radius and damage")
	_player._switch_weapon(&"em40t1")
	var launcher = _player.get_node("Camera3D/WeaponMount/Em40t1")
	var children_before := _scene.get_child_count()
	var grenade_fired: bool = launcher._fire()
	_assert(grenade_fired and _state.em40t1_mag == 19 and _state.rifle_grenades == 200 and _scene.get_child_count() == children_before + 1, "EM-40T-1 fires one projectile from its magazine without draining the shared reserve")
	var projectile = _scene.get_child(_scene.get_child_count() - 1)
	_assert(is_equal_approx(projectile._velocity.length(), config.GRENADE_PROJECTILE_SPEED) and projectile._data.explode_radius == config.GRENADE_EXPLODE_RADIUS, "EM-40T-1 projectile has the real shared velocity and explosion data")
	var blast_target = _scene.get_node("RangeFacilities/Targets/CloseTarget")
	blast_target.add_to_group(&"enemy")
	blast_target.health = 1000.0
	projectile._apply_area_damage(blast_target.global_position)
	_assert(is_equal_approx(blast_target.health, 250.0), "EM-40T-1 explosion deals 750 inside 10m")
	blast_target.health = 1000.0
	projectile._apply_area_damage(blast_target.global_position + Vector3(12, 0, 0))
	_assert(is_equal_approx(blast_target.health, 625.0), "EM-40T-1 explosion deals 375 between 10m and 15m")
	blast_target.health = 1000.0
	projectile._apply_area_damage(blast_target.global_position + Vector3(15.1, 0, 0))
	_assert(is_equal_approx(blast_target.health, 1000.0), "EM-40T-1 explosion deals no damage beyond 15m")
	blast_target.remove_from_group(&"enemy")
	projectile.queue_free()
	_state.em40t1_mag = 0
	_state.rifle_grenades = 200
	launcher._start_reload()
	_assert(launcher._is_reloading, "EM-40T-1 starts its real timed reload")
	await create_timer(launcher_data.reload_time + 0.1).timeout
	_assert(not launcher._is_reloading and _state.em40t1_mag == 20 and _state.rifle_grenades == 180, "EM-40T-1 reloads 20 EC-40 rounds from the shared underbarrel pool")
	_player._cycle_fire_mode()
	_assert(_state.fire_modes[&"em40t1"] == &"semi", "EM-40T-1 remains semi-auto")
	_player._set_aiming(true)
	_settle_weapon(launcher)
	_assert(_player._dmr_scope.visible and _player._dmr_tactical.visible and not launcher._view_model.visible, "EM-40T-1 uses a full-screen scope and hides its weapon")
	_assert(_player._dmr_scope_material.get_shader_parameter("center_style") > 1.5 and _player._dmr_tactical.reticle_mode == &"grenade", "EM-40T-1 has its own ballistic-drop reticle rather than the DMR pattern")
	var target = _scene.get_node("RangeFacilities/Targets/CloseTarget")
	_player.get_node("Camera3D").look_at(target.global_position + Vector3(0, 1, 0))
	_player._dmr_tactical.size = Vector2(1920, 1080)
	_player._dmr_tactical._refresh_range()
	_player._dmr_tactical._refresh_targets()
	_assert(not _player._dmr_tactical._range_text.contains("---") and not _player._dmr_tactical._targets.is_empty(), "EM-40T-1 retains live target search and ranging")
	_assert(is_equal_approx(_player._dmr_tactical.range_limit, config.GRENADE_MAX_RANGE), "EM-40T-1 target search respects the 200m grenade range")

	var categories: Array = config.WEAPON_CATEGORIES
	_assert(&"em57s2" in categories[1].weapons and &"em86m" in categories[4].weapons and &"em40t1" in categories[5].weapons, "new weapons occupy SMG, machine-gun and explosive categories")
	_assert(config.SMG_FIRE_INTERVAL == 0.06 and config.EM86B_DAMAGE_BODY == 120.0 and config.GRENADE_AMMO == 200 and config.GRENADE_EXPLODE_DAMAGE == 750.0, "existing weapon and underbarrel values remain unchanged")
	_scene.queue_free()
	await process_frame
	print("test_em_new_platforms: %d assertion(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
