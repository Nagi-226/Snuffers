## 门禁前置+HUD 任务系统验证（2026-10-25 机主指令：钥匙+2取证终端/任务栏/小地图标记/罗盘）：
## M1 场景登记（mission_points 3 项 + intel_total=2） M2 HUD 节点在位+任务栏文案
## M3 真实拾取 intel（贴身触发）→计数/标记删除/任务栏更新  M4 门禁拦截（有钥匙缺终端）
## M5 补齐后真实放行（穿门 B）  M6 HUD 验收截图（含罗盘转动前后）
## 用法：godot -s tools/probe_mission_hud.gd --path . --resolution 1280x720（窗口模式）
extends SceneTree

const OUT := "C:/Users/FJL03/AppData/Local/Temp/snuff_shots/"


func _init() -> void:
	call_deferred("_run")


func _gs() -> Node:
	return root.get_node("/root/GameState")


func _flat_d(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _shot(cam: Camera3D, pos: Vector3, look: Vector3, nm: String) -> void:
	cam.position = pos
	cam.look_at(look)
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(OUT + nm + ".png")
	print("SHOT_", nm)


func _run() -> void:
	var lv: Node3D = load("res://scenes/levels/street_playable.tscn").instantiate()
	root.add_child(lv)
	current_scene = lv
	for i in 30:
		await process_frame
	# —— M1 场景登记（4 项：钥匙+3 终端；intel_total=3）——
	var mp: Dictionary = _gs().get("mission_points")
	var kinds := {}
	for k in mp:
		kinds[mp[k]["kind"]] = kinds.get(mp[k]["kind"], 0) + 1
	print("M1_POINTS total=", mp.size(), "(期望4) kinds=", kinds,
		" intel_total=", _gs().get("intel_total"), "(期望3)")
	var i1: Node3D = lv.find_child("Pickup_intel_1", true, false)
	var i4: Node3D = lv.find_child("Pickup_intel_4", true, false)
	var i8: Node3D = lv.find_child("Pickup_intel_8", true, false)
	var g9: Node3D = lv.find_child("Pickup_grenade_9", true, false)
	print("M1B_SPOTS E1_2F_y=", snappedf(i1.position.y, 0.01), "(期望≈3.86)",
		" E2_3F_y=", snappedf(i4.position.y, 0.01), "(期望≈6.86)",
		" E3_garage=", i8 != null, " pos=", i8.position.round() if i8 else "-",
		" grenade=", g9 != null)
	# —— M2 HUD 节点 + 初始文案（按名直找，避开多 CanvasLayer 歧义）——
	var panel: Control = lv.find_child("MissionPanel", true, false)
	var compass: Control = lv.find_child("CompassBar", true, false)
	var key_lbl: Label = lv.find_child("MissionKey", true, false)
	var intel_lbl: Label = lv.find_child("MissionIntel", true, false)
	var title_lbl: Label = lv.find_child("MissionTitle", true, false)
	print("M2_HUD panel=", panel != null, " compass=", compass != null,
		" compass_script=", (compass.get_script() != null) if compass != null else "-",
		" title=", title_lbl.text if title_lbl else "-",
		" key=", key_lbl.text if key_lbl else "-", " intel=", intel_lbl.text if intel_lbl else "-")
	# —— 截图机位（HUD 常驻 CanvasLayer，任意相机都入画）——
	var cam := Camera3D.new()
	lv.add_child(cam)
	cam.make_current()
	var player: Node3D = root.get_tree().get_first_node_in_group(&"player")
	player.global_position = Vector3(0, 1.0, -20.0)
	await _shot(cam, Vector3(0, 1.7, -19.2), Vector3(0, 1.6, -30.0), "m_hud_start")
	# —— M3 真实拾取 E1 二楼取证终端（贴身触发 pickup.gd；楼层地面 y=3.0）——
	player.global_position = Vector3(13.5, 3.2, 21.2)
	for i in 30:
		await process_frame
	print("M3_PICKUP intel=", _gs().get("intel"), "(期望1)",
		" points=", _gs().get("mission_points").size(), "(期望3)",
		" lbl=", intel_lbl.text)
	# —— M3b 榴弹补给（E3 车库车位旁；雷池 30+6=36）——
	var nades0: int = _gs().get("rifle_grenades")
	player.global_position = Vector3(10.8, 1.0, -15.6)
	for i in 30:
		await process_frame
	print("M3B_GRENADE before=", nades0, " after=", _gs().get("rifle_grenades"),
		"(期望+6) node_gone=", lv.find_child("Pickup_grenade_9", true, false) == null)
	player.global_position = Vector3(0, 1.0, -20.0)
	await _shot(cam, Vector3(0, 1.7, -19.2), Vector3(0, 1.6, -30.0), "m_hud_1of2")
	# —— M4 门禁拦截：有钥匙、终端 1/3 → 触发区不穿门 ——
	_gs().set("gate_key_have", true)
	player.global_position = Vector3(21.2, 1.0, 5.0)
	var blocked: bool = true
	for i in 90:
		await process_frame
		var cs: Node = current_scene
		if cs != null and String(cs.scene_file_path).ends_with("district_b.tscn"):
			blocked = false
			break
	print("M4_GATE_BLOCKED blocked=", blocked, "(期望true=缺终端被拦)")
	if not blocked:
		print("MISSION_FAIL gate_leak")
		quit()
		return
	# —— M4b 2/3 仍拦（机主四轮报修场景：集齐 3 台才放行）——
	_gs().set("intel", 2)
	player.global_position = Vector3(17.0, 1.0, 5.0)
	for i in 5:
		await process_frame
	player.global_position = Vector3(21.2, 1.0, 5.0)
	var blocked2: bool = true
	for i in 90:
		await process_frame
		var cs: Node = current_scene
		if cs != null and String(cs.scene_file_path).ends_with("district_b.tscn"):
			blocked2 = false
			break
	print("M4B_TWO_STILL_BLOCKED blocked=", blocked2, "(期望true=2/3不放行)")
	# —— M5 补齐 3 台 → 出区重进触发 → 真实放行 ——
	_gs().set("intel", 3)
	player.global_position = Vector3(17.0, 1.0, 5.0)
	for i in 5:
		await process_frame
	player.global_position = Vector3(21.2, 1.0, 5.0)
	var passed: bool = false
	for i in 300:
		await process_frame
		var cs: Node = current_scene
		if cs != null and String(cs.scene_file_path).ends_with("district_b.tscn"):
			passed = true
			break
	print("M5_GATE_PASS passed=", passed,
		" player_at_arrival=", (root.get_tree().get_first_node_in_group(&"player") as Node3D).global_position.round()
			if passed and root.get_tree().get_first_node_in_group(&"player") != null else "-")
	if not passed:
		print("MISSION_FAIL")
		quit()
		return
	# —— M6 往返持久化：从 district_b 返回主街，已拾取的终端不得刷新 ——
	var t_arr: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_arr < 1500:
		await process_frame
	var body := CharacterBody3D.new()
	var cs2 := CollisionShape3D.new()
	var sph2 := SphereShape3D.new()
	sph2.radius = 0.3
	cs2.shape = sph2
	cs2.position = Vector3(0, 0.3, 0)
	body.add_child(cs2)
	(current_scene as Node).add_child(body)
	body.add_to_group(&"player")
	body.global_position = Vector3(0, 0.6, 9.0)
	var back: bool = false
	for i in 600:
		await process_frame
		if i % 20 == 0:
			body.global_position = Vector3(0, 0.6, 9.0)
		var scn: Node = current_scene
		if scn != null and String(scn.scene_file_path).ends_with("street_playable.tscn"):
			back = true
			break
	for i in 15:
		await process_frame
	var back_lv: Node = current_scene
	var pickups_alive: int = back_lv.get_tree().get_nodes_in_group(&"pickup").size()
	var gone: bool = back_lv.find_child("Pickup_intel_1", true, false) == null
	var nade_gone: bool = back_lv.find_child("Pickup_grenade_9", true, false) == null
	var key_gone: bool = back_lv.find_child("GateKeyPickup", true, false) == null
	var kept4: bool = back_lv.find_child("Pickup_intel_4", true, false) != null
	var kept8: bool = back_lv.find_child("Pickup_intel_8", true, false) != null
	var mp2: Dictionary = _gs().get("mission_points")
	print("M6_PERSIST back=", back, " pickups_alive=", pickups_alive,
		"(期望8=10拾取件-已拾2·钥匙已得跳生)",
		" intel1_gone=", gone, "(期望true) grenade_gone=", nade_gone, "(期望true)",
		" key_gone=", key_gone, "(期望true=已得不再生成)",
		" intel4_kept=", kept4, " intel8_kept=", kept8,
		" points=", mp2.size(), "(期望3)",
		" lbl=", intel_lbl.text if is_instance_valid(intel_lbl) else "-")
	var ok: bool = back and pickups_alive == 8 and gone and nade_gone and key_gone \
		and kept4 and kept8 and mp2.size() == 3
	print("MISSION_", "PASS" if ok else "FAIL")
	quit()
