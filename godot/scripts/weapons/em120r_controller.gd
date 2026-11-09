## 长弓肩扛发射器：两种制导均为半自动；激光档同一时刻只允许一枚在飞。
extends WeaponController

var _laser_missile: Node3D
var _laser_mesh: MeshInstance3D
var _laser_cylinder: CylinderMesh
var _is_reloading := false
var _reload_generation := 0
var _arms_skeleton: Skeleton3D
var _arms_animation: AnimationPlayer
var _aim_origin := Vector3.ZERO
var _has_aim_origin := false

@onready var _weapon_node: Node3D = $ViewModel/Weapon
@onready var _muzzle_node: Marker3D = $ViewModel/Weapon/Muzzle
@onready var _laser_origin: Marker3D = $ViewModel/Weapon/LaserOrigin
@onready var _arms_node: Node3D = $ViewModel/Arms


func _ready() -> void:
	super()
	_weapon_node.position = GameConfig.EM120R_MODEL_POSITION
	_weapon_node.rotation = GameConfig.EM120R_MODEL_ROTATION
	_muzzle_node.position = GameConfig.EM120R_MUZZLE_POSITION
	_laser_origin.position = GameConfig.EM120R_LASER_ORIGIN
	_setup_shoulder_arms()
	_build_laser()
	Events.ec120_aim_changed.connect(_on_aim_changed)
	Events.ec120_aim_origin_changed.connect(_on_aim_origin_changed)
	Events.weapon_reload_started.connect(_on_reload_started)
	Events.weapon_reloaded.connect(_on_weapon_reloaded)


func _exit_tree() -> void:
	Events.ec120_aim_changed.disconnect(_on_aim_changed)
	Events.ec120_aim_origin_changed.disconnect(_on_aim_origin_changed)
	Events.weapon_reload_started.disconnect(_on_reload_started)
	Events.weapon_reloaded.disconnect(_on_weapon_reloaded)
	super()


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.keycode == KEY_R and key.pressed and not key.echo \
				and _is_current_weapon() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_start_reload()


## PROJECTILE 被基类的 hitscan 门控排除，长弓显式使用半自动按下边沿。
func _on_trigger_pressed() -> void:
	if _fire_cooldown <= 0.0:
		_try_fire()


