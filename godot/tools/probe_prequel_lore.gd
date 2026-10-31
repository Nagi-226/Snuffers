extends SceneTree

var _scene: Node3D
var _player: CharacterBody3D
var _camera: Camera3D
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = (load("res://scenes/levels/district_b.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	for i in 30:
		await process_frame
	_player = _scene.get_node("Player") as CharacterBody3D
	_camera = _scene.get_node("Player/Camera3D") as Camera3D
	DirAccess.make_dir_recursive_absolute("tmp_shots/prequel_lore")
	_camera.global_position = Vector3(-49, 5.0, 91)
	_camera.look_at(Vector3(-49, 5.0, 80))
	await _shot("warehouse_pbr")
	await _visit(&"LanternReconMarker", Vector3(-49, 0.2, 82.2), Vector3(-49, 1.45, 80.42), "recon_marker")
	await _visit(&"LanternSurveyBeacon", Vector3(-135, 6.1, -93), Vector3(-135, 6.9, -95), "survey_beacon")
	await _visit(&"WickMemento", Vector3(-150, 0.2, -103), Vector3(-150, 1.05, -105), "wick_memento")
	print("PREQUEL_LORE failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _visit(node_name: StringName, player_pos: Vector3, look_at: Vector3, shot_name: String) -> void:
	_player.global_position = player_pos
	_player.velocity = Vector3.ZERO
	_camera.global_position = player_pos + Vector3(0, 1.6, 0)
	_camera.look_at(look_at)
	await physics_frame
	await physics_frame
	_player._update_interact_target()
	var target = _player._interact_target
	if target == null or target.name != node_name:
		_failures += 1
		push_error("LORE interaction target mismatch: %s actual=%s" % [node_name, target])
	else:
		_player._try_interact()
		print("LORE_INTERACT ", node_name)
	await _shot(shot_name)


func _shot(shot_name: String) -> void:
	for i in 8:
		await process_frame
	var path := "tmp_shots/prequel_lore/%s.png" % shot_name
	root.get_texture().get_image().save_png(path)
	print("LORE_SHOT ", path)
