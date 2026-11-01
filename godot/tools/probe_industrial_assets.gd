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
	await _shot(Vector3(202, 2.2, -29), Vector3(202, 2.5, -55), "factory_exterior")
	await _shot(Vector3(202, 2.2, -40), Vector3(202, 2.0, -72), "factory_interior")
	await _shot(Vector3(-120, 2.2, 145), Vector3(-120, 2.0, 119), "maintenance_interior")
	await _shot(Vector3(120, 2.2, 144), Vector3(120, 2.0, 117), "electrical_interior")
	await _shot(Vector3(0, 2.2, -122), Vector3(0, 2.0, -145), "pump_interior")
	await _shot(Vector3(250, 100, 190), Vector3(0, 5, -20), "yard_overview")
	var player := _scene.get_node("Player") as CharacterBody3D
	for route in [[Vector3(202, 0.1, -29), -40.0], [Vector3(-120, 0.1, 145), 136.0], [Vector3(120, 0.1, 144), 132.0], [Vector3(0, 0.1, -122), -134.0]]:
		if not await _verify_walk(player, route[0], route[1]):
			push_error("industrial walk-in failed from %s" % route[0])
			quit(1)
			return
	await create_timer(2.0).timeout
	print("INDUSTRIAL_FPS ", Performance.get_monitor(Performance.TIME_FPS))
	quit()


func _verify_walk(player: CharacterBody3D, start: Vector3, target_z: float) -> bool:
	player.global_position = start
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	var forward := InputEventKey.new()
	forward.physical_keycode = KEY_W
	forward.pressed = true
	Input.parse_input_event(forward)
	for frame in 240:
		await physics_frame
		if player.global_position.z <= target_z:
			break
	var release := InputEventKey.new()
	release.physical_keycode = KEY_W
	release.pressed = false
	Input.parse_input_event(release)
	await physics_frame
	print("INDUSTRIAL_WALK start=", start, " end=", player.global_position)
	return player.global_position.z <= target_z


func _shot(pos: Vector3, target: Vector3, tag: String) -> void:
	_camera.global_position = pos
	_camera.look_at(target)
	for i in 8:
		await process_frame
	var path := "tmp_shots/industrial/%s.png" % tag
	root.get_texture().get_image().save_png(path)
	print("INDUSTRIAL_SHOT ", path)
