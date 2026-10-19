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
const KEY_WEAPON_RIFLE: Key = KEY_1 ## 网页版 1：切步枪
const KEY_WEAPON_PISTOL: Key = KEY_2 ## 2：切手枪 EM-57P（2026-10-19 机主立项）
const KEY_WEAPON_RPG: Key = KEY_3 ## 3：切火箭筒（2026-10-19 由 2 挪 3，手枪入 2 号位）
const KEY_NIGHT_VISION: Key = KEY_N ## N：夜视仪切换（§11.2 机主裁决：V→N，与昼夜演示场景键位一致）
const KEY_MEDKIT: Key = KEY_F ## 网页版 F：使用药包
const KEY_HELI: Key = KEY_H ## 网页版 H：呼叫直升机
const KEY_JUMP: Key = KEY_SPACE ## 空格：跳跃（2026-10-18 机主立项）
const KEY_SPRINT: Key = KEY_SHIFT ## 左 Shift+W：疾跑（2026-10-19 机主立项）
const KEY_INTERACT: Key = KEY_E ## E：通用交互（2026-10-18 机主立项：开门等；拾取物不走此键，贴近自动捡拾）
const KEY_FIRE_MODE: Key = KEY_X ## X：射击模式循环 全自动→三发点射→半自动（2026-10-19 机主立项）
const KEY_RELEASE_MOUSE: Key = KEY_ESCAPE ## Esc：释放鼠标（点击画面恢复捕获）

var _pitch: float = 0.0
var _is_moving: bool = false
var _jump_queued: bool = false ## 跳跃排队位（2026-10-19 修复：输入帧置位、物理帧消费，避免被重力清零）
var _speed_state: StringName = &"normal"
var _still_broadcast_second: int = 0

# 相机高度过渡状态（CAM_HEIGHT_LERP_TIME 定时线性过渡）
var _cam_height_from: float = 0.0
var _cam_height_target: float = 0.0
var _cam_lerp_elapsed: float = 0.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

# E 键通用交互（2026-10-18 机主立项）：准星射线命中带 interact() 方法的节点即生效
var _interact_target: Node = null
var _prompt_label: Label = null

# —— 按住开镜（ADS，2026-10-19 机主立项）——
# 开镜权重 0..1 插值驱动：WeaponMount 位移（optic 归中相机轴）+ FOV 收窄 + 准星覆盖层。
var _ads_weight: float = 0.0
var _mount_hip_pos: Vector3 = Vector3.ZERO ## 腰射挂载位（_ready 从 player.tscn 实测读取）
var _ads_mount_targets: Dictionary = {} ## weapon_id → 开镜挂载位（optic 中心对中）
var _ads_fov_targets: Dictionary = {} ## weapon_id → 开镜 FOV
var _ads_reticle: AdsReticle = null
## 护甲回充脱战计时（受击清零，≥ARMOR_REGEN_DELAY 后按 ARMOR_REGEN_RATE 回充）
var _armor_regen_wait: float = 0.0

@onready var _weapon_mount: Marker3D = $Camera3D/WeaponMount

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
	# 交互提示标签（E 开门等）：脚本自建 CanvasLayer，不动 W5 域 HUD 场景；
	# 准星下方居中，仅在有可交互目标时显示。
	var prompt_layer := CanvasLayer.new()
	prompt_layer.name = "InteractPrompt"
	prompt_layer.layer = 2
	_prompt_label = Label.new()
	_prompt_label.anchor_left = 0.5
	_prompt_label.anchor_right = 0.5
	_prompt_label.anchor_top = 0.5
	_prompt_label.anchor_bottom = 0.5
	_prompt_label.offset_top = 34.0
	_prompt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_label.add_theme_font_size_override("font_size", 18)
	_prompt_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 0.9))
	_prompt_label.visible = false
	prompt_layer.add_child(_prompt_label)
	add_child(prompt_layer)
	# 开镜准星覆盖层（ADS）：脚本自建 CanvasLayer，同 InteractPrompt 模式不动 W5 域 HUD；
	# 步枪=全息圆环+心点，手枪=点状，RPG 无覆盖层（沿用 HUD 准星+FOV_SCOPE）。
	var reticle_layer := CanvasLayer.new()
	reticle_layer.name = "AdsReticle"
	reticle_layer.layer = 3
	_ads_reticle = AdsReticle.new()
	_ads_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ads_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle_layer.add_child(_ads_reticle)
	add_child(reticle_layer)
	_calibrate_ads()
	# 承伤管线挂接（发射侧在 enemy_base._damage_player；结算收口在本类 _apply_damage）。
	Events.player_damaged.connect(_apply_damage)


