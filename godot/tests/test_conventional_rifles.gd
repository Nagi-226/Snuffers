## Prepared service rifles and their playable data/state/mount contracts.
extends SceneTree

const WEAPONS := {
	&"sig516": {"asset": "sig516_tactical.glb", "length": 1.097582, "mag": 30, "damage": 45.0, "groups": ["Body", "Magazine", "ACOG", "InfraredModule", "WeaponLight", "Foregrip"]},
	&"sr25": {"asset": "sr25_precision.glb", "length": 1.10, "mag": 20, "damage": 105.0, "groups": ["Body", "Magazine", "Scope", "Bipod"]},
	&"m700": {"asset": "m700_scoped.glb", "length": 1.054058, "mag": 4, "damage": 140.0, "groups": ["Body", "InternalMagazine", "Bolt", "Scope"]},
}

var _assertions := 0
var _failures := 0
var _state
var _scene: Node3D
var _player
var _hud
var _controllers: Array = []
var _guns: Dictionary = {}
var _shots: Dictionary = {}
var _reloads: Dictionary = {}
const OUTPUT := "res://tmp_shots/conventional_rifles"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		push_error("conventional rifle verification timed out")
		quit(1))
	_state = root.get_node("GameState")
	_state.reset()
	if "--framing-only" in OS.get_cmdline_user_args() or "--optics-only" in OS.get_cmdline_user_args() or "--m700-insertion-only" in OS.get_cmdline_user_args():
		await _check_runtime()
		_finish()
		return
	if "--sr25-contact-only" in OS.get_cmdline_user_args():
		await _check_asset(&"sr25", WEAPONS[&"sr25"])
		_finish()
		return
	var assets_only := "--assets-only" in OS.get_cmdline_user_args()
	var assets_ready := true
	var scenes_ready := true
	for id: StringName in WEAPONS:
		var item: Dictionary = WEAPONS[id]
		var asset_path := "res://addons/community_weapons/" + str(item.asset)
		var exists := FileAccess.file_exists(asset_path)
		_assert(exists, "%s prepared asset exists in the registered addons directory" % id)
		assets_ready = assets_ready and exists
		if assets_only:
			continue
		var scene_exists := ResourceLoader.exists("res://scenes/weapons/%s.tscn" % id)
		var data_exists := ResourceLoader.exists("res://scenes/weapons/%s.tres" % id)
		_assert(scene_exists and data_exists, "%s has its own playable scene and WeaponData" % id)
		scenes_ready = scenes_ready and scene_exists and data_exists
		_assert(_has_property(_state, String(id) + "_mag"), "%s has independent magazine state" % id)
		_assert(_state.weapon_chambered.has(id), "%s has explicit chamber state for a real plus-one round" % id)
		_assert(_state.weapon_unlocked.has(id) and _state.fire_modes.has(id), "%s has explicit campaign unlock and firing-mode state" % id)
		if data_exists:
			var data = load("res://scenes/weapons/%s.tres" % id).duplicate()
			data.sync_from_config()
			_assert(data.mag_size == int(item.mag) and is_equal_approx(data.damage_body, item.damage) and is_equal_approx(data.headshot_factor, 3.0), "%s syncs its approved capacity/body damage/triple head damage" % id)
			_assert(data.fire_interval > 0.0 and data.hitscan_range > 0.0 and data.reload_time > 0.0, "%s imports positive firing, range and reload contracts" % id)
	if not assets_ready:
		_finish()
		return
	for id: StringName in WEAPONS:
		await _check_asset(id, WEAPONS[id])
	if not assets_only and scenes_ready:
		await _check_mounts()
		if DisplayServer.get_name() != "headless":
			await _check_runtime()
		else:
			print("CONVENTIONAL_RIFLES native input/render cases require a native window")
	_finish()


func _check_asset(id: StringName, item: Dictionary) -> void:
	var path := "res://addons/community_weapons/" + str(item.asset)
	_check_container(path, id != &"sr25")
	var packed := load(path) as PackedScene
	_assert(packed != null, "%s actual prepared GLB imports as a PackedScene" % id)
	if packed == null:
		return
	var model := packed.instantiate() as Node3D
	root.add_child(model)
	var bounds := _bounds(model)
	_assert(absf(bounds.size.z - float(item.length)) < 0.012 and bounds.size.z > bounds.size.x and bounds.size.z > bounds.size.y, "%s actual model preserves its documented metre scale and Godot Z long axis" % id)
	var body := model.find_child("Body", true, false) as Node3D
	for name: String in item.groups:
		var group := model.find_child(name, true, false) as Node3D
		_assert(group != null and not group is MeshInstance3D, "%s has the dedicated source component group %s" % [id, name])
		if group != null:
			var component := _bounds(group)
			_assert(component.size.length() > 0.003, "%s %s contains actual geometry" % [id, name])
			if body != null and name != "Body":
				_assert(_bounds(body).grow(float(item.length) * 0.35).has_point(component.get_center()), "%s %s is assembled near its actual body" % [id, name])
	if id == &"sig516" and body != null:
		_check_foregrip(model, body)
		_check_scope(model.find_child("ACOG", true, false) as Node3D, body, "SIG516 original ACOG")
	if id == &"sr25" and body != null:
		_check_scope(model.find_child("Scope", true, false) as Node3D, body, "SR25 dedicated Leupold")
		_check_bipod(model, body)
	if id == &"m700" and body != null:
		_check_scope(model.find_child("Scope", true, false) as Node3D, body, "M700 original scope")
		_assert(model.find_child("Bipod", true, false) == null and model.find_child("ACOG", true, false) == null, "M700 retains its own scope without an added bipod or ACOG")
	_check_materials(model, id)
	print("CONVENTIONAL_RIFLE_ASSET id=", id, " bounds=", bounds)
	model.queue_free()
	await process_frame


func _check_scope(scope: Node3D, body: Node3D, label: String) -> void:
	if scope == null:
		return
	var optics := _bounds(scope)
	var receiver := _bounds(body)
	_assert(optics.get_center().y > receiver.get_center().y and absf(optics.get_center().x - receiver.get_center().x) < 0.05, label + " is mounted above and in line with the actual receiver")
	_assert(optics.size.z > optics.size.x, label + " points along the rifle barrel axis")


func _check_foregrip(model: Node3D, body: Node3D) -> void:
	var grip := model.find_child("Foregrip", true, false) as Node3D
	if grip == null:
		return
	var center := _bounds(grip).get_center()
	var receiver := _bounds(body).get_center()
	_assert(center.y < receiver.y and center.z < receiver.z, "SIG516 actual foregrip mounts below the forward handguard")


func _check_bipod(model: Node3D, body: Node3D) -> void:
	var bipod := model.find_child("Bipod", true, false) as Node3D
	if bipod == null:
		return
	var center := _bounds(bipod).get_center()
	var receiver := _bounds(body).get_center()
	_assert(center.y < receiver.y and center.z < receiver.z, "SR25 actual bipod mounts beneath the forward handguard")
	_check_bipod_contact(bipod, body)
	var left := bipod.find_child("LeftLeg", true, false) as Node3D
	var right := bipod.find_child("RightLeg", true, false) as Node3D
	_assert(left != null and right != null and left != right, "SR25 Harris bipod retains two independent real legs")
	if left != null and right != null:
		var left_bounds := _bounds(left)
		var right_bounds := _bounds(right)
		_assert(left_bounds.size.length() > 0.02 and right_bounds.size.length() > 0.02 and left_bounds.get_center().distance_to(right_bounds.get_center()) > 0.03, "SR25 bipod legs contain separately placed actual geometry")


