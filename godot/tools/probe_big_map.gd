extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := (load("res://scenes/levels/district_b.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i in 30:
		await process_frame
	var player := scene.get_node("Player") as CharacterBody3D
	player._toggle_big_map()
	await create_timer(2.0).timeout
	for i in 8:
		await process_frame
	DirAccess.make_dir_recursive_absolute("tmp_shots")
	var path := "tmp_shots/big_map_live.png"
	root.get_texture().get_image().save_png(path)
	print("BIG_MAP_SHOT ", path, " fps=", Performance.get_monitor(Performance.TIME_FPS))
	quit()
