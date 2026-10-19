## PistolController — EM-57P「掣」手枪 hitscan 半自动（W2 火力蜂）
##
## 参数基准（2026-10-19 机主立项，EDAA 雷械谱系）：15/爆头30 伤害 · 半自动 ≤400RPM ·
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

# 程序化换弹动画（同 EM-68A 方案）：弹匣节点带枢轴原点（匣顶面心，DSH 派单 15/17），
# 绕原点旋转/平移即自然脱匣-插匣。无弹匣节点时静默跳过（灰盒/测试场景兼容）。
@onready var _magazine: Node3D = get_node_or_null("ViewModel/EM57P/em57p_magazine")
var _mag_home: Vector3 = Vector3.ZERO
var _mag_tween: Tween = null


func _ready() -> void:
	super()
	if _magazine != null:
		_mag_home = _magazine.position
	Events.weapon_reload_started.connect(_on_reload_started)
	Events.weapon_reloaded.connect(_on_weapon_reloaded)


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
	Events.weapon_reload_started.emit(&"pistol")
	await get_tree().create_timer(weapon_data.reload_time).timeout
	if not is_instance_valid(self):
		return
	Events.weapon_reloaded.emit(&"pistol")


func _on_reload_started(weapon_id: StringName) -> void:
	if weapon_id == &"pistol":
		_is_reloading = true
		_play_reload_anim()


## 程序化换弹动画：与 EM-68A 同款三段——卸匣（下坠+绕枢轴前倒）→ 空窗滞留 → 插回复位。
func _play_reload_anim() -> void:
	if _magazine == null:
		return
	if _mag_tween != null and _mag_tween.is_valid():
		_mag_tween.kill()
	var t: float = weapon_data.reload_time
	_magazine.position = _mag_home
	_magazine.rotation_degrees = Vector3.ZERO
	_mag_tween = create_tween()
	_mag_tween.tween_property(_magazine, "position",
		_mag_home + Vector3(0.0, -0.14, 0.02), t * 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_mag_tween.parallel().tween_property(_magazine, "rotation_degrees:x",
		28.0, t * 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_mag_tween.tween_interval(t * 0.34)
	_mag_tween.tween_property(_magazine, "position", _mag_home, t * 0.30) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_mag_tween.parallel().tween_property(_magazine, "rotation_degrees:x",
		0.0, t * 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 换弹完成：标准弹药迁移（弹匣缺口 ← 备弹），广播 ammo_changed。
func _on_weapon_reloaded(weapon_id: StringName) -> void:
	if weapon_id != &"pistol":
		return
	_is_reloading = false
	var need: int = weapon_data.mag_size - GameState.pistol_mag
	var take: int = mini(need, GameState.pistol_reserve)
	GameState.pistol_mag += take
	GameState.pistol_reserve -= take
	Events.ammo_changed.emit(&"pistol", GameState.pistol_mag, GameState.pistol_reserve)
