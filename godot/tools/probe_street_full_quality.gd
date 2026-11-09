extends SceneTree

const VIEWS := [
	["north_street", Vector3(0, 1.7, -30), Vector3(0, 2, -75)],
	["north_walls", Vector3(1, 1.7, -51), Vector3(7.5, 2, -53)],
	["cross_west", Vector3(-12, 1.7, 33), Vector3(-34, 2, 33)],
	["cross_east", Vector3(10, 1.7, 33), Vector3(33, 2, 33)],
	["south_street", Vector3(0, 1.7, 42), Vector3(0, 2, 68)],
	["garage_e5", Vector3(3, 1.7, -48), Vector3(9, 1.8, -48)],
	["yard_e5", Vector3(22, 1.7, -51), Vector3(29, 1.4, -46)],
	["court_alley", Vector3(-19, 1.7, -59), Vector3(-24, 1.5, -59)],
]

var _shots := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(70.0).timeout.connect(_timeout)
	if DisplayServer.get_name() == "headless":
		_fail("full-street screenshots need native rendering")
		return
	root.size = Vector2i(1920, 1080)
	var directory := ProjectSettings.globalize_path("res://tmp_shots/street_full")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		_fail("cannot create full-street output directory")
		return
	root.get_node("GameState").reset()
	var scene := (load("res://scenes/levels/street_playable.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for frame in 20:
		await process_frame
	for node in scene.find_children("*", "Node", true, false):
		node.set_process(false)
		node.set_physics_process(false)
		node.set_process_unhandled_input(false)
	scene.get_node("Player/Camera3D/WeaponMount").visible = false
	scene.get_node("HUD").visible = false
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	camera.fov = 75.0
	var driver = scene.get_node("StreetTest/StreetDayNightDriver")
	for mode in [driver.Mode.NIGHT, driver.Mode.DAY]:
		driver.set_mode(mode)
		for view: Array in VIEWS:
			camera.look_at_from_position(view[1], view[2], Vector3.UP)
			for frame in 15:
				await RenderingServer.frame_post_draw
			var capture := root.get_texture().get_image()
			if capture == null or capture.is_empty():
				_fail("full-street capture returned an empty image")
				return
			var label: String = ("night_" if mode == driver.Mode.NIGHT else "day_") + String(view[0])
			if capture.save_png(directory.path_join(label + ".png")) != OK:
				_fail("cannot save " + label)
				return
			_shots += 1
			print("STREET_FULL_SHOT ", label)
	if _shots != VIEWS.size() * 2:
		_fail("full-street capture did not complete every view")
		return
	print("STREET_FULL_PROBE COMPLETED shots=", _shots, " directory=", directory)
	scene.queue_free()
	quit(0)


func _fail(reason: String) -> void:
	push_error("STREET_FULL_PROBE: " + reason)
	quit(1)


func _timeout() -> void:
	_fail("full-street screenshots timed out")
