extends SceneTree

var _scene: Node3D
var _camera: Camera3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = (load("res://scenes/levels/district_b.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	for i in 30:
		await process_frame
	_camera = _scene.get_node("Player/Camera3D") as Camera3D
	DirAccess.make_dir_recursive_absolute("tmp_shots/industrial")
	await _shot(Vector3(-8, 2.2, 70), Vector3(-8, 1.0, 65), "forklift")
	await _shot(Vector3(0, 8, 35), Vector3(0, 13, -45), "gantry_crane")
	await _shot(Vector3(195, 2.2, -38), Vector3(195, 2.5, -55), "factory_exterior")
	await _shot(Vector3(195, 2.2, -50), Vector3(195, 2.0, -75), "factory_interior")
	await _shot(Vector3(250, 80, 160), Vector3(0, 5, -20), "yard_overview")
	await create_timer(2.0).timeout
	print("INDUSTRIAL_FPS ", Performance.get_monitor(Performance.TIME_FPS))
	quit()


func _shot(pos: Vector3, target: Vector3, tag: String) -> void:
	_camera.global_position = pos
	_camera.look_at(target)
	for i in 8:
		await process_frame
	var path := "tmp_shots/industrial/%s.png" % tag
	root.get_texture().get_image().save_png(path)
	print("INDUSTRIAL_SHOT ", path)
