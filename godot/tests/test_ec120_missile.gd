extends SceneTree

var _failures := 0
var _world: Node3D
var _state
var _data
var _sections: Dictionary = {}

class DamageTarget extends StaticBody3D:
	var health := 100000.0
	var hits: Array[float] = []
	func take_damage(amount: float, _head: bool) -> void:
		hits.append(amount)
		health -= amount


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _run() -> void:
	create_timer(30.0).timeout.connect(_timeout)
	_assert(ResourceLoader.exists("res://scenes/weapons/ec120_projectile.tscn"), "EC-120 projectile exists")
	if _failures:
		quit(1)
		return
	_state = root.get_node("GameState")
	_state.reset()
	_data = load("res://scenes/weapons/em120r.tres")
	_data.sync_from_config()
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	await _blast_checks()
	if not _section_completed(&"blast"):
		return
	await _flight_checks()
	if not _section_completed(&"flight"):
		return
	await _launcher_checks()
	if not _section_completed(&"launcher"):
		return
	_world.queue_free()
	await process_frame
	print("test_ec120_missile: %d assertion(s) failed" % _failures)
	quit(1 if _failures else 0)


func _timeout() -> void:
	push_error("test_ec120_missile timed out before completing assertions")
	quit(1)


func _section_completed(section: StringName) -> bool:
	if _sections.has(section):
		print("COMPLETED: ", section)
		return true
	_assert(false, "%s tests did not finish; refusing a partial result" % section)
	quit(1)
	return false


func _target(at: Vector3, group: StringName = &"enemy") -> DamageTarget:
	var target := DamageTarget.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 1, 1)
	collision.shape = box
	target.add_child(collision)
	_world.add_child(target)
	target.global_position = at
	target.add_to_group(group)
	return target