func _check_materials(model: Node3D, id: StringName) -> void:
	var triangles := 0
	var textures := 0
	var valid := true
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += int(indices.size() / 3) if not indices.is_empty() else int(vertices.size() / 3)
			var material := instance.get_active_material(surface) as BaseMaterial3D
			valid = valid and material != null
			if material == null:
				continue
			valid = valid and is_finite(material.metallic) and material.metallic >= 0.0 and material.metallic <= 1.0 and is_finite(material.roughness) and material.roughness >= 0.0 and material.roughness <= 1.0
			if id == &"sr25":
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
				valid = valid and normals.size() == vertices.size()
				# Pure factor source materials can have no UV channel. Preserve and
				# validate any authored UVs without inventing data for plain surfaces.
				if uvs != null:
					valid = valid and uvs is PackedVector2Array and uvs.size() == vertices.size()
			for field: String in ["albedo_texture", "normal_texture", "metallic_texture", "roughness_texture", "ao_texture"]:
				var texture := material.get(field) as Texture2D
				if texture != null:
					textures += 1
					valid = valid and texture.get_width() > 0 and texture.get_height() > 0 and maxi(texture.get_width(), texture.get_height()) <= 2048
	_assert(triangles > 1000 and (textures > 0 or id == &"sr25") and valid, "%s imports real detailed geometry and usable source PBR materials with any textures up to 2K" % id)
	if id == &"sr25":
		_assert(textures == 0, "SR25 preserves the source factor PBR appearance and complete normals/UVs without inventing missing textures")
	print("CONVENTIONAL_RIFLE_MATERIALS id=", id, " triangles=", triangles, " textures=", textures)


func _check_bipod_contact(bipod: Node3D, body: Node3D) -> void:
	var base_points: Array[Vector3] = []
	var top_y := -INF
	for node in bipod.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var in_leg := false
		var ancestor := instance.get_parent()
		while ancestor != null and ancestor != bipod:
			in_leg = in_leg or ancestor.name in [&"LeftLeg", &"RightLeg"]
			ancestor = ancestor.get_parent()
		if in_leg or instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point := instance.global_transform * vertex
				base_points.append(point)
				top_y = maxf(top_y, point.y)
	var center_x := _bounds(bipod).get_center().x
	var top_points: Array[Vector3] = []
	for point in base_points:
		if point.y >= top_y - 0.002 and absf(point.x - center_x) <= 0.010:
			top_points.append(point)
	_assert(top_points.size() >= 2, "SR25 Harris contact probe selects real central top mounting vertices independently of its leg geometry")
	var closest_squared := INF
	for node in body.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var points := PackedVector3Array()
			for vertex in vertices:
				points.append(instance.global_transform * vertex)
			for triangle in range(0, indices.size(), 3):
				var a := points[indices[triangle]]
				var b := points[indices[triangle + 1]]
				var c := points[indices[triangle + 2]]
				for point in top_points:
					closest_squared = minf(closest_squared, _triangle_distance_squared(point, a, b, c))
	var distance := sqrt(closest_squared)
	print("SR25_HARRIS_CONTACT top_vertices=", top_points.size(), " mount_top_y=", top_y, " body_triangle_distance=", distance)
	_assert(distance <= 0.002, "SR25 actual Harris top mounting surface contacts an actual handguard triangle within 2mm instead of floating under the rifle")


func _triangle_distance_squared(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := b - a
	var ac := c - a
	var normal := ab.cross(ac)
	var length_squared := normal.length_squared()
	if length_squared > 0.000000000000000001:
		var projection := point - normal * ((point - a).dot(normal) / length_squared)
		var u := normal.dot(ab.cross(projection - a)) / length_squared
		var v := normal.dot((projection - a).cross(ac)) / length_squared
		if u >= -0.000001 and v >= -0.000001 and u + v <= 1.000001:
			return point.distance_squared_to(projection)
	var nearest := INF
	for pair: Array in [[a, b], [b, c], [c, a]]:
		var first: Vector3 = pair[0]
		var edge: Vector3 = pair[1] - first
		var progress := clampf((point - first).dot(edge) / maxf(edge.length_squared(), 0.000000000000000001), 0.0, 1.0)
		nearest = minf(nearest, point.distance_squared_to(first + edge * progress))
	return nearest


func _check_container(path: String, requires_images: bool) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	_assert(file != null, path + " can be read")
	if file == null:
		return
	var magic := file.get_32()
	var version := file.get_32()
	var length := file.get_32()
	_assert(magic == 0x46546c67 and version == 2 and length == file.get_length(), path + " is a complete glTF 2 binary container")
	var document: Dictionary = {}
	while file.get_position() + 8 <= file.get_length():
		var chunk_size := file.get_32()
		var chunk_type := file.get_32()
		if file.get_position() + chunk_size > file.get_length():
			_assert(false, path + " contains no truncated chunks")
			break
		var bytes := file.get_buffer(chunk_size)
		if chunk_type == 0x4e4f534a:
			var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
			if parsed is Dictionary:
				document = parsed
	file.close()
	if not requires_images:
		_assert(document.get("materials", []).size() == 23, "SR25 container preserves the original rifle/Leupold/Harris 23 PBR materials")
	var embedded: bool = not document.is_empty() and (not requires_images or not document.get("images", []).is_empty())
	for buffer: Dictionary in document.get("buffers", []):
		embedded = embedded and not buffer.has("uri")
	for image: Dictionary in document.get("images", []):
		embedded = embedded and not image.has("uri") and image.has("bufferView")
	_assert(embedded, path + " embeds the geometry and PBR image buffers without external dependencies")


func _check_mounts() -> void:
	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	for id: StringName in WEAPONS:
		var found := false
		for child in player.get_node("Camera3D/WeaponMount").get_children():
			if _has_property(child, "weapon_data") and child.weapon_data != null and child.weapon_data.weapon_id == id:
				found = true
		_assert(found, "%s is mounted in the real Player scene" % id)
	player.queue_free()
	await process_frame


func _check_runtime() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1920, 1080)
	_state.reset()
	_scene = (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	_player = _scene.get_node("Player")
	_hud = _scene.get_node("HUD")
	_player.global_position = Vector3(0, 100, 0)
	_player.rotation = Vector3.ZERO
	_player._pitch = 0.0
	_player._camera.rotation = Vector3.ZERO
	_player.set_process(false)
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	# A neutral, lit fixture makes the real source PBR and clipping readable.
	# The production range environment and player arm poses are not altered.
	var environments := _scene.find_children("*", "WorldEnvironment", true, false)
	if not environments.is_empty():
		var environment := (environments[0] as WorldEnvironment).environment.duplicate() as Environment
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0.42, 0.46, 0.52)
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color.WHITE
		environment.ambient_light_energy = 1.0
		environment.fog_enabled = false
		(environments[0] as WorldEnvironment).environment = environment
	for controller in _player.get_node("Camera3D/WeaponMount").get_children():
		controller.set_process(false)
		controller.set_physics_process(false)
		controller.set_process_unhandled_input(false)
		_controllers.append(controller)
		if _has_property(controller, "weapon_data") and controller.weapon_data != null and WEAPONS.has(controller.weapon_data.weapon_id):
			_guns[controller.weapon_data.weapon_id] = controller
	_assert(_guns.size() == 3, "actual range Player mounts all three service rifle controllers")
	if _guns.size() != 3:
		_scene.queue_free()
		current_scene = null
		await process_frame
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	root.get_node("Events").weapon_fired.connect(_on_shot)
	root.get_node("Events").weapon_reloaded.connect(_on_reload)
	_assert(DirAccess.make_dir_recursive_absolute(OUTPUT) == OK, "native rifle evidence directory is available")
	var insertion_only := "--m700-insertion-only" in OS.get_cmdline_user_args()
	for id: StringName in WEAPONS:
		if insertion_only and id != &"m700":
			continue
		_assert(_state.weapon_unlocked.get(id, false), "%s is unlocked by the actual weapons range" % id)
		_player._switch_weapon(id)
		_mouse_player(MOUSE_BUTTON_RIGHT, false)
		await _advance(0.25)
		_assert(_guns[id].is_visible_in_tree() and _hud._weapon_ammo.weapon_id == id, "%s switching shows its real model and updates its own HUD" % id)
		await RenderingServer.frame_post_draw
		_assert(_visible_gun_vertices(_guns[id]._weapon_node) >= 20, "%s actual hip gun geometry lies inside the real Player camera frustum" % id)
		if id == &"m700":
			_check_m700_hip_framing()
		await _capture("%s_hip" % id)
		if insertion_only:
			await _check_reload_runtime(id)
			continue
		if "--framing-only" in OS.get_cmdline_user_args():
			continue
		await _check_scope_runtime(id)
		if "--optics-only" in OS.get_cmdline_user_args():
			continue
		await _check_trigger_runtime(id)
		await _check_reload_runtime(id)
		await _check_pause_runtime(id)
	if "--framing-only" not in OS.get_cmdline_user_args() and not insertion_only:
		await _check_scope_switch()
		await _check_scope_scan_switch()
		await _check_legacy_reticle_pixels()
		if "--optics-only" not in OS.get_cmdline_user_args():
			await _check_accessory_runtime()
	root.get_node("Events").weapon_fired.disconnect(_on_shot)
	root.get_node("Events").weapon_reloaded.disconnect(_on_reload)
	_scene.queue_free()
	current_scene = null
	await process_frame
	await process_frame


