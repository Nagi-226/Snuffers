## Actual idle MPX laser convergence, camera parallax and unchanged shot-origin offset.
extends SceneTree

const HitSolver = preload("res://scripts/weapons/hit_solver.gd")
const OUTPUT := "res://tmp_shots/mpx_laser_zeroing"
const DISTANCES := [7.0, 16.0, 25.0, 50.0]

var _assertions := 0
var _failures := 0
var _world: Node3D
var _player
var _weapon
var _state
var _events
var _config
var _wall: StaticBody3D
var _samples: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("MPX laser zeroing requires native rendering")
		quit(1)
		return
	Engine.max_fps = 60
	create_timer(100.0).timeout.connect(func() -> void:
		push_error("MPX laser zeroing timed out")
		quit(1))
	root.size = Vector2i(1920, 1080)
	_state = root.get_node("GameState")
	_events = root.get_node("Events")
	_config = root.get_node("GameConfig")
	_state.reset()
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	var holder := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.06, 0.06, 0.08)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 0.2
	holder.environment = environment
	_world.add_child(holder)
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	_world.add_child(hud)
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	_world.add_child(_player)
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	for weapon in _player.get_node("Camera3D/WeaponMount").get_children():
		weapon.set_process_unhandled_input(false)
	_weapon = _player.get_node("Camera3D/WeaponMount/MPX")
	_wall = _make_wall()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _settle()
	var prior_weapon: StringName = _state.current_weapon
	var prior_aiming: bool = _state.is_aiming
	var prior_unlocked: bool = _state.weapon_unlocked[&"mpx"]
	var prior_mode: StringName = _state.weapon_accessory_modes[&"mpx"]
	_state.weapon_unlocked[&"mpx"] = true
	_player._switch_weapon(&"mpx")
	_state.weapon_accessory_modes[&"mpx"] = &"combined"
	_events.weapon_accessory_mode_changed.emit(&"mpx", &"combined")
	_assert(DirAccess.make_dir_recursive_absolute(OUTPUT) == OK, "MPX zeroing evidence directory opens")
	_assert(is_equal_approx(_config.WEAPON_LASER_ZERO_DISTANCE, 25.0), "MPX camera-axis zero is the accepted twenty-five meters")
	for aiming: bool in [false, true]:
		_player._set_aiming(aiming)
		await _settle()
		for distance: float in DISTANCES:
			var camera: Camera3D = _player._camera
			_wall.global_transform = Transform3D(camera.global_basis, camera.global_position - camera.global_basis.z.normalized() * (distance + 0.1))
			await _settle()
			await _measure(distance, aiming)
	await _measure_ads_transition()
	await _measure_minimum_viewmodel_scale()
	_player._set_aiming(false)
	_state.weapon_accessory_modes[&"mpx"] = prior_mode
	_events.weapon_accessory_mode_changed.emit(&"mpx", prior_mode)
	_player._switch_weapon(prior_weapon)
	_state.weapon_unlocked[&"mpx"] = prior_unlocked
	_player._set_aiming(prior_aiming)
	await _settle()
	_assert(_state.current_weapon == prior_weapon and _state.is_aiming == prior_aiming and _state.weapon_accessory_modes[&"mpx"] == prior_mode and _state.weapon_unlocked[&"mpx"] == prior_unlocked, "MPX distance evidence restores actual selection, aiming, unlock and remembered accessory state")
	_assert(_samples.size() == 12, "all four physical ranges, three actual intermediate ADS weights and the legal minimum viewmodel scale complete native samples")
	var report := FileAccess.open(OUTPUT + "/report.json", FileAccess.WRITE)
	_assert(report != null, "MPX zeroing report opens")
	if report != null:
		report.store_string(JSON.stringify({"assertions": _assertions, "failures": _failures, "samples": _samples}, "\t"))
		report.close()
	_world.queue_free()
	current_scene = null
	await process_frame
	print("MPX_LASER_ZEROING COMPLETED assertions=", _assertions, " failures=", _failures, " samples=", _samples.size())
	quit(1 if _failures > 0 else 0)


