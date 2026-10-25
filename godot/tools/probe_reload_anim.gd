## 换弹动画骨运动探针（开发取证，不入 L1 链）：
## 加载 rifle 场景 → hold 基线采样 → 播放 reload 剪辑逐时刻推进，
## 打印武器骨/弹匣骨/左手_ctrl 相对基线的旋转角与位移——量化「混乱脱节」
## 到底乱在哪：枪身摆幅？弹匣轨迹？左手去哪了？
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var rifle: Node3D = load("res://scenes/weapons/rifle.tscn").instantiate()
	root.add_child(rifle)
	for i in 10:
		await process_frame
	var skel: Skeleton3D = null
	var anim: AnimationPlayer = null
	var players: Array = rifle.find_children("*", "AnimationPlayer", true, false)
	var skels: Array = rifle.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		skel = skels[0] as Skeleton3D
	if not players.is_empty():
		anim = players[0] as AnimationPlayer
	if skel == null or anim == null or not anim.has_animation(&"hold"):
		print("RELOAD_PROBE_FAIL setup")
		quit()
		return
	var weapon_bone: int = skel.find_bone("ACRRifle_058")
	var mag_bone: int = skel.find_bone("Pmag_061")
	var hand_ctrl: int = -1
	for b in skel.get_bone_count():
		if skel.get_bone_name(b).begins_with("IK_Hand_Cntrl_L"):
			hand_ctrl = b
			break
	# hold 基线（骨架局部系）。
	anim.play(&"hold")
	anim.seek(0.0, true)
	anim.pause()
	await process_frame
	var base_weapon := skel.get_bone_global_pose(weapon_bone)
	var base_mag := skel.get_bone_global_pose(mag_bone)
	var base_hand := skel.get_bone_global_pose(hand_ctrl).origin
	# reload 全长（重定时后=weapon_data.reload_time 2s）。
	anim.play(&"reload")
	for t in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0]:
		anim.seek(t, true)
		await process_frame
		var w := skel.get_bone_global_pose(weapon_bone)
		var m := skel.get_bone_global_pose(mag_bone)
		var h := skel.get_bone_global_pose(hand_ctrl).origin
		var w_ang: float = rad_to_deg((base_weapon.basis.inverse() * w.basis).get_rotation_quaternion().get_angle())
		var m_ang: float = rad_to_deg((base_mag.basis.inverse() * m.basis).get_rotation_quaternion().get_angle())
		print("RELOAD_PROBE t=", t,
			" gun_deg=", snappedf(w_ang, 1.0), " gun_off_mm=", snappedf((w.origin - base_weapon.origin).length() * 1000.0, 1.0),
			" mag_deg=", snappedf(m_ang, 1.0), " mag_off_mm=", snappedf((m.origin - base_mag.origin).length() * 1000.0, 1.0),
			" hand_off_mm=", snappedf((h - base_hand).length() * 1000.0, 1.0))
	quit()
