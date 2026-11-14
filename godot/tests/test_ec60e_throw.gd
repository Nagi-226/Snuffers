## Native production Player input, independent inventory and real grenade physics.
## Headless cannot capture the mouse; refusing that fixture avoids a false gameplay RED.
extends SceneTree

const PROJECTILE_SCRIPT := "res://scripts/weapons/ec60e_projectile.gd"
var _assertions := 0
var _failures := 0
var _world: Node3D
var _player: CharacterBody3D
var _controller: Node3D
var _state: Node
var _events: Node
var _config: Node
var _requests: Array[Dictionary] = []
var _stocks: Array[int] = []
var _explosions := 0
var _previous_mouse_mode: int


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		print("FAIL: ", label)


func _run() -> void:
	_assert(DisplayServer.get_name() != "headless", "Player G/T integration requires native mouse capture")
	if _failures:
		quit(1)
		return
	create_timer(35.0, true).timeout.connect(_timeout)
	_state = root.get_node("GameState")
	_events = root.get_node("Events")
	_config = root.get_node("GameConfig")
	_state.reset()
	_previous_mouse_mode = Input.mouse_mode
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	_wall(Vector3(0, -0.1, 0), Vector3(200, 0.2, 200))
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	_world.add_child(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	for node: Node in _player.get_node("Camera3D/WeaponMount").get_children():
		node.set_physics_process(false)
		node.set_process(false)
	_controller = _player.get_node_or_null("EC60EController") as Node3D
	_assert(_controller != null, "actual Player contains its independent grenade controller")
	if _controller == null or not _events.has_signal("ec60e_throw_requested"):
		await _finish()
		return
	_events.connect("ec60e_throw_requested", _record_request)
	_events.connect("ec60e_stock_changed", _record_stock)
	_events.connect("ec60e_exploded", _record_explosion)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_assert(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "native fixture actually captures the mouse before G input")
	await _sync()
	await _check_input()
	await _check_guards()
	_check_model_collision_axes()
	await _check_spawn()
	await _check_flight()
	await _check_real_g_landing()
	await _check_cleanup()
	await _finish()


func _key(key: Key, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	event.echo = echo
	_player._unhandled_input(event)


func _sync() -> void:
	await physics_frame
	await physics_frame
	await process_frame


func _grenades() -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	for node: Node in _world.find_children("*", "RigidBody3D", true, false):
		if node.get_script() != null and node.get_script().resource_path == PROJECTILE_SCRIPT and not node.is_queued_for_deletion():
			result.append(node as RigidBody3D)
	return result


func _clear_and_ready() -> void:
	for projectile: RigidBody3D in _grenades():
		projectile.queue_free()
	await process_frame
	for frame in 45:
		await physics_frame
	await process_frame


func _ammo_snapshot() -> Dictionary:
	var result := {"current_weapon": _state.current_weapon, "rifle_grenades": _state.rifle_grenades,
		"fire_modes": _state.fire_modes.duplicate(true), "weapon_chambered": _state.weapon_chambered.duplicate(true)}
	for property: Dictionary in _state.get_property_list():
		var name: String = property.name
		if name.ends_with("_mag") or name.ends_with("_ammo") or name.ends_with("_reserve"):
			result[name] = _state.get(name)
	return result


func _check_input() -> void:
	_state.medkits = 2
	_state.hp = 10.0
	var ammo_before := _ammo_snapshot()
	var camera := _player.get_node("Camera3D") as Camera3D
	_player.velocity = Vector3(1, 0, 2)
	_key(KEY_G)
	var grenades := _grenades()
	_assert(grenades.size() == 1 and _state.ec60e_grenades == 99 and _stocks == [99], "one production G press spawns one grenade and consumes one of the 100 starting units")
	_assert(_requests.size() == 1 and _requests[0].origin.is_equal_approx(camera.global_position)
		and _requests[0].direction.is_equal_approx(-camera.global_basis.z)
		and _requests[0].velocity == _player.velocity and _requests[0].excludes.has(_player.get_rid()), "Player supplies the real camera aim, velocity and its collision RID")
	_assert(_ammo_snapshot() == ammo_before and _state.medkits == 2 and _state.hp == 10.0, "G leaves all gun ammunition, EC-40, selection, firing modes and medicine untouched")
	if grenades.size() == 1:
		var projectile := grenades[0]
		_assert(projectile.get_collision_exceptions().has(_player), "spawned RigidBody explicitly excludes the actual Player collision")
		var expected_velocity := Vector3.FORWARD * 12.0 + Vector3.UP * 2.5 + _player.velocity * 0.65
		_assert(projectile.linear_velocity.is_equal_approx(expected_velocity), "first launch uses the approved 12m/s throw, 2.5m/s lift and 0.65 inherited velocity")
		_assert(projectile.get_parent() == _world, "actual grenade belongs to the active world for scene cleanup")
	_key(KEY_G, false)
	_key(KEY_G, true, true)
	_key(KEY_G)
	_assert(_grenades().size() == 1 and _state.ec60e_grenades == 99 and _stocks == [99], "release, keyboard echo and immediate repeated press consume no extra stock")
	for frame in 45:
		await physics_frame
	_key(KEY_G, true, true)
	_assert(_state.ec60e_grenades == 99, "held-key repeat remains ignored after the throw interval expires")
	_key(KEY_G)
	_assert(_grenades().size() == 2 and _state.ec60e_grenades == 98 and _stocks == [99, 98], "a new G press after the real cooldown creates exactly one additional grenade")
	_key(KEY_T)
	_assert(_state.medkits == 1 and _state.hp == minf(10.0 + float(_config.MEDKIT_HEAL), float(_config.HEALTH_MAX)) and _state.ec60e_grenades == 98, "T uses the actual medkit healing path without consuming a grenade")
	await _clear_and_ready()
	# Existing reload signal is the same live state transition used by an R reload.
	_events.weapon_reload_started.emit(&"rifle")
	var rifle := _player.get_node("Camera3D/WeaponMount/Rifle")
	_assert(rifle.get("_is_reloading") == true, "fixture enters the existing rifle reload state")
	ammo_before = _ammo_snapshot()
	_key(KEY_G)
	_assert(_state.ec60e_grenades == 97 and rifle.get("_is_reloading") == true and _ammo_snapshot() == ammo_before, "grenade throw during reload preserves reload state and gun supply")
	await _clear_and_ready()
	_events.weapon_switched.emit(&"pistol")
	_events.weapon_switched.emit(&"rifle")


func _check_guards() -> void:
	var before: int = _state.ec60e_grenades
	var signals_before := _stocks.size()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_key(KEY_G)
	_assert(_state.ec60e_grenades == before and _grenades().is_empty(), "released mouse rejects G without spawning or consuming stock")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	paused = true
	_key(KEY_G)
	_assert(_state.ec60e_grenades == before and _grenades().is_empty(), "paused Player input cannot throw a grenade")
	paused = false
	for phase in [_state.MissionPhase.COMPLETED, _state.MissionPhase.GAME_OVER]:
		_state.mission_phase = phase
		_key(KEY_G)
		_assert(_state.ec60e_grenades == before and _grenades().is_empty(), "terminal mission phase %s rejects G" % phase)
	_state.mission_phase = _state.MissionPhase.INFILTRATE
	_state.ec60e_grenades = 0
	_key(KEY_G)
	_assert(_state.ec60e_grenades == 0 and _grenades().is_empty() and _stocks.size() == signals_before, "empty stock stays at zero without projectile or success inventory event")
	_state.ec60e_grenades = before
	var excludes: Array[RID] = [_player.get_rid()]
	for values: Array in [[Vector3.ZERO, Vector3.ZERO, Vector3.ZERO],
		[Vector3(INF, 0, 0), Vector3.FORWARD, Vector3.ZERO],
		[Vector3(0, 2, 0), Vector3.FORWARD, Vector3(NAN, 0, 0)]]:
		_events.emit_signal("ec60e_throw_requested", values[0], values[1], values[2], excludes)
	_assert(_state.ec60e_grenades == before and _grenades().is_empty(), "malformed external requests with zero direction or non-finite values cannot consume stock")


func _wall(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	_world.add_child(body)
	body.global_position = at
	return body


func _check_model_collision_axes() -> void:
	var projectile := (load("res://scenes/weapons/ec60e_projectile.tscn") as PackedScene).instantiate() as RigidBody3D
	_world.add_child(projectile)
	var collision := projectile.get_node("CollisionShape3D") as CollisionShape3D
	var shape: Shape3D = collision.shape
	_assert(shape is CapsuleShape3D or shape is CylinderShape3D, "grenade exposes its real capsule or cylindrical collision shape")
	if not (shape is CapsuleShape3D or shape is CylinderShape3D):
		projectile.queue_free()
		return
	var vertices: Array[Vector3] = []
	for node: Node in projectile.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var mesh: Mesh = mesh_instance.mesh
		var transform := projectile.global_transform.affine_inverse() * mesh_instance.global_transform
		for surface in mesh.get_surface_count():
			var points: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for point: Vector3 in points:
				vertices.append(transform * point)
	_assert(vertices.size() > 1000, "collision check measures the prepared real GLB mesh vertices")
	var model_sweep_radius := 0.0
	for vertex: Vector3 in vertices:
		model_sweep_radius = maxf(model_sweep_radius, vertex.length())
	print("EC60E_SPAWN_MODEL_RADIUS model_radius_m=", model_sweep_radius, " query_radius_m=", _config.EC60E_QUERY_RADIUS)
	_assert(model_sweep_radius - float(_config.EC60E_QUERY_RADIUS) <= 0.001, "safe spawn query sphere covers the rotating real model within 1mm")
	var shape_radius: float = shape.get("radius")
	var shape_height: float = shape.get("height")
	var collision_sweep_radius: float = shape_height * 0.5 if shape is CapsuleShape3D \
		else Vector2(shape_radius, shape_height * 0.5).length()
	collision_sweep_radius += collision.position.length()
	_assert(collision_sweep_radius <= float(_config.EC60E_QUERY_RADIUS), "safe spawn query sphere fully covers the rotating collision shape")
	var maximum_excess := -INF
	var outside_vertices := 0
	for vertex: Vector3 in vertices:
		var local: Vector3 = collision.transform.affine_inverse() * vertex
		var excess := _shape_distance(shape, local)
		maximum_excess = maxf(maximum_excess, excess)
		if excess > 0.001:
			outside_vertices += 1
	print("EC60E_COLLISION_ENVELOPE shape=", shape.get_class(), " max_excess_m=", maximum_excess, " vertices_outside_1mm=", outside_vertices, " total=", vertices.size())
	_assert(maximum_excess <= 0.001, "entire real grenade mesh stays within its collision shape at every tumble angle to 1mm")
	# Compare actual skin support to the shape's analytic support plane, not its AABB.
	for normal: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		var model_support := -INF
		for vertex: Vector3 in vertices:
			model_support = maxf(model_support, vertex.dot(normal))
		var collision_support := collision.position.dot(normal) + _shape_support(shape, collision.basis.transposed() * normal)
		var excess := model_support - collision_support
		print("EC60E_COLLISION_SUPPORT normal=", normal, " model=", model_support, " shape=", collision_support, " excess_m=", excess)
		_assert(excess <= 0.001, "real model is supported within 1mm at axis %s after wall/floor contact" % normal)
	projectile.queue_free()


func _shape_distance(shape: Shape3D, point: Vector3) -> float:
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var half_axis := capsule.height * 0.5 - capsule.radius
		var centerline := Vector3(0, clampf(point.y, -half_axis, half_axis), 0)
		return point.distance_to(centerline) - capsule.radius
	var cylinder := shape as CylinderShape3D
	var radial := Vector2(point.x, point.z).length() - cylinder.radius
	var cap := absf(point.y) - cylinder.height * 0.5
	return Vector2(maxf(radial, 0.0), maxf(cap, 0.0)).length() + minf(maxf(radial, cap), 0.0)


func _shape_support(shape: Shape3D, direction: Vector3) -> float:
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		return capsule.radius * direction.length() + (capsule.height * 0.5 - capsule.radius) * absf(direction.y)
	var cylinder := shape as CylinderShape3D
	return cylinder.radius * Vector2(direction.x, direction.z).length() + cylinder.height * 0.5 * absf(direction.y)


func _check_spawn() -> void:
	_player.velocity = Vector3.ZERO
	_player.rotation = Vector3.ZERO
	var camera := _player.get_node("Camera3D") as Camera3D
	var wall := _wall(camera.global_position + Vector3(0, 0, -0.3), Vector3(2, 4, 0.05))
	await _sync()
	var before: int = _state.ec60e_grenades
	_key(KEY_G)
	var grenades := _grenades()
	_assert(grenades.size() == 1 and _state.ec60e_grenades == before - 1, "near-wall G retains a valid throw in front of the wall")
	if grenades.size() == 1:
		var projectile := grenades[0]
		var wall_front: float = wall.global_position.z + 0.025
		_assert(projectile.global_position.z > wall_front + 0.045 and projectile.global_position.z < camera.global_position.z,
			"swept spawn remains on the camera side with room for the whole rotating grenade")
		var minimum_z: float = projectile.global_position.z
		var bounced := false
		for frame in 20:
			await physics_frame
			if is_instance_valid(projectile):
				minimum_z = minf(minimum_z, projectile.global_position.z)
				bounced = bounced or projectile.linear_velocity.z > 0.05
		_assert(minimum_z >= wall_front and bounced, "real rigid-body motion hits the thin wall and rebounds without crossing through")
	await _clear_and_ready()
	wall.global_position = camera.global_position
	await _sync()
	before = _state.ec60e_grenades
	_key(KEY_G)
	_assert(_grenades().is_empty() and _state.ec60e_grenades == before, "camera overlapping solid wall refuses unsafe spawn without charging inventory")
	wall.queue_free()
	await _sync()
	_key(KEY_G)
	_assert(_grenades().size() == 1 and _state.ec60e_grenades == before - 1, "failed wall spawn does not impose cooldown on the next valid request")
	await _clear_and_ready()


func _check_flight() -> void:
	var projectile := (load("res://scenes/weapons/ec60e_projectile.tscn") as PackedScene).instantiate() as RigidBody3D
	_world.add_child(projectile)
	projectile.global_position = Vector3(6, 0.8, 0)
	var excludes: Array[RID] = [_player.get_rid()]
	projectile.call("setup", Vector3.FORWARD, Vector3.ZERO, excludes)
	projectile.linear_velocity = Vector3(0, -1, 0)
	projectile.angular_velocity = Vector3.ZERO
	var minimum_y := 100.0
	var descending := false
	var bounced := false
	var minimum_velocity := INF
	var maximum_contact_up_velocity := -INF
	var maximum_angular_speed := 0.0
	var explosions_before := _explosions
	for frame in 200:
		await physics_frame
		if is_instance_valid(projectile) and not projectile.is_queued_for_deletion():
			minimum_y = minf(minimum_y, projectile.global_position.y)
			minimum_velocity = minf(minimum_velocity, projectile.linear_velocity.y)
			maximum_angular_speed = maxf(maximum_angular_speed, projectile.angular_velocity.length())
			if projectile.global_position.y < 0.2:
				maximum_contact_up_velocity = maxf(maximum_contact_up_velocity, projectile.linear_velocity.y)
			descending = descending or projectile.linear_velocity.y < -1.0
			bounced = bounced or (descending and projectile.global_position.y < 0.2 and projectile.linear_velocity.y > 0.1)
	print("EC60E_FLOOR_TRACE min_center_y=", minimum_y, " min_velocity_y=", minimum_velocity,
		" max_contact_up_velocity=", maximum_contact_up_velocity, " max_angular_speed=", maximum_angular_speed)
	_assert(descending, "real grenade accelerates down under gravity")
	_assert(bounced, "real grenade rebounds upward after floor contact")
	_assert(minimum_y >= 0.025, "real grenade center stays above the floor without tunnelling")
	_assert(not is_instance_valid(projectile) and _explosions == explosions_before + 1, "landed grenade independently finishes the three-second fuse and frees once")


func _check_cleanup() -> void:
	_key(KEY_G)
	var grenades := _grenades()
	_assert(grenades.size() == 1, "cleanup fixture starts with one production G grenade")
	var explosions_before := _explosions
	_player.queue_free()
	await _sync()
	_assert(_grenades().is_empty() and _explosions == explosions_before, "Player/controller removal cleans its outstanding world grenade without an explosion")
	for projectile: RigidBody3D in grenades:
		_assert(not is_instance_valid(projectile), "cleanup removes the original projectile object")
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	_world.add_child(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_key(KEY_G)
	grenades = _grenades()
	_assert(grenades.size() == 1, "scene cleanup fixture starts with a new Player and its real world grenade")
	_world.queue_free()
	await _sync()
	_assert(not is_instance_valid(_world) and _explosions == explosions_before, "removing the entire active level frees its armed grenade without a late explosion")
	for projectile: RigidBody3D in grenades:
		_assert(not is_instance_valid(projectile), "level cleanup destroys the original live grenade object")


func _check_real_g_landing() -> void:
	var before: int = _state.ec60e_grenades
	_key(KEY_G)
	var grenades := _grenades()
	_assert(grenades.size() == 1 and _state.ec60e_grenades == before - 1, "real landing sample starts with a normal Player G throw")
	if grenades.size() != 1:
		return
	var projectile := grenades[0]
	var points: PackedVector3Array = []
	for node: Node in projectile.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var transform := projectile.global_transform.affine_inverse() * instance.global_transform
		for surface in instance.mesh.get_surface_count():
			var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for point: Vector3 in vertices:
				points.append(transform * point)
	var initial_y := projectile.global_position.y
	var rose := false
	var landed := false
	var rebounded := false
	var minimum_center := INF
	var stable_samples := 0
	var minimum_stable_skin := INF
	var explosions_before := _explosions
	for frame in 210:
		await physics_frame
		await process_frame
		if not is_instance_valid(projectile) or projectile.is_queued_for_deletion():
			break
		minimum_center = minf(minimum_center, projectile.global_position.y)
		rose = rose or projectile.global_position.y > initial_y + 0.05
		landed = landed or projectile.global_position.y < 0.2
		rebounded = rebounded or (landed and projectile.global_position.y < 0.2 and projectile.linear_velocity.y > 0.1)
		# Explicit late landing window: final half-second of the approved 3s fuse.
		# Initial discrete-step contacts are logged separately by floor_probe.gd.
		if float(projectile.get("_age")) >= 2.5:
			stable_samples += 1
			for point: Vector3 in points:
				minimum_stable_skin = minf(minimum_stable_skin, (projectile.global_transform * point).y)
	print("EC60E_REAL_G_LANDING vertices=", points.size(), " stable_samples=", stable_samples,
		" min_center_y_all=", minimum_center, " min_stable_skin_y=", minimum_stable_skin)
	_assert(rose and landed and rebounded, "real configured G trajectory rises, lands and rebounds without replacing its velocity or spin")
	_assert(minimum_center >= 0.0, "real G body center never passes below the floor plane")
	_assert(stable_samples >= 12 and points.size() > 1000, "real G landing completes actual mesh measurements in its final half-second")
	_assert(minimum_stable_skin >= -0.001, "all real model vertices remain within 1mm of the floor during the late landing window")
	_assert(not is_instance_valid(projectile) and _explosions == explosions_before + 1, "real configured G grenade explodes once after the sampled landing and cleans up")


func _record_request(origin: Vector3, direction: Vector3, velocity: Vector3, excludes: Array[RID]) -> void:
	_requests.append({"origin": origin, "direction": direction, "velocity": velocity, "excludes": excludes.duplicate()})


func _record_stock(stock: int) -> void:
	_stocks.append(stock)


func _record_explosion(_at: Vector3) -> void:
	_explosions += 1


func _finish() -> void:
	paused = false
	Input.mouse_mode = _previous_mouse_mode
	if _events.has_signal("ec60e_throw_requested") and _events.is_connected("ec60e_throw_requested", _record_request):
		_events.disconnect("ec60e_throw_requested", _record_request)
		_events.disconnect("ec60e_stock_changed", _record_stock)
		_events.disconnect("ec60e_exploded", _record_explosion)
	if is_instance_valid(_world):
		_world.queue_free()
	current_scene = null
	await process_frame
	print("EC60E_THROW COMPLETED assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures else 0)


func _timeout() -> void:
	print("FAIL: EC60E_THROW timed out before completion")
	quit(1)
