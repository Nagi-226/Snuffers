## Real daylight range: native gun triangles and renderer-baked palm/shoulder topology.
extends SceneTree

const OUTPUT := "res://tmp_shots/spas12_pose_daylight"
const GUN_MESHES := ["Object_21", "Object_37", "Object_23", "Object_19"]
const PALM_NAMES := [["R_wrist_028", "R_palm_041"], ["L_wrist_04", "L_palm_017"]]
const UPPER_NAMES := ["R_arm_026", "L_arm_02"]
const LEFT_TIPS := ["L_point3_011", "L_middle3_015", "L_ring3_020", "L_pink3_024", "L_thumb3_07"]
const LEFT_FINGERS := ["L_point1_09", "L_point2_010", "L_point3_011", "L_middle1_013", "L_middle2_014", "L_middle3_015", "L_ring1_018", "L_ring2_019", "L_ring3_020", "L_pink1_022", "L_pink2_023", "L_pink3_024", "L_thumb1_05", "L_thumb2_06", "L_thumb3_07"]
# Native measurements from the unmodified daylight geometry run, not grip/profile expectations.
const HIP_GUN_CAMERA := Transform3D(Basis(Vector3(0.96638995, 0, -0.25708055), Vector3(0.01284867, 0.99875027, 0.04829937), Vector3(0.25675929, -0.04997917, 0.96518224)), Vector3(0.29170609, -0.31095374, -0.49558640))
const ADS_GUN_CAMERA := Transform3D(Basis.IDENTITY, Vector3(-0.04999924, -0.135, -0.82000160))
const SIGHT_TIPS := {"Object_23": Vector3(0.05055246, 0.08998843, -0.69743532), "Object_19": Vector3(0.05055252, 0.10013235, -0.16206540)}

var _assertions := 0
var _failures := 0
var _world: Node3D
var _player
var _weapon
var _state
var _controller
var _day_night
var _materials: Dictionary = {}
var _topology: Array[Dictionary] = []
var _samples: Array[Dictionary] = []
var _geometry_only := false
var _contact_roi: Dictionary = {}
var _rest: Array[Transform3D] = []
var _lengths: Array[float] = []
var _binds: Array = []
var _source_arms: Node3D
var _source_skeleton: Skeleton3D
var _source_animation: AnimationPlayer
var _hold_fingers: Dictionary = {}


func _init() -> void:
	Engine.max_fps = 60
	call_deferred("_run")


