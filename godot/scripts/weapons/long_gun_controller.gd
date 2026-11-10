class_name LongGunController
extends WeaponController

const MagazineReloadMotion = preload("res://scripts/weapons/magazine_reload_motion.gd")

@export var weapon_node_path: NodePath = ^"ViewModel/Weapon"
@export var magazine_node_path: NodePath = ^"ViewModel/Weapon/Magazine"
@export var arms_alignment_node_path: NodePath
@export var arms_node_path: NodePath = ^"ViewModel/Arms"
@export var muzzle_node_path: NodePath = ^"ViewModel/Weapon/Muzzle"
@export var reserve_state_property: StringName = &""

const MAG_FRAME_JUMP_MAX := 0.09
const MAG_SEAT_RADIUS := 0.035
const RELOAD_MAX_CANT := deg_to_rad(22.0)

var _is_reloading: bool = false
var _reload_generation: int = 0
var _weapon_node: Node3D
var _magazine: Node3D
var _arms_node: Node3D
var _muzzle_node: Node3D
var _optic_node: MeshInstance3D
var _arms_animation: AnimationPlayer
var _arms_skeleton: Skeleton3D
var _mag_bone: int = -1
var _weapon_bone: int = -1
var _weapon_home := Transform3D.IDENTITY
var _mag_home_transform := Transform3D.IDENTITY
var _arms_placed := Transform3D.IDENTITY
var _weapon_motion_start := Transform3D.IDENTITY
var _mag_motion_start := Transform3D.IDENTITY
var _pose_extra := Transform3D.IDENTITY
var _mag_lock: bool = false
var _mag_hidden: bool = false
var _reload_counter: float = 0.0
var _reserve_key: StringName
var _aim_weight: float = 0.0
var _pose_pending: bool = false
var _arm_upper_len: float = 0.0
var _arm_fore_len: float = 0.0
var _right_upper_bone: int = -1
var _right_upper_hold_position := Vector3.ZERO
var _charge_elapsed: float = 0.0
var _charge_fired: bool = false
var _charged_shot: bool = false
var _magazine_reload: RefCounted


func _unhandled_input(event: InputEvent) -> void:
	if weapon_data.weapon_id != &"em127g":
		super(event)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not _is_current_weapon():
					return
				_trigger_held = true
				_on_trigger_pressed()
				return
			if _trigger_held and not _charge_fired and _charge_elapsed < GameConfig.EM127G_CHARGE_TIME and _fire_cooldown <= 0.0 and _is_current_weapon():
				_try_fire()
			_trigger_held = false
			_charge_elapsed = 0.0
			_charge_fired = false
			return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.keycode != KEY_R or not key.pressed or key.echo:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not _is_current_weapon():
		return
	_start_reload()


func _on_trigger_pressed() -> void:
	if weapon_data.weapon_id == &"em127g":
		_charge_elapsed = 0.0
		_charge_fired = false
		return
	super()


func _tick_weapon(delta: float) -> void:
	super(delta)
	if weapon_data.weapon_id != &"em127g":
		return
	if not _trigger_held or _is_reloading:
		_charge_elapsed = 0.0
		_charge_fired = false
		return
	if _charge_fired:
		return
	_charge_elapsed += delta
	if _charge_elapsed < GameConfig.EM127G_CHARGE_TIME:
		return
	_charge_fired = true
	_charged_shot = true
	_try_fire()
	_charged_shot = false


func _ready() -> void:
	super()
	_reserve_key = reserve_state_property if reserve_state_property != &"" else weapon_data.weapon_id + "_reserve"
	_weapon_node = get_node_or_null(weapon_node_path) as Node3D
	_magazine = get_node_or_null(magazine_node_path) as Node3D
	_arms_node = get_node_or_null(arms_node_path) as Node3D
	_muzzle_node = get_node_or_null(muzzle_node_path) as Node3D
	if _weapon_node != null:
		_weapon_home = _weapon_node.transform
		for node in _weapon_node.find_children("*", "MeshInstance3D", true, false):
			if String(node.name).to_lower().contains("optic"):
				_optic_node = node as MeshInstance3D
				break
	if _magazine != null:
		_mag_home_transform = _magazine.transform
	_setup_arms()
	Events.weapon_reload_started.connect(_on_reload_started)
	Events.weapon_reloaded.connect(_on_weapon_reloaded)
	_setup_magazine_reload()


