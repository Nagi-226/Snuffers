extends SceneTree

const Chamber = preload("res://tests/chamber_test_support.gd")

const HandSkin = preload("res://tests/hand_skin_probe.gd")

var _failures := 0
var _assertions := 0
var _started := 0
var _finished := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(35.0).timeout.connect(func() -> void:
		push_error("magazine contact test timed out")
		quit(1))
	var config = root.get_node("GameConfig")
	var profiles: Dictionary = config.get_script().get_script_constant_map().get("MAGAZINE_RELOAD_PROFILES", {})
	_assert(profiles.has(&"rifle"), "rifle has its approved real-magazine reload profile")
	if not profiles.has(&"rifle"):
		_finish()
		return
	var profile: Dictionary = profiles[&"rifle"]
	var state = root.get_node("GameState")
	state.reset()
	state.current_weapon = &"rifle"
	Chamber.set_total(state, &"rifle", 12)
	state.rifle_reserve = 100
	var weapon = (load("res://scenes/weapons/rifle.tscn") as PackedScene).instantiate()
	root.add_child(weapon)
	await process_frame
	weapon.set_process(false)
	weapon.set_physics_process(false)
	for frame in 24:
		weapon._process(1.0 / 60.0)
	var magazine: Node3D = weapon._magazine
	var gun: Node3D = weapon._weapon_node
	var skeleton: Skeleton3D = weapon._arms_skeleton
	var animation: AnimationPlayer = weapon._arms_animation
	_assert(magazine is MeshInstance3D or not magazine.find_children("*", "MeshInstance3D", true, false).is_empty(), "pilot controls real detachable magazine geometry")
	animation.set_process(false)
	animation.set_physics_process(false)
	var left := skeleton.find_bone("L_wrist_04")
	var right := skeleton.find_bone("R_wrist_028")
	var upper := skeleton.find_bone("L_arm_02")
	var fore := skeleton.find_bone("L_elbow_03")
	_assert(left >= 0 and right >= 0 and upper >= 0 and fore >= 0, "pilot resolves both hands and the left arm chain")
	if mini(mini(left, right), mini(upper, fore)) < 0:
		weapon.queue_free()
		_finish()
		return
	var rests: Array[Transform3D] = []
	var scales: Array[Vector3] = []
	for bone in skeleton.get_bone_count():
		rests.append(skeleton.get_bone_rest(bone))
		scales.append(skeleton.get_bone_pose_scale(bone))
	var upper_length := skeleton.get_bone_global_pose(upper).origin.distance_to(skeleton.get_bone_global_pose(fore).origin)
	var fore_length := skeleton.get_bone_global_pose(fore).origin.distance_to(skeleton.get_bone_global_pose(left).origin)
	var gun_home := gun.transform
	var magazine_home := magazine.transform
	var right_home := _hand_in_gun(gun, skeleton, right)
	var events = root.get_node("Events")
	events.weapon_reload_started.connect(_on_started)
	events.weapon_reloaded.connect(_on_finished)
	weapon._start_reload()
	weapon._start_reload()
	_assert(_started == 1 and weapon._is_reloading, "actual reload event starts once and blocks duplicate requests")
	var duration: float = weapon.weapon_data.reload_time
	var direction: Vector3 = profile.extraction_direction
	_assert(direction.normalized().dot(Vector3.DOWN) > 0.99, "rifle extraction follows the real downward magazine-well axis")
	var stages := [float(profile.contact_phase), float(profile.pull_phase), float(profile.new_phase), float(profile.seat_phase)]
	var maximum_pull := 0.0
	var maximum_cant := 0.0
	var maximum_lift := 0.0
	var exchanged := false
	for step in 61:
		var progress := float(step) / 60.0
		animation.seek(progress * duration, true)
		weapon._process(0.0)
		var displacement: Vector3 = gun.global_transform.affine_inverse() * magazine.global_position - gun.global_transform.affine_inverse() * (magazine.get_parent().global_transform * magazine_home.origin)
		var pull: float = displacement.dot(direction.normalized())
		maximum_pull = maxf(maximum_pull, pull)
		exchanged = exchanged or not magazine.visible
		var cant := gun_home.basis.get_rotation_quaternion().angle_to(gun.basis.get_rotation_quaternion())
		var native_profile: Dictionary = GameConfig.BLACK_LONG_GUN_PROFILES[&"rifle"]
		var gun_weight := smoothstep(0.0, stages[0], progress) * (1.0 - smoothstep(stages[3], 1.0, progress))
		var display_depth := Vector3(0, 0, -float(native_profile.reload_depth) * gun_weight)
		var body_lift := gun.position - gun_home.origin - display_depth
		var lift := body_lift.length()
		maximum_cant = maxf(maximum_cant, cant)
		maximum_lift = maxf(maximum_lift, lift)
		_assert(gun.transform.is_finite() and cant <= deg_to_rad(30.0) and lift <= 0.15, "reload phase %.3f bounds the coordinated gun cant and lift" % progress)
		_assert(body_lift.distance_to(gun_home.basis * (native_profile.reload_lift as Vector3) * gun_weight) < 0.001, "reload phase %.3f separately validates the declared parent-Z display depth" % progress)
		var right_current := _hand_in_gun(gun, skeleton, right)
		_assert(right_current.origin.distance_to(right_home.origin) < 0.001 and absf(right_current.basis.get_rotation_quaternion().dot(right_home.basis.get_rotation_quaternion())) > 0.9999, "reload phase %.3f keeps the right wrist position and rotation on the grip" % progress)
		if progress >= stages[0] and progress <= stages[3]:
			var expected := magazine.global_position + gun.global_basis.orthonormalized() * (profile.grip_offset as Vector3)
			var palm := HandSkin.palm_world(weapon._arms_node, skeleton, "L")
			_assert(palm.distance_to(expected) < 0.003, "reload phase %.3f keeps the actual left palm at the magazine grab point" % progress)
		_assert(absf(skeleton.get_bone_global_pose(upper).origin.distance_to(skeleton.get_bone_global_pose(fore).origin) - upper_length) < 0.001, "reload phase %.3f preserves upper-arm length" % progress)
		_assert(absf(skeleton.get_bone_global_pose(fore).origin.distance_to(skeleton.get_bone_global_pose(left).origin) - fore_length) < 0.001, "reload phase %.3f preserves forearm length and the wrist seam" % progress)
		var bones_valid := true
		for bone in skeleton.get_bone_count():
			bones_valid = bones_valid and skeleton.get_bone_rest(bone).is_equal_approx(rests[bone]) and skeleton.get_bone_pose_scale(bone).is_equal_approx(scales[bone]) and skeleton.get_bone_global_pose(bone).is_finite()
		_assert(bones_valid and magazine.global_transform.is_finite(), "reload phase %.3f preserves bone rests/scales and finite transforms" % progress)
	_assert(maximum_pull >= float(profile.extraction_distance) * 0.85, "real magazine travels clearly outside its well")
	_assert(maximum_cant >= deg_to_rad(8.0) and maximum_lift >= 0.015, "rifle visibly cants and lifts with magazine exchange")
	_assert(exchanged and maximum_pull >= float(profile.extraction_distance) + 0.15, "old magazine leaves the working area and hides during the incoming-magazine exchange")
	await create_timer(duration + 0.1).timeout
	weapon._process(0.0)
	_assert(_finished == 1 and not weapon._is_reloading and Chamber.total(state, &"rifle") == 61 and state.rifle_mag == 60 and Chamber.chamber(state, &"rifle") == 1 and state.rifle_reserve == 51, "existing timed tactical reload completion and ammunition math remain compatible")
	_assert(magazine.transform.is_equal_approx(magazine_home) and magazine.visible, "real magazine seats at its original transform after reload")
	Chamber.set_total(state, &"rifle", 12)
	weapon._start_reload()
	animation.seek(duration * 0.45, true)
	weapon._process(1.0 / 60.0)
	state.current_weapon = &"pistol"
	events.weapon_switched.emit(&"pistol")
	weapon._process(0.0)
	_assert(not weapon._is_reloading and magazine.transform.is_equal_approx(magazine_home) and magazine.visible, "switching weapons cancels the visible reload and restores the magazine")
	await create_timer(duration + 0.1).timeout
	_assert(_finished == 1 and Chamber.total(state, &"rifle") == 12 and state.rifle_reserve == 51, "cancelled reload does not complete later or change ammunition")
	events.weapon_reload_started.disconnect(_on_started)
	events.weapon_reloaded.disconnect(_on_finished)
	weapon.queue_free()
	await process_frame
	_finish()


func _hand_in_gun(gun: Node3D, skeleton: Skeleton3D, bone: int) -> Transform3D:
	return gun.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(bone)


func _on_started(weapon_id: StringName) -> void:
	if weapon_id == &"rifle":
		_started += 1


func _on_finished(weapon_id: StringName) -> void:
	if weapon_id == &"rifle":
		_finished += 1


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _finish() -> void:
	print("RELOAD_MAGAZINE_CONTACT assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)
