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
	player._cycle_nano_mode()
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
	player._cycle_nano_mode()
	await create_timer(0.3).timeout
	root.get_texture().get_image().save_png("tmp_shots/nano_modes/stealth.png")
	print("NANO_STEALTH_GRAPHICS weapon_visible=", player.get_node("Camera3D/WeaponMount").visible)
	quit()
