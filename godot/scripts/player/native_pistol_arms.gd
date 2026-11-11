## DJMaesen 原生蒙皮及动作适配；只移动容器和动作挂点，不改骨架 rest/scale。
extends RefCounted

const SkinBounds = preload("res://scripts/player/viewmodel_skin_bounds.gd")

var skeleton: Skeleton3D
var animation: AnimationPlayer
var lock_idle_aim := false
var _arms: Node3D
var _weapon: Node3D
var _magazine: Node3D
var _weapon_motion: Node3D
var _magazine_motion: Node3D
var _slide_motion: Node3D
var _slide: Node3D
var _slide_home := Transform3D.IDENTITY
var _slide_attachment := Transform3D.IDENTITY
var _weapon_attachment := Transform3D.IDENTITY
var _magazine_attachment := Transform3D.IDENTITY
var _weapon_home := Transform3D.IDENTITY
var _magazine_home := Transform3D.IDENTITY
var _profile: Dictionary
var _skin_bounds = SkinBounds.new()
var _clip := &"idle"
var _reload_speed := 1.0
var _meshes: Array[MeshInstance3D] = []
var _right_upper := -1
var _right_fore := -1
var _right_wrist := -1
var _right_hold := Transform3D.IDENTITY
var _right_upper_length := 0.0
var _right_fore_length := 0.0
var _left_upper := -1
var _left_fore := -1
var _left_wrist := -1
var _left_upper_length := 0.0
var _left_fore_length := 0.0
var _bone_positions: Dictionary = {}
var _trigger_finger := -1
var _trigger_finger_pose := Quaternion.IDENTITY


func configure(arms: Node3D, weapon: Node3D, magazine: Node3D, profile: Dictionary) -> bool:
	if arms == null or weapon == null or magazine == null or not profile.has("weapon_anchor") or not profile.has("source_rotation"):
		return false
	_arms = arms
	_weapon = weapon
	_magazine = magazine
	_profile = profile
	var skeletons := arms.find_children("*", "Skeleton3D", true, false)
	var players := arms.find_children("*", "AnimationPlayer", true, false)
	_weapon_motion = arms.find_child("WeaponMotion", true, false) as Node3D
	_magazine_motion = arms.find_child("MagazineMotion", true, false) as Node3D
	if skeletons.size() != 1 or players.size() != 1 or _weapon_motion == null or _magazine_motion == null:
		return false
	skeleton = skeletons[0] as Skeleton3D
	animation = players[0] as AnimationPlayer
	if skeleton.get_bone_count() != 60 or not animation.has_animation(&"idle") or not animation.has_animation(&"reload"):
		return false
	# AnimationPlayer 内部tick独立于普通process开关；动作只能由update手动advance一次。
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation.set_process(false)
	animation.set_physics_process(false)
	play_idle()
	_weapon_home = weapon.transform
	_magazine_home = magazine.transform
	var chain := arms.global_transform.affine_inverse() * _weapon_motion.global_transform
	var desired_basis := weapon.global_basis.orthonormalized() * Basis.from_euler(profile.source_rotation as Vector3)
	desired_basis = desired_basis.scaled(_weapon_motion.global_basis.get_scale() * float(profile.get("root_scale", 1.0)))
	var desired := Transform3D(desired_basis, weapon.global_transform * (profile.weapon_anchor as Vector3))
	arms.global_transform = desired * chain.affine_inverse()
	_weapon_attachment = _weapon_motion.global_transform.affine_inverse() * weapon.global_transform
	_magazine_attachment = _magazine_motion.global_transform.affine_inverse() * magazine.global_transform
	_slide = weapon.find_child("Slide", true, false) as Node3D
	_slide_motion = arms.find_child("SlideMotion", true, false) as Node3D
	if _slide != null and _slide_motion != null:
		_slide_home = _slide.transform
		_slide_attachment = _slide_motion.global_transform.affine_inverse() * _slide.global_transform
	_right_upper = skeleton.find_bone("R_arm_026")
	_right_fore = skeleton.find_bone("R_elbow_027")
	_right_wrist = skeleton.find_bone("R_wrist_028")
	if mini(_right_upper, mini(_right_fore, _right_wrist)) < 0:
		return false
	_right_hold = weapon.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(_right_wrist)
	_right_upper_length = skeleton.get_bone_global_pose(_right_upper).origin.distance_to(skeleton.get_bone_global_pose(_right_fore).origin)
	_right_fore_length = skeleton.get_bone_global_pose(_right_fore).origin.distance_to(skeleton.get_bone_global_pose(_right_wrist).origin)
	_left_upper = skeleton.find_bone("L_arm_02")
	_left_fore = skeleton.find_bone("L_elbow_03")
	_left_wrist = skeleton.find_bone("L_wrist_04")
	if mini(_left_upper, mini(_left_fore, _left_wrist)) < 0:
		return false
	_left_upper_length = skeleton.get_bone_global_pose(_left_upper).origin.distance_to(skeleton.get_bone_global_pose(_left_fore).origin)
	_left_fore_length = skeleton.get_bone_global_pose(_left_fore).origin.distance_to(skeleton.get_bone_global_pose(_left_wrist).origin)
	_trigger_finger = -1
	if profile.has("trigger_finger_curl"):
		_trigger_finger = skeleton.find_bone("R_point1_033")
		if _trigger_finger < 0:
			return false
		_trigger_finger_pose = skeleton.get_bone_pose_rotation(_trigger_finger)
	for bone in [_left_upper, _left_fore, _left_wrist, _right_upper, _right_fore, _right_wrist]:
		_bone_positions[bone] = skeleton.get_bone_pose_position(bone)
	for child in arms.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.skin != null and mesh.mesh != null:
			_meshes.append(mesh)
	update(0.0)
	return true


