extends SceneTree

var _scene: Node3D
var _camera: Camera3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_dir := "tmp_shots/district_b"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_scene = (load("res://scenes/levels/district_b.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	for i in 30:
		await process_frame
	_camera = _scene.get_node("Player/Camera3D") as Camera3D
	var nv := _scene.get_node("NightVisionOverlay")
	print("NV_STATE enabled=", root.get_node("GameState").night_vision, " overlay=", nv._overlay.visible, " args=", args)
	await _shot(out_dir + "/spawn.png")
	_camera.global_position = Vector3(22, 12, 22)
	_camera.look_at(Vector3(0, 2.5, -8))
	await _shot(out_dir + "/warehouse_exterior.png")
	_camera.global_position = Vector3(0, 2.1, -4.5)
	_camera.look_at(Vector3(0, 2.0, -16)
	)
	await _shot(out_dir + "/warehouse_interior.png")
	_camera.global_position = Vector3(3.4, 2.5, 15.3)
	_camera.look_at(Vector3(0, 1.25, 11.2))
	await _shot(out_dir + "/apc_rear.png")
	_camera.global_position = Vector3(0, 1.58, 12.62)
	_camera.look_at(Vector3(0, 1.35, 10.45))
	await _shot(out_dir + "/apc_cabin.png")
	_camera.global_position = Vector3(0.82, 1.58, 12.1)
	_camera.look_at(Vector3(-1.1, 1.2, 10.85))
	await _shot(out_dir + "/apc_cabin_seats.png")
	var player := _scene.get_node("Player") as CharacterBody3D
	var state = root.get_node("GameState")
	if not await _verify_apc_walk(player):
		push_error("JB-02 standing walk-in or stand-up clearance failed")
		quit(1)
		return
	for item in [[&"dmr", Vector3(-0.65, 0.65, 11.65)], [&"shotgun", Vector3(0.65, 0.65, 11.65)]]:
		player.global_position = item[1]
		for i in 12:
			await physics_frame
		if not state.weapon_unlocked.get(item[0], false):
			push_error("equipment trigger failed: %s" % item[0])
			quit(1)
			return
		print("DISTRICT_UNLOCK ", item[0], " current=", state.current_weapon)
		await _shot(out_dir + "/equipment_%s.png" % item[0])
	quit()


func _verify_apc_walk(player: CharacterBody3D) -> bool:
	player.global_position = Vector3(0, 0.08, 14.4)
	player.velocity = Vector3.ZERO
	var forward := InputEventKey.new()
	forward.physical_keycode = KEY_W
	forward.pressed = true
	Input.parse_input_event(forward)
	for frame in 360:
		await physics_frame
		if player.global_position.z <= 11.65:
			break
	var release := InputEventKey.new()
	release.physical_keycode = KEY_W
	release.pressed = false
	Input.parse_input_event(release)
	await physics_frame
	print("APC_WALK position=", player.global_position)
	for hit in player.get_slide_collision_count():
		print("APC_WALK_COLLIDER ", player.get_slide_collision(hit).get_collider())
	if player.global_position.z > 11.8 or player.global_position.y < 0.55:
		return false
	player.call("_toggle_prone")
	await physics_frame
	await physics_frame
	player.call("_toggle_prone")
	await physics_frame
	await physics_frame
	var collision := player.get_node("CollisionShape3D") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = collision.global_transform
	query.exclude = [player.get_rid()]
	var overlaps := player.get_world_3d().direct_space_state.intersect_shape(query)
	print("APC_STAND_OVERLAPS ", overlaps)
	for hit in overlaps:
		if hit.collider.name in [&"CargoRoof", &"CargoWest", &"CargoEast", &"CargoBack"]:
			return false
	return true


func _shot(path: String) -> void:
	for i in 8:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(path)
	print("DISTRICT_SHOT ", path)
