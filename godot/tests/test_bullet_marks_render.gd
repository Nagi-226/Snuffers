extends SceneTree

const OUTPUT_DIR := "res://tmp_shots/bullet_marks"
const SURFACES := [
	["wall", Vector3(3.5, 1.3, 20), Vector3(8.0, 1.3, 20)],
	["wall_opposite", Vector3(-3, 1.3, 26), Vector3(-8, 1.3, 26)],
	["ground", Vector3(0, 3.0, 24), Vector3(0, -1, 24)],
	["metal_gate", Vector3(18.5, 1.4, 5), Vector3(24, 1.4, 5)],
	["car_side", Vector3(0, 0.6, -12), Vector3(4.5, 0.6, -12)],
	["car_front", Vector3(3.6, 0.6, -17), Vector3(3.6, 0.6, -11)],
	["police_side", Vector3(0, 0.6, -88), Vector3(3.5, 0.6, -88)],
	["police_front", Vector3(2.6, 0.6, -93), Vector3(2.6, 0.6, -87)],
]

var _failures := 0
var _assertions := 0
var _world: Node3D
var _player
var _fx: Node3D
var _camera: Camera3D
var _state
var _directory := ""
var _completed := 0
var _hits: Array[Dictionary] = []


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
	create_timer(100.0).timeout.connect(_timeout)
	_assert(DisplayServer.get_name() != "headless", "bullet visibility is checked with native rendering")
	if _failures:
		quit(1)
		return
	root.size = Vector2i(1600, 900)
	_directory = ProjectSettings.globalize_path(OUTPUT_DIR)
	if DirAccess.make_dir_recursive_absolute(_directory) != OK:
		_abort("cannot create render evidence directory")
		return
	_state = root.get_node("GameState")
	_state.reset()
	_world = (load("res://scenes/levels/street_playable.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	current_scene = _world
	for frame in 20:
		await process_frame
	_player = _world.get_node("Player")
	_fx = _player.get_node("PlayerCombatFx")
	for node in _world.find_children("*", "Node", true, false):
		node.set_process(false)
		node.set_physics_process(false)
		node.set_process_unhandled_input(false)
	for actor in _world.find_children("*", "CharacterBody3D", true, false):
		if actor != _player:
			actor.collision_layer = 0
	var street := _world.get_node("StreetTest")
	var driver = street.get_node("StreetDayNightDriver")
	driver.set_mode(driver.Mode.DAY)
	var environment: Environment = street.get_node("WorldEnvironment").environment
	# Fixed test lighting reveals real surface marks without changing production assets.
	environment.fog_enabled = false
	environment.volumetric_fog_enabled = false
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.9, 1)
	environment.ambient_light_energy = 1.0
	_world.get_node("HUD").visible = false
	_player.global_position = Vector3(0, 100, 0)
	_player._weapon_mount.visible = false
	_camera = Camera3D.new()
	_world.add_child(_camera)
	_camera.current = true
	_camera.fov = 50.0
	_camera.near = 0.02
	for id in _state.weapon_unlocked:
		_state.weapon_unlocked[id] = true
	root.get_node("Events").bullet_impacted.connect(_record_hit)
	await physics_frame
	await physics_frame
	await _all_hitscan_weapons()
	for view: Array in SURFACES:
		await _surface_view(view)
	root.get_node("Events").bullet_impacted.disconnect(_record_hit)
	_assert(_completed == SURFACES.size(), "all wall, ground, gate, and vehicle views completed")
	print("test_bullet_marks_render: %d assertions, %d failures; COMPLETED views=%d" % [_assertions, _failures, _completed])
	_world.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_player = null
	_fx = null
	_camera = null
	_world = null
	_hits.clear()
	quit(1 if _failures else 0)


func _record_hit(pos: Vector3, normal: Vector3, _metal: bool) -> void:
	_hits.append({"position": pos, "normal": normal})


func _marks() -> Array[Decal]:
	var result: Array[Decal] = []
	for node in _world.find_children("*", "Decal", true, false):
		result.append(node as Decal)
	return result


func _hide_other_fx() -> void:
	for node in _fx.get_children():
		if node is Decal:
			continue
		if node is VisualInstance3D or node is Light3D:
			node.visible = false


func _weapon(id: StringName) -> Node3D:
	for node in _player._weapon_mount.get_children():
		if node.get("weapon_data") != null and node.weapon_data.weapon_id == id:
			return node as Node3D
	return null


func _fire_at(id: StringName, from: Vector3, toward: Vector3) -> bool:
	_player._set_aiming(false)
	_player._switch_weapon(id)
	_state.fire_modes[id] = &"semi"
	var weapon := _weapon(id)
	if weapon == null:
		return false
	weapon.set_process(false)
	weapon.set_physics_process(false)
	_player._weapon_mount.visible = false
	_state.set(String(id) + "_mag", weapon.weapon_data.mag_size)
	weapon.set("_is_reloading", false)
	var data: WeaponData = weapon.weapon_data
	var saved := Vector3(data.spread_hip, data.spread_aim, data.spread_prone)
	var recoil := data.recoil_pitch
	data.spread_hip = 0.0
	data.spread_aim = 0.0
	data.spread_prone = 0.0
	# The ballistic path is real. Remove only test recoil so pre-cast camera kick
	# cannot move a manually positioned weapon far from its frozen owner.
	data.recoil_pitch = 0.0
	_player._pitch = 0.0
	_player._camera.rotation = Vector3.ZERO
	var up := Vector3.FORWARD if absf((toward - from).normalized().dot(Vector3.UP)) > 0.95 else Vector3.UP
	weapon.look_at_from_position(from, toward, up)
	var fired: bool = weapon.call("_fire")
	data.spread_hip = saved.x
	data.spread_aim = saved.y
	data.spread_prone = saved.z
	data.recoil_pitch = recoil
	_hide_other_fx()
	return fired


func _all_hitscan_weapons() -> void:
	var checked := 0
	for node in _player._weapon_mount.get_children():
		if node.get("weapon_data") == null or node.weapon_data.kind != WeaponData.Kind.HITSCAN:
			continue
		if node.get_script().resource_path == "res://scripts/weapons/grenade_launcher_controller.gd":
			# EM-40T-1 inherits the hitscan data kind but _fire launches EC-40.
			_assert(node.weapon_data.projectile_scene != null,
				"dedicated EM-40T-1 grenade launcher retains its projectile path")
			continue
		var id: StringName = node.weapon_data.weapon_id
		var before := _marks().size()
		_hits.clear()
		var fired := _fire_at(id, Vector3(3.5, 1.3, 20), Vector3(8, 1.3, 20))
		var expected: int = node.weapon_data.pellet_count
		_assert(fired and _hits.size() == expected, "%s real firing emits one impact per hitscan pellet" % id)
		_assert(_marks().size() - before == expected, "%s real environment firing creates every bullet mark" % id)
		checked += 1
	_assert(checked >= 15, "actual firing checks cover all hitscan weapon platforms")
	for mark in _marks():
		mark.visible = false


func _surface_view(view: Array) -> void:
	var label: String = view[0]
	var from: Vector3 = view[1]
	var toward: Vector3 = view[2]
	var ray := PhysicsRayQueryParameters3D.create(from, toward)
	ray.collide_with_areas = true
	var hit := _world.get_world_3d().direct_space_state.intersect_ray(ray)
	_assert(not hit.is_empty(), label + " view has a real scene collision")
	if hit.is_empty():
		return
	var receiver := hit.collider as Node3D
	print("BULLET_RENDER_RECEIVER ", label, " collider=", receiver.get_path(), " pos=", hit.position, " normal=", hit.normal)
	if label.begins_with("wall"):
		_assert(String(receiver.get_path()).contains("/Buildings/"), label + " hits an actual building wall rather than a street lamp")
	var up := Vector3.FORWARD if absf(hit.normal.dot(Vector3.UP)) > 0.95 else Vector3.UP
	_camera.look_at_from_position(hit.position + hit.normal * 1.5, hit.position, up)
	_hits.clear()
	var fired := _fire_at(&"rifle", from, toward)
	_assert(fired and _hits.size() == 1, label + " uses a real rifle shot into the scene receiver")
	if _hits.size() == 1:
		var point: Vector3 = _hits[0].position
		var normal: Vector3 = _hits[0].normal
		print("BULLET_RENDER_ACTUAL ", label, " pos=", point, " normal=", normal,
			" fixture_delta=", point.distance_to(hit.position))
		_assert(point.distance_to(hit.position) < 0.001 and normal.dot(hit.normal) > 0.999,
			label + " actual weapon ray matches the expected scene hit point and normal")
	var marks := _marks()
	var visible: Array[Decal] = []
	for mark in marks:
		if mark.visible:
			visible.append(mark)
	_assert(visible.size() == 1, label + " has one visible newly generated mark")
	for mark in visible:
		print("BULLET_RENDER_MARK ", label, " parent=", mark.get_parent().get_path(),
			" pos=", mark.global_position, " normal=", mark.global_basis.y)
	var full: Image = await _capture(label + "_marked")
	for mark in visible:
		mark.visible = false
	var absent: Image = await _capture(label + "_unmarked")
	if full == null or absent == null:
		return
	var center := _camera.unproject_position(hit.position)
	var difference := _difference(full, absent, center)
	_assert(difference.count >= 12 and difference.mass > 1.0,
		label + " actual surface shows a bullet hole (%d changed pixels, %.3f mass)" % [difference.count, difference.mass])
	for mark in visible:
		mark.visible = true
	var stable := visible[0].global_transform if not visible.is_empty() else Transform3D.IDENTITY
	_player.global_position += Vector3(2, 0, 3)
	_player.rotation.y += 0.3
	_fx.call("_process", 0.0)
	_assert(not visible.is_empty() and visible[0].global_transform.is_equal_approx(stable),
		label + " mark remains anchored while the player moves and turns")
	if label in ["wall", "car_side"] and not visible.is_empty():
		_camera.global_position += _camera.global_basis.x * 0.3
		_camera.look_at(hit.position, up)
		var angle_full: Image = await _capture(label + "_changed_view_marked")
		for mark in visible:
			mark.visible = false
		var angle_empty: Image = await _capture(label + "_changed_view_unmarked")
		if angle_full != null and angle_empty != null:
			var angle_difference := _difference(angle_full, angle_empty, _camera.unproject_position(hit.position))
			_assert(visible[0].global_transform.is_equal_approx(stable)
				and angle_difference.count >= 12 and angle_difference.mass > 1.0,
				label + " changed camera angle keeps the rendered hole on the same physical surface")
	for mark in visible:
		mark.visible = false
	_completed += 1


func _capture(label: String) -> Image:
	for frame in 8:
		await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	if result == null or result.is_empty():
		_abort("renderer returned an empty image")
		return null
	if result.save_png(_directory.path_join(label + ".png")) != OK:
		_abort("cannot save render image " + label)
		return null
	return result


func _difference(first: Image, second: Image, center: Vector2) -> Dictionary:
	var mass := 0.0
	var count := 0
	var px := int(center.x)
	var py := int(center.y)
	for y in range(maxi(0, py - 80), mini(first.get_height(), py + 80)):
		for x in range(maxi(0, px - 80), mini(first.get_width(), px + 80)):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
			mass += delta
			if delta > 0.025:
				count += 1
	return {"mass": mass, "count": count}


func _abort(reason: String) -> void:
	push_error("BULLET_RENDER_ABORT: " + reason)
	quit(1)


func _timeout() -> void:
	_abort("native bullet mark rendering did not finish all views")