func play_idle() -> void:
	if animation == null:
		return
	_clip = &"idle"
	_reload_speed = 1.0
	animation.get_animation(_clip).loop_mode = Animation.LOOP_LINEAR
	animation.play(_clip)
	animation.advance(0.0)


func play_fire() -> void:
	if animation == null or _clip in [&"reload", &"reload_empty"]:
		return
	_clip = &"fire"
	_reload_speed = 1.0
	animation.play(_clip)
	animation.advance(0.0)


func play_reload(duration: float, empty: bool = false) -> void:
	if animation == null or duration <= 0.0:
		return
	_clip = &"reload_empty" if empty else &"reload"
	_reload_speed = animation.get_animation(_clip).length / duration
	animation.play(_clip)
	animation.advance(0.0)
	update(0.0)


func update(delta: float) -> void:
	if animation == null or not is_instance_valid(_weapon) or not is_instance_valid(_magazine):
		return
	# Native source mostly keys rotation; clear any previous unreachable-target
	# shoulder adjustment before sampling, so correction cannot accumulate.
	for bone: int in _bone_positions:
		skeleton.set_bone_pose_position(bone, _bone_positions[bone])
	if _trigger_finger >= 0:
		# Restore the last uncorrected sample before animation evaluation, never accumulate the curl.
		skeleton.set_bone_pose_rotation(_trigger_finger, _trigger_finger_pose)
	var hold_idle := bool(_profile.get("lock_idle", false)) or (lock_idle_aim and bool(_profile.get("lock_ads_idle", false)))
	if _clip == &"idle" and hold_idle:
		animation.seek(0.0, true)
	else:
		animation.advance(maxf(0.0, delta) * _reload_speed)
	if _clip == &"fire" and not animation.is_playing():
		play_idle()
	_weapon.global_transform = _weapon_motion.global_transform * _weapon_attachment
	_magazine.global_transform = _magazine_motion.global_transform * _magazine_attachment
	if _slide != null and _slide_motion != null:
		_slide.global_transform = _slide_motion.global_transform * _slide_attachment
	_lock_right_wrist()
	_contact_left_wrist()
	if _trigger_finger >= 0:
		_trigger_finger_pose = skeleton.get_bone_pose_rotation(_trigger_finger)
		skeleton.set_bone_pose_rotation(_trigger_finger, _trigger_finger_pose * Quaternion(Vector3.UP, float(_profile.trigger_finger_curl)))
	for mesh in _meshes:
		mesh.custom_aabb = get_skin_bounds(mesh)


