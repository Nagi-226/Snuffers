## 原生60骨黑臂：真实掌面贴握柄/护木，装填部件与枪身由控制器驱动。
## 保留源rest、蒙皮和骨长；只摆位原容器并解原肩肘腕链。
extends RefCounted

const SkinBounds = preload("res://scripts/player/viewmodel_skin_bounds.gd")

var skeleton: Skeleton3D
var animation: AnimationPlayer
var _arms: Node3D
var _gun: Node3D
var _profile: Dictionary
var _arms_in_gun := Transform3D.IDENTITY
var _positions: Array[Vector3] = []
var _rotations: Array[Quaternion] = []
var _scales: Array[Vector3] = []
var _meshes: Array[MeshInstance3D] = []
var _palms: Array = [[], []]
var _palm_centroids: Array = [{}, {}]
var _wrists: Array[int] = []
var _uppers: Array[int] = []
var _fores: Array[int] = []
var _upper_lengths: Array[float] = []
var _fore_lengths: Array[float] = []
var _wrist_basis: Array[Basis] = []
var _skin_bounds = SkinBounds.new()
var _reload_duration := 0.0


func configure(arms: Node3D, gun: Node3D, profile: Dictionary) -> bool:
	if arms == null or gun == null or profile.is_empty():
		return false
	var skeletons := arms.find_children("*", "Skeleton3D", true, false)
	var players := arms.find_children("*", "AnimationPlayer", true, false)
	if skeletons.size() != 1 or players.size() != 1:
		return false
	skeleton = skeletons[0] as Skeleton3D
	animation = players[0] as AnimationPlayer
	if skeleton.get_bone_count() != 60 or not animation.has_animation(&"idle") or not animation.has_animation(&"reload"):
		return false
	_arms = arms
	_gun = gun
	_profile = profile
	# 各平台装填时长不同；实例独享动作库，不能改共享GLB的reload资源。
	var library := animation.get_animation_library("").duplicate(true) as AnimationLibrary
	animation.remove_animation_library("")
	animation.add_animation_library("", library)
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation.play(&"idle")
	animation.seek(0.0, true)
	animation.pause()
	var hold := animation.get_animation(&"idle").duplicate() as Animation
	animation.get_animation_library("").add_animation(&"hold", hold)
	for bone in skeleton.get_bone_count():
		_positions.append(skeleton.get_bone_pose_position(bone))
		_rotations.append(skeleton.get_bone_pose_rotation(bone))
		_scales.append(skeleton.get_bone_pose_scale(bone))
	for side in [["R_arm_026", "R_elbow_027", "R_wrist_028"], ["L_arm_02", "L_elbow_03", "L_wrist_04"]]:
		var upper := skeleton.find_bone(side[0])
		var fore := skeleton.find_bone(side[1])
		var wrist := skeleton.find_bone(side[2])
		if mini(upper, mini(fore, wrist)) < 0:
			return false
		_uppers.append(upper)
		_fores.append(fore)
		_wrists.append(wrist)
		_upper_lengths.append(skeleton.get_bone_global_pose(upper).origin.distance_to(skeleton.get_bone_global_pose(fore).origin))
		_fore_lengths.append(skeleton.get_bone_global_pose(fore).origin.distance_to(skeleton.get_bone_global_pose(wrist).origin))
		_wrist_basis.append((arms.global_basis.inverse() * skeleton.global_basis * skeleton.get_bone_global_pose(wrist).basis).orthonormalized())
	for child in arms.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.skin != null and mesh.mesh != null:
			_meshes.append(mesh)
			_collect_palms(mesh)
	if _palms[0].is_empty() or _palms[1].is_empty():
		return false
	_cache_palm_centroids()
	# 源枪口为-Z，容器原始单位缩放不动；以真实右掌面标定原容器平移。
	_arms.global_basis = gun.global_basis.orthonormalized() * arms.basis
	var right_world := skeleton.global_transform * _palm_position(0)
	_arms.global_position += gun.global_transform * (profile.right_grip as Vector3) - right_world
	_arms_in_gun = gun.global_transform.affine_inverse() * arms.global_transform
	reset()
	return true


func begin_reload(duration: float) -> void:
	if animation == null or duration <= 0.0:
		return
	if not is_equal_approx(_reload_duration, duration):
		var clip := animation.get_animation(&"reload").duplicate() as Animation
		var source_length := clip.length
		for track in clip.get_track_count():
			var source_times := PackedFloat64Array()
			for key in clip.track_get_key_count(track):
				source_times.append(clip.track_get_key_time(track, key))
			# set_key_time会重排并合并同时间键；扩展从后向前，收缩从前向后。
			var keys := range(source_times.size() - 1, -1, -1) if duration > source_length else range(source_times.size())
			for key in keys:
				clip.track_set_key_time(track, key, source_times[key] * duration / source_length)
		clip.length = duration
		clip.loop_mode = Animation.LOOP_NONE
		animation.get_animation_library("").remove_animation(&"reload")
		animation.get_animation_library("").add_animation(&"reload", clip)
		_reload_duration = duration
	animation.play(&"reload")
	animation.advance(0.0)


func reset() -> void:
	if animation == null:
		return
	animation.play(&"hold")
	animation.seek(0.0, true)
	animation.pause()
	pose_hold(0.0)
	update_bounds()


