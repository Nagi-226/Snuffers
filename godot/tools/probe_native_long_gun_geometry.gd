extends SceneTree

const WEAPONS := [&"rifle", &"dmr", &"shotgun", &"smg", &"lmg", &"em57s2", &"em86b", &"em86d", &"em86s", &"em86m", &"em12g2", &"em127g", &"em127m", &"em40t1"]
const RIGHT_RAYS := {
	&"rifle": Vector2(-0.09, 0.175), &"dmr": Vector2(-0.09, 0.25),
	&"shotgun": Vector2(-0.09, 0.15), &"smg": Vector2(-0.065, 0.13),
	&"lmg": Vector2(-0.09, 0.15), &"em57s2": Vector2(-0.065, 0.30),
	&"em86b": Vector2(-0.09, 0.20), &"em86d": Vector2(-0.065, 0.30),
	&"em86s": Vector2(-0.09, 0.30), &"em86m": Vector2(-0.09, 0.20),
	&"em12g2": Vector2(-0.09, 0.15), &"em127g": Vector2(-0.09, 0.30),
	&"em127m": Vector2(-0.09, 0.20), &"em40t1": Vector2(-0.115, 0.15),
}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var state = root.get_node("GameState")
	var candidates: Dictionary = {}
	for id in WEAPONS:
		var arguments := OS.get_cmdline_user_args()
		if not arguments.is_empty() and not arguments.has(String(id)):
			continue
		state.reset()
		state.current_weapon = id
		var weapon = (load("res://scenes/weapons/%s.tscn" % id) as PackedScene).instantiate()
		root.add_child(weapon)
		await process_frame
		weapon.set_process(false)
		weapon.set_physics_process(false)
		for frame in 24:
			weapon._process(1.0 / 60.0)
		var gun: Node3D = weapon._weapon_node
		var skeleton: Skeleton3D = weapon._arms_skeleton
		print("GEOMETRY ", id, " gun_home=", weapon._weapon_home, " magazine=", weapon._magazine.transform)
		var into_gun := gun.global_transform.affine_inverse()
		var left_search := Vector3(-0.05, -0.045, -0.17)
		if id in [&"dmr", &"em86d", &"em86s", &"em127g"]:
			left_search = Vector3(-0.05, -0.045, -0.14)
		elif id in [&"shotgun", &"em12g2"]:
			left_search = Vector3(-0.04, -0.05, -0.16)
		var left_surface := Vector3.ZERO
		var left_distance := INF
		var left_mesh := ""
		var right_surface: Variant = null
		var right_mesh := ""
		for prefix in ["Hand_R", "Hand_L", "R_wrist_028", "L_wrist_04"]:
			for bone in skeleton.get_bone_count():
				if skeleton.get_bone_name(bone).begins_with(prefix):
					print("  WRIST ", skeleton.get_bone_name(bone), "=", into_gun * skeleton.global_transform * skeleton.get_bone_global_pose(bone))
		for node in gun.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh.mesh == null:
				continue
			var transform := into_gun * mesh.global_transform
			var supply_mesh: bool = weapon._magazine.is_ancestor_of(mesh) or mesh == weapon._magazine
			var body_mesh := not supply_mesh and not String(mesh.name).to_lower().contains("optic")
			var bounds := AABB()
			var count := 0
			var lower_sections: Dictionary = {}
			for surface in mesh.mesh.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				if id == &"rifle":
					var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
					print("  TRIANGLE_FORMAT ", mesh.name, " surface=", surface, " primitive=", mesh.mesh.surface_get_primitive_type(surface), " vertices=", vertices.size(), " indices=", indices.size())
				for vertex in vertices:
					var point := transform * vertex
					bounds = bounds.expand(point) if count else AABB(point, Vector3.ZERO)
					count += 1
					if body_mesh and point.distance_squared_to(left_search) < left_distance:
						left_distance = point.distance_squared_to(left_search)
						left_surface = point
						left_mesh = String(gun.get_path_to(mesh))
					if id == &"rifle" and point.y < -0.04:
						var section := floori(point.z / 0.025)
						lower_sections[section] = minf(float(lower_sections.get(section, 0.0)), point.y)
			print("  MESH ", gun.get_path_to(mesh), "=", bounds, " vertices=", count)
			if not lower_sections.is_empty():
				print("  LOWER_BODY_SECTIONS ", gun.get_path_to(mesh), "=", lower_sections)
			if not supply_mesh:
				var ray: Vector2 = RIGHT_RAYS[id]
				var grip_hit = _right_surface(mesh, transform, ray.x, ray.y)
				if grip_hit != null and (right_surface == null or grip_hit.x > right_surface.x):
					right_surface = grip_hit
					right_mesh = String(gun.get_path_to(mesh))
				var hits: Array[String] = []
				var z_samples := [0.10, 0.15, 0.20, 0.25, 0.30, 0.35]
				if id == &"rifle":
					z_samples = [-0.05, 0.0, 0.05, 0.075, 0.10, 0.125, 0.15, 0.175, 0.20, 0.225, 0.25, 0.275, 0.30, 0.325, 0.35, 0.40, 0.45]
				for z in z_samples:
					for y in [-0.04, -0.065, -0.09, -0.115]:
						var hit = _right_surface(mesh, transform, y, z)
						if hit != null:
							hits.append(str(hit))
				if not hits.is_empty():
					print("  GRIP_SURFACE_SAMPLES ", gun.get_path_to(mesh), "=", ", ".join(hits))
		candidates[String(id)] = {
			"right_palm": [right_surface.x, right_surface.y, right_surface.z] if right_surface != null else [],
			"right_mesh": right_mesh,
			"left_support_hip": [left_surface.x, left_surface.y, left_surface.z],
			"left_support_ads": [left_surface.x, left_surface.y, left_surface.z],
			"left_mesh": left_mesh,
			"left_search_distance": sqrt(left_distance),
			"status": "real geometry candidates; native pose and visual contact still require validation",
		}
		print("CONTRACT_CANDIDATE ", id, "=", JSON.stringify(candidates[String(id)]))
		weapon.queue_free()
		await process_frame
	var native := (load("res://addons/community_weapons/black_pistol_arms.glb") as PackedScene).instantiate() as Node3D
	root.add_child(native)
	await process_frame
	var native_skeleton := native.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var animation := native.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation.play(&"idle")
	animation.seek(0.0, true)
	print("NATIVE_SKELETON_GLOBAL=", native_skeleton.global_transform)
	print("NATIVE_WEAPON_MOTION_GLOBAL=", (native.find_child("WeaponMotion", true, false) as Node3D).global_transform)
	for name in ["L_arm_02", "L_elbow_03", "L_wrist_04", "L_palm_017", "R_arm_026", "R_elbow_027", "R_wrist_028", "R_palm_041"]:
		print("NATIVE_BASE ", name, "=", native_skeleton.get_bone_global_pose(native_skeleton.find_bone(name)))
	var native_mesh: MeshInstance3D
	for child in native.find_children("*", "MeshInstance3D", true, false):
		if child.skin != null:
			native_mesh = child as MeshInstance3D
			break
	if native_mesh == null:
		push_error("native black arm skin missing")
		quit(1)
		return
	for hand in [["R_wrist_028", "R_palm_041"], ["L_wrist_04", "L_palm_017"]]:
		print("NATIVE_PALM_WRIST_OFFSET ", hand[0], "=", _palm_offset(native_mesh, native_skeleton, hand))
	native.queue_free()
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://tmp_shots")
	var output := FileAccess.open("res://tmp_shots/native_long_gun_geometry_candidates.json", FileAccess.WRITE)
	if output == null:
		push_error("cannot save native long gun geometry candidates")
		quit(1)
		return
	output.store_string(JSON.stringify({"units": "gun orthogonal axes in meters", "profiles": candidates}, "\t"))
	output.close()
	print("COMPLETED native long gun geometry")
	quit()


