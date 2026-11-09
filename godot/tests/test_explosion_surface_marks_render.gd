extends SceneTree

const OUTPUT_DIR := "res://tmp_shots/explosion_surface_marks"
const SURFACES := [
	["wall", Vector3(3.5, 1.3, 20), Vector3(8, 1.3, 20)],
	["wall_opposite", Vector3(-3, 1.3, 26), Vector3(-8, 1.3, 26)],
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
var _directory := ""
var _completed := 0
var _hits: Array[Dictionary] = []
var _explosions := 0


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
	_assert(DisplayServer.get_name() != "headless", "explosion surface visibility is checked with native rendering")
	if _failures:
		quit(1)
		return
	root.size = Vector2i(1600, 900)
	_directory = ProjectSettings.globalize_path(OUTPUT_DIR)
	if DirAccess.make_dir_recursive_absolute(_directory) != OK:
		_abort("cannot create render evidence directory")
		return
	var state := root.get_node("GameState")
	state.reset()
	_world = (load("res://scenes/levels/street_playable.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	current_scene = _world
	for frame in 20:
		await process_frame
	_player = _world.get_node("Player")
	_fx = _player.get_node("ExplosionFx")
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
	var events := root.get_node("Events")
	events.connect("explosion_surface_impacted", _record_hit)
	events.rpg_exploded.connect(_record_explosion)
	await physics_frame
	await physics_frame
	for spec in [
		["grenade", "res://scenes/weapons/rpg_projectile.tscn", "res://scenes/weapons/em40t1.tres"],
		["missile", "res://scenes/weapons/ec120_projectile.tscn", "res://scenes/weapons/em120r.tres"],
	]:
		for view: Array in SURFACES:
			await _surface_view(spec, view)
	events.disconnect("explosion_surface_impacted", _record_hit)
	events.rpg_exploded.disconnect(_record_explosion)
	_assert(_completed == SURFACES.size() * 2, "both projectile types complete every real wall and vehicle render view")
	print("test_explosion_surface_marks_render: %d assertions, %d failures; COMPLETED views=%d" % [_assertions, _failures, _completed])
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


func _record_hit(pos: Vector3, normal: Vector3, receiver: Node3D) -> void:
	_hits.append({"position": pos, "normal": normal, "receiver": receiver})


func _record_explosion(_pos: Vector3) -> void:
	_explosions += 1


func _marks() -> Array[Decal]:
	var result: Array[Decal] = []
	for node in _world.find_children("*", "Decal", true, false):
		result.append(node as Decal)
	return result


func _surface_view(spec: Array, view: Array) -> void:
	var label: String = spec[0] + "_" + view[0]
	var from: Vector3 = view[1]
	var toward: Vector3 = view[2]
	var ray := PhysicsRayQueryParameters3D.create(from, toward)
	ray.collide_with_areas = true
	var hit := _world.get_world_3d().direct_space_state.intersect_ray(ray)
	_assert(not hit.is_empty(), label + " has a real scene collision")
	if hit.is_empty():
		return
	var receiver := hit.collider as Node3D
	print("SCORCH_RENDER_RECEIVER ", label, " receiver=", receiver.get_path(), " point=", hit.position, " normal=", hit.normal)
	if String(view[0]).begins_with("wall"):
		_assert(String(receiver.get_path()).contains("/Buildings/"), label + " hits an actual building wall")
	for old in _marks():
		old.visible = false
	_hits.clear()
	_explosions = 0
	var data := load(spec[2]).duplicate() as WeaponData
	data.projectile_gravity = 0.0
	root.get_node("GameState").em120r_aim_point = toward
	var projectile := (load(spec[1]) as PackedScene).instantiate() as Node3D
	_world.add_child(projectile)
	projectile.global_position = from
	var excludes: Array[RID] = []
	projectile.call("setup", (toward - from).normalized(), excludes, data)
	var started := Time.get_ticks_msec()
	while is_instance_valid(projectile) and Time.get_ticks_msec() - started < 1500:
		await physics_frame
		await process_frame
	_assert(not is_instance_valid(projectile) and _explosions == 1 and _hits.size() == 1,
		label + " real projectile flight creates one explosion and one surface event")
	if is_instance_valid(projectile):
		projectile.queue_free()
		await process_frame
	if _hits.size() == 1:
		_assert(_hits[0].receiver == receiver and _hits[0].position.distance_to(hit.position) < 0.001
			and _hits[0].normal.dot(hit.normal) > 0.999,
			label + " real projectile hit agrees with the independently queried scene surface")
		print("SCORCH_RENDER_ACTUAL ", label, " point=", _hits[0].position, " normal=", _hits[0].normal)
	var visible: Array[Decal] = []
	for mark in _marks():
		if mark.visible:
			visible.append(mark)
	_assert(visible.size() == 1, label + " creates exactly one visible scorch Decal")
	if visible.is_empty():
		return
	var mark := visible[0]
	_assert(mark.get_parent() == receiver and mark.global_position.distance_to(hit.position) < 0.5,
		label + " anchors its scorch to the actual nearby receiver skin")
	print("SCORCH_RENDER_MARK ", label, " point=", mark.global_position, " normal=", mark.global_basis.y)
	# Isolate the persistent surface mark after the real collision, excluding fire/smoke pixels.
	_fx.call("_process", 2.0)
	for child in _fx.get_children():
		if child is Node3D:
			child.visible = false
	var up := Vector3.FORWARD if absf(hit.normal.dot(Vector3.UP)) > 0.95 else Vector3.UP
	_camera.look_at_from_position(hit.position + hit.normal * 1.5, hit.position, up)
	var marked := await _capture(label + "_marked")
	mark.visible = false
	var unmarked := await _capture(label + "_unmarked")
	if marked == null or unmarked == null:
		return
	var difference := _difference(marked, unmarked, _camera.unproject_position(hit.position))
	_assert(difference.count >= 100 and difference.mass > 20,
		label + " real surface shows a scorch (%d changed pixels, %.3f mass)" % [difference.count, difference.mass])
	mark.visible = true
	var original := mark.global_transform
	_player.global_position += Vector3(2, 0, 3)
	_player.rotation.y += 0.3
	_fx.call("_process", 0.0)
	_assert(mark.global_transform.is_equal_approx(original), label + " stays anchored while the player moves and turns")
	if String(view[0]) in ["wall", "car_side"]:
		_camera.global_position += _camera.global_basis.x * 0.3
		_camera.look_at(hit.position, up)
		var angled_marked := await _capture(label + "_changed_view_marked")
		mark.visible = false
		var angled_empty := await _capture(label + "_changed_view_unmarked")
		if angled_marked != null and angled_empty != null:
			var angled_difference := _difference(angled_marked, angled_empty, _camera.unproject_position(hit.position))
			_assert(mark.global_transform.is_equal_approx(original)
				and angled_difference.count >= 100 and angled_difference.mass > 20,
				label + " retains a visible surface scorch after the camera angle changes")
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
	var count := 0
	var mass := 0.0
	for y in range(maxi(0, int(center.y) - 80), mini(first.get_height(), int(center.y) + 80)):
		for x in range(maxi(0, int(center.x) - 80), mini(first.get_width(), int(center.x) + 80)):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
			mass += delta
			if delta > 0.025:
				count += 1
	return {"count": count, "mass": mass}


func _abort(reason: String) -> void:
	push_error("SCORCH_RENDER_ABORT: " + reason)
	quit(1)


func _timeout() -> void:
	_abort("native explosion surface rendering did not finish all views")
