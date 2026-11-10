extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.get_node("GameState").reset()
	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	await process_frame
	var weapons := player.get_node("Camera3D/WeaponMount").get_children()
	for weapon in weapons:
		weapon.set_physics_process(false)
		weapon.set_process(false)
	for frame in 5:
		for weapon in weapons:
			weapon._process(1.0 / 60.0)
	var start := Time.get_ticks_usec()
	for frame in 60:
		for weapon in weapons:
			weapon._process(1.0 / 60.0)
	var elapsed := Time.get_ticks_usec() - start
	print("NATIVE_VISUAL_CPU weapons=", weapons.size(), " mean_ms_per_all_weapon_frame=", float(elapsed) / 60000.0)
	player.queue_free()
	await process_frame
	await process_frame
	quit()
