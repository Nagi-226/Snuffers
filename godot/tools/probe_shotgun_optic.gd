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
	player.global_position = Vector3(-40, 0.2, 65)
	player.rotation = Vector3.ZERO
	var state = root.get_node("GameState")
	state.weapon_unlocked[&"shotgun"] = true
	player._switch_weapon(&"shotgun")
	await create_timer(0.3).timeout
	player._set_aiming(true)
	await create_timer(0.35).timeout
	for i in 8:
		await process_frame
	DirAccess.make_dir_recursive_absolute("tmp_shots")
	var path := "tmp_shots/shotgun_optic_rounded_rect.png"
	var image := root.get_texture().get_image()
	image.save_png(path)
	print("SHOTGUN_OPTIC_SHOT ", path)
	quit()
