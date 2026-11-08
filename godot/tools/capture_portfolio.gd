extends SceneTree

var _scene: Node3D
var _player: CharacterBody3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute("tmp_shots/portfolio")
	await _load_scene("res://scenes/levels/weapons_range.tscn")
	var day_night = _scene.get_node("GreyboxArena/DayNightController")
	day_night.set_mode(day_night.Mode.DAY)
	_player.global_position = Vector3(70, 22, 55)
	_player.get_node("Camera3D").look_at(Vector3(0, 15, -35))
	await _shot("03_weapons_range_day")
	_player.global_position = Vector3(80, 12.3, 0)
	_player.get_node("Camera3D").look_at(Vector3(-85, 12.1, -45))
	_player._switch_weapon(&"em127g")
	_player._set_aiming(true)
	await create_timer(0.35).timeout
	_scene.get_node("HUD").get_node("WeaponSelector").visible = false
	await _shot("06_sniper_16x")
	_player._adjust_em86s_zoom(1)
	_player._adjust_em86s_zoom(1)
	await create_timer(0.2).timeout
	_scene.get_node("HUD").get_node("WeaponSelector").visible = false
	await _shot("07_sniper_64x")
	_player._set_aiming(false)
	_scene.queue_free()
	await process_frame

	await _load_scene("res://scenes/levels/street_playable.tscn")
	_player.global_position = Vector3(0, 0.1, 30)
	_player.get_node("Camera3D").rotation = Vector3.ZERO
	await _shot("01_street_level")
	root.get_node("GameState").is_night = true
	_player._toggle_night_vision()
	await create_timer(0.25).timeout
	await _shot("08_night_vision")
	_scene.queue_free()
	await process_frame

	await _load_scene("res://scenes/levels/district_b.tscn")
	_player.global_position = Vector3(45, 0.1, 128)
	_player.get_node("Camera3D").look_at(Vector3(0, 10, 65))
	await _shot("02_district_b_warehouse")
	_player._set_nano_mode(&"armor")
	await create_timer(0.2).timeout
	await _shot("09_armor_mode")
	_player._set_nano_mode(&"stealth")
	await create_timer(0.25).timeout
	await _shot("10_stealth_mode")
	_scene.queue_free()
	await process_frame
	quit()


func _load_scene(path: String) -> void:
	_scene = (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	_player = _scene.get_node("Player") as CharacterBody3D
	for frame in 30:
		await process_frame


func _shot(label: String) -> void:
	for frame in 8:
		await process_frame
	root.get_texture().get_image().save_png("tmp_shots/portfolio/%s.png" % label)
	print("PORTFOLIO_SHOT ", label)
