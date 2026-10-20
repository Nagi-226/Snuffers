extends SceneTree
## probe_los.gd — 敌人隔墙索敌确诊探针（2026-10-20）
## 实例化 street_playable 真实场景，30 帧物理稳定后逐个敌人打印：
## 距离 / LOS 射线结果 / 若被挡则命中物名称。用法：
##   godot --headless --path godot --script tools/probe_los.gd

var _frames := 0


func _init() -> void:
	var scene: Node = load("res://scenes/levels/street_playable.tscn").instantiate()
	root.add_child(scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 30:
		return false
	var player := root.find_child("Player", true, false) as Node3D
	var ppos: Vector3 = player.global_position if player != null else Vector3.ZERO
	print("PROBE player_pos=", ppos)
	var enemies: Array[Node] = []
	for e0: Node in get_nodes_in_group(&"enemy"):
		enemies.append(e0)
	if enemies.is_empty():
		# 探针环境 autoload 缺席 → 敌人脚本未加载 → group 为空；退化为按名字收集
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			if String(n.name).begins_with("Host"):
				enemies.append(n)
	for e: Node in enemies:
		var e3d := e as Node3D
		if e3d == null:
			continue
		var dist := e3d.global_position.distance_to(ppos)
		var eye := e3d.get_node_or_null("Eye") as Marker3D
		var from: Vector3 = eye.global_position if eye != null else e3d.global_position
		var query := PhysicsRayQueryParameters3D.create(from, ppos)
		query.exclude = [e3d.get_rid()]
		if player is CollisionObject3D:
			query.exclude.append((player as CollisionObject3D).get_rid())
		var hit := e3d.get_world_3d().direct_space_state.intersect_ray(query)
		var los := hit.is_empty()
		var hit_name := "-"
		if not los:
			var col: Variant = hit.get("collider")
			hit_name = str(col.name) if col != null else "?"
			var hd: float = from.distance_to(hit["position"])
			var td: float = from.distance_to(ppos)
			los = hd > td - 0.5
			hit_name += " hd=%.1f td=%.1f" % [hd, td]
		print("PROBE %s dist=%.1f los=%s block=%s" % [e3d.name, dist, los, hit_name])
	return true
