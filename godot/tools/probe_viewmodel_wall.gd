extends SceneTree

const CASES := [
	["rifle_front", &"rifle", false, Vector3(-6.05, 0.15, 23), PI * 0.5],
	["rifle_side", &"rifle", false, Vector3(6.05, 0.15, 18), 0.0],
	["shotgun_ads_front", &"shotgun", true, Vector3(-6.05, 0.15, 23), PI * 0.5],
	["em120r_front", &"em120r", false, Vector3(-6.05, 0.15, 23), PI * 0.5],
]

var _directory := ""
var _shots := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(45.0).timeout.connect(_timeout)
	if DisplayServer.get_name() == "headless":
		_fail("wall screenshots require native rendering")
		return
	root.size = Vector2i(1920, 1080)
	var args := OS.get_cmdline_user_args()
	var label := "after"
	var index := args.find("--label")
	if index >= 0 and index + 1 < args.size():
		label = args[index + 1]
	if label not in ["baseline", "after"]:
		_fail("--label must be baseline or after")
		return
	_directory = ProjectSettings.globalize_path("res://tmp_shots/viewmodel_wall/" + label)
	if DirAccess.make_dir_recursive_absolute(_directory) != OK:
		_fail("cannot create screenshot directory")
		return
	var state = root.get_node("GameState")
	state.reset()
	var scene := (load("res://scenes/levels/street_playable.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for frame in 30:
		await process_frame
	var player = scene.get_node("Player")
	for actor in scene.find_children("*", "CharacterBody3D", true, false):
		actor.set_physics_process(false)
		actor.set_process_unhandled_input(false)
	scene.get_node("StreetTest/StreetDayNightDriver").set_mode(0)
	player._camera.current = true
	for entry: Array in CASES:
		state.weapon_unlocked[entry[1]] = true
		player._set_aiming(false)
		player._switch_weapon(entry[1])
		player.global_position = entry[3]
		player.rotation.y = entry[4]
		player._camera.rotation = Vector3.ZERO
		player._set_aiming(entry[2])
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		var snapshot := root.get_texture().get_image()
		if snapshot == null or snapshot.is_empty() or snapshot.get_size() != Vector2i(1920, 1080):
			_fail("missing native frame: " + entry[0])
			return
		var error := snapshot.save_png(_directory.path_join(entry[0] + ".png"))
		if error != OK:
			_fail("cannot save screenshot: " + entry[0])
			return
		_shots += 1
		print("VIEWMODEL_WALL_SHOT ", label, " ", entry[0], " position=", player.global_position, " mount=", player._weapon_mount.position)
	if _shots != CASES.size():
		_fail("did not finish all wall views")
		return
	print("VIEWMODEL_WALL_PROBE COMPLETED shots=", _shots, " directory=", _directory)
	scene.queue_free()
	await process_frame
	quit()


func _timeout() -> void:
	_fail("probe timed out before completing screenshots")


func _fail(reason: String) -> void:
	push_error("VIEWMODEL_WALL_PROBE_FAIL: " + reason)
	quit(1)
