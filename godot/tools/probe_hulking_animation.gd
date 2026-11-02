extends SceneTree

var _hulking: CharacterBody3D
var _camera: Camera3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_hulking = (load("res://scenes/enemies/hulking_host.tscn") as PackedScene).instantiate() as CharacterBody3D
	world.add_child(_hulking)
	_camera = Camera3D.new()
	world.add_child(_camera)
	_camera.position = Vector3(3.5, 2.1, 4.5)
	_camera.look_at(Vector3(0, 1.1, 0))
	_camera.current = true
	var light := OmniLight3D.new()
	light.position = Vector3(1, 4, 2)
	light.light_energy = 3.0
	light.omni_range = 12
	world.add_child(light)
	DirAccess.make_dir_recursive_absolute("tmp_shots/hulking_animation")
	var skeletons := _hulking.get_node("BodyMesh").find_children("*", "Skeleton3D", true, false)
	var skeleton := skeletons[0] as Skeleton3D
	var bone := skeleton.find_bone("upper_arm_r")
	_hulking.set_physics_process(false)
	_hulking._play(&"attack", true)
	for step in 4:
		await create_timer(0.4).timeout
		print("HULKING_POSE t=", step * 0.4, " clip=", _hulking._animation_player.current_animation, " time=", _hulking._animation_player.current_animation_position, " pose=", skeleton.get_bone_global_pose(bone))
		root.get_texture().get_image().save_png("tmp_shots/hulking_animation/pose_%d.png" % step)
	quit()
