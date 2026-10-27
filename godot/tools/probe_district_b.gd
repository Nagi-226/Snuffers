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
	var player := _scene.get_node("Player") as CharacterBody3D
	var state = root.get_node("GameState")
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


func _shot(path: String) -> void:
	for i in 8:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(path)
	print("DISTRICT_SHOT ", path)