func _tick_weapon(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	_burst_left = 0


func _process(delta: float) -> void:
	super(delta)
	_update_laser()


func _mag_value() -> int:
	return GameState.em120r_mag


func _reserve_value() -> int:
	return GameState.em120r_reserve


func _fire() -> bool:
	if not _is_current_weapon() or _is_reloading:
		return false
	if _mag_value() <= 0:
		_start_reload()
		return false
	var mode := GameState.em120r_guidance_mode
	if mode not in [&"laser", &"homing"]:
		return false
	if mode == &"laser" and is_instance_valid(_laser_missile):
		Events.message_posted.emit("激光制导中——等待上一发爆炸")
		return false
	var target: Variant = null
	if mode == &"homing":
		target = GameState.em120r_locked_target
		if not _target_alive(target):
			Events.message_posted.emit("请开镜框住同一目标 1 秒完成锁定")
			return false
	if weapon_data.projectile_scene == null:
		push_error("EM-120R 缺少 EC-120 导弹场景")
		return false
	var projectile := weapon_data.projectile_scene.instantiate() as Node3D
	if projectile == null or not projectile.has_method(&"setup"):
		if projectile != null:
			projectile.free()
		push_error("EM-120R 投射物不满足 setup 契约")
		return false
	# camera 至枪口的整段都必须清空；WeaponMount 自身可能已位于近墙后方。
	# 使用收到事件的有效标记，世界原点 Vector3.ZERO 也可能是合法相机位置。
	var muzzle := _muzzle_node.global_position
	var clearance_origin := _aim_origin if _has_aim_origin else global_position
	var clearance := PhysicsRayQueryParameters3D.create(clearance_origin, muzzle)
	clearance.exclude = HitSolver.collect_owner_rids(self)
	clearance.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(clearance)
	var launch_position: Vector3 = hit.position if not hit.is_empty() else muzzle
	var container: Node = get_tree().current_scene
	if container == null:
		container = get_tree().root
	container.add_child(projectile)
	var direction := GameState.em120r_aim_point - muzzle
	if direction.length_squared() <= 0.000001:
		direction = -global_basis.z
	projectile.global_position = launch_position
	projectile.setup(direction.normalized(), HitSolver.collect_owner_rids(self), weapon_data, mode, target)
	if mode == &"laser":
		_laser_missile = projectile
		projectile.tree_exiting.connect(_on_laser_missile_exited.bind(projectile))
	else:
		# 导弹已持有本发目标；收镜、后续换锁不修改它。
		GameState.em120r_locked_target = null
		Events.ec120_lock_changed.emit(null)
		Events.ec120_lock_consumed.emit()
	GameState.em120r_mag -= 1
	Events.ammo_changed.emit(weapon_data.weapon_id, _mag_value(), _reserve_value())
	Events.weapon_fired.emit(weapon_data.weapon_id)
	Events.player_muzzle_flash.emit(weapon_data.weapon_id, launch_position)
	_apply_recoil()
	if not hit.is_empty():
		projectile._explode(launch_position)
	return true


func _on_laser_missile_exited(projectile: Node3D) -> void:
	if _laser_missile == projectile:
		_laser_missile = null


func _target_alive(target: Variant) -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return false
	var health: Variant = target.get("health")
	return health == null or float(health) > 0.0


func _on_aim_changed(_aim_point: Vector3) -> void:
	_update_laser()


func _on_aim_origin_changed(origin: Vector3) -> void:
	_aim_origin = origin
	_has_aim_origin = true


func _build_laser() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = GameConfig.EM120R_LASER_COLOR
	material.emission_enabled = true
	material.emission = GameConfig.EM120R_LASER_COLOR
	material.emission_energy_multiplier = GameConfig.EM120R_LASER_ENERGY
	_laser_cylinder = CylinderMesh.new()
	_laser_cylinder.top_radius = GameConfig.EM120R_LASER_WIDTH * 0.5
	_laser_cylinder.bottom_radius = _laser_cylinder.top_radius
	_laser_mesh = MeshInstance3D.new()
	_laser_mesh.name = "GuidanceLaser"
	_laser_mesh.mesh = _laser_cylinder
	_laser_mesh.material_override = material
	_laser_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser_mesh.visible = false
	add_child(_laser_mesh)


func _update_laser() -> void:
	if _laser_mesh == null:
		return
	_laser_mesh.visible = _is_current_weapon() and GameState.em120r_guidance_mode == &"laser" and not GameState.is_aiming
	if not _laser_mesh.visible:
		return
	var from := _laser_origin.global_position
	var motion := GameState.em120r_aim_point - from
	if motion.length_squared() <= 0.000001:
		_laser_mesh.visible = false
		return
	_laser_cylinder.height = motion.length()
	_laser_mesh.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, motion.normalized())), from + motion * 0.5)


func _start_reload() -> void:
	if _is_reloading or _reserve_value() <= 0 or _mag_value() >= weapon_data.mag_size:
		return
	_reload_generation += 1
	var generation := _reload_generation
	Events.weapon_reload_started.emit(weapon_data.weapon_id)
	await get_tree().create_timer(weapon_data.reload_time).timeout
	if generation == _reload_generation:
		Events.weapon_reloaded.emit(weapon_data.weapon_id)


func _on_reload_started(weapon_id: StringName) -> void:
	if weapon_data.weapon_id == weapon_id:
		_is_reloading = true


func _on_weapon_reloaded(weapon_id: StringName) -> void:
	if weapon_data.weapon_id != weapon_id:
		return
	_is_reloading = false
	var take := mini(weapon_data.mag_size - _mag_value(), _reserve_value())
	GameState.em120r_mag += take
	GameState.em120r_reserve -= take
	Events.ammo_changed.emit(weapon_id, _mag_value(), _reserve_value())


func _on_weapon_switched(weapon_id: StringName) -> void:
	super(weapon_id)
	_trigger_held = false
	if weapon_data != null and weapon_id != weapon_data.weapon_id:
		_reload_generation += 1
		_is_reloading = false


