extends SceneTree

const Chamber = preload("res://tests/chamber_test_support.gd")

var _failures := 0
var _assertions := 0
var _world: Node3D
var _player
var _state

class DamageTarget extends StaticBody3D:
	var hits: Array[float] = []
	func take_damage(amount: float, _head: bool) -> void:
		hits.append(amount)


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _run() -> void:
	create_timer(60.0).timeout.connect(_timeout)
	_assert(DisplayServer.get_name() != "headless", "posed-mesh geometry verification uses native rendering")
	if _failures:
		quit(1)
		return
	_state = root.get_node("GameState")
	_state.reset()
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	if "--unprotected" in OS.get_cmdline_user_args():
		# Like check_scripts.gd, compile only once autoload nodes are available.
		# Static inner inheritance parses the base before SceneTree has autoloads.
		var unprotected := GDScript.new()
		unprotected.source_code = "extends \"res://scripts/player/player_controller.gd\"\n\nfunc _apply_viewmodel_depth(_delta: float) -> void:\n\tpass\n"
		var compile_error: int = unprotected.reload()
		_assert(compile_error == OK, "unprotected fixture compiles after autoload initialization")
		if compile_error != OK:
			_player.free()
			quit(1)
			return
		_player.set_script(unprotected)
		print("VIEWMODEL_GEOMETRY_MODE: original pose behavior without wall protection")
	_world.add_child(_player)
	_player.global_position = Vector3(0, 100, 0)
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	await _settle()
	await _long_gun_open_floor_checks()
	var cases := [
		[&"rifle", false], [&"rifle", true],
		[&"shotgun", false], [&"shotgun", true],
		[&"em86b", false], [&"em86b", true],
		[&"em127m", false], [&"em120r", false],
	]
	for entry: Array in cases:
		var id: StringName = entry[0]
		var aiming: bool = entry[1]
		_state.weapon_unlocked[id] = true
		_player._set_aiming(false)
		_player._switch_weapon(id)
		_player._set_aiming(aiming)
		await _settle()
		var label := "%s %s" % [id, "ADS" if aiming else "hip"]
		_assert_pose_bounds_contain_baked_vertices(label)
		var home_position: Vector3 = _player._weapon_mount.position
		var home_camera: Vector3 = _player._camera.position
		var optic := _visible_optic()
		var home_projection := _optic_projection(optic) if optic != null else Vector2.ZERO
		_assert(_player._weapon_mount.scale.is_equal_approx(Vector3.ONE), label + " retains original scale in open space")
		var front := _wall(Vector3(0, 101.8, -0.55), Vector3(8, 6, 0.2))
		await _settle()
		var bounds := _visible_bounds()
		_assert(bounds.size() > 0, label + " has real visible viewmodel geometry")
		_assert(_minimum(bounds, 2) >= -0.445, label + " stays outside a reachable front wall")
		_assert(_player._camera.global_position.z > -0.45, label + " keeps the camera outside the wall")
		_assert(_state.is_aiming == aiming and _state.current_weapon == id, label + " preserves aiming and selected weapon near the wall")
		var basis: Basis = _player._weapon_mount.global_basis
		_assert(absf(basis.x.length() - 1.0) < 0.001 and absf(basis.y.length() - 1.0) < 0.001 and absf(basis.z.length() - 1.0) < 0.001, label + " keeps the ballistic root basis unscaled")
		if optic != null:
			_assert(_optic_projection(optic).distance_to(home_projection) < 0.003, label + " preserves the physical optic's screen direction")
		front.queue_free()
		await _settle()
		_assert(_player._weapon_mount.position.distance_to(home_position) < 0.001, label + " restores the original mount after backing away")
		_assert(_player._weapon_mount.scale.distance_to(Vector3.ONE) < 0.001, label + " restores full scale after backing away")
		_assert(_player._camera.position.distance_to(home_camera) < 0.001, label + " preserves original camera compensation")
		var side := _wall(Vector3(0.55, 101.8, 0), Vector3(0.2, 6, 8))
		await _settle()
		bounds = _visible_bounds()
		_assert(_maximum(bounds, 0) <= 0.445, label + " stays outside a reachable side wall")
		side.queue_free()
		await _settle()
	# Both constraints must hold when the player is pressed into a corner.
	_player._set_aiming(false)
	_player._switch_weapon(&"rifle")
	var corner_front := _wall(Vector3(0, 101.8, -0.55), Vector3(8, 6, 0.2))
	var corner_side := _wall(Vector3(0.55, 101.8, 0), Vector3(0.2, 6, 8))
	await _settle()
	var corner := _visible_bounds()
	_assert(_minimum(corner, 2) >= -0.445 and _maximum(corner, 0) <= 0.445, "rifle remains outside both surfaces at a wall corner")
	corner_front.queue_free()
	corner_side.queue_free()
	await _settle()
	await _shoot_and_reload_checks()
	_world.queue_free()
	await process_frame
	print("test_viewmodel_wall_clearance: %d assertions, %d failures; COMPLETED" % [_assertions, _failures])
	quit(1 if _failures else 0)


