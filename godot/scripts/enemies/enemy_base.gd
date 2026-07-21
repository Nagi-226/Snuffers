## EnemyBase — 敌人基类（W3 敌智蜂）
##
## 契约约束（AGENTS.md）：
## - 全部手感参数引用 autoload/game_config.gd；原「契约缺口」行为调参已于
##   G2 契约冻结日（2026-07-21）迁入 game_config.gd，子类已全部切换。
## - 场景通信只走 autoload/events.gd：死亡发 Events.enemy_died(self)，对玩家
##   伤害发 Events.player_damaged(part, amount)，同伴警戒监听
##   Events.enemies_alerted(origin, radius)。
## - 玩家位置主通道为 GameState.player_position（G2 冻结契约，W1 每帧写入）；
##   group "player" 软引用保留作启动早期回退与物理体 RID 排除（禁止跨模块
##   get_node 的边界不变）。
## - 受击接口（与 W2 hit_solver.gd 鸭子类型约定对齐）：武器域 raycast/爆炸命中
##   后调用 take_damage(amount, is_headshot)；爆头判定约定为头部 hitbox
##   （Area3D "HeadHitbox"）节点元数据 "hit_part" = &"head"；狙击手加入
##   group "sniper"（W2 按 RIFLE_DMG_VS_SNIPER 固定伤害结算）。
##   enemy_kind 保留作兵种标识，供蜂后/任务逻辑使用。
extends CharacterBody3D

## 索敌视线复查节流（web 2/60s，index.html L952/L1175；性能节流值，非手感参数）。
const SIGHT_CHECK_INTERVAL: float = 2.0 / 60.0
## 受击红闪时长（web 100ms，L1037/L1371；表现值，非手感参数）。
const HIT_FLASH_TIME: float = 0.1
## 命中玩家部位随机池（web takeDamage L3255-3257 随机部位）。
const PLAYER_HIT_PARTS: Array[StringName] = [&"head", &"body", &"legs"]

## 兵种标识：&"infantry" / &"machine_gunner" / &"sniper" / &"bunker_machine_gunner"。
var enemy_kind: StringName = &"infantry"
var health: float = 1.0
## 警戒状态：见过玩家或收到 enemies_alerted 后置 true（web alerted 语义，单向锁存）。
var alerted: bool = false

var _cached_can_see: bool = false
var _sight_timer: float = 0.0
var _dead: bool = false
var _flash_elapsed: float = 0.0
var _flash_material: StandardMaterial3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

@onready var _eye: Marker3D = $Eye
@onready var _body_mesh: MeshInstance3D = $BodyMesh


func _ready() -> void:
	add_to_group(&"enemy")
	# 复制材质实例，避免受击红闪污染共享 .tscn 子资源的其他实例。
	if _body_mesh != null and _body_mesh.material_override is StandardMaterial3D:
		_flash_material = (_body_mesh.material_override as StandardMaterial3D).duplicate()
		_body_mesh.material_override = _flash_material
	Events.enemies_alerted.connect(_on_enemies_alerted)


func _exit_tree() -> void:
	if Events.enemies_alerted.is_connected(_on_enemies_alerted):
		Events.enemies_alerted.disconnect(_on_enemies_alerted)


func _process(delta: float) -> void:
	# 受击红闪恢复（web setTimeout 100ms，L1037/L1373-1376）。
	if _flash_elapsed > 0.0:
		_flash_elapsed -= delta
		if _flash_elapsed <= 0.0 and _flash_material != null:
			_flash_material.emission_enabled = false


## ===== 受击接口（W2 武器域调用，签名与 hit_solver.gd 约定对齐）=====
## W2 以两参形式调用 take_damage(damage, is_head)；爆头倍率/兵种固定伤害由
## 武器侧结算后传入最终伤害。返回 true 表示本次伤害致死。
## 受击方向（步兵找掩体用）取玩家位置——web 的 attackerPos 恒为 camera.position
## （L2986），与此处 _get_player_position() 语义一致。
func take_damage(amount: float, _is_headshot: bool = false) -> bool:
	if _dead:
		return false
	health -= amount
	_flash_body()
	var attacker_pos := _get_player_position() if _has_player() else global_position
	_on_damaged(amount, attacker_pos)
	if health <= 0.0:
		_die()
		return true
	return false


