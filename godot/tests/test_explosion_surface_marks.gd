extends SceneTree

var _failures := 0
var _assertions := 0
var _world: Node3D
var _owner: Node3D
var _receiver: StaticBody3D
var _fx: Node3D
var _surface_hits: Array[Dictionary] = []
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


func _marks() -> Array[Decal]:
	var result: Array[Decal] = []
	for node in _world.find_children("*", "Decal", true, false):
		result.append(node as Decal)
	return result


func _record_surface(pos: Vector3, normal: Vector3, receiver: Node3D) -> void:
	_surface_hits.append({"position": pos, "normal": normal, "receiver": receiver})


func _record_explosion(_pos: Vector3) -> void:
	_explosions += 1


func _run() -> void:
	create_timer(20.0).timeout.connect(_timeout)
	root.get_node("GameState").reset()
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	_owner = Node3D.new()
	_world.add_child(_owner)
	_receiver = StaticBody3D.new()
	_receiver.position = Vector3(0, 100, -2)
	_world.add_child(_receiver)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 8, 0.2)
	shape.shape = box
	_receiver.add_child(shape)
	_fx = load("res://scripts/weapons/explosion_fx.gd").new()
	_owner.add_child(_fx)
	await process_frame
	_fx.set_process(false)
	var events := root.get_node("Events")
	if events.has_signal("explosion_surface_impacted"):
		events.connect("explosion_surface_impacted", _record_surface)
	events.rpg_exploded.connect(_record_explosion)
	await physics_frame
	await physics_frame
	var excludes: Array[RID] = []
	for spec in [
		["grenade", "res://scenes/weapons/rpg_projectile.tscn", "res://scenes/weapons/em40t1.tres"],
		["missile", "res://scenes/weapons/ec120_projectile.tscn", "res://scenes/weapons/em120r.tres"],
	]:
		_surface_hits.clear()
		_explosions = 0
		var data := load(spec[2]).duplicate() as WeaponData
		data.projectile_gravity = 0.0
		var projectile := (load(spec[1]) as PackedScene).instantiate() as Node3D
		_world.add_child(projectile)
		projectile.global_position = Vector3(0, 100, 0)
		projectile.call("setup", Vector3.FORWARD, excludes, data)
		var start := Time.get_ticks_msec()
		while is_instance_valid(projectile) and Time.get_ticks_msec() - start < 1500:
			await physics_frame
			await process_frame
		_assert(_explosions == 1, String(spec[0]) + " real swept collision explodes exactly once")
		_assert(_surface_hits.size() == 1, String(spec[0]) + " real swept collision publishes exactly one surface impact")
		if _surface_hits.size() == 1:
			_assert(_surface_hits[0].receiver == _receiver
				and absf(_surface_hits[0].position.z + 1.9) < 0.001
				and _surface_hits[0].normal.dot(Vector3.BACK) > 0.999,
				String(spec[0]) + " publishes the actual hit receiver, position, and surface normal")
		_surface_hits.clear()
		_explosions = 0
		data = load(spec[2]).duplicate() as WeaponData
		data.projectile_gravity = 0.0
		data.projectile_max_range = 0.01
		projectile = (load(spec[1]) as PackedScene).instantiate() as Node3D
		_world.add_child(projectile)
		projectile.global_position = Vector3(20, 100, 0)
		projectile.call("setup", Vector3.FORWARD, excludes, data)
		start = Time.get_ticks_msec()
		while is_instance_valid(projectile) and Time.get_ticks_msec() - start < 1500:
			await physics_frame
			await process_frame
		_assert(_explosions == 1 and _surface_hits.is_empty(),
			String(spec[0]) + " range expiry explodes in air without inventing a surface impact")
	await _near_wall_clearance()
	# Retain one mark and exercise receiver anchoring, orientation and lifetime.
	if events.has_signal("explosion_surface_impacted"):
		events.emit_signal("explosion_surface_impacted", Vector3(0, 100, -1.9), Vector3.BACK, _receiver)
	else:
		events.rpg_exploded.emit(Vector3(0, 100, -1.9))
	var marks := _marks()
	var active: Decal
	for mark in marks:
		if mark.visible:
			active = mark
	_assert(active != null, "surface explosion leaves a real scorch mark on the wall")
	if active != null:
		_assert(active.global_basis.y.normalized().dot(Vector3.BACK) > 0.999,
			"explosion scorch projects along the hit normal into the wall")
		_assert(is_equal_approx(active.size.x, GameConfig.EXPLOSION_FX_SCORCH_SIZE)
			and is_equal_approx(active.size.z, GameConfig.EXPLOSION_FX_SCORCH_SIZE),
			"explosion scorch preserves its intended diameter on both texture axes")
		var original := active.global_transform
		_owner.position = Vector3(4, 2, 3)
		_owner.rotation.y = 0.4
		_fx.call("_process", 0.0)
		_assert(active.global_transform.is_equal_approx(original),
			"explosion scorch stays fixed when its player/FX owner moves")
		_receiver.position += Vector3(2, 0, 0)
		_fx.call("_process", 0.0)
		_assert(active.global_position.distance_to(original.origin + Vector3(2, 0, 0)) < 0.001,
			"explosion scorch follows a moving surface receiver")
		_fx.call("_process", 59.9)
		_assert(is_instance_valid(active) and active.is_visible_in_tree(), "explosion scorch survives until its full minute")
		_fx.call("_process", 0.11)
		_assert(not is_instance_valid(active) or not active.is_visible_in_tree(), "explosion scorch disappears after sixty seconds")
	if events.has_signal("explosion_surface_impacted"):
		events.disconnect("explosion_surface_impacted", _record_surface)
	events.rpg_exploded.disconnect(_record_explosion)
	_receiver.queue_free()
	await process_frame
	_fx.call("_process", 0.0)
	var remaining := 0
	for mark in _marks():
		if mark.is_visible_in_tree():
			remaining += 1
	_assert(remaining == 0, "receiver deletion cleans all explosion surface marks")
	if events.has_signal("explosion_surface_impacted"):
		await _pool_lifecycle(events)
	print("test_explosion_surface_marks: %d assertions, %d failures; COMPLETED" % [_assertions, _failures])
	_world.queue_free()
	await process_frame
	quit(1 if _failures else 0)


