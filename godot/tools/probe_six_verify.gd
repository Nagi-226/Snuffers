## 2026-10-25 六项整改综合验证（数据断言 + 验收截图）：
## V1 门A/门B 新位与链路  V2 被替换尽头栏移除+门垛在位  V3 三处窄槽补栏
## V4 E5 车库+后门+后院+驻军  V5 车缝（车宽矫正+自行车纵停）通过性
## V6 钥匙院扩充（钥匙/补给/返回锚点）  V7 EB 巷新东端栏  V8 验收截图
## ⚠️ 2026-10-25 三轮整改后本探针过时（V1/V2/V5/V6 断言已反转：门A已拆、
## 球场西端栏复位、车模不压扁改移位、钥匙移入 E5 后院）——续用 probe_round3.gd
extends SceneTree

const OUT := "C:/Users/FJL03/AppData/Local/Temp/snuff_shots/"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level: Node3D = load("res://scenes/levels/street_playable.tscn").instantiate()
	root.add_child(level)
	for i in 30:
		await process_frame
	# —— V1 门 A/B 新位与链路 ——
	for link in level.find_children("Link_*", "Node3D", true, false):
		print("V1_LINK ", link.name, " pos=", (link as Node3D).global_position.round(),
			" target=", link.get("target_scene"), " key=", link.get("requires_key"),
			" rot=", snappedf((link as Node3D).rotation_degrees.y, 1))
	# —— V2 尽头栏移除 + 门垛在位 ——
	var old_e: bool = false
	var old_c: bool = false
	for n in level.find_children("Fence_*", "Node3D", true, false):
		var fn := n as Node3D
		if absf(fn.rotation_degrees.y) < 1.0 and absf(fn.position.x - 22.0) < 0.35 \
				and absf(fn.position.z - 5.0) < 2.0:
			old_e = true
		if absf(fn.rotation_degrees.y) < 1.0 and absf(fn.position.x - (-27.0)) < 0.35 \
				and absf(fn.position.z - (-59.0)) < 2.0:
			old_c = true
	var pier_b: int = 0
	var pier_a: int = 0
	for n in level.find_children("*", "Node3D", true, false):
		var nm: String = n.name
		if nm.begins_with("BGatePier"):
			pier_b += 1
		if nm.begins_with("AGatePier"):
			pier_a += 1
	print("V2_GATE fence_220_50_removed=", not old_e, " fence_-270_-590_removed=", not old_c,
		" bgate_piers=", pier_b, " agate_piers=", pier_a)
	# —— V3 三处窄槽补栏 ——
	for slot in [[6.5, -72.5], [6.5, -85.5], [-6.5, -44.5]]:
		var found: bool = false
		for n in level.find_children("Fence_*", "Node3D", true, false):
			var fn := n as Node3D
			if absf(fn.rotation_degrees.y) < 1.0 and absf(fn.position.x - slot[0]) < 0.35 \
					and absf(fn.position.z - slot[1]) < 1.2:
				found = true
				break
		print("V3_SLOTFENCE x=", slot[0], " z=", slot[1], " present=", found)
	# —— V4 E5 车库/后门/后院/驻军 ——
	var gar_e5: int = 0
	var yard_e5: int = 0
	for n in level.find_children("*", "Node3D", true, false):
		var nm: String = n.name
		if nm.begins_with("Gar_E5"):
			gar_e5 += 1
		if nm.begins_with("Yard_E5"):
			yard_e5 += 1
	var gy: Node = null
	for e in level.get_tree().get_nodes_in_group(&"enemy"):
		if String((e as Node).name) == "Host_GY1":
			gy = e
	print("V4_E5GARAGE parts=", gar_e5, " rear_wall_split=", null != level.find_children("Gar_E5_WallE_N*", "Node3D", true, false).pop_front(),
		" yard_parts=", yard_e5, " Host_GY1=", gy != null)
	# —— V5 车缝：车宽矫正 + 自行车纵停 + 通过性 ——
	for n in level.find_children("Prop_car_stationwagon_17*", "Node3D", true, false):
		for cs in (n as Node3D).find_children("*", "CollisionShape3D", true, false):
			if (cs as CollisionShape3D).shape is BoxShape3D:
				var bs: BoxShape3D = (cs as CollisionShape3D).shape
				var c: Vector3 = (cs as Node3D).global_position
				print("V5_WAGON center=", c.round(), " xspan=", snappedf(bs.size.x * 0.88, 0.1),
					"(期望≤2.5)")
	for n in level.find_children("Prop_bike_8*", "Node3D", true, false):
		for cs in (n as Node3D).find_children("*", "CollisionShape3D", true, false):
			if (cs as CollisionShape3D).shape is BoxShape3D:
				var bs: BoxShape3D = (cs as CollisionShape3D).shape
				var c: Vector3 = (cs as Node3D).global_position
				print("V5_BIKE center=", c.round(), " xw=", snappedf(bs.size.x, 0.1),
					" zl=", snappedf(bs.size.z, 0.1), "(期望横窄纵长)")
	# 巷口通过性：玩家胶囊扫过 z -61.2..-58.6 × x -6.5..-4.5 的进门走廊
	var ps := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 1.7
	ps.shape = cap
	ps.collision_mask = 0xFFFF
	var free_cells: int = 0
	var blocked_cells: int = 0
	var blockers := {}
	var x: float = -6.5
	while x < -4.5:
		var z: float = -61.2
		while z < -58.4:
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
	print("V5_CORRIDOR free=", free_cells, " blocked=", blocked_cells, " blockers=", blockers)
	# —— V6 钥匙院 ——
	var yard: Node3D = load("res://scenes/levels/alley_next.tscn").instantiate()
	root.add_child(yard)
	await process_frame
	var ret: Node = yard.get_node_or_null("Link_AlleyReturn")
	print("V6_YARD key=", yard.get_node_or_null("GateKeyPickup") != null,
		" battery=", yard.get_node_or_null("Pickup_battery") != null,
		" medkit=", yard.get_node_or_null("Pickup_medkit") != null,
		" return_target=", ret.get("target_anchor") if ret != null else "-",
		" bench=", yard.get_node_or_null("Shed_Bench") != null)
	yard.queue_free()
	# —— V7 EB 巷新东端栏（x=16.5）——
	var eb_fence: bool = false
	for n in level.find_children("Fence_*", "Node3D", true, false):
		var fn := n as Node3D
		if absf(fn.rotation_degrees.y) < 1.0 and absf(fn.position.x - 16.5) < 0.35 \
				and fn.position.z > -60.5 and fn.position.z < -53.5:
			eb_fence = true
	print("V7_EB_END_FENCE present=", eb_fence)
	# —— V8 验收截图（street_playable 移除了 OverviewCamera → 自建临时相机）——
	var cam := Camera3D.new()
	level.add_child(cam)
	cam.make_current()
	var shots := [["gateB_alley_end", Vector3(18, 1.7, 5), Vector3(22.2, 1.6, 5)],
		["gateA_court", Vector3(-23, 1.7, -59), Vector3(-27.2, 1.5, -59)],
		["e5_garage", Vector3(2, 1.7, -49), Vector3(11.5, 2.0, -49)],
		["e5_yard", Vector3(17.5, 1.7, -45), Vector3(22.0, 1.2, -50)],
		["wb_gap_fixed", Vector3(-1.2, 1.7, -55.2), Vector3(-5.8, 1.0, -59.5)],
		["slot_E6E7_sealed", Vector3(4, 1.6, -72.5), Vector3(16, 1.6, -72.5)]]
	for s in shots:
		cam.position = s[1]
		cam.look_at(s[2])
		for i in 3:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(OUT + String(s[0]) + ".png")
		print("V8_SHOT ", s[0])
	print("V8_DONE")
	quit()
