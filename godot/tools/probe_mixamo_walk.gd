extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := (load("res://raw_assets/mixamo/walk.fbx") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	for player in scene.find_children("*", "AnimationPlayer", true, false):
		print("MIXAMO_ANIMATIONS ", (player as AnimationPlayer).get_animation_list())
	for skeleton in scene.find_children("*", "Skeleton3D", true, false):
		var skel := skeleton as Skeleton3D
		for bone in skel.get_bone_count():
			print("MIXAMO_BONE ", bone, " ", skel.get_bone_name(bone), " rest=", skel.get_bone_rest(bone))
	var target := (load("res://scenes/enemies/hulking_host.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(target)
	var player := target._animation_player as AnimationPlayer
	var skeleton := target.get_node("BodyMesh").find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	print("TARGET_PATH ", player.get_path_to(skeleton), " clip_length=", player.get_animation(&"walk").length)
	player.play(&"walk")
	for step in 4:
		await create_timer(0.25).timeout
		var bone := skeleton.find_bone("thigh_r")
		print("TARGET_POSE ", step, " time=", player.current_animation_position, " pose=", skeleton.get_bone_global_pose(bone))
	quit()
