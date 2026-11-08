extends SceneTree

var _failures := 0
var _scene: Node3D
var _player: CharacterBody3D


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _settle(weapon: Node) -> void:
	for frame in 24:
		_player._process(1.0 / 60.0)
		weapon._process(1.0 / 60.0)


func _cut_crosses_frame(a: Vector3, b: Vector3, half_width: float, half_height: float) -> bool:
	if absf(a.x) < half_width and absf(a.y) < half_height:
		return true
	if absf(b.x) < half_width and absf(b.y) < half_height:
		return true
	if not is_equal_approx(a.x, b.x):
		for x in [-half_width, half_width]:
			var t: float = (x - a.x) / (b.x - a.x)
			if t >= 0.0 and t <= 1.0 and absf(lerpf(a.y, b.y, t)) < half_height:
				return true
	if not is_equal_approx(a.y, b.y):
		for y in [-half_height, half_height]:
			var t: float = (y - a.y) / (b.y - a.y)
			if t >= 0.0 and t <= 1.0 and absf(lerpf(a.x, b.x, t)) < half_width:
				return true
	return false


func _visible_near_cuts(model: Node3D) -> int:
	var camera: Camera3D = _player._camera
	var to_camera := camera.global_transform.affine_inverse()
	var half_height := tan(deg_to_rad(camera.fov) * 0.5) * camera.near
	var half_width := half_height * 16.0 / 9.0
	var cuts := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var xform := to_camera * mesh_instance.global_transform
			for index in range(0, indices.size(), 3):
				var intersections: Array[Vector3] = []
				for edge in 3:
					var a := xform * vertices[indices[index + edge]]
					var b := xform * vertices[indices[index + (edge + 1) % 3]]
					if (a.z + camera.near) * (b.z + camera.near) >= 0.0:
						continue
					intersections.append(a.lerp(b, (-camera.near - a.z) / (b.z - a.z)))
				if intersections.size() == 2 and _cut_crosses_frame(intersections[0], intersections[1], half_width, half_height):
					cuts += 1
	return cuts


func _run() -> void:
	_assert(_cut_crosses_frame(Vector3(-2, 0, 0), Vector3(2, 0, 0), 1, 1), "near-cut detection includes segments crossing the entire view")
	root.size = Vector2i(1920, 1080)
	_scene = (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	_player = _scene.get_node("Player") as CharacterBody3D
	await process_frame
	_player._switch_weapon(&"em57s2")
	var smg = _player.get_node("Camera3D/WeaponMount/Em57s2")
	_player._set_aiming(false)
	_settle(smg)
	var model := smg.get_node("ViewModel/EM68A") as Node3D
	var marker := smg.get_node("ViewModel/OpticAim") as Marker3D
	var mesh_node: MeshInstance3D = _player._optic_meshes[&"em57s2"].node
	var hip_mesh := mesh_node.mesh
	var hip_mount: Transform3D = _player._weapon_mount.transform
	var hip_model := model.transform
	var hip_camera: Transform3D = _player._camera.transform
	var hip_near: float = _player._camera.near
	var hip_fov: float = _player._camera.fov
	_player._set_aiming(true)
	var transition_cuts := 0
	for frame in 24:
		_player._process(1.0 / 60.0)
		smg._process(1.0 / 60.0)
		transition_cuts = maxi(transition_cuts, _visible_near_cuts(model))
	_assert(transition_cuts == 0, "aiming transition keeps near-plane cuts outside the frame")
	var optic_local: Vector3 = _player._camera.global_transform.affine_inverse() * marker.global_position
	_assert(-optic_local.z > 0.2 and -optic_local.z < 0.4, "EM-57S2 ADS reaches the forward small optic, 20-40 cm from the eye")
	_assert(Vector2(optic_local.x, optic_local.y).length() < 0.001, "forward optic stays centered")
	var visible_cuts := _visible_near_cuts(model)
	print("EM57S2_ADS_DIAG optic=", optic_local, " near=", _player._camera.near, " visible_near_cuts=", visible_cuts)
	_assert(visible_cuts == 0, "no gun surface is cut by the near plane inside the visible frame")
	root.get_node("GameState").em57s2_mag = 100
	smg._start_reload()
	var reload_cuts := 0
	for frame in 8:
		smg._arms_animation.advance(1.0 / 60.0)
		_player._process(1.0 / 60.0)
		smg._process(1.0 / 60.0)
		reload_cuts = maxi(reload_cuts, _visible_near_cuts(model))
	for phase in 3:
		await create_timer(0.45).timeout
		reload_cuts = maxi(reload_cuts, _visible_near_cuts(model))
	_assert(_player._weapon_mount.position.distance_to(hip_mount.origin) < 0.001 and is_equal_approx(_player._camera.fov, hip_fov), "reload lowers the rotating gun away from the eye while preserving the held aim input")
	_assert(root.get_node("GameState").is_aiming, "reload preserves the player's held right mouse state")
	print("EM57S2_ADS_RELOAD_CUTS ", reload_cuts)
	_assert(reload_cuts == 0, "ADS reload keeps the gun outside visible near-plane cuts")
	await create_timer(0.8).timeout
	_assert(not smg._is_reloading and _player._ads_weight > 0.99 and root.get_node("GameState").em57s2_mag == 150, "reload completes normally and held right mouse returns to the forward optic")
	_player._set_aiming(false)
	_settle(smg)
	_assert(mesh_node.mesh == hip_mesh, "hip restores the exact original mesh")
	_assert(_player._weapon_mount.transform.is_equal_approx(hip_mount) and model.transform.is_equal_approx(hip_model), "hip restores the original mount and weapon pose")
	_assert(_player._camera.transform.is_equal_approx(hip_camera) and is_equal_approx(_player._camera.fov, hip_fov) and is_equal_approx(_player._camera.near, hip_near), "hip restores the original camera, field of view and near plane")
	_player._set_aiming(true)
	_settle(smg)
	_player._switch_weapon(&"em86m")
	_settle(_player.get_node("Camera3D/WeaponMount/Em86m"))
	_assert(is_equal_approx(_player._camera.near, hip_near), "switching weapons while aiming restores the normal near plane")
	_scene.queue_free()
	await process_frame
	print("EM57S2_ADS failures=", _failures)
	quit(1 if _failures else 0)
