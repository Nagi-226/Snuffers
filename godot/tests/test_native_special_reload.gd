## Special supply paths retain real timed gameplay while moving native hands and gun.
extends SceneTree

const HandSkin = preload("res://tests/hand_skin_probe.gd")

var _assertions := 0
var _failures := 0


func _init() -> void:
	Engine.max_fps = 60
	call_deferred("_run")


func _run() -> void:
	var state = root.get_node("GameState")
	await _check_spas(state)
	state.reset()
	state.current_weapon = &"em120r"
	var weapon = (load("res://scenes/weapons/em120r.tscn") as PackedScene).instantiate()
	root.add_child(weapon)
	await process_frame
	var skeleton: Skeleton3D = weapon._arms_skeleton
	_assert(skeleton != null and skeleton.get_bone_count() == 60, "Longbow uses the original sixty-joint black arm skin")
	var supply := weapon.get_node_or_null("ViewModel/Weapon/LoadingMissile") as Node3D
	_assert(supply != null and supply.scene_file_path == "res://assets/models/weapons/ec120_missile.glb" and weapon.get_node_or_null("ViewModel/Weapon/SupplyModule") == null, "Longbow rear loads the existing missile without an added side magazine")
	_assert(weapon.weapon_data.mag_size == 10 and is_equal_approx(weapon.weapon_data.reload_time, 3.0), "Longbow preserves ten ready rounds and three-second bulk reload")
	if supply != null and skeleton != null and skeleton.get_bone_count() == 60:
		var gun: Node3D = weapon._weapon_node
		var home := gun.transform
		var module_home := supply.transform
		state.em120r_mag = 4
		state.em120r_reserve = 20
		weapon._start_reload()
		weapon._start_reload()
		await create_timer(weapon.weapon_data.reload_time * 0.36).timeout
		_assert(weapon._is_reloading and gun.position.distance_to(home.origin) >= 0.015 and home.basis.get_rotation_quaternion().angle_to(gun.basis.get_rotation_quaternion()) >= deg_to_rad(8.0), "Longbow lowers and turns the actual tube to expose its rear breech")
		_assert(supply.visible and supply.position.distance_to(module_home.origin) >= 0.04 and supply.transform.is_finite(), "Longbow carries the actual missile toward its rear breech")
		_assert(state.em120r_mag == 4 and state.em120r_reserve == 20, "Longbow moves visuals before timed ammunition settlement")
		await create_timer(weapon.weapon_data.reload_time * 0.72).timeout
		_assert(not weapon._is_reloading and state.em120r_mag == 10 and state.em120r_reserve == 14, "Longbow transfers exactly the missing six rounds once")
		_assert(gun.transform.is_equal_approx(home) and supply.transform.is_equal_approx(module_home) and not supply.visible, "Longbow completion restores tube and hides the inserted missile")
		state.em120r_mag = 2
		state.em120r_reserve = 12
		weapon._start_reload()
		await create_timer(weapon.weapon_data.reload_time * 0.36).timeout
		state.current_weapon = &"pistol"
		root.get_node("Events").weapon_switched.emit(&"pistol")
		_assert(not weapon._is_reloading and gun.transform.is_equal_approx(weapon._weapon_home) and supply.transform.is_equal_approx(module_home) and not supply.visible, "Longbow switching cancels at the authored callback transform and hides the loading missile")
		await process_frame
		await process_frame
		_assert(gun.transform.is_equal_approx(home), "Longbow returns to its close hip display on the following rendered frames")
		await create_timer(weapon.weapon_data.reload_time).timeout
		_assert(state.em120r_mag == 2 and state.em120r_reserve == 12, "Cancelled Longbow timer cannot transfer ammunition later")
	weapon.queue_free()
	await process_frame
	await process_frame
	print("NATIVE_SPECIAL_RELOAD assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures else 0)


func _check_spas(state: Node) -> void:
	state.reset()
	state.current_weapon = &"spas12"
	var weapon = (load("res://scenes/weapons/spas12.tscn") as PackedScene).instantiate()
	root.add_child(weapon)
	await process_frame
	weapon.set_process(false)
	weapon.set_physics_process(false)
	var skeleton: Skeleton3D = weapon._arms_skeleton
	_assert(skeleton != null and skeleton.get_bone_count() == 60, "SPAS uses the original sixty-joint black arm skin")
	state.spas12_mag = 2
	state.spas12_reserve = 5
	var gun: Node3D = weapon._weapon_node
	var home := gun.transform
	weapon._start_reload()
	weapon._reload_progress = 0.45
	weapon._process(0.0)
	_assert(gun.position.distance_to(home.origin) >= 0.015 and home.basis.get_rotation_quaternion().angle_to(gun.basis.get_rotation_quaternion()) >= deg_to_rad(8.0), "SPAS cants and raises the actual receiver while inserting a shell")
	if skeleton != null and skeleton.get_bone_count() == 60:
		var config = root.get_node("GameConfig")
		var shell: Node3D = weapon._shell
		var expected: Vector3 = shell.global_position + gun.global_basis.orthonormalized() * config.SPAS12_SHELL_HAND_OFFSET
		_assert(shell.visible and _palm_world(weapon, "L_wrist_04", "L_palm_017").distance_to(expected) < 0.003, "SPAS actual weighted left palm carries the displayed shell within three millimeters")
	state.current_weapon = &"rifle"
	root.get_node("Events").weapon_switched.emit(&"rifle")
	_assert(not weapon._is_reloading and not weapon._shell.visible and gun.transform.is_equal_approx(weapon._weapon_home), "SPAS switching cancels shell and receiver movement")
	state.current_weapon = &"spas12"
	root.get_node("Events").weapon_switched.emit(&"spas12")
	await physics_frame
	var pump_mesh := gun.find_child("Object_21", true, false) as MeshInstance3D
	_assert(pump_mesh != null and pump_mesh.mesh != null, "SPAS pump check resolves the actual rendered fore-end")
	var pump_start := gun.to_local(HandSkin.mesh_center(pump_mesh)) if pump_mesh != null else Vector3.ZERO
	_assert(weapon._fire(), "SPAS retains actual shell firing before pump coordination")
	weapon._process(root.get_node("GameConfig").SPAS12_PUMP_TIME * 0.4)
	# Compare in gun coordinates so recoil and restoring the hip cant cannot masquerade as pump travel.
	var pump_motion := gun.to_local(HandSkin.mesh_center(pump_mesh)) - pump_start if pump_mesh != null else Vector3.ZERO
	_assert(pump_motion.z >= 0.04, "SPAS firing moves actual weighted fore-end vertices back along the tube")
	if skeleton != null and skeleton.get_bone_count() == 60:
		var config = root.get_node("GameConfig")
		var profile: Dictionary = config.BLACK_LONG_GUN_PROFILES[&"spas12"]
		var expected: Vector3 = gun.to_global((profile.support_grip_hip as Vector3) + pump_motion)
		_assert(_palm_world(weapon, "L_wrist_04", "L_palm_017").distance_to(expected) < 0.003, "SPAS actual weighted left palm follows the moving pump sleeve")
	weapon.queue_free()
	await process_frame


func _palm_world(weapon: Node3D, wrist: String, palm: String) -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	var skeleton: Skeleton3D = weapon._arms_skeleton
	for node in weapon._arms_node.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or mesh.skin == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var width: int = bones.size() / vertices.size()
			for vertex in vertices.size():
				var point := Vector3.ZERO
				var selected := 0.0
				for influence in width:
					var offset := vertex * width + influence
					var weight := weights[offset]
					if weight <= 0.0:
						continue
					var bind := bones[offset]
					var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind))
					point += (skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * vertices[vertex]) * weight
					if skeleton.get_bone_name(bone) in [wrist, palm]:
						selected += weight
				if selected > 0.65:
					total += skeleton.global_transform * point
					count += 1
	return total / maxf(float(count), 1.0)


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
