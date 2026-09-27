extends SceneTree
## 无头布局校验：实例化 street_test，打印关键节点位置与包围盒。
## 用法: godot --headless --path . --script tools/dump_street_layout.gd

var _frame := 0
var _root: Node3D

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/levels/street_test.tscn")
	_root = scene.instantiate()
	get_root().add_child.call_deferred(_root)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 5:
		return false
	print("=== STREET LAYOUT DUMP ===")
	_walk(_root, 0)
	print("=== END ===")
	return true  # 退出

func _walk(n: Node, depth: int) -> void:
	if depth > 3:
		return
	var interesting := depth <= 1 or n is StaticBody3D
	if n.name in ["Ground", "Buildings", "Wires", "Skyline", "Props"]:
		interesting = true
	if interesting and n is Node3D:
		var info := "%s[%s] %s pos=(%.1f, %.1f, %.1f)" % [
			"  ".repeat(depth), n.get_class(), n.name,
			n.position.x, n.position.y, n.position.z]
		if n is MeshInstance3D and n.mesh:
			var aabb: AABB = n.mesh.get_aabb()
			info += " size=(%.1f, %.1f, %.1f)" % [aabb.size.x, aabb.size.y, aabb.size.z]
		if n is CollisionShape3D and n.shape is BoxShape3D:
			info += " box=(%.1f, %.1f, %.1f)" % [n.shape.size.x, n.shape.size.y, n.shape.size.z]
		print(info)
	for c in n.get_children():
		_walk(c, depth + 1)
