## BunkerMachineGunner — 碉堡机枪（W3 敌智蜂）
##
## 复刻网页版碉堡机枪（index.html L941-949 停火逻辑 + L1819-1824 参数覆盖，
## web 为 MachineGunner isBunkerMG 分支）：常态戒备持续火力压制；
## 玩家趴下触发停火倒计时 BUNKER_PRONE_CEASEFIRE_TIME，倒计时耗尽仍趴下则停火，
## 起身立即恢复射击。
## ⚠ 与网页版字面实现的差异：web L964 的条件实际效果是「趴下立即停火、7s 后
##   恢复射击」；本实现按派单口径与 game_config 契约注释（L104「玩家趴下后停火
##   倒计时」）实现为「趴下继续压制 7s 后停火」。差异已登记交付报告，待 G2 裁决。
## 场景约定：根节点摆在碉堡中心地面（GameConfig.BUNKER_POS），Eye/Muzzle 位于
## 射口高度；碉堡墙体碰撞体由 W4 加入 group "bunker_wall"，本机射线排除之
## （对应 web isBunkerWall 豁免 L980/L1017）。四向射口选择（web L993-1009）
## 简化为单 Muzzle，已登记交付报告。
extends "res://scripts/enemies/machine_gunner.gd"

## 趴下停火倒计时（>0 表示仍在压制窗口内；暴露给 headless 冒烟断言）。
var _prone_ceasefire_timer: float = 0.0
var _player_was_prone: bool = false
## 碉堡被摧毁后永久停火（摧毁信号为契约缺口，暂由 disable() 供集成方调用）。
var _disabled: bool = false


func _ready() -> void:
	super()
	enemy_kind = &"bunker_machine_gunner"
	alerted = true ## 常态戒备（web L1823）


func _get_fire_interval() -> float:
	return GameConfig.BUNKER_MG_FIRE_INTERVAL


func _get_range() -> float:
	return GameConfig.BUNKER_MG_RANGE


## 单发伤害 5 + rand×3（web L1822 damage=5，随机浮动沿用 MG 公式 L1027）。
## 契约缺口：建议新增 GameConfig.BUNKER_MG_DAMAGE_RAND = 3.0，当前复用 MG_DAMAGE_RAND。
func _roll_damage() -> float:
	return GameConfig.BUNKER_MG_DAMAGE_MIN + randf() * GameConfig.MG_DAMAGE_RAND


## 碉堡被 RPG 摧毁时由集成方调用（契约缺口：建议新增 Events.bunker_destroyed()）。
func disable() -> void:
	_disabled = true


func _can_fire_now() -> bool:
	if _disabled:
		return false
	# 玩家趴下且停火倒计时已耗尽 → 停火；站立或倒计时内 → 继续压制。
	if GameState.is_prone and _prone_ceasefire_timer <= 0.0:
		return false
	return true


func _physics_process(delta: float) -> void:
	# 趴下停火倒计时维护（结构复刻 web L941-948，语义按派单裁决，见文件头注）。
	if GameState.is_prone:
		if not _player_was_prone:
			_prone_ceasefire_timer = GameConfig.BUNKER_PRONE_CEASEFIRE_TIME
		_prone_ceasefire_timer -= delta
	else:
		_prone_ceasefire_timer = 0.0
	_player_was_prone = GameState.is_prone
	super(delta)


## 射线排除追加碉堡墙体（group "bunker_wall"，W4 并行施工同一约定，蜂后对齐）。
func _los_exclude_rids() -> Array[RID]:
	var rids := super()
	for node: Node in get_tree().get_nodes_in_group(&"bunker_wall"):
		if node is CollisionObject3D:
			rids.append((node as CollisionObject3D).get_rid())
	return rids