func _advance(seconds: float) -> void:
	for frame in maxi(1, int(ceil(seconds * 60.0))):
		_player._process(1.0 / 60.0)
		for controller in _controllers:
			if controller.has_method("_physics_process"):
				controller._physics_process(1.0 / 60.0)
			if controller.has_method("_process"):
				controller._process(1.0 / 60.0)
		await process_frame


func _mouse_player(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	_player._unhandled_input(event)


func _press_key(key: Key, receiver = null) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	(receiver if receiver != null else _player)._unhandled_input(event)


func _trigger(weapon, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	weapon._unhandled_input(event)


func _loaded(id: StringName) -> int:
	return int(_state.get(String(id) + "_mag")) + (1 if _state.weapon_chambered.get(id, false) else 0)


func _set_loaded(id: StringName, total: int) -> void:
	_state.set(String(id) + "_mag", maxi(0, total - 1))
	_state.weapon_chambered[id] = total > 0


func _on_shot(id: StringName) -> void:
	_shots[id] = int(_shots.get(id, 0)) + 1


func _on_reload(id: StringName) -> void:
	_reloads[id] = int(_reloads.get(id, 0)) + 1


func _check_scope_runtime(id: StringName) -> void:
	var zooms: Array = [4] if id == &"sig516" else ([16, 32] if id == &"sr25" else [16, 32, 64])
	var target := StaticBody3D.new()
	target.add_to_group(&"range_target")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.10, 0.10, 0.01)
	shape.shape = box
	target.add_child(shape)
	var marker := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	marker.mesh = mesh
	target.add_child(marker)
	_scene.add_child(target)
	_player._pitch = 0.0
	_player._camera.rotation = Vector3.ZERO
	target.global_position = _player._camera.global_position - _player._camera.global_basis.z * 12.0
	await physics_frame
	await physics_frame
	var hip_width := _target_projected_width(target)
	_assert(hip_width > 1.0 and _player._camera.unproject_position(target.global_position).distance_to(Vector2(root.size) * 0.5) < 1.0, "%s real 0.10m target is visible on the hip optical axis before measuring magnification" % id)
	_mouse_player(MOUSE_BUTTON_RIGHT, true)
	await _advance(0.25)
	_assert(_state.is_aiming and _player._dmr_scope.is_visible_in_tree() and not _guns[id]._view_model.visible, "%s actual held right mouse activates its scope and hides its gun model" % id)
	for level in zooms.size():
		if level > 0:
			_mouse_player(MOUSE_BUTTON_WHEEL_UP, true)
			await _advance(0.12)
		var tactical = _player._dmr_tactical
		_assert(_state.current_weapon == id and _player._em86s_zoom_index == level and is_equal_approx(_player._camera.fov, _expected_scope_fov(float(zooms[level]))), "%s native wheel selects its geometrically correct %dX FOV without changing guns" % [id, zooms[level]])
		var actual_zoom := _target_projected_width(target) / hip_width
		print("CONVENTIONAL_SCOPE_PROJECTION id=", id, " label=", zooms[level], " hip_width=", hip_width, " scoped_width=", _target_projected_width(target), " actual_magnification=", actual_zoom, " fov=", _player._camera.fov)
		_assert(absf(actual_zoom / float(zooms[level]) - 1.0) <= 0.05, "%s real target projection is magnified %d times within 5 percent, independently of its zoom label" % [id, zooms[level]])
		var center := Vector2(root.size) * 0.5
		var from: Vector3 = _player._camera.project_ray_origin(center)
		var to: Vector3 = from + _player._camera.project_ray_normal(center) * 20.0
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = [_player.get_rid()]
		var hit: Dictionary = _player._camera.get_world_3d().direct_space_state.intersect_ray(query)
		_assert(not hit.is_empty() and hit.collider == target and _player._camera.unproject_position(target.global_position).distance_to(center) < 1.0, "%s %dX true center ray hits the real marker at the reticle optical axis" % [id, zooms[level]])
		_assert(tactical.zoom_text == "%dX" % zooms[level] and not tactical.electronics_enabled and tactical._targets.is_empty() and tactical._target_age.is_empty() and tactical._primary_target == null and tactical._range_text == "", "%s %dX uses a standard scope with no Target Finder, TRACK or range scan" % [id, zooms[level]])
		await _capture("%s_scope_%dx" % [id, zooms[level]])
		await _check_reticle_pixels(id, int(zooms[level]))
	_mouse_player(MOUSE_BUTTON_WHEEL_UP, true)
	await _advance(0.05)
	_assert(_player._em86s_zoom_index == zooms.size() - 1, "%s zoom clamps at its own upper bound" % id)
	for step in 4:
		_mouse_player(MOUSE_BUTTON_WHEEL_DOWN, true)
	await _advance(0.12)
	_assert(_player._em86s_zoom_index == 0 and _state.current_weapon == id, "%s zoom clamps at its own lower bound" % id)
	_mouse_player(MOUSE_BUTTON_RIGHT, false)
	await _advance(0.25)
	_assert(not _state.is_aiming and not _player._dmr_scope.visible and _guns[id]._view_model.visible, "%s actual right-mouse release restores its real hip model" % id)
	var initial_mode: StringName = _state.fire_modes[id]
	for step in 4:
		_press_key(KEY_X)
		_assert(_state.fire_modes[id] in ([&"auto", &"semi"] if id == &"sig516" else [&"semi"]), "%s X exposes only its real firing modes" % id)
	_assert(_state.fire_modes[id] == initial_mode, "%s mode cycling returns to its original mode" % id)
	target.queue_free()
	await process_frame


func _expected_scope_fov(zoom: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(GameConfig.FOV_BASE) * 0.5) / zoom))


