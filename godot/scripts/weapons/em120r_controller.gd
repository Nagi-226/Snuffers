## 长弓肩扛发射器：两种制导均为半自动；激光档同一时刻只允许一枚在飞。
extends WeaponController

const NativeLongGunArms = preload("res://scripts/player/native_long_gun_arms.gd")

var _laser_missile: Node3D
var _laser_mesh: MeshInstance3D
var _laser_cylinder: CylinderMesh
var _is_reloading := false
var _reload_generation := 0
var _arms_skeleton: Skeleton3D
var _arms_animation: AnimationPlayer
var _aim_origin := Vector3.ZERO
var _has_aim_origin := false
var _native_arms: RefCounted
var _weapon_home := Transform3D.IDENTITY
var _loading_home := Transform3D.IDENTITY
var _missile_bounds := AABB()

@onready var _weapon_node: Node3D = $ViewModel/Weapon
@onready var _muzzle_node: Marker3D = $ViewModel/Weapon/Muzzle
@onready var _laser_origin: Marker3D = $ViewModel/Weapon/LaserOrigin
@onready var _arms_node: Node3D = $ViewModel/Arms
@onready var _loading_missile: Node3D = $ViewModel/Weapon/LoadingMissile
@onready var _rear_breech: Marker3D = $ViewModel/Weapon/RearBreech


func _ready() -> void:
	super()
	_weapon_node.position = GameConfig.EM120R_MODEL_POSITION
	_weapon_node.rotation = GameConfig.EM120R_MODEL_ROTATION
	_muzzle_node.position = GameConfig.EM120R_MUZZLE_POSITION
	_laser_origin.position = GameConfig.EM120R_LASER_ORIGIN
	_weapon_home = _weapon_node.transform
	_rear_breech.position = GameConfig.EM120R_REAR_BREECH
	_loading_home = _loading_missile.transform
	_loading_missile.visible = false
	var has_bounds := false
	for node in _loading_missile.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var to_missile := _loading_missile.global_transform.affine_inverse() * mesh.global_transform
		var bounds: AABB = to_missile * mesh.get_aabb()
		_missile_bounds = _missile_bounds.merge(bounds) if has_bounds else bounds
		has_bounds = true
	if not has_bounds or _missile_bounds.size.z <= 0.0:
		push_error("EM-120R未能读取已登记EC-120导弹的真实长度")
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
	if _native_arms != null:
		if _is_reloading:
			_arms_animation.advance(maxf(0.0, delta))
			_update_rear_reload(_arms_animation.current_animation_position / weapon_data.reload_time)
		else:
			_native_arms.pose_hold(1.0 if GameState.is_aiming else 0.0)
			_native_arms.update_bounds()
	_update_laser()


