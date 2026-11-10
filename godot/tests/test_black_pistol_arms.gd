extends SceneTree

const ASSET := "res://addons/community_weapons/black_pistol_arms.glb"
const CLIPS := ["fire", "reload", "reload_empty", "hide", "ready", "idle"]

var _failures := 0
var _assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void:
		push_error("black pistol arms test timed out")
		quit(1))
	_assert(FileAccess.file_exists(ASSET), "native black pistol arms asset exists")
	if not FileAccess.file_exists(ASSET):
		_finish()
		return
	var packed := load(ASSET) as PackedScene
	_assert(packed != null, "native black pistol arms imports into Godot")
	if packed == null:
		_finish()
		return
	var model := packed.instantiate() as Node3D
	root.add_child(model)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	_assert(skeletons.size() == 1 and players.size() == 1, "native asset keeps one skeleton and animation player")
	if skeletons.size() != 1 or players.size() != 1:
		model.queue_free()
		_finish()
		return
	var skeleton := skeletons[0] as Skeleton3D
	var animation := players[0] as AnimationPlayer
	animation.set_process(false)
	animation.set_physics_process(false)
	_assert(skeleton.get_bone_count() == 60, "native source keeps its sixty-bone rig")
	var skinned := 0
	var dark_cloth := true
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.mesh != null and instance.skin != null and instance.skin.get_bind_count() > 0:
			skinned += 1
			for surface in instance.mesh.get_surface_count():
				var material := instance.get_active_material(surface) as StandardMaterial3D
				dark_cloth = dark_cloth and material != null and material.metallic <= 0.01 and material.albedo_color.r <= 0.5 and material.albedo_color.g <= 0.5 and material.albedo_color.b <= 0.5
	_assert(skinned > 0, "native black arms retain their real skin binding")
	_assert(dark_cloth, "native black gloves and cloth use dark nonmetal materials")
	for name in ["WeaponMotion", "MagazineMotion", "SlideMotion"]:
		_assert(model.find_child(name, true, false) is Node3D, "source action node is available: " + name)
	for clip in CLIPS:
		_assert(animation.has_animation(clip), "native action clip exists: " + clip)
		if not animation.has_animation(clip):
			continue
		var action := animation.get_animation(clip)
		_assert(action.length > 0.0 and action.get_track_count() > 0, "native action contains real tracks: " + clip)
		animation.play(clip)
		animation.advance(0.0)
		var first: Array[Transform3D] = []
		for bone in skeleton.get_bone_count():
			first.append(skeleton.get_bone_global_pose(bone))
		var moved := false
		for progress in [0.25, 0.5, 0.75]:
			animation.seek(action.length * progress, true)
			var valid := true
			for bone in skeleton.get_bone_count():
				var pose := skeleton.get_bone_global_pose(bone)
				moved = moved or not pose.is_equal_approx(first[bone])
				valid = valid and pose.is_finite() and skeleton.get_bone_pose_scale(bone).is_equal_approx(Vector3.ONE) and skeleton.get_bone_rest(bone).basis.get_scale().is_equal_approx(Vector3.ONE)
			_assert(valid, "%s phase %.2f samples finite native bone poses without bone scaling" % [clip, progress])
		if clip in ["fire", "reload", "reload_empty"]:
			_assert(moved, "native %s animates the arm bones rather than providing an empty placeholder" % clip)
	model.queue_free()
	await process_frame
	_finish()


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _finish() -> void:
	print("BLACK_PISTOL_ARMS assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)
