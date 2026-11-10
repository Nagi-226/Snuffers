## Native Cransh rig: move the real magazine, then close its existing left arm chain.
## Bone rests, skin binds and bone scales stay authored; gameplay timing stays in the controller.
extends RefCounted

var _skeleton: Skeleton3D
var _arms: Node3D
var _gun: Node3D
var _magazine: Node3D
var _profile: Dictionary
var _positions: Array[Vector3] = []
var _rotations: Array[Quaternion] = []
var _scales: Array[Vector3] = []
var _gun_home := Transform3D.IDENTITY
var _arms_home := Transform3D.IDENTITY
var _magazine_home := Transform3D.IDENTITY
var _wrist_home := Transform3D.IDENTITY
var _shoulder_home := Vector3.ZERO
var _upper := -1
var _fore := -1
var _hand := -1
var _control := -1
var _upper_length := 0.0
var _fore_length := 0.0
var active := false
var _native_arms: RefCounted
var _native_profile: Dictionary


func setup(skeleton: Skeleton3D, arms: Node3D, gun: Node3D, magazine: Node3D, profile: Dictionary) -> void:
	_skeleton = skeleton
	_arms = arms
	_gun = gun
	_magazine = magazine
	_profile = profile
	_native_arms = null
	_native_profile = {}
	_upper = _find_bone("UpArm_L")
	_fore = _find_bone("Forearm_L")
	_hand = _find_bone("Hand_L")
	_control = _find_bone("IK_Hand_Cntrl_L")


func setup_native(skeleton: Skeleton3D, arms: Node3D, gun: Node3D, magazine: Node3D, profile: Dictionary, native_arms: RefCounted) -> void:
	setup(skeleton, arms, gun, magazine, profile)
	_native_arms = native_arms
	_native_profile = native_arms._profile


func begin() -> void:
	if _native_arms != null:
		_gun_home = _gun.transform
		_arms_home = _arms.transform
		_magazine_home = _magazine.transform
		active = true
		return
	if _upper < 0 or _fore < 0 or _hand < 0 or _control < 0:
		return
	_positions.clear()
	_rotations.clear()
	_scales.clear()
	for bone in _skeleton.get_bone_count():
		_positions.append(_skeleton.get_bone_pose_position(bone))
		_rotations.append(_skeleton.get_bone_pose_rotation(bone))
		_scales.append(_skeleton.get_bone_pose_scale(bone))
	_gun_home = _gun.transform
	_arms_home = _arms.transform
	_magazine_home = _magazine.transform
	_wrist_home = _skeleton.get_bone_global_pose(_hand)
	_shoulder_home = _skeleton.get_bone_global_pose(_upper).origin
	_upper_length = _shoulder_home.distance_to(_skeleton.get_bone_global_pose(_fore).origin)
	_fore_length = _skeleton.get_bone_global_pose(_fore).origin.distance_to(_wrist_home.origin)
	active = _upper_length > 0.0 and _fore_length > 0.0


func update(progress: float) -> void:
	if not active:
		return
	if _native_arms != null:
		_update_native(progress)
		return
	_restore_pose()
	_gun.transform = _gun_home
	_arms.transform = _arms_home
	var contact: float = _profile.contact_phase
	var pull: float = _profile.pull_phase
	var new_phase: float = _profile.new_phase
	var seat: float = _profile.seat_phase
	var amount := 0.0
	var exchange := 0.0
	var visible_magazine := true
	if progress > contact and progress < pull:
		amount = _smooth((progress - contact) / (pull - contact))
	elif progress >= pull and progress <= new_phase:
		amount = 1.0
		var exchange_progress := (progress - pull) / (new_phase - pull)
		exchange = _smooth(1.0 - absf(exchange_progress * 2.0 - 1.0))
		visible_magazine = exchange_progress < 1.0 / 3.0 or exchange_progress > 2.0 / 3.0
	elif progress > new_phase and progress < seat:
		amount = 1.0 - _smooth((progress - new_phase) / (seat - new_phase))
	var direction: Vector3 = _profile.extraction_direction
	var distance: float = _profile.extraction_distance
	_magazine.transform = _magazine_home
	_magazine.global_position += _gun.global_basis.orthonormalized() * direction.normalized() * (distance * amount + GameConfig.MAGAZINE_RELOAD_EXCHANGE_DISTANCE * exchange)
	# At the off-screen exchange hold, reuse the same mesh as the incoming magazine.
	# Never expose an authored one-frame teleport, duplicate magazine or ghost marker.
	_magazine.visible = visible_magazine
	var grip: Vector3 = _profile.grip_offset
	var target_world := _magazine.global_position + _gun.global_basis.orthonormalized() * grip
	var target := _skeleton.global_transform.affine_inverse() * target_world
	var reach_weight := 1.0
	if progress < contact:
		reach_weight = _smooth(progress / contact)
	elif progress > seat:
		reach_weight = 1.0 - _smooth((progress - seat) / (1.0 - seat))
	target = _wrist_home.origin.lerp(target, reach_weight)
	_solve_left_arm(target)