func _target_projected_width(target: Node3D) -> float:
	var side: Vector3 = _player._camera.global_basis.x * 0.05
	return _player._camera.unproject_position(target.global_position - side).distance_to(_player._camera.unproject_position(target.global_position + side))


func _scope_pixel_image(label: String) -> Image:
	# Render the actual Player ShaderMaterial over a white fixture surface.
	# This separates black/red reticle pixels from world geometry and UI labels.
	var canvas := CanvasLayer.new()
	canvas.layer = 2
	var background := ColorRect.new()
	background.color = Color.WHITE
	background.size = Vector2(root.size)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(background)
	root.add_child(canvas)
	var tactical_visible: bool = _player._dmr_tactical.visible
	_player._dmr_tactical.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	_assert(result != null and not result.is_empty() and result.save_png(OUTPUT + "/" + label + ".png") == OK, label + " records real native reticle pixels from the current Player material")
	_player._dmr_tactical.visible = tactical_visible
	canvas.queue_free()
	await process_frame
	return result


func _reticle_color(color: Color, red: bool) -> bool:
	return color.r > 0.45 and color.g < 0.30 and color.b < 0.30 if red else maxf(color.r, maxf(color.g, color.b)) < 0.30


func _reticle_point(image: Image, position: Vector2, red: bool) -> bool:
	var center := Vector2(image.get_width(), image.get_height()) * 0.5
	var pixel := Vector2i((center + position * float(image.get_height())).round())
	for y in range(pixel.y - 1, pixel.y + 2):
		for x in range(pixel.x - 1, pixel.x + 2):
			if _reticle_color(image.get_pixel(x, y), red):
				return true
	return false


func _reticle_width(image: Image, position: Vector2, horizontal_axis: bool, red: bool) -> int:
	var center := Vector2(image.get_width(), image.get_height()) * 0.5
	var pixel := Vector2i((center + position * float(image.get_height())).round())
	var width := 0
	for offset in range(-12, 13):
		var at := pixel + (Vector2i(0, offset) if horizontal_axis else Vector2i(offset, 0))
		if _reticle_color(image.get_pixel(at.x, at.y), red):
			width += 1
	return width


func _check_reticle_pixels(id: StringName, zoom: int) -> void:
	var image := await _scope_pixel_image("%s_reticle_%dx" % [id, zoom])
	if image == null or image.is_empty():
		return
	if id == &"sig516":
		_assert(_reticle_point(image, Vector2.ZERO, true) and _reticle_point(image, Vector2(-0.010, 0.011), true) and _reticle_point(image, Vector2(0.010, 0.011), true) and not _reticle_point(image, Vector2(0.0, -0.010), true), "SIG516 real ACOG pixels form a red upward chevron with its aiming apex on the optical axis")
		var previous := INF
		for index in 4:
			var y := 0.060 + float(index) * 0.040
			var width := 0
			for x in range(int(image.get_width() * 0.5 - image.get_height() * 0.040), int(image.get_width() * 0.5 + image.get_height() * 0.040)):
				if _reticle_color(image.get_pixel(x, roundi(image.get_height() * (0.5 + y))), true):
					width += 1
			var expected := 2.0 * (0.026 - float(index) * 0.004) * image.get_height()
			_assert(absf(float(width) / expected - 1.0) <= 0.20 and float(width) < previous, "SIG516 actual red BDC row %d is present with a successively narrower ballistic bar" % (index + 1))
			previous = float(width)
	elif id == &"sr25":
		for horizontal in [true, false]:
			for sign_value in [-1.0, 1.0]:
				for index in 4:
					var offset := float(index + 1) * 0.040 * float(sign_value)
					var point := Vector2(offset, 0) if horizontal else Vector2(0, offset)
					var gap := point - (Vector2(0.020 * float(sign_value), 0) if horizontal else Vector2(0, 0.020 * float(sign_value)))
					var dot := _reticle_width(image, point, horizontal, false)
					var thin := _reticle_width(image, gap, horizontal, false)
					_assert(dot >= 4 and dot >= thin + 2 and thin >= 1 and thin <= 3, "SR25 actual black Mil-Dot axis=%s side=%s dot=%d is wider than the fine crosshair between dots" % [horizontal, sign_value, index + 1])
	elif id == &"m700":
		for horizontal in [true, false]:
			for sign_value in [-1.0, 1.0]:
				var inner := Vector2(0.060 * float(sign_value), 0) if horizontal else Vector2(0, 0.060 * float(sign_value))
				var outer := Vector2(0.200 * float(sign_value), 0) if horizontal else Vector2(0, 0.200 * float(sign_value))
				var thin := _reticle_width(image, inner, horizontal, false)
				var thick := _reticle_width(image, outer, horizontal, false)
				_assert(thin >= 1 and thin <= 3 and thick >= 6 and thick >= thin + 3, "M700 actual black Duplex axis=%s side=%s has a fine inner line and clearly thicker outer post" % [horizontal, sign_value])
				var dot_position := Vector2(0.040 * float(sign_value), 0) if horizontal else Vector2(0, 0.040 * float(sign_value))
				_assert(_reticle_width(image, dot_position, horizontal, false) <= 3, "M700 Duplex preserves its fine inner line without SR25 Mil-Dot circles")


func _check_legacy_reticle_pixels() -> void:
	for id: StringName in [&"dmr", &"em86s", &"em127g", &"em40t1"]:
		_player._switch_weapon(id)
		_mouse_player(MOUSE_BUTTON_RIGHT, true)
		await _advance(0.25)
		var image := await _scope_pixel_image("%s_legacy_reticle" % id)
		if image == null or image.is_empty():
			continue
		var point := Vector2(0.0198, 0.0198) if id == &"dmr" else (Vector2(0.011, -0.01915) if id == &"em40t1" else Vector2(0.014, 0.014))
		var pixel := Vector2i((Vector2(image.get_width(), image.get_height()) * 0.5 + point * float(image.get_height())).round())
		var cyan := false
		for y in range(pixel.y - 1, pixel.y + 2):
			for x in range(pixel.x - 1, pixel.x + 2):
				var color := image.get_pixel(x, y)
				cyan = cyan or (color.r < 0.65 and color.g > 0.65 and color.b > 0.65)
		_assert(cyan and _player._dmr_tactical.electronics_enabled, "%s actual legacy electronic reticle retains its cyan circle/diamond/grenade V after conventional scope switching" % id)
	_mouse_player(MOUSE_BUTTON_RIGHT, false)
	await _advance(0.20)


