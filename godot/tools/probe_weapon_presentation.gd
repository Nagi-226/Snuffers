extends SceneTree

var _player: CharacterBody3D


func _init() -> void:
	call_deferred("_run")


func _shot(label: String) -> void:
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("tmp_shots/weapon_presentation/%s.png" % label)
	print("PRESENTATION_SHOT ", label)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var scene := (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	_player = scene.get_node("Player") as CharacterBody3D
	var day_night = scene.get_node("GreyboxArena/DayNightController")
	day_night.set_mode(day_night.Mode.DAY)
	_player._switch_weapon(&"smg")
	_player.global_position = Vector3(44, 0.1, 19)
	_player.rotation.y = PI
	_player._camera.rotation = Vector3.ZERO
	await create_timer(0.5).timeout
	if "--interactive" in OS.get_cmdline_user_args():
		print("WEAPON_PRESENTATION_PREVIEW_READY: EM-57S1 selected; 4 selects EM-12G-1; right mouse aims")
		return
	DirAccess.make_dir_recursive_absolute("tmp_shots/weapon_presentation")
	await _shot("smg_hip")
	_player._camera.rotation.x = deg_to_rad(-20.0)
	await _shot("smg_hip_down")
	_player._camera.rotation.x = 0.0
	_player._set_aiming(true)
	await create_timer(0.3).timeout
	await _shot("smg_ads")
	_player._set_aiming(false)
	await create_timer(0.3).timeout
	var smg = _player.get_node("Camera3D/WeaponMount/SMG")
	root.get_node("GameState").smg_mag = 50
	smg._start_reload()
	await _shot("smg_reload_start")
	await create_timer(0.6).timeout
	await _shot("smg_reload_600ms")
	await create_timer(0.6).timeout
	await _shot("smg_reload_1200ms")
	await create_timer(0.7).timeout
	await _shot("smg_after_reload")
	_player._switch_weapon(&"shotgun")
	await create_timer(0.3).timeout
	await _shot("shotgun_hip")
	_player._set_aiming(true)
	await create_timer(0.3).timeout
	await _shot("shotgun_ads")
	root.size = Vector2i(2560, 1440)
	await _shot("shotgun_ads_1440")
	root.size = Vector2i(1600, 900)
	_player._set_aiming(false)
	for category: Dictionary in root.get_node("GameConfig").WEAPON_CATEGORIES:
		for id: StringName in category.weapons:
			_player._switch_weapon(id)
			await create_timer(0.2).timeout
			await _shot("hud_" + id)
	scene.queue_free()
	await process_frame
	quit()
