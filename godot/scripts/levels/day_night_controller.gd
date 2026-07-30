## DayNightController — 白天/黑夜双模式环境控制器（W7 昼夜域）
##
## 契约约束（AGENTS.md）：
## - 消费 Events.night_vision_toggled（已存在，events.gd L81）；不新增信号。
## - 环境参数为视觉调参（非手感参数），本地定义；如需契约化见交接备忘录。
## - 场景通信只走 Events 总线；本控制器不引用其他模块节点。
##
## 用法：实例化 day_night_controller.tscn 到关卡场景根下即可。
## 控制器自包含 WorldEnvironment + SunLight 子节点，_ready 中接管其参数。
## 若父场景已有 WorldEnvironment（如 greybox_arena），集成时删除原有即可。
##
## §11.2 裁决：同一战场白天/黑夜双模式；黑夜保留夜视仪核心机制。
extends Node

## 双模式枚举。
enum Mode { DAY, NIGHT }

## 开局初始模式（场景/代码均可配置）。
@export var initial_mode: Mode = Mode.NIGHT

## 当前运行模式（只读访问）。
var current_mode: Mode = Mode.NIGHT

## 模式切换时广播（供同域脚本/演示 UI 监听；非全局契约信号）。
signal mode_changed(new_mode: Mode)

@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _sun_light: DirectionalLight3D = $SunLight

# ===== 白天环境参数（视觉调参，G4 后美术替换）=====
const DAY_BG_COLOR: Color = Color(0.45, 0.65, 0.95, 1.0)
const DAY_AMBIENT_COLOR: Color = Color(0.75, 0.72, 0.65, 1.0)
const DAY_AMBIENT_ENERGY: float = 0.85
const DAY_FOG_ENABLED: bool = false
const DAY_FOG_COLOR: Color = Color(0.65, 0.75, 0.9, 1.0)
const DAY_FOG_DENSITY: float = 0.001

# ===== 黑夜环境参数（基线对齐 greybox_arena.tscn Environment_night）=====
const NIGHT_BG_COLOR: Color = Color(0.02, 0.02, 0.039, 1.0)
const NIGHT_AMBIENT_COLOR: Color = Color(0.0667, 0.0667, 0.1333, 1.0)
const NIGHT_AMBIENT_ENERGY: float = 0.15
const NIGHT_FOG_ENABLED: bool = true
const NIGHT_FOG_COLOR: Color = Color(0.086, 0.086, 0.122, 1.0)
const NIGHT_FOG_DENSITY: float = 0.005

# ===== 白天光源参数 =====
const DAY_LIGHT_COLOR: Color = Color(1.0, 0.95, 0.85, 1.0)
const DAY_LIGHT_ENERGY: float = 1.2
const DAY_LIGHT_ROTATION: Vector3 = Vector3(-0.96, -0.52, 0.0)

# ===== 黑夜光源参数（对齐 greybox_arena MoonLight）=====
const NIGHT_LIGHT_COLOR: Color = Color(0.6667, 0.8, 1.0, 1.0)
const NIGHT_LIGHT_ENERGY: float = 0.4
const NIGHT_LIGHT_ROTATION: Vector3 = Vector3(-0.872665, -0.523599, 0.0)


func _ready() -> void:
	current_mode = initial_mode
	_apply_mode(current_mode)


## 运行时切换模式（外部调用入口）。
func set_mode(mode: Mode) -> void:
	if mode == current_mode:
		return
	current_mode = mode
	_apply_mode(mode)
	mode_changed.emit(mode)


## 便捷切换（T 键演示用）。
func toggle_mode() -> void:
	var next := Mode.DAY if current_mode == Mode.NIGHT else Mode.NIGHT
	set_mode(next)


## 查询当前是否为黑夜（夜视仪可用性判定用）。
func is_night() -> bool:
	return current_mode == Mode.NIGHT


func _apply_mode(mode: Mode) -> void:
	# 同步昼夜运行时状态到契约（GameState.is_night；夜视仪门控消费——蜂后集成 2026-07-30）
	GameState.is_night = (mode == Mode.NIGHT)
	var env := _world_env.environment
	if env == null:
		env = Environment.new()
		_world_env.environment = env

	match mode:
		Mode.DAY:
			env.background_mode = Environment.BG_COLOR
			env.background_color = DAY_BG_COLOR
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = DAY_AMBIENT_COLOR
			env.ambient_light_energy = DAY_AMBIENT_ENERGY
			env.fog_enabled = DAY_FOG_ENABLED
			env.fog_light_color = DAY_FOG_COLOR
			env.fog_density = DAY_FOG_DENSITY
			_sun_light.light_color = DAY_LIGHT_COLOR
			_sun_light.light_energy = DAY_LIGHT_ENERGY
			_sun_light.rotation = DAY_LIGHT_ROTATION
		Mode.NIGHT:
			env.background_mode = Environment.BG_COLOR
			env.background_color = NIGHT_BG_COLOR
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = NIGHT_AMBIENT_COLOR
			env.ambient_light_energy = NIGHT_AMBIENT_ENERGY
			env.fog_enabled = NIGHT_FOG_ENABLED
			env.fog_light_color = NIGHT_FOG_COLOR
			env.fog_density = NIGHT_FOG_DENSITY
			_sun_light.light_color = NIGHT_LIGHT_COLOR
			_sun_light.light_energy = NIGHT_LIGHT_ENERGY
			_sun_light.rotation = NIGHT_LIGHT_ROTATION

	_sun_light.shadow_enabled = true
	_sun_light.directional_shadow_max_distance = 250.0