func _setup_magazine_reload() -> void:
	var profile: Dictionary = GameConfig.MAGAZINE_RELOAD_PROFILES.get(weapon_data.weapon_id, {})
	if profile.is_empty() or _arms_skeleton == null or _magazine == null:
		return
	_magazine_reload = MagazineReloadMotion.new()
	_magazine_reload.setup(_arms_skeleton, _arms_node, _weapon_node, _magazine, profile)


func _setup_arms() -> void:
	if _arms_node == null or _weapon_node == null or _magazine == null:
		return
	var players := _arms_node.find_children("*", "AnimationPlayer", true, false)
	var skeletons := _arms_node.find_children("*", "Skeleton3D", true, false)
	if players.is_empty() or skeletons.is_empty():
		return
	_arms_animation = players[0] as AnimationPlayer
	_arms_skeleton = skeletons[0] as Skeleton3D
	_prepare_native_reload(&"Armature|Arms_FPS_Anim_Reload_Fast")
	_prepare_native_hold(&"Armature|Arms_FPS_Anim_Run")
	_mag_bone = _arms_skeleton.find_bone("Pmag_061")
	_weapon_bone = _arms_skeleton.find_bone("ACRRifle_058")
	if _mag_bone < 0 or _weapon_bone < 0:
		push_error("long gun: Cransh rifle bones missing")
		return
	_align_native_arms()
	_arms_placed = _arms_node.transform
	_measure_left_arm()
	if weapon_data.weapon_id in [&"shotgun", &"spas12"]:
		_right_upper_bone = _find_bone_by_prefix("UpArm_R")
		if _right_upper_bone >= 0:
			_right_upper_hold_position = _arms_skeleton.get_bone_pose_position(_right_upper_bone)
	_pose_pending = true
	_weapon_motion_start = _weapon_motion()
	_mag_motion_start = _magazine_motion()


func _prepare_native_reload(clip: StringName) -> void:
	var animation := _arms_animation.get_animation(clip).duplicate() as Animation
	var source_length := animation.length
	for track in animation.get_track_count():
		for key in animation.track_get_key_count(track):
			animation.track_set_key_time(track, key,
				animation.track_get_key_time(track, key) * weapon_data.reload_time / source_length)
	animation.length = weapon_data.reload_time
	_arms_animation.get_animation_library("").add_animation(&"reload", animation)


func _prepare_native_hold(clip: StringName) -> void:
	var animation := _arms_animation.get_animation(clip).duplicate() as Animation
	_arms_animation.get_animation_library("").add_animation(&"hold", animation)
	_arms_animation.play(&"hold")
	_arms_animation.seek(0.0, true)
	_arms_animation.pause()


func _align_native_arms() -> void:
	var chain: Transform3D = _arms_node.global_transform.affine_inverse() * _arms_skeleton.global_transform
	var weapon_bone_local := _arms_skeleton.get_bone_global_pose(_weapon_bone)
	var mag_bone_local := _arms_skeleton.get_bone_global_pose(_mag_bone)
	var basis := _weapon_node.global_basis.orthonormalized() * Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)) * weapon_bone_local.basis.orthonormalized().inverse()
	var alignment := get_node_or_null(arms_alignment_node_path) as Node3D
	var alignment_position := alignment.global_position if alignment != null else _magazine.global_position
	var origin := alignment_position - basis * mag_bone_local.origin
	var placed := Transform3D(basis, origin) * chain.affine_inverse()
	var arms_offset: Vector3 = GameConfig.DMR_ARMS_OFFSET if weapon_data.weapon_id in [&"dmr", &"spas12", &"em86s", &"em86d", &"em127g"] else GameConfig.SHOTGUN_ARMS_OFFSET
	placed.origin += _weapon_node.global_basis * arms_offset
	_arms_node.global_transform = placed
	for node in _arms_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or not mesh_instance.mesh.resource_name.contains("arms"):
			mesh_instance.visible = false