func _settle() -> void:
	await physics_frame
	await physics_frame
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw


func _wall(at: Vector3, dimensions: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collision.shape = shape
	wall.add_child(collision)
	_world.add_child(wall)
	wall.global_position = at
	return wall


func _visible_optic() -> Marker3D:
	for node in _player._weapon_mount.find_children("OpticAim", "Marker3D", true, false):
		var marker := node as Marker3D
		if marker.is_visible_in_tree():
			return marker
	return null


func _optic_projection(marker: Marker3D) -> Vector2:
	var point: Vector3 = _player._camera.global_transform.affine_inverse() * marker.global_position
	return Vector2(point.x, point.y) / maxf(-point.z, 0.00001)


func _long_gun_open_floor_checks() -> void:
	# A real floor exposes arm pose growth that an empty high-altitude world hides.
	var floor_body := _wall(Vector3(0, 99.5, 0), Vector3(20, 1, 20))
	for pair: Array in [[&"shotgun", "Shotgun"], [&"spas12", "Spas12"]]:
		_state.weapon_unlocked[pair[0]] = true
		_player._switch_weapon(pair[0])
		_assert(_state.current_weapon == pair[0], "open-floor fixture equips the actual " + String(pair[0]))
		var weapon = _player.get_node("Camera3D/WeaponMount/" + pair[1])
		var player_processing: bool = _player.is_processing()
		var weapon_processing: bool = weapon.is_processing()
		_player.set_process(false)
		weapon.set_process(false)
		await physics_frame
		await physics_frame
		for stage: String in ["hip", "ADS", "stable ADS", "return"]:
			_player._set_aiming(stage.contains("ADS"))
			# Multiple normal-framerate IK updates, including after ADS has settled.
			for frame in 24:
				_player._restore_viewmodel_depth()
				weapon._process(1.0 / 60.0)
				_player._process(1.0 / 60.0)
			await RenderingServer.frame_post_draw
			var label := String(pair[0]) + " open-floor " + stage
			_assert_pose_bounds_contain_baked_vertices(label)
			var points := _visible_bounds()
			_assert(not points.is_empty() and _minimum(points, 1) > 100.02, label + " actual posed gun and arms clear the floor")
			_assert(is_equal_approx(_player._viewmodel_depth_scale, 1.0), label + " retains full display scale without nearby walls")
		_player.set_process(player_processing)
		weapon.set_process(weapon_processing)
	floor_body.queue_free()
	await _settle()


func _assert_pose_bounds_contain_baked_vertices(label: String) -> void:
	for node in _player._weapon_mount.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if not instance.is_visible_in_tree() or instance.mesh == null or instance.get_skin_reference() == null:
			continue
		# Compare production's CPU estimate with independent renderer-skinned vertices.
		var estimate: AABB = _player._viewmodel_skin_bounds.get_pose_bounds(instance).grow(0.00005)
		var posed := instance.bake_mesh_from_current_skeleton_pose()
		var contains_all := posed != null and posed.get_surface_count() > 0
		var vertex_count := 0
		if contains_all:
			for surface in posed.get_surface_count():
				var arrays := posed.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				vertex_count += vertices.size()
				for vertex in vertices:
					contains_all = contains_all and estimate.has_point(vertex)
		_assert(contains_all and vertex_count > 0, label + " production pose bounds contain every independently baked vertex of " + String(instance.name))


func _shoot_and_reload_checks() -> void:
	_player._set_aiming(false)
	_player._switch_weapon(&"rifle")
	var side := _wall(Vector3(0.55, 101.8, 0), Vector3(0.2, 6, 8))
	await _settle()
	var rifle = _player.get_node("Camera3D/WeaponMount/Rifle")
	# Remove random spread only in this fixture; use the real weapon's shot path.
	rifle.weapon_data = rifle.weapon_data.duplicate()
	rifle.weapon_data.spread_hip = 0.0
	rifle.weapon_data.spread_aim = 0.0
	rifle.weapon_data.recoil_pitch = 0.0
	var target := DamageTarget.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2, 4, 1)
	collision.shape = shape
	target.add_child(collision)
	_world.add_child(target)
	target.global_position = Vector3(0, 101.8, -90)
	await physics_frame
	await physics_frame
	Chamber.set_total(_state, &"rifle", 3)
	_assert(rifle._fire(), "real rifle can fire while the side wall compresses its viewmodel")
	_assert(target.hits.size() == 1, "near-wall display compression retains a real 90m hitscan hit")
	_assert(Chamber.total(_state, &"rifle") == 2, "near-wall firing consumes exactly one round")
	Chamber.set_total(_state, &"rifle", 0)
	_state.rifle_reserve = 90
	rifle._start_reload()
	await create_timer(0.06).timeout
	_assert(rifle._is_reloading, "real reload starts while standing beside the wall")
	_player._switch_weapon(&"shotgun")
	await _settle()
	_assert(not rifle._is_reloading, "near-wall weapon switching preserves reload cancellation")
	_assert(_maximum(_visible_bounds(), 0) <= 0.445, "switching weapons beside the wall does not expose intersecting geometry")
	await create_timer(rifle.weapon_data.reload_time + 0.05).timeout
	_assert(Chamber.total(_state, &"rifle") == 0 and _state.rifle_reserve == 90, "cancelled reload timer cannot transfer ammunition after the switch")
	_player._switch_weapon(&"rifle")
	await _settle()
	rifle._start_reload()
	var safe_animation := true
	var visible_animation := true
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(rifle.weapon_data.reload_time * 1000.0 + 80.0):
		await RenderingServer.frame_post_draw
		var points := _visible_bounds()
		safe_animation = safe_animation and _maximum(points, 0) <= 0.445
		visible_animation = visible_animation and not points.is_empty()
	_assert(safe_animation and visible_animation, "complete real reload animation remains visible and outside the wall")
	_assert(Chamber.total(_state, &"rifle") == rifle.weapon_data.mag_size and _state.rifle_reserve == 90 - rifle.weapon_data.mag_size, "near-wall reload completes with the original ammunition transfer")
	await _settle()
	var weapon_transform: Transform3D = rifle._weapon_node.transform
	side.queue_free()
	target.queue_free()
	await _settle()
	_assert(rifle._weapon_node.transform.origin.distance_to(weapon_transform.origin) < 0.001, "backing away after reload does not accumulate a weapon pose offset")


