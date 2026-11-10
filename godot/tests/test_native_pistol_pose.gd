extends SceneTree

var _failures := 0
var _assertions := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_assert(FileAccess.file_exists("res://scripts/player/native_pistol_arms.gd"), "native pistol adapter exists")
	if not FileAccess.file_exists("res://scripts/player/native_pistol_arms.gd"):
		_finish()
		return
	var adapter = load("res://scripts/player/native_pistol_arms.gd").new()
	var arms := (load("res://addons/community_weapons/black_pistol_arms.glb") as PackedScene).instantiate() as Node3D
	var gun := (load("res://addons/community_weapons/g17_gen5_olight.glb") as PackedScene).instantiate() as Node3D
	var mount := Node3D.new()
	root.add_child(mount)
	mount.add_child(arms)
	mount.add_child(gun)
	gun.position = Vector3(2.0, 1.5, -3.0)
	gun.rotation.y = 0.7
	var magazine := gun.find_child("Magazine", true, false) as Node3D
	var chamber_round := gun.find_child("Gen5ChamberRound", true, false) as Node3D
	_assert(chamber_round != null and gun.find_child("Frame", true, false).is_ancestor_of(chamber_round), "Gen5 chamber cartridge belongs to frame and does not leave with the magazine")
	var config = root.get_node("GameConfig")
	var profiles: Dictionary = config.get_script().get_script_constant_map().get("BLACK_PISTOL_PROFILES", {})
	_assert(profiles.has(&"gen5"), "Gen5 native pose uses its approved shared profile")
	if not profiles.has(&"gen5"):
		mount.queue_free()
		_finish()
		return
	_assert(adapter.configure(arms, gun, magazine, profiles[&"gen5"]), "native Gen5 adapter configures real arms and parts")
	var profile: Dictionary = profiles[&"gen5"]
	_assert(profile.has("magazine_grip"), "Gen5 has an actual-magazine wrist contact point")
	var expected_grip: Vector3 = profile.get("magazine_grip", Vector3(-0.025, -0.065, 0.06))
	var slide := gun.find_child("Slide", true, false) as Node3D
	var slide_home := slide.transform
	var slide_moved := false
	adapter.play_fire()
	for phase in 8:
		adapter.update(adapter.animation.get_animation("fire").length / 8.0)
		slide_moved = slide_moved or not slide.transform.is_equal_approx(slide_home)
	_assert(slide_moved, "Gen5 fire drives its real independent slide using the native SlideMotion track")
	adapter.reset()
	_assert(slide.transform.is_equal_approx(slide_home), "native reset restores the independent slide")
	var skeleton: Skeleton3D = adapter.skeleton
	var wrist := skeleton.find_bone("R_wrist_028")
	var left := skeleton.find_bone("L_wrist_04")
	var upper := skeleton.find_bone("L_arm_02")
	var fore := skeleton.find_bone("L_elbow_03")
	var rests: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		rests.append(skeleton.get_bone_rest(bone))
	var upper_length := skeleton.get_bone_global_pose(upper).origin.distance_to(skeleton.get_bone_global_pose(fore).origin)
	var fore_length := skeleton.get_bone_global_pose(fore).origin.distance_to(skeleton.get_bone_global_pose(left).origin)
	var right_upper := skeleton.find_bone("R_arm_026")
	var right_fore := skeleton.find_bone("R_elbow_027")
	var right_upper_length := skeleton.get_bone_global_pose(right_upper).origin.distance_to(skeleton.get_bone_global_pose(right_fore).origin)
	var right_fore_length := skeleton.get_bone_global_pose(right_fore).origin.distance_to(skeleton.get_bone_global_pose(wrist).origin)
	var wrist_home: Transform3D = gun.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(wrist)
	var gun_home := gun.transform
	var magazine_home := magazine.transform
	adapter.play_reload(2.0)
	var moved := false
	for step in 61:
		adapter.update(0.0 if step == 0 else 2.0 / 60.0)
		var current: Transform3D = gun.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(wrist)
		_assert(current.origin.distance_to(wrist_home.origin) < 0.003, "native reload keeps right wrist at the actual grip %.3f" % (step / 60.0))
		_assert(absf(current.basis.orthonormalized().get_rotation_quaternion().dot(wrist_home.basis.orthonormalized().get_rotation_quaternion())) > 0.9999, "native reload preserves wrist rotation on the grip")
		var right_upper_current := skeleton.get_bone_global_pose(right_upper).origin.distance_to(skeleton.get_bone_global_pose(right_fore).origin)
		var right_fore_current := skeleton.get_bone_global_pose(right_fore).origin.distance_to(skeleton.get_bone_global_pose(wrist).origin)
		_assert(absf(right_upper_current - right_upper_length) < 0.001 and absf(right_fore_current - right_fore_length) < 0.001, "native reload preserves both right-arm segment lengths %.3f: %.6f/%.6f vs %.6f/%.6f" % [step / 60.0, right_upper_current, right_fore_current, right_upper_length, right_fore_length])
		_assert(absf(skeleton.get_bone_global_pose(upper).origin.distance_to(skeleton.get_bone_global_pose(fore).origin) - upper_length) < 0.001, "native reload preserves upper-arm length")
		_assert(absf(skeleton.get_bone_global_pose(fore).origin.distance_to(skeleton.get_bone_global_pose(left).origin) - fore_length) < 0.001, "native reload preserves forearm length")
		var progress := float(step) / 60.0
		if progress >= float(profile.reload_contact_phase) and progress <= float(profile.reload_seat_phase):
			var actual: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(left).origin
			_assert(actual.distance_to(magazine.global_transform * expected_grip) < 0.003, "native left wrist follows the actual magazine grab point %.3f" % progress)
		var valid := gun.global_transform.is_finite() and magazine.global_transform.is_finite()
		for bone in skeleton.get_bone_count():
			valid = valid and rests[bone].is_equal_approx(skeleton.get_bone_rest(bone)) and skeleton.get_bone_pose_scale(bone).is_equal_approx(Vector3.ONE) and skeleton.get_bone_global_pose(bone).is_finite()
			if not skeleton.get_bone_pose_scale(bone).is_equal_approx(Vector3.ONE):
				print("SCALE_DIAGNOSTIC ", progress, " ", skeleton.get_bone_name(bone), " ", skeleton.get_bone_pose_scale(bone))
		_assert(valid, "native pose retains all bone rests and unit scales %.3f" % progress)
		moved = moved or not magazine.transform.is_equal_approx(magazine_home)
		var mesh: MeshInstance3D = arms.find_child("BlackArmsMesh", true, false)
		var bounds: AABB = adapter.get_skin_bounds(mesh)
		_assert(bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.length() > 1.0, "actual weighted skin evaluates finite nonempty posed bounds")
		if step % 15 == 0:
			_assert_weighted_vertices(mesh, skeleton)
	_assert(moved, "Gen5 native reload drives its real magazine")
	adapter.reset()
	_assert(gun.transform.is_equal_approx(gun_home) and magazine.transform.is_equal_approx(magazine_home) and magazine.visible, "native reload reset restores gun and magazine")
	mount.queue_free()
	await process_frame
	_finish()

func _assert_weighted_vertices(mesh: MeshInstance3D, skeleton: Skeleton3D) -> void:
	var skin := mesh.skin
	var valid := true
	var posed := AABB()
	var has_vertex := false
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var width: int = indices.size() / vertices.size()
		for index in vertices.size():
			var position := Vector3.ZERO
			var total := 0.0
			for influence in width:
				var offset := index * width + influence
				if weights[offset] <= 0.0:
					continue
				var bind := indices[offset]
				var bone := skeleton.find_bone(skin.get_bind_name(bind)) if skin.get_bind_name(bind) != &"" else skin.get_bind_bone(bind)
				position += (skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind) * vertices[index]) * weights[offset]
				total += weights[offset]
			position = skeleton.global_transform * position
			valid = valid and position.is_finite() and absf(total - 1.0) < 0.005
			posed = posed.expand(position) if has_vertex else AABB(position, Vector3.ZERO)
			has_vertex = true
	_assert(valid and has_vertex and posed.size.length() > 0.05 and posed.size.length() < 1.8, "all real skin vertices have finite normalized weighted positions without mesh spikes")

func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)

func _finish() -> void:
	print("NATIVE_PISTOL_POSE assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)
