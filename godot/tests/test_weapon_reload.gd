extends SceneTree

var _failures: int = 0
var _reload_counts: Dictionary = {"rifle": 0, "pistol": 0, "dmr": 0, "shotgun": 0}


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _run() -> void:
	var events = root.get_node("Events")
	events.weapon_reloaded.connect(_on_weapon_reloaded)
	await _check_weapon(&"rifle", "res://scenes/weapons/rifle.tscn", "ViewModel/ArmsEM68A", 2.0, 12, 60)
	await _check_weapon(&"pistol", "res://scenes/weapons/pistol.tscn", "ViewModel/ArmsEM57P", 1.6, 6, 30)
	await _check_weapon(&"dmr", "res://scenes/weapons/dmr.tscn", "ViewModel/Arms", 2.2, 12, 60)
	await _check_weapon(&"shotgun", "res://scenes/weapons/shotgun.tscn", "ViewModel/Arms", 2.4, 7, 40)
	events.weapon_reloaded.disconnect(_on_weapon_reloaded)
	print("test_weapon_reload: %d assertion(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _check_weapon(weapon_id: StringName, scene_path: String, arms_path: NodePath, duration: float, mag: int, reserve: int) -> void:
	var state = root.get_node("GameState")
	state.reset()
	state.current_weapon = weapon_id
	state.set(weapon_id + "_mag", mag)
	state.set(("rifle_reserve" if weapon_id == &"dmr" else weapon_id + "_reserve"), reserve)
	var weapon := (load(scene_path) as PackedScene).instantiate()
	root.add_child(weapon)
	await process_frame
	var players := weapon.get_node(arms_path).find_children("*", "AnimationPlayer", true, false)
	_assert(players.size() == 1, "%s has one native animation player" % weapon_id)
	if players.is_empty():
		weapon.queue_free()
		await process_frame
		return
	var player := players[0] as AnimationPlayer
	var skeletons := weapon.get_node(arms_path).find_children("*", "Skeleton3D", true, false)
	_assert(skeletons.size() == 1, "%s has one native skeleton" % weapon_id)
	_assert(weapon._magazine != null, "%s has a detachable magazine" % weapon_id)
	_assert(weapon._mag_bone >= 0 and weapon._weapon_bone >= 0, "%s resolves native weapon and magazine bones" % weapon_id)
	var visible_arms := 0
	for node in weapon.get_node(arms_path).find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.visible and mi.mesh != null and mi.mesh.resource_name.contains("arms"):
			visible_arms += 1
	_assert(visible_arms > 0, "%s keeps native arm meshes visible" % weapon_id)
	_assert(player.has_animation(&"reload"), "%s has a reload clip" % weapon_id)
	if not player.has_animation(&"reload"):
		weapon.queue_free()
		await process_frame
		return
	_assert(absf(player.get_animation(&"reload").length - duration) < 0.001, "%s reload duration" % weapon_id)

	weapon._start_reload()
	weapon._start_reload()
	_assert(weapon._is_reloading, "%s enters reload state" % weapon_id)
	_assert(player.current_animation == "reload", "%s starts native reload animation" % weapon_id)
	player.advance(duration * 0.25)
	weapon._process(0.0)
	_assert(weapon._magazine.global_position.is_finite(), "%s magazine transform stays finite" % weapon_id)
	await create_timer(duration + 0.1).timeout
	_assert(_reload_counts[weapon_id] == 1, "%s emits reload completion exactly once" % weapon_id)
	_assert(not weapon._is_reloading, "%s leaves reload state" % weapon_id)
	_assert(state.get(weapon_id + "_mag") == weapon.weapon_data.mag_size, "%s refills magazine" % weapon_id)
	_assert(state.get(("rifle_reserve" if weapon_id == &"dmr" else weapon_id + "_reserve")) == reserve - (weapon.weapon_data.mag_size - mag), "%s preserves reserve math" % weapon_id)
	# 原生 Idle 会继续微摆，并带浮点误差；归位容差 1mm / 四元数点积 0.9999。
	_assert(weapon._magazine.position.distance_to(weapon._mag_home_transform.origin) < 0.001, "%s magazine position returns home" % weapon_id)
	var home_q: Quaternion = weapon._mag_home_transform.basis.get_rotation_quaternion()
	var current_q: Quaternion = weapon._magazine.basis.get_rotation_quaternion()
	_assert(absf(home_q.dot(current_q)) > 0.9999, "%s magazine rotation returns home" % weapon_id)
	_assert(weapon._magazine.visible, "%s magazine is visible after reload" % weapon_id)

	state.set(weapon_id + "_mag", mag)
	state.set(("rifle_reserve" if weapon_id == &"dmr" else weapon_id + "_reserve"), reserve)
	weapon._start_reload()
	await create_timer(0.25).timeout
	var other := &"pistol" if weapon_id == &"rifle" else &"rifle"
	state.current_weapon = other
	root.get_node("Events").weapon_switched.emit(other)
	await process_frame
	_assert(not weapon._is_reloading, "%s weapon switch cancels reload state" % weapon_id)
	_assert(player.current_animation != "reload", "%s weapon switch cancels reload animation" % weapon_id)
	await create_timer(duration).timeout
	_assert(_reload_counts[weapon_id] == 1, "%s cancelled reload does not complete later" % weapon_id)
	_assert(state.get(weapon_id + "_mag") == mag, "%s cancelled reload preserves magazine" % weapon_id)
	_assert(state.get(("rifle_reserve" if weapon_id == &"dmr" else weapon_id + "_reserve")) == reserve, "%s cancelled reload preserves reserve" % weapon_id)
	weapon.queue_free()
	await process_frame


func _on_weapon_reloaded(weapon_id: StringName) -> void:
	_reload_counts[weapon_id] += 1
