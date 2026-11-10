extends SceneTree

const VIEWS := [
	["Spore_WA", Vector3(-17.8, 1.4, -31.3)],
	["Spore_EA", Vector3(18.0, 1.4, -28.2)],
	["Spore_GY", Vector3(28.8, 1.4, -51.0)],
	["Spore_North", Vector3(-3.0, 1.4, -78.8)],
]

var _directory := ""
var _shots := 0
var _results: Array[Dictionary] = []
var _scene: Node3D
var _camera: Camera3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(90.0).timeout.connect(_timeout)
	if DisplayServer.get_name() == "headless":
		_fail("screenshots require a native rendering driver")
		return
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_directory = ProjectSettings.globalize_path("res://tmp_shots/street_spores")
	if DirAccess.make_dir_recursive_absolute(_directory) != OK:
		_fail("cannot create screenshot directory")
		return
	root.get_node("GameState").reset()
	_scene = (load("res://scenes/levels/street_playable.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	var player := _scene.get_node("Player")
	player.set_physics_process(false)
	player.set_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	root.get_node("GameState").player_position = player.global_position
	var spores: Array[CharacterBody3D] = []
	for enemy in get_nodes_in_group(&"enemy"):
		if enemy.get("enemy_kind") == &"spore_husk":
			spores.append(enemy as CharacterBody3D)
		else:
			enemy.set_physics_process(false)
	player.get_node("Camera3D/WeaponMount").visible = false
	_scene.get_node("HUD").visible = false
	for frame in 30:
		await process_frame
	for frame in 60:
		await physics_frame
	for spore in spores:
		if not spore.is_on_floor():
			_fail("spore did not settle on the production ground: " + String(spore.name))
			return
		spore.set_physics_process(false)
	_camera = Camera3D.new()
	_camera.fov = 65.0
	_camera.near = 0.05
	_scene.add_child(_camera)
	_camera.current = true
	var street := _scene.get_node("StreetTest")
	var driver = street.get_node("StreetDayNightDriver")
	var modes := [driver.Mode.NIGHT]
	if OS.get_cmdline_user_args().has("--with-day"):
		modes.append(driver.Mode.DAY)
	for mode in modes:
		driver.set_mode(mode)
		for frame in 20:
			await process_frame
		var mode_name := "night" if mode == driver.Mode.NIGHT else "day"
		for view: Array in VIEWS:
			var spore := street.get_node_or_null(NodePath(view[0])) as CharacterBody3D
			if spore == null or spore.get("enemy_kind") != &"spore_husk":
				_fail("missing live spore: " + view[0])
				return
			_camera.global_position = view[1]
			var target := spore.global_position + Vector3(0, 0.4, 0)
			_camera.look_at(target)
			# Camera3D frustum queries use the cached interpolated transform outside
			# physics ticks. Submit the new view before checking its projection.
			for frame in 20:
				await process_frame
			await RenderingServer.frame_post_draw
			var query := PhysicsRayQueryParameters3D.create(_camera.global_position, target)
			query.exclude = [spore.get_rid()]
			if not street.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				_fail("camera view is obstructed: " + view[0])
				return
			if not _camera.is_position_in_frustum(target):
				_fail("spore is outside the camera frame: " + view[0])
				return
			if not await _shot(mode_name + "_" + view[0].to_lower(), spore.global_position):
				return
	if _shots != VIEWS.size() * modes.size():
		_fail("probe did not finish every planned view")
		return
	var report := FileAccess.open(_directory.path_join("report.json"), FileAccess.WRITE)
	if report == null:
		_fail("cannot write screenshot report")
		return
	report.store_string(JSON.stringify({
		"resolution": "1920x1080", "renderer": RenderingServer.get_current_rendering_method(),
		"shots": _shots, "actors": "physics frozen at settled actual production positions",
		"environment": "production materials and fog; optional day uses the existing mode",
		"purpose": "entity placement readability, not human playtest or combat performance",
		"views": _results,
	}, "\t"))
	report.close()
	print("STREET_SPORE_PROBE COMPLETED shots=", _shots, " directory=", _directory)
	_scene.queue_free()
	await process_frame
	quit(0)


func _shot(label: String, entity_position: Vector3) -> bool:
	await RenderingServer.frame_post_draw
	var snapshot := root.get_texture().get_image()
	if snapshot == null or snapshot.is_empty() or snapshot.get_size() != Vector2i(1920, 1080):
		_fail("missing or incorrectly sized frame: " + label)
		return false
	var minimum := 1.0
	var maximum := 0.0
	var sum := 0.0
	var samples := 0
	for y in range(0, snapshot.get_height(), 16):
		for x in range(0, snapshot.get_width(), 16):
			var pixel := snapshot.get_pixel(x, y)
			var luminance := pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
			minimum = minf(minimum, luminance)
			maximum = maxf(maximum, luminance)
			sum += luminance
			samples += 1
	if maximum - minimum < 0.005:
		_fail("frame is visually uniform: " + label)
		return false
	var output_path := _directory.path_join(label + ".png")
	var error := snapshot.save_png(output_path)
	if error != OK:
		_fail("cannot save %s: %s" % [label, error])
		return false
	_shots += 1
	var result := {
		"view": label, "path": output_path, "save_error": error,
		"camera_position": [_camera.global_position.x, _camera.global_position.y, _camera.global_position.z],
		"entity_position": [entity_position.x, entity_position.y, entity_position.z],
		"mean_luminance": sum / samples, "luminance_range": maximum - minimum,
	}
	_results.append(result)
	print("STREET_SPORE_SHOT ", JSON.stringify(result))
	return true


func _timeout() -> void:
	_fail("probe timed out before completing screenshots")


func _fail(reason: String) -> void:
	push_error("STREET_SPORE_PROBE_FAIL: " + reason)
	quit(1)