func _visible_bounds() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for node in _player._weapon_mount.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if not instance.is_visible_in_tree() or instance.mesh == null:
			continue
		# The guidance beam is a world-space VFX ray, not the held gun or arms.
		if String(instance.name).to_lower().contains("laser"):
			continue
		if instance.get_skin_reference() != null:
			# Independent render-server snapshot: production uses cached bone influence
			# bounds instead. Raw source meshes can be in centimetres before skinning.
			var posed := instance.bake_mesh_from_current_skeleton_pose()
			if posed == null or posed.get_surface_count() == 0:
				_assert(false, "visible skinned mesh has no posed snapshot: " + String(instance.name))
				continue
			var world_bounds := AABB()
			var has_vertices := false
			for surface in posed.get_surface_count():
				var arrays := posed.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for vertex in vertices:
					var world_point: Vector3 = instance.global_transform * vertex
					world_bounds = world_bounds.expand(world_point) if has_vertices else AABB(world_point, Vector3.ZERO)
					has_vertices = true
			if not has_vertices:
				_assert(false, "visible skinned mesh has an empty posed vertex buffer: " + String(instance.name))
				continue
			for i in 8:
				points.append(world_bounds.position + world_bounds.size * Vector3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1)))
			continue
		var box := instance.get_aabb()
		for i in 8:
			var p := box.position + box.size * Vector3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1))
			points.append(instance.global_transform * p)
	return points


func _minimum(points: Array[Vector3], axis: int) -> float:
	var value := INF
	for point in points:
		value = minf(value, point[axis])
	return value


func _maximum(points: Array[Vector3], axis: int) -> float:
	var value := -INF
	for point in points:
		value = maxf(value, point[axis])
	return value


func _timeout() -> void:
	push_error("test_viewmodel_wall_clearance timed out before completing all cases")
	quit(1)
