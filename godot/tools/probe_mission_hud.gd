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
	# —— M1 场景登记 ——
	var mp: Dictionary = _gs().get("mission_points")
	var kinds := {}
	for k in mp:
		kinds[mp[k]["kind"]] = kinds.get(mp[k]["kind"], 0) + 1
	print("M1_POINTS total=", mp.size(), "(期望3) kinds=", kinds,
		" intel_total=", _gs().get("intel_total"), "(期望2)")
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
	# —— M3 真实拾取 E1 取证终端（贴身触发 pickup.gd）——
	player.global_position = Vector3(13.0, 1.0, 21.7)
	for i in 30:
		await process_frame
	print("M3_PICKUP intel=", _gs().get("intel"), "(期望1)",
		" points=", _gs().get("mission_points").size(), "(期望2)",
		" lbl=", intel_lbl.text)
	player.global_position = Vector3(0, 1.0, -20.0)
	await _shot(cam, Vector3(0, 1.7, -19.2), Vector3(0, 1.6, -30.0), "m_hud_1of2")
	# —— M4 门禁拦截：有钥匙、终端 1/2 → 触发区不穿门 ——
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
	# —— M5 补齐终端 → 出区重进触发 → 真实放行 ——
	_gs().set("intel", 2)
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
	print("MISSION_", "PASS" if passed else "FAIL")
	quit()