func _right_surface(mesh: MeshInstance3D, transform: Transform3D, y: float, z: float) -> Variant:
	var nearest: Variant = null
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var triangle_vertices := vertices.size() if indices.is_empty() else indices.size()
		for offset in range(0, triangle_vertices, 3):
			var a := transform * vertices[offset if indices.is_empty() else indices[offset]]
			var b := transform * vertices[offset + 1 if indices.is_empty() else indices[offset + 1]]
			var c := transform * vertices[offset + 2 if indices.is_empty() else indices[offset + 2]]
			# Godot's triangle parallel test uses an absolute determinant epsilon.
			# EM68A has over a million small faces; measure uniformly in centimeters
			# so real sub-millimeter faces are not mistaken for parallel triangles.
			var hit = Geometry3D.ray_intersects_triangle(Vector3(0.4, y, z) * 100.0, Vector3.LEFT, a * 100.0, b * 100.0, c * 100.0)
			if hit == null:
				hit = Geometry3D.ray_intersects_triangle(Vector3(0.4, y, z) * 100.0, Vector3.LEFT, a * 100.0, c * 100.0, b * 100.0)
			if hit != null:
				hit /= 100.0
			if hit != null and (nearest == null or hit.x > nearest.x):
				nearest = hit
	return nearest


func _palm_offset(mesh: MeshInstance3D, skeleton: Skeleton3D, names: Array) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	var wrist := skeleton.get_bone_global_pose(skeleton.find_bone(names[0])).affine_inverse()
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var width: int = bones.size() / vertices.size()
		for vertex in vertices.size():
			var position := Vector3.ZERO
			var palm_weight := 0.0
			for influence in width:
				var offset := vertex * width + influence
				if weights[offset] <= 0.0:
					continue
				var bind := bones[offset]
				var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind)) if mesh.skin.get_bind_name(bind) != &"" else mesh.skin.get_bind_bone(bind)
				position += (skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * vertices[vertex]) * weights[offset]
				if skeleton.get_bone_name(bone) in names:
					palm_weight += weights[offset]
			if palm_weight > 0.65:
				sum += wrist * position
				count += 1
	return sum / maxf(float(count), 1.0)
