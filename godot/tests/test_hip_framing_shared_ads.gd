## Real Player frames: restore the authored stock/receiver framing and test the visible shared optic.
extends SceneTree

const PLATFORMS := {
	&"rifle": "Rifle", &"dmr": "DMR", &"shotgun": "Shotgun", &"smg": "SMG",
	&"lmg": "LMG", &"em57s2": "Em57s2", &"em86b": "Em86b", &"em86d": "Em86d",
	&"em86s": "Em86s", &"em86m": "Em86m", &"em12g2": "Em12g2", &"em127g": "Em127g",
	&"em127m": "Em127m", &"em40t1": "Em40t1", &"spas12": "Spas12", &"em120r": "Em120r",
}
const SHARED := [&"smg", &"em12g2", &"lmg"]
var _failures := 0
var _assertions := 0
var _player: CharacterBody3D
var _output: String


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _settle() -> void:
	await create_timer(0.35).timeout
	await physics_frame
	await process_frame
	await RenderingServer.frame_post_draw


func _shot(label: String) -> void:
	_assert(root.get_texture().get_image().save_png(_output + "/" + label + ".png") == OK, label + " captures the production frame")


func _hip(weapon: Node3D, id: StringName) -> void:
	var expected: Transform3D = weapon._weapon_home
	if id == &"spas12":
		expected.origin = Vector3(-0.04, -0.035, 0.12) # Authored placement before 9a3fe86.
		expected = weapon._pose_extra * expected
	elif id == &"em120r":
		expected.origin = Vector3(0, 0.18, 0.38)
	else:
		expected = weapon._pose_extra * expected
	var gun: Node3D = weapon._weapon_node
	var actual_in_camera: Transform3D = _player._camera.global_transform.affine_inverse() * gun.global_transform
	var authored_in_camera: Transform3D = _player._camera.global_transform.affine_inverse() * gun.get_parent().global_transform * expected
	var error := actual_in_camera.origin.distance_to(authored_in_camera.origin)
	print("HIP_FRAMING ", id, " camera=", actual_in_camera.origin, " baseline=", authored_in_camera.origin, " error_m=", error)
	_assert(error < 0.001 and actual_in_camera.basis.is_equal_approx(authored_in_camera.basis), "%s preserves the authored stock/receiver framing within 1mm" % id)
	_assert(_player._weapon_mount.position.distance_to(_player._mount_hip_pos) < 0.001, "%s hip keeps the original camera mount" % id)


func _shared_ads(id: StringName, label: String) -> void:
	var rifle := _player.get_node("Camera3D/WeaponMount/Rifle") as Node3D
	var optic: MeshInstance3D = _player._optic_meshes[&"rifle"].node
	_assert(rifle.is_visible_in_tree() and optic.is_visible_in_tree(), label + " checks the actually visible shared Rifle optic")
	_assert(optic.mesh == _player._optic_meshes[&"rifle"].bored, label + " uses the open optic mesh")
	var equipped := _player.get_node("Camera3D/WeaponMount/" + PLATFORMS[id]) as Node3D
	_assert(not equipped._arms_node.is_visible_in_tree(), label + " renders only the borrowed gun arms")
	var bore: Vector3 = optic.global_transform * GameConfig.ADS_RIFLE_OPTIC_BORE_LOCAL
	var center := Vector2(root.size) * 0.5
	var pixel: Vector2 = _player._camera.unproject_position(bore)
	print("SHARED_ADS ", id, " ", label, " bore_pixel=", pixel, " error_px=", pixel.distance_to(center), " rifle_aim=", rifle._aim_weight)
	_assert(pixel.distance_to(center) < 2.0, label + " visible physical bore is within 2px of screen center")
	var origin: Vector3 = _player._camera.project_ray_origin(center)
	var direction: Vector3 = _player._camera.project_ray_normal(center)
	var blocking := _opaque_blocker(_player._weapon_mount, origin, direction)
	_assert(blocking.is_empty(), label + " screen-center ray passes through the real gun meshes (blocker=" + blocking + ")")
	_assert(root.get_node("GameState").current_weapon == id, label + " keeps the equipped weapon identity")