## 开镜标定：从 player.tscn 实测腰射挂载位；步枪/手枪按 optic 网格 AABB 中心反推
## 开镜挂载位（optic 归中相机轴），免手调免硬编码几何；找不到 optic 时回退 x 归中。
func _calibrate_ads() -> void:
	_mount_hip_pos = _weapon_mount.position
	_ads_fov_targets = {
		&"rifle": GameConfig.RIFLE_ADS_FOV,
		&"pistol": GameConfig.PISTOL_ADS_FOV,
		&"rpg": GameConfig.FOV_SCOPE,
	}
	for pair: Array in [[&"rifle", "Rifle"], [&"pistol", "Pistol"]]:
		var weapon_root := _weapon_mount.get_node_or_null(pair[1]) as Node3D
		var fallback := Vector3(0.0, _mount_hip_pos.y, _mount_hip_pos.z)
		if weapon_root == null:
			_ads_mount_targets[pair[0]] = fallback
			continue
		var center: Variant = _find_optic_center_in_mount(weapon_root, pair[0])
		if center == null:
			_ads_mount_targets[pair[0]] = fallback
		else:
			var c: Vector3 = center
			# optic 相机空间坐标 = 挂载位 + c；令其 x/y 归零 → 挂载位取 -c（z 保持腰射纵距）
			_ads_mount_targets[pair[0]] = Vector3(-c.x, -c.y, _mount_hip_pos.z)


