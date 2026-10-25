## 2026-10-25 自行车/汽车缝隙精测（机主图3 二轮报修：12% 收缩后仍被空气墙挡）：
## ① 自行车/旅行车/人行道碰撞体精确尺寸与位置
## ② WB 巷口走廊网格扫描（胶囊 y=1.0 站立高度；过滤地面/人行道踏面，只报「墙」）
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level: Node3D = load("res://scenes/levels/street_playable.tscn").instantiate()
	root.add_child(level)
	for i in 30:
		await process_frame
	# ① 精确碰撞体
	for n in level.find_children("Prop_*", "Node3D", true, false):
		var nm: String = n.name
		if not (nm.contains("bike") or nm.contains("stationwagon")):
			continue
		var prop := n as Node3D
		for cs in prop.find_children("*", "CollisionShape3D", true, false):
			var sh: Shape3D = (cs as CollisionShape3D).shape
			if sh is BoxShape3D:
				var world_c: Vector3 = (cs as Node3D).global_position
				var s: Vector3 = (sh as BoxShape3D).size
				# 旋转 90° 后盒体沿轴交换（仅报 XZ 占位）
				var rotated: bool = absf(absf(prop.rotation_degrees.y) - 90.0) < 5.0
				var sx: float = (s.z if rotated else s.x)
				var sz: float = (s.x if rotated else s.z)
				print("G1_COLLIDER ", nm, " center=(", snappedf(world_c.x, 0.01), ",",
					snappedf(world_c.z, 0.01), ") xspan=", snappedf(world_c.x - sx * 0.5, 0.02), "..",
					snappedf(world_c.x + sx * 0.5, 0.02), " zspan=", snappedf(world_c.z - sz * 0.5, 0.02), "..",
					snappedf(world_c.z + sz * 0.5, 0.02), " h=", snappedf(s.y, 0.02))
	# 人行道碰撞体（验踏面高度，非墙）
	for n in level.find_children("Sidewalk_*", "Node3D", true, false):
		for cs in (n as Node3D).find_children("*", "CollisionShape3D", true, false):
			var sh: Shape3D = (cs as CollisionShape3D).shape
			if sh is BoxShape3D:
				var s: Vector3 = (sh as BoxShape3D).size
				var c: Vector3 = (cs as Node3D).global_position
				print("G1_SIDEWALK ", n.name, " top_y=", snappedf(c.y + s.y * 0.5, 0.03),
					" bottom_y=", snappedf(c.y - s.y * 0.5, 0.03))
	# ② 走廊扫描（WB 巷口：x -7.5..-2.5 × z -63..-55，0.25 步进）
	var ps := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 1.7
	ps.shape = cap
	ps.collision_mask = 0xFFFF
	var blockers := {}
	var blocked_cells: int = 0
	var x: float = -7.5
	while x < -2.5:
		var z: float = -63.0
		while z < -55.0:
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
				# 过滤地面系统（踏面/路面——不是墙）
				if chain.contains("Ground") or chain.contains("Sidewalk"):
					continue
				names.append(chain)
			if not names.is_empty():
				blocked_cells += 1
				for nm2 in names:
					blockers[nm2] = blockers.get(nm2, 0) + 1
				print("G2_CELL x=", snappedf(x, 0.25), " z=", snappedf(z, 0.25), " blocked_by=", names)
			z += 0.25
		x += 0.25
	print("G2_TOTAL blocked=", blocked_cells)
	quit()
