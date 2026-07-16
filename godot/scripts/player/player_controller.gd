## PlayerController — 第一人称控制器 + 相机 rig（W1 手感蜂）
##
## 契约约束（AGENTS.md）：
## - 全部手感参数引用 autoload/game_config.gd，禁止硬编码。
## - 场景通信只走 autoload/events.gd；运行时状态读写走 autoload/game_state.gd。
## - 键位不走 project.godot InputMap（共享文件），改用物理键码。
extends CharacterBody3D

# ===== 键位映射（物理键码，对应网页版键位；禁止改 project.godot InputMap）=====
const KEY_FORWARD: Key = KEY_W ## 网页版 W：前进
const KEY_BACK: Key = KEY_S ## 网页版 S：后退
const KEY_STRAFE_LEFT: Key = KEY_A ## 网页版 A：左移
const KEY_STRAFE_RIGHT: Key = KEY_D ## 网页版 D：右移
const KEY_PRONE: Key = KEY_C ## 网页版 C：趴下切换
const KEY_RELOAD: Key = KEY_R ## 网页版 R：换弹
const KEY_WEAPON_RIFLE: Key = KEY_1 ## 网页版 1：切步枪
const KEY_WEAPON_RPG: Key = KEY_2 ## 网页版 2：切火箭筒
const KEY_NIGHT_VISION: Key = KEY_V ## 网页版 V：夜视仪切换
const KEY_MEDKIT: Key = KEY_F ## 网页版 F：使用药包
const KEY_HELI: Key = KEY_H ## 网页版 H：呼叫直升机
const KEY_RELEASE_MOUSE: Key = KEY_ESCAPE ## Esc：释放鼠标（点击画面恢复捕获）

var _pitch: float = 0.0
var _is_reloading: bool = false
var _speed_state: StringName = &"normal"
var _still_broadcast_second: int = 0

# 相机高度过渡状态（CAM_HEIGHT_LERP_TIME 定时线性过渡）
var _cam_height_from: float = 0.0
var _cam_height_target: float = 0.0
var _cam_lerp_elapsed: float = 0.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

@onready var _collision_shape: CollisionShape3D = $CollisionShape3D
@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	# 场景内数值仅为占位，全部以 GameConfig 契约为准逐项覆盖（验收基准）。
	var capsule := _collision_shape.shape as CapsuleShape3D
	capsule.radius = GameConfig.PLAYER_RADIUS
	capsule.height = GameConfig.PLAYER_HEIGHT_STAND
	_collision_shape.position.y = GameConfig.PLAYER_HEIGHT_STAND * 0.5
	_camera.fov = GameConfig.FOV_BASE
	_camera.position.y = GameConfig.CAM_HEIGHT_STAND
	_cam_height_target = GameConfig.CAM_HEIGHT_STAND
	_cam_height_from = GameConfig.CAM_HEIGHT_STAND
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	# 鼠标视角：顶层节点管 yaw，内嵌 Camera3D 管 pitch。
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var sens: float = GameConfig.MOUSE_SENS_BASE * GameConfig.view_sensitivity
		if GameState.is_aiming:
			sens *= GameConfig.AIM_SENS_FACTOR
		rotation.y -= motion.relative.x * sens
		_pitch = clampf(_pitch - motion.relative.y * sens, -GameConfig.PITCH_CLAMP, GameConfig.PITCH_CLAMP)
		_camera.rotation.x = _pitch
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		if button.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_RIGHT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_toggle_aim()
		return

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		match key_event.physical_keycode:
			KEY_RELEASE_MOUSE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_PRONE:
				_toggle_prone()
			KEY_RELOAD:
				_start_reload()
			KEY_WEAPON_RIFLE:
				_switch_weapon(&"rifle")
			KEY_WEAPON_RPG:
				_switch_weapon(&"rpg")
			KEY_NIGHT_VISION:
				_toggle_night_vision()
			KEY_MEDKIT:
				_use_medkit()
			KEY_HELI:
				_call_heli()