func _opaque_blocker(gun: Node3D, origin: Vector3, direction: Vector3) -> String:
	for node in gun.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var posed: Mesh = mesh.bake_mesh_from_current_skeleton_pose() if mesh.skin != null else mesh.mesh
		for surface in posed.get_surface_count():
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			var arrays := posed.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for index in range(0, indices.size(), 3):
				var a := mesh.global_transform * vertices[indices[index]]
				var b := mesh.global_transform * vertices[indices[index + 1]]
				var c := mesh.global_transform * vertices[indices[index + 2]]
				if Geometry3D.ray_intersects_triangle(origin, direction, a, b, c) != null or Geometry3D.ray_intersects_triangle(origin, direction, a, c, b) != null:
					return str(mesh.get_path())
	return ""


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("hip/shared ADS regression requires native rendering")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	_output = "res://tmp_shots/hip_shared_ads/" + ("before" if "--before" in OS.get_cmdline_user_args() else "after")
	DirAccess.make_dir_recursive_absolute(_output)
	var state = root.get_node("GameState")
	state.reset()
	var scene := (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	_player = scene.get_node("Player") as CharacterBody3D
	_player.set_process_unhandled_input(false)
	await process_frame
	var maximum_reload_time := 0.0
	for id: StringName in PLATFORMS:
		state.weapon_unlocked[id] = true
		_player._switch_weapon(id)
		_player._set_aiming(false)
		await _settle()
		_hip(_player.get_node("Camera3D/WeaponMount/" + PLATFORMS[id]), id)
		_shot(str(id) + "_hip")
	for id: StringName in SHARED:
		_player._switch_weapon(id)
		_player._set_aiming(true)
		await _settle()
		_shared_ads(id, str(id) + "_enter_ads")
		_shot(str(id) + "_ads")
		_player._switch_weapon(&"rifle")
		await _settle()
		_player._switch_weapon(id)
		await _settle()
		_shared_ads(id, str(id) + "_switch_while_aiming")
		_player._switch_weapon(SHARED[(SHARED.find(id) + 1) % SHARED.size()])
		await _settle()
		_player._switch_weapon(id)
		await _settle()
		_shared_ads(id, str(id) + "_switch_shared_while_aiming")
		_player._set_aiming(false)
		await _settle()
		_hip(_player.get_node("Camera3D/WeaponMount/" + PLATFORMS[id]), id)
		_assert(not _player.get_node("Camera3D/WeaponMount/Rifle").visible, str(id) + " leaving ADS removes the borrowed Rifle")
		var equipped := _player.get_node("Camera3D/WeaponMount/" + PLATFORMS[id]) as Node3D
		_assert(equipped._arms_node.is_visible_in_tree(), str(id) + " leaving ADS restores the equipped gun arms")
		var configured_mag = equipped.get("mag_state_property")
		var mag_key: StringName = configured_mag if configured_mag != null else id + "_mag"
		state.set(mag_key, maxi(1, equipped.weapon_data.mag_size / 2))
		maximum_reload_time = maxf(maximum_reload_time, equipped.weapon_data.reload_time)
		equipped._start_reload()
		await create_timer(0.10).timeout
		_assert(equipped._is_reloading, str(id) + " starts its own real reload after leaving shared ADS")
		_player._switch_weapon(&"rifle")
		_assert(not equipped._is_reloading, str(id) + " switching cancels the equipped reload")
		_player._switch_weapon(id)
		_player._set_aiming(true)
		await _settle()
		_shared_ads(id, str(id) + "_ads_after_reload_cancel")
		_player._set_aiming(false)
		await _settle()
	# Cancelled coroutine owners must remain alive until the longest reload timer returns.
	await create_timer(maximum_reload_time + 0.1).timeout
	scene.queue_free()
	await process_frame
	await process_frame
	print("HIP_SHARED_ADS assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures else 0)
