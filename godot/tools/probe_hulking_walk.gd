extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var hulking := (load("res://scenes/enemies/hulking_host.tscn") as PackedScene).instantiate() as CharacterBody3D
	world.add_child(hulking)
	hulking.set_physics_process(false)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 1.6, 3.8)
	camera.look_at(Vector3(0, 1.0, 0))
	camera.current = true
	var light := OmniLight3D.new()
	light.position = Vector3(1, 4, 3)
	light.light_energy = 3.0
	light.omni_range = 12
	world.add_child(light)
	DirAccess.make_dir_recursive_absolute("tmp_shots/hulking_walk")
	hulking._play(&"walk", true)
	for step in 6:
		await create_timer(0.28).timeout
		root.get_texture().get_image().save_png("tmp_shots/hulking_walk/pose_%d.png" % step)
	quit()
