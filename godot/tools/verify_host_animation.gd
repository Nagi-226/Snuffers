extends SceneTree

var _out_dir := "user://host_animation"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--out")
	if index >= 0 and index + 1 < args.size():
		_out_dir = args[index + 1]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var scene := (load("res://scenes/levels/street_playable.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 12:
		await process_frame
	var host: CharacterBody3D = null
	for node in get_nodes_in_group(&"enemy"):
		if node.get_script() == load("res://scripts/enemies/infantry.gd"):
			host = node as CharacterBody3D
			break
	assert(host != null, "no infantry in street scene")
	for node in get_nodes_in_group(&"enemy"):
		node.set_physics_process(false)
		if node != host:
			node.visible = false
	host.global_position = Vector3(0.0, 0.1, 26.0)
	host.look_at(Vector3(0.0, 0.1, 30.0), Vector3.UP)
	var weapon_mount := scene.get_node_or_null("Player/Camera3D/WeaponMount") as Node3D
	if weapon_mount != null:
		weapon_mount.visible = false
	var light := OmniLight3D.new()
	light.position = Vector3(1.0, 3.0, 27.0)
	light.light_energy = 3.0
	light.omni_range = 8.0
	scene.add_child(light)
	for i in 12:
		await process_frame

	await _capture_state(host, host.State.ALERT, "idle", 0.6)
	await _capture_state(host, host.State.PATROL, "walk", 0.8)
	await _capture_state(host, host.State.ENGAGE, "run", 0.5)
	host._melee()
	await _capture(host, "attack", 1.0)
	host.take_damage(9999.0)
	assert(not host.is_in_group(&"enemy"), "death did not leave enemy group")
	assert(host.collision_layer == 0 and host.collision_mask == 0, "death collision stayed enabled")
	await _capture(host, "death", 2.65)
	await create_timer(0.6).timeout
	assert(not is_instance_valid(host), "death animation did not clean up naturally")
	print("HOST_ANIMATION_VERIFY PASS: real clips, death collision and natural cleanup")
	quit(0)


func _capture_state(host: CharacterBody3D, state: int, clip_name: String, seconds: float) -> void:
	host._set_state(state)
	await _capture(host, clip_name, seconds)


func _capture(host: CharacterBody3D, clip_name: String, seconds: float) -> void:
	var player := host._animation_player as AnimationPlayer
	assert(player != null and player.current_animation == clip_name, "wrong clip: " + clip_name)
	await create_timer(seconds).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := _out_dir.path_join("host_" + clip_name + ".png")
	var error := image.save_png(path)
	assert(error == OK, "failed to save " + path)
	print("HOST_ANIMATION_VERIFY clip=", clip_name, " shot=", path)