func _wall(at: Vector3, dimensions: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	collision.shape = box
	wall.add_child(collision)
	_world.add_child(wall)
	wall.global_position = at
	return wall


func _missile(at: Vector3, mode: StringName = &"laser", target: Node3D = null) -> Node3D:
	var missile = (load("res://scenes/weapons/ec120_projectile.tscn") as PackedScene).instantiate()
	_world.add_child(missile)
	missile.global_position = at
	var excludes: Array[RID] = []
	missile.setup(Vector3.FORWARD, excludes, _data, mode, target)
	if missile.get("_data") == null:
		_assert(false, "EC-120 setup failed")
		missile.queue_free()
		return null
	missile.set_physics_process(false)
	return missile


func _blast_checks() -> void:
	var at := Vector3(100, 100, 0)
	var targets: Array[DamageTarget] = []
	for distance in [0.0, 20.0, 20.001, 35.0, 35.001]:
		targets.append(_target(at + Vector3(distance, 0, 0)))
	var range_target := _target(at + Vector3(0, 0, 15), &"range_target")
	range_target.add_to_group(&"enemy")
	var wall := _wall(at + Vector3(10, 0, 0), Vector3(1, 6, 20))
	await physics_frame
	await physics_frame
	var missile = _missile(at)
	if missile == null:
		return
	missile._apply_area_damage(at)
	for index in targets.size():
		var expected := 1200.0 if index <= 1 else (800.0 if index <= 3 else 0.0)
		var actual := targets[index].hits[0] if not targets[index].hits.is_empty() else 0.0
		_assert(actual == expected, "blast boundary %s receives %s through solid cover (got %s)" % [[0.0, 20.0, 20.001, 35.0, 35.001][index], expected, actual])
	_assert(range_target.hits == [1200.0], "range target in both target groups receives damage exactly once")
	missile.queue_free()
	for target in targets:
		target.queue_free()
	range_target.queue_free()
	wall.queue_free()
	await process_frame
	var direct := _target(at + Vector3(0, 0, -4))
	await physics_frame
	await physics_frame
	var direct_missile = _missile(at)
	if direct_missile == null:
		return
	direct_missile._physics_process(0.5)
	_assert(direct.hits == [1200.0], "direct missile impact deals one 1200-damage blast rather than stacking direct and blast damage")
	direct_missile._explode(at)
	_assert(direct.hits == [1200.0], "a second explosion call cannot damage the same target again")
	direct.queue_free()
	await process_frame
	_sections[&"blast"] = true


func _flight_checks() -> void:
	var at := Vector3(0, 100, 0)
	_state.em120r_aim_point = at + Vector3(0, 0, -1000)
	var missile = _missile(at)
	if missile == null:
		return
	_assert(not missile._engine_ignited and is_equal_approx(missile._velocity.length(), 12.0), "missile initially ejects at 12m/s with its engine off")
	_assert(not missile._engine_flame.visible, "cold ejection has no engine flame")
	missile._physics_process(0.1)
	_assert(not missile._engine_ignited and absf(missile.global_position.distance_to(at) - 1.2) < 0.01, "first 1.2m is cold ejection")
	missile._physics_process(0.149)
	_assert(not missile._engine_ignited and missile._traveled < 3.0, "engine remains off just before three meters")
	missile._physics_process(0.01)
	_assert(missile._engine_ignited and is_equal_approx(missile._velocity.length(), 80.0), "engine ignites at three meters and accelerates to 80m/s")
	_assert(missile._engine_flame.visible, "engine ignition makes the modeled tail flame visible")
	root.get_node("Events").ec120_aim_changed.emit(at + Vector3(40, 0, -100))
	missile._physics_process(0.1)
	_assert(missile._velocity.x > 0.0, "laser missile follows the current cyan indicator to the right")
	root.get_node("Events").ec120_aim_changed.emit(at + Vector3(-40, 0, -100))
	missile._physics_process(0.3)
	_assert(missile._velocity.x < 0.0, "moving the indicator redirects the already launched laser missile")
	missile.queue_free()
	await process_frame
	var target_a := _target(at + Vector3(40, 0, -100))
	var target_b := _target(at + Vector3(-40, 0, -100))
	var first = _missile(at, &"homing", target_a)
	var second = _missile(at, &"homing", target_b)
	if first == null or second == null:
		return
	_state.em120r_locked_target = target_b
	first._physics_process(0.26)
	second._physics_process(0.26)
	first._physics_process(0.1)
	second._physics_process(0.1)
	_assert(first._locked_target == target_a and second._locked_target == target_b, "each autonomous missile retains its own launch target")
	_assert(first._velocity.x > 0.0 and second._velocity.x < 0.0, "autonomous missiles steer toward their separate targets")
	var velocity: Vector3 = first._velocity
	target_a.queue_free()
	await process_frame
	first._physics_process(0.1)
	_assert(first._velocity.is_equal_approx(velocity), "lost autonomous target continues the current flight direction")
	first.queue_free()
	second.queue_free()
	target_b.queue_free()
	await process_frame
	var wall := _wall(at + Vector3(0, 0, -10), Vector3(10, 10, 0.1))
	await physics_frame
	await physics_frame
	var swept = _missile(at)
	if swept == null:
		return
	swept._physics_process(0.26)
	swept._physics_process(0.2)
	_assert(swept._exploded, "swept collision detects a thin wall even when one powered frame moves past it")
	wall.queue_free()
	await process_frame
	_state.em120r_aim_point = Vector3(0, 100, -1500)
	var exhausted = _missile(at)
	if exhausted == null:
		return
	exhausted._physics_process(30.0)
	_assert(exhausted._exploded and exhausted._traveled <= 1500.01, "maximum range detonates a missed missile without overshooting 1500m")
	await process_frame
	_sections[&"flight"] = true


func _launcher_checks() -> void:
	var launcher = (load("res://scenes/weapons/em120r.tscn") as PackedScene).instantiate()
	_world.add_child(launcher)
	launcher.global_position = Vector3(0, 100, 100)
	launcher.set_physics_process(false)
	_state.em120r_aim_origin = launcher.global_position
	root.get_node("Events").ec120_aim_origin_changed.emit(launcher.global_position)
	_state.current_weapon = &"em120r"
	_state.is_aiming = false
	_state.em120r_mag = 10
	_state.em120r_guidance_mode = &"laser"
	_state.em120r_aim_point = Vector3(0, 100, -1000)
	launcher._update_laser()
	_assert(launcher._laser_mesh.visible, "Longbow cyan laser is visible in normal shoulder view")
	_state.is_aiming = true
	launcher._update_laser()
	_assert(not launcher._laser_mesh.visible, "full-screen scope hides the laser mesh so its beam cannot obscure range text")
	_state.is_aiming = false
	launcher._update_laser()
	_assert(launcher._laser_mesh.visible, "releasing the scope restores the cyan laser in normal view")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("EC120_INPUT_MODE: ", Input.mouse_mode)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	launcher._unhandled_input(press)
	_assert(_state.em120r_mag == 9 and is_instance_valid(launcher._laser_missile), "PROJECTILE weapon fires once from its actual left-button handler")
	var guided = launcher._laser_missile
	if not is_instance_valid(guided):
		return
	guided.set_physics_process(false)
	launcher._tick_weapon(1.0)
	_assert(_state.em120r_mag == 9, "holding the trigger cannot auto-fire Longbow")
	launcher._unhandled_input(release)
	launcher._unhandled_input(press)
	_assert(_state.em120r_mag == 9, "laser guidance blocks the next shot while the previous missile is alive")
	guided._explode(guided.global_position)
	await process_frame
	launcher._unhandled_input(release)
	launcher._fire_cooldown = 0.0
	launcher._unhandled_input(press)
	_assert(_state.em120r_mag == 8, "any explosion releases laser guidance for the next shot")
	var second_guided = launcher._laser_missile
	if not is_instance_valid(second_guided):
		_assert(false, "second laser shot failed to create its missile")
		return
	second_guided.set_physics_process(false)
	_state.em120r_guidance_mode = &"homing"
	_state.is_aiming = true
	_state.em120r_locked_target = null
	launcher._fire_cooldown = 0.0
	_assert(not launcher._fire() and _state.em120r_mag == 8, "autonomous mode refuses an unlocked shot without consuming ammo")
	var target_a := _target(Vector3(40, 100, -100))
	var target_b := _target(Vector3(-40, 100, -100))
	_state.em120r_locked_target = target_a
	_assert(launcher._fire() and _state.em120r_mag == 7, "autonomous shot can launch while an earlier laser missile exists")
	_state.em120r_locked_target = target_b
	launcher._fire_cooldown = 0.0
	_assert(launcher._fire() and _state.em120r_mag == 6, "autonomous mode can fire again at a new locked target without waiting for impact")
	_state.em120r_locked_target = target_b
	target_b.health = 0.0
	_assert(not launcher._fire() and _state.em120r_mag == 6, "dead locked target cannot consume an autonomous shot")
	_state.em120r_locked_target = target_a
	target_a.queue_free()
	_assert(not launcher._fire() and _state.em120r_mag == 6, "queued-for-deletion locked target cannot consume a shot")
	await process_frame
	_assert(not launcher._fire() and _state.em120r_mag == 6, "freed locked target is rejected without invalid-object errors")
	_state.em120r_guidance_mode = &"laser"
	_assert(not launcher._fire() and _state.em120r_mag == 6, "returning to laser mode preserves the existing laser missile gate")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sections[&"launcher"] = true
