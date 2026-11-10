extends SceneTree

const WEAPONS := [&"rifle", &"dmr", &"shotgun", &"smg", &"lmg", &"em57s2", &"em86b", &"em86d", &"em86s", &"em86m", &"em12g2", &"em127g", &"em127m", &"em40t1"]

var _assertions := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var state = root.get_node("GameState")
	var maximum_duration := 0.0
	var retired_weapons: Array[Node] = []
	for id in WEAPONS:
		state.reset()
		state.current_weapon = id
		var weapon = (load("res://scenes/weapons/%s.tscn" % id) as PackedScene).instantiate()
		root.add_child(weapon)
		await process_frame
		weapon.set_process(false)
		weapon.set_physics_process(false)
		for frame in 24:
			weapon._process(1.0 / 60.0)
		var skeleton: Skeleton3D = weapon._arms_skeleton
		_assert(skeleton != null and skeleton.get_bone_count() == 60, "%s production scene uses the original 60-joint black arms" % id)
		if skeleton != null:
			_assert(skeleton.find_bone("R_wrist_028") >= 0 and skeleton.find_bone("L_wrist_04") >= 0, "%s resolves the native wrists rather than old rifle control bones" % id)
		var gun: Node3D = weapon._weapon_node
		var home := gun.transform
		var configured_mag = weapon.get("mag_state_property")
		var mag_key: StringName = configured_mag if configured_mag != null else id + "_mag"
		state.set(mag_key, maxi(1, weapon.weapon_data.mag_size / 2))
		var reserve_key: StringName = weapon.reserve_state_property
		if reserve_key == &"":
			reserve_key = id + "_reserve"
		state.set(reserve_key, weapon.weapon_data.mag_size * 2)
		weapon._start_reload()
		maximum_duration = maxf(maximum_duration, weapon.weapon_data.reload_time)
		var animation: AnimationPlayer = weapon._arms_animation
		animation.set_process(false)
		animation.set_physics_process(false)
		var maximum_angle := 0.0
		var maximum_lift := 0.0
		var finite := true
		for step in 61:
			var progress := float(step) / 60.0
			animation.seek(progress * weapon.weapon_data.reload_time, true)
			weapon._process(0.0)
			var angle := home.basis.get_rotation_quaternion().angle_to(gun.basis.get_rotation_quaternion())
			maximum_angle = maxf(maximum_angle, angle)
			maximum_lift = maxf(maximum_lift, gun.position.distance_to(home.origin))
			finite = finite and gun.transform.is_finite()
		_assert(maximum_angle >= deg_to_rad(8.0) and maximum_lift >= 0.015, "%s reload coordinates visible gun cant and lift with the hands and supply part" % id)
		_assert(finite and maximum_angle <= deg_to_rad(30.0) and maximum_lift <= 0.15, "%s reload keeps gun motion finite and bounded" % id)
		state.current_weapon = &"pistol"
		root.get_node("Events").weapon_switched.emit(&"pistol")
		_assert(not weapon._is_reloading and gun.transform.is_equal_approx(weapon._weapon_home), "%s switching cancels motion and restores the authored gun transform" % id)
		retired_weapons.append(weapon)
		await process_frame
	# Keep cancelled coroutine owners alive until their timers return and release references.
	await create_timer(maximum_duration + 0.1).timeout
	for weapon in retired_weapons:
		weapon.queue_free()
	await process_frame
	await process_frame
	print("NATIVE_LONG_GUN_RIG assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures else 0)


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
