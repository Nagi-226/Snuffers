## Native playtest feedback: actual grip skin, source optic parts and red texture.
extends "res://tools/probe_conventional_9x19.gd"

const FEEDBACK_OUTPUT := "res://tmp_shots/conventional_feedback"
# Recorded by the original-anchor native replay at actual reload phase 0.7604255.
# This compatibility boundary preserves evidence of the four existing left-thumb intersections.
const G17_RELOAD_LEFT_BASELINE := {
	4917: Vector3(-0.00990711245685816, 0.04136598482728, -0.0432296395301819),
	4921: Vector3(-0.0103397788479924, 0.043233972042799, -0.0496658384799957),
	4922: Vector3(-0.00847085285931826, 0.0409120991826057, -0.0541951954364777),
	5458: Vector3(-0.00847085285931826, 0.0409120991826057, -0.0541951954364777),
}

var _frame_geometry_dumped := false
var _slide_collision_mesh: Mesh
var _slide_collision_bounds := AABB()
var _slide_ray_cache: Array = []
var _slide_triangle_count := 0
var _baseline_guard_checked := false


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("conventional feedback requires native rendering")
		quit(1)
		return
	create_timer(120.0).timeout.connect(func() -> void:
		push_error("conventional feedback timed out")
		quit(1))
	root.size = Vector2i(1920, 1080)
	_state = root.get_node("GameState")
	_state.reset()
	_scene = (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	_player = _scene.get_node("Player")
	await process_frame
	await physics_frame
	await process_frame
	# Only the fixture's input handlers control cases; normal weapon/process clocks remain active.
	_player.set_process_unhandled_input(false)
	_player.set_physics_process(false)
	for controller in _player.get_node("Camera3D/WeaponMount").get_children():
		controller.set_process_unhandled_input(false)
	_player.global_position = Vector3(44.0, 0.1, 19.0)
	_player.rotation = Vector3(0, PI, 0)
	_player._camera.rotation = Vector3.ZERO
	var lighting = _scene.get_node("GreyboxArena/DayNightController")
	if lighting.is_night():
		lighting.toggle_mode()
	_assert(not _state.is_night, "feedback uses the production range DAY preset")
	_assert(_state.weapon_unlocked.get(&"g17", false) and _state.weapon_unlocked.get(&"mpx", false), "normal range initialization unlocks both guns")
	_reference = (load("res://addons/community_weapons/black_pistol_arms.glb") as PackedScene).instantiate() as Node3D
	var skeletons := _reference.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_reference_skeleton = skeletons[0] as Skeleton3D
	_assert(_reference_skeleton != null, "feedback has the unchanged source skeleton reference")
	_assert(DirAccess.make_dir_recursive_absolute(FEEDBACK_OUTPUT) == OK, "feedback screenshot directory is available")
	for item: Array in WEAPONS:
		var id: StringName = item[0]
		var weapon = _player.get_node("Camera3D/WeaponMount/" + String(item[1]))
		_player._switch_weapon(id)
		_state.fire_modes[id] = &"semi"
		_state.ammo_9x19_reserve = 510
		_player._set_aiming(false)
		await create_timer(0.4).timeout
		await _feedback_capture(weapon, id, "hip", false, false)
		if id == &"g17":
			_check_feedback_finger_repeat(weapon, "initial_idle")
		_player._set_aiming(true)
		await create_timer(0.4).timeout
		await _feedback_capture(weapon, id, "ads", true, false)
		_player._set_aiming(false)
		await create_timer(0.4).timeout
		if id == &"g17":
			for phase in [0.25, 0.5, 0.75]:
				_press_feedback_fire(weapon)
				if await _wait_feedback_fire_phase(weapon, phase):
					await _feedback_capture(weapon, id, "fire_%03d" % int(phase * 100.0), false, false, phase)
				await create_timer(0.4).timeout
		Chamber.set_total(_state, String(id), 3)
		_press_reload(weapon)
		_assert(weapon._is_reloading, "%s real R input starts a partial reload" % id)
		for phase in [0.25, 0.5, 0.75]:
			if await _wait_reload_phase(weapon, id, phase):
				await _feedback_capture(weapon, id, "reload_%03d" % int(phase * 100.0), false, true, phase)
				if phase == 0.5:
					_check_magazine_contact(weapon, id)
		await _wait_reload_completed(weapon)
		_assert(_state.get(String(id) + "_mag") == weapon.weapon_data.mag_size and Chamber.total(_state, id) == weapon.weapon_data.mag_size + 1 and Chamber.chamber(_state, id) == 1, "%s real partial reload completes with M container plus one retained chamber" % id)
		await _feedback_capture(weapon, id, "reload_complete", false, false)
		if id == &"g17":
			_check_feedback_finger_repeat(weapon, "after_reload")
		Chamber.set_total(_state, String(id), 0)
		_press_reload(weapon)
		_assert(weapon._is_reloading, "%s real R input starts an empty reload" % id)
		if await _wait_reload_phase(weapon, id, 0.5):
			await _feedback_capture(weapon, id, "empty_reload_050", false, true, 0.5)
		await _wait_reload_completed(weapon)
		_check_source_skeleton(weapon, id)
		_assert(_state.get(String(id) + "_mag") == weapon.weapon_data.mag_size - 1 and Chamber.total(_state, id) == weapon.weapon_data.mag_size and Chamber.chamber(_state, id) == 1, "%s real empty reload keeps M total and transfers one round from container to chamber" % id)
		_player._switch_weapon(&"rifle")
		await process_frame
		_assert(not weapon.visible, "%s remains hidden after switching away" % id)
	var report := FileAccess.open(FEEDBACK_OUTPUT + "/report.json", FileAccess.WRITE)
	_assert(report != null, "feedback geometry report can be saved")
	if report != null:
		report.store_string(JSON.stringify({"shots": _shots, "assertions": _assertions, "failures": _failures, "views": _report}, "\t"))
		report.close()
	_reference.free()
	_scene.queue_free()
	current_scene = null
	await process_frame
	await create_timer(0.08).timeout
	await process_frame
	print("CONVENTIONAL_FEEDBACK COMPLETED shots=", _shots, " assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _press_feedback_fire(weapon) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	weapon._unhandled_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	weapon._unhandled_input(release)


func _check_feedback_finger_repeat(weapon, label: String) -> void:
	var skeleton: Skeleton3D = weapon._arms_skeleton
	var finger := skeleton.find_bone("R_point1_033")
	_assert(finger >= 0, "G17 repeat sampling resolves the actual index knuckle")
	if finger < 0:
		return
	var before := skeleton.get_bone_pose_rotation(finger)
	for sample in 20:
		weapon._native_arms.update(0.0)
		var current := skeleton.get_bone_pose_rotation(finger)
		_assert(absf(before.dot(current)) > 0.999999, "G17 %s repeated zero-time source sampling does not accumulate finger rotation (%d)" % [label, sample])


func _wait_feedback_fire_phase(weapon, phase: float) -> bool:
	var animation: AnimationPlayer = weapon._arms_animation
	var started := false
	var deadline := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < deadline:
		await process_frame
		await RenderingServer.frame_post_draw
		if animation.current_animation == &"fire":
			started = true
			var actual := animation.current_animation_position / animation.get_animation(&"fire").length
			if actual >= phase:
				return true
		elif started:
			_assert(false, "G17 fire finished before its requested actual phase %.2f" % phase)
			return false
	_assert(false, "G17 real semi input did not reach fire phase %.2f" % phase)
	return false


func _feedback_capture(weapon, id: StringName, label: String, ads: bool, reload: bool, expected_phase: float = -1.0) -> void:
	await RenderingServer.frame_post_draw
	_assert(_state.current_weapon == id and weapon.is_visible_in_tree(), "%s %s captures the actually selected gun" % [id, label])
	var animation: AnimationPlayer = weapon._arms_animation
	var clip: String = animation.current_animation
	var actual_phase := animation.current_animation_position / animation.get_animation(clip).length if not clip.is_empty() else -1.0
	if expected_phase >= 0.0:
		_assert(clip in ["reload", "reload_empty", "fire"] and actual_phase >= expected_phase and actual_phase <= expected_phase + 0.10, "%s %s samples its actual animation clock (clip=%s phase=%.3f)" % [id, label, clip, actual_phase])
	var camera: Camera3D = _player._camera
	var gun: Node3D = weapon._weapon_node
	var arms := _skin_counts(weapon, camera)
	_assert(_static_count(gun, camera) > 20, "%s %s actual source gun is in the viewport" % [id, label])
	_assert(arms.x > 20 and arms.y > 20, "%s %s both actual skinned arms are in the viewport" % [id, label])
	_check_source_skeleton(weapon, id)
	var center := Vector2(root.size) * 0.5
	if not reload:
		_check_hold_contact(weapon, id)
		if id == &"g17" and clip == "idle":
			_check_g17_high_grip(weapon, label)
			_assert(gun.transform.origin.distance_to(weapon._weapon_home.origin) < 0.001, "G17 %s retains the original gun position while correcting hands" % label)
	if id == &"g17" and (reload or clip != "idle"):
		_check_g17_slide_clearance(weapon, label)
	if ads:
		var blocker := _opaque_blocker(_player._weapon_mount, camera.project_ray_origin(center), camera.project_ray_normal(center))
		_assert(blocker.is_empty(), "%s actual ADS ray passes through opaque gun and hand geometry (blocker=%s)" % [id, blocker])
		if id == &"g17":
			_check_g17_sights(gun, camera, center)
		else:
			_check_mpx_feedback(gun, camera, center)
	var error := root.get_texture().get_image().save_png(FEEDBACK_OUTPUT + "/%s_%s.png" % [id, label])
	_assert(error == OK, "%s %s production-material screenshot saves" % [id, label])
	if error == OK:
		_shots += 1
	_report.append({"weapon": String(id), "phase": label, "actual_clip": clip, "actual_animation_phase": actual_phase, "left_arm_vertices": arms.x, "right_arm_vertices": arms.y})
	if id == &"g17":
		var skeleton: Skeleton3D = weapon._arms_skeleton
		var finger := skeleton.find_bone("R_point1_033")
		if finger >= 0:
			var pose := skeleton.get_bone_pose_rotation(finger)
			print("G17_INDEX_SOURCE_POSE ", label, " actual_clip=", clip, " actual_phase=", actual_phase, " local_pose=", pose)
			_report.append({"weapon": "g17", "phase": label, "actual_clip": clip, "actual_animation_phase": actual_phase, "index_local_pose": str(pose)})


func _check_g17_high_grip(weapon, label: String) -> void:
	var gun: Node3D = weapon._weapon_node
	var frame := gun.find_child("FramePart1", true, false) as MeshInstance3D
	var palms := _palm_medians(weapon)
	_assert(frame != null and frame.mesh != null and palms.size() == 2, "G17 high grip measures actual frame and both baked palm skins")
	if frame == null or frame.mesh == null or palms.size() != 2:
		return
	var inverse := gun.global_transform.affine_inverse()
	var transform := inverse * frame.global_transform
	var grip := AABB()
	var count := 0
	var frame_bounds := AABB()
	var all_vertices: Array = []
	var all_indices: Array = []
	for surface in frame.mesh.get_surface_count():
		var arrays := frame.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertex_base := all_vertices.size()
		for index in indices:
			all_indices.append(vertex_base + index)
		for vertex in vertices:
			var point := transform * vertex
			frame_bounds = AABB(point, Vector3.ZERO) if all_vertices.is_empty() else frame_bounds.expand(point)
			all_vertices.append([point.x, point.y, point.z])
			# Actual rear grip faces, excluding the forward trigger guard/rail and upper receiver.
			if point.z < 0.04 or point.y > 0.025:
				continue
			grip = AABB(point, Vector3.ZERO) if count == 0 else grip.expand(point)
			count += 1
	var right: Vector3 = inverse * palms[1]
	var left: Vector3 = inverse * palms[0]
	# Intersect real triangles near the measured grip top, not the empty Z>75mm vertex band.
	var section_height := grip.position.y + grip.size.y * 0.95
	var section := _g17_backstrap_section(frame, gun, section_height, grip.position.z)
	var rear_z := -INF
	for point in section:
		rear_z = maxf(rear_z, point.z)
	var upper_points: Array[Vector3] = []
	for point in section:
		if point.z >= rear_z - 0.001:
			upper_points.append(point)
	print("G17_FRAME_GEOMETRY ", label, " frame_vertices=", all_vertices.size(), " frame_indices=", all_indices.size(), " actual_frame=", frame_bounds, " rear_grip_vertices=", count, " rear_grip=", grip, " upper_section_height=", section_height, " actual_section_points=", section.size(), " actual_rear_points=", upper_points.size(), " right_palm=", right, " left_palm=", left, " left_minus_right=", left - right)
	if not _frame_geometry_dumped:
		var file := FileAccess.open(FEEDBACK_OUTPUT + "/g17_frame_part1_geometry.json", FileAccess.WRITE)
		_assert(file != null, "G17 complete actual frame vertex and triangle data can be saved")
		if file != null:
			file.store_string(JSON.stringify({"vertices_gun_local": all_vertices, "indices": all_indices, "frame_bounds": str(frame_bounds), "grip_bounds": str(grip), "upper_section_height": section_height, "actual_section_points": section, "right_palm": str(right), "left_palm": str(left)}, "\t"))
			file.close()
			_frame_geometry_dumped = true
	_assert(count > 100 and section.size() >= 6 and not upper_points.is_empty(), "G17 high grip has real upper backstrap triangle intersections independent of its placement config")
	if count <= 100 or section.size() < 6 or upper_points.is_empty():
		return
	_assert(_g17_high_grip_matches(right, grip), "G17 %s actual firing palm reaches the upper grip rather than the magazine heel" % label)
	var low_control := Vector3(grip.get_center().x, grip.position.y - 0.02, grip.get_center().z)
	_assert(_distance_to_bounds(gun.to_global(low_control), _mesh_bounds(frame)) < 0.04, "G17 low-hand negative control passes the old whole-frame proximity guard")
	_assert(not _g17_high_grip_matches(low_control, grip), "G17 high-grip guard rejects the source magazine-heel placement")
	var upper := Vector3.ZERO
	for point in upper_points:
		upper += point
	upper /= upper_points.size()
	var hand_faces := _g17_right_hand_faces(weapon)
	var web_faces: Array[Vector3] = []
	for offset in range(0, hand_faces.size(), 3):
		var rear := true
		for corner in 3:
			var local: Vector3 = inverse * hand_faces[offset + corner]
			rear = rear and local.z >= upper.z - 0.02 and local.y <= upper.y + 0.025
		if rear:
			for corner in 3:
				web_faces.append(hand_faces[offset + corner])
	_assert(web_faces.size() > 30, "G17 thumb-web contact excludes the forward trigger fingers and sleeve")
	var distance := _hand_surface_distance(gun.to_global(upper), web_faces)
	_assert(distance <= 0.025, "G17 %s actual rear hand skin meets the upper backstrap within 25mm" % label)
	print("G17_HIGH_GRIP ", label, " right_palm=", right, " left_palm=", left, " real_grip=", grip, " upper_backstrap=", upper, " rear_hand_faces=", web_faces.size() / 3, " upper_contact_distance=", distance)
	_report.append({"weapon": "g17", "phase": label, "right_palm_local": str(right), "left_palm_local": str(left), "real_grip": str(grip), "upper_backstrap": str(upper), "upper_contact_distance": distance})
	_check_g17_slide_clearance(weapon, label, {"grip": grip, "upper": upper, "web_faces": web_faces, "right_palm": right})


func _check_g17_slide_clearance(weapon, label: String, analysis: Dictionary = {}) -> void:
	var gun: Node3D = weapon._weapon_node
	var slide := gun.find_child("SlidePart1", true, false) as MeshInstance3D
	_assert(slide != null and slide.mesh != null, "G17 hand clearance uses the real source SlidePart1 mesh")
	if slide == null or slide.mesh == null:
		return
	if _slide_collision_mesh != slide.mesh:
		_cache_slide_triangles(slide.mesh)
	_assert(_slide_triangle_count > 10000, "G17 hand clearance checks the complete actual slide triangle shell")
	var vertices := _baked_hand_vertices(weapon, slide)
	var counts := Vector2i.ZERO
	var candidates := Vector2i.ZERO
	var inside := Vector2i.ZERO
	var shifted_candidates := Vector2i.ZERO
	var shifted_inside := Vector2i.ZERO
	var actual_inside: Array = []
	var baseline_ids: Dictionary = {}
	var animation: AnimationPlayer = weapon._arms_animation
	var actual_clip: String = animation.current_animation
	var actual_phase := animation.current_animation_position / animation.get_animation(actual_clip).length if not actual_clip.is_empty() else -1.0
	# This is a read-only static candidate, not a new production pose or a pass criterion.
	var candidate_shift := Vector3(0.006, 0, 0)
	var shift_in_slide: Vector3 = slide.global_basis.inverse() * gun.global_basis * candidate_shift
	var slide_to_gun := gun.global_transform.affine_inverse() * slide.global_transform
	for vertex: Dictionary in vertices:
		var side: int = vertex.side
		var point: Vector3 = vertex.point
		counts[side] += 1
		if _slide_collision_bounds.has_point(point):
			candidates[side] += 1
			if _slide_contains(point):
				inside[side] += 1
				var local: Vector3 = slide_to_gun * point
				var record := {"side": "right" if side == 0 else "left", "bone": vertex.bone, "mesh": vertex.mesh, "surface": vertex.surface, "vertex": vertex.vertex, "gun_local": [local.x, local.y, local.z]}
				if _matches_g17_baseline_left_vertex(vertex, local, actual_clip, actual_phase) and not baseline_ids.has(vertex.vertex):
					baseline_ids[vertex.vertex] = true
					record["known_baseline"] = true
					var baseline: Vector3 = G17_RELOAD_LEFT_BASELINE[vertex.vertex]
					print("KNOWN_BASELINE G17 ", label, " mesh=", vertex.mesh, " surface=", vertex.surface, " vertex=", vertex.vertex, " bone=", vertex.bone, " actual_clip=", actual_clip, " actual_phase=", actual_phase, " gun_local=", local, " baseline_distance=", local.distance_to(baseline))
				actual_inside.append(record)
		if not analysis.is_empty():
			var shifted: Vector3 = point + shift_in_slide
			if _slide_collision_bounds.has_point(shifted):
				shifted_candidates[side] += 1
				if _slide_contains(shifted):
					shifted_inside[side] += 1
	_assert(counts.x > 1000 and counts.y > 1000, "G17 clearance samples both complete renderer-baked wrist and finger bone branches")
	# Independently checked source solid band: all three projected ray parities are odd.
	_assert(_slide_contains(Vector3(0.000476, 0.039470968, -0.007853341)), "G17 actual solid-slide positive control is inside its real triangle shell")
	var exterior := _slide_collision_bounds.get_center()
	exterior.x = _slide_collision_bounds.end.x + 0.005
	_assert(not _slide_contains(exterior), "G17 triangle-shell guard rejects an exterior negative control")
	_check_g17_baseline_guard()
	_assert(inside.x == 0, "G17 %s actual right wrist and finger skins do not enter the real slide solid (inside=%d)" % [label, inside.x])
	_assert(inside.y == baseline_ids.size(), "G17 %s actual left slide intersections add no points beyond the recorded reload baseline (inside=%d known_baseline=%d)" % [label, inside.y, baseline_ids.size()])
	print("G17_SLIDE_CLEARANCE ", label, " baked_hand_vertices=", counts, " actual_slide_triangles=", _slide_triangle_count, " aabb_candidates=", candidates, " actual_solid_inside=", inside, " inside_points=", JSON.stringify(actual_inside))
	_report.append({"weapon": "g17", "phase": label, "baked_right_hand_vertices": counts.x, "baked_left_hand_vertices": counts.y, "right_slide_inside": inside.x, "left_slide_inside": inside.y, "known_baseline_left_vertex_ids": baseline_ids.keys(), "inside_points": actual_inside})
	if not analysis.is_empty():
		var shifted_web: Array[Vector3] = []
		var shift_world: Vector3 = gun.global_basis * candidate_shift
		for point: Vector3 in analysis.web_faces:
			shifted_web.append(point + shift_world)
		var shifted_web_distance := _hand_surface_distance(gun.to_global(analysis.upper as Vector3), shifted_web)
		var right_palm: Vector3 = analysis.right_palm
		print("G17_STATIC_SHIFT_CANDIDATE ", label, " gun_local_shift=", candidate_shift, " whole_hand_aabb_candidates=", shifted_candidates, " whole_hand_solid_inside=", shifted_inside, " right_palm=", right_palm + candidate_shift, " high_grip_matches=", _g17_high_grip_matches(right_palm + candidate_shift, analysis.grip as AABB), " real_upper_web_distance=", shifted_web_distance)
		_report.append({"weapon": "g17", "phase": label, "static_x_6mm_right_inside": shifted_inside.x, "static_x_6mm_left_inside": shifted_inside.y, "static_x_6mm_web_distance": shifted_web_distance})


func _baked_hand_vertices(owner: Node3D, slide: MeshInstance3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var inverse := slide.global_transform.affine_inverse()
	for child in owner.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if not mesh.is_visible_in_tree() or mesh.skin == null or mesh.mesh == null:
			continue
		var skeleton := mesh.get_node(mesh.skeleton) as Skeleton3D
		var wrists := [skeleton.find_bone("R_wrist_028"), skeleton.find_bone("L_wrist_04")]
		var posed := mesh.bake_mesh_from_current_skeleton_pose()
		var transform := inverse * mesh.global_transform
		for surface in posed.get_surface_count():
			var source := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = posed.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = source[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = source[Mesh.ARRAY_WEIGHTS]
			if vertices.is_empty() or bones.is_empty():
				continue
			var width: int = bones.size() / vertices.size()
			for vertex in vertices.size():
				var totals := Vector2.ZERO
				var dominant := &""
				var greatest := 0.0
				for influence in width:
					var offset := vertex * width + influence
					if weights[offset] <= 0.0:
						continue
					var bind := bones[offset]
					var name := mesh.skin.get_bind_name(bind)
					var bone := skeleton.find_bone(name) if name != &"" else mesh.skin.get_bind_bone(bind)
					if bone < 0:
						continue
					if weights[offset] > greatest:
						greatest = weights[offset]
						dominant = skeleton.get_bone_name(bone)
					while bone >= 0:
						if bone == wrists[0]:
							totals.x += weights[offset]
							break
						if bone == wrists[1]:
							totals.y += weights[offset]
							break
						bone = skeleton.get_bone_parent(bone)
				for side in 2:
					if totals[side] > 0.65:
						result.append({"side": side, "point": transform * vertices[vertex], "bone": String(dominant), "mesh": String(mesh.name), "surface": surface, "vertex": vertex})
	return result


func _matches_g17_baseline_left_vertex(vertex: Dictionary, local: Vector3, clip: String, phase: float) -> bool:
	if vertex.get("side", -1) != 1 or vertex.get("mesh", "") != "BlackArmsMesh" or vertex.get("surface", -1) != 0 or vertex.get("bone", "") != "L_thumb3_07":
		return false
	if clip != "reload" or phase < 0.74 or phase > 0.80 or not G17_RELOAD_LEFT_BASELINE.has(vertex.get("vertex", -1)):
		return false
	var baseline: Vector3 = G17_RELOAD_LEFT_BASELINE[vertex.vertex]
	return local.distance_to(baseline) <= 0.0005


func _check_g17_baseline_guard() -> void:
	if _baseline_guard_checked:
		return
	_baseline_guard_checked = true
	var vertex := {"side": 1, "mesh": "BlackArmsMesh", "surface": 0, "bone": "L_thumb3_07", "vertex": 4917}
	var baseline: Vector3 = G17_RELOAD_LEFT_BASELINE[4917]
	_assert(_matches_g17_baseline_left_vertex(vertex, baseline, "reload", 0.7604255), "G17 compatibility guard recognizes its recorded native baseline point")
	for field: String in ["side", "mesh", "surface", "bone", "vertex"]:
		var changed := vertex.duplicate()
		changed[field] = {"side": 0, "mesh": "OtherMesh", "surface": 1, "bone": "L_wrist_04", "vertex": 4918}[field]
		_assert(not _matches_g17_baseline_left_vertex(changed, baseline, "reload", 0.7604255), "G17 compatibility guard rejects a different actual %s" % field)
	_assert(not _matches_g17_baseline_left_vertex(vertex, baseline, "reload_empty", 0.7604255), "G17 compatibility guard rejects the empty-reload clip")
	_assert(not _matches_g17_baseline_left_vertex(vertex, baseline, "reload", 0.73) and not _matches_g17_baseline_left_vertex(vertex, baseline, "reload", 0.81), "G17 compatibility guard rejects phases outside the recorded reload interval")
	_assert(not _matches_g17_baseline_left_vertex(vertex, baseline + Vector3(0.0006, 0, 0), "reload", 0.7604255), "G17 compatibility guard rejects a baseline point displaced beyond 0.5mm")


func _cache_slide_triangles(mesh: Mesh) -> void:
	_slide_collision_mesh = mesh
	_slide_collision_bounds = mesh.get_aabb()
	_slide_triangle_count = 0
	var projected: Array = [[], [], []]
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for offset in range(0, count, 3):
			var a := vertices[indices[offset] if not indices.is_empty() else offset]
			var b := vertices[indices[offset + 1] if not indices.is_empty() else offset + 1]
			var c := vertices[indices[offset + 2] if not indices.is_empty() else offset + 2]
			_slide_triangle_count += 1
			for axis in 3:
				var u := (axis + 1) % 3
				var v := (axis + 2) % 3
				var ab_u := b[u] - a[u]
				var ab_v := b[v] - a[v]
				var ac_u := c[u] - a[u]
				var ac_v := c[v] - a[v]
				var area := ab_u * ac_v - ab_v * ac_u
				if absf(area) < 1.0e-14:
					continue
				var row: Array = [minf(a[u], minf(b[u], c[u])), maxf(a[u], maxf(b[u], c[u])), minf(a[v], minf(b[v], c[v])), maxf(a[v], maxf(b[v], c[v])), a[axis], a[u], a[v], ab_u, ab_v, ac_u, ac_v, 1.0 / area, b[axis] - a[axis], c[axis] - a[axis]]
				var cached: Array = projected[axis]
				cached.append_array(row)
	_slide_ray_cache = [PackedFloat64Array(projected[0]), PackedFloat64Array(projected[1]), PackedFloat64Array(projected[2])]


func _slide_contains(point: Vector3) -> bool:
	if not _slide_collision_bounds.has_point(point):
		return false
	# +X is the primary parity; confirm real solid membership on the other two axes.
	for axis in 3:
		var cached: PackedFloat64Array = _slide_ray_cache[axis]
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		var hits: Array[float] = []
		for offset in range(0, cached.size(), 14):
			# Projected Y/Z (or Z/X, X/Y) bounds only accelerate the actual triangle test.
			if point[u] < cached[offset] - 1.0e-8 or point[u] > cached[offset + 1] + 1.0e-8 \
				or point[v] < cached[offset + 2] - 1.0e-8 or point[v] > cached[offset + 3] + 1.0e-8:
				continue
			var delta_u := point[u] - cached[offset + 5]
			var delta_v := point[v] - cached[offset + 6]
			var w_b := (delta_u * cached[offset + 10] - delta_v * cached[offset + 9]) * cached[offset + 11]
			var w_c := (cached[offset + 7] * delta_v - cached[offset + 8] * delta_u) * cached[offset + 11]
			if w_b < -1.0e-8 or w_c < -1.0e-8 or w_b + w_c > 1.0 + 1.0e-8:
				continue
			var hit := cached[offset + 4] + w_b * cached[offset + 12] + w_c * cached[offset + 13]
			if hit > point[axis] + 1.0e-7:
				hits.append(hit)
		hits.sort()
		var unique := 0
		var previous := -INF
		for hit in hits:
			if hit - previous > 1.0e-7:
				unique += 1
				previous = hit
		if unique % 2 == 0:
			return false
	return true


func _g17_backstrap_section(frame: MeshInstance3D, gun: Node3D, height: float, rear_start: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var transform := gun.global_transform.affine_inverse() * frame.global_transform
	for surface in frame.mesh.get_surface_count():
		var arrays := frame.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for offset in range(0, count, 3):
			var triangle: Array[Vector3] = []
			for corner in 3:
				triangle.append(transform * vertices[indices[offset + corner] if not indices.is_empty() else offset + corner])
			for edge in 3:
				var a := triangle[edge]
				var b := triangle[(edge + 1) % 3]
				if (a.y - height) * (b.y - height) > 0.0 or is_zero_approx(b.y - a.y):
					continue
				var point := a.lerp(b, (height - a.y) / (b.y - a.y))
				if point.z >= rear_start:
					result.append(point)
	return result


func _g17_high_grip_matches(palm: Vector3, grip: AABB) -> bool:
	# A 50mm palm-height allowance below the actual grip top still rejects a heel-only grip.
	return palm.y >= grip.end.y - 0.05 and palm.y <= grip.end.y + 0.015 \
		and absf(palm.x - grip.get_center().x) < 0.04 \
		and palm.z >= grip.position.z - 0.025 and palm.z <= grip.end.z + 0.025


func _check_mpx_feedback(gun: Node3D, camera: Camera3D, center: Vector2) -> void:
	var glass := _glass_bounds(gun)
	_assert(glass.size.length() > 0.001, "MPX uses the actual source optical glass")
	if glass.size.length() <= 0.001:
		return
	_assert(camera.unproject_position(glass.get_center()).distance_to(center) < 2.0, "MPX real lens center remains aligned after optic correction")
	var inverse := gun.global_transform.affine_inverse()
	var lens: Vector3 = inverse * glass.get_center()
	for part: Array in [["HolographicSightPart26", "battery"], ["HolographicSightPart18", "night_vision_button"], ["HolographicSightPart19", "brightness_button"]]:
		var mesh := gun.find_child(String(part[0]), true, false) as MeshInstance3D
		_assert(mesh != null and mesh.mesh != null, "MPX direction uses actual %s mesh" % part[1])
		if mesh == null or mesh.mesh == null:
			continue
		var actual: Vector3 = inverse * mesh.global_transform * mesh.mesh.get_aabb().get_center()
		if part[1] == "battery":
			_assert(actual.z < lens.z and actual.x > lens.x, "MPX actual battery is forward toward the muzzle and on the shooter's right")
		else:
			_assert(actual.z > lens.z and actual.x < lens.x, "MPX actual %s is behind the lens on the shooter's left" % part[1])
		print("MPX_OPTIC_DIRECTION ", part[1], " actual=", actual, " actual_lens=", lens)
	_assert(_player._ads_reticle.mode == &"none", "MPX uses its real red optic texture without the cyan HUD reticle")
	var crosshair := gun.find_child("HolographicSightPart1", true, false) as MeshInstance3D
	_assert(crosshair != null and crosshair.mesh != null and crosshair.is_visible_in_tree(), "MPX source crosshair plane is visible")
	if crosshair == null or crosshair.mesh == null:
		return
	var material := crosshair.get_active_material(0) as BaseMaterial3D
	_assert(material != null and material.resource_name == "crosshair" and material.albedo_texture != null, "MPX reticle uses the actual source crosshair material and texture")
	if material == null or material.albedo_texture == null:
		return
	var red := _red_texture_center(material.albedo_texture.get_image())
	_assert(int(red.get("pixels", 0)) > 0, "MPX actual source texture contains nontransparent red reticle pixels")
	if int(red.get("pixels", 0)) == 0:
		return
	var point: Variant = _crosshair_uv_point(crosshair, red.uv as Vector2)
	_assert(point != null, "MPX actual red texture centroid maps onto its real mesh UV triangles")
	if point == null:
		return
	var projected := camera.unproject_position(point as Vector3)
	var error := projected.distance_to(center)
	_assert(error < 2.0, "MPX actual red texture center projects within two pixels of the sight line")
	var blocked := _opaque_blocker(_player._weapon_mount, camera.global_position, ((point as Vector3) - camera.global_position).normalized())
	_assert(blocked.is_empty(), "MPX source red reticle is visible through the actual opaque optic opening")
	var image := root.get_texture().get_image()
	var pixels := _reticle_screen_pixels(image, Vector2i(projected), 36)
	_assert(pixels.x > 0, "MPX native production image actually displays red reticle pixels")
	_assert(pixels.y == 0, "MPX native production image has no overlapping cyan ADS ring")
	print("MPX_SOURCE_RETICLE uv=", red.uv, " source_red_pixels=", red.pixels, " projected=", projected, " center_error=", error, " native_red_pixels=", pixels.x, " native_cyan_pixels=", pixels.y)
	_report.append({"weapon": "mpx", "source_red_pixels": red.pixels, "center_error": error, "native_red_pixels": pixels.x, "native_cyan_pixels": pixels.y})


func _red_texture_center(image: Image) -> Dictionary:
	if image == null or image.is_empty():
		return {}
	if image.is_compressed() and image.decompress() != OK:
		return {}
	var sum := Vector2.ZERO
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a > 0.25 and color.r > 0.12 and color.r > color.g * 1.4 and color.r > color.b * 1.4:
				sum += Vector2(x + 0.5, y + 0.5)
				count += 1
	if count == 0:
		return {}
	return {"pixels": count, "uv": sum / float(count) / Vector2(image.get_width(), image.get_height())}


func _crosshair_uv_point(mesh: MeshInstance3D, uv: Vector2) -> Variant:
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for offset in range(0, count, 3):
			var a := indices[offset] if not indices.is_empty() else offset
			var b := indices[offset + 1] if not indices.is_empty() else offset + 1
			var c := indices[offset + 2] if not indices.is_empty() else offset + 2
			var first := uvs[b] - uvs[a]
			var second := uvs[c] - uvs[a]
			var delta := uv - uvs[a]
			var area := first.cross(second)
			if absf(area) < 1.0e-12:
				continue
			var w_b := delta.cross(second) / area
			var w_c := first.cross(delta) / area
			if w_b >= -0.0001 and w_c >= -0.0001 and w_b + w_c <= 1.0001:
				return mesh.global_transform * (vertices[a] * (1.0 - w_b - w_c) + vertices[b] * w_b + vertices[c] * w_c)
	return null


func _reticle_screen_pixels(image: Image, center: Vector2i, radius: int) -> Vector2i:
	var result := Vector2i.ZERO
	for y in range(maxi(0, center.y - radius), mini(image.get_height(), center.y + radius + 1)):
		for x in range(maxi(0, center.x - radius), mini(image.get_width(), center.x + radius + 1)):
			var color := image.get_pixel(x, y)
			if color.r > 0.12 and color.r > color.g * 1.4 and color.r > color.b * 1.4:
				result.x += 1
			if color.g > 0.5 and color.b > 0.5 and color.r < color.g * 0.8:
				result.y += 1
	return result
