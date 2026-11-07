extends SceneTree

var _scene: Node3D
var _player: CharacterBody3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	_player = _scene.get_node("Player") as CharacterBody3D
	for frame in 30:
		await process_frame
	DirAccess.make_dir_recursive_absolute("tmp_shots/heavy_platforms")
	var day_night = _scene.get_node("GreyboxArena/DayNightController")
	day_night.set_mode(day_night.Mode.DAY)
	var target = _scene.get_node("RangeFacilities/Targets/CloseTarget") as Node3D
	for weapon_id in [&"em127g", &"em12g2"]:
		_player._switch_weapon(weapon_id)
		_player._set_aiming(false)
		_player.global_position = Vector3(44, 0.1, 19)
		_player.rotation.y = PI
		_player.get_node("Camera3D").rotation = Vector3.ZERO
		await create_timer(0.25).timeout
		await _shot(weapon_id + "_hip")
		_player._set_aiming(true)
		await create_timer(0.3).timeout
		_player.get_node("Camera3D").look_at(target.global_position + Vector3(0, 1, 0))
		if weapon_id == &"em127g":
			await _shot("em127g_ads_16x")
			_player._adjust_em86s_zoom(1)
			await create_timer(0.15).timeout
			await _shot("em127g_ads_32x")
			_player._adjust_em86s_zoom(1)
			await create_timer(0.15).timeout
			await _shot("em127g_ads_64x")
		else:
			await _shot("em12g2_ads")
		_player._set_aiming(false)
		await create_timer(0.2).timeout
		print("HEAVY_PROBE ", weapon_id, " complete")
	_scene.queue_free()
	await process_frame
	quit()


func _shot(label: String) -> void:
	for frame in 8:
		await process_frame
	root.get_texture().get_image().save_png("tmp_shots/heavy_platforms/%s.png" % label)
	print("HEAVY_SHOT ", label, " fov=", _player._camera.fov)
