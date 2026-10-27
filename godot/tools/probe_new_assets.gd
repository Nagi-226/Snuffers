extends SceneTree

const PATHS := [
	"res://assets/models/weapons/em68d_viewmodel.glb",
	"res://assets/models/weapons/em12g1_viewmodel.glb",
	"res://assets/models/vehicles/jb02_apc.glb",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for path in PATHS:
		var inst := (load(path) as PackedScene).instantiate() as Node3D
		root.add_child(inst)
		var bounds := AABB()
		var first := true
		for mi in _meshes(inst):
			var wa: AABB = (inst.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
			bounds = wa if first else bounds.merge(wa)
			first = false
			print("MESH ", path, " name=", mi.name, " resource=", mi.mesh.resource_name,
				" size=", wa.size, " center=", wa.get_center(), " materials=", mi.mesh.get_surface_count())
		print("ASSET ", path, " bounds=", bounds, " nodes=", _nodes(inst).size())
		for n in _nodes(inst):
			print("NODE ", n.get_path(), " type=", n.get_class())
		inst.free()
	quit()


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _nodes(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_nodes(c))
	return out
