## Real Player visibility: renderer-skinned vertices and diagnostic rendered pixels.
extends SceneTree

const OUTPUT := "res://tmp_shots/spas12_visibility"

var _assertions := 0
var _failures := 0
var _world: Node3D
var _player
var _weapon
var _state
var _materials: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _run() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("SPAS visibility timed out")
		quit(1))
	_assert(DisplayServer.get_name() != "headless", "SPAS visibility uses native rendering")
	if _failures:
		quit(1)
		return
	root.size = Vector2i(960, 540)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	_state = root.get_node("GameState")
	_state.reset()
	_state.weapon_unlocked[&"spas12"] = true
	var use_street := "--street" in OS.get_cmdline_user_args()
	var use_district := "--district" in OS.get_cmdline_user_args()
	var use_rack := "--rack" in OS.get_cmdline_user_args()
	var use_range := "--range" in OS.get_cmdline_user_args()
	if use_rack:
		_state.weapon_unlocked[&"spas12"] = false
		use_district = true
	if use_street or use_district or use_range:
		var path := "res://scenes/levels/weapons_range.tscn" if use_range else ("res://scenes/levels/street_playable.tscn" if use_street else "res://scenes/levels/district_b.tscn")
		_world = (load(path) as PackedScene).instantiate() as Node3D
		root.add_child(_world)
		current_scene = _world
		_player = _world.get_node("Player")
	else:
		_setup_open_floor()
	_player.set_process_unhandled_input(false)
	_weapon = _player.get_node("Camera3D/WeaponMount/Spas12")
	if use_rack:
		_player.global_position = Vector3(-38, 0.1, 52.2)
		await _settle(90)
		_assert(_state.weapon_unlocked[&"spas12"] and _state.current_weapon == &"spas12",
			"real district rack pickup unlocks and equips SPAS")
	_player.set_physics_process(false)
	_state.weapon_unlocked[&"spas12"] = true
	if use_range:
		_state.weapon_unlocked[&"shotgun"] = true
		_state.shotgun_mag = 32
		_press(KEY_4)
		_assert(_state.current_weapon == &"shotgun", "real key 4 selects EM shotgun first")
		await _settle(30)
		_press(KEY_4)
		_assert(_state.current_weapon == &"spas12", "real repeated key 4 selects SPAS")
	else:
		_player._switch_weapon(&"spas12")
	if use_district:
		_player.global_position = Vector3(-38, 0.1, 55)
		_player.rotation = Vector3.ZERO
		_player._pitch = 0.0
		_player._camera.rotation = Vector3.ZERO
	await _settle(45)
	await _check("hip")
	_player._set_aiming(true)
	await _settle(45)
	await _check("ads")
	_player._set_aiming(false)
	await _settle(45)
	_assert(_weapon._fire(), "SPAS fires through the production controller")
	await create_timer(0.25).timeout
	await _check("pump")
	await create_timer(0.7).timeout
	_state.spas12_mag = 3
	_state.spas12_reserve = 5
	_weapon._start_reload()
	await create_timer(0.28).timeout
	await _check("reload")
	_player._switch_weapon(&"rifle")
	await _settle(12)
	_player._switch_weapon(&"spas12")
	await _settle(30)
	await _check("switch_back")
	_player._switch_weapon(&"rifle")
	_player._set_aiming(true)
	await _settle(90)
	_player._switch_weapon(&"spas12")
	await _settle(45)
	await _check("from_rifle_ads")
	_player._set_aiming(false)
	await _settle(45)
	await _check("after_rifle_ads")
	_world.queue_free()
	await process_frame
	await process_frame
	print("SPAS_VISIBILITY assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures else 0)


func _setup_open_floor() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.12, 0.12, 0.12)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 1.0
	environment.environment = settings
	_world.add_child(environment)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(20, 0.2, 20)
	collision.shape = floor_shape
	floor_body.position.y = -0.1
	floor_body.add_child(collision)
	_world.add_child(floor_body)
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	_world.add_child(_player)


func _settle(frames: int) -> void:
	for frame in frames:
		await physics_frame
		await process_frame
	await RenderingServer.frame_post_draw


