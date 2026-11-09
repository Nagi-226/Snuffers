extends SceneTree

var _scene: Node3D
var _player: CharacterBody3D
var _state
var _shots := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	_state = root.get_node("GameState")
	_scene = (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	_player = _scene.get_node("Player") as CharacterBody3D
	for frame in 30:
		await process_frame
	if _player._missile_scope == null or _player._missile_tactical == null:
		_fail("Longbow scope did not initialize")
		return
	var directory_error := DirAccess.make_dir_recursive_absolute("tmp_shots/em_final_platforms")
	if directory_error != OK:
		_fail("cannot create screenshot directory: %s" % directory_error)
		return
	var day_night = _scene.get_node("GreyboxArena/DayNightController")
	day_night.set_mode(day_night.Mode.DAY)
	var target = _scene.get_node("RangeFacilities/Targets/CloseTarget") as Node3D
	target.health = 100000.0
	_player.global_position = Vector3(44, 0.1, 19)
	_player.rotation.y = PI
	_player._camera.rotation = Vector3.ZERO
	for id in [&"em127m", &"em120r"]:
		_player._set_aiming(false)
		_player._switch_weapon(id)
		await create_timer(0.3).timeout
		if not await _shot("%s_hip" % id):
			return
		_player._camera.look_at(target.global_position + Vector3(0, 1, 0))
		_player._set_aiming(true)
		await create_timer(0.3).timeout
		if not await _shot("%s_scope_16x" % id):
			return
		_player._adjust_em86s_zoom(1)
		await create_timer(0.15).timeout
		if not await _shot("%s_scope_32x" % id):
			return
		_player._adjust_em86s_zoom(1)
		await create_timer(0.15).timeout
		if not await _shot("%s_scope_64x" % id):
			return
		_player._set_aiming(false)
		await create_timer(0.2).timeout
	_player._switch_weapon(&"em120r")
	var launcher = _player.get_node("Camera3D/WeaponMount/Em120r")
	if _state.em120r_guidance_mode != &"homing":
		_player._cycle_fire_mode()
	_player._camera.look_at(target.global_position + Vector3(0, 1, 0))
	_player._set_aiming(true)
	await create_timer(1.5).timeout
	if not is_instance_valid(_state.em120r_locked_target):
		_fail("target was not locked after the acquisition interval")
		return
	if not await _shot("em120r_scope_locked"):
		return
	print("EM_FINAL_LOCK target=", _state.em120r_locked_target)
	_player._set_aiming(false)
	_player._cycle_fire_mode()
	await create_timer(0.2).timeout
	if not await _shot("em120r_laser"):
		return
	# Use the real projectile and flight integrator, pausing between measured phases
	# so both the cold launch and lit engine are captured at a stable render frame.
	launcher._fire_cooldown = 0.0
	if launcher._fire():
		var missile = launcher._laser_missile
		if not is_instance_valid(missile) or missile._exploded:
			_fail("laser launch failed to create a flying missile")
			return
		missile.set_physics_process(false)
		var observer := Camera3D.new()
		_scene.add_child(observer)
		observer.global_position = missile.global_position + Vector3(2, 0.6, 1.5)
		observer.look_at(missile.global_position)
		observer.current = true
		missile._physics_process(0.08)
		observer.look_at(missile.global_position)
		if missile._exploded or missile._engine_ignited:
			_fail("cold ejection did not remain unlit")
			return
		if not await _shot("ec120_cold_ejection"):
			return
		missile._physics_process(0.18)
		observer.global_position = missile.global_position + Vector3(2, 0.6, 1.5)
		observer.look_at(missile.global_position)
		if missile._exploded or not missile._engine_ignited:
			_fail("engine did not ignite after the measured ejection distance")
			return
		if not await _shot("ec120_engine_ignition"):
			return
		missile._explode(missile.global_position)
		_player._camera.current = true
		observer.queue_free()
	else:
		_fail("laser launch was rejected")
		return
	if _shots != 12:
		_fail("probe finished without all twelve screenshots")
		return
	if "--interactive" in OS.get_cmdline_user_args():
		_player._set_aiming(false)
		print("EM_FINAL_PREVIEW_READY: white-day range, Longbow selected; keys 5/6 choose Thunder/Longbow, X switches mode, RMB aims, wheel zooms")
		return
	_scene.queue_free()
	await process_frame
	quit()


func _shot(label: String) -> bool:
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var snapshot := root.get_texture().get_image()
	if snapshot == null or snapshot.is_empty():
		_fail("render produced no image for %s" % label)
		return false
	var error := snapshot.save_png("tmp_shots/em_final_platforms/%s.png" % label)
	if error != OK:
		_fail("cannot save screenshot %s: %s" % [label, error])
		return false
	_shots += 1
	print("EM_FINAL_SHOT ", label, " fov=", _player._camera.fov)
	return true


func _fail(reason: String) -> void:
	push_error("EM_FINAL_PROBE_FAIL: " + reason)
	quit(1)
