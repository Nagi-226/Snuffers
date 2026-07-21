## RifleController — 步枪 hitscan（W2 火力蜂）
##
## 参数基准（§7 对照表 G2 行）：25/爆头50 伤害 · 600RPM（0.1s/发）· 30/150 弹药 ·
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

var _fire_cooldown: float = 0.0
var _is_reloading: bool = false


func _ready() -> void:
	super()
	Events.weapon_reload_started.connect(_on_reload_started)
	Events.weapon_reloaded.connect(_on_weapon_reloaded)


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


## 全自动：按住左键按 fire_interval 连发（600 RPM）。
func _tick_weapon(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	if _trigger_held and _fire_cooldown <= 0.0:
		if _fire():
			_fire_cooldown = weapon_data.fire_interval


## 单发流程：弹药门控 → 扣弹广播 → 后坐 → 散布射线 → 命中结算。返回是否真正击发。
func _fire() -> bool:
	if _is_reloading:
		return false
	if GameState.rifle_mag <= 0:
		# 网页版弹尽自动换弹（index.html L2954）。
		_start_reload()
		return false

	GameState.rifle_mag -= 1
	Events.ammo_changed.emit(&"rifle", GameState.rifle_mag, GameState.rifle_reserve)
	Events.weapon_fired.emit(&"rifle")
	_apply_recoil()

	var hit := _cast_spread_ray()
	if hit.is_empty():
		return true
	var collider: Object = hit.collider

	# 碉堡跳弹：提示需用火箭筒（index.html L2973-2980）。
	if HitSolver.find_group_ancestor(collider, &"bunker") != null:
		Events.ricochet_on_bunker.emit()
		return true

	var target := HitSolver.find_damageable(collider)
	if target == null:
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
	Events.weapon_reload_started.emit(&"rifle")
	await get_tree().create_timer(weapon_data.reload_time).timeout
	if not is_instance_valid(self):
		return
	Events.weapon_reloaded.emit(&"rifle")


func _on_reload_started(weapon_id: StringName) -> void:
	if weapon_id == &"rifle":
		_is_reloading = true


## 换弹完成：标准弹药迁移（弹匣缺口 ← 备弹），广播 ammo_changed。
func _on_weapon_reloaded(weapon_id: StringName) -> void:
	if weapon_id != &"rifle":
		return
	_is_reloading = false
	var need: int = weapon_data.mag_size - GameState.rifle_mag
	var take: int = mini(need, GameState.rifle_reserve)
	GameState.rifle_mag += take
	GameState.rifle_reserve -= take
	Events.ammo_changed.emit(&"rifle", GameState.rifle_mag, GameState.rifle_reserve)
