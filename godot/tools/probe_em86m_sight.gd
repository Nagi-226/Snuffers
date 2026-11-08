extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var scene := (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	var day_night = scene.get_node("GreyboxArena/DayNightController")
	day_night.set_mode(day_night.Mode.DAY)
	player._switch_weapon(&"em86m")
	player.global_position = Vector3(44, 0.1, 19)
	player.rotation.y = PI
	player._camera.rotation = Vector3.ZERO
	await create_timer(0.4).timeout
	if "--interactive" in OS.get_cmdline_user_args():
		print("EM86M_PREVIEW_READY: right mouse aims; dev1 weapons range")
		return
	DirAccess.make_dir_recursive_absolute("tmp_shots/em86m_sight")
	var sizes: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(2560, 1440)]
	for view_size in sizes:
		root.size = view_size
		for aiming in [false, true]:
			player._set_aiming(aiming)
			await create_timer(0.4).timeout
			await RenderingServer.frame_post_draw
			var label := "%dx%d_%s" % [view_size.x, view_size.y, "ads" if aiming else "hip"]
			root.get_texture().get_image().save_png("tmp_shots/em86m_sight/%s.png" % label)
			print("EM86M_SHOT ", label)
	scene.queue_free()
	await process_frame
	quit()
