extends SceneTree

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var district := (load("res://scenes/levels/district_b.tscn") as PackedScene).instantiate()
	root.add_child(district)
	await process_frame
	await physics_frame
	var player := district.get_node("Player")
	var state := root.get_node("GameState")
	if player.get("_big_map") == null:
		_assert(false, "player has a big-map controller")
		_finish(district)
		return
	var map = player._big_map
	map.set_deferred("size", Vector2(1920, 1080))
	_assert(not map.visible, "big map starts closed")
	player._toggle_big_map()
	_assert(map.visible, "big map opens")
	player._toggle_big_map()
	_assert(not map.visible, "big map closes")
	player._toggle_big_map()
	map._refresh_markers()
	_assert(map._enemies.size() == 64, "all 64 enemies are tracked on the live map")
	_assert(map._pickups.size() == 2, "remaining equipment supplies are tracked")
	_assert(map._objectives.size() == 2, "unclaimed DMR and shotgun are current objectives")
	var rect: Rect2 = map._map_rect()
	var center: Vector2 = map.world_to_map(Vector3.ZERO)
	_assert(rect.has_point(center), "world origin maps inside the tactical panel")
	_assert(map.world_to_map(Vector3(-10, 0, 0)).x < center.x, "west maps left")
	_assert(map.world_to_map(Vector3(0, 0, -10)).y < center.y, "north maps up")
	state.weapon_unlocked[&"dmr"] = true
	state.weapon_unlocked[&"shotgun"] = true
	map._refresh_objectives()
	_assert(map._objectives.size() == 1 and map._objectives[0].node.name == &"Link_DistrictBReturn", "completed equipment objective switches to the return gate")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_M
	key.pressed = true
	player._unhandled_input(key)
	_assert(not map.visible, "M key closes the map")
	var pickup = district.get_node("Equipment_dmr")
	pickup.queue_free()
	await process_frame
	map._refresh_markers()
	_assert(map._pickups.size() == 1, "collected supply disappears from the live map")
	_finish(district)


func _finish(district: Node) -> void:
	district.queue_free()
	await process_frame
	print("test_big_map: %d assertion(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