## 复用已登记手臂与两骨 IK，双手独立标定到筒身握点，筒体保持肩位。
func _setup_shoulder_arms() -> void:
	var skeletons := _arms_node.find_children("*", "Skeleton3D", true, false)
	var animations := _arms_node.find_children("*", "AnimationPlayer", true, false)
	if skeletons.is_empty() or animations.is_empty():
		return
	_arms_skeleton = skeletons[0] as Skeleton3D
	_arms_animation = animations[0] as AnimationPlayer
	var hold: StringName = &"Armature|Arms_FPS_Anim_Run"
	if not _arms_animation.has_animation(hold):
		return
	_arms_animation.play(hold)
	_arms_animation.seek(0.0, true)
	_arms_animation.pause()
	var hand := _find_bone("Hand_R")
	var gun := _arms_skeleton.find_bone("ACRRifle_058")
	if hand < 0 or gun < 0:
		return
	var chain := _arms_node.global_transform.affine_inverse() * _arms_skeleton.global_transform
	var basis := _weapon_node.global_basis.orthonormalized() \
		* Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD) \
		* _arms_skeleton.get_bone_global_pose(gun).basis.orthonormalized().inverse()
	var origin := _weapon_node.to_global(GameConfig.EM120R_RIGHT_GRIP) \
		- basis * _arms_skeleton.get_bone_global_pose(hand).origin
	_arms_node.global_transform = Transform3D(basis, origin) * chain.affine_inverse()
	_pose_arm("R", GameConfig.EM120R_RIGHT_GRIP, GameConfig.EM120R_RIGHT_ELBOW)
	_pose_arm("L", GameConfig.EM120R_SUPPORT_GRIP, GameConfig.EM120R_LEFT_ELBOW)
	for node in _arms_node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		(node as MeshInstance3D).visible = mesh != null and mesh.resource_name.contains("arms")


func _find_bone(prefix: String) -> int:
	for bone in _arms_skeleton.get_bone_count():
		if _arms_skeleton.get_bone_name(bone).begins_with(prefix):
			return bone
	return -1


func _pose_arm(side: String, grip: Vector3, elbow: Vector3) -> void:
	var upper := _find_bone("UpArm_" + side)
	var fore := _find_bone("Forearm_" + side)
	var hand := _find_bone("Hand_" + side)
	var control := _find_bone("IK_Hand_Cntrl_" + side)
	if upper < 0 or fore < 0 or hand < 0:
		return
	var upper_pose := _arms_skeleton.get_bone_global_pose(upper)
	var fore_pose := _arms_skeleton.get_bone_global_pose(fore)
	var hand_pose := _arms_skeleton.get_bone_global_pose(hand)
	var upper_length := upper_pose.origin.distance_to(fore_pose.origin)
	var fore_length := fore_pose.origin.distance_to(hand_pose.origin)
	var to_skeleton := _arms_skeleton.global_transform.affine_inverse() * _weapon_node.global_transform
	var wrist := to_skeleton * grip
	var shoulder := wrist + to_skeleton.basis * (GameConfig.LONG_GUN_SHOULDER_DIRECTION.normalized() * (upper_length + fore_length) * 0.94)
	var direction := (wrist - shoulder).normalized()
	var distance := clampf(wrist.distance_to(shoulder), absf(upper_length - fore_length) + 0.001, upper_length + fore_length - 0.001)
	var a := (upper_length * upper_length - fore_length * fore_length + distance * distance) / (2.0 * distance)
	var h := sqrt(maxf(0.0, upper_length * upper_length - a * a))
	var pole := to_skeleton.basis * elbow
	pole -= direction * pole.dot(direction)
	pole /= maxf(pole.length(), 0.000001)
	var joint := shoulder + direction * a + pole * h
	_arms_skeleton.set_bone_global_pose(upper, Transform3D(upper_pose.basis, shoulder))
	_aim_bone(upper, joint)
	_aim_bone(fore, wrist)
	if control >= 0:
		var control_pose := _arms_skeleton.get_bone_global_pose(control)
		_arms_skeleton.set_bone_global_pose(control, Transform3D(control_pose.basis, wrist))
	var finger_direction := (to_skeleton.basis * Vector3.FORWARD).normalized()
	var rotation := Quaternion(hand_pose.basis.y.normalized(), finger_direction)
	_arms_skeleton.set_bone_global_pose(hand, Transform3D(Basis(rotation) * hand_pose.basis, wrist))


func _aim_bone(bone: int, point: Vector3) -> void:
	var pose := _arms_skeleton.get_bone_global_pose(bone)
	var rotation := Quaternion(pose.basis.y.normalized(), (point - pose.origin).normalized())
	_arms_skeleton.set_bone_global_pose(bone, Transform3D(Basis(rotation) * pose.basis, pose.origin))
