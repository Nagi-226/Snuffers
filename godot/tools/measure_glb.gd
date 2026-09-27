extends SceneTree
## 测量 GLB 模型包围盒（道具缩放定标用）
## 用法: godot --headless --path . --script tools/measure_glb.gd

func _initialize() -> void:
	for path in ["res://assets/models/prop_basketball_hoop.glb", "res://assets/models/prop_bicycle.glb"]:
		var scene: PackedScene = load(path)
		if not scene:
			print(path, " LOAD FAIL")
			continue
		var inst: Node3D = scene.instantiate()
		var aabb := _combined_aabb(inst)
		print(path, " aabb_pos=", aabb.position, " size=", aabb.size)
	quit()

func _combined_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	if n is VisualInstance3D:
		out = n.get_aabb()
		first = false
	for c in n.get_children():
		var child_aabb := _combined_aabb(c)
		if child_aabb.size == Vector3.ZERO:
			continue
		# 子节点局部变换应用到包围盒（简化：仅处理 position，poly.pizza 模型通常无复杂变换）
		child_aabb.position += (c as Node3D).position if c is Node3D else Vector3.ZERO
		if first:
			out = child_aabb
			first = false
		else:
			out = out.merge(child_aabb)
	return out
