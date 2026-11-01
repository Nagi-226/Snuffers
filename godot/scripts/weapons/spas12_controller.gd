extends LongGunController

var _pump_left: float = 0.0
var _reload_progress: float = 0.0
var _shell: MeshInstance3D
var _pump_sleeve: Node3D
var _pump_home := Vector3.ZERO


func _ready() -> void:
	super()
	for node in _weapon_node.find_children("*", "Node3D", true, false):
		if String(node.name).contains("Action_sleeve"):
			_pump_sleeve = node as Node3D
			_pump_home = _pump_sleeve.position
			break
	_shell = get_node_or_null("ViewModel/LoadingShell") as MeshInstance3D
	if _shell != null:
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
	var finger_dir := to_skel.basis * Vector3.LEFT
	var palm_rot := Quaternion(hand_g.basis.y, finger_dir.normalized())
	_arms_skeleton.set_bone_global_pose(hand, Transform3D(Basis(palm_rot) * hand_g.basis, wrist_end))


func _process(delta: float) -> void:
	super._process(delta)
	if GameState.is_aiming and _arms_skeleton != null:
		_pose_spas_right_arm_ads()
	_pump_left = maxf(0.0, _pump_left - delta)
	if _pump_sleeve != null:
		var phase := 1.0 - _pump_left / GameConfig.SPAS12_PUMP_TIME if _pump_left > 0.0 else 0.0
		var world_pull := _weapon_node.global_basis * Vector3(0, 0, sin(phase * PI) * 0.09)
		_pump_sleeve.position = _pump_home + _pump_sleeve.get_parent().global_basis.inverse() * world_pull
	if not _is_reloading:
		return
	_reload_progress += delta / weapon_data.reload_time
	if _shell != null:
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


func _fire() -> bool:
	if _pump_left > 0.0:
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
	_reload_generation += 1
	_reload_progress = 0.0
	Events.weapon_reload_started.emit(weapon_data.weapon_id)


func _play_reload_anim() -> void:
	_reload_progress = 0.0
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
	if _shell != null:
		_shell.visible = false


func _on_weapon_switched(weapon_id: StringName) -> void:
	super._on_weapon_switched(weapon_id)
	_pump_left = 0.0
	_reload_progress = 0.0
	if _shell != null:
		_shell.visible = false
