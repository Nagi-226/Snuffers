## 左臂姿势几何探针（开发取证，不入 L1 链）：
## 加载 rifle.tscn 跑完 _ready 姿势改写后，读骨架实测——腕接缝（前臂尖端 vs
## 手原点）、手到目标误差、链长可达性、手指轴向 vs 枪轴向。视觉分析器不可靠，
## 这些数字直接从引擎取，作为姿势修复的地面真值。
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var rifle: Node3D = load("res://scenes/weapons/rifle.tscn").instantiate()
	root.add_child(rifle)
	for i in 10:
		await process_frame
	var skel: Skeleton3D = null
	var players: Array = rifle.find_children("*", "Skeleton3D", true, false)
	if not players.is_empty():
		skel = players[0] as Skeleton3D
	var weapon: Node3D = rifle.get_node("ViewModel/EM68A")
	if skel == null or weapon == null:
		print("PROBE_FAIL no skel/weapon")
		quit()
		return
	var bones := {}
	for b in skel.get_bone_count():
		var n: String = skel.get_bone_name(b)
		bones[n] = b
	# 世界系读数（场景在原点附近，安全）。
	var uparm: int = -1
	var fore: int = -1
	var twist: int = -1
	var ctrl: int = -1
	var hand: int = -1
	for n: String in bones.keys():
		if n.begins_with("UpArm_L"):
			uparm = bones[n]
		elif n.begins_with("Forearm_L"):
			fore = bones[n]
		elif n.begins_with("BoneTwist_03.L"):
			twist = bones[n]
		elif n.begins_with("IK_Hand_Cntrl_L"):
			ctrl = bones[n]
		elif n.begins_with("Hand_L"):
			hand = bones[n]
	if uparm < 0 or fore < 0 or twist < 0 or ctrl < 0 or hand < 0:
		print("PROBE_FAIL bone lookup")
		quit()
		return
	var shoulder: Vector3 = skel.global_transform * skel.get_bone_global_pose(uparm).origin
	var elbow: Vector3 = skel.global_transform * skel.get_bone_global_pose(fore).origin
	var ftip: Vector3 = skel.global_transform * skel.get_bone_global_pose(twist).origin
	var hand_pos: Vector3 = skel.global_transform * skel.get_bone_global_pose(hand).origin
	# 链长（改写只旋转不伸缩）。
	var l_forearm: float = (skel.get_bone_global_pose(fore).origin - skel.get_bone_global_pose(uparm).origin).length()
	var l_wrist: float = (skel.get_bone_global_pose(fore).origin - skel.get_bone_global_pose(hand).origin).length()
	# 真实链端=前臂原点+骨轴Y×前臂长（twist 骨与前臂共位，不能作尖端）。
	var chain_end: Vector3 = skel.global_transform * (skel.get_bone_global_pose(fore).origin + skel.get_bone_global_pose(fore).basis.y * l_wrist)
	var hand_y_world: Vector3 = skel.global_transform.basis * skel.get_bone_global_pose(hand).basis.y
	# 手指轴向：Hand_L 的子骨（指骨）方向；无子骨则用 Hand basis 的某轴。
	var finger_dir_world: Vector3 = Vector3.ZERO
	var children: PackedInt32Array = skel.get_bone_children(hand)
	if children.size() > 0:
		var c0: int = children[0]
		finger_dir_world = skel.global_transform.basis * (skel.get_bone_global_pose(c0).origin - skel.get_bone_global_pose(hand).origin).normalized()
	var gun_g: Transform3D = weapon.global_transform
	# EM68A 枪身几何实测：各子网格 AABB 转武器局部系（目标点不能拍脑袋，
	# 手必须落在真实下表面上）。
	var to_weapon: Transform3D = gun_g.affine_inverse()
	var combined_min: Vector3 = Vector3(INF, INF, INF)
	var combined_max: Vector3 = Vector3(-INF, -INF, -INF)
	for mesh_node in weapon.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_node as MeshInstance3D
		if mi.mesh == null:
			continue
		var aabb: AABB = mi.get_aabb()
		var local_to_weapon: Transform3D = to_weapon * mi.global_transform
		for corner in [
			aabb.position,
			aabb.position + Vector3(aabb.size.x, 0, 0),
			aabb.position + Vector3(0, aabb.size.y, 0),
			aabb.position + Vector3(0, 0, aabb.size.z),
			aabb.position + Vector3(aabb.size.x, aabb.size.y, 0),
			aabb.position + Vector3(aabb.size.x, 0, aabb.size.z),
			aabb.position + Vector3(0, aabb.size.y, aabb.size.z),
			aabb.position + aabb.size,
		]:
			var p: Vector3 = local_to_weapon * corner
			combined_min = combined_min.min(p)
			combined_max = combined_max.max(p)
		print("PROBE gun_mesh=", mi.name, " aabb_weapon=", local_to_weapon * aabb.position, "..", local_to_weapon * (aabb.position + aabb.size))
	print("PROBE gun_combined=", combined_min, "..", combined_max)
	# 护木参考点（与控制器腰射腕目标同参）。
	var wrist_target: Vector3 = gun_g * Vector3(-0.05, -0.045, -0.26)
	var muzzle_dir: Vector3 = -gun_g.basis.z
	# 骨轴向约定：basis.y 是否沿骨（肩→肘 / 肘→腕）。
	var uparm_y: Vector3 = skel.global_transform.basis * skel.get_bone_global_pose(uparm).basis.y
	var se_dir: Vector3 = (elbow - shoulder).normalized()
	print("PROBE uparm_y_vs_shoulder_elbow_deg=", rad_to_deg(uparm_y.angle_to(se_dir)))
	var fore_y: Vector3 = skel.global_transform.basis * skel.get_bone_global_pose(fore).basis.y
	print("PROBE fore_y=", fore_y, " fore_y_vs_elbow_hand_deg=", rad_to_deg(fore_y.angle_to((hand_pos - elbow).normalized())))
	# 前臂与手的子骨清单（找真实腕骨/指骨）。
	var fc: PackedInt32Array = skel.get_bone_children(fore)
	for c in fc:
		print("PROBE fore_child=", skel.get_bone_name(c), " at=", skel.global_transform * skel.get_bone_global_pose(c).origin)
	var hc: PackedInt32Array = skel.get_bone_children(hand)
	for c in hc:
		print("PROBE hand_child=", skel.get_bone_name(c), " at=", skel.global_transform * skel.get_bone_global_pose(c).origin)
	print("PROBE shoulder=", shoulder)
	print("PROBE elbow=", elbow)
	print("PROBE forearm_tip=", ftip)
	print("PROBE hand=", hand_pos)
	print("PROBE wrist_target=", wrist_target)
	print("PROBE wrist_gap_mm=", (chain_end.distance_to(hand_pos)) * 1000.0)
	print("PROBE hand_to_target_mm=", hand_pos.distance_to(wrist_target) * 1000.0)
	print("PROBE chain_reach_mm=", (l_forearm + l_wrist) * 1000.0)
	print("PROBE shoulder_to_target_mm=", shoulder.distance_to(wrist_target) * 1000.0)
	print("PROBE hand_y_vs_muzzle_deg=", rad_to_deg(hand_y_world.angle_to(muzzle_dir)))
	quit()
