extends SceneTree

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _run() -> void:
	var state = root.get_node("GameState")
	state.reset()
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	await process_frame
	player._switch_weapon(&"dmr")
	_assert(state.current_weapon == &"rifle", "locked DMR cannot be selected")
	state.weapon_unlocked[&"dmr"] = true
	state.weapon_unlocked[&"shotgun"] = true
	state.is_aiming = true
	await create_timer(0.25).timeout
	_assert(is_equal_approx(player._camera.fov, 60.0), "rifle ADS FOV remains 60")
	player._switch_weapon(&"dmr")
	await create_timer(0.25).timeout
	_assert(is_equal_approx(player._camera.fov, 35.0), "switching to DMR while aiming applies FOV 35")
	_assert(is_equal_approx(player._camera.position.z, player._camera_hip_z), "DMR aiming does not inherit shotgun camera travel")
	_assert(player._weapon_mount.position.is_equal_approx(player._ads_mount_targets[&"dmr"]), "switching to DMR while aiming applies its mount")
	_assert(player._dmr_scope.visible, "DMR full-screen scope is visible while aiming")
	_assert(player._dmr_tactical.visible, "DMR tactical overlay activates with the full-screen scope")
	var dmr := player.get_node("Camera3D/WeaponMount/DMR")
	_assert(not dmr._view_model.visible, "DMR full-screen scope hides the complete weapon and floating arms")
	player._switch_weapon(&"shotgun")
	await create_timer(0.25).timeout
	_assert(is_equal_approx(player._camera.fov, 60.0), "switching to shotgun while aiming applies FOV 60")
	var shotgun := player.get_node("Camera3D/WeaponMount/Shotgun")
	_assert(shotgun._optic_node.visible, "shotgun optic frame stays visible while aiming")
	_assert(shotgun._optic_node.mesh == player._optic_meshes[&"shotgun"].bored, "shotgun ADS uses the physically bored optic mesh")
	_assert(is_equal_approx(player._ads_mount_targets[&"shotgun"].z, player._mount_hip_pos.z), "shotgun ADS does not push the weapon farther away")
	_assert(absf(player._camera.position.z - (player._camera_hip_z - GameConfig.SHOTGUN_ADS_CAMERA_FORWARD)) < 0.001, "shotgun ADS moves the player camera toward the optic")
	_assert(shotgun._aim_weight > 0.99, "shotgun support-arm IK reaches its ADS pose")
	var optic_aim := shotgun.get_node("ViewModel/Weapon/OpticAim") as Marker3D
	var optic_in_camera: Vector3 = player._camera.global_transform.affine_inverse() * optic_aim.global_position
	_assert(Vector2(optic_in_camera.x, optic_in_camera.y).length() < 0.001, "shotgun optic remains centered after support-arm IK")
	_assert(shotgun._weapon_node.transform.is_equal_approx(shotgun._pose_extra * shotgun._weapon_home), "shotgun arms cannot displace the weapon outside reload")
	player._switch_weapon(&"dmr")
	player._set_aiming(false)
	for frame in 3:
		await process_frame
		if player._dmr_scope.visible and not dmr._view_model.visible:
			break
	_assert(player._dmr_scope.visible and not dmr._view_model.visible, "DMR viewmodel stays hidden until the scope transition finishes")
	await create_timer(0.25).timeout
	_assert(dmr._view_model.visible, "DMR viewmodel and arms restore after leaving ADS")
	_assert(dmr._weapon_node.visible, "DMR weapon mesh restores after leaving ADS")
	player._set_aiming(true)
	player._switch_weapon(&"rifle")
	await create_timer(0.25).timeout
	_assert(is_equal_approx(player._camera.fov, 60.0), "switching back to rifle restores ADS settings")
	player._switch_weapon(&"shotgun")
	player._set_aiming(false)
	await create_timer(0.3).timeout
	_assert(player._weapon_mount.position.is_equal_approx(player._mount_hip_pos), "shotgun compensation preserves the hip-fire mount")
	var hip_optic: Vector3 = player._camera.global_transform.affine_inverse() * optic_aim.global_position
	player._set_aiming(true)
	await create_timer(0.06).timeout
	_assert(player._ads_weight > 0.05 and player._ads_weight < 0.95, "ADS regression samples a real transition frame")
	_assert(absf(player._ads_weight - shotgun._aim_weight) < 0.001, "shotgun pose and camera mount share the same ADS timing")
	optic_in_camera = player._camera.global_transform.affine_inverse() * optic_aim.global_position
	var expected_optic: Vector2 = Vector2(hip_optic.x, hip_optic.y) * (1.0 - shotgun._aim_weight)
	_assert(Vector2(optic_in_camera.x, optic_in_camera.y).distance_to(expected_optic) < 0.002, "shotgun optic follows the compensated hip-to-ADS trajectory")
	var frozen_weight: float = shotgun._aim_weight
	state.shotgun_mag = 0
	shotgun._start_reload()
	player._set_aiming(false)
	await create_timer(0.06).timeout
	_assert(is_equal_approx(shotgun._aim_weight, frozen_weight) and player._ads_weight < frozen_weight, "reload freezes pose while player ADS weight continues")
	_assert(player._weapon_mount.position.is_equal_approx(player._shotgun_mount_for_weight(shotgun._aim_weight)), "reload transition mount follows the actual weapon pose weight")
	player._switch_weapon(&"rifle")
	await create_timer(shotgun.weapon_data.reload_time + 0.1).timeout
	player.queue_free()
	await process_frame
	var district := (load("res://scenes/levels/district_b.tscn") as PackedScene).instantiate()
	root.add_child(district)
	await process_frame
	_assert(not district.get_node("HUD/CompassBar").show_mission_markers, "district compass hides street mission markers")
	_assert(district.get_node("HUD/Minimap").visible, "district shows its live minimap")
	_assert(district.get_node("HUD/Minimap")._map_ok, "district minimap loads warehouse-specific terrain and calibration")
	_assert(district.get_node("HUD/Minimap")._calib_min.x < -200.0, "district minimap uses the expanded warehouse bounds rather than street calibration")
	_assert(not district.get_node("HUD/Minimap")._show_mission_points, "district minimap does not show street mission markers")
	var seats_present := true
	for side in ["L", "R"]:
		for row in 3:
			seats_present = seats_present and district.has_node("APCSeat_%s%d" % [side, row])
	_assert(seats_present, "JB-02 cabin contains six troop seats")
	_assert(district.has_node("APCC4I"), "JB-02 cabin contains the C4I dashboard")
	_assert(district.has_node("Equipment_dmr") and district.has_node("Equipment_shotgun"), "JB-02 interior preserves both equipment pickups")
	var district_player := district.get_node("Player")
	state.is_night = true
	state.night_vision = false
	district_player._toggle_night_vision()
	_assert(state.night_vision and district.get_node("NightVisionOverlay")._overlay.visible, "district night vision activates")
	district_player._toggle_night_vision()
	_assert(not state.night_vision and not district.get_node("NightVisionOverlay")._overlay.visible, "district night vision deactivates")
	await create_timer(1.5).timeout
	district.queue_free()
	print("test_ads_switch: %d assertion(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
