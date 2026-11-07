extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := (load("res://scenes/levels/district_b.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	var player := scene.get_node("Player") as CharacterBody3D
	for i in 30:
		await process_frame
	DirAccess.make_dir_recursive_absolute("tmp_shots/nano_modes")
	root.get_texture().get_image().save_png("tmp_shots/nano_modes/armor.png")
	var hud := scene.get_node("HUD") as CanvasLayer
	for state: StringName in [&"green", &"yellow", &"red"]:
		var color := Color(0.95, 0.25, 0.2) if state == &"red" else (Color(0.95, 0.75, 0.2) if state == &"yellow" else Color(0.35, 0.9, 0.45))
		hud._set_awareness_segments(state, color)
		hud._awareness_label.add_theme_color_override("font_color", color)
		hud._awareness_label.text = {"red": "敌人已发现你", "yellow": "敌人正在警觉", "green": "未察觉"}[state]
		for frame in 3:
			await process_frame
		root.get_texture().get_image().save_png("tmp_shots/nano_modes/awareness_%s.png" % state)
	player._set_nano_mode(&"power")
	var forward := InputEventKey.new()
	forward.physical_keycode = KEY_W
	forward.pressed = true
	Input.parse_input_event(forward)
	var sprint := InputEventKey.new()
	sprint.physical_keycode = KEY_SHIFT
	sprint.pressed = true
	Input.parse_input_event(sprint)
	await create_timer(0.2).timeout
	print("NANO_SPEED_GRAPHICS ", player._current_speed())
	root.get_texture().get_image().save_png("tmp_shots/nano_modes/power.png")
	root.get_node("GameState").current_weapon = &"rifle"
	root.get_node("Events").weapon_switched.emit(&"rifle")
	player._set_nano_mode(&"stealth")
	await create_timer(0.3).timeout
	root.get_texture().get_image().save_png("tmp_shots/nano_modes/stealth.png")
	print("NANO_STEALTH_GRAPHICS weapon_visible=", player.get_node("Camera3D/WeaponMount").visible)
	await create_timer(0.8).timeout
	scene.queue_free()
	await process_frame
	quit()