func _measure_ads_transition() -> void:
	_player._set_aiming(false)
	await _settle()
	var player_processing: bool = _player.is_processing()
	var weapon_processing: bool = _weapon.is_processing()
	_player.set_process(false)
	_weapon.set_process(false)
	_player._set_aiming(true)
	var previous_weight := 0.0
	for weight: float in [0.25, 0.5, 0.75]:
		# Use the same real producer order as process_priority 0 then 1.
		# The actual accessory child keeps updating while this snapshot is held.
		var delta: float = (weight - previous_weight) * _config.ADS_LERP_TIME
		_weapon._process(delta)
		_player._process(delta)
		previous_weight = weight
		var camera: Camera3D = _player._camera
		_wall.global_transform = Transform3D(camera.global_basis, camera.global_position - camera.global_basis.z.normalized() * 25.1)
		await _settle()
		_assert(is_equal_approx(float(_weapon.get("_aim_weight")), weight) and is_equal_approx(float(_player.get("_ads_weight")), weight), "actual native gun and Player mount retain ADS weight %.2f without writing either weight" % weight)
		await _measure(25.0, true, "_w%03d" % int(weight * 100.0))
	_player.set_process(player_processing)
	_weapon.set_process(weapon_processing)
	_assert(_player.is_processing() == player_processing and _weapon.is_processing() == weapon_processing, "intermediate ADS evidence restores both actual production processing flags")


