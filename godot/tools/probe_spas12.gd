extends SceneTree

var _scene: Node3D
var _player: CharacterBody3D
var _weapon: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = (load("res://scenes/levels/district_b.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	_player = _scene.get_node("Player") as CharacterBody3D
	_weapon = _player.get_node("Camera3D/WeaponMount/Spas12") as Node3D
	var state := root.get_node("GameState")
	var events := root.get_node("Events")
	_player.global_position = Vector3(-38, 0.1, 52.2)
	for i in 90:
		await physics_frame
	if not state.weapon_unlocked.get(&"spas12", false):
		push_error("SPAS rack pickup did not trigger from the accessible side")
		quit(1)
		return
	print("SPAS12_PICKUP unlocked and equipped")
	_player.global_position = Vector3(-38, 0.1, 55)
	_player.rotation = Vector3.ZERO
	_player.set("_pitch", 0.0)
	(_player.get_node("Camera3D") as Camera3D).rotation = Vector3.ZERO
	for i in 30:
		await process_frame
	DirAccess.make_dir_recursive_absolute("tmp_shots/spas12")
	_weapon.get_node("ViewModel/Arms").visible = false
	await _shot("model_only")
	_weapon.get_node("ViewModel/Arms").visible = true
	await _shot("hip")
	state.is_aiming = true
	events.player_aim_changed.emit(true)
	await create_timer(0.25).timeout
	await _shot("ads")
	state.is_aiming = false
	events.player_aim_changed.emit(false)
	await create_timer(0.25).timeout
	_weapon._fire()
	await create_timer(0.25).timeout
	await _shot("pump")
	await create_timer(0.7).timeout
	state.spas12_mag = 3
	_weapon._start_reload()
	await create_timer(0.28).timeout
	await _shot("reload")
	await create_timer(3.0).timeout
	print("SPAS12_AMMO mag=", state.spas12_mag, " reserve=", state.spas12_reserve)
	var shotgun := _player.get_node("Camera3D/WeaponMount/Shotgun") as Node3D
	print("SHOTGUN_ARMS_PLACED ", shotgun.get("_arms_placed"))
	print("SPAS_ARMS_PLACED ", _weapon.get("_arms_placed"))
	state.current_weapon = &"shotgun"
	events.weapon_switched.emit(&"shotgun")
	await create_timer(0.3).timeout
	await _shot("em_shotgun_compare")
	var dmr := _player.get_node("Camera3D/WeaponMount/DMR") as Node3D
	print("DMR_MAGAZINE_TRANSFORM ", dmr.get("_mag_home_transform"))
	print("DMR_ARMS_PLACED ", dmr.get("_arms_placed"))
	state.current_weapon = &"dmr"
	events.weapon_switched.emit(&"dmr")
	await create_timer(0.3).timeout
	await _shot("dmr_compare")
	quit()


func _shot(tag: String) -> void:
	for i in 6:
		await process_frame
	var path := "tmp_shots/spas12/%s.png" % tag
	root.get_texture().get_image().save_png(path)
	print("SPAS12_SHOT ", path)