func _process(delta: float) -> void:
	super._process(delta)
	if _arms_skeleton == null or _weapon_bone < 0:
		return
	if _is_reloading and _magazine_reload != null and _magazine_reload.active:
		_magazine_reload.update(_arms_animation.current_animation_position / weapon_data.reload_time)
		return
	if _pose_pending:
		_pose_pending = false
		_apply_pose_rotation()
		_pose_left_arm_mainstream(_aim_weight)
	if not _is_reloading and _arms_animation != null and _arms_animation.has_animation(&"hold"):
		var aim_target := 1.0 if GameState.is_aiming else 0.0
		if not is_equal_approx(_aim_weight, aim_target):
			_aim_weight = move_toward(_aim_weight, aim_target, delta / GameConfig.ADS_LERP_TIME)
			_apply_pose_rotation()
			_pose_left_arm_mainstream(_aim_weight)
	elif _is_reloading:
		_reload_counter = lerpf(_reload_counter, _reload_cant_counter(), minf(delta * 10.0, 1.0))
		_apply_pose_rotation()
	if weapon_data.weapon_id == &"spas12":
		# 子类每帧重解右腕；稳定 ADS 与逐壳换弹也须从同一 hold 姿态开始。
		_pose_left_arm_mainstream(_aim_weight)
	_weapon_node.transform = _pose_extra * _weapon_home * _weapon_motion_start.affine_inverse() * _weapon_motion()
	if _mag_bone >= 0:
		if _is_reloading and not _mag_lock:
			_govern_magazine_motion()
		elif not _is_reloading:
			_magazine.transform = _mag_home_transform * _mag_motion_start.affine_inverse() * _magazine_motion()


func _apply_pose_rotation() -> void:
	var w := 1.0 - _aim_weight
	var yaw: float = GameConfig.DMR_HIP_POSE_YAW if weapon_data.weapon_id in [&"dmr", &"spas12", &"em86s", &"em86d", &"em127g"] else GameConfig.SHOTGUN_HIP_POSE_YAW
	var pitch: float = GameConfig.DMR_HIP_POSE_PITCH if weapon_data.weapon_id in [&"dmr", &"spas12", &"em86s", &"em86d", &"em127g"] else GameConfig.SHOTGUN_HIP_POSE_PITCH
	var q := Quaternion(Vector3.UP, yaw * w) * Quaternion(Vector3.RIGHT, pitch * w) * Quaternion(Vector3.BACK, _reload_counter)
	_pose_extra = Transform3D(Basis(q), Vector3.ZERO)
	if _arms_node != null:
		_arms_node.transform = _pose_extra * _arms_placed
	if _weapon_node != null:
		_weapon_node.transform = _pose_extra * _weapon_home


