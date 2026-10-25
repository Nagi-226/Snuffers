## 换弹连续动作探针 v2（开发取证，不入 L1 链）：
## 触发真实换弹管线（_start_reload 全链：Events→_play_reload_anim→逐帧counter），
## 每 0.05s 采样：反向滚转角、弹匣世界位、左/右手骨世界位、弹匣-井距、弹匣-右手距、
## 逐帧跳变检测——验收换弹「动作」而非单帧。
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var rifle: Node3D = load("res://scenes/weapons/rifle.tscn").instantiate()
	root.add_child(rifle)
	for i in 12:
		await process_frame
	var skel: Skeleton3D = null
	var skels: Array = rifle.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		skel = skels[0] as Skeleton3D
	var mag: Node3D = rifle.get_node_or_null("ViewModel/EM68A/em68a_magazine")
	var gun: Node3D = rifle.get_node("ViewModel/EM68A")
	if skel == null or mag == null:
		print("MOTION_PROBE_FAIL setup")
		quit()
		return
	var hand_l := -1
	var hand_r := -1
	for b in skel.get_bone_count():
		var n: String = skel.get_bone_name(b)
		if hand_l < 0 and n.begins_with("IK_Hand_Cntrl_L"):
			hand_l = b
		elif hand_r < 0 and n.begins_with("IK_Hand_Cntrl_R"):
			hand_r = b
	var mag_home: Vector3 = mag.global_position
	var last_mag: Vector3 = mag.global_position
	var mag_bone: int = skel.find_bone("Pmag_061")
	var last_bone: Vector3 = skel.global_transform * skel.get_bone_global_pose(mag_bone).origin
	var worst_jump: float = 0.0
	var worst_jump_at: float = -1.0
	var worst_bone_jump: float = 0.0
	var worst_bone_at: float = -1.0
	# 触发真实换弹（与 vm-shot 同法：先清弹匣过守卫，再走控制器全管线）。
	var game_state: Node = root.get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.set("rifle_mag", 0)
	if not rifle.has_method("_start_reload"):
		print("MOTION_PROBE_FAIL no _start_reload")
		quit()
		return
	rifle.call("_start_reload")
	var t: float = 0.0
	while t < 2.3:
		await process_frame
		t += 1.0 / 60.0
		if fmod(t, 0.05) < (1.0 / 60.0):
			var counter: float = float(rifle.get("_reload_counter"))
			var mag_pos: Vector3 = mag.global_position
			var jump: float = mag_pos.distance_to(last_mag)
			if jump > worst_jump and t > 0.1:
				worst_jump = jump
				worst_jump_at = t
			var bone_pos: Vector3 = skel.global_transform * skel.get_bone_global_pose(mag_bone).origin
			var bone_jump: float = bone_pos.distance_to(last_bone)
			if bone_jump > worst_bone_jump and t > 0.1:
				worst_bone_jump = bone_jump
				worst_bone_at = t
			var hand_r_pos: Vector3 = skel.global_transform * skel.get_bone_global_pose(hand_r).origin if hand_r >= 0 else Vector3.INF
			var hand_l_pos: Vector3 = skel.global_transform * skel.get_bone_global_pose(hand_l).origin if hand_l >= 0 else Vector3.INF
			print("MOTION_PROBE t=", snappedf(t, 0.05),
				" counter_deg=", snappedf(rad_to_deg(counter), 1.0),
				" mag_home_mm=", snappedf(mag_pos.distance_to(mag_home) * 1000.0, 1.0),
				" mag_handR_mm=", snappedf(mag_pos.distance_to(hand_r_pos) * 1000.0, 1.0),
				" mag_handL_mm=", snappedf(mag_pos.distance_to(hand_l_pos) * 1000.0, 1.0),
				" frame_jump_mm=", snappedf(jump * 1000.0, 1.0),
				" bone_jump_mm=", snappedf(bone_jump * 1000.0, 1.0))
			last_mag = mag_pos
			last_bone = bone_pos
	print("MOTION_PROBE worst_jump_mm=", snappedf(worst_jump * 1000.0, 1.0), " at t=", worst_jump_at)
	print("MOTION_PROBE worst_bone_jump_mm=", snappedf(worst_bone_jump * 1000.0, 1.0), " at t=", worst_bone_at)
	quit()
