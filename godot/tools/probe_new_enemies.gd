extends SceneTree

var _scene: Node3D
var _spore: CharacterBody3D
var _hulking: CharacterBody3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = (load("res://scenes/levels/district_b.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	for i in 30:
		await process_frame
	_spore = (load("res://scenes/enemies/spore_husk.tscn") as PackedScene).instantiate() as CharacterBody3D
	_spore.position = Vector3(-3, 0, 54)
	_scene.add_child(_spore)
	_hulking = _scene.get_node("HulkingHost") as CharacterBody3D
	var player := _scene.get_node("Player") as CharacterBody3D
	player.global_position = Vector3(0, 0.2, 65)
	player.rotation = Vector3.ZERO
	DirAccess.make_dir_recursive_absolute("tmp_shots/new_enemies")
	await create_timer(1.4).timeout
	await _shot("spore_leap")
	print("SPORE_STATE ", _spore.get_state_name(), " pos=", _spore.global_position)
	_hulking.global_position = Vector3(1, 0, 55)
	await create_timer(3.5).timeout
	await _shot("hulking_approach")
	print("HULKING_STATE ", _hulking.current_state, " pos=", _hulking.global_position)
	var camera := _scene.get_node("Player/Camera3D") as Camera3D
	camera.global_position = Vector3(25, 10, 65)
	camera.look_at(Vector3(0, 2, 10))
	await _shot("warehouse_rooms")
	print("NEW_ENEMIES_FPS ", Performance.get_monitor(Performance.TIME_FPS))
	quit()


func _shot(tag: String) -> void:
	for i in 6:
		await process_frame
	var path := "tmp_shots/new_enemies/%s.png" % tag
	root.get_texture().get_image().save_png(path)
	print("NEW_ENEMY_SHOT ", path)