func _pose_left_arm_mainstream(weight: float = 0.0) -> void:
	# hold 只有右上臂旋转轨，seek 不会复位 IK 写入的肩部平移。
	if _right_upper_bone >= 0:
		_arms_skeleton.set_bone_pose_position(_right_upper_bone, _right_upper_hold_position)
	_arms_animation.seek(0.0, true)
	var uparm := _find_bone_by_prefix("UpArm_L")
	var fore := _find_bone_by_prefix("Forearm_L")
	var ctrl := _find_bone_by_prefix("IK_Hand_Cntrl_L")
	var hand := _find_bone_by_prefix("Hand_L")
	if uparm < 0 or fore < 0 or ctrl < 0 or hand < 0 or _arm_upper_len <= 0.0 or _arm_fore_len <= 0.0:
		return
	var to_skel_from_weapon: Transform3D = _arms_skeleton.global_transform.affine_inverse() * _weapon_node.global_transform
	var hip: Vector3 = GameConfig.DMR_SUPPORT_WRIST_HIP if weapon_data.weapon_id in [&"dmr", &"spas12", &"em86s", &"em86d", &"em127g"] else GameConfig.SHOTGUN_SUPPORT_WRIST_HIP
	var ads: Vector3 = GameConfig.DMR_SUPPORT_WRIST_ADS if weapon_data.weapon_id in [&"dmr", &"em86s", &"em86d"] else GameConfig.SHOTGUN_SUPPORT_WRIST_ADS
	if weapon_data.weapon_id == &"spas12":
		ads = GameConfig.SPAS12_SUPPORT_WRIST_ADS
	var wrist_t := to_skel_from_weapon * hip.lerp(ads, weight)
	var shoulder_t := wrist_t + to_skel_from_weapon.basis * (GameConfig.LONG_GUN_SHOULDER_DIRECTION.normalized() * (_arm_upper_len + _arm_fore_len) * 0.94)
	var pole_offset: Vector3 = Vector3(0.08, -0.35, 0.22) if weapon_data.weapon_id in [&"dmr", &"spas12", &"em86s", &"em86d", &"em127g"] else GameConfig.SHOTGUN_ELBOW_POLE
	var pole_t := wrist_t + to_skel_from_weapon.basis * pole_offset
	var d := wrist_t - shoulder_t
	var dist := clampf(d.length(), absf(_arm_upper_len - _arm_fore_len) + 0.001, _arm_upper_len + _arm_fore_len - 0.001)
	d = d.normalized()
	var a := (_arm_upper_len * _arm_upper_len - _arm_fore_len * _arm_fore_len + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(0.0, _arm_upper_len * _arm_upper_len - a * a))
	var pole_off := pole_t - shoulder_t
	pole_off -= d * pole_off.dot(d)
	pole_off = pole_off / maxf(pole_off.length(), 0.0001)
	var elbow_t := shoulder_t + d * a + pole_off * h
	var up_g := _arms_skeleton.get_bone_global_pose(uparm)
	_arms_skeleton.set_bone_global_pose(uparm, Transform3D(up_g.basis, shoulder_t))
	_aim_bone_y_at(uparm, elbow_t)
	_aim_bone_y_at(fore, wrist_t)
	var fore_g := _arms_skeleton.get_bone_global_pose(fore)
	var wrist_end := fore_g.origin + fore_g.basis.y * _arm_fore_len
	var ctrl_g := _arms_skeleton.get_bone_global_pose(ctrl)
	_arms_skeleton.set_bone_global_pose(ctrl, Transform3D(ctrl_g.basis, wrist_end))
	var hand_g := _arms_skeleton.get_bone_global_pose(hand)
	var muzzle_dir := to_skel_from_weapon.basis * Vector3(0.0, 0.0, -1.0)
	var palm_rot := Quaternion(hand_g.basis.y, muzzle_dir)
	_arms_skeleton.set_bone_global_pose(hand, Transform3D(Basis(palm_rot) * hand_g.basis, hand_g.origin))
	if weapon_data.weapon_id in [&"shotgun", &"spas12"] and weight > 0.0:
		_pose_right_arm_shotgun(weight)