func _check_trigger_runtime(id: StringName) -> void:
	var weapon = _guns[id]
	_set_loaded(id, int(WEAPONS[id].mag))
	_state.fire_modes[id] = &"auto" if id == &"sig516" else &"semi"
	var before := _loaded(id)
	var shots_before: int = _shots.get(id, 0)
	var reserve_key: StringName = weapon._reserve_key
	var reserve_before: int = _state.get(reserve_key)
	_trigger(weapon, true)
	await _advance(0.50)
	_trigger(weapon, false)
	var fired: int = int(_shots.get(id, 0)) - shots_before
	_assert((fired >= 5 if id == &"sig516" else fired == 1) and _loaded(id) == before - fired and int(_state.get(reserve_key)) == reserve_before, "%s native trigger consumes exactly one chamber round per real shot and preserves reserve" % id)
	if id == &"m700":
		_assert(not _state.weapon_chambered[id] and weapon._bolt_left > 0.0, "M700 fired case remains unchambered during its actual bolt cycle")
		_assert(not weapon._bolt.transform.is_equal_approx(weapon._bolt_home) and weapon._bolt.position.distance_to(weapon._bolt_home.origin) >= 0.04, "M700 actual original bolt mesh lifts and pulls at least 4cm during its real cycle")
		await _capture("m700_bolt_open")
		var count := _loaded(id)
		_trigger(weapon, true)
		_trigger(weapon, false)
		_assert(_loaded(id) == count, "M700 rejects another native trigger edge before its bolt closes")
		await _advance(0.50)
		_assert(_state.weapon_chambered[id] and weapon._bolt_left <= 0.0 and _loaded(id) == count, "M700 loads the next chamber only after its real 0.85s bolt cycle without creating a round")
		_assert(weapon._bolt.transform.is_equal_approx(weapon._bolt_home), "M700 actual bolt closes to its original mesh transform after cycling")
	var quiet := _loaded(id)
	await _advance(0.25)
	_assert(_loaded(id) == quiet, "%s release stops firing without ghost continuation" % id)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_trigger(weapon, true)
	_trigger(weapon, false)
	_assert(_loaded(id) == quiet, "%s ignores trigger input after mouse capture is released" % id)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _check_reload_runtime(id: StringName) -> void:
	var weapon = _guns[id]
	_set_loaded(id, 3)
	var reserve_key: StringName = weapon._reserve_key
	_state.set(reserve_key, 100)
	var before_total := _loaded(id) + int(_state.get(reserve_key))
	var magazine: Node3D = weapon._magazine
	var magazine_home := magazine.transform
	var started_count: int = _reloads.get(id, 0)
	_press_key(KEY_R, weapon)
	_press_key(KEY_R, weapon)
	_assert(weapon._is_reloading and _loaded(id) == 3 and int(_state.get(reserve_key)) == 100, "%s native R begins once and defers ammunition settlement" % id)
	var pause_mag := _loaded(id)
	var pause_reserve: int = _state.get(reserve_key)
	var pause_progress: float = weapon._reload_progress if id == &"m700" else weapon._arms_animation.current_animation_position
	weapon.set_physics_process(true)
	weapon.set_process(true)
	paused = true
	await create_timer(0.20, true).timeout
	paused = false
	weapon.set_physics_process(false)
	weapon.set_process(false)
	var resumed_progress: float = weapon._reload_progress if id == &"m700" else weapon._arms_animation.current_animation_position
	_assert(weapon._is_reloading and _loaded(id) == pause_mag and int(_state.get(reserve_key)) == pause_reserve and is_equal_approx(resumed_progress, pause_progress), "%s actual SceneTree pause freezes reload progress and ammunition settlement" % id)
	var duration: float = weapon.weapon_data.reload_time
	await _advance(duration * 0.45)
	await RenderingServer.frame_post_draw
	_assert(_visible_arm_vertices(weapon._arms_node) >= 40, "%s real posed black-arm geometry stays visible during its actual reload" % id)
	if id == &"m700":
		_assert(magazine.transform.is_equal_approx(magazine_home) and _loaded(id) == 3, "M700 keeps its actual internal magazine in place and does not grant an early cartridge")
		_assert(weapon._loading_round.is_visible_in_tree(), "M700 presents its actual individual cartridge during the native retrieval-to-insertion phase")
		var round_mesh := weapon._loading_round as MeshInstance3D
		var round_bounds := AABB()
		var first_round_point := true
		var round_points: Array[Vector3] = []
		var round_axes: Basis = weapon._weapon_node.global_basis.orthonormalized().inverse()
		for surface in round_mesh.mesh.get_surface_count():
			var vertices: PackedVector3Array = round_mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				round_points.append(round_mesh.global_transform * vertex)
				var point: Vector3 = round_axes * (round_mesh.global_transform * vertex - round_mesh.global_position)
				round_bounds = AABB(point, Vector3.ZERO) if first_round_point else round_bounds.expand(point)
				first_round_point = false
		_assert(absf(round_bounds.size.z - 0.0711) < 0.002 and absf(round_bounds.size.x - 0.0119) < 0.002 and absf(round_bounds.size.y - 0.0119) < 0.002, "M700 actual inserted cartridge stays 71.1mm long and 11.9mm wide with its long axis along the gun instead of flattened by rotated scaling")
		await _check_m700_insertion_visibility(round_mesh, round_points)
		await _advance(duration * 0.65)
		_assert(_loaded(id) == 4 and int(_state.get(reserve_key)) == 99, "M700 inserts its first real cartridge separately before completing the next")
		await _advance(duration + 0.15)
	else:
		_assert(not magazine.transform.is_equal_approx(magazine_home) or not magazine.visible, "%s moves its real detachable magazine during reload" % id)
		await _capture("%s_magazine_pull" % id)
		await _advance(duration * 0.60 + 0.15)
	_assert(not weapon._is_reloading and int(_state.get(String(id) + "_mag")) == int(WEAPONS[id].mag) and _state.weapon_chambered[id] and _loaded(id) == int(WEAPONS[id].mag) + 1, "%s tactical reload reaches its actual magazine capacity plus the retained chamber round" % id)
	_assert(_loaded(id) + int(_state.get(reserve_key)) == before_total and int(_reloads.get(id, 0)) == started_count + 1, "%s repeated R settles exactly once and conserves all ammunition" % id)
	_assert(_hud._weapon_ammo.mag == _loaded(id) and _hud._weapon_ammo.reserve == int(_state.get(reserve_key)), "%s actual completed reload updates its own HUD" % id)
	if id == &"m700":
		await _advance(0.90)
		_assert(weapon._bolt_left <= 0.0 and weapon._bolt.transform.is_equal_approx(weapon._bolt_home), "M700 closes its original bolt before beginning a separate reload-cancellation case")
	_set_loaded(id, 3)
	_press_key(KEY_R, weapon)
	await _advance(duration * 0.25)
	var cancelled_total := _loaded(id) + int(_state.get(reserve_key))
	_player._switch_weapon(&"pistol")
	await _advance(duration + 0.15)
	_assert(not weapon._is_reloading and _loaded(id) + int(_state.get(reserve_key)) == cancelled_total, "%s switching cancels unfinished reload without delayed free ammunition" % id)
	_player._switch_weapon(id)
	await _advance(0.15)