func _near_wall_clearance() -> void:
	var launcher = (load("res://scenes/weapons/em120r.tscn") as PackedScene).instantiate()
	_world.add_child(launcher)
	launcher.global_position = Vector3(0, 100, 0)
	launcher.set_process(false)
	launcher.set_physics_process(false)
	var muzzle: Marker3D = launcher.get("_muzzle_node")
	muzzle.global_position = Vector3(0, 100, -3)
	var state := root.get_node("GameState")
	state.current_weapon = &"em120r"
	state.em120r_guidance_mode = &"laser"
	state.em120r_mag = 10
	state.em120r_aim_point = Vector3(0, 100, -20)
	root.get_node("Events").ec120_aim_origin_changed.emit(Vector3(0, 100, 0))
	_surface_hits.clear()
	_explosions = 0
	var fired: bool = launcher.call("_fire")
	await physics_frame
	await process_frame
	_assert(fired and _explosions == 1 and _surface_hits.size() == 1,
		"Longbow's real obstructed camera-to-muzzle clearance emits exactly one surface impact and explosion")
	if _surface_hits.size() == 1:
		_assert(_surface_hits[0].receiver == _receiver
			and _surface_hits[0].position.distance_to(Vector3(0, 100, -1.9)) < 0.001
			and _surface_hits[0].normal.dot(Vector3.BACK) > 0.999,
			"Longbow near-wall clearance preserves the actual wall's point, normal, and receiver")
	launcher.queue_free()
	await process_frame


func _active_marks() -> Array[Decal]:
	var result: Array[Decal] = []
	for mark in _marks():
		if mark.is_visible_in_tree():
			result.append(mark)
	return result


func _pool_lifecycle(events: Node) -> void:
	var first_receiver := StaticBody3D.new()
	_world.add_child(first_receiver)
	var second_receiver := StaticBody3D.new()
	_world.add_child(second_receiver)
	var point := Vector3(0, 100, -2)
	events.emit_signal("explosion_surface_impacted", point, Vector3.BACK, first_receiver)
	var visible := _active_marks()
	_assert(visible.size() == 1, "a surviving receiver accepts scorch marks after the original receiver is deleted")
	if visible.is_empty():
		return
	var expired_id := visible[0].get_instance_id()
	var allocated := _marks().size()
	_fx.call("_process", 60.01)
	events.emit_signal("explosion_surface_impacted", point, Vector3.BACK, first_receiver)
	visible = _active_marks()
	_assert(visible.size() == 1 and visible[0].get_instance_id() == expired_id
		and _marks().size() == allocated,
		"an expired inactive scorch is reused without allocating another Decal")
	var oldest := visible[0]
	for index in range(1, GameConfig.EXPLOSION_FX_SCORCH_POOL):
		events.emit_signal("explosion_surface_impacted", point + Vector3(index, 0, 0), Vector3.BACK, first_receiver)
	_assert(_active_marks().size() == GameConfig.EXPLOSION_FX_SCORCH_POOL,
		"scorch pool fills to its configured capacity with distinct active marks")
	_fx.call("_process", 59.9)
	events.emit_signal("explosion_surface_impacted", point, Vector3.BACK, second_receiver)
	_assert(_marks().size() == GameConfig.EXPLOSION_FX_SCORCH_POOL
		and oldest.get_parent() == second_receiver and oldest.is_visible_in_tree(),
		"a full scorch pool reuses its oldest Decal and reparents it to the new receiver")
	_fx.call("_process", 0.11)
	_assert(_active_marks().size() == 1 and oldest.is_visible_in_tree(),
		"FIFO scorch reuse restarts a full minute while unreused marks expire")
	first_receiver.queue_free()
	await process_frame
	_fx.call("_process", 0.0)
	var pool: Array = _fx.get("_scorches")
	_assert(pool.size() == 1 and is_instance_valid(oldest) and oldest.get_parent() == second_receiver,
		"deleting the old receiver removes its freed marks from the pool and preserves the reparented scorch")
	if not is_instance_valid(oldest):
		return
	_fx.call("_process", 59.79)
	_assert(oldest.is_visible_in_tree(), "the reused scorch stays visible until 59.9 seconds of its new lifetime")
	_fx.call("_process", 0.11)
	_assert(not oldest.is_visible_in_tree(), "the reused scorch expires after its own restarted sixty-second deadline")
	events.emit_signal("explosion_surface_impacted", point, Vector3.BACK, second_receiver)
	_assert(_active_marks().size() == 1, "an expired reused scorch can be activated again")
	_fx.queue_free()
	await process_frame
	_assert(_marks().is_empty() and is_instance_valid(second_receiver),
		"deleting the FX owner cleans its receiver-bound Decals without deleting the surviving receiver")


func _timeout() -> void:
	push_error("test_explosion_surface_marks timed out")
	quit(1)
