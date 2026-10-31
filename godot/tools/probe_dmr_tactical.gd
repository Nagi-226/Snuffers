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
	player.global_position = Vector3(0, 0.2, 65)
	player.rotation = Vector3.ZERO
	for pair in [[Vector3(0, 0, 25), 0.0], [Vector3(5, 0, 18), 0.35]]:
		var enemy := (load("res://scenes/enemies/infantry.tscn") as PackedScene).instantiate() as CharacterBody3D
		scene.add_child(enemy)
		enemy.global_position = pair[0]
		enemy.rotation.y = pair[1]
		enemy.set_physics_process(false)
		enemy.set_process(false)
	var state = root.get_node("GameState")
	state.weapon_unlocked[&"dmr"] = true
	player._switch_weapon(&"dmr")
	await create_timer(0.3).timeout
	player._set_aiming(true)
	await create_timer(0.8).timeout
	for i in 8:
		await process_frame
	DirAccess.make_dir_recursive_absolute("tmp_shots")
	var path := "tmp_shots/dmr_tactical_scope.png"
	var image := root.get_texture().get_image()
	image.save_png(path)
	print("DMR_TACTICAL_SHOT ", path, " range=", player._dmr_tactical._range_text, " targets=", player._dmr_tactical._targets.size(), " fps=", Performance.get_monitor(Performance.TIME_FPS))
	quit()
