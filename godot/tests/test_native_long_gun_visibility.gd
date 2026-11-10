## Actual Player viewport and renderer-baked black-arm silhouettes, across all supply layouts.
extends SceneTree

const IDS := [&"rifle", &"dmr", &"shotgun", &"smg", &"lmg", &"em57s2", &"em86b", &"em86d", &"em86s", &"em86m", &"em12g2", &"em127g", &"em127m", &"em40t1", &"spas12", &"em120r"]
var _failures := 0
var _assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(960, 540)
	var state = root.get_node("GameState")
	state.reset()
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.set_process_unhandled_input(false)
	var fill := DirectionalLight3D.new()
	world.add_child(fill)
	fill.rotation_degrees = Vector3(-30, -20, 0)
	fill.light_energy = 1.8
	await process_frame
	for candidate in player.get_node("Camera3D/WeaponMount").get_children():
		candidate.set_process(false)
		candidate.set_physics_process(false)
	DirAccess.make_dir_recursive_absolute("res://tmp_shots/native_long_gun_visibility")
	for id in IDS:
		if "--only-em120r" in OS.get_cmdline_user_args() and id != &"em120r":
			continue
		state.weapon_unlocked[id] = true
		player._switch_weapon(id)
		var weapon: Node3D
		for candidate in player.get_node("Camera3D/WeaponMount").get_children():
			if candidate.weapon_data.weapon_id == id:
				weapon = candidate
		var samples := [["hip", -1.0], ["contact", 0.22], ["insert", 0.70]]
		if id == &"em120r":
			samples.append(["aligned", 0.42])
			samples.append(["release", 0.80])
		for sample in samples:
			weapon._is_reloading = false
			if id == &"em120r":
				weapon._reset_supply_visuals()
			else:
				weapon._reset_reload_visuals()
			player._set_aiming(false)
			for frame in 30:
				player._restore_viewmodel_depth()
				weapon._process(1.0 / 60.0)
				player._process(1.0 / 60.0)
			if float(sample[1]) >= 0:
				root.get_node("Events").weapon_reload_started.emit(id)
				weapon._arms_animation.seek(weapon.weapon_data.reload_time * float(sample[1]), true)
				if id == &"spas12":
					weapon._reload_progress = float(sample[1])
				weapon._process(0.0)
				player._process(0.0)
			await process_frame
			await RenderingServer.frame_post_draw
			var counts := _skin_counts(weapon._arms_node, player._camera)
			_assertions += 1
			print("NATIVE_VISIBILITY ", id, " ", sample[0], " L=", counts.x, " R=", counts.y)
			if counts.x <= 20 or counts.y <= 20:
				_failures += 1
				push_error("FAIL: %s %s both actual black-arm skins must enter the Player viewport" % [id, sample[0]])
			if id == &"em120r" and float(sample[1]) >= 0.0:
				var missile := weapon.get_node("ViewModel/Weapon/LoadingMissile") as Node3D
				var skeleton: Skeleton3D = weapon._arms_skeleton
				var sleeve_roots_outside := true
				for name in ["L_arm_02", "R_arm_026"]:
					var bone := skeleton.find_bone(name)
					var point := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
					print("REAR_SLEEVE_ROOT ", sample[0], " ", name, " camera=", player._camera.to_local(point), " visible=", player._camera.is_position_in_frustum(point))
					sleeve_roots_outside = sleeve_roots_outside and not player._camera.is_position_in_frustum(point)
				_assertions += 1
				if not sleeve_roots_outside:
					_failures += 1
					push_error("FAIL: original sleeve roots must remain outside the viewport at " + str(sample[0]))
				var missile_count := _static_count(missile, player._camera)
				_assertions += 1
				print("REAR_VISIBILITY ", sample[0], " missile_vertices=", missile_count)
				if missile_count <= 20 or not player._camera.is_position_in_frustum(weapon.get_node("ViewModel/Weapon/RearBreech").global_position):
					_failures += 1
					push_error("FAIL: rear loading missile and original breech must enter Player viewport at " + str(sample[0]))
			root.get_texture().get_image().save_png("res://tmp_shots/native_long_gun_visibility/%s_%s.png" % [id, sample[0]])
			if id == &"em120r" and float(sample[1]) >= 0.0:
				var pixels := await _missile_pixels(weapon.get_node("ViewModel/Weapon/LoadingMissile"))
				_assertions += 1
				print("REAR_PIXELS ", sample[0], " visible_pixels=", pixels)
				if pixels <= 20:
					_failures += 1
					push_error("FAIL: actual loading missile must render visible pixels at " + str(sample[0]))
	world.queue_free()
	await process_frame
	await process_frame
	print("NATIVE_LONG_GUN_VISIBILITY assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures else 0)


func _missile_pixels(owner: Node3D) -> int:
	var saved: Dictionary = {}
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0, 1, 0, 1)
	for node in owner.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		saved[mesh] = mesh.material_override
		mesh.material_override = material
	await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	var count := 0
	for y in capture.get_height():
		for x in capture.get_width():
			var pixel := capture.get_pixel(x, y)
			if pixel.g > 0.7 and pixel.r < 0.2 and pixel.b < 0.2:
				count += 1
	for mesh in saved:
		mesh.material_override = saved[mesh]
	await process_frame
	await RenderingServer.frame_post_draw
	return count


func _static_count(owner: Node3D, camera: Camera3D) -> int:
	var count := 0
	for node in owner.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for point in vertices:
				if camera.is_position_in_frustum(mesh.to_global(point)):
					count += 1
	return count


func _skin_counts(arms: Node3D, camera: Camera3D) -> Vector2i:
	var count := Vector2i.ZERO
	for node in arms.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.is_visible_in_tree() or mesh.skin == null:
			continue
		var skeleton := mesh.get_node(mesh.skeleton) as Skeleton3D
		var posed := mesh.bake_mesh_from_current_skeleton_pose()
		for surface in posed.get_surface_count():
			var source := mesh.mesh.surface_get_arrays(surface)
			var arrays := posed.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = source[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = source[Mesh.ARRAY_WEIGHTS]
			var width: int = bones.size() / vertices.size()
			for vertex in vertices.size():
				if not camera.is_position_in_frustum(mesh.global_transform * vertices[vertex]):
					continue
				var sides := Vector2.ZERO
				for influence in width:
					var offset := vertex * width + influence
					if weights[offset] <= 0:
						continue
					var bone := skeleton.find_bone(mesh.skin.get_bind_name(bones[offset]))
					while bone >= 0:
						var name := skeleton.get_bone_name(bone)
						if name == "R_arm_026":
							sides.y += weights[offset]
							break
						if name == "L_arm_02":
							sides.x += weights[offset]
							break
						bone = skeleton.get_bone_parent(bone)
				if sides.x > 0.25:
					count.x += 1
				if sides.y > 0.25:
					count.y += 1
	return count
