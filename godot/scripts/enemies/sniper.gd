## Sniper — 狙击手（W3 敌智蜂）
##
## 复刻网页版 Sniper 类（index.html L1050-1121，继承 MachineGunner）：
## 玩家在射程内被通视且连续静止 ≥ SNIPER_STILL_TIME 秒 → 狙杀；
## 否则放空枪警告（不消耗玩家血量）。玩家静止时长读 GameState.still_time
## （由玩家域按 STILL_SPEED_THRESHOLD 维护，契约既有）。
## lethal 参数化开关按 §6 裁决实现，契约已落地（GameConfig.SNIPER_LETHAL /
## SNIPER_KILL_DAMAGE / SNIPER_NON_LETHAL_DAMAGE，默认 true 保留秒杀，
## G2 试玩可切 8 伤档）；
## 场景由 W4 摆放在狙击塔顶（SNIPER_POS / SNIPER_TOWER_HEIGHT），本脚本不强制 y。
extends "res://scripts/enemies/machine_gunner.gd"

## lethal 参数化开关（§6 裁决：实例字段，对应 web L1062 实例属性）。
## 默认值读 GameConfig.SNIPER_LETHAL（常量编译期折叠，成员初始化安全）；
## 塔上狙击手/事件狙击手可逐实例覆盖。
var lethal: bool = GameConfig.SNIPER_LETHAL


func _ready() -> void:
	super()
	enemy_kind = &"sniper"
	add_to_group(&"sniper") ## W2 约定：命中即 RIFLE_DMG_VS_SNIPER 固定伤害（hit_solver.gd）
	health = GameConfig.SNIPER_HP


func _get_fire_interval() -> float:
	return GameConfig.SNIPER_FIRE_INTERVAL


func _get_mag_size() -> int:
	return GameConfig.SNIPER_MAG


func _get_reload_time() -> float:
	return GameConfig.SNIPER_RELOAD_TIME


func _get_range() -> float:
	return GameConfig.SNIPER_RANGE


## 狙杀/空枪判定（web L1081-1089）：狙/空枪均无弹道遮挡复检
## （web 原版如此，由交战门控的缓存视线保证；警戒状态可隔墙开枪为 web 既有行为，
## 已登记交付报告风险项）。
func _shoot(player_pos: Vector3) -> void:
	if _reloading:
		return
	if _magazine <= 0:
		_start_reload()
		return
	_fire_cooldown = _get_fire_interval()
	_magazine -= 1
	# 开火广播（G2 冻结信号，W5 枪口音效/火光锚点；狙击枪复用 &"rifle" kind，
	# 契约不新增 kind——蜂后裁决）。
	var muzzle_pos := _muzzle.global_position if _muzzle != null else global_position
	Events.enemy_fired.emit(&"rifle", muzzle_pos)
	if GameState.still_time >= GameConfig.SNIPER_STILL_TIME:
		_kill_shot()
	else:
		_miss_shot()


## 空枪警告（web missShot L1092-1105：飘字 + 地面弹痕；弹痕视觉归 W5/W4，略）。
func _miss_shot() -> void:
	Events.message_posted.emit("狙击手射击! 未命中")


## 狙杀（web killShot L1106-1120）：lethal=true → 大伤害 + game_over(&"sniper")；
## lethal=false → 8 伤普通弹（§6 裁决备选）。player_damaged 缺 source 参数为
## 契约缺口，game_over 暂由本类直发，待伤害管线落地后移交（见交付报告）。
func _kill_shot() -> void:
	if lethal:
		Events.message_posted.emit("被狙击手击中! 一枪毙命")
		Events.player_damaged.emit(&"head", GameConfig.SNIPER_KILL_DAMAGE)
		Events.player_hit_direction.emit(global_position)
		Events.game_over.emit(&"sniper")
	else:
		_damage_player(GameConfig.SNIPER_NON_LETHAL_DAMAGE)
