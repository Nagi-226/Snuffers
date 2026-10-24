## RifleController — 步枪 hitscan（W2 火力蜂）
##
## 参数基准（§7 对照表 G2 行；2026-10-22 机主裁决伤害改按弹药口径）：75/爆头150 伤害（EC-68 步枪弹）· 800RPM 连发档 · 60/600 弹药 ·
## 2s 换弹 · 三档散布（腰射 0.004 / 趴 0.002 / 瞄 0.0005，瞄准优先，index.html L2966-2967）·
## 后坐每发 +0.003 rad 带相机恢复（修正网页版永久上跳缺陷）。
##
## 解耦：
## - 伤害结算：射线命中 → HitSolver 鸭子探测 take_damage，禁止引用 enemies 域节点；
##   take_damage 保留为投递机制，随后发 Events.damage_dealt(amount, is_headshot)
##   供 HUD 伤害飘字消费（G2 冻结信号，与 hit_confirmed 互补）。
## - 命中反馈：Events.hit_confirmed(is_headshot)（契约已有，HUD 准星 1.3×/1.8× 由 W5 消费）。
## - 碉堡跳弹：Events.ricochet_on_bunker()（契约已有）。
##
## 换弹责任划分（蜂后裁决：换弹归武器域自足，W1 已移除 player_controller 占位分发）：
## R 键监听在本脚本 _unhandled_input（门控与基类左键开火同款），
## 本脚本监听 Events.weapon_reload_started/reloaded 做状态封锁与弹药结算；
## 弹尽自动换弹（网页版 L2954）与 R 键手动换弹共用 _start_reload，两条路径信号序列一致。
extends WeaponController

## 射击模式机制已上收基类（2026-10-19：半自动/三发点射/全自动三档，X 键切换）；
## 本子类只保留弹药结算、散布射线与换弹三件套。
var _is_reloading: bool = false
var _reload_generation: int = 0

# Cransh 源动画重定向到 RafaP 手臂；magazine_motion 与左手共享同一右手参考系。
@onready var _magazine: Node3D = get_node_or_null("ViewModel/EM68A/em68a_magazine")
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
	var players := $ViewModel/ArmsEM68A.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_arms_animation = players[0] as AnimationPlayer
	var skeletons := $ViewModel/ArmsEM68A.find_children("*", "Skeleton3D", true, false)
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
## RPG 无换弹概念，故监听放本子类而非基类。
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


## 全自动/点射 tick 已收口基类（_tick_weapon）；本子类仅实现单发流程。


## 单发流程：榴档分流投射物；否则弹药门控 → 扣弹广播 → 后坐 → 散布射线 → 命中结算。
## 返回是否真正击发。
func _fire() -> bool:
	if _current_fire_mode() == &"grenade":
		return _fire_grenade()
	if _is_reloading:
		return false
	if GameState.rifle_mag <= 0:
		# 网页版弹尽自动换弹（index.html L2954）。
		_start_reload()
		return false

	GameState.rifle_mag -= 1
	Events.ammo_changed.emit(&"rifle", GameState.rifle_mag, GameState.rifle_reserve)
	Events.weapon_fired.emit(&"rifle")
	# 微弱青蓝枪口焰（2026-10-19 机主立项）：炮口近似位 = 武器原点沿 -Z 前移 PLAYER_MUZZLE_OFFSET。
	Events.player_muzzle_flash.emit(&"rifle",
		global_position + (-global_transform.basis.z) * GameConfig.PLAYER_MUZZLE_OFFSET)
	_apply_recoil()

	var hit := _cast_spread_ray()
	if hit.is_empty():
		return true
	var collider: Object = hit.collider

	# 碉堡跳弹：提示需用火箭筒（index.html L2973-2980）；碉体为金属，附带火星+弹痕。
	if HitSolver.find_group_ancestor(collider, &"bunker") != null:
		Events.bullet_impacted.emit(hit.position, hit.normal, true)
		Events.ricochet_on_bunker.emit()
		return true

	var target := HitSolver.find_damageable(collider)
	if target == null:
		# 命中环境（墙/地/金属物件）：弹坑贴花；金属表面加溅射火星（2026-10-19 机主立项）。
		Events.bullet_impacted.emit(hit.position, hit.normal, HitSolver.is_metal_surface(collider))
		return true

	var is_head := HitSolver.is_headshot(collider)
	var damage: float = weapon_data.damage_body * (weapon_data.headshot_factor if is_head else 1.0)
	# 狙击手固定伤害（index.html L3014：网页版不分部位一律 999）。
	if HitSolver.find_group_ancestor(collider, &"sniper") != null:
		damage = weapon_data.dmg_vs_sniper
	target.take_damage(damage, is_head)
	# G2 冻结契约：HUD 伤害飘字（与 hit_confirmed 互补；狙击手固定伤害如实广播）。
	Events.damage_dealt.emit(damage, is_head)
	Events.hit_confirmed.emit(is_head)
	return true