func reset() -> void:
	if animation == null:
		return
	play_idle()
	_weapon.transform = _weapon_home
	_magazine.transform = _magazine_home
	_magazine.visible = true
	if _slide != null:
		_slide.transform = _slide_home


func get_skin_bounds(mesh: MeshInstance3D) -> AABB:
	return _skin_bounds.get_pose_bounds(mesh)


func _lock_right_wrist() -> void:
	# 原动画有数毫米的握柄滑动；以原长度旋转两骨链，腕点保持在当前真实枪柄。
	var target := skeleton.global_transform.affine_inverse() * _weapon.global_transform * _right_hold
	var pole := skeleton.get_bone_global_pose(_right_fore).origin - skeleton.get_bone_global_pose(_right_upper).origin
	_place_arm(_right_upper, _right_fore, _right_wrist, _right_upper_length, _right_fore_length, target, pole)


func _contact_left_wrist() -> void:
	if _clip not in [&"reload", &"reload_empty"] or not _profile.has("magazine_grip"):
		return
	var progress := animation.current_animation_position / animation.get_animation(_clip).length
	var contact: float = _profile.reload_contact_phase
	var seat: float = _profile.reload_seat_phase
	var weight := smoothstep(0.0, contact, progress) * (1.0 - smoothstep(seat, 1.0, progress))
	var source := skeleton.get_bone_global_pose(_left_wrist)
	var actual: Vector3 = skeleton.global_transform.affine_inverse() * (_magazine.global_transform * (_profile.magazine_grip as Vector3))
	var target := Transform3D(source.basis, source.origin.lerp(actual, weight))
	var pole: Vector3 = skeleton.global_transform.basis.inverse() * (_weapon.global_basis.orthonormalized() * (_profile.left_elbow_pole as Vector3))
	_place_arm(_left_upper, _left_fore, _left_wrist, _left_upper_length, _left_fore_length, target, pole)


func _place_arm(upper_bone: int, fore_bone: int, wrist_bone: int, upper_length: float, fore_length: float, target: Transform3D, pole_offset: Vector3) -> void:
	var upper := skeleton.get_bone_global_pose(upper_bone)
	var fore := skeleton.get_bone_global_pose(fore_bone)
	var wrist := skeleton.get_bone_global_pose(wrist_bone)
	var shoulder := upper.origin
	var reach := target.origin - shoulder
	var length := reach.length()
	var maximum := upper_length + fore_length
	var minimum := absf(upper_length - fore_length)
	if length >= maximum or length <= minimum:
		var corrected := clampf(length, minimum + 0.0001, maximum - 0.0001)
		shoulder = target.origin - reach.normalized() * corrected
		length = corrected
	var direction := (target.origin - shoulder).normalized()
	var along := (upper_length * upper_length - fore_length * fore_length + length * length) / (2.0 * length)
	var height := sqrt(maxf(0.0, upper_length * upper_length - along * along))
	var pole := pole_offset
	pole -= direction * pole.dot(direction)
	if pole.length_squared() < 0.000001:
		pole = direction.cross(Vector3.UP)
	var elbow := shoulder + direction * along + pole.normalized() * height
	var upper_rotation := Quaternion((fore.origin - upper.origin).normalized(), (elbow - shoulder).normalized())
	skeleton.set_bone_global_pose(upper_bone, Transform3D(Basis(upper_rotation) * upper.basis.orthonormalized(), shoulder))
	skeleton.set_bone_pose_scale(upper_bone, Vector3.ONE)
	fore = skeleton.get_bone_global_pose(fore_bone)
	wrist = skeleton.get_bone_global_pose(wrist_bone)
	var fore_rotation := Quaternion((wrist.origin - fore.origin).normalized(), (target.origin - elbow).normalized())
	skeleton.set_bone_global_pose(fore_bone, Transform3D(Basis(fore_rotation) * fore.basis.orthonormalized(), elbow))
	skeleton.set_bone_pose_scale(fore_bone, Vector3.ONE)
	skeleton.set_bone_global_pose(wrist_bone, Transform3D(target.basis.orthonormalized(), target.origin))
	skeleton.set_bone_pose_scale(wrist_bone, Vector3.ONE)
