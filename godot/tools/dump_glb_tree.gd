extends SceneTree
func _initialize() -> void:
	var s: PackedScene = load("res://assets/models/prop_basketball_hoop.glb")
	_walk(s.instantiate(), 0)
	quit()
func _walk(n: Node, d: int) -> void:
	var extra := ""
	if n is MeshInstance3D:
		extra = " aabb=" + str(n.get_aabb().size)
	print("  ".repeat(d) + n.name + extra)
	for c in n.get_children():
		_walk(c, d + 1)
