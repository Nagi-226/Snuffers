extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for id in [&"spas12", &"em120r"]:
		root.get_node("GameState").current_weapon = id
		var weapon = (load("res://scenes/weapons/%s.tscn" % id) as PackedScene).instantiate()
		root.add_child(weapon)
		await process_frame
		weapon.set_process(false)
		weapon.set_physics_process(false)
		var gun: Node3D = weapon._weapon_node
		print("SPECIAL_GEOMETRY ", id, " gun=", gun.transform)
		for node in gun.find_children("*", "Skeleton3D", true, false):
			var skeleton := node as Skeleton3D
			for bone in skeleton.get_bone_count():
				print("SPECIAL_GUN_BONE ", id, " ", skeleton.get_bone_name(bone), "=", skeleton.get_bone_global_pose(bone))
		for node in gun.find_children("*", "MeshInstance3D", true, false):
			var instance := node as MeshInstance3D
			var mesh: Mesh = instance.mesh
			if mesh == null:
				continue
			if instance.get_skin_reference() != null:
				mesh = instance.bake_mesh_from_current_skeleton_pose()
			var transform := gun.global_transform.affine_inverse() * instance.global_transform
			var bounds := AABB()
			var count := 0
			var points: Array[Vector3] = []
			var all_points: Array[Vector3] = []
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for vertex in vertices:
					var point := transform * vertex
					all_points.append(point)
					bounds = bounds.expand(point) if count else AABB(point, Vector3.ZERO)
					count += 1
					if point.y < -0.10 and point.z > 0.1 and point.z < 0.3:
						points.append(point)
			print("MESH ", id, " ", gun.get_path_to(instance), " bound=", bounds, " count=", count)
			if not points.is_empty():
				var nearest := points[0]
				var sample := Vector3(0.08, -0.18, 0.21)
				for point in points:
					if point.distance_squared_to(sample) < nearest.distance_squared_to(sample):
						nearest = point
				print("RIGHT_HANDLE_SURFACE ", id, " ", gun.get_path_to(instance), "=", nearest)
			if id in [&"spas12", &"em120r"]:
				var samples := [Vector3(0.01, -0.02, -0.35), Vector3(0.05, 0.015, -0.06)] if id == &"spas12" else [Vector3(-0.095, -0.10, -0.28)]
				for sample in samples:
					var nearest := all_points[0]
					for point in all_points:
						if point.distance_squared_to(sample) < nearest.distance_squared_to(sample):
							nearest = point
					print("SPECIAL_CONTACT_SAMPLE ", id, " ", gun.get_path_to(instance), " target=", sample, " nearest=", nearest)
		weapon.queue_free()
		await process_frame
	quit()