func _pose_right_arm_shotgun(weight: float) -> void:
	var uparm := _find_bone_by_prefix("UpArm_R")
	var fore := _find_bone_by_prefix("Forearm_R")
	var ctrl := _find_bone_by_prefix("IK_Hand_Cntrl_R")
	var hand := _find_bone_by_prefix("Hand_R")
	if uparm < 0 or fore < 0 or ctrl < 0 or hand < 0:
		return
	if uparm == _right_upper_bone:
		_arms_skeleton.set_bone_pose_position(uparm, _right_upper_hold_position)
	var wrist_t := _arms_skeleton.get_bone_global_pose(hand).origin
	var upper_len := _arms_skeleton.get_bone_global_pose(uparm).origin.distance_to(_arms_skeleton.get_bone_global_pose(fore).origin)
	var fore_len := _arms_skeleton.get_bone_global_pose(fore).origin.distance_to(wrist_t)
	var to_skel_from_weapon: Transform3D = _arms_skeleton.global_transform.affine_inverse() * _weapon_node.global_transform
	var shoulder_t := wrist_t + to_skel_from_weapon.basis * (GameConfig.LONG_GUN_SHOULDER_DIRECTION.normalized() * (upper_len + fore_len) * 0.94)
	var pole_t := wrist_t + to_skel_from_weapon.basis * (GameConfig.SHOTGUN_RIGHT_ELBOW_POLE * weight)
	var d := wrist_t - shoulder_t
	var dist := clampf(d.length(), absf(upper_len - fore_len) + 0.001, upper_len + fore_len - 0.001)
	d = d.normalized()
	var a := (upper_len * upper_len - fore_len * fore_len + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(0.0, upper_len * upper_len - a * a))
	var pole_off := pole_t - shoulder_t
	pole_off -= d * pole_off.dot(d)
	pole_off /= maxf(pole_off.length(), 0.0001)
	var elbow_t := shoulder_t + d * a + pole_off * h
	var up_g := _arms_skeleton.get_bone_global_pose(uparm)
	_arms_skeleton.set_bone_global_pose(uparm, Transform3D(up_g.basis, shoulder_t))
	_aim_bone_y_at(uparm, elbow_t)
	_aim_bone_y_at(fore, wrist_t)
	var fore_g := _arms_skeleton.get_bone_global_pose(fore)
	var wrist_end := fore_g.origin + fore_g.basis.y * fore_len
	var ctrl_g := _arms_skeleton.get_bone_global_pose(ctrl)
	_arms_skeleton.set_bone_global_pose(ctrl, Transform3D(ctrl_g.basis, wrist_end))


func _find_bone_by_prefix(prefix: String) -> int:
	for b in _arms_skeleton.get_bone_count():
		if _arms_skeleton.get_bone_name(b).begins_with(prefix):
			return b
	return -1


func _measure_left_arm() -> void:
	var uparm := _find_bone_by_prefix("UpArm_L")
	var fore := _find_bone_by_prefix("Forearm_L")
	var hand := _find_bone_by_prefix("Hand_L")
	if uparm < 0 or fore < 0 or hand < 0:
		return
	var g_u := _arms_skeleton.get_bone_global_pose(uparm).origin
	var g_f := _arms_skeleton.get_bone_global_pose(fore).origin
	var g_h := _arms_skeleton.get_bone_global_pose(hand).origin
	_arm_upper_len = g_u.distance_to(g_f)
	_arm_fore_len = g_f.distance_to(g_h)


func _aim_bone_y_at(bone: int, target_pos: Vector3) -> void:
	var g := _arms_skeleton.get_bone_global_pose(bone)
	var rot := Quaternion(g.basis.y, (target_pos - g.origin).normalized())
	_arms_skeleton.set_bone_global_pose(bone, Transform3D(Basis(rot) * g.basis, g.origin))


func _reload_cant_counter() -> float:
	var delta := _weapon_motion_start.affine_inverse() * _weapon_motion()
	var q := delta.basis.get_rotation_quaternion()
	if q.get_angle() < 0.01:
		return 0.0
	var roll := q.get_angle() * signf(q.get_axis().z)
	return roll - clampf(roll, -RELOAD_MAX_CANT, RELOAD_MAX_CANT)


func _weapon_motion() -> Transform3D:
	var raw: Transform3D = _view_model.global_transform.affine_inverse() * _arms_skeleton.global_transform * _arms_skeleton.get_bone_global_pose(_weapon_bone)
	return _pose_extra.affine_inverse() * raw


