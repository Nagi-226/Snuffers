## Actual L input, native world laser/light, and viewmodel/nano isolation.
extends SceneTree

const OUTPUT := "res://tmp_shots/weapon_accessory_modes"
const IDS := [&"g17", &"mpx"]

var _assertions := 0
var _failures := 0
var _world: Node3D
var _player
var _state
var _events
var _config
var _wall: StaticBody3D
var _night
var _mode_events: Array[Dictionary] = []
var _evidence: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("weapon accessory native light verification requires native rendering")
		quit(1)
		return
	Engine.max_fps = 60
	create_timer(100.0).timeout.connect(func() -> void:
		push_error("weapon accessory modes timed out")
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
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 0.0
	holder.environment = environment
	_world.add_child(holder)
	_wall = _make_box(Vector3(0, 1.65, -16), Vector3(30, 30, 0.2))
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	_world.add_child(_player)
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	for weapon in _player.get_node("Camera3D/WeaponMount").get_children():
		weapon.set_process_unhandled_input(false)
	_night = load("res://scripts/levels/night_vision_overlay.gd").new()
	_world.add_child(_night)
	_state.is_night = true
	_state.weapon_unlocked[&"g17"] = true
	_state.weapon_unlocked[&"mpx"] = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_events.weapon_accessory_mode_changed.connect(_on_mode)
	await _settle()
	_assert(DirAccess.make_dir_recursive_absolute(OUTPUT) == OK, "native accessory evidence output is available")
	_assert(_config.WEAPON_ACCESSORY_MODES == [&"laser", &"flashlight", &"combined"], "contract defines exactly laser, flashlight and combined")
	await _check_modes_and_inputs()
	for id: StringName in IDS:
		await _check_world_effects(id)
	_events.weapon_accessory_mode_changed.disconnect(_on_mode)
	var report := FileAccess.open(OUTPUT + "/report.json", FileAccess.WRITE)
	_assert(report != null, "native accessory report opens")
	if report != null:
		report.store_string(JSON.stringify({"assertions": _assertions, "failures": _failures, "evidence": _evidence}, "\t"))
		report.close()
	_world.queue_free()
	current_scene = null
	await process_frame
	print("WEAPON_ACCESSORY_MODES COMPLETED assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _press_l(pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_L
	event.physical_keycode = KEY_L
	event.pressed = pressed
	event.echo = echo
	_player._unhandled_input(event)


func _want_mode(id: StringName, wanted: StringName) -> void:
	for attempt in 3:
		if _state.weapon_accessory_modes.get(id) == wanted:
			break
		_press_l()
	_assert(_state.weapon_accessory_modes.get(id) == wanted, "%s actual L reaches %s" % [id, wanted])
	await _settle()


func _check_modes_and_inputs() -> void:
	for id: StringName in IDS:
		_player._switch_weapon(id)
		await _settle()
		_assert(_state.weapon_accessory_modes[id] == &"laser", "%s initially selects its own default laser mode" % id)
		for mode: StringName in [&"flashlight", &"combined", &"laser"]:
			var before := _mode_events.size()
			_press_l()
			await _settle()
			_assert(_state.weapon_accessory_modes[id] == mode and _mode_events.size() == before + 1 and _mode_events[-1] == {"weapon": id, "mode": mode}, "%s L cycles to %s with one correct event" % [id, mode])
		await _want_mode(id, &"combined")
		var before := _mode_events.size()
		_press_l(true, true)
		_press_l(false)
		_assert(_state.weapon_accessory_modes[id] == &"combined" and _mode_events.size() == before, "%s L echo and release cannot repeat mode changes" % id)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_press_l()
		_assert(_state.weapon_accessory_modes[id] == &"combined" and _mode_events.size() == before, "%s L is ignored while mouse capture is released" % id)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_state.weapon_unlocked[id] = false
		_press_l()
		_assert(_state.weapon_accessory_modes[id] == &"combined" and _mode_events.size() == before, "%s locked current weapon cannot accept accessory input" % id)
		_state.weapon_unlocked[id] = true
	_player._switch_weapon(&"g17")
	await _want_mode(&"g17", &"flashlight")
	_player._switch_weapon(&"mpx")
	await _want_mode(&"mpx", &"laser")
	_player._switch_weapon(&"g17")
	await _settle()
	_assert(_state.weapon_accessory_modes[&"g17"] == &"flashlight" and _state.weapon_accessory_modes[&"mpx"] == &"laser", "switching back restores independent G17/MPX accessory memories")
	var saved: Dictionary = _state.weapon_accessory_modes.duplicate()
	var before := _mode_events.size()
	_player._switch_weapon(&"rifle")
	_press_l()
	await _settle()
	_assert(_state.weapon_accessory_modes == saved and _mode_events.size() == before, "unsupported rifle L input cannot modify either accessory state")
	_assert(_visible_fx_meshes().is_empty() and _visible_fx_lights().is_empty(), "switching to an unsupported gun hides both conventional world effects")
	_state.weapon_unlocked[&"mpx"] = false
	_player._switch_weapon(&"mpx")
	_assert(_state.current_weapon == &"rifle", "locked MPX selection cannot activate its accessory")
	_state.weapon_unlocked[&"mpx"] = true


func _fx_nodes(type_name: String) -> Array[Node]:
	var nodes: Array[Node] = []
	for node in _world.find_children("*", type_name, true, false):
		if node.get_meta(_config.VIEWMODEL_WORLD_FX_META, false) == true:
			nodes.append(node)
	return nodes


func _visible_fx_meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for node in _fx_nodes("MeshInstance3D"):
		var mesh := node as MeshInstance3D
		if mesh != null and mesh.is_visible_in_tree():
			meshes.append(mesh)
	return meshes


func _visible_fx_lights() -> Array[Light3D]:
	var lights: Array[Light3D] = []
	for node in _fx_nodes("Light3D"):
		var light := node as Light3D
		if light != null and light.is_visible_in_tree():
			lights.append(light)
	return lights


func _check_visible_mode(id: StringName, mode: StringName) -> void:
	var meshes := _visible_fx_meshes()
	var lights := _visible_fx_lights()
	_assert(meshes.size() == (0 if mode == &"flashlight" else 2) and lights.size() == (0 if mode == &"laser" else 1), "%s %s shows exactly its actual world beam/dot and flashlight combination" % [id, mode])


func _check_world_effects(id: StringName) -> void:
	_player._set_aiming(false)
	_player._switch_weapon(id)
	await _want_mode(id, &"laser")
	_check_visible_mode(id, &"laser")
	await _want_mode(id, &"flashlight")
	_check_visible_mode(id, &"flashlight")
	await _want_mode(id, &"combined")
	_check_visible_mode(id, &"combined")
	var meshes := _visible_fx_meshes()
	var lights := _visible_fx_lights()
	if meshes.size() != 2 or lights.size() != 1:
		return
	var light := lights[0] as SpotLight3D
	_assert(light != null, "%s actual flashlight is a world SpotLight3D" % id)
	if light == null:
		return
	var expected_range: float = _config.G17_FLASHLIGHT_RANGE if id == &"g17" else _config.MPX_FLASHLIGHT_RANGE
	_assert(light.light_color.is_equal_approx(_config.WEAPON_FLASHLIGHT_COLOR) and is_equal_approx(light.light_energy, _config.WEAPON_FLASHLIGHT_ENERGY) and is_equal_approx(light.spot_range, expected_range) and is_equal_approx(light.spot_angle, _config.WEAPON_FLASHLIGHT_ANGLE), "%s actual flashlight reads its frozen color, energy, range and cone" % id)
	var snapshots: Array[Dictionary] = []
	for mesh in meshes:
		var material := mesh.get_active_material(0) as BaseMaterial3D
		_assert(material != null and material.emission_enabled and material.albedo_color.r > material.albedo_color.g * 1.4, "%s world laser mesh has an actual emissive red material" % id)
		_assert(not _player._viewmodel_depth_meshes.has(mesh), "%s marked world laser mesh is excluded from physical gun depth bounds" % id)
		if material != null:
			snapshots.append({"mesh": mesh, "transparency": mesh.transparency, "material": material, "albedo": material.albedo_color, "emission": material.emission})
	var dot := _laser_dot(meshes)
	_assert(dot != null, "%s identifies its actual world laser dot by geometry" % id)
	if dot != null:
		_assert(absf(_mesh_center(dot).z - (_wall.position.z + 0.1)) < 0.025, "%s actual laser dot stops on the physical wall surface" % id)
		await _check_native_laser(id, meshes, dot)
	await _check_native_light(id, light)
	await _want_mode(id, &"combined")
	await _check_animation_directions(id, light)
	await _check_emitters_inside_cover(id)
	_player._set_aiming(true)
	await _settle()
	_check_visible_mode(id, &"combined")
	_assert(_state.weapon_accessory_modes[id] == &"combined", "%s ADS preserves its actual accessory mode" % id)
	_state.is_night = true
	_player._toggle_night_vision()
	await _settle()
	_assert(_state.night_vision and _night._overlay.visible and _state.weapon_accessory_modes[id] == &"combined" and light.is_visible_in_tree(), "%s actual night-vision overlay and ADS leave the world flashlight active" % id)
	_player._set_nano_mode(&"stealth")
	await _settle()
	var isolated := snapshots.size() == 2
	for snapshot: Dictionary in snapshots:
		isolated = isolated and snapshot.mesh.transparency == snapshot.transparency and snapshot.material.albedo_color.is_equal_approx(snapshot.albedo) and snapshot.material.emission.is_equal_approx(snapshot.emission)
	_assert(isolated and light.light_color.is_equal_approx(_config.WEAPON_FLASHLIGHT_COLOR) and is_equal_approx(light.light_energy, _config.WEAPON_FLASHLIGHT_ENERGY), "%s nano stealth does not recolor, fade or alter world laser and light materials" % id)
	var faded_gun := false
	for mesh in _player._weapon_mount.find_children("*", "MeshInstance3D", true, false):
		if mesh.get_meta(_config.VIEWMODEL_WORLD_FX_META, false) != true and mesh.is_visible_in_tree():
			faded_gun = faded_gun or mesh.transparency > 0.8
	_assert(faded_gun, "%s nano control still fades the real gun meshes" % id)
	_player._set_nano_mode(&"normal")
	_player._toggle_night_vision()
	_player._set_aiming(false)
	await _settle()
	var weapon = _player.get_node("Camera3D/WeaponMount/" + ("G17" if id == &"g17" else "MPX"))
	_state.set(String(id) + "_mag", 3)
	_state.ammo_9x19_reserve = 100
	weapon._start_reload()
	await create_timer(weapon.weapon_data.reload_time * 0.3).timeout
	_assert(weapon._is_reloading and _state.weapon_accessory_modes[id] == &"combined" and light.is_visible_in_tree(), "%s real timed magazine reload preserves the actual accessory light and mode" % id)
	_player._switch_weapon(&"rifle")
	await _settle()
	_assert(not weapon._is_reloading and _visible_fx_meshes().is_empty() and _visible_fx_lights().is_empty(), "%s switching away cancels reload and hides all of its world effects" % id)
	_player._switch_weapon(id)
	await _settle()
	var near_wall := _make_box(Vector3(0, 1.65, -0.55), Vector3(8, 8, 0.2))
	await _settle()
	_check_visible_mode(id, &"combined")
	_assert(weapon._view_model.scale.x < 0.99 and light.global_basis.get_scale().distance_to(Vector3.ONE) < 0.001, "%s near wall compresses the real viewmodel while its world flashlight retains metric scale" % id)
	dot = _laser_dot(_visible_fx_meshes())
	if dot != null:
		_assert(absf(_mesh_center(dot).z - (near_wall.position.z + 0.1)) < 0.025, "%s near-wall laser stops on the close physical blocker without inheriting gun compression" % id)
	near_wall.queue_free()
	await _settle()
	_assert(weapon._view_model.scale.is_equal_approx(Vector3.ONE), "%s removing the near wall restores the actual gun scale" % id)
	# Cancelled reload coroutines keep their owners until the real timer returns.
	await create_timer(weapon.weapon_data.reload_time).timeout


func _emitter(weapon: Node, name: String) -> Marker3D:
	for node in weapon.find_children(name, "Marker3D", true, false):
		return node as Marker3D
	return null


func _direction_sample(id: StringName, light: SpotLight3D, label: String) -> Dictionary:
	var weapon = _player.get_node("Camera3D/WeaponMount/" + ("G17" if id == &"g17" else "MPX"))
	var laser := _emitter(weapon, "LaserOrigin")
	var flashlight := _emitter(weapon, "FlashlightOrigin")
	_assert(laser != null and flashlight != null, label + " resolves the real model emitter markers")
	if laser == null or flashlight == null:
		return {}
	var forward := -laser.global_basis.z.normalized()
	# Retain 25m convergence and the physical emitter offset from the shot origin.
	var zero: Vector3 = weapon.global_position + forward * _config.WEAPON_LASER_ZERO_DISTANCE
	var expected_beam := (zero - laser.global_position).normalized()
	var expected_light := (zero - flashlight.global_position).normalized()
	var beam: MeshInstance3D
	for mesh in _visible_fx_meshes():
		if mesh.mesh is CylinderMesh:
			beam = mesh
	_assert(beam != null and light.is_visible_in_tree(), label + " has actual visible world laser and flashlight outputs")
	if beam == null:
		return {}
	var axis := beam.global_basis.y.normalized()
	var cylinder := beam.mesh as CylinderMesh
	var actual_from := beam.global_position - axis * cylinder.height * 0.5
	var beam_error := acos(clampf(axis.dot(expected_beam), -1.0, 1.0))
	var light_error := acos(clampf((-light.global_basis.z.normalized()).dot(expected_light), -1.0, 1.0))
	_assert(actual_from.distance_to(laser.global_position) < 0.001 and light.global_position.distance_to(flashlight.global_position) < 0.001, label + " world outputs start at the moving physical emitter mouths")
	_assert(beam_error < 0.015 and light_error < 0.015, label + " actual outgoing beam and cone follow the animated gun basis with 25m convergence")
	_evidence.append({"weapon": id, "phase": label, "marker_forward": forward, "beam_error_rad": beam_error, "light_error_rad": light_error})
	return {"forward": forward}


func _check_animation_directions(id: StringName, light: SpotLight3D) -> void:
	var weapon = _player.get_node("Camera3D/WeaponMount/" + ("G17" if id == &"g17" else "MPX"))
	_state.fire_modes[id] = &"semi"
	_state.set(String(id) + "_mag", 3)
	_state.weapon_chambered[id] = true
	_state.ammo_9x19_reserve = 100
	await _settle()
	var idle := _direction_sample(id, light, "%s actual idle" % id)
	_assert(weapon._fire(), "%s direction control executes a real production shot" % id)
	await create_timer(0.13).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	var fired := _direction_sample(id, light, "%s actual fire" % id)
	if not idle.is_empty() and not fired.is_empty():
		_assert((idle.forward as Vector3).angle_to(fired.forward as Vector3) > 0.002, "%s fire direction control observes actual model-basis movement" % id)
	await create_timer(0.8).timeout
	weapon._start_reload()
	await create_timer(weapon.weapon_data.reload_time * 0.35).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	var reloading := _direction_sample(id, light, "%s actual reload lift" % id)
	_assert(weapon._is_reloading, "%s reload direction sample occurs during its real native reload" % id)
	if not idle.is_empty() and not reloading.is_empty():
		_assert((idle.forward as Vector3).angle_to(reloading.forward as Vector3) > 0.02, "%s reload direction control observes actual raised-gun rotation" % id)
	await create_timer(weapon.weapon_data.reload_time).timeout
	await _settle()


func _check_emitters_inside_cover(id: StringName) -> void:
	var weapon = _player.get_node("Camera3D/WeaponMount/" + ("G17" if id == &"g17" else "MPX"))
	# Isolate the inside-solid rule from Player's separate near-wall compression:
	# weapon/native animation and the real accessory physics query keep running.
	var player_processing: bool = _player.is_processing()
	_player.set_process(false)
	for name: String in ["LaserOrigin", "FlashlightOrigin"]:
		var marker := _emitter(weapon, name)
		if marker == null:
			continue
		var cover := _make_box(marker.global_position, Vector3(0.025, 0.025, 0.025))
		await _settle()
		var point := PhysicsPointQueryParameters3D.new()
		point.position = marker.global_position
		point.exclude = [_player.get_rid()]
		var inside := _world.get_world_3d().direct_space_state.intersect_point(point)
		var found_cover := false
		for hit: Dictionary in inside:
			found_cover = found_cover or hit.collider == cover
		_assert(found_cover, "%s %s positive control places the actual emitter mouth inside physical cover" % [id, name])
		_assert(_visible_fx_meshes().is_empty() if name == "LaserOrigin" else _visible_fx_lights().is_empty(), "%s %s inside-solid output is genuinely disabled rather than emitted through cover" % [id, name])
		cover.queue_free()
		await _settle()
		_check_visible_mode(id, &"combined")
	_player.set_process(player_processing)


func _laser_dot(meshes: Array[MeshInstance3D]) -> MeshInstance3D:
	var dot: MeshInstance3D
	var smallest := INF
	for mesh in meshes:
		if mesh.mesh == null:
			continue
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		var length := bounds.size.length()
		if length < smallest:
			smallest = length
			dot = mesh
	return dot


func _mesh_center(mesh: MeshInstance3D) -> Vector3:
	return mesh.global_transform * mesh.get_aabb().get_center()


func _check_native_laser(id: StringName, meshes: Array[MeshInstance3D], dot: MeshInstance3D) -> void:
	var original: Array[float] = []
	for mesh in meshes:
		original.append(mesh.transparency)
		mesh.transparency = 1.0
	var hidden := await _capture(String(id) + "_laser_hidden")
	for index in meshes.size():
		meshes[index].transparency = original[index]
	var visible := await _capture(String(id) + "_laser_visible")
	if hidden == null or visible == null or hidden.is_empty() or visible.is_empty():
		return
	# _capture has just awaited frame_post_draw for this actual visible image.
	# Sample both the moving dot and camera in that same completed frame.
	var dot_center := _mesh_center(dot)
	var camera: Camera3D = _player._camera
	var center_pixel := camera.unproject_position(dot_center)
	var pixel := Vector2i(center_pixel)
	var sphere := dot.mesh as SphereMesh
	var radius := sphere.radius if sphere != null else 0.0
	var radius_world := camera.global_basis.x.normalized() * radius * dot.global_basis.x.length()
	var projected_radius_px := center_pixel.distance_to(camera.unproject_position(dot_center + radius_world))
	var base_radius_px := center_pixel.distance_to(camera.unproject_position(dot_center + camera.global_basis.x.normalized() * radius))
	var visible_frame := Engine.get_process_frames()
	_assert(sphere != null and is_equal_approx(radius, _config.WEAPON_LASER_DOT_RADIUS) and is_equal_approx(radius, 0.004), "%s actual dot retains its authored four-millimeter SphereMesh radius" % id)
	_assert(projected_radius_px * 2.0 + 0.001 >= _config.WEAPON_LASER_DOT_MIN_DIAMETER_PIXELS, "%s actual scaled world dot reaches the configured minimum projected diameter" % id)
	var beam: MeshInstance3D
	for mesh in meshes:
		if mesh.mesh is CylinderMesh:
			beam = mesh
	var beam_tip := Vector3.ZERO
	if beam != null:
		var cylinder := beam.mesh as CylinderMesh
		beam_tip = beam.global_position + beam.global_basis.y.normalized() * cylinder.height * 0.5
	_assert(beam != null and dot_center.distance_to(beam_tip) < 0.001 and dot_center.distance_to(dot.global_position) < 0.001, "%s scaled dot preserves the actual beam endpoint and physical wall-hit center" % id)
	var red_signal := 0.0
	for y in range(maxi(0, pixel.y - 12), mini(visible.get_height(), pixel.y + 13)):
		for x in range(maxi(0, pixel.x - 12), mini(visible.get_width(), pixel.x + 13)):
			var color := visible.get_pixel(x, y)
			var reference := hidden.get_pixel(x, y)
			red_signal += maxf(0.0, color.r - maxf(color.g, color.b) - reference.r + maxf(reference.g, reference.b))
	_assert(red_signal > 0.01, "%s actual world laser produces native red pixels at its physical wall dot" % id)
	var evidence := {"weapon": id, "laser_dot_world": dot_center, "beam_tip_world": beam_tip, "dot_pixel": pixel, "dot_pixel_float": center_pixel, "visible_process_frame": visible_frame, "camera_fov": camera.fov, "sphere_radius": radius, "display_scale": dot.global_basis.get_scale(), "base_projected_radius_px": base_radius_px, "projected_radius_px": projected_radius_px, "projected_diameter_px": projected_radius_px * 2.0, "minimum_diameter_px": _config.WEAPON_LASER_DOT_MIN_DIAMETER_PIXELS, "native_red_signal": red_signal}
	# Diagnostic positive control only: preserve the authored-radius assertion above.
	# Change mesh geometry because production resets the effect transform each frame.
	if sphere != null:
		var original_height := sphere.height
		sphere.radius = radius * 10.0
		sphere.height = original_height * 10.0
		var diagnostic := await _capture(String(id) + "_laser_diagnostic_10x")
		var diagnostic_center := _mesh_center(dot)
		var diagnostic_pixel_float := camera.unproject_position(diagnostic_center)
		var diagnostic_pixel := Vector2i(diagnostic_pixel_float)
		var diagnostic_radius_world := camera.global_basis.x.normalized() * sphere.radius * dot.global_basis.x.length()
		evidence["diagnostic_projected_radius_px"] = diagnostic_pixel_float.distance_to(camera.unproject_position(diagnostic_center + diagnostic_radius_world))
		evidence["diagnostic_dot_pixel_float"] = diagnostic_pixel_float
		evidence["diagnostic_process_frame"] = Engine.get_process_frames()
		evidence["diagnostic_display_scale"] = dot.global_basis.get_scale()
		sphere.radius = radius
		sphere.height = original_height
		var diagnostic_signal := 0.0
		if diagnostic != null and not diagnostic.is_empty():
			for y in range(maxi(0, diagnostic_pixel.y - 12), mini(diagnostic.get_height(), diagnostic_pixel.y + 13)):
				for x in range(maxi(0, diagnostic_pixel.x - 12), mini(diagnostic.get_width(), diagnostic_pixel.x + 13)):
					var color := diagnostic.get_pixel(x, y)
					var reference := hidden.get_pixel(x, y)
					diagnostic_signal += maxf(0.0, color.r - maxf(color.g, color.b) - reference.r + maxf(reference.g, reference.b))
		evidence["diagnostic_10x_red_signal"] = diagnostic_signal
		_assert(diagnostic_signal > 0.01, "%s enlarged actual dot positive control renders at the same projected wall center" % id)
	_evidence.append(evidence)


func _check_native_light(id: StringName, light: SpotLight3D) -> void:
	await _want_mode(id, &"laser")
	var dark := await _capture(String(id) + "_flashlight_off")
	await _want_mode(id, &"flashlight")
	var lit := await _capture(String(id) + "_flashlight_on")
	if dark == null or lit == null or dark.is_empty() or lit.is_empty():
		return
	var pixel := Vector2i(root.size / 2) + Vector2i(60, -60)
	var dark_luma := _patch_luma(dark, pixel)
	var lit_luma := _patch_luma(lit, pixel)
	_assert(lit_luma > dark_luma + 0.03, "%s actual world flashlight illuminates a native diffuse wall patch" % id)
	var screen_point := Vector2(pixel)
	var from: Vector3 = _player._camera.project_ray_origin(screen_point)
	var direction: Vector3 = _player._camera.project_ray_normal(screen_point)
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * 100.0)
	query.exclude = [_player.get_rid()]
	var hit := _world.get_world_3d().direct_space_state.intersect_ray(query)
	_assert(not hit.is_empty() and hit.collider == _wall, "%s light-shadow control samples the real wall receiver" % id)
	if hit.is_empty() or hit.collider != _wall:
		return
	var blocker_position: Vector3 = light.global_position + ((hit.position as Vector3) - light.global_position).normalized() * 0.15
	var blocker := _make_box(blocker_position, Vector3(0.04, 0.04, 0.04))
	await _settle()
	var camera_hit := _world.get_world_3d().direct_space_state.intersect_ray(query)
	_assert(not camera_hit.is_empty() and camera_hit.collider == _wall, "%s shadow blocker intercepts the light path while leaving the camera wall ray clear" % id)
	var shadow := await _capture(String(id) + "_flashlight_shadow")
	if shadow == null or shadow.is_empty():
		blocker.queue_free()
		await _settle()
		return
	var shadow_luma := _patch_luma(shadow, pixel)
	_assert(light.shadow_enabled and shadow_luma < lit_luma * 0.8, "%s physical occluder casts an actual native flashlight shadow on the unobstructed wall" % id)
	_evidence.append({"weapon": id, "dark_luma": dark_luma, "lit_luma": lit_luma, "shadow_luma": shadow_luma, "blocker_world": blocker_position})
	blocker.queue_free()
	await _settle()


func _make_box(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var model := BoxMesh.new()
	model.size = size
	mesh.mesh = model
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.5, 0.5)
	material.roughness = 1.0
	mesh.material_override = material
	body.add_child(mesh)
	_world.add_child(body)
	body.position = position
	return body


func _settle() -> void:
	await create_timer(0.25).timeout
	await physics_frame
	await process_frame
	await RenderingServer.frame_post_draw


func _capture(label: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_assert(image != null and not image.is_empty(), "%s native image exists" % label)
	if image != null and not image.is_empty():
		_assert(image.save_png(OUTPUT + "/" + label + ".png") == OK, "%s native image saves" % label)
	return image


func _patch_luma(image: Image, center: Vector2i) -> float:
	var total := 0.0
	var count := 0
	for y in range(maxi(0, center.y - 8), mini(image.get_height(), center.y + 9)):
		for x in range(maxi(0, center.x - 8), mini(image.get_width(), center.x + 9)):
			var color := image.get_pixel(x, y)
			total += color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			count += 1
	_assert(count > 0, "native flashlight patch lies inside the actual image")
	return total / float(count) if count > 0 else 0.0


func _on_mode(id: StringName, mode: StringName) -> void:
	_mode_events.append({"weapon": id, "mode": mode})


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
