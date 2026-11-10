## 初始握柄验收：实际左右掌蒙皮和食指关节，不能用已保存腕点自证。
extends SceneTree

var _failures := 0
var _assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	await process_frame
	player.set_process(false)
	player.set_physics_process(false)
	for node in player.find_children("*", "Node", true, false):
		node.set_process(false)
		node.set_physics_process(false)
	for weapon_id in [&"pistol", &"magnum"]:
		var state = root.get_node("GameState")
		state.reset()
		state.weapon_unlocked[weapon_id] = true
		player._switch_weapon(weapon_id)
		var weapon = player.get_node("Camera3D/WeaponMount/" + ("Pistol" if weapon_id == &"pistol" else "Magnum"))
		for aiming in [false, true]:
			player._set_aiming(aiming)
			weapon._reset_reload_visuals()
			for frame in 30:
				player._process(1.0 / 60.0)
				weapon._process(0.0)
			_check_grip(weapon, weapon_id, "ADS" if aiming else "hip")
	player.queue_free()
	await process_frame
	print("BLACK_PISTOL_GRIP assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _check_grip(weapon: Node3D, weapon_id: StringName, mode: String) -> void:
	var label := "%s %s" % [weapon_id, mode]
	var gun: Node3D = weapon._weapon_node
	var skeleton: Skeleton3D = weapon._arms_skeleton
	var mesh := weapon.get_node("ViewModel/ArmsEM57P").find_child("BlackArmsMesh", true, false) as MeshInstance3D
	var palms := _palm_medians(mesh, skeleton, gun)
	_assert(palms.size() == 2, "%s measures both real weighted palm skins" % label)
	if palms.size() != 2:
		return
	var grip := _grip_bounds(gun, weapon_id)
	var scale_x := gun.global_basis.get_scale().x
	var center := grip.get_center().x * scale_x
	var right_side := grip.end.x * scale_x
	var left_side := grip.position.x * scale_x
	var right: Vector3 = palms[0]
	var left: Vector3 = palms[1]
	var finger: Vector3 = gun.global_basis.orthonormalized().inverse() * (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("R_point3_035")).origin - gun.global_position)
	print("GRIP_GEOMETRY ", label, " center=", center, " sides=", left_side, "/", right_side, " skin_palms=", left, "/", right, " finger=", finger, " suggested_anchor_x=", weapon._native_arms._profile.weapon_anchor.x + (center - (right.x + left.x) * 0.5) / scale_x)
	_assert(right.x > center and left.x < center, "%s actual palm skins straddle the grip instead of both sitting on its left" % label)
	_assert(absf((right.x + left.x) * 0.5 - center) < 0.006, "%s actual two-palm grasp center matches the mesh grip center within six millimeters" % label)
	_assert(absf(right.x - right_side) < 0.015 and absf(left.x - left_side) < 0.015, "%s actual palm skins contact their respective grip sides within glove thickness" % label)
	_assert(absf(finger.x - center) < 0.006, "%s trigger finger distal knuckle reaches the trigger centerline within six millimeters" % label)


func _palm_medians(mesh: MeshInstance3D, skeleton: Skeleton3D, gun: Node3D) -> Array[Vector3]:
	var skin := mesh.skin
	var output: Array[Vector3] = []
	var gun_axes := gun.global_basis.orthonormalized().inverse()
	for names in [["R_wrist_028", "R_palm_041"], ["L_wrist_04", "L_palm_017"]]:
		var positions: Array[Vector3] = []
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
					var bone := skeleton.find_bone(skin.get_bind_name(bind)) if skin.get_bind_name(bind) != &"" else skin.get_bind_bone(bind)
					position += (skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind) * vertices[vertex]) * weights[offset]
					if skeleton.get_bone_name(bone) in names:
						palm_weight += weights[offset]
				if palm_weight > 0.65:
					positions.append(gun_axes * (skeleton.global_transform * position - gun.global_position))
		if positions.is_empty():
			return []
		var median := Vector3.ZERO
		for axis in 3:
			var coordinates: Array[float] = []
			for point in positions:
				coordinates.append(point[axis])
			coordinates.sort()
			median[axis] = coordinates[coordinates.size() / 2]
		output.append(median)
	return output


func _grip_bounds(gun: Node3D, weapon_id: StringName) -> AABB:
	var body := gun.find_child("em57p_body" if weapon_id == &"pistol" else "Body", true, false) as Node3D
	var meshes := body.find_children("*", "MeshInstance3D", true, false)
	if body is MeshInstance3D:
		meshes.append(body)
	var result := AABB()
	var count := 0
	for child in meshes:
		var mesh := child as MeshInstance3D
		var transform := gun.global_transform.affine_inverse() * mesh.global_transform
		for surface in mesh.mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point: Vector3 = transform * vertex
				if point.y >= -0.035 or point.z <= (0.18 if weapon_id == &"pistol" else 0.30):
					continue
				result = result.expand(point) if count > 0 else AABB(point, Vector3.ZERO)
				count += 1
	_assert(count > 50, "%s grip bounds come from actual lower rear body vertices" % weapon_id)
	return result


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)