func _measure_minimum_viewmodel_scale() -> void:
	_player._set_aiming(false)
	await _settle()
	var camera: Camera3D = _player._camera
	_wall.global_transform = Transform3D(camera.global_basis, camera.global_position - camera.global_basis.z.normalized() * 25.1)
	await _settle()
	var player_processing: bool = _player.is_processing()
	var weapon_processing: bool = _weapon.is_processing()
	_player.set_process(false)
	_weapon.set_process(false)
	var mount: Node3D = _player._weapon_mount
	var model: Node3D = _weapon._view_model
	var mount_transform := mount.transform
	var mount_visible := mount.visible
	var camera_near := camera.near
	var depth_scale: float = _player._viewmodel_depth_scale
	var depth_applied: bool = _player._viewmodel_depth_applied
	var depth_hidden: bool = _player._viewmodel_depth_hidden
	var depth_mount_home: Vector3 = _player._viewmodel_depth_mount_home
	var depth_mount_visible: bool = _player._viewmodel_depth_mount_visible
	var depth_homes: Dictionary = _player._viewmodel_depth_homes.duplicate(true)
	var depth_shape_size: Vector3 = _player._viewmodel_depth_shape.size
	var depth_query_transform: Transform3D = _player._viewmodel_depth_query.transform
	var model_transforms: Dictionary = {}
	for item: Node3D in _player._viewmodel_depth_models:
		model_transforms[item] = item.transform
	_player._restore_viewmodel_depth()
	var uncompressed_model_scale := model.scale
	var uncompressed_mount_position := mount.position
	var uncompressed_model_position := model.position
	var minimum_scale: float = _config.VIEWMODEL_WALL_MIN_SCALE
	_assert(is_equal_approx(minimum_scale, 0.02), "minimum-scale regression exercises the actual accepted nonzero 0.02 viewmodel limit")
	# Hold the real minimum release-state scale, then use Player's production
	# compression method against the same unobstructed twenty-five-meter wall.
	# delta=0 retains the minimum for this snapshot without altering GameConfig.
	_player._viewmodel_depth_scale = minimum_scale
	_player._apply_viewmodel_depth(0.0)
	_assert(_player._viewmodel_depth_applied and not _player._viewmodel_depth_hidden and mount.visible == mount_visible, "minimum-scale fixture uses the actual Player compression path without hiding the gun or emitter")
	_assert(model.scale.is_equal_approx(uncompressed_model_scale * minimum_scale) and mount.position.is_equal_approx(uncompressed_mount_position * minimum_scale) and model.position.is_equal_approx(uncompressed_model_position * minimum_scale), "minimum-scale fixture applies the actual mount position, ViewModel position and uniform scale together")
	await _settle()
	var accessory: Node = _weapon.get_node("WeaponAccessory")
	var marker := accessory.get("_laser_origin") as Marker3D
	_assert(not _player.is_processing() and not _weapon.is_processing() and accessory.is_processing() and is_equal_approx(float(_weapon.get("_aim_weight")), 0.0) and model.scale.is_equal_approx(uncompressed_model_scale * minimum_scale), "minimum-scale native snapshot freezes real idle producers while the actual accessory keeps updating the retained legal scale")
	if marker != null:
		var determinant := marker.global_basis.determinant()
		_assert(determinant > 0.0 and absf(determinant - pow(minimum_scale, 3.0)) <= 0.000000001 and absf(marker.global_basis.orthonormalized().determinant() - 1.0) <= 0.00001, "minimum-scale actual emitter basis is invertible at determinant 0.000008 and remains a proper normalized rotation")
		var point_query := PhysicsPointQueryParameters3D.new()
		point_query.position = marker.global_position
		point_query.exclude = HitSolver.collect_owner_rids(_weapon)
		point_query.collide_with_areas = false
		_assert(_world.get_world_3d().direct_space_state.intersect_point(point_query, 1).is_empty(), "minimum-scale actual emitter remains outside every physical collider rather than hiding an inside-wall failure")
	await _measure(25.0, false, "_min_scale")
	# Restore every property touched by the production compression path before
	# resuming normal producers, including other models and its collision query.
	mount.transform = mount_transform
	mount.visible = mount_visible
	var models_restored := true
	for item: Node3D in model_transforms:
		item.transform = model_transforms[item]
		models_restored = models_restored and item.transform.is_equal_approx(model_transforms[item])
	camera.near = camera_near
	_player._viewmodel_depth_scale = depth_scale
	_player._viewmodel_depth_applied = depth_applied
	_player._viewmodel_depth_hidden = depth_hidden
	_player._viewmodel_depth_mount_home = depth_mount_home
	_player._viewmodel_depth_mount_visible = depth_mount_visible
	_player._viewmodel_depth_homes = depth_homes
	_player._viewmodel_depth_shape.size = depth_shape_size
	_player._viewmodel_depth_query.transform = depth_query_transform
	_assert(models_restored and mount.transform.is_equal_approx(mount_transform) and mount.visible == mount_visible and camera.near == camera_near and _player._viewmodel_depth_scale == depth_scale and _player._viewmodel_depth_applied == depth_applied and _player._viewmodel_depth_hidden == depth_hidden and _player._viewmodel_depth_mount_home == depth_mount_home and _player._viewmodel_depth_mount_visible == depth_mount_visible and _player._viewmodel_depth_homes == depth_homes and _player._viewmodel_depth_shape.size == depth_shape_size and _player._viewmodel_depth_query.transform.is_equal_approx(depth_query_transform), "minimum-scale evidence restores all real model transforms, mount visibility, near plane, compression state and physical query")
	_player.set_process(player_processing)
	_weapon.set_process(weapon_processing)
	_assert(_player.is_processing() == player_processing and _weapon.is_processing() == weapon_processing, "minimum-scale evidence restores both actual production processing flags")


