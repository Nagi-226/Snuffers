## Real range Player, production lighting and renderer-baked hands for the conventional guns.
extends SceneTree

const Chamber = preload("res://tests/chamber_test_support.gd")

const OUTPUT := "res://tmp_shots/conventional_9x19"
const WEAPONS := [[&"g17", "G17"], [&"mpx", "MPX"]]

var _assertions := 0
var _failures := 0
var _shots := 0
var _state
var _player
var _scene: Node3D
var _reference: Node3D
var _reference_skeleton: Skeleton3D
var _report: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("conventional weapon views require native rendering")
		quit(1)
		return
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("conventional weapon views timed out")
		quit(1))
	root.size = Vector2i(1920, 1080)
	_state = root.get_node("GameState")
	_state.reset()
	_scene = (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	_player = _scene.get_node("Player")
	if "--ready-only" in OS.get_cmdline_user_args():
		await _diagnose_ready()
		_scene.queue_free()
		current_scene = null
		await process_frame
		await create_timer(0.08).timeout
		await process_frame
		quit(0)
		return
	await process_frame
	await physics_frame
	await process_frame
	# This evidence fixture owns its inputs; native window keyboard/mouse events must not change its cases.
	_player.set_process_unhandled_input(false)
	_player.set_physics_process(false)
	for controller in _player.get_node("Camera3D/WeaponMount").get_children():
		controller.set_process_unhandled_input(false)
	_assert(_state.weapon_unlocked.get(&"g17", false) and _state.weapon_unlocked.get(&"mpx", false), "the actual range completes its normal unlock initialization before evidence capture")
	_reference = (load("res://addons/community_weapons/black_pistol_arms.glb") as PackedScene).instantiate() as Node3D
	_reference_skeleton = _reference.find_child("Skeleton3D", true, false) as Skeleton3D
	if _reference_skeleton == null:
		var skeletons := _reference.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			_reference_skeleton = skeletons[0] as Skeleton3D
	_assert(_reference_skeleton != null, "the unchanged source black arms provide a reference skeleton")
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for item: Array in WEAPONS:
		var id: StringName = item[0]
		var path := "Camera3D/WeaponMount/" + String(item[1])
		_assert(_player.has_node(path), "%s is present in the real playable range" % id)
		if not _player.has_node(path):
			continue
		var weapon = _player.get_node(path)
		_player._switch_weapon(id)
		_assert(_state.current_weapon == id and _state.weapon_unlocked.get(id, false), "%s production switching selects the range-unlocked gun" % id)
		if _state.current_weapon != id:
			continue
		_state.fire_modes[id] = &"semi"
		_state.ammo_9x19_reserve = 150
		_player._set_aiming(false)
		await create_timer(0.4).timeout
		await _capture(weapon, id, "hip", false, false)
		_check_source_skeleton(weapon, id)
		_check_hold_contact(weapon, id)
		_player._set_aiming(true)
		await create_timer(0.4).timeout
		await _capture(weapon, id, "ads", true, false)
		_player._set_aiming(false)
		await create_timer(0.4).timeout
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		weapon._unhandled_input(press)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		weapon._unhandled_input(release)
		await create_timer(0.05).timeout
		await _capture(weapon, id, "fire", false, false)
		await create_timer(0.4).timeout
		Chamber.set_total(_state, String(id), 3)
		_press_reload(weapon)
		_assert(weapon._is_reloading, "%s production R starts the partial reload captured below" % id)
		for phase in [0.25, 0.5, 0.75]:
			if await _wait_reload_phase(weapon, id, phase):
				await _capture(weapon, id, "reload_%03d" % int(phase * 100.0), false, true, phase)
				if phase == 0.5:
					_check_magazine_contact(weapon, id)
		await _wait_reload_completed(weapon)
		_assert(not weapon._is_reloading and _state.get(String(id) + "_mag") == weapon.weapon_data.mag_size and Chamber.total(_state, id) == weapon.weapon_data.mag_size + 1 and Chamber.chamber(_state, id) == 1, "%s captured tactical reload completes with a full container and retained chamber" % id)
		await _capture(weapon, id, "reload_complete", false, false)
		Chamber.set_total(_state, String(id), 0)
		_press_reload(weapon)
		_assert(weapon._is_reloading, "%s production R starts the empty reload" % id)
		if await _wait_reload_phase(weapon, id, 0.5):
			await _capture(weapon, id, "empty_reload_050", false, true, 0.5)
		await _wait_reload_completed(weapon)
		_assert(_state.get(String(id) + "_mag") == weapon.weapon_data.mag_size - 1 and Chamber.total(_state, id) == weapon.weapon_data.mag_size and Chamber.chamber(_state, id) == 1, "%s captured empty reload transfers one of its M rounds into the chamber" % id)
		_player._switch_weapon(&"rifle")
		await process_frame
		_assert(not weapon.visible, "%s disappears when a different gun is selected" % id)
	var file := FileAccess.open(OUTPUT + "/report.json", FileAccess.WRITE)
	_assert(file != null, "view evidence report can be saved")
	if file != null:
		file.store_string(JSON.stringify({"shots": _shots, "assertions": _assertions, "failures": _failures, "views": _report}, "\t"))
		file.close()
	_reference.free()
	_scene.queue_free()
	current_scene = null
	await process_frame
	await create_timer(0.08).timeout
	await process_frame
	print("CONVENTIONAL_9X19_VIEWS COMPLETED shots=", _shots, " assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _ready_state(label: String) -> void:
	var g17 = _player.get_node("Camera3D/WeaponMount/G17")
	var mpx = _player.get_node("Camera3D/WeaponMount/MPX")
	print("READY_DIAGNOSTIC ", label, " current=", _state.current_weapon, " unlocks=", _state.weapon_unlocked.get(&"g17", false), "/", _state.weapon_unlocked.get(&"mpx", false), " visible=", g17.visible, "/", mpx.visible, " process_frame=", Engine.get_process_frames(), " physics_frame=", Engine.get_physics_frames())


func _diagnose_ready() -> void:
	_ready_state("after_add_scene")
	await process_frame
	_ready_state("after_first_process")
	_player._switch_weapon(&"g17")
	_ready_state("switch_at_first_process")
	await physics_frame
	_ready_state("after_first_physics")
	await process_frame
	_ready_state("after_second_process")
	_player._switch_weapon(&"g17")
	_ready_state("switch_after_physics")
	await create_timer(0.4).timeout
	_ready_state("after_settle")


func _press_reload(weapon) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var event := InputEventKey.new()
	event.keycode = KEY_R
	event.physical_keycode = KEY_R
	event.pressed = true
	weapon._unhandled_input(event)


func _wait_reload_phase(weapon, id: StringName, phase: float) -> bool:
	var animation: AnimationPlayer = weapon._arms_animation
	_assert(animation != null, "%s has a real reload animation clock" % id)
	if animation == null:
		return false
	while weapon._is_reloading:
		await process_frame
		await RenderingServer.frame_post_draw
		var clip := animation.current_animation
		if clip not in ["reload", "reload_empty"]:
			_assert(false, "%s cannot sample reload while the actual animation is %s" % [id, clip])
			return false
		var actual := animation.current_animation_position / animation.get_animation(clip).length
		if actual >= phase:
			return true
	_assert(false, "%s real reload completed before its requested %.2f phase could be captured" % [id, phase])
	return false


func _wait_reload_completed(weapon) -> void:
	while weapon._is_reloading:
		await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func _capture(weapon, id: StringName, label: String, ads: bool, reload: bool, expected_phase: float = -1.0) -> void:
	if expected_phase < 0.0:
		await physics_frame
		await process_frame
		await RenderingServer.frame_post_draw
	var context: bool = _state.current_weapon == id and _state.weapon_unlocked.get(id, false) and weapon.is_visible_in_tree()
	_assert(context, "%s %s captures the selected, range-unlocked gun (actual=%s)" % [id, label, _state.current_weapon])
	if not context:
		return
	var animation: AnimationPlayer = weapon._arms_animation
	var clip: String = animation.current_animation if animation != null else ""
	var actual_phase := animation.current_animation_position / animation.get_animation(clip).length if animation != null and not clip.is_empty() else -1.0
	if expected_phase >= 0.0:
		_assert(clip in ["reload", "reload_empty"] and actual_phase >= expected_phase and actual_phase <= expected_phase + 0.10, "%s %s captures the declared real animation phase (actual=%.3f)" % [id, label, actual_phase])
	var camera: Camera3D = _player._camera
	var gun: Node3D = weapon._weapon_node
	var arms := _skin_counts(weapon, camera)
	var gun_count := _static_count(gun, camera)
	_assert(weapon.is_visible_in_tree() and gun_count > 20, "%s %s renders the selected real gun inside the Player viewport" % [id, label])
	if reload:
		_assert(arms.x > 20 and arms.y > 20, "%s %s brings both renderer-baked native arms into the viewport" % [id, label])
	_assert(weapon._magazine != null and _mesh_vertices(weapon._magazine) > 100, "%s %s operates an actual mesh magazine rather than a marker" % [id, label])
	if ads:
		var center := Vector2(root.size) * 0.5
		var origin := camera.project_ray_origin(center)
		var direction := camera.project_ray_normal(center)
		var blocking := _opaque_blocker(_player._weapon_mount, origin, direction)
		_assert(blocking.is_empty(), "%s ADS center passes through actual opaque gun and renderer-baked hands (blocker=%s)" % [id, blocking])
		if id == &"mpx":
			var glass := _glass_bounds(gun)
			_assert(glass.size.length() > 0.001, "MPX ADS uses the actual transparent EOTech lens geometry")
			if glass.size.length() > 0.001:
				var error := camera.unproject_position(glass.get_center()).distance_to(center)
				print("MPX_REAL_LENS pixel_error=", error, " bounds=", glass)
				_assert(error < 2.0, "the actual MPX lens center aligns within two pixels of the Player ADS center")
		else:
			_check_g17_sights(gun, camera, center)
	var error := root.get_texture().get_image().save_png(OUTPUT + "/%s_%s.png" % [id, label])
	_assert(error == OK, "%s %s screenshot saves successfully" % [id, label])
	if error == OK:
		_shots += 1
	_report.append({"weapon": String(id), "phase": label, "actual_weapon": String(_state.current_weapon), "actual_clip": clip, "actual_animation_phase": actual_phase, "gun_vertices": gun_count, "left_arm_vertices": arms.x, "right_arm_vertices": arms.y, "save_error": error})
	print("CONVENTIONAL_VIEW ", id, " ", label, " gun=", gun_count, " arms=", arms, " actual_clip=", clip, " actual_phase=", actual_phase)


func _check_source_skeleton(weapon, id: StringName) -> void:
	var skeleton: Skeleton3D = weapon._arms_skeleton
	_assert(skeleton != null and _reference_skeleton != null, "%s resolves the original native skeleton" % id)
	if skeleton == null or _reference_skeleton == null:
		return
	var intact := skeleton.get_bone_count() == 60 and skeleton.get_bone_count() == _reference_skeleton.get_bone_count()
	for bone in mini(skeleton.get_bone_count(), _reference_skeleton.get_bone_count()):
		intact = intact and skeleton.get_bone_name(bone) == _reference_skeleton.get_bone_name(bone) and skeleton.get_bone_rest(bone).is_equal_approx(_reference_skeleton.get_bone_rest(bone))
	_assert(intact, "%s preserves all sixty source bone names and rest transforms" % id)


func _check_hold_contact(weapon, id: StringName) -> void:
	var palms := _palm_medians(weapon)
	_assert(palms.size() == 2, "%s hold measures both actual renderer-baked palm skins" % id)
	if palms.size() != 2:
		return
	var gun: Node3D = weapon._weapon_node
	var body := gun.find_child("Frame" if id == &"g17" else "Body", true, false) as Node3D
	if body == null:
		body = gun
	var right_distance := _distance_to_bounds(palms[1], _mesh_bounds(body))
	if id == &"mpx":
		_check_mpx_actual_grip(gun, palms[1])
	else:
		_assert(right_distance < 0.04, "%s actual right palm reaches the real grip body within glove thickness" % id)
		_check_g17_support_hand(weapon, palms[0])
		return
	var support := gun.find_child("Foregrip", true, false) as Node3D if id == &"mpx" else body
	_assert(support != null, "%s has its real support-hand geometry" % id)
	if support != null:
		var left_distance := _distance_to_bounds(palms[0], _mesh_bounds(support))
		print("CONVENTIONAL_HOLD_CONTACT ", id, " R=", right_distance, " L=", left_distance, " palms=", palms)
		_assert(left_distance < 0.04, "%s actual left palm reaches its real support geometry within glove thickness" % id)


func _check_g17_support_hand(weapon, left_palm: Vector3) -> void:
	# A two-handed pistol grip supports the firing hand; it need not touch the frame directly.
	var faces := _g17_right_hand_faces(weapon)
	_assert(faces.size() > 60, "G17 support validation uses actual renderer-baked right palm and finger triangles")
	if faces.size() <= 60:
		return
	var distance := _hand_surface_distance(left_palm, faces)
	print("G17_SUPPORT_CONTACT left_palm=", left_palm, " right_hand_faces=", faces.size() / 3, " distance=", distance)
	_assert(distance < 0.04, "G17 actual left palm supports the actual right-hand skin within glove thickness")
	var skeleton: Skeleton3D = weapon._arms_skeleton
	var elbow := skeleton.find_bone("R_elbow_027")
	_assert(elbow >= 0, "G17 source right elbow provides a separate forearm negative control")
	if elbow >= 0:
		var forearm := skeleton.global_transform * skeleton.get_bone_global_pose(elbow).origin
		var forearm_distance := _hand_surface_distance(forearm, faces)
		print("G17_SUPPORT_NEGATIVE forearm=", forearm, " right_hand_distance=", forearm_distance)
		_assert(forearm_distance > 0.04, "G17 local hand contact check rejects a support palm moved to the source forearm")


func _g17_right_hand_faces(owner: Node3D) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for child in owner.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if not mesh.is_visible_in_tree() or mesh.skin == null or mesh.mesh == null:
			continue
		var skeleton := mesh.get_node(mesh.skeleton) as Skeleton3D
		var wrist := skeleton.find_bone("R_wrist_028")
		var palm := skeleton.find_bone("R_palm_041")
		if wrist < 0 or palm < 0:
			continue
		var wrist_point := skeleton.global_transform * skeleton.get_bone_global_pose(wrist).origin
		var palm_point := skeleton.global_transform * skeleton.get_bone_global_pose(palm).origin
		var distal := (palm_point - wrist_point).normalized()
		var posed := mesh.bake_mesh_from_current_skeleton_pose()
		for surface in posed.get_surface_count():
			var source := mesh.mesh.surface_get_arrays(surface)
			var arrays := posed.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var bones: PackedInt32Array = source[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = source[Mesh.ARRAY_WEIGHTS]
			if vertices.is_empty() or bones.is_empty():
				continue
			var width: int = bones.size() / vertices.size()
			var hand := PackedByteArray()
			hand.resize(vertices.size())
			for vertex in vertices.size():
				var hand_weight := 0.0
				for influence in width:
					var offset := vertex * width + influence
					if weights[offset] <= 0.0:
						continue
					var bone := skeleton.find_bone(mesh.skin.get_bind_name(bones[offset]))
					while bone >= 0:
						if bone == wrist:
							hand_weight += weights[offset]
							break
						bone = skeleton.get_bone_parent(bone)
				# The hand bone branch plus the distal wrist plane excludes the arm and sleeve.
				var point := mesh.global_transform * vertices[vertex]
				hand[vertex] = int(hand_weight > 0.65 and (point - wrist_point).dot(distal) >= 0.0)
			var size := indices.size() if not indices.is_empty() else vertices.size()
			for offset in range(0, size, 3):
				var a := indices[offset] if not indices.is_empty() else offset
				var b := indices[offset + 1] if not indices.is_empty() else offset + 1
				var c := indices[offset + 2] if not indices.is_empty() else offset + 2
				if hand[a] > 0 and hand[b] > 0 and hand[c] > 0:
					result.append(mesh.global_transform * vertices[a])
					result.append(mesh.global_transform * vertices[b])
					result.append(mesh.global_transform * vertices[c])
	return result


func _hand_surface_distance(point: Vector3, faces: Array[Vector3]) -> float:
	var distance := INF
	for offset in range(0, faces.size(), 3):
		distance = minf(distance, _point_triangle_distance(point, faces[offset], faces[offset + 1], faces[offset + 2]))
	return distance


func _point_triangle_distance(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var normal := (b - a).cross(c - a)
	var area := normal.length_squared()
	if area > 1.0e-16:
		var projected := point - normal * ((point - a).dot(normal) / area)
		if normal.dot((b - a).cross(projected - a)) >= 0.0 \
			and normal.dot((c - b).cross(projected - b)) >= 0.0 \
			and normal.dot((a - c).cross(projected - c)) >= 0.0:
			return point.distance_to(projected)
	var distance := INF
	for edge: Array in [[a, b], [b, c], [c, a]]:
		var begin: Vector3 = edge[0]
		var segment: Vector3 = edge[1] - begin
		var length := segment.length_squared()
		var fraction := clampf((point - begin).dot(segment) / length, 0.0, 1.0) if length > 1.0e-16 else 0.0
		distance = minf(distance, point.distance_to(begin + segment * fraction))
	return distance


func _check_mpx_actual_grip(gun: Node3D, right_palm: Vector3) -> void:
	var grip := gun.find_child("BodyPart25", true, false) as MeshInstance3D
	_assert(grip != null and grip.mesh != null, "MPX grip validation uses the actual source handgrip faces")
	if grip == null or grip.mesh == null:
		return
	var palm := gun.global_transform.affine_inverse() * right_palm
	# The source grip extends Y=-0.10244..0.03759; the lower grasping section excludes its receiver junction.
	var section := _mpx_grip_section(grip, gun, clampf(palm.y, -0.09, -0.035))
	_assert(int(section.get("points", 0)) >= 6, "MPX source grip provides a real triangle intersection section at hand height")
	if int(section.get("points", 0)) < 6:
		return
	var bounds: AABB = section.bounds
	print("MPX_LOCAL_GRIP palm=", palm, " real_section=", bounds, " side_error=", absf(palm.x - bounds.end.x))
	_assert(_mpx_grip_matches(palm, bounds), "MPX actual right palm contacts the handgrip right side within 15mm and stays in the lower grip section")
	var receiver_point := Vector3(bounds.get_center().x, 0.02, bounds.get_center().z)
	var body := gun.find_child("Body", true, false) as Node3D
	_assert(body != null and _distance_to_bounds(gun.to_global(receiver_point), _mesh_bounds(body)) < 0.04, "MPX receiver-junction negative control would pass the old entire-Body proximity check")
	_assert(not _mpx_grip_matches(receiver_point, bounds), "MPX local grip check rejects a hand resting on the receiver junction")


func _mpx_grip_matches(palm: Vector3, section: AABB) -> bool:
	return palm.y >= -0.09 and palm.y <= -0.035 and palm.x > section.get_center().x \
		and absf(palm.x - section.end.x) <= 0.015 \
		and palm.z >= section.position.z - 0.015 and palm.z <= section.end.z + 0.015


func _mpx_grip_section(grip: MeshInstance3D, gun: Node3D, height: float) -> Dictionary:
	var bounds := AABB()
	var count := 0
	var transform := gun.global_transform.affine_inverse() * grip.global_transform
	for surface in grip.mesh.get_surface_count():
		var arrays := grip.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var size := indices.size() if not indices.is_empty() else vertices.size()
		for offset in range(0, size, 3):
			var triangle: Array[Vector3] = []
			for corner in 3:
				triangle.append(transform * vertices[indices[offset + corner] if not indices.is_empty() else offset + corner])
			for edge in 3:
				var a := triangle[edge]
				var b := triangle[(edge + 1) % 3]
				if (a.y - height) * (b.y - height) > 0.0 or is_zero_approx(b.y - a.y):
					continue
				var point := a.lerp(b, (height - a.y) / (b.y - a.y))
				bounds = AABB(point, Vector3.ZERO) if count == 0 else bounds.expand(point)
				count += 1
	return {"bounds": bounds, "points": count}


func _check_magazine_contact(weapon, id: StringName) -> void:
	var palms := _palm_medians(weapon)
	_assert(palms.size() == 2, "%s reload measures actual palm skins" % id)
	if palms.size() != 2 or weapon._magazine == null:
		return
	var bounds := _mesh_bounds(weapon._magazine)
	var distance := _distance_to_bounds(palms[0], bounds)
	print("CONVENTIONAL_MAG_CONTACT ", id, " distance=", distance, " magazine_bounds=", bounds, " left_palm=", palms[0])
	_assert(distance < 0.04, "%s actual left palm follows the extracted real magazine within glove thickness" % id)


func _distance_to_bounds(point: Vector3, bounds: AABB) -> float:
	return point.distance_to(Vector3(clampf(point.x, bounds.position.x, bounds.end.x), clampf(point.y, bounds.position.y, bounds.end.y), clampf(point.z, bounds.position.z, bounds.end.z)))


func _mesh_bounds(owner: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	var meshes := owner.find_children("*", "MeshInstance3D", true, false)
	if owner is MeshInstance3D:
		meshes.append(owner)
	for child in meshes:
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		var current: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = current if first else bounds.merge(current)
		first = false
	return bounds


func _check_g17_sights(gun: Node3D, camera: Camera3D, center: Vector2) -> void:
	# Source-measured front post and rear notch; the point is 0.103 mm above the real sight tops.
	var slide := gun.find_child("SlidePart1", true, false) as MeshInstance3D
	_assert(slide != null and slide.mesh != null, "G17 ADS retains its actual mechanical sight mesh")
	if slide == null or slide.mesh == null:
		return
	var front_top := -INF
	var rear_top := -INF
	var rear_left := false
	var rear_right := false
	var inverse := gun.global_transform.affine_inverse()
	for surface in slide.mesh.get_surface_count():
		var arrays := slide.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var local: Vector3 = inverse * slide.global_transform * vertex
			if absf(local.x - 0.000476038) > 0.003:
				continue
			if local.z > -0.09 and local.z < -0.06:
				front_top = maxf(front_top, local.y)
			if local.z > 0.074 and local.z < 0.082 and local.y > 0.064:
				rear_top = maxf(rear_top, local.y)
				rear_left = rear_left or absf(local.x + 0.00121931755) < 0.0001
				rear_right = rear_right or absf(local.x - 0.00217136834) < 0.0001
	_assert(absf(front_top - 0.06451677531) < 0.0001 and absf(rear_top - 0.06449795514) < 0.0001 and rear_left and rear_right, "G17 ADS checks the preserved real front post top and both rear-notch edges")
	var sight_point := gun.global_transform * Vector3(0.000476038, 0.06462, 0.07767575)
	var error := camera.unproject_position(sight_point).distance_to(center)
	print("G17_REAL_SIGHT pixel_error=", error, " front_top=", front_top, " rear_top=", rear_top)
	_assert(error < 2.0, "G17 actual mechanical sight axis aligns within two pixels of the Player ADS center")


func _glass_bounds(gun: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for child in gun.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			if material == null or material.resource_name != "EotechOpticalGlass":
				continue
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point := mesh.global_transform * vertex
				bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
				first = false
	return bounds


func _mesh_vertices(owner: Node3D) -> int:
	var count := 0
	var meshes := owner.find_children("*", "MeshInstance3D", true, false)
	if owner is MeshInstance3D:
		meshes.append(owner)
	for child in meshes:
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			count += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return count


func _static_count(owner: Node3D, camera: Camera3D) -> int:
	var count := 0
	for child in owner.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				if camera.is_position_in_frustum(mesh.global_transform * vertex):
					count += 1
	return count


func _skin_counts(owner: Node3D, camera: Camera3D) -> Vector2i:
	var count := Vector2i.ZERO
	for child in owner.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
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
					if weights[offset] <= 0.0:
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


func _palm_medians(owner: Node3D) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for names in [["L_wrist_04", "L_palm_017"], ["R_wrist_028", "R_palm_041"]]:
		var points: Array[Vector3] = []
		for child in owner.find_children("*", "MeshInstance3D", true, false):
			var mesh := child as MeshInstance3D
			if not mesh.is_visible_in_tree() or mesh.skin == null:
				continue
			var skeleton := mesh.get_node(mesh.skeleton) as Skeleton3D
			var posed := mesh.bake_mesh_from_current_skeleton_pose()
			for surface in posed.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = posed.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var width: int = bones.size() / vertices.size()
				for vertex in vertices.size():
					var weight := 0.0
					for influence in width:
						var offset := vertex * width + influence
						if weights[offset] <= 0.0:
							continue
						var bone := skeleton.find_bone(mesh.skin.get_bind_name(bones[offset]))
						if skeleton.get_bone_name(bone) in names:
							weight += weights[offset]
					if weight > 0.65:
						points.append(mesh.global_transform * vertices[vertex])
		if points.is_empty():
			return []
		var median := Vector3.ZERO
		for axis in 3:
			var coordinates: Array[float] = []
			for point in points:
				coordinates.append(point[axis])
			coordinates.sort()
			median[axis] = coordinates[coordinates.size() / 2]
		result.append(median)
	return result


func _opaque_blocker(owner: Node3D, origin: Vector3, direction: Vector3) -> String:
	for child in owner.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var posed: Mesh = mesh.bake_mesh_from_current_skeleton_pose() if mesh.skin != null else mesh.mesh
		for surface in posed.get_surface_count():
			var material := mesh.get_active_material(surface) as BaseMaterial3D
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
					return String(mesh.get_path())
	return ""


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		print("FAIL: ", label)