## 子类钩子：受击后的状态反应（默认仅进入警戒；步兵重写做状态跳转）。
func _on_damaged(_amount: float, _attacker_pos: Vector3) -> void:
	alerted = true


## 子类钩子：同伴警戒广播反应（默认仅置 alerted；步兵重写做状态跳转）。
func _on_enemies_alerted(origin: Vector3, radius: float) -> void:
	if _dead:
		return
	var flat_origin := Vector3(origin.x, 0.0, origin.z)
	if _horizontal_distance_to(flat_origin) < radius:
		alerted = true


## 死亡：广播契约信号后释放。击杀计数/同伴警戒广播由击杀方负责
## （events.gd 注释：enemies_alerted 由击杀者随后广播；见交付报告集成建议）。
func _die() -> void:
	_dead = true
	Events.enemy_died.emit(self)
	queue_free()


## ===== 感知 =====
## 玩家节点软引用；玩家未入组 "player" 时返回 null。
## 仅用于物理体 RID 排除与启动早期回退；位置读取请用 _get_player_position()。
func _get_player() -> Node3D:
	return get_tree().get_first_node_in_group(&"player") as Node3D


## 玩家世界坐标主通道：GameState.player_position（G2 冻结契约，W1 每帧写入）。
## 启动早期回退：GameState 尚未写入（Vector3.ZERO 哨兵；出生点 90,-55 不会
## 碰撞该值）时回退 group "player" 节点坐标；均无则返回 ZERO（配 _has_player()
## 判空使用）。
func _get_player_position() -> Vector3:
	if GameState.player_position != Vector3.ZERO:
		return GameState.player_position
	var player := _get_player()
	if player != null:
		return player.global_position
	return Vector3.ZERO


## 玩家是否在场（GameState 已写入或 group 节点存在）。
func _has_player() -> bool:
	return GameState.player_position != Vector3.ZERO or _get_player() != null


## 节流视线检测：每 SIGHT_CHECK_INTERVAL 秒做一次真实射线，其余帧用缓存。
func _update_sight(delta: float, target_pos: Vector3) -> bool:
	_sight_timer += delta
	if _sight_timer >= SIGHT_CHECK_INTERVAL:
		_cached_can_see = _check_line_of_sight(target_pos)
		_sight_timer = 0.0
	return _cached_can_see


## Eye → 目标点无遮挡（web checkLineOfSight：命中物距终点 <0.5u 不算遮挡，L1404-1414）。
func _check_line_of_sight(target_pos: Vector3) -> bool:
	if _eye == null:
		return false
	var world := get_world_3d()
	if world == null:
		return false
	var from := _eye.global_position
	var query := PhysicsRayQueryParameters3D.create(from, target_pos)
	query.exclude = _los_exclude_rids()
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return from.distance_to(hit["position"]) > from.distance_to(target_pos) - 0.5


## 射线排除集：自身 + 玩家（玩家是射线目标而非遮挡物）。碉堡机枪子类追加碉堡墙体。
func _los_exclude_rids() -> Array[RID]:
	var rids: Array[RID] = [get_rid()]
	var player := _get_player()
	if player is CollisionObject3D:
		rids.append((player as CollisionObject3D).get_rid())
	return rids


## ===== 共用工具 =====
## 对玩家造成一次伤害：部位随机（web takeDamage L3255-3257）。
## 护甲吸收/部位系数/溢出分摊属玩家域伤害管线，不在本类职责内。
func _damage_player(amount: float) -> void:
	var part: StringName = PLAYER_HIT_PARTS[randi() % PLAYER_HIT_PARTS.size()]
	Events.player_damaged.emit(part, amount)


## 朝向目标（锁定水平面，避免俯仰翻倒）。
func _face_position(target_pos: Vector3) -> void:
	var flat := Vector3(target_pos.x, global_position.y, target_pos.z)
	if flat.is_equal_approx(global_position):
		return
	look_at(flat, Vector3.UP)


func _horizontal_distance_to(pos: Vector3) -> float:
	return Vector2(global_position.x - pos.x, global_position.z - pos.z).length()


func _flash_body() -> void:
	if _flash_material == null:
		return
	_flash_material.emission_enabled = true
	_flash_material.emission = Color(1.0, 0.0, 0.0)
	_flash_elapsed = HIT_FLASH_TIME