func _measure(distance: float, aiming: bool, phase: String = "") -> void:
	var label := ("ads" if aiming else "hip") + "_%02dm" % int(distance)
	label += phase
	var accessory: Node = _weapon.get_node("WeaponAccessory")
	var beam := accessory.get("_laser_beam") as MeshInstance3D
	var dot := accessory.get("_laser_dot") as MeshInstance3D
	var marker := accessory.get("_laser_origin") as Marker3D
	_assert(beam != null and dot != null and marker != null and beam.is_visible_in_tree() and dot.is_visible_in_tree(), label + " samples the actual current world beam, dot and physical emitter")
	if beam == null or dot == null or marker == null:
		return
	var beam_transparency := beam.transparency
	var dot_transparency := dot.transparency
	beam.transparency = 1.0
	dot.transparency = 1.0
	var hidden := await _capture(label + "_hidden")
	beam.transparency = beam_transparency
	dot.transparency = dot_transparency
	var visible := await _capture(label + "_visible")
	var camera: Camera3D = _player._camera
	var center := camera.get_viewport().get_visible_rect().size * 0.5
	var camera_direction := camera.project_ray_normal(center).normalized()
	var camera_hit := _ray(camera.project_ray_origin(center), camera_direction)
	# MPX inherits RifleController's zero-argument physical query.
	# Exercise it without random spread, restoring the real resource before any await.
	var data: WeaponData = _weapon.weapon_data
	var original_spread_hip := data.spread_hip
	var original_spread_prone := data.spread_prone
	var original_spread_aim := data.spread_aim
	data.spread_hip = 0.0
	data.spread_prone = 0.0
	data.spread_aim = 0.0
	var shot_hit: Dictionary = _weapon._cast_spread_ray()
	data.spread_hip = original_spread_hip
	data.spread_prone = original_spread_prone
	data.spread_aim = original_spread_aim
	_assert(data.spread_hip == original_spread_hip and data.spread_prone == original_spread_prone and data.spread_aim == original_spread_aim, label + " actual zero-spread production query restores all original WeaponData spread values exactly and immediately")
	_assert(beam.mesh is CylinderMesh, label + " actual outgoing world beam retains its physical CylinderMesh")
	if not beam.mesh is CylinderMesh:
		return
	var cylinder := beam.mesh as CylinderMesh
	var direction := beam.global_basis.y.normalized()
	var from := beam.global_position - direction * cylinder.height * 0.5
	var tip := beam.global_position + direction * cylinder.height * 0.5
	var laser_hit := _ray(from, direction)
	var zero: Vector3 = camera.global_position + camera_direction * _config.WEAPON_LASER_ZERO_DISTANCE
	var theoretical_direction := (zero - marker.global_position).normalized()
	var theoretical_hit := _ray(marker.global_position, theoretical_direction)
	_assert(not camera_hit.is_empty() and camera_hit.collider == _wall and not shot_hit.is_empty() and shot_hit.collider == _wall and not laser_hit.is_empty() and laser_hit.collider == _wall and not theoretical_hit.is_empty() and theoretical_hit.collider == _wall, label + " actual laser, camera-center, unchanged production shot and theoretical rays hit the real plane")
	if camera_hit.is_empty() or shot_hit.is_empty() or laser_hit.is_empty() or theoretical_hit.is_empty():
		return
	var impact: Vector3 = laser_hit.position
	var theoretical_impact: Vector3 = theoretical_hit.position
	var camera_impact: Vector3 = camera_hit.position
	var shot_impact: Vector3 = shot_hit.position
	var pixel := camera.unproject_position(impact)
	var camera_pixel := camera.unproject_position(camera_impact)
	var shot_pixel := camera.unproject_position(shot_impact)
	var theoretical_pixel := camera.unproject_position(theoretical_impact)
	var pixel_error := pixel.distance_to(theoretical_pixel)
	var world_error := impact.distance_to(theoretical_impact)
	_assert(from.distance_to(marker.global_position) < 0.001 and tip.distance_to(impact) < 0.001 and dot.global_position.distance_to(impact) < 0.001, label + " actual displayed beam and dot retain the physical ray endpoints within one millimeter")
	_assert(camera_pixel.distance_to(center) < 0.01 and absf((camera_impact - camera.global_position).dot(camera_direction) - distance) < 0.001, label + " physical plane lies at the declared exact camera distance and center projection")
	_assert(pixel_error <= 2.0 and world_error <= 0.02, label + " actual idle laser follows the twenty-five-meter zero line with only its expected range parallax")
	if is_equal_approx(distance, _config.WEAPON_LASER_ZERO_DISTANCE):
		_assert(pixel.distance_to(camera_pixel) <= 2.0 and impact.distance_to(camera_impact) <= 0.02, label + " at the accepted zero distance the laser converges on the actual camera-center ray")
	var red_signal := 0.0
	if hidden != null and visible != null:
		var point := Vector2i(pixel)
		for y in range(maxi(0, point.y - 12), mini(visible.get_height(), point.y + 13)):
			for x in range(maxi(0, point.x - 12), mini(visible.get_width(), point.x + 13)):
				var color := visible.get_pixel(x, y)
				var reference := hidden.get_pixel(x, y)
				red_signal += maxf(0.0, color.r - maxf(color.g, color.b) - reference.r + maxf(reference.g, reference.b))
	_assert(red_signal > 0.01, label + " the actual physical laser dot produces native red pixels in the unchanged twenty-five-pixel window")
	var camera_local_direction := camera.global_basis.inverse() * direction
	var marker_direction := -marker.global_basis.z.normalized()
	var sample := {"label": label, "mode": "ads" if aiming else "hip", "distance": distance, "aim_weight": float(_weapon.get("_aim_weight")), "camera_fov": camera.fov, "camera_transform": camera.global_transform, "weapon_transform": _weapon.global_transform, "gun_transform": (_weapon.get("_weapon_node") as Node3D).global_transform, "marker_transform": marker.global_transform, "marker_direction": marker_direction, "laser_direction": direction, "laser_yaw_rad": atan2(camera_local_direction.x, -camera_local_direction.z), "laser_pitch_rad": atan2(camera_local_direction.y, Vector2(camera_local_direction.x, camera_local_direction.z).length()), "laser_impact": impact, "laser_pixel": pixel, "camera_center_impact": camera_impact, "camera_center_pixel": camera_pixel, "production_shot_impact": shot_impact, "production_shot_pixel": shot_pixel, "production_shot_screen_offset": shot_pixel - camera_pixel, "theoretical_parallax_pixel": theoretical_pixel - camera_pixel, "laser_screen_offset": pixel - camera_pixel, "zero_line_pixel_error": pixel_error, "zero_line_world_error": world_error, "native_red_signal": red_signal, "process_frame": Engine.get_process_frames()}
	sample["view_model_scale"] = (_weapon._view_model as Node3D).scale
	sample["view_model_transform"] = (_weapon._view_model as Node3D).global_transform
	sample["mount_transform"] = (_player._weapon_mount as Node3D).global_transform
	sample["marker_basis_determinant"] = marker.global_basis.determinant()
	sample["marker_normalized_basis_determinant"] = marker.global_basis.orthonormalized().determinant()
	sample["beam_basis_determinant"] = beam.global_basis.determinant()
	_samples.append(sample)
	print("MPX_ZERO_SAMPLE ", JSON.stringify(sample))


func _ray(from: Vector3, direction: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * _config.WEAPON_LASER_RANGE)
	query.exclude = HitSolver.collect_owner_rids(_weapon)
	query.collide_with_areas = false
	query.hit_from_inside = true
	return _world.get_world_3d().direct_space_state.intersect_ray(query)


func _make_wall() -> StaticBody3D:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 60, 0.2)
	shape.shape = box
	wall.add_child(shape)
	var mesh := MeshInstance3D.new()
	var model := BoxMesh.new()
	model.size = box.size
	mesh.mesh = model
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.5, 0.5)
	mesh.material_override = material
	wall.add_child(mesh)
	wall.position = Vector3(0, 1.65, -50.1)
	_world.add_child(wall)
	return wall


func _settle() -> void:
	await create_timer(0.4).timeout
	await physics_frame
	await process_frame
	await RenderingServer.frame_post_draw


func _capture(label: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_assert(image != null and not image.is_empty(), label + " native image exists")
	if image != null and not image.is_empty():
		_assert(image.save_png(OUTPUT + "/" + label + ".png") == OK, label + " native image saves")
	return image


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
