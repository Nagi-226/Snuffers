extends SceneTree

var _scene: Node3D
var _player: CharacterBody3D


func _init() -> void:
	call_deferred("_run")


func _shot(label: String) -> void:
	for frame in 2:
		await process_frame
	root.get_texture().get_image().save_png("tmp_shots/em57s2_ads/%s.png" % label)
	print("EM57S2_SHOT ", label, " weight=", _player._ads_weight, " near=", _player._camera.near)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	_scene = (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	_player = _scene.get_node("Player") as CharacterBody3D
	var day_night = _scene.get_node("GreyboxArena/DayNightController")
	day_night.set_mode(day_night.Mode.DAY)
	_player._switch_weapon(&"em57s2")
	_player.global_position = Vector3(44, 0.1, 19)
	_player.rotation.y = PI
	_player._camera.rotation = Vector3.ZERO
	await create_timer(0.4).timeout
	if "--interactive" in OS.get_cmdline_user_args():
		print("EM57S2_PREVIEW_READY: right mouse aims; dev1 weapons range")
		return
	DirAccess.make_dir_recursive_absolute("tmp_shots/em57s2_ads")
	await _shot("hip")
	var smg = _player.get_node("Camera3D/WeaponMount/Em57s2")
	_player.set_process(false)
	smg.set_process(false)
	_player._set_aiming(true)
	for phase in 3:
		_player._process(0.04)
		smg._process(0.04)
		await _shot("aim_transition_%d" % phase)
	_player.set_process(true)
	smg.set_process(true)
	await create_timer(0.2).timeout
	await _shot("ads")
	root.get_node("GameState").em57s2_mag = 100
	smg._start_reload()
	await _shot("reload_start")
	for phase in [0.5, 1.0, 1.5]:
		await create_timer(0.5).timeout
		await _shot("reload_%dms" % int(phase * 1000))
	await create_timer(0.6).timeout
	_player._set_aiming(false)
	await create_timer(0.2).timeout
	await _shot("hip_after")
	_scene.queue_free()
	await process_frame
	quit()
