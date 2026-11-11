## 原生idle全过程ADS中心通光：真实玩家相机中心射线与每相位实际不透明枪身。
extends SceneTree

var _assertions := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(80.0).timeout.connect(func() -> void:
		push_error("native pistol ADS idle timed out")
		quit(1))
	root.size = Vector2i(1920, 1080)
	var state = root.get_node("GameState")
	state.reset()
	state.fire_modes[&"pistol"] = &"semi"
	state.weapon_unlocked[&"pistol"] = true
	state.weapon_unlocked[&"magnum"] = true
	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	await process_frame
	player.set_process(false)
	player.set_physics_process(false)
	for node in player.find_children("*", "Node", true, false):
		node.set_process(false)
		node.set_physics_process(false)
	for weapon_id in [&"pistol", &"magnum"]:
		player._switch_weapon(weapon_id)
		player._set_aiming(true)
		var weapon = player.get_node("Camera3D/WeaponMount/" + ("Pistol" if weapon_id == &"pistol" else "Magnum"))
		weapon._reset_reload_visuals()
		for frame in 30:
			player._process(1.0 / 60.0)
			weapon._process(0.0)
		await physics_frame
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		var animation: AnimationPlayer = weapon._arms_animation
		var duration := animation.get_animation(&"idle").length
		for step in 61:
			animation.seek(duration * float(step) / 60.0, true)
			weapon._process(0.0)
			await process_frame
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
			var center: Vector2 = player._camera.get_viewport().get_visible_rect().size * 0.5
			var origin: Vector3 = player._camera.project_ray_origin(center)
			var direction: Vector3 = player._camera.project_ray_normal(center)
			var blocked := _opaque_gun_blocks(weapon._weapon_node, origin, direction)
			_assertions += 1
			if blocked:
				_failures += 1
				push_error("FAIL: %s actual ADS screen center is blocked by its opaque gun at idle phase %.3f" % [weapon_id, float(step) / 60.0])
		# ADS待机约束不得冻结射击和真实弹匣换弹动作。
		var fired: bool = weapon._fire()
		weapon._process(animation.get_animation(&"fire").length * 0.5)
		_assertions += 1
		if not fired or animation.current_animation != "fire" or animation.current_animation_position <= 0.0:
			_failures += 1
			push_error("FAIL: %s ADS preserves native fire progression" % weapon_id)
		weapon._on_reload_started(weapon_id)
		weapon._process(weapon.weapon_data.reload_time * 0.25)
		_assertions += 1
		if animation.current_animation != "reload" or animation.current_animation_position <= 0.0 or weapon._magazine.transform.is_equal_approx(weapon._mag_home_transform):
			_failures += 1
			push_error("FAIL: %s ADS preserves native reload and actual magazine progression" % weapon_id)
		weapon._is_reloading = false
		weapon._reset_reload_visuals()
		weapon._process(duration * 0.25)
		_assertions += 1
		if not weapon._native_arms.lock_idle_aim or animation.current_animation_position > 0.0:
			_failures += 1
			push_error("FAIL: %s current weapon ADS idle stays at its calibrated pose" % weapon_id)
		# 机主本轮取消两枪腰射idle晃动，收镜后同样保持标定姿态。
		player._set_aiming(false)
		for frame in 30:
			player._process(1.0 / 60.0)
			weapon._process(0.0)
		animation.seek(duration * 0.5, true)
		weapon._process(0.0)
		var current: Transform3D = weapon._weapon_node.transform
		var home: Transform3D = weapon._weapon_home
		var movement := current.origin.distance_to(home.origin) > 0.0001 or current.basis.orthonormalized().get_rotation_quaternion().angle_to(home.basis.orthonormalized().get_rotation_quaternion()) > 0.001
		_assertions += 1
		if movement:
			_failures += 1
			push_error("FAIL: %s hip idle remains at its calibrated gun pose" % weapon_id)
		var hip_position := animation.current_animation_position
		weapon._process(duration * 0.1)
		_assertions += 1
		if weapon._native_arms.lock_idle_aim or animation.current_animation_position != hip_position:
			_failures += 1
			push_error("FAIL: %s exiting ADS keeps native idle stable" % weapon_id)
		player._switch_weapon(&"magnum" if weapon_id == &"pistol" else &"pistol")
		player._set_aiming(true)
		weapon._reset_reload_visuals()
		weapon._process(duration * 0.25)
		_assertions += 1
		if weapon._native_arms.lock_idle_aim or animation.current_animation_position > 0.0:
			_failures += 1
			push_error("FAIL: %s inactive weapon keeps its own idle stable without another weapon's ADS state" % weapon_id)
	player.queue_free()
	await process_frame
	print("NATIVE_PISTOL_ADS_IDLE assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _opaque_gun_blocks(gun: Node3D, origin: Vector3, direction: Vector3) -> bool:
	for node in gun.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for index in range(0, indices.size(), 3):
				var a := mesh.global_transform * vertices[indices[index]]
				var b := mesh.global_transform * vertices[indices[index + 1]]
				var c := mesh.global_transform * vertices[indices[index + 2]]
				if Geometry3D.ray_intersects_triangle(origin, direction, a, b, c) != null or Geometry3D.ray_intersects_triangle(origin, direction, a, c, b) != null:
					return true
	return false
