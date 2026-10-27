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
	_assert(player._weapon_mount.position.is_equal_approx(player._ads_mount_targets[&"dmr"]), "switching to DMR while aiming applies its mount")
	_assert(player._dmr_scope.visible, "DMR full-screen scope is visible while aiming")
	player._switch_weapon(&"shotgun")
	await create_timer(0.25).timeout
	_assert(is_equal_approx(player._camera.fov, 60.0), "switching to shotgun while aiming applies FOV 60")
	var shotgun := player.get_node("Camera3D/WeaponMount/Shotgun")
	_assert(not shotgun._optic_node.visible, "shotgun opaque optic is hidden while aiming")
	_assert(absf(player._ads_mount_targets[&"shotgun"].z - (player._mount_hip_pos.z - 0.06)) < 0.001, "shotgun ADS mount moves forward 6cm")
	player._switch_weapon(&"rifle")
	await create_timer(0.25).timeout
	_assert(is_equal_approx(player._camera.fov, 60.0), "switching back to rifle restores ADS settings")
	player.queue_free()
	await process_frame
	var district := (load("res://scenes/levels/district_b.tscn") as PackedScene).instantiate()
	root.add_child(district)
	await process_frame
	_assert(not district.get_node("HUD/CompassBar").show_mission_markers, "district compass hides street mission markers")
	_assert(not district.get_node("HUD/Minimap").visible, "district hides street minimap")
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
