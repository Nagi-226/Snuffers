extends SceneTree

var _out_dir: String = "user://"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.08, 0.10, 0.13)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.85, 1.0)
	environment.ambient_light_energy = 0.8
	var world := WorldEnvironment.new()
	world.environment = environment
	root.add_child(world)
	var light := DirectionalLight3D.new()
	light.light_energy = 2.0
	light.rotation_degrees = Vector3(-55, -25, 0)
	root.add_child(light)
	var camera := Camera3D.new()
	camera.fov = 55.0
	root.add_child(camera)
	camera.current = true
	camera.position = Vector3(0.3, 0.12, 0.42)
	camera.look_at(Vector3(0.0, -0.06, 0.04))
	await _capture("rifle", "res://scenes/weapons/rifle.tscn", "ViewModel/EM68A", 0.5, 2.0)
	await _capture("pistol", "res://scenes/weapons/pistol.tscn", "ViewModel/EM57P", 0.8, 1.6)
	quit()


func _capture(weapon_id: String, scene_path: String, weapon_path: NodePath, seconds: float, duration: float) -> void:
	var game_state = root.get_node("GameState")
	game_state.reset()
	game_state.current_weapon = weapon_id as StringName
	game_state.set(weapon_id + "_mag", 0)
	var weapon := (load(scene_path) as PackedScene).instantiate()
	root.add_child(weapon)
	weapon.get_node(weapon_path).visible = false
	weapon._start_reload()
	await create_timer(seconds).timeout
	var image := root.get_texture().get_image()
	image.save_png(_out_dir.path_join(weapon_id + "_arms_only.png"))
	await create_timer(maxf(0.0, duration - seconds + 0.1)).timeout
	weapon.queue_free()
	await process_frame
