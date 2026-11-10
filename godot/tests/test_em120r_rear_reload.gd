## The Longbow loads its existing missile through the rear; no side magazine is added.
extends SceneTree

const HandSkin = preload("res://tests/hand_skin_probe.gd")

var _assertions := 0
var _failures := 0


func _init() -> void:
	Engine.max_fps = 60
	call_deferred("_run")


func _run() -> void:
	var state = root.get_node("GameState")
	state.reset()
	state.current_weapon = &"em120r"
	var weapon = (load("res://scenes/weapons/em120r.tscn") as PackedScene).instantiate()
	root.add_child(weapon)
	await process_frame
	_assert(weapon.get_node_or_null("ViewModel/Weapon/SupplyModule") == null, "Longbow has no added side supply module or magazine")
	var missile := weapon.get_node_or_null("ViewModel/Weapon/LoadingMissile") as Node3D
	_assert(missile != null, "Longbow resolves its existing missile model for rear loading")
	_assert(weapon.weapon_data.mag_size == 10 and is_equal_approx(weapon.weapon_data.reload_time, 3.0), "Rear loading retains ten ready rounds and three-second bulk reload")
	if missile != null:
		_assert(missile.scene_file_path == "res://assets/models/weapons/ec120_missile.glb", "Loading missile instances the existing registered EC-120 model")
		_assert(not missile.visible, "Rear loading missile is hidden during idle")
		_check_motion(weapon, missile, state)
	weapon.queue_free()
	await process_frame
	await process_frame
	print("EM120R_REAR_RELOAD assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures else 0)


func _check_motion(weapon: Node3D, missile: Node3D, state: Node) -> void:
	weapon.set_process(false)
	weapon.set_physics_process(false)
	var gun: Node3D = weapon._weapon_node
	var config = root.get_node("GameConfig")
	var source_points := _points(missile, missile)
	_assert(not source_points.is_empty(), "Rear loading uses actual visible missile vertices")
	if source_points.is_empty():
		return
	var minimum := source_points[0].z
	var maximum := minimum
	var grip: Vector3 = config.EM120R_REAR_MISSILE_GRIP
	var grip_distance := INF
	for point in source_points:
		minimum = minf(minimum, point.z)
		maximum = maxf(maximum, point.z)
		grip_distance = minf(grip_distance, grip.distance_to(point))
	_assert(grip_distance < 0.003 and grip.z > maximum - 0.04, "Left palm targets the actual rear missile surface within three millimeters")
	var breech: Vector3 = config.EM120R_REAR_BREECH
	var lip_distance := INF
	for point in _points(gun, gun, missile):
		lip_distance = minf(lip_distance, point.distance_to(breech))
	_assert(lip_distance < 0.025, "Rear breech lies at the original launcher rear lip geometry")
	var original_scale := missile.scale
	var source = (load("res://addons/community_weapons/black_pistol_arms.glb") as PackedScene).instantiate()
	root.add_child(source)
	var source_animation := source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	source_animation.play(&"idle")
	source_animation.seek(0.0, true)
	source_animation.pause()
	var source_skeleton := source.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var rests: Array[Transform3D] = []
	var scales: Array[Vector3] = []
	var lengths: Array[float] = []
	for bone in source_skeleton.get_bone_count():
		rests.append(source_skeleton.get_bone_rest(bone))
		scales.append(source_skeleton.get_bone_pose_scale(bone))
	var segments := [["L_arm_02", "L_elbow_03"], ["L_elbow_03", "L_wrist_04"], ["R_arm_026", "R_elbow_027"], ["R_elbow_027", "R_wrist_028"]]
	for segment in segments:
		lengths.append(source_skeleton.get_bone_global_pose(source_skeleton.find_bone(segment[0])).origin.distance_to(source_skeleton.get_bone_global_pose(source_skeleton.find_bone(segment[1])).origin))
	source.free()
	state.em120r_mag = 4
	state.em120r_reserve = 20
	root.get_node("Events").weapon_reload_started.emit(&"em120r")
	var previous_nose_z := INF
	var first_nose_z := 0.0
	var final_nose_z := 0.0
	var first_aligned := true
	var samples := 0
	for step in 61:
		var phase := float(step) / 60.0
		weapon._arms_animation.seek(weapon.weapon_data.reload_time * phase, true)
		weapon._process(0.0)
		var skeleton: Skeleton3D = weapon._arms_skeleton
		var source_rig_intact := true
		for bone in skeleton.get_bone_count():
			source_rig_intact = source_rig_intact and skeleton.get_bone_rest(bone).is_equal_approx(rests[bone]) and skeleton.get_bone_pose_scale(bone).is_equal_approx(scales[bone])
		for segment_index in segments.size():
			var segment: Array = segments[segment_index]
			var length := skeleton.get_bone_global_pose(skeleton.find_bone(segment[0])).origin.distance_to(skeleton.get_bone_global_pose(skeleton.find_bone(segment[1])).origin)
			source_rig_intact = source_rig_intact and absf(length - lengths[segment_index]) < 0.0001
		_assert(source_rig_intact, "phase %d preserves every source bone rest/scale and both original upper/forearm lengths" % step)
		var nose := gun.to_local(missile.to_global(Vector3(0, 0, minimum)))
		var right := HandSkin.palm_world(weapon._arms_node, weapon._arms_skeleton, "R")
		var right_target: Vector3 = gun.to_global(config.BLACK_LONG_GUN_PROFILES[&"em120r"].right_grip)
		_assert(right.distance_to(right_target) < 0.003 and missile.scale.is_equal_approx(original_scale), "phase %d keeps right palm on launcher and source missile scale intact" % step)
		if phase >= config.EM120R_REAR_CONTACT_PHASE and phase <= config.EM120R_REAR_RELEASE_PHASE:
			var left := HandSkin.palm_world(weapon._arms_node, weapon._arms_skeleton, "L")
			print("REAR_PALM phase=", phase, " error_m=", left.distance_to(missile.to_global(grip)), " left_gun=", gun.to_local(left), " target=", missile.position + grip)
			_assert(missile.visible and left.distance_to(missile.to_global(grip)) < 0.003, "phase %d actual left palm carries the missile tail within three millimeters" % step)
			_assert(gun.to_local(left).z >= breech.z, "phase %d carrying palm stays outside the rear breech" % step)
		if phase >= config.EM120R_REAR_ALIGN_PHASE and phase <= config.EM120R_REAR_SEAT_PHASE:
			_assert(Vector2(nose.x - breech.x, nose.y - breech.y).length() < 0.001 and nose.z <= previous_nose_z + 0.0001, "phase %d nose follows the bore axis forward through the rear" % step)
			if first_aligned:
				first_nose_z = nose.z
				first_aligned = false
			previous_nose_z = nose.z
			final_nose_z = nose.z
			samples += 1
		if phase >= config.EM120R_REAR_SEAT_PHASE:
			_assert(not missile.visible, "phase %d fully inserted missile hides" % step)
		if phase > config.EM120R_REAR_RELEASE_PHASE:
			var left := gun.to_local(HandSkin.palm_world(weapon._arms_node, weapon._arms_skeleton, "L"))
			var support: Vector3 = config.BLACK_LONG_GUN_PROFILES[&"em120r"].support_grip_hip
			var outside := left.z >= breech.z or Vector2(left.x, left.y).length() >= Vector2(support.x, support.y).length() - 0.003
			_assert(left.is_finite() and outside, "phase %d released left palm returns outside the bore axis" % step)
	_assert(samples > 20 and first_nose_z - final_nose_z > (maximum - minimum) * 0.9, "Missile advances its actual full length into the rear bore")
	_assert(state.em120r_mag == 4 and state.em120r_reserve == 20, "Scrubbing reload visuals cannot settle ammunition")
	state.current_weapon = &"pistol"
	root.get_node("Events").weapon_switched.emit(&"pistol")
	_assert(not weapon._is_reloading and not missile.visible and gun.transform.is_equal_approx(weapon._weapon_home), "Switching restores launcher and hides loading missile")


func _points(owner: Node3D, coordinates: Node3D, excluded: Node3D = null) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for node in owner.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or (excluded != null and excluded.is_ancestor_of(mesh)):
			continue
		var to_coordinates := coordinates.global_transform.affine_inverse() * mesh.global_transform
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				points.append(to_coordinates * vertex)
	return points


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
