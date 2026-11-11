extends SceneTree

var _assertions := 0
var _failures := 0
var _started: Dictionary = {}
var _finished: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(35.0).timeout.connect(func() -> void:
		push_error("black pistol integration timed out")
		quit(1))
	var events = root.get_node("Events")
	events.weapon_reload_started.connect(_on_started)
	events.weapon_reloaded.connect(_on_finished)
	for weapon_id in [&"pistol", &"magnum"]:
		await _check_weapon(weapon_id)
	events.weapon_reload_started.disconnect(_on_started)
	events.weapon_reloaded.disconnect(_on_finished)
	print("BLACK_PISTOL_INTEGRATION assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _check_weapon(weapon_id: StringName) -> void:
	var state = root.get_node("GameState")
	state.reset()
	state.current_weapon = weapon_id
	state.fire_modes[weapon_id] = &"semi"
	var mount := Node3D.new()
	mount.transform = Transform3D(Basis.from_euler(Vector3(0.1, 0.7, -0.1)), Vector3(210, 8, -170))
	root.add_child(mount)
	var packed := load("res://scenes/weapons/%s.tscn" % weapon_id) as PackedScene
	_assert(packed != null, "%s scene loads" % weapon_id)
	if packed == null:
		mount.queue_free()
		return
	var weapon = packed.instantiate()
	mount.add_child(weapon)
	await process_frame
	weapon.set_process(false)
	weapon.set_physics_process(false)
	var arms: Node3D = weapon.get_node("ViewModel/ArmsEM57P")
	var skeletons := arms.find_children("*", "Skeleton3D", true, false)
	var black := skeletons.size() == 1 and (skeletons[0] as Skeleton3D).get_bone_count() == 60
	_assert(black, "%s uses the native sixty-bone black arm rig" % weapon_id)
	var has_adapter := false
	for property: Dictionary in weapon.get_property_list():
		has_adapter = has_adapter or property.name == "_native_arms"
	_assert(has_adapter, "%s controller connects the native arm adapter" % weapon_id)
	var config = root.get_node("GameConfig")
	var profiles: Dictionary = config.get_script().get_script_constant_map().get("BLACK_PISTOL_PROFILES", {})
	_assert(profiles.has(weapon_id), "%s uses its measured shared grip profile" % weapon_id)
	if not black or not has_adapter or not profiles.has(weapon_id):
		mount.queue_free()
		await process_frame
		return
	var adapter = weapon._native_arms
	_assert(adapter != null, "%s native adapter configures successfully" % weapon_id)
	if adapter == null:
		mount.queue_free()
		await process_frame
		return
	var magazine: Node3D = weapon._magazine
	_assert(magazine != null and (magazine is MeshInstance3D or not magazine.find_children("*", "MeshInstance3D", true, false).is_empty()), "%s animates a real detachable magazine" % weapon_id)
	var skeleton: Skeleton3D = adapter.skeleton
	var animation: AnimationPlayer = adapter.animation
	var right := skeleton.find_bone("R_wrist_028")
	var left := skeleton.find_bone("L_wrist_04")
	var rests: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		rests.append(skeleton.get_bone_rest(bone))
	var lengths: Array[float] = []
	for chain: Array in [["L_arm_02", "L_elbow_03", "L_wrist_04"], ["R_arm_026", "R_elbow_027", "R_wrist_028"]]:
		lengths.append(skeleton.get_bone_global_pose(skeleton.find_bone(chain[0])).origin.distance_to(skeleton.get_bone_global_pose(skeleton.find_bone(chain[1])).origin))
		lengths.append(skeleton.get_bone_global_pose(skeleton.find_bone(chain[1])).origin.distance_to(skeleton.get_bone_global_pose(skeleton.find_bone(chain[2])).origin))
	var gun: Node3D = weapon._weapon_node
	var right_home := gun.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(right)
	var magazine_home: Transform3D = weapon._mag_home_transform
	state.set(weapon.mag_state_property, 3)
	state.set(weapon.reserve_state_property, 100)
	_assert(weapon._fire() and state.get(weapon.mag_state_property) == 2 and animation.current_animation == "fire", "%s real firing consumes one round and plays the native fire action" % weapon_id)
	for frame in 8:
		weapon._process(1.0 / 60.0)
	var duration: float = weapon.weapon_data.reload_time
	for empty in [false, true]:
		var starting_mag := 0 if empty else 2
		state.set(weapon.mag_state_property, starting_mag)
		state.set(weapon.reserve_state_property, 100)
		var start_count := int(_started.get(weapon_id, 0))
		var finish_count := int(_finished.get(weapon_id, 0))
		weapon._start_reload()
		weapon._start_reload()
		_assert(weapon._is_reloading and int(_started.get(weapon_id, 0)) == start_count + 1, "%s gates duplicate reload starts" % weapon_id)
		_assert(animation.current_animation == ("reload_empty" if empty else "reload"), "%s selects the correct native reload action" % weapon_id)
		var moved := false
		var profile: Dictionary = profiles[weapon_id]
		for step in 61:
			var progress := float(step) / 60.0
			weapon._process(0.0 if step == 0 else duration / 60.0)
			var wrist := gun.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(right)
			_assert(wrist.origin.distance_to(right_home.origin) < 0.003 and absf(wrist.basis.orthonormalized().get_rotation_quaternion().dot(right_home.basis.orthonormalized().get_rotation_quaternion())) > 0.9999, "%s reload %.3f keeps the right wrist on the grip" % [weapon_id, progress])
			if progress >= float(profile.reload_contact_phase) and progress <= float(profile.reload_seat_phase):
				var expected: Vector3 = magazine.global_transform * (profile.magazine_grip as Vector3)
				var actual := skeleton.global_transform * skeleton.get_bone_global_pose(left).origin
				_assert(actual.distance_to(expected) < 0.003, "%s reload %.3f keeps the left wrist at the actual magazine" % [weapon_id, progress])
			var valid := magazine.global_transform.is_finite() and gun.global_transform.is_finite()
			for bone in skeleton.get_bone_count():
				valid = valid and skeleton.get_bone_rest(bone).is_equal_approx(rests[bone]) and skeleton.get_bone_pose_scale(bone).is_equal_approx(Vector3.ONE) and skeleton.get_bone_global_pose(bone).is_finite()
			var length_index := 0
			for chain: Array in [["L_arm_02", "L_elbow_03", "L_wrist_04"], ["R_arm_026", "R_elbow_027", "R_wrist_028"]]:
				for segment in 2:
					valid = valid and absf(skeleton.get_bone_global_pose(skeleton.find_bone(chain[segment])).origin.distance_to(skeleton.get_bone_global_pose(skeleton.find_bone(chain[segment + 1])).origin) - lengths[length_index]) < 0.001
					length_index += 1
			_assert(valid, "%s reload %.3f preserves native bone lengths, rests, unit scales and finite transforms" % [weapon_id, progress])
			moved = moved or not magazine.transform.is_equal_approx(magazine_home)
		_assert(moved, "%s moves actual magazine geometry during reload" % weapon_id)
		_assert(not weapon._fire(), "%s cannot fire during reload" % weapon_id)
		await create_timer(duration + 0.1).timeout
		_assert(int(_finished.get(weapon_id, 0)) == finish_count + 1 and not weapon._is_reloading, "%s original timed reload completes exactly once" % weapon_id)
		_assert(state.get(weapon.mag_state_property) == weapon.weapon_data.mag_size and state.get(weapon.reserve_state_property) == 100 - (weapon.weapon_data.mag_size - starting_mag), "%s preserves reload ammunition math" % weapon_id)
		_assert(magazine.transform.is_equal_approx(magazine_home) and magazine.visible, "%s seats its real magazine after reload" % weapon_id)
	state.set(weapon.mag_state_property, 2)
	state.set(weapon.reserve_state_property, 100)
	var finishes := int(_finished.get(weapon_id, 0))
	weapon._start_reload()
	weapon._process(duration * 0.5)
	state.current_weapon = &"rifle"
	root.get_node("Events").weapon_switched.emit(&"rifle")
	_assert(not weapon._is_reloading and magazine.transform.is_equal_approx(magazine_home) and magazine.visible, "%s switching weapons resets the visible reload" % weapon_id)
	await create_timer(duration + 0.1).timeout
	_assert(int(_finished.get(weapon_id, 0)) == finishes and state.get(weapon.mag_state_property) == 2 and state.get(weapon.reserve_state_property) == 100, "%s cancelled reload cannot complete later" % weapon_id)
	mount.queue_free()
	await process_frame


func _on_started(weapon_id: StringName) -> void:
	_started[weapon_id] = int(_started.get(weapon_id, 0)) + 1


func _on_finished(weapon_id: StringName) -> void:
	_finished[weapon_id] = int(_finished.get(weapon_id, 0)) + 1


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)
