## 2026-10-25 三轮整改综合验证（数据断言 + 验收截图）：
## R1 门A拆除+球场西端密封栏复位+门B完好  R2 车模还原(不压扁)+移位+WB口/E5门口通过性
## R3 E5 背门 E 键门扇(door.gd)  R4 后院扩容(x→31)+钥匙移入+开源杂物  R5 篮球架归位
## R6 验收截图（窗口化运行：godot -s tools/probe_round3.gd --path . --resolution 1280x720）
## 取代 probe_six_verify.gd（其 V1/V2/V5/V6 断言已被本轮反转，勿再引用）
extends SceneTree

const OUT := "C:/Users/FJL03/AppData/Local/Temp/snuff_shots/"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level: Node3D = load("res://scenes/levels/street_playable.tscn").instantiate()
	root.add_child(level)
	for i in 30:
		await process_frame
	# —— R1 门 A 拆除 + 球场西端栏复位 + 门 B 完好 ——
	var gate_a_nodes: int = 0
	var court_fence: bool = false
	var bgate_link: Node = null
	for n in level.find_children("*", "Node3D", true, false):
		var nm: String = n.name
		if nm.begins_with("AGate") or nm == "Link_CourtGate" or nm == "GateGlow":
			gate_a_nodes += 1
	for n in level.find_children("Fence_*", "Node3D", true, false):
		var fn := n as Node3D
		if absf(fn.rotation_degrees.y) < 1.0 and absf(fn.position.x - (-27.0)) < 0.35 \
				and absf(fn.position.z - (-59.0)) < 2.0:
			court_fence = true
	for link in level.find_children("Link_*", "Node3D", true, false):
		if String(link.name) == "Link_BGate_E":
			bgate_link = link
	print("R1_GATEA_REMOVED remains=", gate_a_nodes, " court_fence_restored=", court_fence,
		" bgate=", bgate_link != null,
		" bgate_key=", bgate_link.get("requires_key") if bgate_link else "-",
		" bgate_target=", bgate_link.get("target_scene") if bgate_link else "-")
	# —— R2 车模还原 + 移位 + 两口通过性 ——
	# 旅行车/紧凑车：模型不压扁（碰撞盒横宽≈3.3 原生胖），新位让口
	for pat in [["Prop_car_stationwagon_*", -1.5, -60.0], ["Prop_car_compact_*", 1.2, -48.0]]:
		for n in level.find_children(pat[0], "Node3D", true, false):
			var c: Vector3 = (n as Node3D).global_position
			for cs in (n as Node3D).find_children("*", "CollisionShape3D", true, false):
				if (cs as CollisionShape3D).shape is BoxShape3D:
					var bs: BoxShape3D = (cs as CollisionShape3D).shape
					print("R2_CAR ", n.name, " center=", c.round(),
						" size=", Vector3(snappedf(bs.size.x, 0.1), snappedf(bs.size.y, 0.1),
							snappedf(bs.size.z, 0.1)),
						" expected_x=", pat[1], " native_fat_z>=3.0=", bs.size.z >= 3.0)
	# 巷口通过性胶囊扫掠：WB 巷口（x -6.2..-4.6, z -61.5..-57.5）/ E5 车库门口（x 5.4..6.4, z -50.5..-45.5）
	var ps := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 1.7
	ps.shape = cap
	ps.collision_mask = 0xFFFF
	for corridor in [["wb_mouth", -6.2, -4.6, -61.5, -57.5], ["e5_mouth", 5.4, 6.4, -50.5, -45.5]]:
		var free_cells: int = 0
		var blocked_cells: int = 0
		var blockers := {}
		var x: float = corridor[1]
		while x < corridor[2]:
			var z: float = corridor[3]
			while z < corridor[4]:
				ps.transform = Transform3D(Basis(), Vector3(x, 1.0, z))
				var hits: Array = level.get_world_3d().direct_space_state.intersect_shape(ps, 16)
				var names: Array = []
				for hit in hits:
					var col := hit["collider"] as Node
					if col == null:
						continue
					var chain: String = String(col.name)
					var par: Node = col.get_parent()
					if par != null:
						chain = String(par.name) + "/" + chain
					if chain.contains("Ground") or chain.contains("Sidewalk"):
						continue
					names.append(chain)
				if names.is_empty():
					free_cells += 1
				else:
					blocked_cells += 1
					for nm2 in names:
						blockers[nm2] = blockers.get(nm2, 0) + 1
				z += 0.25
			x += 0.25
		print("R2_CORRIDOR ", corridor[0], " free=", free_cells, " blocked=", blocked_cells,
			" blockers=", blockers)
	# —— R3 E5 背门 E 键门扇 ——
	var rear_door: Node = null
	for n in level.find_children("Gar_E5_RearDoor", "Node3D", true, false):
		rear_door = n
	print("R3_REARDOOR present=", rear_door != null,
		" interact=", rear_door.has_method(&"interact") if rear_door else "-",
		" prompt=", rear_door.has_method(&"interact_prompt") if rear_door else "-",
		" leaf=", rear_door.get_node_or_null("Leaf") != null if rear_door else "-",
		" jamb_n=", level.find_children("Gar_E5_RearJamb_N*", "Node3D", true, false).size() > 0,
		" jamb_s=", level.find_children("Gar_E5_RearJamb_S*", "Node3D", true, false).size() > 0)
	# —— R4 后院扩容 + 钥匙 + 开源杂物 ——
	var key_pickup: Node3D = null
	for n in level.find_children("GateKeyPickup", "Area3D", true, false):
		key_pickup = n
	var junk_props: int = 0
	var junk_with_collider: int = 0
	for n in level.find_children("Prop_junk_*", "Node3D", true, false):
		junk_props += 1
		if not (n as Node3D).find_children("*", "CollisionShape3D", true, false).is_empty():
			junk_with_collider += 1
	var yard_fence_e: bool = false
	for n in level.find_children("Fence_*", "Node3D", true, false):
		var fn := n as Node3D
		if absf(fn.rotation_degrees.y) < 1.0 and absf(fn.position.x - 31.0) < 0.6 \
				and fn.position.z > -54.5 and fn.position.z < -43.5:
			yard_fence_e = true
	print("R4_YARD key=", key_pickup != null,
		" key_pos=", key_pickup.global_position.round() if key_pickup else "-",
		" bench=", level.find_children("Yard_E5_Bench*", "Node3D", true, false).size() > 0,
		" junk_props=", junk_props, " junk_colliders=", junk_with_collider,
		" yard_fence_x31=", yard_fence_e)
	# —— R5 篮球架归位（北端居中面朝南）——
	for n in level.find_children("Prop_basket_hoop_*", "Node3D", true, false):
		var hp := n as Node3D
		print("R5_HOOP pos=", hp.global_position.round(),
			" rot_y=", snappedf(hp.rotation_degrees.y, 1), "(期望 (-23.25,-65) rot 0 面朝南)")
	# —— R6 验收截图（street_playable 移除了 OverviewCamera → 自建临时相机）——
	var cam := Camera3D.new()
	level.add_child(cam)
	cam.make_current()
	var shots := [["r3_court_owner_view", Vector3(-21.5, 1.7, -56.0), Vector3(-23.25, 2.8, -65.0)],
		["r3_court_west_fence", Vector3(-23.0, 1.7, -59.0), Vector3(-27.2, 1.5, -59.0)],
		["r3_yard_from_door", Vector3(17.0, 1.7, -49.0), Vector3(26.0, 1.0, -49.0)],
		["r3_yard_bench_key", Vector3(19.5, 1.6, -50.5), Vector3(17.35, 1.2, -51.8)],
		["r3_garage_rear_door", Vector3(13.0, 1.6, -49.0), Vector3(16.35, 1.2, -49.0)],
		["r3_wb_mouth_fixed", Vector3(-1.2, 1.7, -55.2), Vector3(-5.8, 1.0, -59.5)]]
	for s in shots:
		cam.position = s[1]
		cam.look_at(s[2])
		for i in 3:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(OUT + String(s[0]) + ".png")
		print("R6_SHOT ", s[0])
	print("R6_DONE")
	quit()