func reset() -> void:
	if not active:
		return
	if _native_arms != null:
		_gun.transform = _gun_home
		_magazine.transform = _magazine_home
		_magazine.visible = true
		_native_arms.reset()
		active = false
		return
	_restore_pose()
	_gun.transform = _gun_home
	_arms.transform = _arms_home
	_magazine.transform = _magazine_home
	_magazine.visible = true
	active = false


func _update_native(progress: float) -> void:
	progress = clampf(progress, 0.0, 1.0)
	var contact: float = _profile.contact_phase
	var pull: float = _profile.pull_phase
	var new_phase: float = _profile.new_phase
	var seat: float = _profile.seat_phase
	var gun_weight := _smooth(progress / contact) * (1.0 - _smooth((progress - seat) / (1.0 - seat)))
	_gun.transform = _gun_home * Transform3D(Basis.from_euler((_native_profile.reload_cant as Vector3) * gun_weight), (_native_profile.reload_lift as Vector3) * gun_weight)
	_native_arms.pose_hold(0.0)
	var amount := 0.0
	var exchange := 0.0
	var visible_magazine := true
	if progress > contact and progress < pull:
		amount = _smooth((progress - contact) / (pull - contact))
	elif progress >= pull and progress <= new_phase:
		amount = 1.0
		var exchange_progress := (progress - pull) / (new_phase - pull)
		exchange = _smooth(1.0 - absf(exchange_progress * 2.0 - 1.0))
		visible_magazine = exchange_progress < 1.0 / 3.0 or exchange_progress > 2.0 / 3.0
	elif progress > new_phase and progress < seat:
		amount = 1.0 - _smooth((progress - new_phase) / (seat - new_phase))
	_magazine.transform = _magazine_home
	_magazine.global_position += _gun.global_basis.orthonormalized() * (_profile.extraction_direction as Vector3).normalized() * (float(_profile.extraction_distance) * amount + GameConfig.MAGAZINE_RELOAD_EXCHANGE_DISTANCE * exchange)
	_magazine.visible = visible_magazine
	var support := _gun.global_transform * (_native_profile.support_grip_hip as Vector3)
	var grasp := _magazine.global_position + _gun.global_basis.orthonormalized() * (_profile.grip_offset as Vector3)
	var reach := _smooth(progress / contact) * (1.0 - _smooth((progress - seat) / (1.0 - seat)))
	_native_arms.pose_left_grip(support.lerp(grasp, reach), _native_arms.support_basis_world())
	_native_arms.update_bounds()


func _restore_pose() -> void:
	for bone in _skeleton.get_bone_count():
		_skeleton.set_bone_pose_position(bone, _positions[bone])
		_skeleton.set_bone_pose_rotation(bone, _rotations[bone])
		_skeleton.set_bone_pose_scale(bone, _scales[bone])


func _solve_left_arm(target: Vector3) -> void:
	var shoulder := _shoulder_home
	var delta := target - shoulder
	var maximum := _upper_length + _fore_length - 0.001
	var minimum := absf(_upper_length - _fore_length) + 0.001
	# The existing rig's upper arm is independently positioned by the hold pose.
	# Move that anchor only when the target falls outside its physical arm reach.
	if delta.length() > maximum:
		shoulder = target - delta.normalized() * maximum
	elif delta.length() < minimum:
		shoulder = target - delta.normalized() * minimum
	delta = target - shoulder
	var distance := delta.length()
	var axis := delta.normalized()
	var along := (_upper_length * _upper_length - _fore_length * _fore_length + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, _upper_length * _upper_length - along * along))
	var gun_to_skeleton: Basis = _skeleton.global_basis.inverse() * _gun.global_basis.orthonormalized()
	var pole: Vector3 = gun_to_skeleton * GameConfig.MAGAZINE_RELOAD_ELBOW_POLE
	pole -= axis * pole.dot(axis)
	if pole.length_squared() <= 0.000001:
		pole = axis.cross(Vector3.RIGHT)
	var elbow := shoulder + axis * along + pole.normalized() * height
	var upper_pose := _skeleton.get_bone_global_pose(_upper)
	_skeleton.set_bone_global_pose(_upper, Transform3D(upper_pose.basis, shoulder))
	_aim_bone_y(_upper, elbow)
	_aim_bone_y(_fore, target)
	var control_pose := _skeleton.get_bone_global_pose(_control)
	_skeleton.set_bone_global_pose(_control, Transform3D(control_pose.basis, target))
	var hand_pose := _skeleton.get_bone_global_pose(_hand)
	_skeleton.set_bone_global_pose(_hand, Transform3D(_wrist_home.basis, hand_pose.origin))


func _aim_bone_y(bone: int, target: Vector3) -> void:
	var pose := _skeleton.get_bone_global_pose(bone)
	var direction := (target - pose.origin).normalized()
	var turn := Quaternion(pose.basis.y.normalized(), direction)
	_skeleton.set_bone_global_pose(bone, Transform3D(Basis(turn) * pose.basis, pose.origin))


func _find_bone(prefix: String) -> int:
	if _skeleton == null:
		return -1
	for bone in _skeleton.get_bone_count():
		if _skeleton.get_bone_name(bone).begins_with(prefix):
			return bone
	return -1


func _smooth(value: float) -> float:
	value = clampf(value, 0.0, 1.0)
	return value * value * (3.0 - 2.0 * value)
