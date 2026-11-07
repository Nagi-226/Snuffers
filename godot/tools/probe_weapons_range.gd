extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for frame in 30:
		await process_frame
	DirAccess.make_dir_recursive_absolute("tmp_shots/weapons_range")
	var player := scene.get_node("Player") as CharacterBody3D
	var camera := player.get_node("Camera3D") as Camera3D
	var day_switch = scene.get_node("RangeFacilities/DayNightSwitch")
	player.global_position = day_switch.global_position + Vector3(0, 0.1, -2.0)
	camera.look_at(day_switch.global_position + Vector3(0, 0.75, 0))
	player._update_interact_target()
	await _shot("switch_night")
	player._try_interact()
	await _shot("switch_day")
	player.global_position = Vector3(70, 22, 55)
	camera.look_at(Vector3(0, 15, -35))
	await _shot("overview_day")
	player._try_interact()
	player.global_position = Vector3(105, 65, 95)
	camera.look_at(Vector3(5, 0, 0))
	await _shot("overview")
	player.global_position = Vector3(44, 0.1, 19)
	player.rotation.y = PI
	camera.rotation = Vector3.ZERO
	await _shot("maze")
	player.global_position = Vector3(30, 4.1, -25)
	camera.look_at(Vector3(30, 1.0, -40))
	await _shot("near_overwatch")
	player.global_position = Vector3(80, 12.3, 0)
	camera.look_at(Vector3(-85, 12.0, -45))
	await _shot("sniper")
	print("WEAPONS_RANGE_PROBE targets=", get_nodes_in_group(&"range_target").size(), " enemies=", get_nodes_in_group(&"enemy").size())
	scene.queue_free()
	await process_frame
	quit()


func _shot(label: String) -> void:
	for frame in 8:
		await process_frame
	root.get_texture().get_image().save_png("tmp_shots/weapons_range/%s.png" % label)
	print("WEAPONS_RANGE_SHOT ", label)
