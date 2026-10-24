## PistolController — EM-57P「掣」手枪 hitscan 半自动（W2 火力蜂）
##
## 参数基准（2026-10-19 机主立项，EDAA 雷械谱系；2026-10-22 伤害改按弹药口径）：45/爆头90 伤害（EC-57 手枪弹）· 半自动 ≤400RPM ·
## 30/120 弹药 · 1.6s 换弹 · 三档散布（腰射 0.006 / 趴 0.003 / 瞄 0.001）·
## 后坐每发 +0.002 rad 带相机恢复（设定：后坐仅 .22 级）。
##
## 结构与 rifle_controller.gd 同款（信号序列/散布/换弹三件套一致），差异：
## - 半自动：左键按下边沿击发一次（基类 _on_trigger_pressed 钩子），不按 fire_interval 连发；
## - 弹药走 GameState.pistol_mag / pistol_reserve 契约字段。
extends WeaponController

## 射击模式机制已上收基类（2026-10-19：半自动/三发点射/全自动三档，X 键切换）；
## 本子类只保留弹药结算、散布射线与换弹三件套。
var _is_reloading: bool = false
var _reload_generation: int = 0

# Cransh 源动画重定向到 RafaP 手臂；magazine_motion 与左手共享同一右手参考系。
@onready var _magazine: Node3D = get_node_or_null("ViewModel/EM57P/em57p_magazine")
var _mag_home: Vector3 = Vector3.ZERO
var _mag_home_basis: Basis = Basis.IDENTITY
var _arms_animation: AnimationPlayer = null
var _arms_skeleton: Skeleton3D = null
var _mag_bone: int = -1
var _mag_motion_start: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	super()
	if _magazine != null:
		_mag_home = _magazine.position
		_mag_home_basis = _magazine.basis
	var players := $ViewModel/ArmsEM57P.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_arms_animation = players[0] as AnimationPlayer
	var skeletons := $ViewModel/ArmsEM57P.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_arms_skeleton = skeletons[0] as Skeleton3D
		_mag_bone = _arms_skeleton.find_bone("magazine_motion")
	Events.weapon_reload_started.connect(_on_reload_started)
	Events.weapon_reloaded.connect(_on_weapon_reloaded)


func _process(delta: float) -> void:
	super._process(delta)
	if not _is_reloading or _arms_skeleton == null:
		return
	if _magazine != null and _mag_bone >= 0:
		var motion := _magazine_motion()
		_magazine.position = _mag_home + motion.origin - _mag_motion_start.origin
		_magazine.basis = _mag_home_basis * (_mag_motion_start.basis.inverse() * motion.basis).orthonormalized()


func _magazine_motion() -> Transform3D:
	return _magazine.get_parent().global_transform.affine_inverse() * _arms_skeleton.global_transform * _arms_skeleton.get_bone_global_pose(_mag_bone)


func _exit_tree() -> void:
	Events.weapon_reload_started.disconnect(_on_reload_started)
	Events.weapon_reloaded.disconnect(_on_weapon_reloaded)
	super()


## R 键换弹监听：门控与基类左键开火同款——仅鼠标捕获态 + 当前手持武器响应。
func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.keycode != KEY_R or not key.pressed or key.echo:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not _is_current_weapon():
		return
	_start_reload()


## 半自动/点射/全自动 tick 已收口基类（_on_trigger_pressed/_tick_weapon）；本子类仅实现单发流程。


## 单发流程：弹药门控 → 扣弹广播 → 后坐 → 散布射线 → 命中结算。返回是否真正击发。
func _fire() -> bool:
	if _is_reloading:
		return false
	if GameState.pistol_mag <= 0:
		# 弹尽自动换弹（与步枪同口径）。
		_start_reload()
		return false

	GameState.pistol_mag -= 1
	Events.ammo_changed.emit(&"pistol", GameState.pistol_mag, GameState.pistol_reserve)
	Events.weapon_fired.emit(&"pistol")
	# 微弱青蓝枪口焰（与步枪同口径）。
	Events.player_muzzle_flash.emit(&"pistol",
		global_position + (-global_transform.basis.z) * GameConfig.PLAYER_MUZZLE_OFFSET)
	_apply_recoil()

	var hit := _cast_spread_ray()
	if hit.is_empty():
		return true
	var collider: Object = hit.collider

	# 碉堡跳弹：提示需用火箭筒；碉体为金属，附带火星+弹痕。
	if HitSolver.find_group_ancestor(collider, &"bunker") != null:
		Events.bullet_impacted.emit(hit.position, hit.normal, true)
		Events.ricochet_on_bunker.emit()
		return true

	var target := HitSolver.find_damageable(collider)
	if target == null:
		# 命中环境：弹坑贴花；金属表面加溅射火星。
		Events.bullet_impacted.emit(hit.position, hit.normal, HitSolver.is_metal_surface(collider))
		return true

	var is_head := HitSolver.is_headshot(collider)
	var damage: float = weapon_data.damage_body * (weapon_data.headshot_factor if is_head else 1.0)
	if HitSolver.find_group_ancestor(collider, &"sniper") != null:
		damage = weapon_data.dmg_vs_sniper
	target.take_damage(damage, is_head)
	Events.damage_dealt.emit(damage, is_head)
	Events.hit_confirmed.emit(is_head)
	return true