## 在武器子树中找名字含 optic 的网格实例（无则返回 null）。
func _find_optic_mesh(weapon_root: Node) -> MeshInstance3D:
	var stack: Array = [weapon_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and String(n.name).to_lower().contains("optic"):
			return n as MeshInstance3D
	return null


## 在武器子树中找名字含 optic 的网格，返回其瞄窗中心在 WeaponMount 局部空间的坐标。
## 步枪：用开窗手术实测的镜孔轴心（GameConfig.ADS_RIFLE_OPTIC_BORE_LOCAL），准星正对筒心；
## 手枪：AABB 中心 + ADS_PISTOL_OPTIC_WINDOW_LIFT 上移（外壳下沿拉低 AABB 中心，视窗偏上半部）。
func _find_optic_center_in_mount(weapon_root: Node, weapon_id: StringName) -> Variant:
	var mi := _find_optic_mesh(weapon_root)
	if mi == null:
		return null
	var window_local: Vector3
	if weapon_id == &"rifle":
		window_local = GameConfig.ADS_RIFLE_OPTIC_BORE_LOCAL
	else:
		var aabb := mi.get_aabb()
		window_local = aabb.get_center() + Vector3(0.0, aabb.size.y * GameConfig.ADS_PISTOL_OPTIC_WINDOW_LIFT, 0.0)
	var global_pos: Vector3 = mi.global_transform * window_local
	return _weapon_mount.global_transform.affine_inverse() * global_pos


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
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_RIGHT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			# 按住开镜（2026-10-19 机主立项：原切换式改为按住式，松开即关镜）
			_set_aiming(button.pressed)
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
			KEY_WEAPON_RIFLE:
				_switch_weapon(&"rifle")
			KEY_WEAPON_PISTOL:
				_switch_weapon(&"pistol")
			KEY_WEAPON_RPG:
				_switch_weapon(&"rpg")
			KEY_NIGHT_VISION:
				_toggle_night_vision()
			KEY_MEDKIT:
				_use_medkit()
			KEY_HELI:
				_call_heli()
			KEY_JUMP:
				_try_jump()
			KEY_INTERACT:
				_try_interact()
			KEY_FIRE_MODE:
				_cycle_fire_mode()


func _physics_process(delta: float) -> void:
	# 重力（引擎全局设置，非手感参数）；跳跃排队位在落地帧消费（修复：原先输入回调
	# 直接写 velocity.y，下一物理帧此处 is_on_floor 仍为 true 被清零，跳跃失效）。
	if is_on_floor():
		if _jump_queued:
			_jump_queued = false
			velocity.y = GameConfig.JUMP_VELOCITY
		else:
			velocity.y = 0.0
	else:
		_jump_queued = false  # 离地期间不保留排队（不做土狼时间，与立项口径一致）
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

	# 移动输入边沿广播（G2 冻结新增信号；脚步循环音起停用，与速度档位语义不同）。
	var is_moving := input_dir != Vector2.ZERO
	if is_moving != _is_moving:
		_is_moving = is_moving
		Events.player_moving_changed.emit(is_moving)

	var speed := _current_speed()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	var pre_pos := global_position
	var wish := Vector3(velocity.x, 0.0, velocity.z) * delta
	move_and_slide()
	# 自动上台阶（2026-10-18 机主立项：路缘 0.145m 免跳直上）：水平位移被挡掉大半
	# 且在地面上时，按「抬升-前推-落回」三段 test_move 尝试跨上台阶；任何一段失败
	# 都保持原位不动（真墙/头顶压顶/前方悬空均不触发）。起跳上升帧不触发（防吞跳跃速度）。
	if is_on_floor() and velocity.y <= 0.01 and wish.length() > 0.001:
		var actual := Vector3(global_position.x - pre_pos.x, 0.0, global_position.z - pre_pos.z)
		if actual.length() < wish.length() * 0.4:
			_try_step_up(wish)

	# 世界边界钳制。
	global_position.x = clampf(global_position.x, -GameConfig.WORLD_BOUND_X, GameConfig.WORLD_BOUND_X)
	global_position.z = clampf(global_position.z, -GameConfig.WORLD_BOUND_Z, GameConfig.WORLD_BOUND_Z)

	# 每物理帧写入玩家世界坐标（G2 冻结新增字段；敌人感知/AI 共用）。
	GameState.player_position = global_position
	GameState.player_yaw = rotation.y

	_update_interact_target()

	_update_speed_state()
	_update_still_time(delta)
	_update_armor_regen(delta)


## 纳米服式回充（2026-10-19 机主立项，孤岛危机式）：受击后 ARMOR_REGEN_DELAY 秒未再受击，
## 护甲按 ARMOR_REGEN_RATE、头/躯/腿三部位按 HEALTH_REGEN_RATE 同步回复至各自上限；
## 任务结束态不回复；腿部回复后自动解除 injured/critical 状态。
func _update_armor_regen(delta: float) -> void:
	if GameState.mission_phase == GameState.MissionPhase.COMPLETED \
			or GameState.mission_phase == GameState.MissionPhase.GAME_OVER:
		return
	var needs := GameState.armor < GameConfig.ARMOR_MAX
	if not needs:
		for part: StringName in GameState.health:
			if GameState.health[part] < _part_max_health(part):
				needs = true
				break
	if not needs:
		return
	_armor_regen_wait += delta
	if _armor_regen_wait < GameConfig.ARMOR_REGEN_DELAY:
		return
	if GameState.armor < GameConfig.ARMOR_MAX:
		GameState.armor = minf(GameState.armor + GameConfig.ARMOR_REGEN_RATE * delta, GameConfig.ARMOR_MAX)
		Events.armor_changed.emit(GameState.armor, GameConfig.ARMOR_MAX)
	var health_changed := false
	for part: StringName in GameState.health:
		var maximum := _part_max_health(part)
		if GameState.health[part] < maximum:
			GameState.health[part] = minf(GameState.health[part] + GameConfig.HEALTH_REGEN_RATE * delta, maximum)
			Events.player_health_changed.emit(part, GameState.health[part], maximum)
			health_changed = true
	if health_changed:
		_update_leg_state()


## 跳跃（空格）：趴下状态忽略；置排队位由物理帧落地消费（输入回调直接写 velocity.y
## 会被下一物理帧重力清零，2026-10-19 修复）。
func _try_jump() -> void:
	if GameState.is_prone:
		return
	_jump_queued = true


## E 键通用交互：当前射线目标（_update_interact_target 每物理帧刷新）响应即调用。
## 交互对象契约：实现 interact() + interact_prompt()（见 scripts/levels/door.gd）。
func _try_interact() -> void:
	if _interact_target != null and is_instance_valid(_interact_target):
		_interact_target.interact()


## 准星射线探测可交互目标：命中碰撞体后沿父链找 interact() 方法；
## 有目标时显示提示文案（interact_prompt()），无目标时隐藏。
func _update_interact_target() -> void:
	var from := _camera.global_position
	var to := from + (-_camera.global_transform.basis.z) * GameConfig.INTERACT_RANGE
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var target: Node = null
	if not hit.is_empty():
		var n: Node = hit["collider"] as Node
		while n != null:
			if n.has_method("interact"):
				target = n
				break
			n = n.get_parent()
	_interact_target = target
	if _prompt_label != null:
		_prompt_label.visible = target != null
		if target != null:
			_prompt_label.text = target.interact_prompt()


## 自动上台阶：抬 STEP_MAX_HEIGHT → 前推 → 向下落回台阶面（三段 test_move，
## 任一段被挡即放弃，全程不穿透任何碰撞；落点必须高于原地面才认定为台阶）。
func _try_step_up(wish: Vector3) -> void:
	var step_h: float = GameConfig.STEP_MAX_HEIGHT
	var from := global_transform
	var up := Vector3(0.0, step_h, 0.0)
	if test_move(from, up):
		return  # 头顶无抬升余量（低门楣/楼板下）
	var forward: Vector3 = wish.normalized() * minf(wish.length() + 0.15, 0.45)
	var lifted := from.translated(up)
	if test_move(lifted, forward):
		return  # 抬高后前方仍被挡 → 是真墙不是台阶
	var stepped := lifted.translated(forward)
	var col := KinematicCollision3D.new()
	var down := Vector3(0.0, -(step_h + 0.05), 0.0)
	if not test_move(stepped, down, col):
		return  # 前方悬空（坑/悬崖），不挪
	var landing := stepped.translated(col.get_travel())
	if landing.origin.y - from.origin.y < 0.03:
		return  # 落点不比原地面高，不是台阶
	global_position = landing.origin
	velocity.y = 0.0


func _process(delta: float) -> void:
	# 相机高度 CAM_HEIGHT_LERP_TIME 平滑过渡（趴下/起身）。
	if not is_equal_approx(_camera.position.y, _cam_height_target):
		_cam_lerp_elapsed += delta
		var t := clampf(_cam_lerp_elapsed / GameConfig.CAM_HEIGHT_LERP_TIME, 0.0, 1.0)
		_camera.position.y = lerpf(_cam_height_from, _cam_height_target, t)

	# 开镜插值（ADS_LERP_TIME）：挂载位移 + FOV + 准星覆盖层同步驱动。
	var ads_target := 1.0 if GameState.is_aiming else 0.0
	if not is_equal_approx(_ads_weight, ads_target):
		_ads_weight = move_toward(_ads_weight, ads_target, delta / GameConfig.ADS_LERP_TIME)
		_weapon_mount.position = _mount_hip_pos.lerp(
			_ads_mount_targets.get(GameState.current_weapon, _mount_hip_pos), _ads_weight)
		_camera.fov = lerpf(GameConfig.FOV_BASE,
			_ads_fov_targets.get(GameState.current_weapon, GameConfig.FOV_BASE), _ads_weight)
	# 准星覆盖层：权重过 60% 才显形（过渡中段不闪半吊子准星）；RPG 无覆盖层。
	if _ads_reticle != null:
		var mode: StringName = &"none"
		if GameState.current_weapon != &"rpg":
			mode = GameState.current_weapon
		if _ads_reticle.mode != mode or not is_equal_approx(_ads_reticle.weight, _ads_weight):
			_ads_reticle.mode = mode
			_ads_reticle.weight = _ads_weight
			_ads_reticle.queue_redraw()


## 当前移速：趴下 > 瞄准 > 疾跑（Shift+W 前进中）> 站立取基速，再按腿部状态乘系数。
func _current_speed() -> float:
	var base: float
	if GameState.is_prone:
		base = GameConfig.SPEED_PRONE
	elif GameState.is_aiming:
		base = GameConfig.SPEED_AIM
	elif Input.is_physical_key_pressed(KEY_SPRINT) and Input.is_physical_key_pressed(KEY_FORWARD):
		base = GameConfig.SPEED_SPRINT
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


## 右键按住开镜（2026-10-19 机主立项重做：原切换式只减速像潜行，现带挂载归中 +
## FOV 收窄 + 青蓝准星覆盖层三件套）。is_aiming 语义不变（散布/移速/灵敏度下游零改动）。
func _set_aiming(aiming: bool) -> void:
	if GameState.is_aiming == aiming:
		return
	GameState.is_aiming = aiming
	Events.player_aim_changed.emit(aiming)


## 武器后坐接收（蜂后裁决：recoil_kick 不上总线，player.tscn 内局部连接）。
## 语义即「rotation.x += delta」：增量同步进 _pitch 保持鼠标/后坐状态一致，
## 沿用既有俯仰钳制，避免后坐把相机推出 ±PITCH_CLAMP。
func _on_weapon_recoil_kick(pitch_delta: float) -> void:
	_pitch = clampf(_pitch + pitch_delta, -GameConfig.PITCH_CLAMP, GameConfig.PITCH_CLAMP)
	_camera.rotation.x = _pitch


## 1/2：切枪占位——改写 GameState.current_weapon + 发信号。
func _switch_weapon(weapon_id: StringName) -> void:
	if GameState.current_weapon == weapon_id:
		return
	GameState.current_weapon = weapon_id
	Events.weapon_switched.emit(weapon_id)


## X：射击模式循环（2026-10-19 机主立项）——全自动 → 三发点射 → 半自动 → 回全自动。
## RPG 投射物无模式概念，直接忽略。状态入 GameState.fire_modes 契约字段 + 发信号。
func _cycle_fire_mode() -> void:
	var w := GameState.current_weapon
	if w == &"rpg":
		return
	const ORDER: Array[StringName] = [&"auto", &"burst", &"semi"]
	var cur: StringName = GameState.fire_modes.get(w, &"auto")
	GameState.fire_modes[w] = ORDER[(ORDER.find(cur) + 1) % ORDER.size()]
	Events.fire_mode_changed.emit(w, GameState.fire_modes[w])


## N：夜视仪切换占位。白天禁开（§11.2）：白天且当前未开启时直接返回；关闭不限时段。
func _toggle_night_vision() -> void:
	if not GameState.is_night and not GameState.night_vision:
		return
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
	_update_leg_state()


## 玩家承伤管线（§6 既定修复落地 + web takeDamage L3252-3292 复刻，2026-08-19 Phase 0b）。
## 发射侧（enemy_base._damage_player）只随机部位发信号；护甲/头盔吸收、部位系数、
## 溢出分摊、致死判定全部在本函数收口。任务结束态（COMPLETED/GAME_OVER）不再承伤。
func _apply_damage(part: StringName, amount: float) -> void:
	if GameState.mission_phase == GameState.MissionPhase.COMPLETED \
			or GameState.mission_phase == GameState.MissionPhase.GAME_OVER:
		return
	var actual := amount
	# 受击即打断护甲/部位回充计时（2026-10-19 纳米服式回充）。
	_armor_regen_wait = 0.0
	# （头盔吸收模块已于 2026-10-19 机主裁决取消：头盔耐久归并入护甲，头部承伤直接走部位系数。）
	# 护甲吸收（仅躯体；上限 = 原始伤害 × ARMOR_ABSORB_FACTOR，web L3269-3273 既有口径）。
	if part == &"body" and GameState.armor > 0.0:
		var armor_absorb := minf(GameState.armor, amount * GameConfig.ARMOR_ABSORB_FACTOR)
		GameState.armor -= armor_absorb
		actual -= armor_absorb
		Events.armor_changed.emit(GameState.armor, GameConfig.ARMOR_MAX)
	# 部位系数 + 趴下爆头减免（web L3275-3278）。
	if part == &"head":
		actual *= GameConfig.DMG_TAKEN_HEAD_FACTOR
		if GameState.is_prone:
			actual *= GameConfig.DMG_TAKEN_PRONE_HEAD_FACTOR
	elif part == &"legs":
		actual *= GameConfig.DMG_TAKEN_LEGS_FACTOR
	GameState.health[part] -= actual
	# 溢出分摊（§6 修复 web 死代码：先算溢出再清零，均摊到仍有血的部位，单趟不连锁）。
	if GameState.health[part] <= 0.0:
		var overflow: float = -GameState.health[part]
		GameState.health[part] = 0.0
		var others: Array = []
		for p: StringName in GameState.health:
			if p != part and GameState.health[p] > 0.0:
				others.append(p)
		if overflow > 0.0 and not others.is_empty():
			var per_part: float = overflow / others.size()
			for p: StringName in others:
				GameState.health[p] = maxf(0.0, GameState.health[p] - per_part)
				Events.player_health_changed.emit(p, GameState.health[p], _part_max_health(p))
	Events.player_health_changed.emit(part, GameState.health[part], _part_max_health(part))
	_update_leg_state()
	# 致死判定（web L3290：头/躯清零即结算；腿部清零不致死）。
	if GameState.health[&"head"] <= 0.0 or GameState.health[&"body"] <= 0.0:
		GameState.mission_phase = GameState.MissionPhase.GAME_OVER
		Events.game_over.emit(&"enemy")


## 腿部状态派生：≤0 → critical（×0.25），≤60% → injured（×0.5）（阈值契约 L3242-3243 既有）。
func _update_leg_state() -> void:
	var legs: float = GameState.health[&"legs"]
	var new_state: StringName = &"healthy"
	if legs <= 0.0:
		new_state = &"critical"
	elif legs <= GameConfig.HEALTH_LEGS * GameConfig.LEG_INJURED_THRESHOLD:
		new_state = &"injured"
	if new_state != GameState.leg_state:
		GameState.leg_state = new_state
		Events.leg_state_changed.emit(new_state)


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


## 开镜准星覆盖层（2026-10-19 机主立项）：青蓝 (0.4,0.95,1.0) 全息风。
## rifle = 全息圆环 + 心点 + 四向刻度；pistol = 点状准星；none/rpg = 不画。
## 权重 <0.6 不显形（开镜过渡中段由 HUD 准星交接，避免双准星）。
class AdsReticle extends Control:
	var mode: StringName = &"none"
	var weight: float = 0.0

	func _draw() -> void:
		if weight < 0.6 or mode == &"none":
			return
		var alpha: float = clampf((weight - 0.6) / 0.4, 0.0, 1.0) * 0.9
		var color := Color(0.4, 0.95, 1.0, alpha)
		var center := size * 0.5
		match mode:
			&"rifle":
				# 全息环：外环 + 心点 + 四向短刻度
				draw_arc(center, 22.0, 0.0, TAU, 64, color, 1.6, true)
				draw_circle(center, 2.2, color)
				for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					draw_line(center + dir * 26.0, center + dir * 31.0, color, 1.6, true)
			&"pistol":
				# 点状准星：心点 + 微光晕圈
				draw_arc(center, 5.0, 0.0, TAU, 32, Color(color, alpha * 0.45), 1.2, true)
				draw_circle(center, 2.0, color)