func _magazine_motion() -> Transform3D:
	return _magazine.get_parent().global_transform.affine_inverse() * _arms_skeleton.global_transform * _arms_skeleton.get_bone_global_pose(_mag_bone)


func _govern_magazine_motion() -> void:
	var candidate: Transform3D = _mag_home_transform * _mag_motion_start.affine_inverse() * _magazine_motion()
	if _mag_hidden:
		if candidate.origin.distance_to(_mag_home_transform.origin) <= MAG_SEAT_RADIUS:
			_mag_lock = true
			_mag_hidden = false
			_magazine.transform = _mag_home_transform
			_magazine.visible = true
		return
	if candidate.origin.distance_to(_magazine.transform.origin) > MAG_FRAME_JUMP_MAX:
		_mag_hidden = true
		_magazine.visible = false
		return
	_magazine.transform = candidate


func _exit_tree() -> void:
	if Events.weapon_reload_started.is_connected(_on_reload_started):
		Events.weapon_reload_started.disconnect(_on_reload_started)
	if Events.weapon_reloaded.is_connected(_on_weapon_reloaded):
		Events.weapon_reloaded.disconnect(_on_weapon_reloaded)
	super()



func _fire() -> bool:
	if _is_reloading:
		return false
	var weapon_id := weapon_data.weapon_id
	if int(GameState.get(weapon_id + "_mag")) <= 0:
		_start_reload()
		return false
	GameState.set(weapon_id + "_mag", int(GameState.get(weapon_id + "_mag")) - 1)
	Events.ammo_changed.emit(weapon_id, GameState.get(weapon_id + "_mag"), GameState.get(_reserve_key))
	Events.weapon_fired.emit(weapon_id)
	if _charged_shot and weapon_id == &"em127g":
		Events.weapon_charge_fired.emit(weapon_id)
	Events.player_muzzle_flash.emit(weapon_id, _muzzle_position())
	var shot_damage: float = GameConfig.EM127G_CHARGED_DAMAGE_BODY if _charged_shot and weapon_id == &"em127g" else weapon_data.damage_body
	var total_damage := 0.0
	var any_headshot := false
	var any_hit := false
	var ricochet_reported := false
	var first_hit := _cast_spread_ray(0.0)
	var first_distance := weapon_data.hitscan_range
	if not first_hit.is_empty():
		first_distance = global_position.distance_to(first_hit.position)
	var spread := _spread_for_distance(first_distance)
	for pellet in weapon_data.pellet_count:
		var hit := _cast_spread_ray(spread)
		if hit.is_empty():
			continue
		var collider: Object = hit.collider
		if HitSolver.find_group_ancestor(collider, &"bunker") != null:
			Events.bullet_impacted.emit(hit.position, hit.normal, true)
			Events.bullet_mark_requested.emit(hit.position, hit.normal, collider as Node3D)
			if not ricochet_reported:
				Events.ricochet_on_bunker.emit()
				ricochet_reported = true
			continue
		var target := HitSolver.find_damageable(collider)
		if target == null:
			Events.bullet_impacted.emit(hit.position, hit.normal, HitSolver.is_metal_surface(collider))
			Events.bullet_mark_requested.emit(hit.position, hit.normal, collider as Node3D)
			continue
		var is_head := HitSolver.is_headshot(collider)
		var damage: float = shot_damage * (weapon_data.headshot_factor if is_head else 1.0)
		if not _charged_shot and HitSolver.find_group_ancestor(collider, &"sniper") != null:
			damage = weapon_data.dmg_vs_sniper
		target.take_damage(damage, is_head)
		total_damage += damage
		any_headshot = any_headshot or is_head
		any_hit = true
	if any_hit:
		Events.damage_dealt.emit(total_damage, any_headshot)
		Events.hit_confirmed.emit(any_headshot)
	_apply_recoil()
	return true


func _muzzle_position() -> Vector3:
	if _muzzle_node != null:
		return _muzzle_node.global_position
	return global_position + (-global_transform.basis.z) * GameConfig.PLAYER_MUZZLE_OFFSET


