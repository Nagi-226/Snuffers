class_name GrenadeLauncherController
extends RifleController


func _fire() -> bool:
	if _is_reloading:
		return false
	if _mag_value() <= 0:
		_start_reload()
		return false
	if weapon_data.projectile_scene == null:
		push_error("EM-40T-1 缺少 EC-40 投射物场景")
		return false
	_set_mag_value(_mag_value() - 1)
	Events.ammo_changed.emit(weapon_data.weapon_id, _mag_value(), _reserve_value())
	Events.weapon_fired.emit(weapon_data.weapon_id)
	Events.player_muzzle_flash.emit(weapon_data.weapon_id,
		global_position + (-global_transform.basis.z) * GameConfig.GRENADE_LAUNCH_FORWARD)
	_apply_recoil()
	var projectile: Node3D = weapon_data.projectile_scene.instantiate()
	var container: Node = get_tree().current_scene
	if container == null:
		container = get_tree().root
	container.add_child(projectile)
	var launch_xform := global_transform
	launch_xform.origin += (-global_transform.basis.z) * GameConfig.GRENADE_LAUNCH_FORWARD \
		+ Vector3.DOWN * GameConfig.GRENADE_LAUNCH_DROP
	projectile.global_transform = launch_xform
	projectile.setup(
		-global_transform.basis.z,
		HitSolver.collect_owner_rids(self),
		weapon_data
	)
	return true
