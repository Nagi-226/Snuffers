## 2026-10-25 四项交付综合验证探针（开发取证）：
## ①咖啡馆椅朝向 ②道具碰撞收缩比 ③E3 车库结构与驻军 ④坚固门B/钥匙链。
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# —— 主街：①②③④ ——
	var level: Node3D = load("res://scenes/levels/street_playable.tscn").instantiate()
	root.add_child(level)
	for i in 25:
		await process_frame
	# ① 咖啡馆椅朝向（负 X 椅应 rot 90°=面向 +X 桌）
	for n in level.find_children("BistroChair_*", "Node3D", true, false):
		var c := n as Node3D
		var facing: float = c.rotation_degrees.y
		var toward_table: bool = (c.position.x < 0.0 and absf(facing - 90.0) < 1.0) \
			or (c.position.x > 0.0 and absf(facing + 90.0) < 1.0)
		print("V1_CHAIR ", c.name, " rot=", snappedf(facing, 1.0), " 面向桌=", toward_table)
	# ② 碰撞收缩比（抽样：自行车/汽车 box 应 ≈ mesh×0.88）
	for n in level.find_children("Prop_*", "Node3D", true, false):
		var nm: String = n.name
		if not (nm.contains("bike") or nm.contains("car")):
			continue
		var prop := n as Node3D
		var shapes: Array = prop.find_children("*", "CollisionShape3D", true, false)
		var mesh_aabb := AABB()
		var first := true
		for mi in prop.find_children("*", "MeshInstance3D", true, false):
			var a: AABB = (prop.global_transform.affine_inverse() * (mi as Node3D).global_transform) * (mi as MeshInstance3D).get_aabb()
			if first: mesh_aabb = a; first = false
			else: mesh_aabb = mesh_aabb.merge(a)
		if not shapes.is_empty() and shapes[0].shape is BoxShape3D and not first:
			var bs: Vector3 = (shapes[0].shape as BoxShape3D).size
			var ratio: float = (bs.x / mesh_aabb.size.x + bs.z / mesh_aabb.size.z) * 0.5
			print("V2_COLLIDE ", n.name, " 收缩比=", snappedf(ratio, 0.01), " box=", bs.round(), " mesh=", mesh_aabb.size.round())
	# ③ E3 车库结构 + 驻军
	var garage_parts: int = 0
	for n in level.find_children("*", "Node3D", true, false):
		if String(n.name).begins_with("Gar_E3"):
			garage_parts += 1
	print("V3_GARAGE parts=", garage_parts)
	var host_g1: Node = null
	for n in level.get_tree().get_nodes_in_group(&"enemy"):
		if String((n as Node).name) == "Host_G1":
			host_g1 = n
	print("V3_GARAGE Host_G1=", host_g1 != null,
		" pos=", (host_g1 as Node3D).global_position.round() if host_g1 != null else "-")
	# ④ 门 B 结构 + 钥匙链组件
	var bgate: int = 0
	for n in level.find_children("*", "Node3D", true, false):
		var nm2: String = n.name
		if nm2.begins_with("BGate"):
			bgate += 1
	print("V4_BGate parts=", bgate)
	var link_b: Node = level.get_node_or_null("StreetBuilder/SceneGate/Link_BGate_E")
	print("V4_BGate link=", link_b != null, " requires_key=", link_b.get("requires_key") if link_b != null else "-")
	var key_scene: PackedScene = load("res://scenes/levels/alley_next.tscn")
	var dist_scene: PackedScene = load("res://scenes/levels/district_b.tscn")
	print("V4_KEY alley_next=", key_scene != null, " district_b=", dist_scene != null)
	# —— 钥匙院：钥匙拾取体存在 ——
	var yard: Node3D = key_scene.instantiate()
	root.add_child(yard)
	await process_frame
	print("V4_KEY pickup=", yard.get_node_or_null("GateKeyPickup") != null)
	yard.queue_free()
	quit()