## 只摆位已登记的静态导弹；实际飞行与弹药迁移仍由原有流程负责。
func _update_rear_reload(progress: float) -> void:
	progress = clampf(progress, 0.0, 1.0)
	var profile: Dictionary = _native_arms._profile
	var contact: float = GameConfig.EM120R_REAR_CONTACT_PHASE
	var release: float = GameConfig.EM120R_REAR_RELEASE_PHASE
	var seat: float = GameConfig.EM120R_REAR_SEAT_PHASE
	var weight := smoothstep(0.0, contact, progress) * (1.0 - smoothstep(seat, 1.0, progress))
	# 大幅侧转只作用于筒身；先在原腰射坐标恢复袖根，避免Arms容器随枪转到画中央。
	_weapon_node.transform = _weapon_home
	_native_arms.pose_hold(0.0)
	_weapon_node.transform = _weapon_home * Transform3D(
		Basis.from_euler((profile.reload_cant as Vector3) * weight), (profile.reload_lift as Vector3) * weight)
	_loading_missile.transform = _loading_home
	# 源弹头为-Z；由真实AABB鼻端推至后膛，完整入筒时尾端恰好齐后口。
	_loading_missile.position = _rear_reload_nose(progress) - Vector3(0, 0, _missile_bounds.position.z)
	_loading_missile.visible = progress >= GameConfig.EM120R_REAR_SHOW_PHASE and progress < seat
	_native_arms.pose_right_grip()
	var support: Vector3 = profile.support_grip_hip
	var hand: Vector3 = _loading_missile.position + GameConfig.EM120R_REAR_MISSILE_GRIP
	if progress < contact:
		hand = support.lerp(hand, smoothstep(0.0, contact, progress))
	elif progress > release:
		# 提前放开尾段；先退到筒外左下，再回前支撑，不跟导弹深入筒内。
		var release_hand := _rear_reload_nose(release) - Vector3(0, 0, _missile_bounds.position.z) + GameConfig.EM120R_REAR_MISSILE_GRIP
		var clear_hand: Vector3 = release_hand + GameConfig.EM120R_REAR_HAND_CLEARANCE
		if progress < seat:
			hand = release_hand.lerp(clear_hand, smoothstep(release, seat, progress))
		else:
			hand = clear_hand.lerp(support, smoothstep(seat, 1.0, progress))
	var hand_world := _weapon_node.to_global(hand)
	var hand_basis: Basis = _native_arms.support_basis_world()
	# 尾段装填选择下后方肩锚，避免超臂展时沿旧肩方向重锚进屏。
	# 实际掌面不是腕心；先按同一蒙皮掌面偏移反解目标腕，再平滑摆原上臂锚。
	var upper_bone: int = _native_arms._uppers[1]
	var wrist_bone: int = _native_arms._wrists[1]
	var wrist_pose := _arms_skeleton.get_bone_global_pose(wrist_bone)
	var palm_offset: Vector3 = wrist_pose.affine_inverse() * _native_arms._palm_position(1)
	var wrist_basis := (_arms_skeleton.global_basis.inverse() * hand_basis).orthonormalized()
	var wrist_target := _arms_skeleton.global_transform.affine_inverse() * hand_world - wrist_basis * palm_offset
	var shoulder_direction := (_arms_skeleton.global_basis.inverse() * _view_model.global_basis
		* GameConfig.EM120R_REAR_SHOULDER_DIRECTION).normalized()
	var source_reach: float = (_native_arms._upper_lengths[1] + _native_arms._fore_lengths[1]) \
		* GameConfig.BLACK_LONG_GUN_SHOULDER_REACH
	var upper_pose := _arms_skeleton.get_bone_global_pose(upper_bone)
	upper_pose.origin = upper_pose.origin.lerp(wrist_target + shoulder_direction * source_reach, weight)
	_arms_skeleton.set_bone_global_pose(upper_bone, upper_pose)
	_native_arms.pose_left_grip(hand_world, hand_basis)
	# 尾段远抓点重解前臂后，掌面中的前臂混合权重也随之变动。
	# 用第一次求解后的真实掌面再求一次，消除约3.2mm残差，不改源骨长/缩放。
	_native_arms.pose_left_grip(hand_world, hand_basis)
	_native_arms.update_bounds()


func _rear_reload_nose(progress: float) -> Vector3:
	var align: float = GameConfig.EM120R_REAR_ALIGN_PHASE
	var aligned: Vector3 = _rear_breech.position + Vector3(0, 0, GameConfig.EM120R_REAR_CLEARANCE)
	if progress <= align:
		return GameConfig.EM120R_REAR_START_NOSE.lerp(aligned,
			smoothstep(GameConfig.EM120R_REAR_CONTACT_PHASE, align, progress))
	var seated: Vector3 = _rear_breech.position - Vector3(0, 0, _missile_bounds.size.z)
	return aligned.lerp(seated, smoothstep(align, GameConfig.EM120R_REAR_SEAT_PHASE, progress))


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
		var receiver := hit.collider as Node3D
		if is_instance_valid(receiver):
			Events.explosion_surface_impacted.emit(hit.position, hit.normal, receiver)
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
		if _native_arms != null:
			_native_arms.begin_reload(weapon_data.reload_time)
			_update_rear_reload(0.0)


func _on_weapon_reloaded(weapon_id: StringName) -> void:
	if weapon_data.weapon_id != weapon_id:
		return
	_is_reloading = false
	_reset_supply_visuals()
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
		_reset_supply_visuals()


func _reset_supply_visuals() -> void:
	_weapon_node.transform = _weapon_home
	_loading_missile.transform = _loading_home
	_loading_missile.visible = false
	if _native_arms != null:
		_native_arms.reset()


## 复用已登记手臂与两骨 IK，双手独立标定到筒身握点，筒体保持肩位。
func _setup_shoulder_arms() -> void:
	var profile: Dictionary = GameConfig.BLACK_LONG_GUN_PROFILES.get(&"em120r", {})
	if not profile.is_empty():
		_native_arms = NativeLongGunArms.new()
		if not _native_arms.configure(_arms_node, _weapon_node, profile):
			push_error("EM-120R 原生黑臂未能解析源骨架和后膛装填抓点")
			_native_arms = null
			return
		_arms_skeleton = _native_arms.skeleton
		_arms_animation = _native_arms.animation
		return
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
