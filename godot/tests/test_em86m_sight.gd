extends SceneTree
## Uses the actual drawn reticle and physical ADS mesh, rather than its constants.

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _opaque_triangles(model: Node3D, camera: Camera3D) -> Array[Vector3]:
	var triangles: Array[Vector3] = []
	var to_camera := camera.global_transform.affine_inverse()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		for surface in instance.mesh.get_surface_count():
			var material := instance.get_active_material(surface) as StandardMaterial3D
			if material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and material.albedo_color.a <= 0.35:
				continue
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for index in range(0, indices.size(), 3):
				var world: Array[Vector3] = []
				var projected := Rect2()
				var all_forward := true
				for corner in 3:
					var point: Vector3 = instance.global_transform * vertices[indices[index + corner]]
					world.append(point)
					var local := to_camera * point
					all_forward = all_forward and local.z < -0.001
					var slope := Vector2(local.x, local.y) / maxf(-local.z, 0.001)
					projected = Rect2(slope, Vector2.ZERO) if corner == 0 else projected.expand(slope)
				# Conservative central cone includes the sight and every tested pixel.
				if all_forward and not projected.intersects(Rect2(-0.08, -0.08, 0.16, 0.16), true):
					continue
				triangles.append_array(world)
	return triangles


func _blocked(triangles: Array[Vector3], from: Vector3, direction: Vector3) -> bool:
	for index in range(0, triangles.size(), 3):
		# The native frame has tiny triangles; detect them in millimetres.
		var a := (triangles[index] - from) * 1000.0
		var b := (triangles[index + 1] - from) * 1000.0
		var c := (triangles[index + 2] - from) * 1000.0
		if Geometry3D.ray_intersects_triangle(Vector3.ZERO, direction, a, b, c) != null \
			or Geometry3D.ray_intersects_triangle(Vector3.ZERO, direction, a, c, b) != null:
			return true
	return false


func _render_reticle(view_size: Vector2i) -> PackedVector2Array:
	var viewport := SubViewport.new()
	viewport.size = view_size
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var player_script = load("res://scripts/player/player_controller.gd")
	var reticle = player_script.AdsReticle.new()
	reticle.size = Vector2(view_size)
	reticle.mode = &"em86m"
	reticle.weight = 1.0
	viewport.add_child(reticle)
	reticle.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	var pixels := PackedVector2Array()
	var center := Vector2(view_size) * 0.5
	for y in range(int(center.y) - 60, int(center.y) + 61):
		for x in range(int(center.x) - 60, int(center.x) + 61):
			var color := picture.get_pixel(x, y)
			if color.a > 0.15 and color.g > 0.7 and color.b > 0.8 and color.r < 0.65:
				pixels.append(Vector2(x + 0.5, y + 0.5))
	viewport.queue_free()
	await process_frame
	return pixels


func _run() -> void:
	root.get_node("GameState").reset()
	var scene := (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	player._switch_weapon(&"em86m")
	player.global_position = Vector3(44, 0.1, 19)
	player.rotation.y = PI
	player._camera.rotation = Vector3.ZERO
	var weapon = player.get_node("Camera3D/WeaponMount/Em86m")
	for frame in 24:
		player._process(1.0 / 60.0)
		weapon._process(1.0 / 60.0)
	var intact_mesh: Mesh = player._optic_meshes[&"em86m"].node.mesh
	var hip_transform: Transform3D = player._weapon_mount.transform
	player._set_aiming(true)
	for frame in 24:
		player._process(1.0 / 60.0)
		weapon._process(1.0 / 60.0)
		await process_frame
	var model := weapon.get_node("ViewModel/EM68A") as Node3D
	var triangles := _opaque_triangles(model, player._camera)
	var sizes: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(2560, 1440)]
	for view_size: Vector2i in sizes:
		root.size = view_size
		await process_frame
		var center := Vector2(view_size) * 0.5
		var blocked_samples := 0
		for radius in [0.0, 6.0, 12.0, 18.0, 22.0]:
			for angle in (1 if radius == 0.0 else 16):
				var theta := float(angle) * TAU / 16.0
				var pixel: Vector2 = center + Vector2(cos(theta), sin(theta)) * radius * view_size.y / 900.0
				if _blocked(triangles, player._camera.global_position, player._camera.project_ray_normal(pixel)):
					blocked_samples += 1
		_assert(blocked_samples == 0, "EM-86M %s has 65 unobstructed sight samples through a 22px/900h aperture (blocked=%d)" % [view_size, blocked_samples])
		if DisplayServer.get_name() != "headless":
			var pixels: PackedVector2Array = await _render_reticle(view_size)
			var extent := 0.0
			var occluded_pixels := 0
			for pixel in pixels:
				extent = maxf(extent, (pixel - center).length())
				if _blocked(triangles, player._camera.global_position, player._camera.project_ray_normal(pixel)):
					occluded_pixels += 1
			_assert(not pixels.is_empty() and extent <= 20.0 * view_size.y / 900.0, "EM-86M %s actual cyan reticle stays within the sight margin (radius=%.2f)" % [view_size, extent])
			_assert(occluded_pixels == 0, "EM-86M %s every visible reticle pixel points through the physical opening (blocked=%d)" % [view_size, occluded_pixels])
	player._set_aiming(false)
	for frame in 24:
		player._process(1.0 / 60.0)
		weapon._process(1.0 / 60.0)
	_assert(player._optic_meshes[&"em86m"].node.mesh == intact_mesh and player._weapon_mount.transform.is_equal_approx(hip_transform), "EM-86M exits ADS with its original hip mesh and transform")
	scene.queue_free()
	await process_frame
	print("EM86M_SIGHT failures=", _failures, " renderer=", DisplayServer.get_name())
	quit(1 if _failures else 0)