func _run() -> void:
	_geometry_only = "--geometry-only" in OS.get_cmdline_user_args()
	create_timer(180.0).timeout.connect(func() -> void:
		push_error("SPAS daylight geometry timed out")
		quit(1))
	_assert(DisplayServer.get_name() != "headless", "daylight geometry uses native rendering")
	if _failures:
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	_assert(DirAccess.make_dir_recursive_absolute(OUTPUT) == OK, "daylight evidence directory opens")
	_state = root.get_node("GameState")
	_state.reset()
	# SceneTree script preloads precede autoload registration; load this contract consumer now.
	_day_night = load("res://scripts/levels/day_night_controller.gd")
	_world = (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	_assert(_world != null, "production weapons range loads")
	if _world == null:
		quit(1)
		return
	root.add_child(_world)
	current_scene = _world
	_player = _world.get_node("Player")
	_weapon = _player.get_node("Camera3D/WeaponMount/Spas12")
	_controller = _world.get_node("GreyboxArena/DayNightController")
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	for child in _player.get_node("Camera3D/WeaponMount").get_children():
		child.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_player.global_position = Vector3(44, 0.1, 19)
	_player.rotation = Vector3(0, PI, 0)
	_player._pitch = 0.0
	_player._camera.rotation = Vector3.ZERO
	_controller.set_mode(_day_night.Mode.DAY)
	await _settle(8)
	var prior_weapon: StringName = _state.current_weapon
	var prior_aiming: bool = _state.is_aiming
	var prior_unlock: bool = _state.weapon_unlocked[&"spas12"]
	_state.weapon_unlocked[&"spas12"] = true
	_player._switch_weapon(&"spas12")
	_player._set_aiming(false)
	await _settle(45)
	# Let the production HUD's temporary selector expire before the daylight capture.
	await create_timer(root.get_node("GameConfig").WEAPON_SELECTOR_HOLD_TIME + 0.05).timeout
	await _settle(2)
	_check_daylight()
	_capture_materials()
	_build_topology()
	_capture_source_rig()
	await _sample("hip")
	if _geometry_only:
		_player._set_aiming(true)
		await _settle(45)
		await _sample("ads")
	else:
		await _check_actions()
	_player._set_aiming(false)
	_player._switch_weapon(prior_weapon)
	_state.weapon_unlocked[&"spas12"] = prior_unlock
	_player._set_aiming(prior_aiming)
	await _settle(8)
	_assert(_state.current_weapon == prior_weapon and _state.is_aiming == prior_aiming and _state.weapon_unlocked[&"spas12"] == prior_unlock, "diagnostic restores selection, aiming and unlock state")
	_check_materials()
	_write_json(OUTPUT + "/report.json", {"geometry_only": _geometry_only, "assertions": _assertions, "failures": _failures, "samples": _samples})
	_source_arms.queue_free()
	_world.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	var mix_period := AudioServer.get_time_since_last_mix() + AudioServer.get_time_to_next_mix()
	await create_timer(maxf(mix_period, 1.0 / Engine.max_fps)).timeout
	await process_frame
	await process_frame
	print("SPAS_DAYLIGHT_POSE COMPLETED assertions=", _assertions, " failures=", _failures, " samples=", _samples.size())
	quit(1 if _failures else 0)


func _check_daylight() -> void:
	var environment: Environment = _controller.get_node("WorldEnvironment").environment
	var sun: DirectionalLight3D = _controller.get_node("SunLight")
	_assert(not _controller.is_night() and not _state.is_night and not _state.night_vision, "actual controller selects DAY and disables night vision")
	_assert(environment.background_mode == Environment.BG_SKY and environment.sky != null and environment.sky.sky_material is PanoramaSkyMaterial, "real range uses its production panoramic day sky")
	_assert(environment.sky.sky_material.panorama == _controller.day_sky, "range sky retains the actual configured panorama")
	_assert(is_equal_approx(sun.light_energy, _day_night.DAY_LIGHT_ENERGY) and sun.light_color.is_equal_approx(_day_night.DAY_LIGHT_COLOR) and sun.shadow_enabled, "actual directional Sun retains day energy, color and shadows")
	_assert(_player.global_position.is_equal_approx(Vector3(44, 0.1, 19)) and is_equal_approx(_player.rotation.y, PI), "range preserves the feedback camera station and yaw")
	_assert(_weapon._native_arms != null and _weapon._arms_skeleton.get_bone_count() == 60, "SPAS uses the production sixty-joint native black arms")


func _settle(frames: int) -> void:
	for frame in frames:
		await physics_frame
		await process_frame
	await RenderingServer.frame_post_draw


func _capture_source_rig() -> void:
	_source_arms = (load("res://addons/community_weapons/black_pistol_arms.glb") as PackedScene).instantiate() as Node3D
	root.add_child(_source_arms)
	_source_arms.visible = false
	var skeleton := _source_arms.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var animation := _source_arms.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_source_skeleton = skeleton
	_source_animation = animation
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation.play(&"idle")
	animation.seek(0.0, true)
	animation.pause()
	_assert(skeleton.get_bone_count() == 60, "independent source fixture retains sixty native bones")
	for bone in skeleton.get_bone_count():
		_rest.append(skeleton.get_bone_rest(bone))
	for side: Array in [["R_arm_026", "R_elbow_027", "R_wrist_028"], ["L_arm_02", "L_elbow_03", "L_wrist_04"]]:
		for index in 2:
			_lengths.append(skeleton.get_bone_global_pose(skeleton.find_bone(side[index])).origin.distance_to(skeleton.get_bone_global_pose(skeleton.find_bone(side[index + 1])).origin))
	for entry: Dictionary in _topology:
		var row: Array[Transform3D] = []
		var source_mesh := _source_arms.find_child(str(entry.mesh.name), true, false) as MeshInstance3D
		_assert(source_mesh != null and source_mesh.skin != null, "independent original source resolves the matching native skin")
		for bind in source_mesh.skin.get_bind_count():
			row.append(source_mesh.skin.get_bind_pose(bind))
		_binds.append(row)
	for name: String in LEFT_FINGERS:
		_hold_fingers[name] = _weapon._arms_skeleton.get_bone_pose_rotation(_weapon._arms_skeleton.find_bone(name))


func _check_rig(label: String) -> void:
	var skeleton: Skeleton3D = _weapon._arms_skeleton
	var valid := skeleton.get_bone_count() == 60
	for bone in skeleton.get_bone_count():
		valid = valid and skeleton.get_bone_rest(bone).is_equal_approx(_rest[bone]) and skeleton.get_bone_pose_scale(bone).is_equal_approx(Vector3.ONE) and skeleton.get_bone_global_pose(bone).is_finite()
	_assert(valid, label + " preserves all sixty source rests, unit scales and finite native poses")
	var lengths_valid := true
	var offset := 0
	for side: Array in [["R_arm_026", "R_elbow_027", "R_wrist_028"], ["L_arm_02", "L_elbow_03", "L_wrist_04"]]:
		for index in 2:
			var length := skeleton.get_bone_global_pose(skeleton.find_bone(side[index])).origin.distance_to(skeleton.get_bone_global_pose(skeleton.find_bone(side[index + 1])).origin)
			lengths_valid = lengths_valid and absf(length - _lengths[offset]) < 0.0001
			offset += 1
	_assert(lengths_valid, label + " retains both original upper-arm and forearm lengths within 0.1mm")
	var binds_valid := true
	for index in _topology.size():
		var skin: Skin = _topology[index].skin
		binds_valid = binds_valid and skin.get_bind_count() == _binds[index].size()
		for bind in skin.get_bind_count():
			binds_valid = binds_valid and skin.get_bind_pose(bind).is_equal_approx(_binds[index][bind])
	_assert(binds_valid, label + " retains registered source skin binds")
	_assert(is_equal_approx(_player._camera.near, 0.05) and is_equal_approx(_player._viewmodel_depth_scale, 1.0), label + " keeps the authored near plane and real-world viewmodel scale")


func _advance_visuals(delta: float) -> void:
	# Drive the actual production interpolation/clock at exact sampling boundaries.
	_player._process(delta)
	_weapon._process(delta)


func _check_support_fingers(label: String) -> void:
	var expected := _hold_fingers
	var reloading: bool = _weapon._is_reloading
	if reloading:
		# The isolated original GLB is the oracle, before production pose overrides.
		var clip := _source_animation.get_animation(&"reload")
		_source_animation.play(&"reload")
		_source_animation.seek(clampf(_weapon._reload_progress, 0.0, 1.0) * clip.length, true)
		_source_animation.pause()
		expected = {}
		for name: String in LEFT_FINGERS:
			expected[name] = _source_skeleton.get_bone_pose_rotation(_source_skeleton.find_bone(name))
	var skeleton: Skeleton3D = _weapon._arms_skeleton
	var valid := expected.size() == LEFT_FINGERS.size()
	for name: String in LEFT_FINGERS:
		var actual := skeleton.get_bone_pose_rotation(skeleton.find_bone(name))
		valid = valid and actual.is_finite() and absf(actual.dot(expected[name] as Quaternion)) >= 0.999999
	_assert(valid, label + (" preserves all fifteen independent source reload finger curves" if reloading else " restores all fifteen hold finger rotations without accumulated pose deltas"))


func _supply_total() -> int:
	return _state.spas12_mag + int(_state.weapon_chambered[&"spas12"]) + _state.spas12_reserve


func _check_actions() -> void:
	var player_process: bool = _player.is_processing()
	var weapon_process: bool = _weapon.is_processing()
	var weapon_physics: bool = _weapon.is_physics_processing()
	var mag: int = _state.spas12_mag
	var reserve: int = _state.spas12_reserve
	var chambered: bool = _state.weapon_chambered[&"spas12"]
	_player.set_process(false)
	_weapon.set_process(false)
	_weapon.set_physics_process(false)
	for repeat in 8:
		_weapon._native_arms.pose_hold(_weapon._aim_weight)
	_check_support_fingers("eight repeated direct pose_hold calls")
	_player._set_aiming(true)
	for step in 4:
		_advance_visuals(root.get_node("GameConfig").ADS_LERP_TIME * 0.25)
		_assert(absf(_weapon._aim_weight - float(step + 1) * 0.25) < 0.0001, "ADS transition advances the production interpolation by one quarter")
		await _sample("ads" if step == 3 else "ads_" + str(step + 1))
	var ads_budget := _supply_total()
	_assert(_weapon._fire(), "full ADS fires an actual chambered shell before pumping")
	_assert(_supply_total() == ads_budget - 1 and not _state.weapon_chambered[&"spas12"], "full ADS shot consumes exactly one shell and empties the chamber")
	for step in 4:
		_advance_visuals(root.get_node("GameConfig").SPAS12_PUMP_TIME * 0.25)
		for repeat in 3:
			_advance_visuals(0.0)
		await _sample("ads_pump_" + str(step + 1))
		_assert(_supply_total() == ads_budget - 1, "ADS pump phase transfers existing supply without creating a shell")
		_assert(bool(_state.weapon_chambered[&"spas12"]) == (step == 3), "ADS chamber remains empty until the actual fourth pump phase completes")
	_assert(_weapon._pump_left <= 0.0 and _state.is_aiming and is_equal_approx(_weapon._aim_weight, 1.0), "complete ADS pump preserves full aiming weight and chambers exactly one existing tube shell")
	_player._set_aiming(false)
	for step in 4:
		_advance_visuals(root.get_node("GameConfig").ADS_LERP_TIME * 0.25)
		await _sample("hip_return" if step == 3 else "hip_transition_" + str(step + 1))
	var budget := _supply_total()
	_assert(_weapon._fire(), "real SPAS controller fires a chambered shell before the visual pump")
	_assert(_supply_total() == budget - 1 and not _state.weapon_chambered[&"spas12"], "actual shot consumes exactly one shell and waits for pump chambering")
	for step in 4:
		_advance_visuals(root.get_node("GameConfig").SPAS12_PUMP_TIME * 0.25)
		for repeat in 3:
			_advance_visuals(0.0)
		await _sample("pump_" + str(step + 1))
		_assert(_supply_total() == budget - 1, "pump phase transfers existing supply without creating a shell")
	_assert(_state.weapon_chambered[&"spas12"] and _weapon._pump_left <= 0.0, "the complete production pump chambers one tube shell")
	_state.spas12_mag = 3
	_state.weapon_chambered[&"spas12"] = true
	_state.spas12_reserve = 1
	budget = _supply_total()
	_weapon._start_reload()
	_assert(_weapon._is_reloading, "production reload starts a real one-shell low-reserve sequence")
	var previous := 0.0
	for phase: float in [0.18, 0.50, 0.77, 0.84]:
		_advance_visuals(_weapon.weapon_data.reload_time * (phase - previous))
		previous = phase
		_assert(_state.spas12_mag == 3 and _state.spas12_reserve == 1 and _supply_total() == budget, "real retrieve/carry/insert visuals precede the exact shell interval settlement")
		await _sample("shell_" + str(roundi(phase * 100.0)))
	_advance_visuals(_weapon.weapon_data.reload_time * 0.17)
	_assert(not _weapon._is_reloading and _state.spas12_mag == 4 and _state.spas12_reserve == 0 and _supply_total() == budget, "one full real shell interval settles once and stops on depleted reserve")
	_advance_visuals(0.0)
	await _sample("reload_complete")
	_state.spas12_mag = 2
	_state.spas12_reserve = 3
	budget = _supply_total()
	_weapon._start_reload()
	_advance_visuals(_weapon.weapon_data.reload_time * 0.5)
	_player._switch_weapon(&"rifle")
	_assert(not _weapon._is_reloading and not _weapon._shell.visible and _weapon._pump_left == 0.0, "real switch cancels shell handling and hides its visible supply")
	_advance_visuals(_weapon.weapon_data.reload_time * 2.0)
	_assert(_supply_total() == budget, "inactive cancelled reload cannot settle ammunition later")
	_player._switch_weapon(&"spas12")
	_advance_visuals(0.0)
	await _sample("switch_back")
	_state.spas12_mag = mag
	_state.spas12_reserve = reserve
	_state.weapon_chambered[&"spas12"] = chambered
	_player.set_process(player_process)
	_weapon.set_process(weapon_process)
	_weapon.set_physics_process(weapon_physics)
	_assert(_player.is_processing() == player_process and _weapon.is_processing() == weapon_process and _weapon.is_physics_processing() == weapon_physics and _state.spas12_mag == mag and _state.spas12_reserve == reserve and _state.weapon_chambered[&"spas12"] == chambered, "action fixture restores exact process flags and physical supply")


func _capture_materials() -> void:
	for node in _weapon.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var surfaces: Array = []
		for surface in mesh.get_surface_override_material_count():
			surfaces.append(mesh.get_surface_override_material(surface))
		_materials[mesh] = {"override": mesh.material_override, "surfaces": surfaces, "mesh": mesh.mesh}


func _check_materials() -> void:
	var unchanged := true
	for mesh: MeshInstance3D in _materials:
		var prior: Dictionary = _materials[mesh]
		unchanged = unchanged and mesh.material_override == prior.override and mesh.mesh == prior.mesh
		for surface in prior.surfaces.size():
			unchanged = unchanged and mesh.get_surface_override_material(surface) == prior.surfaces[surface]
	_assert(unchanged, "all captures retain original source meshes and production materials")


func _build_topology() -> void:
	for node in _weapon._arms_node.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or mesh.get_skin_reference() == null:
			continue
		var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		var skin: Skin = mesh.get_skin_reference().get_skin()
		_assert(skeleton != null and skin != null, "arm mesh resolves registered skeleton and skin: " + str(mesh.name))
		if skeleton == null or skin == null:
			continue
		var welds: Dictionary = {}
		var representatives: Array[Dictionary] = []
		var edges: Dictionary = {}
		var surface_ids: Array = []
		var binds_valid := true
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			_assert(not vertices.is_empty() and not indices.is_empty() and bones.size() == weights.size() and bones.size() % vertices.size() == 0, "source topology has indexed skin arrays: " + str(mesh.name))
			if vertices.is_empty() or indices.is_empty():
				continue
			var width: int = bones.size() / vertices.size()
			var ids := PackedInt32Array()
			for vertex in vertices.size():
				var point := vertices[vertex]
				# Source POSITION welding joins UV/material seams before boundary edge counting.
				var key := "%d,%d,%d" % [roundi(point.x * 100000.0), roundi(point.y * 100000.0), roundi(point.z * 100000.0)]
				if not welds.has(key):
					var classes := [0.0, 0.0]
					for influence in width:
						var offset := vertex * width + influence
						var bind := bones[offset]
						var bone := skeleton.find_bone(skin.get_bind_name(bind)) if skin.get_bind_name(bind) != &"" else skin.get_bind_bone(bind)
						if weights[offset] > 0.0:
							binds_valid = binds_valid and bone >= 0
							if bone >= 0:
								for hand in 2:
									if skeleton.get_bone_name(bone) == UPPER_NAMES[hand]:
										classes[hand] += weights[offset]
					welds[key] = representatives.size()
					representatives.append({"surface": surface, "vertex": vertex, "source": point, "upper_weights": classes})
				ids.append(int(welds[key]))
			surface_ids.append(ids)
			for triangle in range(0, indices.size(), 3):
				for edge in 3:
					var a: int = ids[indices[triangle + edge]]
					var b: int = ids[indices[triangle + (edge + 1) % 3]]
					if a == b:
						continue
					var key := "%d,%d" % [mini(a, b), maxi(a, b)]
					if edges.has(key):
						edges[key].count += 1
					else:
						edges[key] = {"a": a, "b": b, "count": 1}
		_assert(binds_valid, "all source weighted binds resolve actual native bones: " + str(mesh.name))
		var rings: Array = []
		for hand in 2:
			var adjacency: Dictionary = {}
			var edge_count := 0
			for key: String in edges:
				var edge: Dictionary = edges[key]
				if edge.count != 1 or float(representatives[edge.a].upper_weights[hand]) < 0.999 or float(representatives[edge.b].upper_weights[hand]) < 0.999:
					continue
				edge_count += 1
				for pair: Array in [[edge.a, edge.b], [edge.b, edge.a]]:
					if not adjacency.has(pair[0]):
						adjacency[pair[0]] = []
					adjacency[pair[0]].append(pair[1])
			var ordered: Array[int] = []
			var degree_two := true
			for id: int in adjacency:
				degree_two = degree_two and adjacency[id].size() == 2
			if not adjacency.is_empty() and degree_two:
				var start: int = adjacency.keys()[0]
				var previous := -1
				var cursor := start
				for step in adjacency.size():
					ordered.append(cursor)
					var neighbours: Array = adjacency[cursor]
					var next: int = neighbours[0] if neighbours[0] != previous else neighbours[1]
					previous = cursor
					cursor = next
				degree_two = degree_two and cursor == start
			rings.append({"hand": hand, "ids": ordered, "edges": edge_count, "closed": degree_two})
			if edge_count > 0:
				_assert(edge_count == 24 and ordered.size() == 24 and degree_two, "%s %s shoulder is the source welded 24-edge open ring" % [mesh.name, UPPER_NAMES[hand]])
		_topology.append({"mesh": mesh, "skeleton": skeleton, "skin": skin, "representatives": representatives, "rings": rings})
	var counts := [0, 0]
	for entry: Dictionary in _topology:
		for ring: Dictionary in entry.rings:
			counts[ring.hand] += ring.edges
	_assert(counts == [24, 24], "topology identifies exactly one native 24-edge shoulder ring on each arm")


func _sample(label: String) -> void:
	await RenderingServer.frame_post_draw
	_check_daylight()
	_check_materials()
	var camera: Camera3D = _player._camera
	var gun: Node3D = _weapon._weapon_node
	if not _geometry_only and label in ["hip", "ads"]:
		var baseline: Transform3D = HIP_GUN_CAMERA if label == "hip" else ADS_GUN_CAMERA
		var actual := camera.global_transform.affine_inverse() * gun.global_transform
		_assert(actual.origin.distance_to(baseline.origin) < 0.0001 and actual.basis.is_equal_approx(baseline.basis), label + " retains the independently measured original gun framing within 0.1mm")
		_assert(is_equal_approx(camera.fov, 75.0 if label == "hip" else 65.0), label + " retains the original measured camera FOV")
	var shot := root.get_texture().get_image()
	_assert(shot != null and not shot.is_empty() and shot.save_png(OUTPUT + "/" + label + ".png") == OK, label + " saves unmodified production daylight pixels")
	var meshes: Dictionary = {}
	for name: String in GUN_MESHES:
		var mesh := gun.find_child(name, true, false) as MeshInstance3D
		_assert(mesh != null and mesh.mesh != null, label + " resolves actual gun mesh " + name)
		if mesh == null or mesh.mesh == null:
			continue
		var surfaces: Array = []
		var local := gun.global_transform.affine_inverse() * mesh.global_transform
		var minimum := Vector3(INF, INF, INF)
		var maximum := Vector3(-INF, -INF, -INF)
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var points: Array = []
			var directions: Array = []
			for vertex in vertices:
				var point := local * vertex
				minimum = minimum.min(point)
				maximum = maximum.max(point)
				points.append(_v3(point))
			for normal in normals:
				directions.append(_v3(local.basis.inverse().transposed() * normal))
			surfaces.append({"vertices": points, "normals": directions, "indices": Array(arrays[Mesh.ARRAY_INDEX])})
		meshes[name] = {"path": str(gun.get_path_to(mesh)), "transform": _transform(local), "bounds": {"min": _v3(minimum), "max": _v3(maximum)}, "surfaces": surfaces}
	_write_json(OUTPUT + "/" + label + "_gun.json", meshes)
	if not _geometry_only and label == "ads":
		for name: String in SIGHT_TIPS:
			var mesh := gun.find_child(name, true, false) as MeshInstance3D
			var points: Array = meshes[name].surfaces[0].vertices
			var maximum := -INF
			for point: Array in points:
				maximum = maxf(maximum, float(point[1]))
			var tip := Vector3.ZERO
			var count := 0
			for point: Array in points:
				if float(point[1]) >= maximum - 0.002:
					tip += _vector(point)
					count += 1
			tip /= maxf(count, 1.0)
			var old_point: Vector3 = ADS_GUN_CAMERA * (SIGHT_TIPS[name] as Vector3)
			var focal := 1080.0 / (2.0 * tan(deg_to_rad(65.0) * 0.5))
			var expected := Vector2(960.0 + old_point.x / -old_point.z * focal, 540.0 - old_point.y / -old_point.z * focal)
			var actual := camera.unproject_position(gun.to_global(tip))
			_assert(mesh.is_visible_in_tree() and count >= 6 and tip.distance_to(SIGHT_TIPS[name]) < 0.00001 and actual.distance_to(expected) < 0.01, name + " visible mechanical sight geometry retains its original measured projection within 0.01px")
	var arms: Array = []
	for entry: Dictionary in _topology:
		var mesh: MeshInstance3D = entry.mesh
		var posed := mesh.bake_mesh_from_current_skeleton_pose()
		_assert(posed != null and posed.get_surface_count() == mesh.mesh.get_surface_count(), label + " native renderer bakes matching skin surfaces")
		if posed == null:
			continue
		var baked_arrays: Array = []
		var palms: Array = [{"points": [], "normals": []}, {"points": [], "normals": []}]
		var tips: Dictionary = {}
		var left_hand_points: Array = []
		var left_hand_triangles: Array = []
		for name: String in LEFT_TIPS:
			tips[name] = []
		for surface in posed.get_surface_count():
			var source := mesh.mesh.surface_get_arrays(surface)
			var baked := posed.surface_get_arrays(surface)
			baked_arrays.append(baked)
			var vertices: PackedVector3Array = baked[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = baked[Mesh.ARRAY_NORMAL]
			var source_vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = source[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = source[Mesh.ARRAY_WEIGHTS]
			_assert(vertices.size() == source_vertices.size(), label + " bake retains native source vertex correspondence")
			if not _geometry_only and label == "ads" and mesh.is_visible_in_tree():
				var indices: PackedInt32Array = baked[Mesh.ARRAY_INDEX]
				var hits := 0
				var ray_start := camera.global_position
				var ray_end := camera.to_global(Vector3(0, 0, -2.0))
				for offset in range(0, indices.size(), 3):
					if Geometry3D.segment_intersects_triangle(ray_start, ray_end, mesh.to_global(vertices[indices[offset]]), mesh.to_global(vertices[indices[offset + 1]]), mesh.to_global(vertices[indices[offset + 2]])) != null:
						hits += 1
				_assert(hits == 0, "ADS center sight ray passes all actually visible renderer-baked native arm triangles")
			var width: int = bones.size() / vertices.size()
			var local := gun.global_transform.affine_inverse() * mesh.global_transform
			var hand_vertices := PackedByteArray()
			hand_vertices.resize(vertices.size())
			for vertex in vertices.size():
				var selected := [0.0, 0.0]
				var left_hand_weight := 0.0
				var tip_weights: Dictionary = {}
				for influence in width:
					var offset := vertex * width + influence
					if weights[offset] <= 0.0:
						continue
					var bind := bones[offset]
					var skin: Skin = entry.skin
					var skeleton: Skeleton3D = entry.skeleton
					var bone := skeleton.find_bone(skin.get_bind_name(bind)) if skin.get_bind_name(bind) != &"" else skin.get_bind_bone(bind)
					var bone_name: String = str(skeleton.get_bone_name(bone))
					if bone_name.begins_with("L_") and bone_name not in ["L_arm_02", "L_elbow_03"]:
						left_hand_weight += weights[offset]
					if bone_name in LEFT_TIPS:
						tip_weights[bone_name] = float(tip_weights.get(bone_name, 0.0)) + weights[offset]
					for hand in 2:
						if skeleton.get_bone_name(bone) in PALM_NAMES[hand]:
							selected[hand] += weights[offset]
				for hand in 2:
					if selected[hand] > 0.65:
						palms[hand].points.append(_v3(local * vertices[vertex]))
						palms[hand].normals.append(_v3((local.basis.inverse().transposed() * normals[vertex]).normalized()))
				for name: String in tip_weights:
					if float(tip_weights[name]) > 0.65:
						tips[name].append(_v3(local * vertices[vertex]))
				if left_hand_weight > 0.65:
					left_hand_points.append(_v3(local * vertices[vertex]))
					hand_vertices[vertex] = 1
			var indices: PackedInt32Array = baked[Mesh.ARRAY_INDEX]
			for offset in range(0, indices.size(), 3):
				if hand_vertices[indices[offset]] and hand_vertices[indices[offset + 1]] and hand_vertices[indices[offset + 2]]:
					for corner in 3:
						left_hand_triangles.append(_v3(local * vertices[indices[offset + corner]]))
		var rings: Array = []
		for hand in 2:
			var center := Vector3.ZERO
			for point: Array in palms[hand].points:
				center += Vector3(point[0], point[1], point[2])
			if not palms[hand].points.is_empty():
				center /= palms[hand].points.size()
			palms[hand].center = _v3(center)
		for ring: Dictionary in entry.rings:
			if ring.ids.is_empty():
				continue
			var world_points := PackedVector3Array()
			var source_points: Array = []
			var world_export: Array = []
			var gun_points: Array = []
			var camera_points: Array = []
			var center := Vector3.ZERO
			for id: int in ring.ids:
				var representative: Dictionary = entry.representatives[id]
				var vertices: PackedVector3Array = baked_arrays[representative.surface][Mesh.ARRAY_VERTEX]
				var world := mesh.global_transform * vertices[representative.vertex]
				world_points.append(world)
				world_export.append(_v3(world))
				gun_points.append(_v3(gun.to_local(world)))
				center += world
				source_points.append(_v3(representative.source))
				camera_points.append(_v3(camera.to_local(world)))
			center /= world_points.size()
			var clipped: Array = []
			var visible_area := 0.0
			for index in world_points.size():
				var polygon := _clip_polygon(PackedVector3Array([center, world_points[index], world_points[(index + 1) % world_points.size()]]), camera.get_frustum())
				var projected := PackedVector2Array()
				for world in polygon:
					projected.append(camera.unproject_position(world))
				var area := _polygon_area(projected)
				visible_area += area
				if polygon.size() >= 3:
					var triangle: Array = []
					for point in projected:
						triangle.append([point.x, point.y])
					clipped.append(triangle)
			var record := {"hand": UPPER_NAMES[ring.hand], "edges": ring.edges, "source": source_points, "world": world_export, "gun_local": gun_points, "camera": camera_points, "center_camera": _v3(camera.to_local(center)), "clipped_pixels": clipped, "visible_area_pixels": visible_area}
			rings.append(record)
			print("SPAS_SHOULDER ", label, " ", UPPER_NAMES[ring.hand], " edges=", ring.edges, " area_px=", visible_area, " center_camera=", camera.to_local(center))
			if not _geometry_only:
				_assert(visible_area == 0.0, "%s %s actual source shoulder opening stays completely outside all six camera planes" % [label, UPPER_NAMES[ring.hand]])
		arms.append({"mesh": str(mesh.name), "palms_gun_local": palms, "left_tip_points": tips, "left_hand_points": left_hand_points, "left_hand_triangles": left_hand_triangles, "shoulder_rings": rings})
	_write_json(OUTPUT + "/" + label + "_arms.json", arms)
	if not _geometry_only:
		_check_contact(label, meshes, arms)
		_check_rig(label)
		_check_support_fingers(label)
	var skeleton: Skeleton3D = _weapon._arms_skeleton
	var bone_frames: Dictionary = {}
	for bone in skeleton.get_bone_count():
		bone_frames[skeleton.get_bone_name(bone)] = {"rest": _transform(skeleton.get_bone_rest(bone)), "pose_gun": _transform(gun.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(bone)), "pose_scale": _v3(skeleton.get_bone_pose_scale(bone))}
	var wrist_bases: Array = []
	for basis: Basis in _weapon._native_arms._wrist_basis:
		wrist_bases.append([_v3(basis.x), _v3(basis.y), _v3(basis.z)])
	var sample := {"label": label, "fov": camera.fov, "near": camera.near, "far": camera.far, "camera": _transform(camera.global_transform), "gun_camera": _transform(camera.global_transform.affine_inverse() * gun.global_transform), "mount": _transform(_player._weapon_mount.transform), "arm_transform": _transform(_weapon._arms_node.transform), "aim_weight": float(_weapon._aim_weight), "depth_scale": float(_player._viewmodel_depth_scale), "day": not _controller.is_night(), "night_vision": bool(_state.night_vision), "arms": arms, "bones": bone_frames, "native_wrist_basis": wrist_bases}
	_samples.append(sample)
	print("SPAS_DAYLIGHT_SAMPLE ", label, " fov=", camera.fov, " near=", camera.near, " depth=", _player._viewmodel_depth_scale, " gun=", gun.transform)


func _check_contact(label: String, meshes: Dictionary, arms: Array) -> void:
	var right_faces: Array[Vector3] = []
	var left_faces: Array[Vector3] = []
	var pump_faces: Array[Vector3] = []
	var cache_roi := _contact_roi.is_empty()
	for name: String in ["Object_37", "Object_21"]:
		if not meshes.has(name):
			_assert(false, label + " contact resolves the real indexed source body")
			continue
		if cache_roi:
			_contact_roi[name] = []
		for surface_index in meshes[name].surfaces.size():
			var surface: Dictionary = meshes[name].surfaces[surface_index]
			var points: Array = surface.vertices
			var indices: Array = surface.indices
			for offset in range(0, indices.size(), 3):
				var a := _vector(points[indices[offset]])
				var b := _vector(points[indices[offset + 1]])
				var c := _vector(points[indices[offset + 2]])
				if name == "Object_21" and (b - a).cross(c - a).length_squared() > 1.0e-16:
					pump_faces.append_array([a, b, c])
				var selected := false
				if not cache_roi:
					selected = [surface_index, offset] in _contact_roi[name]
				elif name == "Object_37":
					# Native source grip upper section; all corners exclude the lower handle and receiver.
					selected = true
					for point: Vector3 in [a, b, c]:
						selected = selected and point.y >= -0.095 and point.y <= -0.040 and point.z >= 0.090 and point.z <= 0.190
				else:
					var center := (a + b + c) / 3.0
					var normal := (b - a).cross(c - a).normalized()
					# Real lower fore-end faces; side contact alone permits a reversed claw grip.
					if center.y < -0.022 and center.z >= -0.470 and center.z <= -0.250 and absf(normal.dot(Vector3.UP)) > 0.95:
						selected = true
				if selected:
					if cache_roi:
						_contact_roi[name].append([surface_index, offset])
					if name == "Object_37":
						right_faces.append_array([a, b, c])
					else:
						left_faces.append_array([a, b, c])
	_assert(right_faces.size() == 48, label + " upper grip ROI contains the sixteen independently identified native triangles")
	_assert(left_faces.size() >= 6, label + " fore-end ROI resolves actual lower support triangles")
	if cache_roi:
		_assert(_inside_surface(Vector3(0.05, -0.024, -0.34), pump_faces), "solid pump underside positive control is inside actual material")
		_assert(not _inside_surface(Vector3(0.05, -0.04, -0.34), pump_faces), "below-pump negative control is outside actual material")
		_assert(not _inside_surface(Vector3(0.05, -0.015, -0.34), pump_faces), "pump inner cavity negative control is outside actual material")
		_assert(_edge_penetration_depth(Vector3(0.05, -0.04, -0.34), Vector3(0.05, -0.015, -0.34), pump_faces) > 0.001, "edge crossing thin pump wall is detected even with both endpoints outside")
	for entry: Dictionary in arms:
		var palms: Array = entry.palms_gun_local
		if palms[0].points.size() > 20:
			var right := _vector(palms[0].center)
			var distance := _surface_distance(right, right_faces)
			_assert(distance <= 0.015, label + " actual renderer-baked right palm contacts upper native grip within 15mm (%.3fmm)" % (distance * 1000.0))
			print("SPAS_GRIP ", label, " right=", right, " upper_distance=", distance)
		else:
			_assert(false, label + " right palm has enough actual weighted renderer vertices")
		if palms[1].points.size() > 20:
			var left := _vector(palms[1].center)
			if _weapon._is_reloading:
				if _weapon._shell.visible:
					var shell_faces: Array[Vector3] = []
					var shell: MeshInstance3D = _weapon._shell
					var local: Transform3D = _weapon._weapon_node.global_transform.affine_inverse() * shell.global_transform
					for surface in shell.mesh.get_surface_count():
						var arrays := shell.mesh.surface_get_arrays(surface)
						var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
						var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
						for index in indices:
							shell_faces.append(local * vertices[index])
					var shell_distance := _surface_distance(left, shell_faces)
					_assert(shell_faces.size() > 6 and shell_distance < 0.015, label + " actual palm contacts the visible loading shell surface within 15mm")
					print("SPAS_SHELL_CONTACT ", label, " distance=", shell_distance)
				continue
			var distance := _surface_distance(left, left_faces)
			var normal := _palm_plane_normal(palms[1].points)
			# These source weights select the wrist/palm volume, whose centroid is
			# inside the glove. Actual upward-facing surface contact is checked below.
			var nearest := INF
			var below := false
			for offset in range(0, left_faces.size(), 3):
				var a: Vector3 = left_faces[offset]
				var b: Vector3 = left_faces[offset + 1]
				var c: Vector3 = left_faces[offset + 2]
				var candidate := _point_triangle_distance(left, a, b, c)
				if candidate < nearest:
					nearest = candidate
					var up := (b - a).cross(c - a).normalized()
					if up.y < 0.0:
						up = -up
					below = up.dot(left - a) <= -0.001
			_assert(below, label + " palm center supports the actual pump surface from below")
			_assert(absf(normal.dot(Vector3.UP)) >= 0.90, label + " actual palm plane faces the physical fore-end underside (alignment=%.6f)" % absf(normal.dot(Vector3.UP)))
			var skeleton: Skeleton3D = _weapon._arms_skeleton
			var wrist := skeleton.get_bone_global_pose(skeleton.find_bone("L_wrist_04")).origin
			var elbow := skeleton.get_bone_global_pose(skeleton.find_bone("L_elbow_03")).origin
			var finger := skeleton.get_bone_global_pose(skeleton.find_bone("L_middle1_013")).origin
			var hand_axis := (finger - wrist).normalized()
			var fore_axis := (wrist - elbow).normalized()
			var distal := skeleton.get_bone_global_pose(skeleton.find_bone("L_middle3_015")).origin
			var bend := distal - finger - hand_axis * (distal - finger).dot(hand_axis)
			var bend_gun: Vector3 = _weapon._weapon_node.global_basis.inverse() * skeleton.global_basis * bend
			var cup_normal := normal if normal.dot(bend_gun) >= 0.0 else -normal
			_assert(cup_normal.dot(Vector3.UP) >= 0.90, label + " actual cupped palm interior faces upward toward the pump (alignment=%.6f)" % cup_normal.dot(Vector3.UP))
			var wrist_angle := rad_to_deg(acos(clampf(hand_axis.dot(fore_axis), -1.0, 1.0)))
			_assert(wrist_angle <= 30.0, label + " actual forearm-to-hand flexion remains natural within 30 degrees (%.3fdeg)" % wrist_angle)
			var palm_surface_distance := INF
			for index in palms[1].points.size():
				if _vector(palms[1].normals[index]).dot(Vector3.UP) >= 0.90:
					palm_surface_distance = minf(palm_surface_distance, _surface_distance(_vector(palms[1].points[index]), left_faces))
			_assert(palm_surface_distance <= 0.003, label + " actual upward-facing glove palm surface meets the pump underside within 3mm (%.3fmm)" % (palm_surface_distance * 1000.0))
			var close_fingers := 0
			for name: String in LEFT_TIPS:
				var tip_distance := INF
				var points: Array = entry.left_tip_points[name]
				for point: Array in points:
					tip_distance = minf(tip_distance, _surface_distance(_vector(point), pump_faces))
				_assert(points.size() >= 20 and tip_distance <= 0.012, label + " " + name + " actual distal glove stays wrapped within 12mm of the pump (%.3fmm)" % (tip_distance * 1000.0))
				if tip_distance <= 0.003:
					close_fingers += 1
			_assert(close_fingers >= 3, label + " at least three actual distal glove surfaces contact the pump within 3mm")
			var deep_points := 0
			var maximum_depth := 0.0
			for point: Array in entry.left_hand_points:
				var position := _vector(point)
				if _inside_surface(position, pump_faces):
					var depth := _surface_distance(position, pump_faces)
					maximum_depth = maxf(maximum_depth, depth)
					if depth > 0.001:
						deep_points += 1
			_assert(entry.left_hand_points.size() > 500 and deep_points == 0, label + " whole renderer-baked support hand has no pump penetration deeper than 1mm (%d points, %.3fmm)" % [deep_points, maximum_depth * 1000.0])
			var hand_faces: Array = entry.left_hand_triangles
			var edge_depth := 0.0
			var checked_edges: Dictionary = {}
			var pump_min := _vector(meshes.Object_21.bounds.min)
			var pump_max := _vector(meshes.Object_21.bounds.max)
			for offset in range(0, hand_faces.size(), 3):
				for edge in 3:
					var begin := _vector(hand_faces[offset + edge])
					var end := _vector(hand_faces[offset + (edge + 1) % 3])
					if begin.max(end).x < pump_min.x or begin.min(end).x > pump_max.x or begin.max(end).y < pump_min.y or begin.min(end).y > pump_max.y or begin.max(end).z < pump_min.z or begin.min(end).z > pump_max.z:
						continue
					var key := str(begin) + ":" + str(end) if str(begin) < str(end) else str(end) + ":" + str(begin)
					if checked_edges.has(key):
						continue
					checked_edges[key] = true
					edge_depth = maxf(edge_depth, _edge_penetration_depth(begin, end, pump_faces))
			_assert(hand_faces.size() > 1000 and edge_depth <= 0.001, label + " actual glove triangle edges do not cross pump material deeper than 1mm (%.3fmm)" % (edge_depth * 1000.0))
			print("SPAS_GRIP ", label, " left=", left, " palm_centroid_distance=", distance, " upward_surface_distance=", palm_surface_distance, " palm_thin_normal=", normal, " wrist_angle_deg=", wrist_angle)
		else:
			_assert(false, label + " left palm has enough actual weighted renderer vertices")


func _palm_plane_normal(points: Array) -> Vector3:
	var center := Vector3.ZERO
	for point: Array in points:
		center += _vector(point)
	center /= points.size()
	var xx := 0.0
	var yy := 0.0
	var zz := 0.0
	var xy := 0.0
	var xz := 0.0
	var yz := 0.0
	for point: Array in points:
		var offset := _vector(point) - center
		xx += offset.x * offset.x
		yy += offset.y * offset.y
		zz += offset.z * offset.z
		xy += offset.x * offset.y
		xz += offset.x * offset.z
		yz += offset.y * offset.z
	var scale := maxf(xx, maxf(yy, zz))
	_assert(scale > 0.0, "baked palm covariance has real spatial extent")
	if scale <= 0.0:
		return Vector3.ZERO
	var covariance := Basis(Vector3(xx, xy, xz) / scale, Vector3(xy, yy, yz) / scale, Vector3(xz, yz, zz) / scale)
	_assert(covariance.determinant() != 0.0, "baked palm covariance is nondegenerate")
	if covariance.determinant() == 0.0:
		return Vector3.ZERO
	# Independent inverse iteration finds the actual thin palm plane from the rendered skin.
	var inverse := covariance.inverse()
	var normal := Vector3.ONE.normalized()
	for step in 32:
		normal = (inverse * normal).normalized()
	return normal


func _surface_distance(point: Vector3, faces: Array[Vector3]) -> float:
	var distance := INF
	for offset in range(0, faces.size(), 3):
		distance = minf(distance, _point_triangle_distance(point, faces[offset], faces[offset + 1], faces[offset + 2]))
	return distance


func _inside_surface(point: Vector3, faces: Array[Vector3]) -> bool:
	# Source sleeve has eight boundary edges. Three-axis voting avoids a single
	# ray through an opening declaring the empty cavity to be solid material.
	var inside_votes := 0
	for direction: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		if _ray_inside_surface(point, point + direction * 2.0, faces):
			inside_votes += 1
	return inside_votes >= 2


func _edge_penetration_depth(begin: Vector3, end: Vector3, faces: Array[Vector3]) -> float:
	var length := begin.distance_to(end)
	if length < 0.000001:
		return 0.0
	var cuts: Array[float] = [0.0, 1.0]
	for offset in range(0, faces.size(), 3):
		var hit = Geometry3D.segment_intersects_triangle(begin, end, faces[offset], faces[offset + 1], faces[offset + 2])
		if hit != null:
			cuts.append(begin.distance_to(hit as Vector3) / length)
	if cuts.size() == 2:
		return 0.0
	cuts.sort()
	var depth := 0.0
	for index in cuts.size() - 1:
		if cuts[index + 1] - cuts[index] < 0.000001:
			continue
		var midpoint := begin.lerp(end, (cuts[index] + cuts[index + 1]) * 0.5)
		if _inside_surface(midpoint, faces):
			depth = maxf(depth, _surface_distance(midpoint, faces))
	return depth


func _ray_inside_surface(point: Vector3, end: Vector3, faces: Array[Vector3]) -> bool:
	# Shared triangle hits count once, including a ray crossing a face diagonal.
	var distances: Array[float] = []
	for offset in range(0, faces.size(), 3):
		var hit = Geometry3D.segment_intersects_triangle(point, end, faces[offset], faces[offset + 1], faces[offset + 2])
		if hit != null:
			distances.append(point.distance_to(hit as Vector3))
	distances.sort()
	var intersections := 0
	var previous := -INF
	for distance: float in distances:
		if distance > 0.000001 and distance - previous > 0.000001:
			intersections += 1
			previous = distance
	return intersections % 2 == 1


func _point_triangle_distance(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var normal := (b - a).cross(c - a)
	var area := normal.length_squared()
	if area > 1.0e-16:
		var projected := point - normal * ((point - a).dot(normal) / area)
		if normal.dot((b - a).cross(projected - a)) >= 0.0 and normal.dot((c - b).cross(projected - b)) >= 0.0 and normal.dot((a - c).cross(projected - c)) >= 0.0:
			return point.distance_to(projected)
	var distance := INF
	for edge: Array in [[a, b], [b, c], [c, a]]:
		var begin: Vector3 = edge[0]
		var segment: Vector3 = edge[1] - begin
		var length := segment.length_squared()
		var fraction := clampf((point - begin).dot(segment) / length, 0.0, 1.0) if length > 1.0e-16 else 0.0
		distance = minf(distance, point.distance_to(begin + segment * fraction))
	return distance


func _vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


func _clip_polygon(points: PackedVector3Array, planes: Array[Plane]) -> PackedVector3Array:
	var result := points
	for plane in planes:
		if result.is_empty():
			break
		var clipped := PackedVector3Array()
		var previous := result[result.size() - 1]
		var previous_distance := plane.distance_to(previous)
		for point in result:
			var distance := plane.distance_to(point)
			var inside := distance <= 0.0
			var prior_inside := previous_distance <= 0.0
			if inside != prior_inside:
				clipped.append(previous.lerp(point, previous_distance / (previous_distance - distance)))
			if inside:
				clipped.append(point)
			previous = point
			previous_distance = distance
		result = clipped
	return result


func _polygon_area(points: PackedVector2Array) -> float:
	var sum := 0.0
	for index in points.size():
		var point := points[index]
		var next := points[(index + 1) % points.size()]
		sum += point.x * next.y - point.y * next.x
	return absf(sum) * 0.5


func _v3(point: Vector3) -> Array:
	return [point.x, point.y, point.z]


func _transform(value: Transform3D) -> Dictionary:
	return {"origin": _v3(value.origin), "basis": [_v3(value.basis.x), _v3(value.basis.y), _v3(value.basis.z)]}


func _write_json(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_assert(file != null, "evidence JSON opens: " + path)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		print("FAIL: ", label)
