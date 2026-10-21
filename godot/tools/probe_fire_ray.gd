extends SceneTree
## probe_fire_ray.gd — 开火复核射线几何验证（2026-10-21）
## 复刻 infantry._fire_ray_clear 的查询（Eye→玩家胸口 +1.2m，排除自身与玩家），
## 验证「隔墙敌人 ray=blocked / 开阔敌人 ray=clear」。用法：
##   godot --headless --path godot --script tools/probe_fire_ray.gd

var _frames := 0


func _init() -> void:
	var scene: Node = load("res://scenes/levels/street_playable.tscn").instantiate()
	root.add_child(scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 30:
		return false
	var player := root.find_child("Player", true, false) as Node3D
	var chest: Vector3 = (player.global_position if player != null else Vector3.ZERO) + Vector3(0.0, 1.2, 0.0)
	print("PROBE chest=", chest)
	var enemies: Array[Node] = []
	for e0: Node in get_nodes_in_group(&"enemy"):
		enemies.append(e0)
	if enemies.is_empty():
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
		var eye := e3d.get_node_or_null("Eye") as Marker3D
		var from: Vector3 = eye.global_position if eye != null else e3d.global_position
		var dist := from.distance_to(chest)
		var query := PhysicsRayQueryParameters3D.create(from, chest)
		query.exclude = [e3d.get_rid()]
		if player is CollisionObject3D:
			query.exclude.append((player as CollisionObject3D).get_rid())
		var hit := e3d.get_world_3d().direct_space_state.intersect_ray(query)
		var clear := hit.is_empty()
		var block := "-"
		if not clear:
			var col: Variant = hit.get("collider")
			clear = from.distance_to(hit["position"]) > dist - 0.5
			block = str(col.name) if col != null else "?"
		print("PROBE %s dist=%.1f fire_ray_clear=%s block=%s" % [e3d.name, dist, clear, block])
	return true
