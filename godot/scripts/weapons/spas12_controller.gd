extends LongGunController

var _pump_left: float = 0.0
var _reload_progress: float = 0.0
var _shell: MeshInstance3D
var _pump_sleeve: Node3D
var _pump_home := Vector3.ZERO
var _shell_basis := Basis.IDENTITY


func _ready() -> void:
	(get_node(weapon_node_path) as Node3D).position = GameConfig.SPAS12_MODEL_POSITION
	super()
	# 上游的Action_sleeve_LOD0是空定位节点；可见泵套是独立静态Object_21。
	_pump_sleeve = _weapon_node.find_child("Object_21", true, false) as MeshInstance3D
	if _pump_sleeve != null:
		_pump_home = _pump_sleeve.position
	else:
		push_error("SPAS-12未找到实际可见泵套")
	_shell = get_node_or_null("ViewModel/LoadingShell") as MeshInstance3D
	if _shell != null:
		_shell_basis = _shell.basis
		_shell.visible = false


func _pose_spas_right_arm_ads() -> void:
	var uparm := _find_bone_by_prefix("UpArm_R")
	var fore := _find_bone_by_prefix("Forearm_R")
	var ctrl := _find_bone_by_prefix("IK_Hand_Cntrl_R")
	var hand := _find_bone_by_prefix("Hand_R")
	if uparm < 0 or fore < 0 or ctrl < 0 or hand < 0:
		return
	var up_g := _arms_skeleton.get_bone_global_pose(uparm)
	var fore_g := _arms_skeleton.get_bone_global_pose(fore)
	var hand_g := _arms_skeleton.get_bone_global_pose(hand)
	var upper_len := up_g.origin.distance_to(fore_g.origin)
	var fore_len := fore_g.origin.distance_to(hand_g.origin)
	var to_skel := _arms_skeleton.global_transform.affine_inverse() * _view_model.global_transform
	var wrist_t := to_skel * GameConfig.SPAS12_RIGHT_WRIST_ADS
	var pole_t := wrist_t + to_skel.basis * GameConfig.SPAS12_RIGHT_ELBOW_ADS
	var shoulder_t := wrist_t + to_skel.basis * (GameConfig.LONG_GUN_SHOULDER_DIRECTION.normalized() * (upper_len + fore_len) * 0.94)
	var d := wrist_t - shoulder_t
	var dist := clampf(d.length(), absf(upper_len - fore_len) + 0.001, upper_len + fore_len - 0.001)
	d = d.normalized()
	var a := (upper_len * upper_len - fore_len * fore_len + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(0.0, upper_len * upper_len - a * a))
	var pole_off := pole_t - shoulder_t
	pole_off -= d * pole_off.dot(d)
	pole_off /= maxf(pole_off.length(), 0.0001)
	var elbow_t := shoulder_t + d * a + pole_off * h
	_arms_skeleton.set_bone_global_pose(uparm, Transform3D(up_g.basis, shoulder_t))
	_aim_bone_y_at(uparm, elbow_t)
	_aim_bone_y_at(fore, wrist_t)
	fore_g = _arms_skeleton.get_bone_global_pose(fore)
	var wrist_end := fore_g.origin + fore_g.basis.y * fore_len
	var ctrl_g := _arms_skeleton.get_bone_global_pose(ctrl)
	_arms_skeleton.set_bone_global_pose(ctrl, Transform3D(ctrl_g.basis, wrist_end))
	var finger_dir := to_skel.basis * Vector3.FORWARD
	var palm_rot := Quaternion(hand_g.basis.y, finger_dir.normalized())
	_arms_skeleton.set_bone_global_pose(hand, Transform3D(Basis(palm_rot) * hand_g.basis, wrist_end))


func _process(delta: float) -> void:
	super._process(delta)
	if _native_arms == null and GameState.is_aiming and _arms_skeleton != null:
		_pose_spas_right_arm_ads()
	var was_pumping := _pump_left > 0.0
	_pump_left = maxf(0.0, _pump_left - delta)
	if was_pumping and _pump_left <= 0.0 \
			and ChamberFeed.load_chamber(weapon_data.weapon_id, weapon_data.weapon_id + "_mag"):
		Events.ammo_changed.emit(weapon_data.weapon_id, GameState.get(weapon_data.weapon_id + "_mag"), GameState.get(_reserve_key))
	var phase := 1.0 - _pump_left / GameConfig.SPAS12_PUMP_TIME if _pump_left > 0.0 else 0.0
	var pump_pull := sin(phase * PI) * GameConfig.SPAS12_PUMP_DISTANCE
	if _pump_sleeve != null:
		var world_pull := _weapon_node.global_basis * Vector3(0, 0, pump_pull)
		_pump_sleeve.position = _pump_home + _pump_sleeve.get_parent().global_basis.inverse() * world_pull
	if not _is_reloading:
		if _native_arms != null:
			_pose_native_spas(pump_pull)
		return
	_reload_progress += delta / weapon_data.reload_time
	if _native_arms != null:
		_pose_native_spas(pump_pull)
	elif _shell != null:
		var travel := clampf(_reload_progress, 0.0, 1.0)
		_shell.position = Vector3(-0.16, -0.18, 0.08).lerp(Vector3(-0.055, -0.055, 0.08), travel)
		_shell.visible = travel > 0.12 and travel < 0.92
	if _reload_progress < 1.0:
		return
	_reload_progress -= 1.0
	var mag := int(GameState.get(weapon_data.weapon_id + "_mag")) + 1
	var reserve := int(GameState.get(_reserve_key)) - 1
	GameState.set(weapon_data.weapon_id + "_mag", mag)
	GameState.set(_reserve_key, reserve)
	Events.ammo_changed.emit(weapon_data.weapon_id, mag, reserve)
	if mag >= weapon_data.mag_size or reserve <= 0:
		Events.weapon_reloaded.emit(weapon_data.weapon_id)
	elif _native_arms != null:
		_native_arms.begin_reload(weapon_data.reload_time)


