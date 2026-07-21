## BunkerMachineGunner — 碉堡机枪（W3 敌智蜂）
##
## 复刻网页版碉堡机枪（index.html L941-949 停火逻辑 + L1819-1824 参数覆盖，
## web 为 MachineGunner isBunkerMG 分支）：常态戒备持续火力压制。
## 停火裁决（采 A 语义，2026-07-21 机主签字；00-spike-plan.md §7「碉堡停火」
## G2 行）：玩家趴下 → 立即停火；趴下期间以
## GameConfig.BUNKER_PRONE_CEASEFIRE_TIME(7s) 倒计时，计时耗尽后对趴下目标
## 恢复射击；玩家起身立即恢复射击。
## 源码依据：index.html L941-949（proneDelayTimer 维护）+ L964（仅
## proneDelayTimer <= 0 才允许开火——趴下瞬间 timer=7>0 即停火，7s 耗尽恢复，
## 起身 timer=0 立即恢复）。
## 摧毁停火：消费 Events.bunker_destroyed()（G2 冻结信号，由 W2
## rpg_projectile.gd 爆炸结算广播），永久停火。
## 场景约定：根节点摆在碉堡中心地面（GameConfig.BUNKER_POS），Eye/Muzzle 位于
## 射口高度；碉堡墙体碰撞体由 W4 加入 group "bunker_wall"，本机射线排除之
## （对应 web isBunkerWall 豁免 L980/L1017）。四向射口选择（web L993-1009）
## 简化为单 Muzzle，已登记交付报告。
extends "res://scripts/enemies/machine_gunner.gd"

## 趴下停火安全窗倒计时（>0 表示停火窗口内；暴露给 headless 冒烟断言）。
var _prone_ceasefire_timer: float = 0.0
var _player_was_prone: bool = false
## 碉堡被摧毁后永久停火（Events.bunker_destroyed 驱动）。
var _disabled: bool = false


func _ready() -> void:
	super()
	enemy_kind = &"bunker_machine_gunner"
	alerted = true ## 常态戒备（web L1823）
	Events.bunker_destroyed.connect(_on_bunker_destroyed)


func _exit_tree() -> void:
	if Events.bunker_destroyed.is_connected(_on_bunker_destroyed):
		Events.bunker_destroyed.disconnect(_on_bunker_destroyed)
	super()


func _get_fire_interval() -> float:
	return GameConfig.BUNKER_MG_FIRE_INTERVAL


func _get_range() -> float:
	return GameConfig.BUNKER_MG_RANGE


## 单发伤害 5 + rand×3（web L1822 damage=5，随机浮动沿用 MG 公式 L1027；
## 契约已落地 GameConfig.BUNKER_MG_DAMAGE_RAND）。
func _roll_damage() -> float:
	return GameConfig.BUNKER_MG_DAMAGE_MIN + randf() * GameConfig.BUNKER_MG_DAMAGE_RAND


## 碉堡被 RPG 摧毁（Events.bunker_destroyed，G2 冻结信号）→ 永久停火。
func _on_bunker_destroyed() -> void:
	_disabled = true


func _can_fire_now() -> bool:
	if _disabled:
		return false
	# A 语义（机主裁决）：趴下即停火——安全窗倒计时 >0 期间禁火；
	# 计时耗尽（<=0）后对趴下目标恢复射击；起身时计时清零立即恢复（web L964）。
	if GameState.is_prone and _prone_ceasefire_timer > 0.0:
		return false
	return true


func _physics_process(delta: float) -> void:
	# 趴下停火安全窗维护（结构复刻 web L941-948，语义为机主裁决 A，见文件头注）。
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
