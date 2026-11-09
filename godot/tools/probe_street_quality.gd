extends SceneTree

const VIEWS := [
	["street_south", Vector3(0, 1.7, 26), Vector3(0, 2.0, -10)],
	["street_north", Vector3(0, 1.7, 4), Vector3(0, 2.0, -34)],
	["wall", Vector3(3.5, 1.7, 20), Vector3(7.2, 2.1, 18)],
	["garage", Vector3(1.5, 1.7, -16), Vector3(8.0, 1.8, -18)],
	["metal_gate", Vector3(18.5, 1.7, 4.2), Vector3(22, 1.4, 5)],
]

var _directory := ""
var _label := "after"
var _shots := 0
var _results: Array[Dictionary] = []
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
	Engine.max_fps = 0
	var args := OS.get_cmdline_user_args()
	if "--before" in args:
		_label = "baseline"
	var label_index := args.find("--label")
	if label_index >= 0 and label_index + 1 < args.size():
		_label = args[label_index + 1]
	if _label not in ["baseline", "after"]:
		_fail("--label must be baseline or after")
		return
	_directory = ProjectSettings.globalize_path("res://tmp_shots/street_quality/" + _label)
	if DirAccess.make_dir_recursive_absolute(_directory) != OK:
		_fail("cannot create screenshot directory")
		return
	root.get_node("GameState").reset()
	var scene := (load("res://scenes/levels/street_playable.tscn") as PackedScene).instantiate() as Node3D
	var sample := scene.get_node_or_null("StreetTest/StreetQualitySample")
	if sample != null and _label == "baseline":
		sample.set_meta("quality_sample_disabled", true)
	root.add_child(scene)
	current_scene = scene
	for frame in 30:
		await process_frame
	for actor in scene.find_children("*", "CharacterBody3D", true, false):
		actor.set_physics_process(false)
		actor.set_process_unhandled_input(false)
	var player = scene.get_node("Player")
	player.set_process(false)
	player.get_node("Camera3D/WeaponMount").visible = false
	scene.get_node("HUD").visible = false
	_camera = Camera3D.new()
	scene.add_child(_camera)
	_camera.fov = 75.0
	_camera.current = true
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var street := scene.get_node("StreetTest")
	var driver = street.get_node("StreetDayNightDriver")
	for mode in [driver.Mode.NIGHT, driver.Mode.DAY]:
		driver.set_mode(mode)
		for frame in 30:
			await process_frame
		var mode_name := "night" if mode == driver.Mode.NIGHT else "day"
		for view: Array in VIEWS:
			_camera.global_position = view[1]
			_camera.look_at(view[2])
			for frame in 30:
				await process_frame
			if not await _shot(mode_name + "_" + view[0]):
				return
			await _measure(mode_name + "_" + view[0])
	if _shots != 10:
		_fail("probe did not finish all ten views")
		return
	var report := {
		"label": _label, "resolution": "1920x1080", "vsync": "disabled",
		"actors": "physics frozen for repeatable scene comparison",
		"measurements": _results,
	}
	var output := FileAccess.open(_directory.path_join("frame_times.json"), FileAccess.WRITE)
	if output == null:
		_fail("cannot write frame-time report")
		return
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("STREET_QUALITY_PROBE COMPLETED shots=", _shots, " directory=", _directory)
	if "--interactive" in args:
		_camera.queue_free()
		player._camera.current = true
		player._weapon_mount.visible = true
		player.set_process(true)
		player.set_physics_process(true)
		player.set_process_unhandled_input(true)
		scene.get_node("HUD").visible = true
		driver.set_mode(driver.Mode.NIGHT)
		print("STREET_QUALITY_PREVIEW_READY: first street; WASD moves, RMB aims")
		return
	scene.queue_free()
	await process_frame
	quit()


func _shot(label: String) -> bool:
	await RenderingServer.frame_post_draw
	var snapshot := root.get_texture().get_image()
	if snapshot == null or snapshot.is_empty() or snapshot.get_size() != Vector2i(1920, 1080):
		_fail("missing or incorrectly sized frame: " + label)
		return false
	var error := snapshot.save_png(_directory.path_join(label + ".png"))
	if error != OK:
		_fail("cannot save %s: %s" % [label, error])
		return false
	_shots += 1
	print("STREET_QUALITY_SHOT ", _label, " ", label)
	return true


func _measure(label: String) -> void:
	var intervals: Array[float] = []
	var gpu_times: Array[float] = []
	var cpu_times: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame in 180:
		await process_frame
		var now := Time.get_ticks_usec()
		intervals.append(float(now - previous) / 1000.0)
		gpu_times.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		cpu_times.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		previous = now
	intervals.sort()
	gpu_times.sort()
	cpu_times.sort()
	var total := 0.0
	for interval in intervals:
		total += interval
	var result := {
		"view": label, "frames": intervals.size(), "mean_ms": total / intervals.size(),
		"median_ms": intervals[int(intervals.size() * 0.5)], "p95_ms": intervals[int(intervals.size() * 0.95) - 1],
		"viewport_gpu_median_ms": gpu_times[int(gpu_times.size() * 0.5)], "viewport_gpu_p95_ms": gpu_times[int(gpu_times.size() * 0.95) - 1],
		"viewport_render_cpu_median_ms": cpu_times[int(cpu_times.size() * 0.5)],
	}
	_results.append(result)
	print("STREET_QUALITY_FRAME_TIME ", JSON.stringify(result))


func _timeout() -> void:
	_fail("probe timed out before completing screenshots")


func _fail(reason: String) -> void:
	push_error("STREET_QUALITY_PROBE_FAIL: " + reason)
	quit(1)