func _check_scope_switch() -> void:
	_player._switch_weapon(&"m700")
	_mouse_player(MOUSE_BUTTON_RIGHT, true)
	_mouse_player(MOUSE_BUTTON_WHEEL_UP, true)
	_mouse_player(MOUSE_BUTTON_WHEEL_UP, true)
	await _advance(0.20)
	_assert(_player._em86s_zoom_index == 2, "M700 reaches its third scope tier before a live scoped switch")
	_player._switch_weapon(&"sr25")
	await _advance(0.20)
	_assert(_state.is_aiming and _player._em86s_zoom_index == 0 and is_equal_approx(_player._camera.fov, _expected_scope_fov(16.0)), "switching from M700 64X to SR25 safely resets to its first real tier while holding aim")
	_mouse_player(MOUSE_BUTTON_RIGHT, false)
	await _advance(0.20)
	_mouse_player(MOUSE_BUTTON_RIGHT, true)
	await _advance(0.20)
	_assert(_player._em86s_zoom_index == 0, "closing and reopening a conventional scope restores its initial tier")
	_mouse_player(MOUSE_BUTTON_RIGHT, false)
	await _advance(0.20)
	var before: StringName = _state.current_weapon
	_mouse_player(MOUSE_BUTTON_WHEEL_DOWN, true)
	_assert(_state.current_weapon != before, "native wheel resumes weapon selection after releasing the scope")


func _check_pause_runtime(id: StringName) -> void:
	var weapon = _guns[id]
	var original_data = weapon.weapon_data
	weapon.weapon_data = original_data.duplicate()
	# A short independent fixture proves settlement against a pause lasting
	# longer than the reload, while keeping frozen production timing intact.
	weapon.weapon_data.reload_time = 0.30
	_set_loaded(id, 3)
	var reserve_key: StringName = weapon._reserve_key
	var before_total := _loaded(id) + int(_state.get(reserve_key))
	var before_events: int = _reloads.get(id, 0)
	_press_key(KEY_R, weapon)
	_assert(weapon._is_reloading, "%s long-pause fixture starts the actual reload path" % id)
	weapon.set_physics_process(true)
	weapon.set_process(true)
	paused = true
	await create_timer(0.45, true).timeout
	paused = false
	weapon.set_physics_process(false)
	weapon.set_process(false)
	_assert(weapon._is_reloading and _loaded(id) == 3 and int(_reloads.get(id, 0)) == before_events, "%s a real pause longer than the entire reload cannot transfer ammunition or emit completion" % id)
	var loaded_missing: int = int(WEAPONS[id].mag) - 2
	await _advance(0.30 * (loaded_missing if id == &"m700" else 1) + 1.0)
	_assert(not weapon._is_reloading and _loaded(id) == int(WEAPONS[id].mag) + 1 and _loaded(id) + int(_state.get(reserve_key)) == before_total and int(_reloads.get(id, 0)) == before_events + 1, "%s resuming completes one real reload with conserved ammunition" % id)
	weapon.weapon_data = original_data


func _check_scope_scan_switch() -> void:
	_player._pitch = 0.0
	_player._camera.rotation = Vector3.ZERO
	var target := StaticBody3D.new()
	target.add_to_group(&"range_target")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.2)
	shape.shape = box
	shape.position.y = 0.9
	target.add_child(shape)
	_scene.add_child(target)
	target.global_position = _player._camera.global_position - _player._camera.global_basis.z * 12.0 - Vector3(0, 0.9, 0)
	await physics_frame
	await physics_frame
	_player._switch_weapon(&"dmr")
	_mouse_player(MOUSE_BUTTON_RIGHT, true)
	await _advance(0.30)
	var overlay = _player._dmr_tactical
	overlay._refresh_left = 0.0
	overlay._process(0.10)
	_assert(overlay.electronics_enabled and overlay._primary_target == target and not overlay._targets.is_empty() and is_finite(overlay._range_distance), "actual existing DMR scope positively tracks and ranges a real visible target before switching")
	_player._switch_weapon(&"m700")
	await _advance(0.30)
	overlay._process(0.10)
	_assert(_state.is_aiming and not overlay.electronics_enabled and overlay._targets.is_empty() and overlay._target_age.is_empty() and overlay._primary_target == null and overlay._range_text == "", "actual held-scope switch to M700 clears real prior electronic tracking while the same target stays visible")
	_player._switch_weapon(&"dmr")
	await _advance(0.30)
	overlay._refresh_left = 0.0
	overlay._process(0.10)
	_assert(overlay.electronics_enabled and overlay._primary_target == target and not overlay._targets.is_empty(), "actual switch back to the existing DMR restores target finding after conventional optics")
	_mouse_player(MOUSE_BUTTON_RIGHT, false)
	await _advance(0.20)
	target.queue_free()
	await process_frame


func _check_accessory_runtime() -> void:
	_player._switch_weapon(&"sig516")
	var remembered: Dictionary = _state.weapon_accessory_modes.duplicate()
	var accessory = _guns[&"sig516"].find_child("WeaponAccessory", true, false)
	_assert(accessory != null, "SIG516 has its actual PEQ15 and weapon-light controller")
	if accessory == null:
		return
	for mode: StringName in [&"flashlight", &"combined", &"laser"]:
		_press_key(KEY_L)
		await _advance(0.08)
		accessory._process(0.0)
		_assert(_state.weapon_accessory_modes[&"sig516"] == mode and accessory._flashlight.visible == (mode in [&"flashlight", &"combined"]), "SIG516 native L selects %s and controls its real world light" % mode)
		_assert(_state.weapon_accessory_modes[&"g17"] == remembered[&"g17"] and _state.weapon_accessory_modes[&"mpx"] == remembered[&"mpx"], "SIG516 L preserves the independent existing G17 and MPX modes")
	_player._switch_weapon(&"sr25")
	accessory._process(0.0)
	_assert(not accessory._flashlight.visible and not accessory._laser_beam.visible, "switching away from SIG516 hides its world accessory effects")


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_assert(image != null and not image.is_empty() and image.save_png(OUTPUT + "/" + label + ".png") == OK, label + " captures the actual native 1920x1080 view")


func _visible_gun_vertices(owner: Node3D) -> int:
	var count := 0
	for node in owner.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null or not instance.is_visible_in_tree():
			continue
		for surface in instance.mesh.get_surface_count():
			var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for point in vertices:
				if _player._camera.is_position_in_frustum(instance.global_transform * point):
					count += 1
	return count


func _m700_framing_points(group: Node3D, receiver_only: bool) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if group == null:
		return points
	var weapon: Node3D = _guns[&"m700"]._weapon_node
	for child in group.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.mesh == null or not instance.is_visible_in_tree():
			continue
		for surface in instance.mesh.get_surface_count():
			var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point := instance.global_transform * vertex
				var local := weapon.to_local(point)
				# The source loading port is z=.1416. This independent body band
				# contains its upper receiver, excluding the long barrel and stock.
				if receiver_only and (local.z < 0.03 or local.z > 0.22 or local.y < 0.005):
					continue
				points.append(point)
	return points


func _projected_component(points: Array[Vector3], offset := Vector3.ZERO) -> Dictionary:
	var inside := 0
	var behind := 0
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var safe_view := Rect2(Vector2(12, 12), Vector2(root.size) - Vector2(24, 24))
	for original in points:
		var point := original + offset
		if _player._camera.is_position_behind(point):
			behind += 1
			continue
		var screen: Vector2 = _player._camera.unproject_position(point)
		minimum = minimum.min(screen)
		maximum = maximum.max(screen)
		if safe_view.has_point(screen) and _player._camera.is_position_in_frustum(point):
			inside += 1
	return {"total": points.size(), "inside": inside, "behind": behind, "rect": Rect2(minimum, maximum - minimum)}


