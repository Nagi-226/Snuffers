## Independent contact measurement from source vertex weights and current bone transforms.
extends RefCounted


static func palm_world(arms: Node3D, skeleton: Skeleton3D, side: String) -> Vector3:
	var names := ["L_wrist_04", "L_palm_017"] if side == "L" else ["R_wrist_028", "R_palm_041"]
	var total := Vector3.ZERO
	var count := 0
	for node in arms.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or mesh.skin == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var width: int = bones.size() / vertices.size()
			for vertex in vertices.size():
				var point := Vector3.ZERO
				var selected := 0.0
				for influence in width:
					var offset := vertex * width + influence
					var weight := weights[offset]
					if weight <= 0.0:
						continue
					var bind := bones[offset]
					var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind)) if mesh.skin.get_bind_name(bind) != &"" else mesh.skin.get_bind_bone(bind)
					point += (skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * vertices[vertex]) * weight
					if skeleton.get_bone_name(bone) in names:
						selected += weight
				if selected > 0.65:
					total += skeleton.global_transform * point
					count += 1
	return total / maxf(float(count), 1.0)


static func mesh_center(mesh: MeshInstance3D) -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var width: int = bones.size() / vertices.size() if not bones.is_empty() else 0
		for vertex in vertices.size():
			var point := vertices[vertex]
			if mesh.skin != null and skeleton != null and width > 0:
				point = Vector3.ZERO
				for influence in width:
					var offset := vertex * width + influence
					if weights[offset] <= 0.0:
						continue
					var bind := bones[offset]
					var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind)) if mesh.skin.get_bind_name(bind) != &"" else mesh.skin.get_bind_bone(bind)
					point += (skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * vertices[vertex]) * weights[offset]
				total += skeleton.global_transform * point
			else:
				total += mesh.global_transform * point
			count += 1
	return total / maxf(float(count), 1.0)
