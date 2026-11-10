extends SceneTree

const WEAPONS := {&"em86b": "Em86b", &"em57s2": "Em57s2", &"em86m": "Em86m", &"em12g2": "Em12g2"}
const ORIGINAL_INTACT := {&"em86b": "em86b_viewmodel_intact.glb", &"em57s2": "em57s2_viewmodel.glb", &"em86m": "em86m_viewmodel.glb", &"em12g2": "em12g2_viewmodel_intact.glb"}
var _failures := 0
var _assertions := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(50.0).timeout.connect(func() -> void:
		push_error("player ADS magazine test timed out")
		quit(1))
	var state = root.get_node("GameState")
	state.reset()
	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	var maximum_reload_duration := 0.0
	root.add_child(player)
	await process_frame
	player.set_process(false)
	player.set_physics_process(false)
	for child in player.get_node("Camera3D/WeaponMount").get_children():
		child.set_process(false)
		child.set_physics_process(false)
		var animations := child.find_children("*", "AnimationPlayer", true, false)
		for animation in animations:
			animation.set_process(false)
			animation.set_physics_process(false)
	for weapon_id: StringName in WEAPONS:
		state.weapon_unlocked[weapon_id] = true
		player._switch_weapon(weapon_id)
		var weapon = player.get_node("Camera3D/WeaponMount/" + WEAPONS[weapon_id])
		var magazine: Node3D = weapon._magazine
		var gun: Node3D = weapon._weapon_node
		_assert(magazine != null and gun != null, "%s actual weapon resolves its removable magazine and gun nodes" % weapon_id)
		if magazine == null or gun == null:
			continue
		var parts := magazine.find_children("*", "MeshInstance3D", true, false)
		if magazine is MeshInstance3D:
			parts.append(magazine)
		_assert(not parts.is_empty(), "%s Player uses actual removable magazine geometry" % weapon_id)
		if parts.is_empty():
			continue
		player._set_aiming(true)
		_settle(player, weapon)
		var pair: Dictionary = player._optic_meshes[weapon_id]
		_assert(pair.node.mesh == pair.bored, "%s actual ADS selects its open optic body" % weapon_id)
		player._set_aiming(false)
		_settle(player, weapon)
		_assert(pair.node.mesh == pair.intact, "%s actual hip restores its closed optic body" % weapon_id)
		var mag_faces: Dictionary = {}
		for part: MeshInstance3D in parts:
			mag_faces.merge(_faces(part, gun))
		var original := (load("res://assets/models/weapons/" + ORIGINAL_INTACT[weapon_id]) as PackedScene).instantiate()
		var original_mesh := original.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var control := MeshInstance3D.new()
		control.mesh = original_mesh.mesh
		gun.add_child(control)
		control.global_transform = pair.node.global_transform
		_assert(_duplicates(control, gun, mag_faces) > 0, "%s positive control detects original intact magazine faces at the same mesh replacement transform" % weapon_id)
		control.free()
		original.free()
		_assert(_duplicates(pair.node, gun, mag_faces) == 0, "%s hip body does not restore magazine faces into the gun" % weapon_id)
		state.set(weapon_id + "_mag", 1)
		weapon._start_reload()
		maximum_reload_duration = maxf(maximum_reload_duration, weapon.weapon_data.reload_time)
		weapon._arms_animation.seek(weapon.weapon_data.reload_time * 0.45, true)
		weapon._process(1.0 / 60.0)
		player._process(1.0 / 60.0)
		_assert(_duplicates(pair.node, gun, mag_faces) == 0, "%s real reload after ADS-to-hip leaves no original magazine behind in the body" % weapon_id)
		player._switch_weapon(&"rifle")
		weapon._process(0.0)
		_assert(not weapon._is_reloading and magazine.visible, "%s switching away cancels its actual visible reload" % weapon_id)
	# Cancelled reload coroutine owners must survive until their timers return.
	await create_timer(maximum_reload_duration + 0.1).timeout
	player.queue_free()
	await process_frame
	await process_frame
	print("PLAYER_ADS_MAGAZINE assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)

func _settle(player: Node, weapon: Node) -> void:
	for frame in 30:
		player._restore_viewmodel_depth()
		weapon._process(1.0 / 60.0)
		player._process(1.0 / 60.0)

func _faces(instance: MeshInstance3D, gun: Node3D) -> Dictionary:
	var faces: Dictionary = {}
	var transform := gun.global_transform.affine_inverse() * instance.global_transform
	for surface in instance.mesh.get_surface_count():
		var arrays := instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for offset in range(0, indices.size(), 3):
			var keys: Array[String] = []
			for corner in 3:
				var point: Vector3 = transform * vertices[indices[offset + corner]]
				keys.append("%d,%d,%d" % [roundi(point.x * 10000), roundi(point.y * 10000), roundi(point.z * 10000)])
			keys.sort()
			faces["/".join(keys)] = true
	return faces

func _duplicates(body: MeshInstance3D, gun: Node3D, magazine_faces: Dictionary) -> int:
	var duplicates := 0
	for face in _faces(body, gun):
		if magazine_faces.has(face):
			duplicates += 1
	return duplicates

func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)
