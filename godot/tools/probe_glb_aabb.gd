extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	for path in ["res://assets/models/prop_car_stationwagon.glb",
			"res://assets/models/prop_car_compact.glb",
			"res://assets/models/prop_car_sedan.glb",
			"res://assets/models/prop_car_hatchback.glb",
			"res://assets/models/prop_bicycle.glb"]:
		if not ResourceLoader.exists(path):
			print("GLB missing ", path)
			continue
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(inst)
		var aabb := AABB()
		var first := true
		var parts: Array = []
		for mi in _find(inst):
			var mim := mi as MeshInstance3D
			var wa: AABB = (inst.global_transform.affine_inverse() * mim.global_transform) * mim.get_aabb()
			if first:
				aabb = wa; first = false
			else:
				aabb = aabb.merge(wa)
			parts.append([String(mim.name), wa.size, wa.get_center()])
		print("GLB ", path, " total_size=", aabb.size.snapped(Vector3(0.01, 0.01, 0.01)),
			" center=", aabb.get_center().snapped(Vector3(0.01, 0.01, 0.01)), " parts=", parts.size())
		for p in parts:
			print("  PART ", p[0], " size=", (p[1] as Vector3).snapped(Vector3(0.01, 0.01, 0.01)),
				" center=", (p[2] as Vector3).snapped(Vector3(0.01, 0.01, 0.01)))
		inst.free()
	quit()
func _find(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find(c))
	return out