func _check_m700_hip_framing() -> void:
	var weapon = _guns[&"m700"]
	var scope := _m700_framing_points(weapon._weapon_node.find_child("Scope", true, false) as Node3D, false)
	var receiver := _m700_framing_points(weapon._weapon_node.find_child("Body", true, false) as Node3D, true)
	_assert(scope.size() > 1000 and receiver.size() > 20, "M700 hip probes select the complete original optic and independent upper receiver instead of barrel vertices")
	var optic := _projected_component(scope)
	var body := _projected_component(receiver)
	print("M700_HIP_FRAMING current=", GameConfig.BLACK_LONG_GUN_PROFILES[&"m700"].hip_rearward, " scope=", optic, " receiver=", body)
	_assert(optic.total > 0 and optic.inside == optic.total and optic.behind == 0 and optic.rect.size.x >= 12.0 and optic.rect.size.y >= 12.0, "M700 hip shows its complete original scope inside the native screen with a 12px edge margin")
	_assert(body.total > 0 and body.inside >= ceili(float(body.total) * 0.90) and body.behind == 0, "M700 hip shows at least 90 percent of its actual upper receiver inside the native screen")
	# Report sensitivity without changing the controller, Config, or arm pose.
	for candidate in [0.20, 0.10, 0.0, -0.10, -0.20, -0.25, -0.30]:
		var local: Vector3 = weapon._pose_extra.basis * Vector3(0, 0, float(candidate) - float(GameConfig.BLACK_LONG_GUN_PROFILES[&"m700"].hip_rearward))
		var offset: Vector3 = weapon._weapon_node.get_parent().global_basis * local
		print("M700_HIP_CANDIDATE rearward=", candidate, " scope=", _projected_component(scope, offset), " receiver=", _projected_component(receiver, offset))


func _check_m700_insertion_visibility(round_mesh: MeshInstance3D, round_points: Array[Vector3]) -> void:
	var weapon = _guns[&"m700"]
	var cartridge := _projected_component(round_points)
	var receiver := _projected_component(_m700_framing_points(weapon._weapon_node.find_child("Body", true, false) as Node3D, true))
	var port := weapon._weapon_node.get_node_or_null(^"M700Scoped/RoundPort") as Node3D
	_assert(port != null, "M700 insertion probe resolves the original receiver RoundPort marker")
	print("M700_INSERT_FRAMING round=", cartridge, " receiver=", receiver)
	_assert(cartridge.total > 0 and cartridge.inside == cartridge.total and cartridge.behind == 0, "M700 actual loading cartridge has all original mesh vertices inside the native screen with a 12px edge margin")
	_assert(receiver.total > 20 and receiver.inside >= ceili(float(receiver.total) * 0.90) and receiver.behind == 0, "M700 insertion keeps at least 90 percent of its independent actual upper receiver inside the native screen")
	if port != null:
		var port_points: Array[Vector3] = [port.global_position]
		var projected_port := _projected_component(port_points)
		print("M700_INSERT_PORT ", projected_port)
		_assert(projected_port.inside == 1 and projected_port.behind == 0, "M700 original receiver RoundPort stays inside the native screen with a 12px edge margin during insertion")
	var footprint := _round_screen_footprint(round_mesh)
	var round_transform := round_mesh.global_transform
	var progress: float = weapon._reload_progress
	var animation_time: float = weapon._arms_animation.current_animation_position
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var shown: Image = root.get_texture().get_image()
	# Only this actual mesh is hidden. Manual arm animation and disabled fixture
	# controllers hold the same receiver, cartridge transform and hand pose.
	round_mesh.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var hidden: Image = root.get_texture().get_image()
	round_mesh.visible = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_assert(round_mesh.global_transform.is_equal_approx(round_transform) and is_equal_approx(weapon._reload_progress, progress) and is_equal_approx(weapon._arms_animation.current_animation_position, animation_time), "M700 cartridge shown/hidden native frames preserve the actual insertion and hand pose")
	var images_ready := shown != null and hidden != null and not shown.is_empty() and not hidden.is_empty() and shown.get_size() == hidden.get_size()
	_assert(images_ready, "M700 cartridge shown/hidden comparison obtains matching actual native frames")
	if not images_ready:
		return
	_assert(shown.save_png(OUTPUT + "/m700_round_insert.png") == OK and hidden.save_png(OUTPUT + "/m700_round_insert_hidden.png") == OK, "M700 insertion records actual cartridge shown/hidden evidence without replacing its material or moving its hands")
	var changed := 0
	for pixel: Vector2i in footprint:
		if pixel.x < 0 or pixel.y < 0 or pixel.x >= shown.get_width() or pixel.y >= shown.get_height():
			continue
		var a := shown.get_pixel(pixel.x, pixel.y)
		var b := hidden.get_pixel(pixel.x, pixel.y)
		if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 0.025:
			changed += 1
	var required := maxi(12, ceili(float(footprint.size()) * 0.08))
	print("M700_INSERT_PIXELS projected_mesh_pixels=", footprint.size(), " changed=", changed, " required=", required)
	_assert(not footprint.is_empty() and changed >= required, "M700 real cartridge changes at least 12 native pixels and 8 percent of its actual projected mesh footprint instead of merely being marked visible behind the hands or off screen")
	if "--m700-occlusion-diagnostic" in OS.get_cmdline_user_args():
		await _diagnose_m700_arm_occlusion(round_mesh, footprint)


func _diagnose_m700_arm_occlusion(round_mesh: MeshInstance3D, footprint: Dictionary) -> void:
	var weapon = _guns[&"m700"]
	var arms: Node3D = weapon._arms_node
	var arms_visible := arms.visible
	var round_visible := round_mesh.visible
	var palm_world: Vector3 = weapon._native_arms.skeleton.global_transform * weapon._native_arms._palm_position(1)
	print("M700_DIAGNOSTIC_ONLY geometry round_world=", round_mesh.global_position, " round_camera=", _player._camera.to_local(round_mesh.global_position), " round_basis=", round_mesh.global_basis, " palm_world=", palm_world, " support_basis=", weapon._native_arms.support_basis_world(), " hand_offset_world=", weapon._weapon_node.global_basis * GameConfig.M700_ROUND_HAND_OFFSET)
	_diagnose_m700_baked_contact(round_mesh, palm_world)
	arms.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var shown: Image = root.get_texture().get_image()
	round_mesh.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var hidden: Image = root.get_texture().get_image()
	round_mesh.visible = round_visible
	arms.visible = arms_visible
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if shown == null or hidden == null or shown.is_empty() or hidden.is_empty() or shown.get_size() != hidden.get_size():
		print("M700_DIAGNOSTIC_ONLY no matching native frames; original acceptance remains unchanged")
		return
	var changed := 0
	for pixel: Vector2i in footprint:
		if pixel.x < 0 or pixel.y < 0 or pixel.x >= shown.get_width() or pixel.y >= shown.get_height():
			continue
		var a := shown.get_pixel(pixel.x, pixel.y)
		var b := hidden.get_pixel(pixel.x, pixel.y)
		if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 0.025:
			changed += 1
	print("M700_DIAGNOSTIC_ONLY arms_hidden projected_mesh_pixels=", footprint.size(), " cartridge_changed=", changed, " shown_save=", shown.save_png(OUTPUT + "/m700_round_no_arms_diagnostic.png"), " hidden_save=", hidden.save_png(OUTPUT + "/m700_round_no_arms_hidden_diagnostic.png"), " restored_arms=", arms.visible, " restored_round=", round_mesh.visible)


