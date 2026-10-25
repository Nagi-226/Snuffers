## RPGProjectile — 火箭弹/EM-40G「滚雷」榴弹共用投射物（W2 火力蜂）
##
## 弹道忠实复刻网页版 updateRocket（index.html L3133-3180）：
## 恒定初速 + vy -= g·delta 手动积分 + 每帧扫掠射线碰撞 + 朝向速度方向 +
## 超程（300u）或坠地（y < -10）空中自爆。
## 不用 RigidBody3D：网页版为纯运动学弹道，手动积分才能 1:1 对齐 §7 参数表。
##
## 爆炸结算（explode，index.html L1510-1625）：
## - 爆径内可伤害目标即杀（explode_damage 由 GameConfig.GRENADE_EXPLODE_DAMAGE 契约接管；
##   网页版不经 HP 直接移除）；
## - group "bunker" 目标在 爆径+bonus 内特杀（destroy() 鸭子调用保留为投递机制，
##   随后发 Events.bunker_destroyed() 供碉堡机枪停火/HUD/任务判定消费——G2 冻结信号）；
## - 每次爆炸发 Events.rpg_exploded(position)（音效/特效锚点，G2 冻结信号名保留，
##   2026-10-22 起由 EM-40G 榴弹爆炸发射）；
## - 每次伤害投递发 Events.damage_dealt(amount, false)（HUD 飘字，G2 冻结信号；
##   爆炸不分部位，is_headshot 恒 false）；
## - 玩家零自伤（GameConfig.GRENADE_SELF_DAMAGE=false，经发射方 RID 排除实现）。
extends Node3D

var _velocity: Vector3 = Vector3.ZERO
var _excludes: Array[RID] = []
var _data: WeaponData
var _traveled: float = 0.0
var _exploded: bool = false


## 由发射方（rifle_controller._fire_grenade）在实例化后调用：方向、发射方排除 RID、武器数据。
func setup(direction: Vector3, excludes: Array[RID], data: WeaponData) -> void:
	_data = data
	_velocity = direction.normalized() * data.projectile_speed
	_excludes = excludes


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	# 守卫：setup() 由发射方实例化后调用；未 setup 时（如场景单独冒烟）静止待销毁。
	if _data == null:
		return

	_velocity.y -= _data.projectile_gravity * delta
	var from := global_position
	var motion := _velocity * delta

	# 扫掠射线（网页版同款：射线长 = 本帧位移 + 余量，L3164）。
	var query := PhysicsRayQueryParameters3D.create(from, from + motion)
	query.exclude = _excludes
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_explode(hit.position)
		return

	global_position = from + motion
	# 朝向速度方向（网页版 L3142）；模型 -Z 为弹头。
	if _velocity.length_squared() > 0.0001:
		look_at(global_position + _velocity, Vector3.UP)

	_traveled += motion.length()
	if _traveled >= _data.projectile_max_range or global_position.y < _data.projectile_explode_below_y:
		_explode(global_position)


## 爆炸：球形范围查询结算 + Events.rpg_exploded 广播（视觉由 ExplosionFx 消费，
## 2026-10-22 程序化多层爆炸特效替换灰盒占位橙球）。
func _explode(at: Vector3) -> void:
	if _exploded:
		return
	_exploded = true
	set_physics_process(false)
	# 爆炸锚点广播（G2 冻结契约）：音效/特效由消费方接入。
	Events.rpg_exploded.emit(at)
	_apply_area_damage(at)
	queue_free()


func _apply_area_damage(at: Vector3) -> void:
	# 目标枚举：group 遍历（enemy/bunker），非物理球形查询（2026-10-25 修复：
	# 半径扩到 15m 后 intersect_shape 的 32 结果上限被密集街区静态墙体占满，
	# 敌人挤不进枚举=榴弹零杀伤回归，机主实机「杀伤效果没了」指认+探针透视
	# shape_results=32 全为 StaticBody 实锤）。group 遍历无上限、天然无视墙体
	# 遮挡（机主 2026-10-25 口径：杀伤圈内无视建筑障碍），静态物不参与结算。
	# 玩家不参与（GRENADE_SELF_DAMAGE=false 沿用排除口径）。
	for target in get_tree().get_nodes_in_group(&"enemy"):
		if not is_instance_valid(target) or not target.has_method(&"take_damage"):
			continue
		var blast_dist: float = (target as Node3D).global_position.distance_to(at)
		if blast_dist > _data.explode_radius:
			continue
		# 两段伤害圈（2026-10-25 机主裁决）：10m 必杀圈内定值 750；10–15m 过渡带
		# 半伤 375；15m 外不结算。
		var dmg: float = _data.explode_kill_damage if blast_dist <= _data.explode_kill_radius \
			else _data.explode_damage * _data.explode_falloff_factor
		(target as Node).take_damage(dmg, false)
		# G2 冻结契约：HUD 伤害飘字；take_damage 鸭子调用保留为投递机制。
		Events.damage_dealt.emit(dmg, false)
	# 碉堡特杀：判定半径 = 爆径 + 加成（index.html L1593-1610）。
	for bunker in get_tree().get_nodes_in_group(&"bunker"):
		if not is_instance_valid(bunker):
			continue
		if (bunker as Node3D).global_position.distance_to(at) <= _data.explode_radius + _data.bunker_radius_bonus:
			if bunker.has_method(&"destroy"):
				bunker.destroy()
				# G2 冻结契约：碉堡全图唯一，信号无参数；destroy() 鸭子调用保留为投递机制。
				Events.bunker_destroyed.emit()
