## 背门洞视线遮挡取证（2026-10-25 机主报修：开门后能过但有无碰撞贴图挡视线）：
## O1 开门态洞口区网格清点（谁在洞口、有无碰撞祖先、来自哪个场景文件）
## O2 穿洞射线（有碰撞体才命中——假视觉件不命中=owner「能通过」的原因）
## O3 机主视角复现截图（库内朝洞看）
## 用法：godot -s tools/probe_rear_occluder.gd --path . --resolution 1280x720（窗口模式）
extends SceneTree

const OUT := "C:/Users/FJL03/AppData/Local/Temp/snuff_shots/"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level: Node3D = load("res://scenes/levels/street_playable.tscn").instantiate()
	root.add_child(level)
	for i in 30:
		await process_frame
	# 开门（door.gd interact；等 0.45s 动画走完）
	var door: Node = null
	for n in level.find_children("Gar_E5_RearDoor", "Node3D", true, false):
		door = n
	if door != null:
		door.call("interact")
	for i in 40:
		await process_frame
	print("O0_DOOR open_called=", door != null, " leaf_rot=",
		snappedf((door.get_node("Leaf") as Node3D).rotation_degrees.y, 1) if door else "-")
	# —— O2 穿洞射线：库内 (14.5,1.6,-49) → 院内 (19,1.6,-49) ——
	var space := level.get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(Vector3(14.5, 1.6, -49.0), Vector3(19.0, 1.6, -49.0))
	rq.collision_mask = 0xFFFF
	var hits := space.intersect_ray(rq)
	if hits.is_empty():
		print("O2_RAY no_hit（全程无碰撞体=洞口无实体，视觉件不拦射线）")
	else:
		for h in hits:
			var col := h["collider"] as Node
			var chain: String = String(col.name)
			var par: Node = col.get_parent()
			if par != null:
				chain = String(par.name) + "/" + chain
			print("O2_RAY hit=", chain, " pos=", (h["position"] as Vector3).round())
	# —— O1 洞口区网格清点：AABB 交 (x 15.1..17.7, y 0..2.4, z -50.3..-47.7) ——
	var hole := AABB(Vector3(15.1, 0.0, -50.3), Vector3(2.6, 2.4, 2.6))
	var found: int = 0
	for n in level.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var ab: AABB = mi.global_transform * mi.get_aabb()
		if not ab.intersects(hole):
			continue
		found += 1
		var src: String = ""
		var walk: Node = mi
		var has_col: bool = false
		while walk != null:
			if walk.scene_file_path != "":
				src = walk.scene_file_path.get_file()
				break
			if walk is PhysicsBody3D:
				has_col = true
				break
			walk = walk.get_parent()
		print("O1_MESH name=", mi.name, " src=", src if src != "" else "(程序化)",
			" col_ancestor=", has_col, " aabb_c=", ab.get_center().round(),
			" aabb_s=", ab.size.round())
	print("O1_TOTAL meshes_in_hole=", found)
	# —— O3 机主视角复现截图 ——
	var cam := Camera3D.new()
	level.add_child(cam)
	cam.make_current()
	cam.position = Vector3(13.8, 1.7, -49.0)
	cam.look_at(Vector3(17.5, 1.3, -49.0))
	for i in 3:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(OUT + "r4_rear_door_occluder.png")
	print("O3_SHOT saved")
	quit()
