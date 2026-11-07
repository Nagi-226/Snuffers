extends SceneTree

const BONE_MAP := {
	"hips": "mixamorig_Hips",
	"spine": "mixamorig_Spine",
	"chest": "mixamorig_Spine2",
	"head": "mixamorig_Head",
	"upper_arm_r": "mixamorig_RightArm",
	"forearm_r": "mixamorig_RightForeArm",
	"hand_r": "mixamorig_RightHand",
	"upper_arm_l": "mixamorig_LeftArm",
	"forearm_l": "mixamorig_LeftForeArm",
	"hand_l": "mixamorig_LeftHand",
	"thigh_r": "mixamorig_RightUpLeg",
	"shin_r": "mixamorig_RightLeg",
	"foot_r": "mixamorig_RightFoot",
	"thigh_l": "mixamorig_LeftUpLeg",
	"shin_l": "mixamorig_LeftLeg",
	"foot_l": "mixamorig_LeftFoot",
}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var source := (load("res://raw_assets/mixamo/run.fbx") as PackedScene).instantiate() as Node3D
	root.add_child(source)
	var source_player := source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var source_skeleton := source.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var target := (load("res://scenes/enemies/hulking_host.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(target)
	var target_skeleton := target.get_node("BodyMesh").find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var source_animation := source_player.get_animation(&"mixamo_com")
	var animation := target._animation_player.get_animation(&"walk").duplicate() as Animation
	animation.length = source_animation.length * 1.25
	var frames := maxi(2, int(ceil(source_animation.length * 30.0)) + 1)
	var height_ratio := target_skeleton.get_bone_rest(target_skeleton.find_bone("hips")).origin.y / source_skeleton.get_bone_rest(source_skeleton.find_bone("mixamorig_Hips")).origin.y
	for frame in frames:
		var time := source_animation.length * float(frame) / float(frames - 1)
		var key_time := time * 1.25
		source_player.play(&"mixamo_com")
		source_player.seek(time, true)
		for bone_name in BONE_MAP:
			var target_bone := target_skeleton.find_bone(bone_name)
			var source_bone := source_skeleton.find_bone(BONE_MAP[bone_name])
			var target_track := _find_bone_track(animation, bone_name)
			if frame == 0 and target_track >= 0:
				while animation.track_get_key_count(target_track) > 0:
					animation.track_remove_key(target_track, 0)
			var source_rest := source_skeleton.get_bone_rest(source_bone)
			var source_pose := source_skeleton.get_bone_pose(source_bone)
			var delta := source_rest.basis.get_rotation_quaternion().inverse() * source_pose.basis.get_rotation_quaternion()
			var target_rotation := target_skeleton.get_bone_rest(target_bone).basis.get_rotation_quaternion() * delta
			if target_track >= 0:
				animation.track_insert_key(target_track, key_time, target_rotation)
			if bone_name == "hips":
				var position_track := _find_or_add_position_track(animation, bone_name)
				var offset := (source_pose.origin - source_rest.origin) * height_ratio
				animation.track_insert_key(position_track, key_time, target_skeleton.get_bone_rest(target_bone).origin + offset)
	var path := "res://assets/models/enemies/hulking_mixamo_big_stride.tres"
	var error := ResourceSaver.save(animation, path)
	print("HULKING_MIXAMO_WALK ", path, " frames=", frames, " length=", animation.length, " error=", error)
	quit(error)


func _find_bone_track(animation: Animation, bone_name: String) -> int:
	for track in animation.get_track_count():
		if animation.track_get_type(track) == Animation.TYPE_ROTATION_3D and String(animation.track_get_path(track)).contains(bone_name):
			return track
	return -1


func _find_or_add_position_track(animation: Animation, bone_name: String) -> int:
	for track in animation.get_track_count():
		if animation.track_get_type(track) == Animation.TYPE_POSITION_3D and String(animation.track_get_path(track)).contains(bone_name):
			return track
	var rotation_path := NodePath("")
	for track in animation.get_track_count():
		if String(animation.track_get_path(track)).contains(bone_name):
			rotation_path = animation.track_get_path(track)
			break
	var index := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(index, rotation_path)
	return index
