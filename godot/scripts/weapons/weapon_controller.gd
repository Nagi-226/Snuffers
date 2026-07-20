## WeaponController — 武器基类（W2 火力蜂）
##
## 职责：输入门控（仅当前武器响应开火）、后坐状态机（相机 kick + 视图模型）、
## 可见性跟随切枪。子类：rifle_controller.gd（hitscan 全自动）、rpg_controller.gd（投射物半自动）。
##
## 契约约束（AGENTS.md）：
## - 全部手感参数经 WeaponData（.tres）← GameConfig（sync_from_config），脚本零硬编码数值。
## - 场景通信只走 Events 总线；本脚本仅定义武器自身本地信号 recoil_kick，
##   用于相机后坐/恢复——相机属 W1 域，禁止武器直接引用，
##   由集成侧（player.tscn 或 main.tscn）把本信号连到相机控制（见交付报告契约缺口 #3）。
##
## 挂载约定：武器场景实例化到 player.tscn 的 Camera3D/WeaponMount 下（W1 已预留挂载点）；
## 射线/投射物均以武器自身 global_transform 为原点（即相机炮口）。
## 注：须用 class_name 继承（非路径 extends），L1 链 check_scripts.gd 的 throwaway
## GDScript 编译无法解析路径基类。
class_name WeaponController
extends Node3D

## 相机后坐请求：正值上跳、负值恢复。逐帧增量，接收方只做 rotation.x += pitch_delta。
## （本地信号，非 Events 总线新增；集成侧连接，未连接时武器功能完整仅无相机后坐。）
signal recoil_kick(pitch_delta: float)

## 数据驱动武器定义（.tres）；_ready 时以 GameConfig 覆盖契约内字段。
@export var weapon_data: WeaponData

const HitSolver = preload("res://scripts/weapons/hit_solver.gd")

var _trigger_held: bool = false
## 相机后坐未恢复累积量（rad）：开火 += recoil_pitch，随后按 recover_rate 指数回零。
var _camera_kick: float = 0.0
## 视图模型后坐量：开火时置 recoil_view_offset，随后 ×decay/帧 衰减（语义对齐网页版 recoilOffset）。
var _view_offset: float = 0.0
var _view_model_base_pos: Vector3 = Vector3.ZERO

@onready var _view_model: MeshInstance3D = $ViewModel


func _ready() -> void:
	if weapon_data != null:
		weapon_data.sync_from_config()
	if _view_model != null:
		_view_model_base_pos = _view_model.position
	Events.weapon_switched.connect(_on_weapon_switched)
	visible = _is_current_weapon()


func _exit_tree() -> void:
	Events.weapon_switched.disconnect(_on_weapon_switched)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		# 与 player_controller 一致：仅在鼠标捕获态响应开火输入。
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not _is_current_weapon():
			return
		_trigger_held = true
		_on_trigger_pressed()
	else:
		_trigger_held = false


func _physics_process(delta: float) -> void:
	if not _is_current_weapon():
		_trigger_held = false
		return
	_tick_weapon(delta)


func _process(delta: float) -> void:
	_update_camera_recover(delta)
	_update_view_recoil(delta)


# ===== 子类钩子 =====

## 是否当前手持武器（输入/显示门控的唯一判据）。
func _is_current_weapon() -> bool:
	return weapon_data != null and GameState.current_weapon == weapon_data.weapon_id


## 左键按下边沿（半自动武器用；全自动武器在 _tick_weapon 轮询 _trigger_held）。
func _on_trigger_pressed() -> void:
	pass


## 每物理帧 tick（全自动武器在此按 fire_interval 连发）。
func _tick_weapon(_delta: float) -> void:
	pass


# ===== 后坐 =====

## 开火后坐：相机上跳（经 recoil_kick 发出，含后续恢复）+ 视图模型偏移。
func _apply_recoil() -> void:
	_camera_kick += weapon_data.recoil_pitch
	recoil_kick.emit(weapon_data.recoil_pitch)
	# 网页版 recoilOffset 为赋值而非累加（index.html L2959），保持一致。
	_view_offset = weapon_data.recoil_view_offset


## 相机恢复（有意改进：修正网页版 rotY 永久上跳缺陷）：
## 未恢复量按 recover_rate 指数回零，每帧把恢复量以负 kick 发还给相机。
func _update_camera_recover(delta: float) -> void:
	if _camera_kick <= 0.0:
		return
	var recover: float = minf(_camera_kick * weapon_data.recoil_recover_rate * delta, _camera_kick)
	_camera_kick -= recover
	recoil_kick.emit(-recover)


## 视图模型后坐衰减：×decay 每帧（powf 帧率无关化，对齐 §6 delta 化裁决）；
## 变换系数对齐网页版 updateWeaponRecoil（index.html L3183-3209）。
func _update_view_recoil(delta: float) -> void:
	if _view_offset > 0.0:
		_view_offset *= float(pow(weapon_data.recoil_decay, delta * 60.0))
		if _view_offset < 0.001:
			_view_offset = 0.0
	if _view_model == null:
		return
	_view_model.rotation.x = _view_offset * weapon_data.view_recoil_rot_factor
	_view_model.position.y = _view_model_base_pos.y + _view_offset * weapon_data.view_recoil_y_factor
	_view_model.position.z = _view_model_base_pos.z - _view_offset * weapon_data.view_recoil_z_factor


# ===== 切枪可见性 =====

func _on_weapon_switched(weapon_id: StringName) -> void:
	visible = weapon_data != null and weapon_id == weapon_data.weapon_id