## 散布射线：与步枪同款（武器原点沿 -Z 局部空间角偏移）。
func _cast_spread_ray() -> Dictionary:
	var spread := _current_spread()
	var local_dir := Vector3(
		randf_range(-spread, spread),
		randf_range(-spread, spread),
		-1.0
	).normalized()
	var from := global_position
	var to: Vector3 = from + (global_transform.basis * local_dir) * weapon_data.hitscan_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = HitSolver.collect_owner_rids(self)
	query.collide_with_areas = true
	return get_world_3d().direct_space_state.intersect_ray(query)


## 三档散布：瞄准 > 趴下 > 腰射。
func _current_spread() -> float:
	if GameState.is_aiming:
		return weapon_data.spread_aim
	if GameState.is_prone:
		return weapon_data.spread_prone
	return weapon_data.spread_hip


## 换弹启动（R 键手动 / 弹尽自动共用）：自发 started →（reload_time）→ reloaded 信号序列。
func _start_reload() -> void:
	if _is_reloading or GameState.pistol_reserve <= 0:
		return
	if GameState.pistol_mag >= weapon_data.mag_size:
		return
	_reload_generation += 1
	var generation := _reload_generation
	Events.weapon_reload_started.emit(&"pistol")
	await get_tree().create_timer(weapon_data.reload_time).timeout
	if not is_instance_valid(self) or generation != _reload_generation:
		return
	Events.weapon_reloaded.emit(&"pistol")


func _on_reload_started(weapon_id: StringName) -> void:
	if weapon_id == &"pistol":
		_is_reloading = true
		_play_reload_anim()


func _play_reload_anim() -> void:
	_set_sleeve_extenders_visible(false)
	if _magazine != null:
		_magazine.position = _mag_home
		_magazine.basis = _mag_home_basis
	if _arms_animation != null and _arms_animation.has_animation(&"reload"):
		_arms_animation.play(&"reload")
		_arms_animation.advance(0.0)
	if _arms_skeleton != null and _mag_bone >= 0:
		_mag_motion_start = _magazine_motion()


func _on_weapon_switched(weapon_id: StringName) -> void:
	super._on_weapon_switched(weapon_id)
	if weapon_id != weapon_data.weapon_id:
		_is_reloading = false
		_reload_generation += 1
	_reset_reload_visuals()


func _reset_reload_visuals() -> void:
	if _magazine != null:
		_magazine.position = _mag_home
		_magazine.basis = _mag_home_basis
		_magazine.visible = true
	if _arms_animation != null and _arms_animation.has_animation(&"reload"):
		_arms_animation.play(&"reload")
		_arms_animation.advance(0.0)
		_arms_animation.stop()
	_set_sleeve_extenders_visible(true)


func _set_sleeve_extenders_visible(value: bool) -> void:
	for sleeve in $ViewModel/ArmsEM57P.find_children("sleeve_ext_*", "Node3D", true, false):
		(sleeve as Node3D).visible = value


## 换弹完成：标准弹药迁移（弹匣缺口 ← 备弹），广播 ammo_changed。
func _on_weapon_reloaded(weapon_id: StringName) -> void:
	if weapon_id != &"pistol":
		return
	_reset_reload_visuals()
	_is_reloading = false
	var need: int = weapon_data.mag_size - GameState.pistol_mag
	var take: int = mini(need, GameState.pistol_reserve)
	GameState.pistol_mag += take
	GameState.pistol_reserve -= take
	Events.ammo_changed.emit(&"pistol", GameState.pistol_mag, GameState.pistol_reserve)
