extends SceneTree

var _failures := 0
var _assertions := 0
var _world: Node3D
var _owner: Node3D
var _receiver: StaticBody3D
var _fx: Node3D


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


func _emit_mark(pos: Vector3, normal: Vector3, receiver: Node3D = null) -> void:
	var events := root.get_node("Events")
	var destination := receiver if receiver != null else _receiver
	# RED remains runnable before the new receiver-aware contract exists.
	if events.has_signal("bullet_mark_requested") \
			and not events.get_signal_connection_list("bullet_mark_requested").is_empty():
		events.emit_signal("bullet_mark_requested", pos, normal, destination)
	else:
		events.emit_signal("bullet_impacted", pos, normal, false)


func _run() -> void:
	create_timer(80.0).timeout.connect(_timeout)
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	_owner = Node3D.new()
	_world.add_child(_owner)
	_receiver = StaticBody3D.new()
	_receiver.name = "MetalReceiver"
	_world.add_child(_receiver)
	_fx = load("res://scripts/weapons/player_combat_fx.gd").new()
	_owner.add_child(_fx)
	await process_frame
	_fx.set_process(false)
	var point := Vector3(4.0, 1.2, -8.0)
	var normal := Vector3.BACK
	_emit_mark(point, normal)
	var marks := _marks()
	_assert(marks.size() == 1, "environment impact creates exactly one real Decal")
	if marks.is_empty():
		_finish()
		return
	var mark := marks[0]
	_assert(mark.texture_albedo != null, "bullet mark carries its procedural texture")
	_assert(mark.global_basis.y.normalized().dot(normal) > 0.999,
		"Decal local +Y faces the surface normal so -Y projects into the wall")
	_assert(is_equal_approx(mark.size.x, GameConfig.BULLET_DECAL_SIZE)
		and is_equal_approx(mark.size.z, GameConfig.BULLET_DECAL_SIZE),
		"Decal has full bullet-hole width on both texture axes X/Z")
	var original := mark.global_transform
	_owner.position = Vector3(-3, 2, 5)
	_owner.rotation = Vector3(0.3, 1.1, -0.2)
	_fx.call("_process", 0.0)
	_assert(mark.global_transform.is_equal_approx(original),
		"moving and turning the player leaves the wall mark fixed in world space")
	_receiver.position = Vector3(2, -1, 3)
	_fx.call("_process", 0.0)
	_assert(mark.global_position.distance_to(original.origin + _receiver.position) < 0.001,
		"moving a hit vehicle carries the mark with its receiver")
	_receiver.rotation.y = 0.4
	_fx.call("_process", 0.0)
	var local_point := original.origin
	_assert(mark.global_position.distance_to(_receiver.global_transform * local_point) < 0.001,
		"rotating a hit vehicle preserves the mark's receiver-local anchor")
	_fx.call("_process", 59.9)
	_assert(is_instance_valid(mark) and mark.is_visible_in_tree(),
		"bullet mark remains visible before its full sixty-second lifetime")
	_fx.call("_process", 0.11)
	_assert(not is_instance_valid(mark) or not mark.is_visible_in_tree(),
		"bullet mark disappears once sixty seconds have elapsed")
	if is_instance_valid(mark):
		await process_frame
	var pool: int = GameConfig.BULLET_DECAL_POOL
	for index in pool:
		_emit_mark(Vector3(float(index) * 0.2, 1, -8), normal)
	_fx.call("_process", 59.0)
	var reused_receiver := StaticBody3D.new()
	_world.add_child(reused_receiver)
	_emit_mark(Vector3(0, 2, -8), normal, reused_receiver)
	_assert(_marks().size() <= pool, "FIFO never allocates more than the configured Decal limit")
	_fx.call("_process", 1.1)
	var surviving := 0
	for item in _marks():
		if item.is_visible_in_tree():
			surviving += 1
	_assert(surviving == 1, "FIFO reused mark gets a fresh sixty seconds while old marks expire")
	_receiver.queue_free()
	await process_frame
	_fx.call("_process", 0.0)
	var reparented := 0
	for item in _marks():
		if item.is_visible_in_tree() and item.get_parent() == reused_receiver:
			reparented += 1
	_assert(reparented == 1, "FIFO mark reused on another receiver survives deletion of the old receiver")
	_receiver = reused_receiver
	_fx.call("_process", 59.0)
	var visible_after := 0
	for item in _marks():
		if item.is_visible_in_tree():
			visible_after += 1
	_assert(visible_after == 0, "reused mark eventually expires at its own new deadline")
	_emit_mark(point, normal)
	_receiver.queue_free()
	await process_frame
	_fx.call("_process", 0.1)
	var orphan_visible := 0
	for item in _marks():
		if item.is_visible_in_tree():
			orphan_visible += 1
	_assert(orphan_visible == 0, "deleting a hit object removes its marks without invalid-object errors")
	var second_receiver := StaticBody3D.new()
	_world.add_child(second_receiver)
	_emit_mark(point, normal, second_receiver)
	_assert(not _marks().is_empty(), "a different receiver can receive marks after the first is deleted")
	_fx.queue_free()
	await process_frame
	var fx_orphans := 0
	for item in _marks():
		if item.is_visible_in_tree():
			fx_orphans += 1
	_assert(fx_orphans == 0 and is_instance_valid(second_receiver),
		"destroying the FX owner removes its anchored marks without deleting the receiver")
	if "--lifetime" in OS.get_cmdline_user_args():
		await _realtime_lifetime(second_receiver)
	_finish()


func _realtime_lifetime(receiver: Node3D) -> void:
	_fx = load("res://scripts/weapons/player_combat_fx.gd").new()
	_owner.add_child(_fx)
	await process_frame
	var started := Time.get_ticks_msec()
	_emit_mark(Vector3(4, 1.2, -8), Vector3.BACK, receiver)
	await create_timer(59.5).timeout
	var visible_before := 0
	for mark in _marks():
		if mark.is_visible_in_tree():
			visible_before += 1
	_assert(visible_before == 1 and Time.get_ticks_msec() - started < 60000,
		"actual running frames keep the mark visible at 59.5 seconds")
	await create_timer(0.8).timeout
	var visible_after := 0
	for mark in _marks():
		if mark.is_visible_in_tree():
			visible_after += 1
	_assert(visible_after == 0 and Time.get_ticks_msec() - started >= 60000,
		"actual running frames remove the mark after sixty real seconds")
	print("BULLET_MARK_REAL_LIFETIME elapsed_msec=", Time.get_ticks_msec() - started)


func _finish() -> void:
	print("test_bullet_marks: %d assertions, %d failures; COMPLETED" % [_assertions, _failures])
	_world.queue_free()
	quit(1 if _failures else 0)


func _timeout() -> void:
	push_error("test_bullet_marks timed out")
	quit(1)