func _pose_native_spas(pump_pull: float) -> void:
	var profile: Dictionary = _native_arms._profile
	var support: Vector3 = (profile.support_grip_hip as Vector3).lerp(profile.support_grip_ads as Vector3, _aim_weight)
	var hip_offset := _pose_extra.basis * Vector3(0, 0, float(profile.hip_rearward) * (1.0 - _aim_weight))
	if _is_reloading:
		var progress := clampf(_reload_progress, 0.0, 1.0)
		var lift := sin(progress * PI)
		_weapon_node.transform = _pose_extra * _weapon_home * Transform3D(
			Basis.from_euler((profile.reload_cant as Vector3) * lift), GameConfig.SPAS12_RELOAD_LIFT * lift)
		_weapon_node.position += hip_offset * (1.0 - lift)
		_arms_animation.seek(progress * weapon_data.reload_time, true)
		_native_arms.pose_hold(_aim_weight)
		var retrieve: float = GameConfig.SPAS12_SHELL_RETRIEVE_PHASE
		var insert: float = GameConfig.SPAS12_SHELL_INSERT_PHASE
		var travel := smoothstep(retrieve, insert, progress)
		var shell_point: Vector3 = GameConfig.SPAS12_SHELL_START.lerp(GameConfig.SPAS12_SHELL_PORT, travel)
		if _shell != null:
			_shell.global_transform = Transform3D(_weapon_node.global_basis * _shell_basis, _weapon_node.to_global(shell_point))
			_shell.visible = progress >= retrieve and progress < insert
		var carry: Vector3 = shell_point + GameConfig.SPAS12_SHELL_HAND_OFFSET
		var reach := smoothstep(0.0, retrieve, progress)
		if progress >= insert:
			reach = 1.0 - smoothstep(insert, 1.0, progress)
		_native_arms.pose_left_grip(_weapon_node.to_global(support.lerp(carry, reach)), _native_arms.support_basis_world())
	else:
		# 从保存姿态重建旧腰射取景，双掌在显示偏移后重新贴握点。
		_weapon_node.transform = _pose_extra * _weapon_home
		_weapon_node.position += hip_offset
		_native_arms.pose_hold(_aim_weight)
		_native_arms.pose_left_grip(_weapon_node.to_global(support + Vector3(0, 0, pump_pull)), _native_arms.support_basis_world())
	_native_arms.update_bounds()


func _fire() -> bool:
	if _pump_left > 0.0:
		return false
	if not _is_reloading and not ChamberFeed.is_chambered(weapon_data.weapon_id) \
			and int(GameState.get(weapon_data.weapon_id + "_mag")) > 0:
		_pump_left = GameConfig.SPAS12_PUMP_TIME
		return false
	var fired := super._fire()
	if not fired:
		return false
	_pump_left = GameConfig.SPAS12_PUMP_TIME
	return true


func _spread_for_distance(distance: float) -> float:
	if distance <= GameConfig.SPAS12_SPREAD_START:
		return 0.0
	return _current_spread()


func _start_reload() -> void:
	if _is_reloading or int(GameState.get(_reserve_key)) <= 0:
		return
	if int(GameState.get(weapon_data.weapon_id + "_mag")) >= weapon_data.mag_size:
		return
	# 插壳期间不延续上一枪的泵动；空膛装填完成后重新起泵上膛。
	_pump_left = 0.0
	_reload_generation += 1
	_reload_progress = 0.0
	Events.weapon_reload_started.emit(weapon_data.weapon_id)


func _play_reload_anim() -> void:
	_reload_progress = 0.0
	if _native_arms != null:
		_native_arms.begin_reload(weapon_data.reload_time)
	if _shell != null:
		_shell.visible = false


func _reload_cant_counter() -> float:
	return sin(clampf(_reload_progress, 0.0, 1.0) * PI) * GameConfig.SPAS12_RELOAD_CANT


func _on_weapon_reloaded(weapon_id: StringName) -> void:
	if weapon_id != weapon_data.weapon_id:
		return
	_reset_reload_visuals()
	_is_reloading = false
	_reload_progress = 0.0
	if not ChamberFeed.is_chambered(weapon_id) and int(GameState.get(weapon_id + "_mag")) > 0:
		_pump_left = GameConfig.SPAS12_PUMP_TIME
	if _shell != null:
		_shell.visible = false


func _on_weapon_switched(weapon_id: StringName) -> void:
	super._on_weapon_switched(weapon_id)
	_pump_left = 0.0
	if _pump_sleeve != null:
		_pump_sleeve.position = _pump_home
	_reload_progress = 0.0
	if _shell != null:
		_shell.visible = false
