extends LongGunController

var _pump_left: float = 0.0
var _reload_progress: float = 0.0
var _shell: MeshInstance3D
var _pump_sleeve: Node3D
var _pump_home := Vector3.ZERO


func _ready() -> void:
	super()
	_arms_placed = _arms_node.transform
	for node in _weapon_node.find_children("*", "Node3D", true, false):
		if String(node.name).contains("Action_sleeve"):
			_pump_sleeve = node as Node3D
			_pump_home = _pump_sleeve.position
			break
	_shell = get_node_or_null("ViewModel/LoadingShell") as MeshInstance3D
	if _shell != null:
		_shell.visible = false


func _setup_arms() -> void:
	if _arms_node == null:
		return
	var players := _arms_node.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_arms_animation = players[0] as AnimationPlayer
		_prepare_native_hold(&"Armature|Arms_FPS_Anim_Run")
	for node in _arms_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or not mesh_instance.mesh.resource_name.contains("arms"):
			mesh_instance.visible = false


func _process(delta: float) -> void:
	_update_camera_recover(delta)
	_update_view_recoil(delta)
	var cant := _reload_cant_counter() if _is_reloading else 0.0
	var q := Quaternion(Vector3.UP, GameConfig.SHOTGUN_HIP_POSE_YAW) \
		* Quaternion(Vector3.RIGHT, GameConfig.SHOTGUN_HIP_POSE_PITCH) \
		* Quaternion(Vector3.BACK, cant)
	_pose_extra = Transform3D(Basis(q), Vector3.ZERO)
	_weapon_node.transform = _pose_extra * _weapon_home
	_arms_node.transform = _pose_extra * _arms_placed
	_pump_left = maxf(0.0, _pump_left - delta)
	if _pump_sleeve != null:
		var phase := 1.0 - _pump_left / GameConfig.SPAS12_PUMP_TIME if _pump_left > 0.0 else 0.0
		var world_pull := _weapon_node.global_basis * Vector3(0, 0, sin(phase * PI) * 0.09)
		_pump_sleeve.position = _pump_home + _pump_sleeve.get_parent().global_basis.inverse() * world_pull
	if not _is_reloading:
		return
	_reload_progress += delta / weapon_data.reload_time
	if _shell != null:
		var travel := clampf(_reload_progress, 0.0, 1.0)
		_shell.position = Vector3(-0.16, -0.18, 0.08).lerp(Vector3(-0.055, -0.055, 0.08), travel)
		_shell.visible = travel > 0.12 and travel < 0.92
	if _reload_progress < 1.0:
		return
	_reload_progress -= 1.0
	var mag := int(GameState.get(weapon_data.weapon_id + "_mag")) + 1
	var reserve := int(GameState.get(_reserve_key)) - 1
	GameState.set(weapon_data.weapon_id + "_mag", mag)
	GameState.set(_reserve_key, reserve)
	Events.ammo_changed.emit(weapon_data.weapon_id, mag, reserve)
	if mag >= weapon_data.mag_size or reserve <= 0:
		Events.weapon_reloaded.emit(weapon_data.weapon_id)


func _fire() -> bool:
	if _pump_left > 0.0:
		return false
	var fired := super._fire()
	if not fired:
		return false
	_pump_left = GameConfig.SPAS12_PUMP_TIME
	return true


func _spread_for_distance(distance: float) -> float:
	if distance <= GameConfig.SPAS12_SPREAD_START:
		return 0.0
	return _current_spread()


func _start_reload() -> void:
	if _is_reloading or int(GameState.get(_reserve_key)) <= 0:
		return
	if int(GameState.get(weapon_data.weapon_id + "_mag")) >= weapon_data.mag_size:
		return
	_reload_generation += 1
	_reload_progress = 0.0
	Events.weapon_reload_started.emit(weapon_data.weapon_id)


func _play_reload_anim() -> void:
	_reload_progress = 0.0
	if _shell != null:
		_shell.visible = false


func _reload_cant_counter() -> float:
	return sin(clampf(_reload_progress, 0.0, 1.0) * PI) * GameConfig.SPAS12_RELOAD_CANT


func _reset_reload_visuals() -> void:
	_reload_counter = 0.0
	_pose_extra = Transform3D.IDENTITY
	if _weapon_node != null:
		_weapon_node.transform = _weapon_home
	if _arms_node != null:
		_arms_node.transform = _arms_placed
	if _arms_animation != null and _arms_animation.has_animation(&"hold"):
		_arms_animation.play(&"hold")
		_arms_animation.seek(0.0, true)
		_arms_animation.pause()


func _on_weapon_reloaded(weapon_id: StringName) -> void:
	if weapon_id != weapon_data.weapon_id:
		return
	_reset_reload_visuals()
	_is_reloading = false
	_reload_progress = 0.0
	if _shell != null:
		_shell.visible = false


func _on_weapon_switched(weapon_id: StringName) -> void:
	super._on_weapon_switched(weapon_id)
	_pump_left = 0.0
	_reload_progress = 0.0
	if _shell != null:
		_shell.visible = false