func _physics_process(delta: float) -> void:
	# 重力（引擎全局设置，非手感参数）。
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta

	# WASD 输入，对角线归一化；yaw 在根节点上，故用根节点 basis 变换。
	var input_dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_FORWARD):
		input_dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_BACK):
		input_dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_STRAFE_LEFT):
		input_dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_STRAFE_RIGHT):
		input_dir.x += 1.0

	var direction := Vector3.ZERO
	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		direction = (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var speed := _current_speed()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	move_and_slide()

	# 世界边界钳制。
	global_position.x = clampf(global_position.x, -GameConfig.WORLD_BOUND_X, GameConfig.WORLD_BOUND_X)
	global_position.z = clampf(global_position.z, -GameConfig.WORLD_BOUND_Z, GameConfig.WORLD_BOUND_Z)

	_update_speed_state()
	_update_still_time(delta)


func _process(delta: float) -> void:
	# 相机高度 CAM_HEIGHT_LERP_TIME 平滑过渡（趴下/起身）。
	if not is_equal_approx(_camera.position.y, _cam_height_target):
		_cam_lerp_elapsed += delta
		var t := clampf(_cam_lerp_elapsed / GameConfig.CAM_HEIGHT_LERP_TIME, 0.0, 1.0)
		_camera.position.y = lerpf(_cam_height_from, _cam_height_target, t)


## 当前移速：趴下 > 瞄准 > 站立取基速，再按腿部状态乘系数。
func _current_speed() -> float:
	var base: float
	if GameState.is_prone:
		base = GameConfig.SPEED_PRONE
	elif GameState.is_aiming:
		base = GameConfig.SPEED_AIM
	else:
		base = GameConfig.SPEED_STAND
	match GameState.leg_state:
		&"injured":
			base *= GameConfig.LEG_INJURED_FACTOR
		&"critical":
			base *= GameConfig.LEG_CRITICAL_FACTOR
	return base


## 移速状态变化广播（供 HUD；契约既有信号）。
func _update_speed_state() -> void:
	var state: StringName = &"normal"
	if GameState.is_prone:
		state = &"prone"
	elif GameState.leg_state == &"critical":
		state = &"critical"
	elif GameState.leg_state == &"injured":
		state = &"injured"
	if state != _speed_state:
		_speed_state = state
		Events.player_speed_state_changed.emit(state)


## 静止判定：水平速度 < 阈值累计 still_time，每秒广播一次；恢复移动时清零并广播 0。
func _update_still_time(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed < GameConfig.STILL_SPEED_THRESHOLD:
		GameState.still_time += delta
		var whole_seconds := int(GameState.still_time)
		if whole_seconds > _still_broadcast_second:
			_still_broadcast_second = whole_seconds
			Events.player_still_time_changed.emit(GameState.still_time)
	else:
		if GameState.still_time > 0.0:
			GameState.still_time = 0.0
			Events.player_still_time_changed.emit(0.0)
		_still_broadcast_second = 0


## C：趴下切换（碰撞体高度 + 相机高度过渡 + 信号）。
func _toggle_prone() -> void:
	GameState.is_prone = not GameState.is_prone
	var capsule := _collision_shape.shape as CapsuleShape3D
	if GameState.is_prone:
		# 契约几何冲突（已上报蜂后裁决）：胶囊高 0.4 < 2×半径 0.8 不可行，
		# 趴下时退化为球等效胶囊（半径=高/2=0.2），保证高度参数精确成立。
		capsule.radius = GameConfig.PLAYER_HEIGHT_PRONE * 0.5
		capsule.height = GameConfig.PLAYER_HEIGHT_PRONE
	else:
		capsule.radius = GameConfig.PLAYER_RADIUS
		capsule.height = GameConfig.PLAYER_HEIGHT_STAND
	_collision_shape.position.y = capsule.height * 0.5
	_start_cam_height_lerp(GameConfig.CAM_HEIGHT_PRONE if GameState.is_prone else GameConfig.CAM_HEIGHT_STAND)
	Events.player_prone_changed.emit(GameState.is_prone)


func _start_cam_height_lerp(target: float) -> void:
	_cam_height_from = _camera.position.y
	_cam_height_target = target
	_cam_lerp_elapsed = 0.0


## 右键：瞄准切换式（非按住）。
func _toggle_aim() -> void:
	GameState.is_aiming = not GameState.is_aiming
	Events.player_aim_changed.emit(GameState.is_aiming)


## R：占位换弹——只发信号，不接真实弹药逻辑（W2 职责）。
## 契约注明「RPG 无此事件」，故仅步枪触发。
func _start_reload() -> void:
	if _is_reloading or GameState.current_weapon != &"rifle":
		return
	_is_reloading = true
	Events.weapon_reload_started.emit(&"rifle")
	await get_tree().create_timer(GameConfig.RIFLE_RELOAD_TIME).timeout
	if not is_instance_valid(self):
		return
	_is_reloading = false
	Events.weapon_reloaded.emit(&"rifle")


## 1/2：切枪占位——改写 GameState.current_weapon + 发信号。
func _switch_weapon(weapon_id: StringName) -> void:
	if GameState.current_weapon == weapon_id:
		return
	GameState.current_weapon = weapon_id
	Events.weapon_switched.emit(weapon_id)


## V：夜视仪切换占位。
func _toggle_night_vision() -> void:
	GameState.night_vision = not GameState.night_vision
	Events.night_vision_toggled.emit(GameState.night_vision)


## F：药包占位——三部位各 +MEDKIT_HEAL（不超上限），库存 -1，广播信号。
func _use_medkit() -> void:
	if GameState.medkits <= 0:
		return
	GameState.medkits -= 1
	Events.medkit_used.emit(GameState.medkits)
	for part: StringName in GameState.health:
		var maximum := _part_max_health(part)
		GameState.health[part] = minf(GameState.health[part] + GameConfig.MEDKIT_HEAL, maximum)
		Events.player_health_changed.emit(part, GameState.health[part], maximum)


func _part_max_health(part: StringName) -> float:
	match part:
		&"head":
			return GameConfig.HEALTH_HEAD
		&"body":
			return GameConfig.HEALTH_BODY
		&"legs":
			return GameConfig.HEALTH_LEGS
	return 0.0


## H：呼叫直升机占位——仅在已解锁时发信号。
func _call_heli() -> void:
	if GameState.heli_unlocked:
		Events.heli_called.emit()