func _press(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	_player._unhandled_input(event)


func _check(label: String) -> void:
	await RenderingServer.frame_post_draw
	print("SPAS_POSE ", label, " mount=", _player._weapon_mount.transform,
		" hidden=", _player._viewmodel_depth_hidden, " depth=", _player._viewmodel_depth_scale,
		" weapon=", _weapon._weapon_node.transform, " arms=", _weapon._arms_node.transform)
	for prefix: String in ["UpArm_R", "Forearm_R", "Hand_R"]:
		var bone: int = _weapon._find_bone_by_prefix(prefix)
		var point: Vector3 = _player._camera.global_transform.affine_inverse() * _weapon._arms_skeleton.global_transform * _weapon._arms_skeleton.get_bone_global_pose(bone).origin
		print("SPAS_RIGHT ", label, " ", prefix, " camera=", point)
	_assert(_weapon.is_visible_in_tree(), label + " selected SPAS root remains visible")
	var gun_count := _frustum_vertex_count(_weapon._weapon_node)
	var arm_count := _frustum_vertex_count(_weapon._arms_node)
	_assert(gun_count > 20, "%s real gun vertices enter Player frustum (%d)" % [label, gun_count])
	_assert(arm_count > 20, "%s renderer-skinned arm vertices enter Player frustum (%d)" % [label, arm_count])
	var sides := _arm_frustum_counts()
	_assert(sides.left > 20 and sides.right > 20,
		"%s both real skinned arms enter Player frustum (L=%d R=%d)" % [label, sides.left, sides.right])
	var natural := root.get_texture().get_image()
	_assert(natural != null and not natural.is_empty() and natural.save_png(OUTPUT + "/" + label + ".png") == OK,
		label + " saves production-material Player capture")
	_color_meshes(_weapon._weapon_node, Color(1.0, 0.0, 1.0))
	_color_meshes(_weapon._arms_node, Color(0.0, 1.0, 1.0))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var diagnostic := root.get_texture().get_image()
	var gun_pixels := 0
	var arm_pixels := 0
	for y in diagnostic.get_height():
		for x in diagnostic.get_width():
			var pixel := diagnostic.get_pixel(x, y)
			var prior := natural.get_pixel(x, y)
			var changed := maxf(absf(pixel.r - prior.r), maxf(absf(pixel.g - prior.g), absf(pixel.b - prior.b))) > 0.15
			if not changed:
				continue
			if pixel.r > 0.45 and pixel.b > 0.45 and pixel.g < pixel.r - 0.35 and pixel.g < pixel.b - 0.35:
				gun_pixels += 1
			if pixel.g > 0.45 and pixel.b > 0.45 and pixel.r < pixel.g - 0.35 and pixel.r < pixel.b - 0.35:
				arm_pixels += 1
	_assert(gun_pixels > 150, "%s actual gun renders visible pixels (%d)" % [label, gun_pixels])
	_assert(arm_pixels > 150, "%s actual arms render visible pixels (%d)" % [label, arm_pixels])
	diagnostic.save_png(OUTPUT + "/" + label + "_diagnostic.png")
	for mesh: MeshInstance3D in _materials:
		mesh.material_override = _materials[mesh]
	_materials.clear()
	await RenderingServer.frame_post_draw


func _frustum_vertex_count(branch: Node3D) -> int:
	var count := 0
	for node in branch.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if not instance.is_visible_in_tree() or instance.mesh == null:
			continue
		var mesh: Mesh = instance.mesh
		if instance.get_skin_reference() != null:
			mesh = instance.bake_mesh_from_current_skeleton_pose()
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				if _player._camera.is_position_in_frustum(instance.global_transform * vertex):
					count += 1
	return count


func _color_meshes(branch: Node3D, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	for node in branch.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		_materials[mesh] = mesh.material_override
		mesh.material_override = material


func _arm_frustum_counts() -> Dictionary:
	var result := {"left": 0, "right": 0}
	for node in _weapon._arms_node.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if not instance.is_visible_in_tree() or instance.mesh == null:
			continue
		var reference := instance.get_skin_reference()
		if reference == null:
			continue
		var skin := reference.get_skin()
		var skeleton := instance.get_node_or_null(instance.skeleton) as Skeleton3D
		var posed := instance.bake_mesh_from_current_skeleton_pose()
		if skin == null or skeleton == null or posed == null:
			continue
		for surface in posed.get_surface_count():
			var source := instance.mesh.surface_get_arrays(surface)
			var baked := posed.surface_get_arrays(surface)
			var vertices: PackedVector3Array = baked[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = source[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = source[Mesh.ARRAY_WEIGHTS]
			var per_vertex: int = bones.size() / vertices.size()
			for vertex in vertices.size():
				if not _player._camera.is_position_in_frustum(instance.global_transform * vertices[vertex]):
					continue
				var left_weight := 0.0
				var right_weight := 0.0
				for influence in per_vertex:
					var offset := vertex * per_vertex + influence
					if weights[offset] <= 0.0:
						continue
					var bind := bones[offset]
					var bone := skeleton.find_bone(skin.get_bind_name(bind))
					while bone >= 0:
						var name := skeleton.get_bone_name(bone)
						if name.begins_with("UpArm_L") or name.begins_with("Hand_L") or name.begins_with("L_arm_"):
							left_weight += weights[offset]
							break
						if name.begins_with("UpArm_R") or name.begins_with("Hand_R") or name.begins_with("R_arm_"):
							right_weight += weights[offset]
							break
						bone = skeleton.get_bone_parent(bone)
				if left_weight > 0.25:
					result.left += 1
				if right_weight > 0.25:
					result.right += 1
	return result
