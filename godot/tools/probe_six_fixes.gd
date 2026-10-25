## 2026-10-25 六项整改取证探针：
## A. 全量围挡线位（栅栏/砖墙：轴/线位/起止）——定位东侧flank巷与各巷尽头栅栏
## B. 场景门组件（门A/门B/SceneLink 目标）——错位门取证
## C. 全部敌人 vs 静态几何嵌入检测（墙里敌人取证）+ 背景填充块碰撞体有无
## D. 自行车/汽车缝隙玩家胶囊通过性扫描（WB/EB 两巷口）——空气墙根因
## E. E3 车库结构参照（门B 重定位用）
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _fence_extent(holder: Node3D) -> float:
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh is BoxMesh:
			return (mesh as BoxMesh).size.z
	return 0.0


func _run() -> void:
	var level: Node3D = load("res://scenes/levels/street_playable.tscn").instantiate()
	root.add_child(level)
	for i in 30:
		await process_frame

	# —— A. 围挡全量（Barriers 行下 Fence_/Wall_）——
	print("=== A_FENCES ===")
	for n in level.find_children("Fence_*", "Node3D", true, false):
		var h := n as Node3D
		if h.get_parent() == null or not String(h.get_parent().name).begins_with("Barrier"):
			continue
		var length: float = _fence_extent(h)
		var rot: bool = absf(h.rotation_degrees.y) > 45.0
		if rot:  # axis=1 沿X：holder=(mid,0,line)
			print("A_FENCE ", h.name, " axis=X line_z=", snappedf(h.position.z, 0.1),
				" x ", snappedf(h.position.x - length * 0.5, 0.1), "..", snappedf(h.position.x + length * 0.5, 0.1))
		else:     # axis=0 沿Z：holder=(line,0,mid)
			print("A_FENCE ", h.name, " axis=Z line_x=", snappedf(h.position.x, 0.1),
				" z ", snappedf(h.position.z - length * 0.5, 0.1), "..", snappedf(h.position.z + length * 0.5, 0.1))
	for n in level.find_children("Wall_*", "Node3D", true, false):
		var h := n as Node3D
		if h.get_parent() == null or not String(h.get_parent().name).begins_with("Barrier"):
			continue
		var bs: BoxShape3D = null
		for cs in h.find_children("*", "CollisionShape3D", true, false):
			if (cs as CollisionShape3D).shape is BoxShape3D:
				bs = (cs as CollisionShape3D).shape
				break
		if bs == null:
			continue
		var rot: bool = bs.size.x > bs.size.z
		if rot:
			print("A_WALL ", h.name, " axis=X line_z=", snappedf(h.position.z, 0.1),
				" x ", snappedf(h.position.x - bs.size.x * 0.5, 0.1), "..", snappedf(h.position.x + bs.size.x * 0.5, 0.1))
		else:
			print("A_WALL ", h.name, " axis=Z line_x=", snappedf(h.position.x, 0.1),
				" z ", snappedf(h.position.z - bs.size.z * 0.5, 0.1), "..", snappedf(h.position.z + bs.size.z * 0.5, 0.1))

	# —— B. 场景门组件 ——
	print("=== B_GATES ===")
	for link in level.find_children("Link_*", "Node3D", true, false):
		print("B_LINK ", link.name, " pos=", (link as Node3D).global_position.round(),
			" target=", link.get("target_scene"), " anchor=", link.get("anchor_id"),
			" key=", link.get("requires_key"))
	for n in level.find_children("*", "Node3D", true, false):
		var nm: String = n.name
		if nm.begins_with("GatePost") or nm.begins_with("GateBeam") or nm.begins_with("GateDoor") \
				or nm.begins_with("BGate"):
			print("B_GATEPART ", nm, " pos=", (n as Node3D).global_position.round())

	# —— C. 敌人 vs 静态几何 ——
	print("=== C_ENEMIES ===")
	var ps := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.30
	cap.height = 1.6
	ps.shape = cap
	ps.collide_with_bodies = true
	ps.collision_mask = 0xFFFF  # 全层，含静态与道具
	for e in level.get_tree().get_nodes_in_group(&"enemy"):
		var en := e as Node3D
		if en == null:
			continue
		ps.transform = Transform3D(Basis(), en.global_position + Vector3(0, 0.8, 0))
		ps.exclude = []
		if en is CollisionObject3D:
			var rid: RID = (en as CollisionObject3D).get_rid()
			ps.exclude = [rid]
		var hits: Array = level.get_world_3d().direct_space_state.intersect_shape(ps, 16)
		var embeds: Array = []
		for hit in hits:
			var col := hit["collider"] as Node
			if col == null or col.is_ancestor_of(en) or en.is_ancestor_of(col):
				continue
			var chain: String = col.name
			var p: Node = col.get_parent()
			for k in 2:
				if p == null:
					break
				chain = String(p.name) + "/" + chain
				p = p.get_parent()
			embeds.append(chain)
		print("C_ENEMY ", en.name, " pos=", en.global_position.round(),
			" embedded=", not embeds.is_empty(), " hit=", embeds.slice(0, 3))

	# —— C2. 背景填充块有无碰撞体 ——
	var backdrop: Node = level.find_children("Backdrop*", "Node3D", true, false).pop_front()
	var block_count: int = 0
	var block_colliders: int = 0
	if backdrop != null:
		for c in backdrop.get_children():
			block_count += 1
			if not c.find_children("*", "CollisionShape3D", true, false).is_empty():
				block_colliders += 1
	print("C_BACKFILL blocks=", block_count, " with_collider=", block_colliders)

	# —— D. 巷口通过性扫描（玩家胶囊 r0.33；WB 西巷口/EB 东巷口）——
	print("=== D_GAP_SWEEP ===")
	var pps := PhysicsShapeQueryParameters3D.new()
	var pcap := CapsuleShape3D.new()
	pcap.radius = 0.33
	pcap.height = 1.7
	pps.shape = pcap
	pps.collision_mask = 0xFFFF
	var zones := {
		"WB_mouth_west": Rect2(-9.5, -64.0, 7.0, 10.0),   # x -9.5..-2.5, z -64..-54
		"EB_mouth_east": Rect2(2.5, -64.0, 7.0, 10.0),    # x 2.5..9.5, z -64..-54
	}
	for zname in zones:
		var zr: Rect2 = zones[zname]
		var blocked_cells: int = 0
		var blockers := {}
		var x: float = zr.position.x
		while x < zr.end.x:
			var z: float = zr.position.y
			while z < zr.end.y:
				pps.transform = Transform3D(Basis(), Vector3(x, 0.95, z))
				var hs: Array = level.get_world_3d().direct_space_state.intersect_shape(pps, 16)
				var names: Array = []
				for hit in hs:
					var col := hit["collider"] as Node
					if col == null:
						continue
					var top: String = String(col.name)
					var par: Node = col.get_parent()
					if par != null:
						top = String(par.name) + "/" + top
					names.append(top)
				if not names.is_empty():
					blocked_cells += 1
					for nm2 in names:
						blockers[nm2] = blockers.get(nm2, 0) + 1
				z += 0.5
			x += 0.5
		print("D_ZONE ", zname, " blocked_cells=", blocked_cells)
		var bk: Array = blockers.keys()
		bk.sort_custom(func(a, b): return blockers[b] > blockers[a])
		for nm3 in bk.slice(0, 12):
			print("D_BLOCKER ", zname, " ", nm3, " x", blockers[nm3])

	# —— E. E3 车库参照 + 东侧 flank 巷尽头的可达性 ——
	print("=== E_GARAGE ===")
	for n in level.find_children("Gar_E3*", "Node3D", true, false):
		print("E_GAR ", n.name, " pos=", (n as Node3D).global_position.round())
	quit()