## 榴档单发（EM-40G「滚雷」，2026-10-22 机主裁决并入第四射击档）：
## 模块 6 发弹匣=雷池（GameState.rifle_grenades 总数制，无换弹）；投射物复用
## rpg_projectile 链路（直射档参数：GRENADE_* 契约组，平直弹道微下坠）。
## 「闸不合，榴不发」——本路径只在 &"grenade" 档下可达，实弹击发互斥。
func _fire_grenade() -> bool:
	if _is_reloading:
		return false
	if GameState.rifle_grenades <= 0:
		Events.message_posted.emit("滚雷模块弹药耗尽")
		return false
	if weapon_data.projectile_scene == null:
		push_error("rifle.tres 未配置 projectile_scene（EM-40G 投射物）")
		return false
	GameState.rifle_grenades -= 1
	Events.ammo_changed.emit(&"rifle", GameState.rifle_grenades, -1)
	Events.weapon_fired.emit(&"grenade")
	_apply_recoil()
	var projectile: Node3D = weapon_data.projectile_scene.instantiate()
	# 投射物挂到关卡根（武器随玩家移动，投射物需独立存在于世界空间）。
	var container: Node = get_tree().current_scene
	if container == null:
		container = get_tree().root
	container.add_child(projectile)
	# 出膛点 = 武器原点 前移 GRENADE_LAUNCH_FORWARD + 下移 GRENADE_LAUNCH_DROP
	# （下挂发射管位于护木前下方；方向仍取相机 -Z 保证准星所指即弹道所向）。
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


## 散布射线：从武器原点（挂 WeaponMount，即炮口）沿 -Z，
## 局部空间角偏移近似网页版 NDC 散布（数值沿用 §7 对照表）。
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


## 三档散布：瞄准 > 趴下 > 腰射（index.html L2966-2967）。
func _current_spread() -> float:
	if GameState.is_aiming:
		return weapon_data.spread_aim
	if GameState.is_prone:
		return weapon_data.spread_prone
	return weapon_data.spread_hip


## 换弹启动（R 键手动 / 弹尽自动共用）：自发 started →（reload_time）→ reloaded 信号序列。
## 守卫：换弹中 / 无备弹 / 弹匣已满时不触发。
func _start_reload() -> void:
	if _is_reloading or GameState.rifle_reserve <= 0:
		return
	if GameState.rifle_mag >= weapon_data.mag_size:
		return
	_reload_generation += 1
	var generation := _reload_generation
	Events.weapon_reload_started.emit(&"rifle")
	await get_tree().create_timer(weapon_data.reload_time).timeout
	if not is_instance_valid(self) or generation != _reload_generation:
		return
	Events.weapon_reloaded.emit(&"rifle")


func _on_reload_started(weapon_id: StringName) -> void:
	if weapon_id == &"rifle":
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
	for sleeve in $ViewModel/ArmsEM68A.find_children("sleeve_ext_*", "Node3D", true, false):
		(sleeve as Node3D).visible = value


## 换弹完成：标准弹药迁移（弹匣缺口 ← 备弹），广播 ammo_changed。
func _on_weapon_reloaded(weapon_id: StringName) -> void:
	if weapon_id != &"rifle":
		return
	_reset_reload_visuals()
	_is_reloading = false
	var need: int = weapon_data.mag_size - GameState.rifle_mag
	var take: int = mini(need, GameState.rifle_reserve)
	GameState.rifle_mag += take
	GameState.rifle_reserve -= take
	Events.ammo_changed.emit(&"rifle", GameState.rifle_mag, GameState.rifle_reserve)
