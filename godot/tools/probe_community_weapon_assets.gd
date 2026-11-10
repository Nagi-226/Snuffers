extends SceneTree

const ASSETS := [
	["mpx_tactical", "res://addons/community_weapons/mpx_tactical.glb"],
	["g17_gen5_olight", "res://addons/community_weapons/g17_gen5_olight.glb"],
]
const VIEWS := [
	["front", Vector3(0, 0, -1)],
	["back", Vector3(0, 0, 1)],
	["left", Vector3(-1, 0, 0)],
	["right", Vector3(1, 0, 0)],
	["isometric", Vector3(1, 0.6, -1)],
]

var _directory := ""
var _shots := 0
var _results: Array[Dictionary] = []
var _world: Node3D
var _camera: Camera3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(90.0).timeout.connect(func() -> void: _fail("probe timed out"))
	if DisplayServer.get_name() == "headless":
		_fail("screenshots require native rendering")
		return
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_directory = ProjectSettings.globalize_path("res://tmp_shots/community_weapons")
	if DirAccess.make_dir_recursive_absolute(_directory) != OK:
		_fail("cannot create screenshot directory")
		return
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.045, 0.06)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.90, 1.0)
	environment.ambient_light_energy = 1.0
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_world.add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, -35, 0)
	key.light_energy = 1.4
	key.shadow_enabled = true
	_world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(30, 140, 0)
	fill.light_color = Color(0.65, 0.78, 1.0)
	fill.light_energy = 0.6
	_world.add_child(fill)
	_camera = Camera3D.new()
	_camera.fov = 48.0
	_camera.near = 0.001
	_camera.far = 10.0
	_world.add_child(_camera)
	_camera.current = true
	for asset: Array in ASSETS:
		var packed := load(asset[1]) as PackedScene
		if packed == null:
			_fail("cannot import prepared asset: " + asset[1])
			return
		var model := packed.instantiate() as Node3D
		_world.add_child(model)
		var bounds := _bounds(model)
		if bounds.size.length() <= 0.001:
			_fail("prepared asset has no visible geometry: " + asset[1])
			return
		var center := bounds.get_center()
		var distance := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)) * 1.7
		for view: Array in VIEWS:
			var direction: Vector3 = view[1]
			_camera.global_position = center + direction.normalized() * distance
			_camera.look_at(center)
			# Frustum and rendering use the interpolated camera cache outside physics.
			for frame in 20:
				await process_frame
			await RenderingServer.frame_post_draw
			if not _camera.is_position_in_frustum(center):
				_fail("prepared asset is outside the camera frame: " + asset[0])
				return
			if not await _shot(asset[0] + "_" + view[0], bounds):
				return
		model.queue_free()
		await process_frame
	if _shots != ASSETS.size() * VIEWS.size():
		_fail("probe did not finish every planned asset view")
		return
	var report := FileAccess.open(_directory.path_join("report.json"), FileAccess.WRITE)
	if report == null:
		_fail("cannot write screenshot report")
		return
	report.store_string(JSON.stringify({
		"shots": _shots, "resolution": "1920x1080",
		"renderer": RenderingServer.get_current_rendering_method(),
		"purpose": "prepared static community assets; no gameplay or animation acceptance",
		"materials": "original prepared PBR materials under controlled preview lighting",
		"views": _results,
	}, "\t"))
	report.close()
	print("COMMUNITY_WEAPON_PROBE COMPLETED shots=", _shots, " directory=", _directory)
	_world.queue_free()
	await process_frame
	quit(0)


func _bounds(node: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.mesh == null:
			continue
		var box := instance.global_transform * instance.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


func _shot(label: String, bounds: AABB) -> bool:
	await RenderingServer.frame_post_draw
	var snapshot := root.get_texture().get_image()
	if snapshot == null or snapshot.is_empty() or snapshot.get_size() != Vector2i(1920, 1080):
		_fail("missing or incorrectly sized frame: " + label)
		return false
	var minimum := 1.0
	var maximum := 0.0
	for y in range(0, snapshot.get_height(), 16):
		for x in range(0, snapshot.get_width(), 16):
			var pixel := snapshot.get_pixel(x, y)
			var luminance := pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
			minimum = minf(minimum, luminance)
			maximum = maxf(maximum, luminance)
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
		"asset_size": [bounds.size.x, bounds.size.y, bounds.size.z],
		"luminance_range": maximum - minimum,
	}
	_results.append(result)
	print("COMMUNITY_WEAPON_SHOT ", JSON.stringify(result))
	return true


func _fail(reason: String) -> void:
	push_error("COMMUNITY_WEAPON_PROBE_FAIL: " + reason)
	quit(1)
