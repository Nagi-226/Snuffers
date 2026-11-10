extends SceneTree

const HandSkin = preload("res://tests/hand_skin_probe.gd")

const WEAPONS := [&"rifle", &"smg", &"lmg", &"dmr", &"shotgun", &"em57s2", &"em86b", &"em86d", &"em86s", &"em86m", &"em12g2", &"em127g", &"em127m", &"em40t1"]

var _failures := 0
var _assertions := 0
var _started: Dictionary = {}
var _finished: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(180.0).timeout.connect(func() -> void:
		push_error("magazine platform test timed out")
		quit(1))
	var config = root.get_node("GameConfig")
	var profiles: Dictionary = config.get_script().get_script_constant_map().get("MAGAZINE_RELOAD_PROFILES", {})
	var events = root.get_node("Events")
	events.weapon_reload_started.connect(_on_started)
	events.weapon_reloaded.connect(_on_finished)
	for weapon_id in WEAPONS:
		await _check_weapon(weapon_id, profiles)
	_assert(not profiles.has(&"spas12") and not profiles.has(&"em120r"), "SPAS remains tube-fed and Longbow rear missile loading stays outside detachable-magazine motion")
	events.weapon_reload_started.disconnect(_on_started)
	events.weapon_reloaded.disconnect(_on_finished)
	print("MAGAZINE_PLATFORMS assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures else 0)


func _check_weapon(weapon_id: StringName, profiles: Dictionary) -> void:
	var state = root.get_node("GameState")
	state.reset()
	state.current_weapon = weapon_id
	var parent := Node3D.new()
	parent.transform = Transform3D(Basis.from_euler(Vector3(0.13, 1.1, -0.07)), Vector3(230, 8, -170))
	root.add_child(parent)
	var weapon = (load("res://scenes/weapons/%s.tscn" % weapon_id) as PackedScene).instantiate()
	parent.add_child(weapon)
	await process_frame
	weapon.set_process(false)
	weapon.set_physics_process(false)
	for frame in 24:
		weapon._process(1.0 / 60.0)
	var magazine: Node3D = weapon._magazine
	_assert(magazine != null, "%s resolves its configured magazine node" % weapon_id)
	if magazine == null:
		parent.queue_free()
		await process_frame
		return
	var visible_mesh := magazine is MeshInstance3D or not magazine.find_children("*", "MeshInstance3D", true, false).is_empty()
	_assert(visible_mesh, "%s controls actual detachable geometry, including its documented supply position" % weapon_id)
	_assert(profiles.has(weapon_id), "%s has an approved magazine contact profile" % weapon_id)
	if not visible_mesh or not profiles.has(weapon_id):
		parent.queue_free()
		await process_frame
		return
	var profile: Dictionary = profiles[weapon_id]
	var direction: Vector3 = profile.extraction_direction
	_assert(direction.normalized().dot(Vector3.UP if weapon_id == &"em57s2" else Vector3.DOWN) > 0.99, "%s pulls along the actual top/bottom magazine well axis" % weapon_id)
	var gun: Node3D = weapon._weapon_node
	var skeleton: Skeleton3D = weapon._arms_skeleton
	var animation: AnimationPlayer = weapon._arms_animation
	animation.set_process(false)
	animation.set_physics_process(false)
	var left := skeleton.find_bone("L_wrist_04")
	var right := skeleton.find_bone("R_wrist_028")
	var upper := skeleton.find_bone("L_arm_02")
	var fore := skeleton.find_bone("L_elbow_03")
	_assert(mini(mini(left, right), mini(upper, fore)) >= 0, "%s retains its native two-arm rig" % weapon_id)
	if mini(mini(left, right), mini(upper, fore)) < 0:
		parent.queue_free()
		await process_frame
		return
	var rests: Array[Transform3D] = []
	var scales: Array[Vector3] = []
	for bone in skeleton.get_bone_count():
		rests.append(skeleton.get_bone_rest(bone))
		scales.append(skeleton.get_bone_pose_scale(bone))
	var upper_length := skeleton.get_bone_global_pose(upper).origin.distance_to(skeleton.get_bone_global_pose(fore).origin)
	var fore_length := skeleton.get_bone_global_pose(fore).origin.distance_to(skeleton.get_bone_global_pose(left).origin)
	var gun_home := gun.transform
	# Completion and cancellation restore the controller's authored seated pose,
	# rather than the idle bone-follow pose's world-space rounding residue.
	var magazine_home: Transform3D = weapon._mag_home_transform
	var right_home := gun.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(right)
	var configured_mag = weapon.get("mag_state_property")
	var mag_key: StringName = configured_mag if configured_mag != null else weapon_id + "_mag"
	var reserve_key: StringName = weapon.reserve_state_property
	if reserve_key == &"":
		reserve_key = weapon_id + "_reserve"
	var starting_mag: int = maxi(1, weapon.weapon_data.mag_size / 2)
	var starting_reserve: int = weapon.weapon_data.mag_size * 2
	state.set(mag_key, starting_mag)
	state.set(reserve_key, starting_reserve)
	var starts := int(_started.get(weapon_id, 0))
	var finishes := int(_finished.get(weapon_id, 0))
	weapon._start_reload()
	weapon._start_reload()
	_assert(int(_started.get(weapon_id, 0)) == starts + 1 and weapon._is_reloading, "%s gates duplicate reload requests" % weapon_id)
	var duration: float = weapon.weapon_data.reload_time
	var maximum_pull := 0.0
	var maximum_cant := 0.0
	var maximum_lift := 0.0
	var exchanged := false
	var poses_valid := true
	var bones_valid := true
	var contact_valid := true
	var grip_valid := true
	var presentation_valid := true
	for step in 61:
		var progress := float(step) / 60.0
		animation.seek(progress * duration, true)
		weapon._process(0.0)
		var seated_world: Vector3 = magazine.get_parent().global_transform * magazine_home.origin
		var pull: float = (magazine.global_position - seated_world).dot(gun.global_basis.orthonormalized() * direction.normalized())
		maximum_pull = maxf(maximum_pull, pull)
		exchanged = exchanged or not magazine.visible
		var cant := gun_home.basis.get_rotation_quaternion().angle_to(gun.basis.get_rotation_quaternion())
		var native_profile: Dictionary = GameConfig.BLACK_LONG_GUN_PROFILES[weapon_id]
		var gun_weight := smoothstep(0.0, float(profile.contact_phase), progress) * (1.0 - smoothstep(float(profile.seat_phase), 1.0, progress))
		var display_depth := Vector3(0, 0, -float(native_profile.reload_depth) * gun_weight)
		var body_lift := gun.position - gun_home.origin - display_depth
		var lift := body_lift.length()
		presentation_valid = presentation_valid and body_lift.distance_to(gun_home.basis * (native_profile.reload_lift as Vector3) * gun_weight) < 0.001
		maximum_cant = maxf(maximum_cant, cant)
		maximum_lift = maxf(maximum_lift, lift)
		poses_valid = poses_valid and gun.transform.is_finite() and cant <= deg_to_rad(30.0) and lift <= 0.15 and magazine.global_transform.is_finite()
		var right_current := gun.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(right)
		grip_valid = grip_valid and right_current.origin.distance_to(right_home.origin) < 0.001 and absf(right_current.basis.get_rotation_quaternion().dot(right_home.basis.get_rotation_quaternion())) > 0.9999
		if progress >= float(profile.contact_phase) and progress <= float(profile.seat_phase):
			var target: Vector3 = magazine.global_position + gun.global_basis.orthonormalized() * (profile.grip_offset as Vector3)
			var palm := HandSkin.palm_world(weapon._arms_node, skeleton, "L")
			contact_valid = contact_valid and palm.distance_to(target) < 0.003
		bones_valid = bones_valid and absf(skeleton.get_bone_global_pose(upper).origin.distance_to(skeleton.get_bone_global_pose(fore).origin) - upper_length) < 0.001
		bones_valid = bones_valid and absf(skeleton.get_bone_global_pose(fore).origin.distance_to(skeleton.get_bone_global_pose(left).origin) - fore_length) < 0.001
		for bone in skeleton.get_bone_count():
			bones_valid = bones_valid and skeleton.get_bone_rest(bone).is_equal_approx(rests[bone]) and skeleton.get_bone_pose_scale(bone).is_equal_approx(scales[bone]) and skeleton.get_bone_global_pose(bone).is_finite()
	_assert(poses_valid and grip_valid and maximum_cant >= deg_to_rad(8.0) and maximum_lift >= 0.015, "%s translated/rotated parent coordinates bounded gun movement with the native right wrist on the grip" % weapon_id)
	_assert(presentation_valid, "%s translated/rotated parent preserves the declared display-depth axis and phase within 1mm" % weapon_id)
	_assert(contact_valid, "%s actual left palm contacts its real magazine within 3mm throughout pull and insertion" % weapon_id)
	_assert(bones_valid, "%s preserves all bone rests/scales, both left-arm lengths and the wrist seam at 61 phases" % weapon_id)
	_assert(maximum_pull >= float(profile.extraction_distance) * 0.95, "%s physically extracts its real magazine clear of the well" % weapon_id)
	_assert(exchanged and maximum_pull >= float(profile.extraction_distance) + 0.15, "%s moves the old magazine away and hides it during exchange" % weapon_id)
	await create_timer(duration + 0.05).timeout
	_assert(int(_finished.get(weapon_id, 0)) == finishes + 1 and not weapon._is_reloading and state.get(mag_key) == weapon.weapon_data.mag_size and state.get(reserve_key) == starting_reserve - (weapon.weapon_data.mag_size - starting_mag), "%s retains timed completion and shared reserve arithmetic" % weapon_id)
	_assert(magazine.transform.is_equal_approx(magazine_home) and magazine.visible, "%s seats its real magazine at the original transform" % weapon_id)
	weapon._process(0.0)
	_assert(magazine.position.distance_to(magazine_home.origin) < 0.001 and magazine.visible, "%s returns to seated idle within 1mm after the completion callback" % weapon_id)
	state.set(mag_key, starting_mag)
	var reserve_after: int = state.get(reserve_key)
	weapon._start_reload()
	animation.seek(duration * 0.45, true)
	weapon._process(1.0 / 60.0)
	state.current_weapon = &"pistol"
	root.get_node("Events").weapon_switched.emit(&"pistol")
	_assert(not weapon._is_reloading and magazine.transform.is_equal_approx(magazine_home) and magazine.visible, "%s switch cancels the visible reload and restores actual geometry" % weapon_id)
	weapon._process(0.0)
	_assert(magazine.position.distance_to(magazine_home.origin) < 0.001 and magazine.visible, "%s remains seated within 1mm when idle resumes after cancellation" % weapon_id)
	await create_timer(duration + 0.05).timeout
	_assert(int(_finished.get(weapon_id, 0)) == finishes + 1 and state.get(mag_key) == starting_mag and state.get(reserve_key) == reserve_after, "%s cancelled timer cannot duplicate ammunition later" % weapon_id)
	parent.queue_free()
	await process_frame


func _on_started(weapon_id: StringName) -> void:
	_started[weapon_id] = int(_started.get(weapon_id, 0)) + 1


func _on_finished(weapon_id: StringName) -> void:
	_finished[weapon_id] = int(_finished.get(weapon_id, 0)) + 1


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