func _diagnose_m700_baked_contact(round_mesh: MeshInstance3D, palm_world: Vector3) -> void:
	var weapon = _guns[&"m700"]
	var skeleton: Skeleton3D = weapon._native_arms.skeleton
	var axes: Basis = weapon._weapon_node.global_basis.orthonormalized().inverse()
	var palms: Array[Vector3] = []
	var thumbs: Array = []
	var indexes: Array = []
	var palm_sum := Vector3.ZERO
	for child in weapon._arms_node.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.mesh == null or instance.skin == null:
			continue
		var posed := instance.bake_mesh_from_current_skeleton_pose()
		if posed == null:
			continue
		var bind_names: Array[StringName] = []
		for bind in instance.skin.get_bind_count():
			var name := instance.skin.get_bind_name(bind)
			if name == &"":
				name = skeleton.get_bone_name(instance.skin.get_bind_bone(bind))
			bind_names.append(name)
		for surface in instance.mesh.get_surface_count():
			var source := instance.mesh.surface_get_arrays(surface)
			var bones: PackedInt32Array = source[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = source[Mesh.ARRAY_WEIGHTS]
			var vertices: PackedVector3Array = posed.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			var width: int = bones.size() / vertices.size()
			for vertex in vertices.size():
				var palm_weight := 0.0
				var thumb_weight := 0.0
				var index_weight := 0.0
				for influence in width:
					var offset := vertex * width + influence
					var name := bind_names[bones[offset]]
					if name in [&"L_wrist_04", &"L_palm_017"]:
						palm_weight += weights[offset]
					elif name == &"L_thumb3_07":
						thumb_weight += weights[offset]
					elif name == &"L_point3_011":
						index_weight += weights[offset]
				var world := instance.global_transform * vertices[vertex]
				var point := axes * (world - palm_world)
				if palm_weight > GameConfig.BLACK_LONG_GUN_PALM_WEIGHT:
					palms.append(point)
					palm_sum += world
				if thumb_weight > GameConfig.BLACK_LONG_GUN_PALM_WEIGHT:
					thumbs.append({"point": point, "vertex": vertex})
				if index_weight > GameConfig.BLACK_LONG_GUN_PALM_WEIGHT:
					indexes.append({"point": point, "vertex": vertex})
	if palms.is_empty() or thumbs.is_empty() or indexes.is_empty():
		print("M700_DIAGNOSTIC_ONLY baked contact masks unavailable palm=", palms.size(), " thumb=", thumbs.size(), " index=", indexes.size())
		return
	var bounds := AABB(palms[0], Vector3.ZERO)
	for point in palms:
		bounds = bounds.expand(point)
	var nearest := INF
	var thumb: Dictionary = {}
	var index: Dictionary = {}
	for a: Dictionary in thumbs:
		for b: Dictionary in indexes:
			var distance: float = (a.point as Vector3).distance_squared_to(b.point as Vector3)
			if distance < nearest:
				nearest = distance
				thumb = a
				index = b
	var pinch: Vector3 = ((thumb.point as Vector3) + (index.point as Vector3)) * 0.5
	var tail: Vector3 = axes * (round_mesh.to_global(Vector3(0, -0.5, 0)) - palm_world)
	print("M700_DIAGNOSTIC_ONLY baked palm_vertices=", palms.size(), " thumb_vertices=", thumbs.size(), " index_vertices=", indexes.size(), " palm_min_mm=", bounds.position * 1000.0, " palm_max_mm=", bounds.end * 1000.0, " cached_centroid_error_mm=", (palm_sum / float(palms.size())).distance_to(palm_world) * 1000.0)
	print("M700_DIAGNOSTIC_ONLY baked thumb_id=", thumb.vertex, " index_id=", index.vertex, " thumb_mm=", (thumb.point as Vector3) * 1000.0, " index_mm=", (index.point as Vector3) * 1000.0, " pinch_mm=", pinch * 1000.0, " gap_mm=", sqrt(nearest) * 1000.0, " actual_tail_mm=", tail * 1000.0, " pinch_tail_error_mm=", pinch.distance_to(tail) * 1000.0, " derived_offset=", Vector3(0, 0, GameConfig.M700_ROUND_LENGTH * 0.5) - pinch)


func _round_screen_footprint(instance: MeshInstance3D) -> Dictionary:
	var footprint := {}
	# Union the rasterised source triangles so front/back overlap cannot inflate
	# the physical cartridge's projected area and a bounding box is not its area.
	for surface in instance.mesh.get_surface_count():
		var arrays := instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var projected: Array[Vector2] = []
		for vertex in vertices:
			projected.append(_player._camera.unproject_position(instance.global_transform * vertex))
		if indices.is_empty():
			for index in vertices.size():
				indices.append(index)
		for triangle in range(0, indices.size(), 3):
			var a := projected[indices[triangle]]
			var b := projected[indices[triangle + 1]]
			var c := projected[indices[triangle + 2]]
			var minimum := a.min(b).min(c)
			var maximum := a.max(b).max(c)
			if not is_finite(minimum.x) or not is_finite(minimum.y) or not is_finite(maximum.x) or not is_finite(maximum.y) or maximum.x - minimum.x > root.size.x * 2 or maximum.y - minimum.y > root.size.y * 2:
				continue
			var area := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
			if absf(area) < 0.000001:
				continue
			for y in range(floori(minimum.y), ceili(maximum.y)):
				for x in range(floori(minimum.x), ceili(maximum.x)):
					var p := Vector2(x + 0.5, y + 0.5)
					var ab := (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
					var bc := (c.x - b.x) * (p.y - b.y) - (c.y - b.y) * (p.x - b.x)
					var ca := (a.x - c.x) * (p.y - c.y) - (a.y - c.y) * (p.x - c.x)
					if (ab >= 0.0 and bc >= 0.0 and ca >= 0.0) or (ab <= 0.0 and bc <= 0.0 and ca <= 0.0):
						footprint[Vector2i(x, y)] = true
	return footprint


func _visible_arm_vertices(owner: Node3D) -> int:
	var count := 0
	for node in owner.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null or instance.skin == null or not instance.is_visible_in_tree():
			continue
		var posed := instance.bake_mesh_from_current_skeleton_pose()
		if posed == null:
			continue
		for surface in posed.get_surface_count():
			var vertices: PackedVector3Array = posed.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for point in vertices:
				if _player._camera.is_position_in_frustum(instance.global_transform * point):
					count += 1
	return count


func _bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point := instance.global_transform * vertex
				if first:
					result = AABB(point, Vector3.ZERO)
					first = false
				else:
					result = result.expand(point)
	return result


func _has_property(object: Object, name: String) -> bool:
	for property in object.get_property_list():
		if property.name == name:
			return true
	return false


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _finish() -> void:
	print("CONVENTIONAL_RIFLES assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures else 0)