func _cast_spread_ray(spread: float) -> Dictionary:
	var local_dir := Vector3(randf_range(-spread, spread), randf_range(-spread, spread), -1.0).normalized()
	var from := global_position
	var to: Vector3 = from + (global_transform.basis * local_dir) * weapon_data.hitscan_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = HitSolver.collect_owner_rids(self)
	query.collide_with_areas = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _spread_for_distance(distance: float) -> float:
	if weapon_data.weapon_id in [&"shotgun", &"em12g2"] and distance <= GameConfig.SHOTGUN_SPREAD_START:
		return 0.0
	return _current_spread()


func _current_spread() -> float:
	if GameState.is_aiming:
		return weapon_data.spread_aim
	if GameState.is_prone:
		return weapon_data.spread_prone
	return weapon_data.spread_hip


func _start_reload() -> void:
	var weapon_id := weapon_data.weapon_id
	if _is_reloading or int(GameState.get(_reserve_key)) <= 0:
		return
	if int(GameState.get(weapon_id + "_mag")) >= weapon_data.mag_size:
		return
	_reload_generation += 1
	var generation := _reload_generation
	Events.weapon_reload_started.emit(weapon_id)
	await get_tree().create_timer(weapon_data.reload_time).timeout
	if not is_instance_valid(self) or generation != _reload_generation:
		return
	Events.weapon_reloaded.emit(weapon_id)


func _on_reload_started(weapon_id: StringName) -> void:
	if weapon_id != weapon_data.weapon_id:
		return
	_is_reloading = true
	_play_reload_anim()


func _play_reload_anim() -> void:
	_mag_lock = false
	_mag_hidden = false
	if _magazine != null:
		_magazine.transform = _mag_home_transform
		_magazine.visible = true
	if _magazine_reload != null:
		_magazine_reload.begin()
	if _arms_skeleton != null:
		_weapon_motion_start = _weapon_motion()
		_mag_motion_start = _magazine_motion()
	if _arms_animation != null and _arms_animation.has_animation(&"reload"):
		_arms_animation.play(&"reload", 0.15)
		_arms_animation.advance(0.0)


func _on_weapon_switched(weapon_id: StringName) -> void:
	super._on_weapon_switched(weapon_id)
	if weapon_id != weapon_data.weapon_id:
		_is_reloading = false
		_reload_generation += 1
	_reset_reload_visuals()


func _reset_reload_visuals() -> void:
	if _magazine_reload != null:
		_magazine_reload.reset()
	_reload_counter = 0.0
	_pose_extra = Transform3D.IDENTITY
	_mag_lock = false
	_mag_hidden = false
	if _weapon_node != null:
		_weapon_node.transform = _weapon_home
	if _magazine != null:
		_magazine.transform = _mag_home_transform
		_magazine.visible = true
	if _arms_animation != null and _arms_animation.has_animation(&"hold"):
		_arms_animation.play(&"hold")
		_arms_animation.seek(0.0, true)
		_arms_animation.pause()
	if _arms_node != null:
		_arms_node.transform = _arms_placed
	_apply_pose_rotation()
	if _arms_animation != null and _arms_animation.has_animation(&"hold"):
		_pose_left_arm_mainstream(_aim_weight)
	if _arms_skeleton != null and _weapon_bone >= 0:
		_weapon_motion_start = _weapon_motion()
		_mag_motion_start = _magazine_motion()


func _on_weapon_reloaded(weapon_id: StringName) -> void:
	if weapon_id != weapon_data.weapon_id:
		return
	_reset_reload_visuals()
	_is_reloading = false
	var mag := int(GameState.get(weapon_id + "_mag"))
	var reserve := int(GameState.get(_reserve_key))
	var take: int = mini(weapon_data.mag_size - mag, reserve)
	GameState.set(weapon_id + "_mag", mag + take)
	GameState.set(_reserve_key, reserve - take)
	Events.ammo_changed.emit(weapon_id, mag + take, reserve - take)
