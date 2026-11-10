## 优化前后均与真实蒙皮顶点逐个求和对照；相对耗时证明缓存确实减少运行时工作。
extends SceneTree

var _assertions := 0
var _failures := 0


func _init() -> void:
	Engine.max_fps = 60
	call_deferred("_run")


func _run() -> void:
	var state = root.get_node("GameState")
	state.reset()
	state.current_weapon = &"rifle"
	var weapon = (load("res://scenes/weapons/rifle.tscn") as PackedScene).instantiate()
	root.add_child(weapon)
	await process_frame
	weapon.set_process(false)
	weapon.set_physics_process(false)
	var helper = weapon._native_arms
	_assert(helper != null and helper.skeleton.get_bone_count() == 60, "fixture uses the actual native sixty-joint production rifle")
	if helper == null:
		weapon.queue_free()
		await process_frame
		quit(1)
		return
	var skeleton: Skeleton3D = helper.skeleton
	var samples := [_collect_vertices(weapon._arms_node, skeleton, ["R_wrist_028", "R_palm_041"]), _collect_vertices(weapon._arms_node, skeleton, ["L_wrist_04", "L_palm_017"])]
	_assert(samples[0].size() > 20 and samples[1].size() > 20, "independent oracle samples actual weighted palm vertices from both source skins")
	root.get_node("Events").weapon_reload_started.emit(&"rifle")
	var maximum_error := 0.0
	for step in 61:
		helper.animation.seek(float(step) / 60.0 * weapon.weapon_data.reload_time, true)
		weapon._process(0.0)
		var poses := _poses(skeleton)
		for hand in 2:
			var expected := _reference_centroid(samples[hand], poses)
			var actual: Vector3 = helper._palm_position(hand)
			var error := (skeleton.global_basis * (actual - expected)).length()
			maximum_error = maxf(maximum_error, error)
			_assert(actual.is_finite() and error < 0.000003, "phase %d hand %d centroid matches independent rendered-skin math within three micrometers" % [step, hand])
	var reference_poses := _poses(skeleton)
	var iterations := 120
	var checksum := Vector3.ZERO
	var started := Time.get_ticks_usec()
	for sample in iterations:
		checksum += _reference_centroid(samples[sample % 2], reference_poses)
	var reference_us := maxi(Time.get_ticks_usec() - started, 1)
	started = Time.get_ticks_usec()
	for sample in iterations:
		checksum += helper._palm_position(sample % 2)
	var helper_us := Time.get_ticks_usec() - started
	print("NATIVE_CENTROID_BENCH reference_us=", reference_us, " helper_us=", helper_us, " ratio=", float(helper_us) / float(reference_us), " checksum=", checksum, " maximum_world_error=", maximum_error)
	_assert(helper_us < reference_us * 0.35, "runtime centroid is at least three times faster than a per-vertex skin oracle")
	weapon._is_reloading = false
	weapon._reset_reload_visuals()
	weapon.queue_free()
	await process_frame
	await process_frame
	print("NATIVE_LONG_GUN_CENTROID assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures else 0)


func _collect_vertices(arms: Node3D, skeleton: Skeleton3D, names: Array) -> Array:
	var result: Array = []
	var minimum: float = root.get_node("GameConfig").BLACK_LONG_GUN_PALM_WEIGHT
	for node in arms.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.skin == null or mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var width: int = joints.size() / positions.size()
			for vertex in positions.size():
				var weight := 0.0
				var bindings: Array = []
				for influence in width:
					var offset := vertex * width + influence
					if weights[offset] <= 0.0:
						continue
					var bind := joints[offset]
					var joint := skeleton.find_bone(mesh.skin.get_bind_name(bind)) if mesh.skin.get_bind_name(bind) != &"" else mesh.skin.get_bind_bone(bind)
					bindings.append({"joint": joint, "inverse_bind": mesh.skin.get_bind_pose(bind), "weight": weights[offset]})
					if String(skeleton.get_bone_name(joint)) in names:
						weight += weights[offset]
				if weight > minimum:
					result.append({"position": positions[vertex], "bindings": bindings})
	return result


func _poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		poses.append(skeleton.get_bone_global_pose(bone))
	return poses


func _reference_centroid(vertices: Array, poses: Array[Transform3D]) -> Vector3:
	var sum := Vector3.ZERO
	for vertex: Dictionary in vertices:
		var skinned := Vector3.ZERO
		for binding: Dictionary in vertex.bindings:
			skinned += (poses[binding.joint] * binding.inverse_bind * vertex.position) * binding.weight
		sum += skinned
	return sum / float(vertices.size())


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
