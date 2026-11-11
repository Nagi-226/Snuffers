## Real range input, native animation and original-vs-production optic material.
extends "res://tools/probe_conventional_feedback.gd"

const CHECK_OUTPUT := "res://tmp_shots/reticle_auto_feedback"
var _feedback_events
var _feedback_shots: Dictionary = {}
var _feedback_shot_frames: Dictionary = {}
var _feedback_muzzles: Dictionary = {}


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("reticle/auto feedback requires native rendering")
		quit(1)
		return
	Engine.max_fps = 60
	create_timer(75.0).timeout.connect(func() -> void:
		push_error("reticle/auto feedback timed out")
		quit(1))
	root.size = Vector2i(1920, 1080)
	_state = root.get_node("GameState")
	_feedback_events = root.get_node("Events")
	_state.reset()
	_scene = (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	_player = _scene.get_node("Player")
	await process_frame
	await physics_frame
	await process_frame
	_player.set_process_unhandled_input(false)
	_player.set_physics_process(false)
	for controller in _player.get_node("Camera3D/WeaponMount").get_children():
		controller.set_process_unhandled_input(false)
	_player.global_position = Vector3(44.0, 0.1, 19.0)
	_player.rotation = Vector3(0, PI, 0)
	_assert(DirAccess.make_dir_recursive_absolute(CHECK_OUTPUT) == OK, "feedback output directory is available")
	_feedback_events.weapon_fired.connect(_count_feedback_shot)
	_feedback_events.player_muzzle_flash.connect(_record_feedback_muzzle)
	await _check_pistol_auto_feedback()
	await _check_reticle_material_feedback()
	_feedback_events.weapon_fired.disconnect(_count_feedback_shot)
	_feedback_events.player_muzzle_flash.disconnect(_record_feedback_muzzle)
	var report := FileAccess.open(CHECK_OUTPUT + "/report.json", FileAccess.WRITE)
	_assert(report != null, "feedback report can be saved")
	if report != null:
		report.store_string(JSON.stringify({"assertions": _assertions, "failures": _failures, "evidence": _report}, "\t"))
		report.close()
	_scene.queue_free()
	current_scene = null
	await process_frame
	await create_timer(0.08).timeout
	await process_frame
	print("RETICLE_AUTO_FEEDBACK COMPLETED assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _count_feedback_shot(id: StringName) -> void:
	_feedback_shots[id] = int(_feedback_shots.get(id, 0)) + 1
	if not _feedback_shot_frames.has(id):
		_feedback_shot_frames[id] = []
	_feedback_shot_frames[id].append(Engine.get_physics_frames())


func _record_feedback_muzzle(id: StringName, position: Vector3) -> void:
	if not _feedback_muzzles.has(id):
		_feedback_muzzles[id] = []
	_feedback_muzzles[id].append(position)


func _feedback_trigger(weapon, pressed: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	weapon._unhandled_input(event)


func _feedback_mode(id: StringName, wanted: StringName) -> void:
	for attempt in 4:
		if _state.fire_modes[id] == wanted:
			break
		var event := InputEventKey.new()
		event.keycode = KEY_X
		event.physical_keycode = KEY_X
		event.pressed = true
		_player._unhandled_input(event)
	_assert(_state.fire_modes[id] == wanted, "%s real X input selects %s" % [id, wanted])


func _check_pistol_auto_feedback() -> void:
	_player._switch_weapon(&"pistol")
	_player._set_aiming(false)
	await create_timer(0.4).timeout
	var weapon = _player.get_node("Camera3D/WeaponMount/Pistol")
	var animation: AnimationPlayer = weapon._arms_animation
	_feedback_mode(&"pistol", &"semi")
	var before := int(_feedback_shots.get(&"pistol", 0))
	_feedback_trigger(weapon, true)
	_assert(animation.current_animation == "fire", "EM-57P semi starts its original native fire clip")
	await process_frame
	await process_frame
	_assert(animation.current_animation_position > 0.0, "EM-57P semi native fire progresses on the real clock")
	await create_timer(0.18).timeout
	_assert(int(_feedback_shots.get(&"pistol", 0)) == before + 1, "held EM-57P semi trigger fires exactly once")
	_feedback_trigger(weapon, false)
	await create_timer(0.6).timeout
	# Change mode while a newly started semi clip is still active.
	var camera_before: float = _player._camera.rotation.x
	_feedback_trigger(weapon, true)
	_feedback_trigger(weapon, false)
	_assert(animation.current_animation == "fire", "semi-to-auto fixture begins with an actual unfinished native fire clip")
	_feedback_mode(&"pistol", &"auto")
	before = int(_feedback_shots.get(&"pistol", 0))
	var muzzle_before: int = _feedback_muzzles.get(&"pistol", []).size()
	_feedback_trigger(weapon, true)
	var maximum_pitch := 0.0
	var maximum_camera_pitch := 0.0
	var non_idle := 0
	var frames := 0
	var deadline := Time.get_ticks_msec() + 750
	while Time.get_ticks_msec() < deadline and int(_feedback_shots.get(&"pistol", 0)) < before + 8:
		await process_frame
		if int(_feedback_shots.get(&"pistol", 0)) == before:
			continue
		frames += 1
		maximum_pitch = maxf(maximum_pitch, absf(weapon._view_model.rotation.x))
		maximum_camera_pitch = maxf(maximum_camera_pitch, absf(_player._camera.rotation.x - camera_before))
		if animation.current_animation != "idle":
			non_idle += 1
	var fired := int(_feedback_shots.get(&"pistol", 0)) - before
	_assert(fired >= 6, "held real EM-57P auto input fires at least six rounds")
	_assert(non_idle == 0, "EM-57P auto clears residual semi animation and keeps native arms in idle throughout firing")
	_assert(maximum_pitch > 0.001, "EM-57P auto has actual visible ViewModel recoil")
	_assert(maximum_camera_pitch > 0.001, "EM-57P auto recoil changes the actual production Camera3D rotation")
	var pitch_limit: float = weapon.weapon_data.recoil_view_offset * weapon.weapon_data.view_recoil_rot_factor
	_assert(maximum_pitch <= pitch_limit + 0.001, "EM-57P auto ViewModel recoil stays within its production per-shot bound")
	var muzzle_count: int = _feedback_muzzles.get(&"pistol", []).size() - muzzle_before
	var finite_muzzles := true
	for index in range(muzzle_before, muzzle_before + muzzle_count):
		var position: Vector3 = _feedback_muzzles[&"pistol"][index]
		finite_muzzles = finite_muzzles and position.is_finite()
	_assert(muzzle_count == fired and finite_muzzles, "each real EM-57P auto round emits exactly one finite world-space muzzle flash")
	var actual_gaps: Array[float] = []
	var rate_valid := true
	var physics_step := 1.0 / float(Engine.physics_ticks_per_second)
	for index in range(before + 1, before + fired):
		var gap: float = float(_feedback_shot_frames[&"pistol"][index] - _feedback_shot_frames[&"pistol"][index - 1]) * physics_step
		actual_gaps.append(gap)
		rate_valid = rate_valid and gap >= weapon.weapon_data.fire_interval - 0.0001 and gap <= weapon.weapon_data.fire_interval + physics_step + 0.0001
	_assert(actual_gaps.size() >= 5 and rate_valid, "EM-57P actual auto shot cadence matches its production interval within one physics frame")
	_feedback_trigger(weapon, false)
	before = int(_feedback_shots.get(&"pistol", 0))
	await create_timer(0.65).timeout
	_assert(int(_feedback_shots.get(&"pistol", 0)) == before and weapon._view_offset == 0.0 and absf(weapon._view_model.rotation.x) < 0.0001, "release stops real auto shots and restores actual ViewModel recoil")
	_assert(animation.current_animation == "idle", "released EM-57P auto has its native idle pose")
	_assert(absf(_player._camera.rotation.x - camera_before) < maximum_camera_pitch * 0.1 + 0.0001, "release restores the actual EM-57P camera recoil toward its original rotation")
	# A real burst leaves the native fire clip active before X selects auto.
	_feedback_mode(&"pistol", &"burst")
	before = int(_feedback_shots.get(&"pistol", 0))
	_feedback_trigger(weapon, true)
	_feedback_trigger(weapon, false)
	deadline = Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < deadline and int(_feedback_shots.get(&"pistol", 0)) == before:
		await process_frame
	_assert(int(_feedback_shots.get(&"pistol", 0)) > before and animation.current_animation == "fire", "burst-to-auto fixture begins with a real burst round and unfinished native fire clip")
	_feedback_mode(&"pistol", &"auto")
	before = int(_feedback_shots.get(&"pistol", 0))
	_feedback_trigger(weapon, true)
	var burst_non_idle := 0
	var burst_frames := 0
	deadline = Time.get_ticks_msec() + 500
	while Time.get_ticks_msec() < deadline and int(_feedback_shots.get(&"pistol", 0)) < before + 4:
		await process_frame
		if int(_feedback_shots.get(&"pistol", 0)) == before:
			continue
		burst_frames += 1
		if animation.current_animation != "idle":
			burst_non_idle += 1
	_assert(int(_feedback_shots.get(&"pistol", 0)) >= before + 4 and burst_frames > 0 and burst_non_idle == 0, "EM-57P auto clears residual burst animation and keeps native idle across four real rounds")
	_feedback_trigger(weapon, false)
	await create_timer(0.65).timeout
	var partial_mag: int = Chamber.total(_state, &"pistol")
	var partial_reserve: int = _state.get(weapon.reserve_state_property)
	_feedback_trigger(weapon, true)
	_press_reload(weapon)
	_assert(weapon._is_reloading and animation.current_animation == "reload", "real R interrupts auto with the native reload clip")
	before = int(_feedback_shots.get(&"pistol", 0))
	await create_timer(0.2).timeout
	_assert(int(_feedback_shots.get(&"pistol", 0)) == before, "auto input cannot fire through the real reload")
	_assert(animation.current_animation == "reload" and animation.current_animation_position > 0.0 and not weapon._magazine.transform.is_equal_approx(weapon._mag_home_transform), "partial manual reload progresses the native clip and moves the actual magazine during auto mode")
	_feedback_trigger(weapon, false)
	await create_timer(weapon.weapon_data.reload_time + 0.1).timeout
	_assert(not weapon._is_reloading and animation.current_animation == "idle" and int(_state.get(weapon.mag_state_property)) == weapon.weapon_data.mag_size and Chamber.total(_state, &"pistol") == weapon.weapon_data.mag_size + 1 and int(_state.get(weapon.reserve_state_property)) == partial_reserve - (weapon.weapon_data.mag_size + 1 - partial_mag), "partial manual reload returns to native idle and preserves exact ammunition transfer")
	# Manual empty and automatic depletion both retain their real empty-reload clip.
	for automatic in [false, true]:
		Chamber.set_total(_state, &"pistol", 2 if automatic else 0)
		_state.set(weapon.reserve_state_property, 100)
		before = int(_feedback_shots.get(&"pistol", 0))
		_feedback_trigger(weapon, true)
		if automatic:
			deadline = Time.get_ticks_msec() + 500
			while Time.get_ticks_msec() < deadline and not weapon._is_reloading:
				await process_frame
		else:
			_press_reload(weapon)
		var label := "automatic depletion" if automatic else "empty manual"
		_assert(weapon._is_reloading and animation.current_animation == "reload_empty", "%s starts the native empty-reload clip in auto mode" % label)
		_assert(int(_feedback_shots.get(&"pistol", 0)) == before + (2 if automatic else 0), "%s emits only its available real rounds before the reload" % label)
		before = int(_feedback_shots.get(&"pistol", 0))
		await create_timer(0.2).timeout
		_assert(int(_feedback_shots.get(&"pistol", 0)) == before and animation.current_animation == "reload_empty" and animation.current_animation_position > 0.0, "%s blocks held auto fire without replacing the progressing empty-reload clip" % label)
		_feedback_trigger(weapon, false)
		await create_timer(weapon.weapon_data.reload_time + 0.1).timeout
		_assert(not weapon._is_reloading and animation.current_animation == "idle" and int(_state.get(weapon.mag_state_property)) == weapon.weapon_data.mag_size - 1 and Chamber.total(_state, &"pistol") == weapon.weapon_data.mag_size and int(_state.get(weapon.reserve_state_property)) == 100 - weapon.weapon_data.mag_size, "%s completes exact ammunition transfer and restores native idle" % label)
	_feedback_trigger(weapon, true)
	await create_timer(0.12).timeout
	_player._switch_weapon(&"g17")
	before = int(_feedback_shots.get(&"pistol", 0))
	await create_timer(0.2).timeout
	_assert(int(_feedback_shots.get(&"pistol", 0)) == before and not weapon.visible, "switching away blocks the held EM-57P auto trigger")
	_feedback_trigger(weapon, false)
	for item: Array in [[&"g17", "G17"], [&"magnum", "Magnum"]]:
		var id: StringName = item[0]
		_player._switch_weapon(id)
		var other = _player.get_node("Camera3D/WeaponMount/" + String(item[1]))
		before = int(_feedback_shots.get(id, 0))
		_feedback_trigger(other, true)
		_assert(other._arms_animation.current_animation == "fire", "%s retains its native single-shot fire clip" % id)
		await create_timer(0.18).timeout
		_feedback_trigger(other, false)
		_assert(int(_feedback_shots.get(id, 0)) == before + 1, "%s remains single-shot while held" % id)
		await create_timer(0.3).timeout
	print("EM57P_AUTO_NATIVE shots=", fired, " frames=", frames, " non_idle_frames=", non_idle, " actual_max_view_pitch=", maximum_pitch, " production_limit=", pitch_limit, " actual_max_camera_pitch=", maximum_camera_pitch, " muzzle_count=", muzzle_count, " shot_gaps=", actual_gaps, " burst_non_idle_frames=", burst_non_idle)
	_report.append({"weapon": "pistol", "auto_shots": fired, "frames": frames, "non_idle_frames": non_idle, "actual_max_view_pitch": maximum_pitch, "actual_max_camera_pitch": maximum_camera_pitch, "muzzle_count": muzzle_count, "shot_gaps": actual_gaps, "burst_non_idle_frames": burst_non_idle})


func _check_reticle_material_feedback() -> void:
	_player._switch_weapon(&"mpx")
	_player._set_aiming(true)
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var weapon = _player.get_node("Camera3D/WeaponMount/MPX")
	var gun: Node3D = weapon._weapon_node
	_check_mpx_feedback(gun, _player._camera, Vector2(root.size) * 0.5)
	var crosshair := gun.find_child("HolographicSightPart1", true, false) as MeshInstance3D
	var source := (load("res://addons/community_weapons/mpx_tactical.glb") as PackedScene).instantiate()
	var source_mesh := source.find_child("HolographicSightPart1", true, false) as MeshInstance3D
	_assert(crosshair != null and source_mesh != null, "MPX production and unchanged original source contain the real reticle mesh")
	if crosshair == null or source_mesh == null:
		source.free()
		return
	var production := crosshair.get_active_material(0) as BaseMaterial3D
	var original := source_mesh.get_active_material(0) as BaseMaterial3D
	_assert(production != null and original != null and production.albedo_texture != null and original.albedo_texture != null, "MPX material comparison resolves actual source and production textures")
	if production == null or original == null or production.albedo_texture == null or original.albedo_texture == null:
		source.free()
		return
	var image := production.albedo_texture.get_image()
	_assert(image != null and not image.is_empty(), "MPX actual production texture provides nonempty pixels")
	if image == null or image.is_empty():
		source.free()
		return
	if image.is_compressed():
		var error := image.decompress()
		_assert(error == OK, "actual production reticle texture decompresses")
		if error != OK:
			source.free()
			return
	var source_image := original.albedo_texture.get_image()
	_assert(source_image != null and not source_image.is_empty(), "unchanged original MPX reticle texture provides nonempty source pixels")
	if source_image == null or source_image.is_empty():
		source.free()
		return
	if source_image.is_compressed():
		var error := source_image.decompress()
		_assert(error == OK, "original MPX reticle texture decompresses for source UV evidence")
		if error != OK:
			source.free()
			return
	var blank := 0
	var transparent := 0
	for y in range(0, image.get_height(), 64):
		for x in range(0, image.get_width(), 64):
			var color := image.get_pixel(x, y)
			if color.r <= maxf(color.g, color.b) + 0.01 or color.a < 0.01:
				blank += 1
				transparent += int(color.a < 0.01)
	_assert(blank > 100 and transparent == blank, "actual production reticle empty pixels have alpha zero instead of an opaque gray square")
	_assert(production.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED, "actual source-plane material applies transparency")
	var red := _red_texture_center(image)
	if int(red.get("pixels", 0)) == 0:
		source.free()
		return
	var point_value: Variant = _crosshair_uv_point(crosshair, red.uv as Vector2)
	_assert(point_value != null, "MPX material comparison uses the real source UV geometry")
	if point_value == null:
		source.free()
		return
	var point: Vector3 = point_value
	var center := Vector2i(_player._camera.unproject_position(point))
	var board := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(4, 4)
	board.mesh = quad
	var background := StandardMaterial3D.new()
	background.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	board.material_override = background
	_player._camera.add_child(board)
	board.position = Vector3(0, 0, minf(_player._camera.to_local(point).z - 0.5, -2.0))
	_player.set_process(false)
	for controller in _player.get_node("Camera3D/WeaponMount").get_children():
		controller.set_process(false)
	var blank_samples := _reticle_blank_uv_samples(crosshair, source_image)
	var saved_override := crosshair.material_override
	for item: Array in [["dark", Color(0.02, 0.02, 0.02)], ["bright", Color(0.8, 0.8, 0.8)]]:
		background.albedo_color = item[1]
		crosshair.visible = false
		var hidden := await _reticle_feedback_image(String(item[0]) + "_hidden")
		crosshair.visible = true
		crosshair.material_override = original
		var old_image := await _reticle_feedback_image(String(item[0]) + "_original")
		crosshair.material_override = production
		var new_image := await _reticle_feedback_image(String(item[0]) + "_production")
		var old_signal := _reticle_chroma_signal(old_image, hidden, center)
		var new_signal := _reticle_chroma_signal(new_image, hidden, center)
		var native_blanks := _reticle_blank_native_samples(blank_samples, hidden, old_image, new_image, String(item[0]))
		_assert(new_signal > 0.05, "MPX production red reticle is visible against %s background" % item[0])
		_assert(new_signal > old_signal * 1.15 + 0.02, "MPX native red signal is brighter than the original material against %s background" % item[0])
		print("MPX_RETICLE_NATIVE background=", item[0], " original_red_signal=", old_signal, " production_red_signal=", new_signal, " empty_texels=", blank, " alpha_zero_texels=", transparent)
		print("MPX_RETICLE_BLANK_NATIVE background=", item[0], " source_uv_pixel_samples=", JSON.stringify(native_blanks))
		_report.append({"weapon": "mpx", "background": item[0], "original_red_signal": old_signal, "production_red_signal": new_signal, "empty_texels": blank, "alpha_zero_texels": transparent, "native_blank_samples": native_blanks})
	crosshair.material_override = saved_override
	board.queue_free()
	source.free()
	for controller in _player.get_node("Camera3D/WeaponMount").get_children():
		controller.set_process(true)
	_player.set_process(true)
	_player._set_aiming(false)


func _reticle_blank_uv_samples(mesh: MeshInstance3D, source_image: Image) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	# The native collection verified these four interior UVs as RGB188 gray.
	# Corner UVs are diagnostic only: source red ticks extend to the edge.
	var blank_uvs: Array[Vector2] = [Vector2(0.35, 0.35), Vector2(0.65, 0.35), Vector2(0.35, 0.65), Vector2(0.65, 0.65), Vector2(0.2, 0.2), Vector2(0.8, 0.2), Vector2(0.2, 0.8), Vector2(0.8, 0.8)]
	var selected_count := 0
	for index in blank_uvs.size():
		var uv := blank_uvs[index]
		var selected := index < 4
		var texel := Vector2i(Vector2(source_image.get_size()) * uv)
		var color := source_image.get_pixel(texel.x, texel.y)
		var neutral := color.a > 0.99 and color.r > 0.1 and absf(color.r - color.g) < 0.01 and absf(color.g - color.b) < 0.01
		if selected:
			_assert(neutral and absf(color.r - 188.0 / 255.0) < 1.0 / 255.0, "selected actual original MPX empty UV %s is opaque RGB188 neutral gray" % uv)
		if not neutral:
			continue
		var point_value: Variant = _crosshair_uv_point(mesh, uv)
		if selected:
			_assert(point_value != null, "selected actual source empty UV %s maps onto the MPX mesh" % uv)
		if point_value == null:
			continue
		var point: Vector3 = point_value
		var pixel := Vector2i(_player._camera.unproject_position(point))
		var inside := point.is_finite() and pixel.x >= 0 and pixel.y >= 0 and pixel.x < root.size.x and pixel.y < root.size.y
		if selected:
			_assert(inside, "selected actual source empty UV %s projects into a finite native screen pixel" % uv)
		if inside:
			samples.append({"uv": uv, "pixel": pixel, "source_rgba": [color.r, color.g, color.b, color.a], "selected": selected})
			selected_count += int(selected)
	_assert(selected_count == 4, "native gray-background difference uses all four verified interior opaque source UV points")
	return samples


func _reticle_blank_native_samples(samples: Array[Dictionary], hidden: Image, original: Image, production: Image, background: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var selected_count := 0
	for sample: Dictionary in samples:
		var pixel: Vector2i = sample.pixel
		var hidden_color := hidden.get_pixel(pixel.x, pixel.y)
		var original_color := original.get_pixel(pixel.x, pixel.y)
		var production_color := production.get_pixel(pixel.x, pixel.y)
		var old_delta := maxf(absf(original_color.r - hidden_color.r), maxf(absf(original_color.g - hidden_color.g), absf(original_color.b - hidden_color.b)))
		var new_delta := maxf(absf(production_color.r - hidden_color.r), maxf(absf(production_color.g - hidden_color.g), absf(production_color.b - hidden_color.b)))
		if sample.selected:
			selected_count += 1
			_assert(old_delta >= 2.0 / 255.0, "original MPX gray background is measurable at source UV %s against %s" % [sample.uv, background])
			_assert(new_delta <= 1.0 / 255.0, "production MPX empty source UV %s matches the hidden native background within one RGB level against %s" % [sample.uv, background])
		output.append({"uv": [sample.uv.x, sample.uv.y], "pixel": [pixel.x, pixel.y], "source_rgba": sample.source_rgba, "selected": sample.selected, "hidden_rgb": [hidden_color.r, hidden_color.g, hidden_color.b], "original_rgb": [original_color.r, original_color.g, original_color.b], "production_rgb": [production_color.r, production_color.g, production_color.b], "original_max_rgb_delta": old_delta, "production_max_rgb_delta": new_delta})
	_assert(selected_count >= 4, "MPX native gray-background disappearance checks at least four verified source UV points against %s" % background)
	return output


func _reticle_feedback_image(label: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_assert(image.save_png(CHECK_OUTPUT + "/mpx_" + label + ".png") == OK, "MPX %s native image saves" % label)
	return image


func _reticle_chroma_signal(image: Image, hidden: Image, center: Vector2i) -> float:
	var red_signal := 0.0
	for y in range(maxi(0, center.y - 36), mini(image.get_height(), center.y + 37)):
		for x in range(maxi(0, center.x - 36), mini(image.get_width(), center.x + 37)):
			var color := image.get_pixel(x, y)
			var reference := hidden.get_pixel(x, y)
			red_signal += maxf(0.0, (color.r - maxf(color.g, color.b)) - (reference.r - maxf(reference.g, reference.b)))
	return red_signal
