## GameState — 运行时状态单一事实源（Autoload 单例）
##
## 纯数据容器：状态由所属模块写入，变更后通过 Events 总线广播。
## 业务逻辑禁止进本文件（AGENTS.md 约束 #2：状态≠逻辑）。
## 依赖 GameConfig，autoload 顺序必须在 GameConfig 之后（见 project.godot）。
extends Node

## 任务阶段：渗透 → 坚守 → 登机 → 已完成 / 已失败
enum MissionPhase { INFILTRATE, DEFEND, BOARD, COMPLETED, GAME_OVER }

## 部位血量。键：&"head" / &"body" / &"legs"
var health: Dictionary = {}
var helmet: float = 0.0
var armor: float = 0.0

var rifle_mag: int = 0
var rifle_reserve: int = 0
var rpg_ammo: int = 0
var medkits: int = 0
var kills: int = 0

var current_weapon: StringName = &"rifle"
var is_prone: bool = false
var is_aiming: bool = false
## 腿部状态：&"healthy" / &"injured" / &"critical"（驱动移速与 HUD 警告）
var leg_state: StringName = &"healthy"
## 连续静止时长（狙击手判定用）
var still_time: float = 0.0
## 玩家世界坐标（W1 每帧写入；敌人感知/AI 共用，替代 group 软引用——G2 冻结新增）
var player_position: Vector3 = Vector3.ZERO

var heli_unlocked: bool = false
var heli_time_left: float = 0.0
var mission_phase: MissionPhase = MissionPhase.INFILTRATE
var night_vision: bool = false
## 昼夜模式运行时状态（DayNightController 维护；true=黑夜。夜视仪白天禁开——§11.2；蜂后集成 2026-07-30）
var is_night: bool = true


func _ready() -> void:
	reset()
	# 击杀统一记账（纯状态派生，非业务逻辑；防止 W2/W3 双头计数——2026-07-21 蜂后裁决）
	Events.enemy_died.connect(_on_enemy_died)


func _on_enemy_died(_enemy: Node) -> void:
	kills += 1
	Events.kills_changed.emit(kills)


## 回到开局状态（对应网页版 initGame L327 初始值）。
func reset() -> void:
	health = {
		&"head": GameConfig.HEALTH_HEAD,
		&"body": GameConfig.HEALTH_BODY,
		&"legs": GameConfig.HEALTH_LEGS,
	}
	helmet = GameConfig.HELMET_MAX
	armor = GameConfig.ARMOR_MAX
	rifle_mag = GameConfig.RIFLE_MAG
	rifle_reserve = GameConfig.RIFLE_RESERVE
	rpg_ammo = GameConfig.RPG_AMMO
	medkits = 0
	kills = 0
	current_weapon = &"rifle"
	is_prone = false
	is_aiming = false
	leg_state = &"healthy"
	still_time = 0.0
	heli_unlocked = false
	heli_time_left = GameConfig.HELI_COUNTDOWN
	mission_phase = MissionPhase.INFILTRATE
	night_vision = false
