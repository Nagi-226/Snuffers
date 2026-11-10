## 真实Player自然帧时钟：完整idle周期内枪身、60骨姿态及双掌蒙皮稳定。
extends SceneTree

var _assertions := 0
var _failures := 0


func _init() -> void:
	Engine.max_fps = 60
	call_deferred("_run")


func _run() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("native pistol stillness timed out")
		quit(1))
	var state = root.get_node("GameState")
	state.reset()
	state.weapon_unlocked[&"pistol"] = true
	state.weapon_unlocked[&"magnum"] = true
	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	await process_frame
	# 无地板fixture只停重力/移动；Player、武器与AnimationPlayer保留真实process。
	player.set_physics_process(false)
	for weapon_id in [&"pistol", &"magnum"]:
		player._switch_weapon(weapon_id)
		var weapon = player.get_node("Camera3D/WeaponMount/" + ("Pistol" if weapon_id == &"pistol" else "Magnum"))
		var palms := _palm_vertices(weapon)
		_assert(palms[0].size() > 20 and palms[1].size() > 20, "%s uses actual weighted vertices of both palms" % weapon_id)
		for aiming in [false, true]:
			player._set_aiming(aiming)
			weapon._reset_reload_visuals()
			await create_timer(0.6).timeout
			var label := "%s %s" % [weapon_id, "ADS" if aiming else "hip"]
			await _check_idle(player, weapon, palms, label)
			state.set(weapon.mag_state_property, 3)
			state.set(weapon.reserve_state_property, 100)
			var home: Transform3D = weapon._weapon_node.transform
			_assert(weapon._fire() and state.get(weapon.mag_state_property) == 2 and weapon._view_offset > 0.0, "%s real fire consumes one round and applies view recoil" % label)
			var fire_duration: float = weapon._arms_animation.get_animation(&"fire").length
			var fire_progressed := false
			var gun_moved := false
			var started := Time.get_ticks_usec()
			while float(Time.get_ticks_usec() - started) / 1000000.0 < fire_duration + 0.1:
				await process_frame
				fire_progressed = fire_progressed or (weapon._arms_animation.current_animation == "fire" and weapon._arms_animation.current_animation_position > 0.0)
				gun_moved = gun_moved or _transform_error(home, weapon._weapon_node.transform) > 0.00001
			_assert(fire_progressed and gun_moved, "%s native fire still advances and moves the actual gun" % label)
			await create_timer(2.0).timeout
			_assert(weapon._arms_animation.current_animation == "idle" and weapon._view_offset == 0.0, "%s fire returns to idle after recoil recovery" % label)
			await _check_idle(player, weapon, palms, label + " after fire")
			var starting_reserve: int = state.get(weapon.reserve_state_property)
			weapon._start_reload()
			await create_timer(weapon.weapon_data.reload_time * 0.35).timeout
			_assert(weapon._is_reloading and weapon._arms_animation.current_animation == "reload" and weapon._arms_animation.current_animation_position > 0.0 and not weapon._magazine.transform.is_equal_approx(weapon._mag_home_transform), "%s real timed reload advances the existing animation and actual magazine" % label)
			await create_timer(weapon.weapon_data.reload_time * 0.75).timeout
			_assert(not weapon._is_reloading and state.get(weapon.mag_state_property) == weapon.weapon_data.mag_size and state.get(weapon.reserve_state_property) == starting_reserve - (weapon.weapon_data.mag_size - 2), "%s real timed reload preserves ammunition transfer" % label)
			await _check_idle(player, weapon, palms, label + " after reload")
		state.set(weapon.mag_state_property, 2)
		state.set(weapon.reserve_state_property, 100)
		weapon._start_reload()
		await create_timer(weapon.weapon_data.reload_time * 0.35).timeout
		player._switch_weapon(&"magnum" if weapon_id == &"pistol" else &"pistol")
		_assert(not weapon._is_reloading and weapon._magazine.transform.is_equal_approx(weapon._mag_home_transform) and weapon._magazine.visible, "%s switching weapons cancels and restores the existing reload" % weapon_id)
		await create_timer(weapon.weapon_data.reload_time).timeout
		_assert(state.get(weapon.mag_state_property) == 2 and state.get(weapon.reserve_state_property) == 100, "%s cancelled timer cannot migrate ammunition later" % weapon_id)
	player.queue_free()
	await process_frame
	# 共用helper的社区Gen5预览保留现有idle展示，不能被两枪约束误伤。
	var preview = (load("res://scenes/player/black_pistol_preview.tscn") as PackedScene).instantiate()
	root.add_child(preview)
	await process_frame
	var gen5: Node3D = preview.get_node("G17Gen5Olight")
	var gen5_start := gen5.transform
	var idle_position: float = preview.adapter.animation.current_animation_position
	await create_timer(0.35).timeout
	_assert(preview.adapter.animation.current_animation_position > idle_position and _transform_error(gen5_start, gen5.transform) > 0.00001, "Gen5 preview preserves existing native idle progression and gun motion")
	preview.queue_free()
	await process_frame
	print("NATIVE_PISTOL_STILLNESS assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _check_idle(player: Node3D, weapon: Node3D, palms: Array, label: String) -> void:
	var reference := _snapshot(player, weapon, palms)
	var maximum := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var duration: float = weapon._arms_animation.get_animation(&"idle").length
	var started := Time.get_ticks_usec()
	var elapsed := 0.0
	var frames := 0
	while elapsed < duration + 0.1:
		await process_frame
		elapsed = float(Time.get_ticks_usec() - started) / 1000000.0
		var actual := _snapshot(player, weapon, palms)
		maximum[0] = maxf(maximum[0], _transform_error(reference.gun, actual.gun))
		for bone in actual.bones.size():
			maximum[1] = maxf(maximum[1], _transform_error(reference.bones[bone], actual.bones[bone]))
		for hand in 2:
			for vertex in actual.palms[hand].size():
				maximum[hand + 2] = maxf(maximum[hand + 2], reference.palms[hand][vertex].distance_to(actual.palms[hand][vertex]))
		frames += 1
	print("STILLNESS ", label, " elapsed=", elapsed, " idle_length=", duration, " frames=", frames, " max_gun/bones/right_palm/left_palm=", maximum)
	_assert(elapsed >= duration and frames >= 30, "%s observes a complete source idle period under the real SceneTree clock" % label)
	_assert(maximum[0] < 0.00001, "%s actual camera-space gun remains stable for the entire idle cycle" % label)
	_assert(maximum[1] < 0.00001, "%s all sixty camera-space bone poses remain stable for the entire idle cycle" % label)
	_assert(maximum[2] < 0.00001 and maximum[3] < 0.00001, "%s both actual weighted palm skins remain stable for the entire idle cycle" % label)


func _snapshot(player: Node3D, weapon: Node3D, palms: Array) -> Dictionary:
	var camera: Transform3D = player._camera.global_transform.affine_inverse()
	var skeleton: Skeleton3D = weapon._arms_skeleton
	var skin_space := camera * skeleton.global_transform
	var poses: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		poses.append(skeleton.get_bone_global_pose(bone))
	var posed_palms: Array = [PackedVector3Array(), PackedVector3Array()]
	for hand in 2:
		for vertex: Dictionary in palms[hand]:
			var position := Vector3.ZERO
			for influence: Dictionary in vertex.influences:
				position += (poses[influence.bone] * influence.bind * vertex.position) * influence.weight
			posed_palms[hand].append(skin_space * position)
	for bone in poses.size():
		poses[bone] = skin_space * poses[bone]
	return {"gun": camera * weapon._weapon_node.global_transform, "bones": poses, "palms": posed_palms}


func _palm_vertices(weapon: Node3D) -> Array:
	var mesh := weapon.get_node("ViewModel/ArmsEM57P").find_child("BlackArmsMesh", true, false) as MeshInstance3D
	var skeleton: Skeleton3D = weapon._arms_skeleton
	var skin := mesh.skin
	var output: Array = [[], []]
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var width: int = bones.size() / vertices.size()
		for vertex in vertices.size():
			var influences: Array[Dictionary] = []
			var palm_weights := Vector2.ZERO
			for influence in width:
				var offset := vertex * width + influence
				if weights[offset] <= 0.0:
					continue
				var bind := bones[offset]
				var bone := skeleton.find_bone(skin.get_bind_name(bind)) if skin.get_bind_name(bind) != &"" else skin.get_bind_bone(bind)
				influences.append({"bone": bone, "bind": skin.get_bind_pose(bind), "weight": weights[offset]})
				if skeleton.get_bone_name(bone) in ["R_wrist_028", "R_palm_041"]:
					palm_weights.x += weights[offset]
				if skeleton.get_bone_name(bone) in ["L_wrist_04", "L_palm_017"]:
					palm_weights.y += weights[offset]
			for hand in 2:
				if palm_weights[hand] > 0.65:
					output[hand].append({"position": vertices[vertex], "influences": influences})
	return output


func _transform_error(first: Transform3D, second: Transform3D) -> float:
	return maxf(first.origin.distance_to(second.origin), maxf(first.basis.x.distance_to(second.basis.x), maxf(first.basis.y.distance_to(second.basis.y), first.basis.z.distance_to(second.basis.z))))


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)
