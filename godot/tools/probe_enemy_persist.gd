## 敌人跨场景持久化验证 v2（2026-10-25 机主实机报修后重写：全真实链路）：
## P1 初次加载 → P2 杀2敌+搬移1敌掉血 → P3 真玩家teleport进门B触发区（真实
## _on_body_entered：快照+change_scene）→ P4 district_b 里造触发体进返回门
## → P5 断言主街：敌人=快照态 + 玩家被到达分支传送到门内侧（v1 曾手动 call
## _restore_enemies 绕过了构造时序 bug——link 属性在 add_child 之后才 set，
## _ready 时 anchor_id 为空串=到达分支死路；本探针专验该接线）。
## ⚠️ 探针严禁编译期引用 SceneLink/带 autoload 的类（-s 语境编译毒化），全鸭子类型。
## 用法：godot --headless -s tools/probe_enemy_persist.gd --path .
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _enemies() -> Dictionary:
	var out := {}
	for e in root.get_tree().get_nodes_in_group(&"enemy"):
		out[String((e as Node).name)] = e
	return out


func _flat_d(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _run() -> void:
	# —— P1 初次加载（手动接管 current_scene，change_scene_to_file 才能工作）——
	var lv: Node3D = load("res://scenes/levels/street_playable.tscn").instantiate()
	root.add_child(lv)
	current_scene = lv
	for i in 30:
		await process_frame
	var n0: int = _enemies().size()
	print("P1_FIRST_LOAD enemies=", n0)
	# —— P2 施压：杀2敌 + 搬移1敌 + 掉血 ——
	var killed: int = 0
	for victim in ["Host_ST1", "Host_GY1"]:
		var e: Node = _enemies().get(victim)
		if e != null:
			e.call("take_damage", 9999.0, false)
			killed += 1
	for i in 5:
		await process_frame
	var st2: Node3D = _enemies()["Host_ST2"]
	st2.global_position = Vector3(5.0, 0.3, -40.0)
	st2.set("health", 0.37)
	print("P2_PRESS killed=", killed, " st2_moved=", st2.global_position.round())
	# —— P2b 领钥匙（门B requires_key；-s 语境按路径取 autoload，勿编译期引用）——
	var gs: Node = root.get_node("/root/GameState")
	gs.set("gate_key_have", true)
	print("P2B_KEY gate_key_have=", gs.get("gate_key_have"))
	# —— P3 真玩家进门B触发区（门内 = bx-0.8=21.2, z=5）——
	var player: Node3D = root.get_tree().get_first_node_in_group(&"player")
	player.global_position = Vector3(21.2, 1.0, 5.0)
	var waited: int = 0
	var to_district: bool = false
	while waited < 300:
		await process_frame
		waited += 1
		var cs: Node = current_scene
		if cs != null and String(cs.scene_file_path).ends_with("district_b.tscn"):
			to_district = true
			break
	var cur: Node = current_scene
	print("P3_TRANSIT district=", to_district, " waited_frames=", waited)
	if not to_district:
		print("PERSIST_FAIL transit")
		quit()
		return
	# —— P4 district_b：等免疫期(1.2s 真实墙钟)过——headless 帧率不定，按墙钟等——
	var t_arrive: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_arrive < 1500:
		await process_frame
	var body := CharacterBody3D.new()
	body.name = "ProbePlayer"
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.3
	cs.shape = sph
	cs.position = Vector3(0, 0.3, 0)
	body.add_child(cs)
	cur.add_child(body)
	body.add_to_group(&"player")
	body.global_position = Vector3(0, 0.6, 9.0)
	waited = 0
	var back_street: bool = false
	while waited < 600:
		await process_frame
		waited += 1
		if waited % 20 == 0:
			body.global_position = Vector3(0, 0.6, 9.0)  # 微移刷新重叠检测
		var scn: Node = current_scene
		if scn != null and String(scn.scene_file_path).ends_with("street_playable.tscn"):
			back_street = true
			break
	var lv2: Node = current_scene
	print("P4_RETURN street=", back_street, " waited_frames=", waited)
	if not back_street:
		var scn2: Node = current_scene
		print("P4_DEBUG cur=", scn2.scene_file_path if scn2 != null else "null")
		if scn2 != null:
			for n in scn2.find_children("Link_*", "Node3D", true, false):
				var ln := n as Node3D
				print("P4_DEBUG link=", ln.name, " pos=", ln.global_position.round(),
					" onbody=", ln.has_method(&"_on_body_entered"),
					" anchor=", ln.get("anchor_id"))
			for a in scn2.find_children("TriggerArea", "Area3D", true, false):
				var ar := a as Area3D
				print("P4_DEBUG area=", (ar.get_parent() as Node).name, "/TriggerArea pos=",
					ar.global_position.round(), " monitoring=", ar.monitoring,
					" mask=", ar.collision_mask)
			print("P4_DEBUG body_in_tree=", body.is_inside_tree(),
				" body_pos=", body.global_position,
				" in_player_group=", body.is_in_group(&"player"))
		print("PERSIST_FAIL return")
		quit()
		return
	if not back_street:
		print("PERSIST_FAIL return")
		quit()
		return
	for i in 15:
		await process_frame  # 延迟恢复 + queue_free 落树
	# —— P5 断言：敌人=快照态 + 玩家被 _ready 到达分支传送到门内侧 ——
	var names1 := _enemies()
	var st2b: Node3D = names1.get("Host_ST2")
	var pc: Variant = st2b.get("_patrol_center") if st2b != null else null
	var pl: Node3D = root.get_tree().get_first_node_in_group(&"player")
	var pl_at_gate: bool = pl != null and _flat_d(pl.global_position, Vector3(18.6, 0, 5)) < 3.0
	print("P5_RETURN enemies=", names1.size(), " (期望=", n0 - killed, ")",
		" ST1_alive=", names1.has("Host_ST1"), "(期望false)",
		" GY1_alive=", names1.has("Host_GY1"), "(期望false)",
		" ST2_hp=", snappedf(st2b.get("health"), 0.01) if st2b else "-", "(期望0.37)")
	print("P5_ST2 pos=", st2b.global_position.round() if st2b else "-",
		" patrol_center=", (pc as Vector3).round() if pc != null else "-")
	print("P5_PLAYER at_gate=", pl_at_gate,
		" pos=", pl.global_position.round() if pl != null else "-",
		" (期望≈(18.6,0.2,5)=门内侧落点，证明 _ready 到达分支已活)")
	var ok: bool = names1.size() == n0 - killed and not names1.has("Host_ST1") \
		and not names1.has("Host_GY1") and st2b != null \
		and absf(st2b.get("health") - 0.37) < 0.01 \
		and _flat_d(st2b.global_position, Vector3(5, 0, -40)) < 2.5 \
		and pc != null and _flat_d(pc as Vector3, Vector3(5, 0, -40)) < 0.5 \
		and pl_at_gate
	print("PERSIST_", "PASS" if ok else "FAIL")
	quit()