func pose_hold(aim_weight: float) -> void:
	if skeleton == null or not is_instance_valid(_gun):
		return
	for bone in skeleton.get_bone_count():
		# 装填时保留原生手指曲线，肩肘腕由真实抓点解算。
		if animation.current_animation != "reload" or bone in _uppers or bone in _fores or bone in _wrists:
			skeleton.set_bone_pose_rotation(bone, _rotations[bone])
		skeleton.set_bone_pose_position(bone, _positions[bone])
		skeleton.set_bone_pose_scale(bone, _scales[bone])
	_arms.global_transform = _gun.global_transform * _arms_in_gun
	pose_right_grip()
	var support: Vector3 = (_profile.support_grip_hip as Vector3).lerp(_profile.support_grip_ads as Vector3, clampf(aim_weight, 0.0, 1.0))
	pose_left_grip(_gun.global_transform * support, support_basis_world())


func support_basis_world() -> Basis:
	return _gun.global_basis.orthonormalized() * _wrist_basis[1] * Basis.from_euler(_profile.support_rotation as Vector3)


func pose_right_grip() -> void:
	_place_palm(0, _gun.global_transform * (_profile.right_grip as Vector3), _gun.global_basis.orthonormalized() * _wrist_basis[0])


func pose_left_grip(point_world: Vector3, rotation_world: Basis) -> void:
	_place_palm(1, point_world, rotation_world)


func update_bounds() -> void:
	for mesh in _meshes:
		mesh.custom_aabb = _skin_bounds.get_pose_bounds(mesh)


func _collect_palms(mesh: MeshInstance3D) -> void:
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var width: int = bones.size() / vertices.size()
		for vertex in vertices.size():
			var influences: Array = []
			var hand_weights := [0.0, 0.0]
			for influence in width:
				var offset := vertex * width + influence
				if weights[offset] <= 0.0:
					continue
				var bind := bones[offset]
				var name := mesh.skin.get_bind_name(bind)
				var bone := skeleton.find_bone(name) if name != &"" else mesh.skin.get_bind_bone(bind)
				influences.append({"bone": bone, "bind": mesh.skin.get_bind_pose(bind), "weight": weights[offset]})
				if skeleton.get_bone_name(bone) in ["R_wrist_028", "R_palm_041"]:
					hand_weights[0] += weights[offset]
				elif skeleton.get_bone_name(bone) in ["L_wrist_04", "L_palm_017"]:
					hand_weights[1] += weights[offset]
			for hand in 2:
				if hand_weights[hand] > GameConfig.BLACK_LONG_GUN_PALM_WEIGHT:
					_palms[hand].append({"position": vertices[vertex], "influences": influences})


func _palm_position(hand: int) -> Vector3:
	var sum := Vector3.ZERO
	for bone: int in _palm_centroids[hand]:
		var entry: Dictionary = _palm_centroids[hand][bone]
		var pose := skeleton.get_bone_global_pose(bone)
		sum += pose.basis * (entry.point as Vector3) + pose.origin * float(entry.weight)
	return sum


func _cache_palm_centroids() -> void:
	# 线性蒙皮逐顶点求和等于每骨的bind-space加权位置与平移权重求和。
	# 所有参与的骨均保留，包括腕/掌以外的混合权重；动态手指姿态仍实时应用。
	for hand in 2:
		var entries: Dictionary = _palm_centroids[hand]
		entries.clear()
		var count := float(_palms[hand].size())
		for vertex: Dictionary in _palms[hand]:
			for influence: Dictionary in vertex.influences:
				var bone: int = influence.bone
				if not entries.has(bone):
					entries[bone] = {"point": Vector3.ZERO, "weight": 0.0}
				var entry: Dictionary = entries[bone]
				var weight := float(influence.weight) / count
				entry.point += (influence.bind * vertex.position) * weight
				entry.weight = float(entry.weight) + weight


func _place_palm(hand: int, point_world: Vector3, basis_world: Basis) -> void:
	var wrist_pose := skeleton.get_bone_global_pose(_wrists[hand])
	var palm_offset := wrist_pose.affine_inverse() * _palm_position(hand)
	var target_basis := (skeleton.global_basis.inverse() * basis_world).orthonormalized()
	var target := Transform3D(target_basis, skeleton.global_transform.affine_inverse() * point_world - target_basis * palm_offset)
	var pole: Vector3 = GameConfig.BLACK_LONG_GUN_RIGHT_ELBOW_POLE if hand == 0 else GameConfig.BLACK_LONG_GUN_LEFT_ELBOW_POLE
	pole = skeleton.global_basis.inverse() * (_gun.global_basis.orthonormalized() * pole)
	_place_arm(hand, target, pole)


func _place_arm(hand: int, target: Transform3D, pole_offset: Vector3) -> void:
	var upper_bone := _uppers[hand]
	var fore_bone := _fores[hand]
	var wrist_bone := _wrists[hand]
	var upper_length := _upper_lengths[hand]
	var fore_length := _fore_lengths[hand]
	var upper := skeleton.get_bone_global_pose(upper_bone)
	var fore := skeleton.get_bone_global_pose(fore_bone)
	var wrist := skeleton.get_bone_global_pose(wrist_bone)
	var shoulder := upper.origin
	var reach := target.origin - shoulder
	var length := reach.length()
	var minimum := absf(upper_length - fore_length)
	var maximum := upper_length + fore_length
	if length >= maximum or length <= minimum:
		length = clampf(length, minimum + 0.0001, maximum * GameConfig.BLACK_LONG_GUN_SHOULDER_REACH)
		shoulder = target.origin - reach.normalized() * length
	var direction := (target.origin - shoulder).normalized()
	var along := (upper_length * upper_length - fore_length * fore_length + length * length) / (2.0 * length)
	var height := sqrt(maxf(0.0, upper_length * upper_length - along * along))
	var pole := pole_offset - direction * pole_offset.dot(direction)
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
	skeleton.set_bone_global_pose(wrist_bone, target)
	skeleton.set_bone_pose_scale(wrist_bone, Vector3.ONE)
