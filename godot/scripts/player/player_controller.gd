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
const KEY_CATEGORY_PISTOL: Key = KEY_1
const KEY_CATEGORY_SMG: Key = KEY_2
const KEY_CATEGORY_RIFLE: Key = KEY_3
const KEY_CATEGORY_SHOTGUN: Key = KEY_4
const KEY_CATEGORY_MACHINE_GUN: Key = KEY_5
const KEY_CATEGORY_HEAVY: Key = KEY_6
const KEY_NIGHT_VISION: Key = KEY_N ## N：夜视仪切换（§11.2 机主裁决：V→N，与昼夜演示场景键位一致）
const KEY_MEDKIT: Key = KEY_G ## G：使用药包（F 统一交互）
const KEY_HELI: Key = KEY_H ## 网页版 H：呼叫直升机
const KEY_JUMP: Key = KEY_SPACE ## 空格：跳跃（2026-10-18 机主立项）
const KEY_SPRINT: Key = KEY_SHIFT ## 左 Shift+W：疾跑（2026-10-19 机主立项）
const KEY_INTERACT: Key = KEY_F ## F：统一交互（开门/叙事等；拾取物不走此键，贴近自动捡拾）
const KEY_FIRE_MODE: Key = KEY_X ## X：射击模式循环 全自动→三发点射→半自动（2026-10-19 机主立项）
const KEY_RELEASE_MOUSE: Key = KEY_ESCAPE ## Esc：释放鼠标（点击画面恢复捕获）
const KEY_BIG_MAP: Key = KEY_M ## M：全屏实时战术地图
const KEY_NANO_MODE: Key = KEY_Q ## Q：装甲模式开关
const KEY_STEALTH: Key = KEY_E ## E：隐形模式开关

var _pitch: float = 0.0
var _is_moving: bool = false
var _jump_queued: bool = false ## 跳跃排队位（2026-10-19 修复：输入帧置位、物理帧消费，避免被重力清零）
var _jump_charge_time: float = 0.0
var _jump_power_queued: bool = false
var _visual_nano_mode: StringName = &""
var _speed_state: StringName = &"normal"
var _still_broadcast_second: int = 0

# 相机高度过渡状态（CAM_HEIGHT_LERP_TIME 定时线性过渡）
var _cam_height_from: float = 0.0
var _cam_height_target: float = 0.0
var _cam_lerp_elapsed: float = 0.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
@export var world_bounds := Vector2(GameConfig.WORLD_BOUND_X, GameConfig.WORLD_BOUND_Z)

# E 键通用交互（2026-10-18 机主立项）：准星射线命中带 interact() 方法的节点即生效
var _interact_target: Node = null
var _prompt_label: Label = null

# —— 按住开镜（ADS，2026-10-19 机主立项）——
# 开镜权重 0..1 插值驱动：WeaponMount 位移（optic 归中相机轴）+ FOV 收窄 + 准星覆盖层。
var _ads_weight: float = 0.0
var _last_ads_weapon: StringName = &""
var _mount_hip_pos: Vector3 = Vector3.ZERO ## 腰射挂载位（_ready 从 player.tscn 实测读取）
var _ads_mount_targets: Dictionary = {} ## weapon_id → 开镜挂载位（optic 中心对中）
var _shotgun_optic_center := Vector3.ZERO
var _ads_fov_targets: Dictionary = {} ## weapon_id → 开镜 FOV
var _em86s_zoom_index: int = 0
var _ads_reticle: AdsReticle = null
var _dmr_scope: ColorRect = null
var _dmr_scope_material: ShaderMaterial = null
var _dmr_tactical: Control = null
var _missile_scope: ColorRect = null
var _missile_scope_material: ShaderMaterial = null
var _missile_tactical: Control = null
var _big_map: Control = null
var _scope_view_models: Dictionary = {}
@onready var _dmr_view_model: Node3D = $Camera3D/WeaponMount/DMR/ViewModel
@onready var _shotgun_controller: Node = $Camera3D/WeaponMount/Shotgun
@onready var _em57s2_controller: Node = $Camera3D/WeaponMount/Em57s2
## 瞄具双网格切换（2026-10-20 机主立项）：常规视角用完整瞄具（外观完好），
## 开镜过半把 optic 网格换成独立开孔版（透视镜筒），收镜过半换回。
## 开孔版由 extract_optic_bored.py / open_generated_optic.py 从完整 GLB 提取，几何同源、坐标系一致，直接换 mesh 即可。
const OPTIC_BORED_GLB := {
	&"rifle": "res://assets/models/weapons/em68a_optic_bored.glb",
	&"shotgun": "res://assets/models/weapons/em12g1_optic_bored.glb",
}
var _optic_meshes: Dictionary = {}
## 显示深度与射击方向分离：只压缩枪臂显示树，武器根节点 basis 始终保持原值。
const ViewmodelDepthReset := preload("res://scripts/player/viewmodel_depth_reset.gd")
const ViewmodelSkinBounds := preload("res://scripts/player/viewmodel_skin_bounds.gd")
var _viewmodel_skin_bounds := ViewmodelSkinBounds.new()
var _viewmodel_depth_scale: float = 1.0
var _viewmodel_depth_applied: bool = false
var _viewmodel_depth_hidden: bool = false
var _viewmodel_depth_mount_home := Vector3.ZERO
var _viewmodel_depth_mount_visible: bool = true
var _viewmodel_depth_models: Array[Node3D] = []
var _viewmodel_depth_meshes: Array[MeshInstance3D] = []
var _viewmodel_depth_homes: Dictionary = {}
var _viewmodel_depth_shape := BoxShape3D.new()
var _viewmodel_depth_query := PhysicsShapeQueryParameters3D.new()
## 护甲回充脱战计时（受击清零，≥ARMOR_REGEN_DELAY 后按 ARMOR_REGEN_RATE 回充）
var _armor_regen_wait: float = 0.0

@onready var _weapon_mount: Marker3D = $Camera3D/WeaponMount

@onready var _collision_shape: CollisionShape3D = $CollisionShape3D
@onready var _camera: Camera3D = $Camera3D
@onready var _camera_hip_z: float = _camera.position.z
@onready var _camera_hip_near: float = _camera.near


func _ready() -> void:
	process_priority = 1 # 武器姿态先更新，再计算相机与挂载补偿
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
	# 步枪=全息圆环+心点，手枪=点状（榴档沿用步枪全息环，直射档直瞄）。
	var reticle_layer := CanvasLayer.new()
	reticle_layer.name = "AdsReticle"
	reticle_layer.layer = 3
	_ads_reticle = AdsReticle.new()
	_ads_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ads_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle_layer.add_child(_ads_reticle)
	add_child(reticle_layer)
	_dmr_scope = ColorRect.new()
	_dmr_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dmr_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dmr_scope_material = ShaderMaterial.new()
	_dmr_scope_material.shader = load("res://scripts/player/dmr_scope.gdshader") as Shader
	_dmr_scope.material = _dmr_scope_material
	_dmr_scope.visible = false
	reticle_layer.add_child(_dmr_scope)
	_dmr_tactical = load("res://scripts/player/dmr_tactical_overlay.gd").new() as Control
	_dmr_tactical.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dmr_tactical.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dmr_tactical.set("camera", _camera)
	_dmr_tactical.set("excluded_rids", [get_rid()])
	_dmr_tactical.visible = false
	reticle_layer.add_child(_dmr_tactical)
	_missile_scope = ColorRect.new()
	_missile_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_missile_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_missile_scope_material = ShaderMaterial.new()
	_missile_scope_material.shader = load("res://scripts/player/missile_scope.gdshader") as Shader
	_missile_scope.material = _missile_scope_material
	_missile_scope.visible = false
	reticle_layer.add_child(_missile_scope)
	_missile_tactical = load("res://scripts/player/missile_tactical_overlay.gd").new() as Control
	_missile_tactical.set_anchors_preset(Control.PRESET_FULL_RECT)
	_missile_tactical.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_missile_tactical.set("camera", _camera)
	_missile_tactical.set("excluded_rids", [get_rid()])
	_missile_tactical.set("range_limit", GameConfig.EM120R_MAX_RANGE)
	_missile_tactical.visible = false
	reticle_layer.add_child(_missile_tactical)
	_big_map = load("res://scripts/player/big_map.gd").new() as Control
	_big_map.visible = false
	reticle_layer.add_child(_big_map)
	_calibrate_ads()
	_ads_mount_targets[&"em57s2"].z = GameConfig.EM57S2_ADS_MOUNT_Z
	_ads_mount_targets[&"smg"] = _ads_mount_targets[&"rifle"]
	_ads_mount_targets[&"lmg"] = _ads_mount_targets[&"rifle"]
	_ads_mount_targets[&"em12g2"] = _ads_mount_targets[&"rifle"]
	for pair: Array in [[&"smg", "SMG/ViewModel/EM68A"], [&"lmg", "LMG/ViewModel/EM68A"], [&"magnum", "Magnum/ViewModel/EM57P"], [&"em12g2", "Em12g2/ViewModel/Weapon"]]:
		_scope_view_models[pair[0]] = _weapon_mount.get_node_or_null(pair[1])
	_load_optic_meshes()
	_setup_viewmodel_depth()
	# 承伤管线挂接（发射侧在 enemy_base._damage_player；结算收口在本类 _apply_damage）。
	Events.player_damaged.connect(_apply_damage)


## 瞄具双网格加载：完整网格从场景内武器子树实测持有，开孔网格从独立 GLB 提取。
## 加载失败保持 null，切换逻辑自动跳过（常规视角外观不受影响）。
func _load_optic_meshes() -> void:
	for pair: Array in [[&"rifle", "Rifle"], [&"shotgun", "Shotgun"]]:
		var weapon_root := _weapon_mount.get_node_or_null(pair[1]) as Node3D
		if weapon_root == null:
			continue
		var optic_mesh := _find_optic_mesh(weapon_root)
		if optic_mesh == null:
			continue
		var bored_scene: PackedScene = load(OPTIC_BORED_GLB[pair[0]])
		if bored_scene == null:
			continue
		var bored_root := bored_scene.instantiate()
		var bored_mi := _find_optic_mesh(bored_root)
		if bored_mi != null:
			_optic_meshes[pair[0]] = {
				"node": optic_mesh,
				"intact": optic_mesh.mesh,
				"bored": bored_mi.mesh,
			}
		bored_root.free()
	# EM 整枪瞄具只切换 Body：镜框恢复时保持 DetachableMagazine 独立。
	var em86b_root := _weapon_mount.get_node_or_null("Em86b") as Node3D
	if em86b_root != null:
		var current_mesh: MeshInstance3D = null
		for node in em86b_root.find_children("Body", "MeshInstance3D", true, false):
			current_mesh = node as MeshInstance3D
			break
		var intact_scene: PackedScene = load("res://assets/models/weapons/em86b_viewmodel_intact_reload.glb")
		if current_mesh != null and intact_scene != null:
			var intact_root := intact_scene.instantiate()
			for node in intact_root.find_children("Body", "MeshInstance3D", true, false):
				_optic_meshes[&"em86b"] = {
					"node": current_mesh,
					"intact": (node as MeshInstance3D).mesh,
					"bored": current_mesh.mesh,
				}
				break
			intact_root.free()
	var em57s2_root := _weapon_mount.get_node_or_null("Em57s2") as Node3D
	if em57s2_root != null:
		var current_mesh: MeshInstance3D = null
		for node in em57s2_root.find_children("Body", "MeshInstance3D", true, false):
			current_mesh = node as MeshInstance3D
			break
		var intact_scene: PackedScene = load("res://assets/models/weapons/em57s2_viewmodel_reload.glb")
		if current_mesh != null and intact_scene != null:
			var intact_root := intact_scene.instantiate()
			for node in intact_root.find_children("Body", "MeshInstance3D", true, false):
				_optic_meshes[&"em57s2"] = {
					"node": current_mesh,
					"intact": (node as MeshInstance3D).mesh,
					"bored": current_mesh.mesh,
				}
				break
			intact_root.free()
	var em86m_root := _weapon_mount.get_node_or_null("Em86m") as Node3D
	if em86m_root != null:
		var current_mesh: MeshInstance3D = null
		for node in em86m_root.find_children("Body", "MeshInstance3D", true, false):
			current_mesh = node as MeshInstance3D
			break
		var intact_scene: PackedScene = load("res://assets/models/weapons/em86m_viewmodel_reload.glb")
		if current_mesh != null and intact_scene != null:
			var intact_root := intact_scene.instantiate()
			for node in intact_root.find_children("Body", "MeshInstance3D", true, false):
				_optic_meshes[&"em86m"] = {
					"node": current_mesh,
					"intact": (node as MeshInstance3D).mesh,
					"bored": current_mesh.mesh,
				}
				break
			intact_root.free()
	var em12g2_root := _weapon_mount.get_node_or_null("Em12g2") as Node3D
	if em12g2_root != null:
		var current_mesh: MeshInstance3D = null
		for node in em12g2_root.find_children("Body", "MeshInstance3D", true, false):
			current_mesh = node as MeshInstance3D
			break
		var intact_scene: PackedScene = load("res://assets/models/weapons/em12g2_viewmodel_intact_reload.glb")
		if current_mesh != null and intact_scene != null:
			var intact_root := intact_scene.instantiate()
			for node in intact_root.find_children("Body", "MeshInstance3D", true, false):
				_optic_meshes[&"em12g2"] = {
					"node": current_mesh,
					"intact": (node as MeshInstance3D).mesh,
					"bored": current_mesh.mesh,
				}
				break
			intact_root.free()


## 开镜标定：从 player.tscn 实测腰射挂载位；步枪/手枪按 optic 网格 AABB 中心反推
## 开镜挂载位（optic 归中相机轴），免手调免硬编码几何；找不到 optic 时回退 x 归中。
func _calibrate_ads() -> void:
	_mount_hip_pos = _weapon_mount.position
	_ads_fov_targets = {
		&"rifle": GameConfig.RIFLE_ADS_FOV,
		&"pistol": GameConfig.PISTOL_ADS_FOV,
		&"g17": GameConfig.G17_ADS_FOV,
		&"dmr": GameConfig.DMR_ADS_FOV,
		&"shotgun": GameConfig.SHOTGUN_ADS_FOV,
		&"spas12": GameConfig.SPAS12_ADS_FOV,
		&"smg": GameConfig.SMG_ADS_FOV,
		&"mpx": GameConfig.MPX_ADS_FOV,
		&"lmg": GameConfig.LMG_ADS_FOV,
		&"magnum": GameConfig.MAGNUM_ADS_FOV,
		&"em86s": GameConfig.EM86S_SCOPE_FOVS[0],
		&"em86b": GameConfig.EM86B_ADS_FOV,
		&"em86d": GameConfig.EM86D_ADS_FOV,
		&"em86m": GameConfig.EM86M_ADS_FOV,
		&"em57s2": GameConfig.EM57S2_ADS_FOV,
		&"em40t1": GameConfig.EM40T1_ADS_FOV,
		&"em127g": GameConfig.EM127G_SCOPE_FOVS[0],
		&"em127m": GameConfig.EM127G_SCOPE_FOVS[0],
		&"em120r": GameConfig.EM127G_SCOPE_FOVS[0],
		&"em12g2": GameConfig.SHOTGUN_ADS_FOV,
	}
	for pair: Array in [[&"rifle", "Rifle"], [&"pistol", "Pistol"], [&"g17", "G17"], [&"dmr", "DMR"], [&"shotgun", "Shotgun"], [&"spas12", "Spas12"], [&"smg", "SMG"], [&"mpx", "MPX"], [&"em57s2", "Em57s2"], [&"lmg", "LMG"], [&"magnum", "Magnum"], [&"em86s", "Em86s"], [&"em86b", "Em86b"], [&"em86d", "Em86d"], [&"em86m", "Em86m"], [&"em40t1", "Em40t1"], [&"em127g", "Em127g"], [&"em12g2", "Em12g2"], [&"em127m", "Em127m"], [&"em120r", "Em120r"]]:
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
			if pair[0] == &"shotgun":
				_shotgun_optic_center = c
			# optic 相机空间坐标 = 挂载位 + c；令其 x/y 归零 → 挂载位取 -c。
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


## 新武器优先读取实测标定的 OpticAim 标记；旧步枪/手枪保留原有几何标定路径。
func _find_optic_center_in_mount(weapon_root: Node, weapon_id: StringName) -> Variant:
	var marker := weapon_root.get_node_or_null("ViewModel/Weapon/OpticAim") as Marker3D
	if marker == null:
		marker = weapon_root.get_node_or_null("ViewModel/OpticAim") as Marker3D
	if marker != null:
		return _weapon_mount.global_transform.affine_inverse() * marker.global_position
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
		elif button.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
				and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if GameState.current_weapon in [&"em86s", &"em127g", &"em127m", &"em120r"] and GameState.is_aiming:
				_adjust_em86s_zoom(1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			else:
				_cycle_unlocked_weapon(-1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		return

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.physical_keycode == KEY_JUMP and not key_event.pressed:
			_release_jump()
			return
		if not key_event.pressed or key_event.echo:
			return
		match key_event.physical_keycode:
			KEY_RELEASE_MOUSE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_BIG_MAP:
				_toggle_big_map()
			KEY_NANO_MODE:
				_toggle_armor()
			KEY_STEALTH:
				_toggle_stealth()
			KEY_PRONE:
				_toggle_prone()
			KEY_CATEGORY_PISTOL:
				_select_weapon_category(1)
			KEY_CATEGORY_SMG:
				_select_weapon_category(2)
			KEY_CATEGORY_RIFLE:
				_select_weapon_category(3)
			KEY_CATEGORY_SHOTGUN:
				_select_weapon_category(4)
			KEY_CATEGORY_MACHINE_GUN:
				_select_weapon_category(5)
			KEY_CATEGORY_HEAVY:
				_select_weapon_category(6)
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
	if _jump_charge_time > 0.0 and Input.is_physical_key_pressed(KEY_JUMP):
		_jump_charge_time += delta
		if _jump_charge_time >= GameConfig.NANO_POWER_JUMP_HOLD_TIME and not _jump_queued:
			_jump_queued = true
			_jump_power_queued = true
			_jump_charge_time = 0.0
	# 重力（引擎全局设置，非手感参数）；跳跃排队位在落地帧消费（修复：原先输入回调
	# 直接写 velocity.y，下一物理帧此处 is_on_floor 仍为 true 被清零，跳跃失效）。
	if is_on_floor():
		if _jump_queued:
			_jump_queued = false
			var power_jump := _jump_power_queued and GameState.armor > 0.0
			if power_jump:
				_consume_armor_energy(GameConfig.NANO_POWER_JUMP_COST)
			velocity.y = GameConfig.NANO_POWER_JUMP_VELOCITY if power_jump else GameConfig.JUMP_VELOCITY
			_jump_power_queued = false
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
	_update_nano_energy(delta, is_moving)
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
	global_position.x = clampf(global_position.x, -world_bounds.x, world_bounds.x)
	global_position.z = clampf(global_position.z, -world_bounds.y, world_bounds.y)

	# 每物理帧写入玩家世界坐标（G2 冻结新增字段；敌人感知/AI 共用）。
	GameState.player_position = global_position
	GameState.player_yaw = rotation.y

	_update_interact_target()
	_update_ec120_aim()

	_update_speed_state()
	_update_still_time(delta)
	_update_armor_regen(delta)


## 纳米服式回充（2026-10-19 机主立项，孤岛危机式；2026-10-21 单一生命值制简化）：
## 受击后 ARMOR_REGEN_DELAY 秒未再受击，护甲按 ARMOR_REGEN_RATE、生命值按
## HEALTH_REGEN_RATE 同步回复至各自上限；任务结束态不回复。
func _update_armor_regen(delta: float) -> void:
	if GameState.mission_phase == GameState.MissionPhase.COMPLETED \
			or GameState.mission_phase == GameState.MissionPhase.GAME_OVER:
		return
	var needs := GameState.armor < GameConfig.ARMOR_MAX or GameState.hp < GameConfig.HEALTH_MAX
	if not needs:
		return
	_armor_regen_wait += delta
	if _armor_regen_wait < GameConfig.ARMOR_REGEN_DELAY:
		return
	if GameState.armor < GameConfig.ARMOR_MAX:
		GameState.armor = minf(GameState.armor + GameConfig.ARMOR_REGEN_RATE * delta, GameConfig.ARMOR_MAX)
		Events.armor_changed.emit(GameState.armor, GameConfig.ARMOR_MAX)
	if GameState.hp < GameConfig.HEALTH_MAX:
		GameState.hp = minf(GameState.hp + GameConfig.HEALTH_REGEN_RATE * delta, GameConfig.HEALTH_MAX)
		Events.player_health_changed.emit(&"hp", GameState.hp, GameConfig.HEALTH_MAX)


func _try_jump() -> void:
	if GameState.is_prone or _jump_charge_time > 0.0:
		return
	_jump_charge_time = 0.0001
	_jump_power_queued = false


func _release_jump() -> void:
	if _jump_charge_time > 0.0 and not _jump_queued:
		_jump_queued = true
		_jump_power_queued = _jump_charge_time >= GameConfig.NANO_POWER_JUMP_HOLD_TIME
	_jump_charge_time = 0.0


func _update_nano_energy(delta: float, moving: bool) -> void:
	var power_sprinting := moving and _power_sprint_requested() and GameState.armor > 0.0
	var drain := 0.0
	if GameState.nano_mode == &"stealth" and moving:
		drain = GameConfig.NANO_STEALTH_SPRINT_DRAIN_PER_SEC if power_sprinting else GameConfig.NANO_STEALTH_WALK_DRAIN_PER_SEC
	elif power_sprinting:
		drain = GameConfig.NANO_POWER_SPRINT_DRAIN_PER_SEC
	if drain > 0.0:
		_consume_armor_energy(drain * delta)


func _consume_armor_energy(amount: float) -> void:
	if amount <= 0.0:
		return
	_armor_regen_wait = 0.0
	GameState.armor = maxf(0.0, GameState.armor - amount)
	Events.armor_changed.emit(GameState.armor, GameConfig.ARMOR_MAX)
	if GameState.armor > 0.0 or GameState.nano_mode == &"normal":
		return
	var previous_mode := GameState.nano_mode
	_set_nano_mode(&"normal")
	var labels := {&"armor": "装甲", &"stealth": "隐形"}
	Events.message_posted.emit("护甲能量耗尽，%s解除" % labels.get(previous_mode, "主动模式"))


## F 键通用交互：当前射线目标（_update_interact_target 每物理帧刷新）响应即调用。
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


## 长弓的激光指向与鼠标准星共用相机射线；武器/导弹只消费总线和状态契约。
func _update_ec120_aim() -> void:
	if GameState.current_weapon != &"em120r" or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var from := _camera.global_position
	var to := from - _camera.global_basis.z * GameConfig.EM120R_MAX_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	GameState.em120r_aim_origin = from
	Events.ec120_aim_origin_changed.emit(from)
	GameState.em120r_aim_point = to if hit.is_empty() else hit.position
	Events.ec120_aim_changed.emit(GameState.em120r_aim_point)


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
	# 正常帧由早优先级子节点还原；保留手动调用 _process 的测试路径。
	_restore_viewmodel_depth()
	# 相机高度 CAM_HEIGHT_LERP_TIME 平滑过渡（趴下/起身）。
	if not is_equal_approx(_camera.position.y, _cam_height_target):
		_cam_lerp_elapsed += delta
		var t := clampf(_cam_lerp_elapsed / GameConfig.CAM_HEIGHT_LERP_TIME, 0.0, 1.0)
		_camera.position.y = lerpf(_cam_height_from, _cam_height_target, t)

	if _visual_nano_mode != GameState.nano_mode:
		_apply_nano_visuals()
	# 开镜插值（ADS_LERP_TIME）：挂载位移 + FOV + 准星覆盖层同步驱动。
	# EM-57S-2 换弹暂退视觉开镜；保持右键输入，结束后自动回到前方瞄具。
	var lowering_for_reload := GameState.current_weapon == &"em57s2" and bool(_em57s2_controller.get("_is_reloading"))
	var ads_target := 1.0 if GameState.is_aiming and not lowering_for_reload else 0.0
	var weapon_changed := _last_ads_weapon != GameState.current_weapon
	if not is_equal_approx(_ads_weight, ads_target) or weapon_changed or GameState.current_weapon in [&"shotgun", &"em86s", &"em127g", &"em127m", &"em120r"]:
		_last_ads_weapon = GameState.current_weapon
		_ads_weight = move_toward(_ads_weight, ads_target, delta / GameConfig.ADS_LERP_TIME)
		if GameState.current_weapon == &"shotgun":
			_weapon_mount.position = _shotgun_mount_for_weight(_shotgun_controller.get("_aim_weight"))
		else:
			_weapon_mount.position = _mount_hip_pos.lerp(
				_ads_mount_targets.get(GameState.current_weapon, _mount_hip_pos), _ads_weight)
		var fov_target: float = _ads_fov_targets.get(GameState.current_weapon, GameConfig.FOV_BASE)
		if GameState.current_weapon in [&"em86s", &"em127g", &"em127m", &"em120r"]:
			fov_target = _scope_fovs()[_em86s_zoom_index]
		_camera.fov = lerpf(GameConfig.FOV_BASE, fov_target, _ads_weight)
		var camera_forward: float = GameConfig.SHOTGUN_ADS_CAMERA_FORWARD if GameState.current_weapon == &"shotgun" else 0.0
		_camera.position.z = _camera_hip_z - camera_forward * _ads_weight
	# EM-57S-2 前方眼位：近平面截口移出画面下缘，收镜和切枪恢复原近平面。
	var near_weight := _ads_weight if GameState.current_weapon == &"em57s2" else 0.0
	_camera.near = lerpf(_camera_hip_near, GameConfig.EM57S2_ADS_NEAR, near_weight)
	# 准星覆盖层：权重过 60% 才显形（过渡中段不闪半吊子准星）；榴档沿用步枪全息准星
	# （直射档平直弹道，全息环直瞄即可）。
	if _ads_reticle != null:
		var mode := GameState.current_weapon
		if GameState.current_weapon in [&"g17", &"mpx"]:
			mode = &"none" ## Gen5 机械瞄具及 MPX 源红准星均使用真实模型，不叠加 HUD 瞄点。
		if GameState.current_weapon == &"em12g2":
			mode = &"shotgun"
		if _ads_reticle.mode != mode or not is_equal_approx(_ads_reticle.weight, _ads_weight):
			_ads_reticle.mode = mode
			_ads_reticle.weight = _ads_weight
			_ads_reticle.queue_redraw()
	for weapon_id in _scope_view_models:
		var model := _scope_view_models[weapon_id] as Node3D
		if model != null:
			model.visible = GameState.current_weapon != weapon_id or _ads_weight < 0.75 or weapon_id == &"magnum"
	if GameState.current_weapon in [&"smg", &"lmg", &"em12g2"]:
		_weapon_mount.get_node("Rifle").visible = _ads_weight >= 0.75
	for pair: Array in [[&"smg", "SMG"], [&"lmg", "LMG"], [&"em12g2", "Em12g2"]]:
		var arms := _weapon_mount.get_node(pair[1]).get("_arms_node") as Node3D
		if arms != null:
			arms.visible = GameState.current_weapon != pair[0] or _ads_weight < 0.75
	var grenade_scope := GameState.current_weapon == &"em40t1"
	var full_scope := GameState.current_weapon in [&"dmr", &"em86s", &"em86d", &"em127g", &"em127m", &"em40t1"] and _ads_weight > 0.6
	var missile_scope := GameState.current_weapon == &"em120r" and _ads_weight > 0.6
	if _dmr_scope != null:
		_dmr_scope.visible = full_scope
		_dmr_tactical.visible = full_scope
		match GameState.current_weapon:
			&"dmr":
				_dmr_view_model.visible = not full_scope
			&"em86s":
				_weapon_mount.get_node("Em86s/ViewModel").visible = not full_scope
			&"em86d":
				_weapon_mount.get_node("Em86d/ViewModel").visible = not full_scope
			&"em127g":
				_weapon_mount.get_node("Em127g/ViewModel").visible = not full_scope
			&"em127m":
				_weapon_mount.get_node("Em127m/ViewModel").visible = not full_scope
			&"em40t1":
				_weapon_mount.get_node("Em40t1/ViewModel").visible = not full_scope
		var viewport_size := get_viewport().get_visible_rect().size
		_dmr_scope_material.set_shader_parameter("aspect", viewport_size.x / viewport_size.y)
		_dmr_scope_material.set_shader_parameter("weight", clampf((_ads_weight - 0.6) / 0.4, 0.0, 1.0))
		_dmr_scope_material.set_shader_parameter("center_style", 2.0 if grenade_scope else (1.0 if GameState.current_weapon in [&"em86s", &"em127g", &"em127m"] else 0.0))
		_dmr_tactical.set("zoom_text", "%dX" % _scope_zooms()[_em86s_zoom_index] if GameState.current_weapon in [&"em86s", &"em127g", &"em127m"] else "")
		_dmr_tactical.set("reticle_mode", &"grenade" if grenade_scope else &"hitscan")
		_dmr_tactical.set("range_limit", GameConfig.GRENADE_MAX_RANGE if grenade_scope else GameConfig.DMR_RANGE)
		_dmr_tactical.set("projectile_speed", GameConfig.GRENADE_PROJECTILE_SPEED)
		_dmr_tactical.set("projectile_gravity", GameConfig.GRENADE_GRAVITY)
		_ads_reticle.visible = not full_scope and not missile_scope
	if _missile_scope != null:
		_missile_scope.visible = missile_scope
		_missile_tactical.visible = missile_scope
		var viewport_size := get_viewport().get_visible_rect().size
		_missile_scope_material.set_shader_parameter("aspect", viewport_size.x / viewport_size.y)
		_missile_scope_material.set_shader_parameter("weight", clampf((_ads_weight - 0.6) / 0.4, 0.0, 1.0))
		_missile_tactical.set("zoom_text", "%dX" % _scope_zooms()[_em86s_zoom_index])
		if GameState.current_weapon == &"em120r":
			_weapon_mount.get_node("Em120r/ViewModel").visible = not missile_scope
	# 瞄具双网格切换：当前武器且开镜过半用开孔版，其余情况回完整版。
	# 切换点取过渡中点（0.5），此时镜筒正在归中途中，换网格肉眼不可察。
	for weapon_id: StringName in _optic_meshes:
		var pair: Dictionary = _optic_meshes[weapon_id]
		var wants_rifle_optic := GameState.current_weapon == weapon_id or (weapon_id == &"rifle" and GameState.current_weapon in [&"smg", &"lmg", &"em12g2"])
		var want_bored := wants_rifle_optic and _ads_weight > 0.5
		var target_mesh: Mesh = pair.bored if want_bored else pair.intact
		if pair.node.mesh != target_mesh:
			pair.node.mesh = target_mesh
	_apply_viewmodel_depth(delta)


func _setup_viewmodel_depth() -> void:
	for weapon in _weapon_mount.get_children():
		var model := weapon.get_node_or_null("ViewModel") as Node3D
		if model != null:
			_viewmodel_depth_models.append(model)
	for node in _weapon_mount.find_children("*", "MeshInstance3D", true, false):
		# 制导光束跨越整个世界，不属于枪臂的实体显示体积。
		if not String(node.name).to_lower().contains("laser"):
			_viewmodel_depth_meshes.append(node as MeshInstance3D)
	_viewmodel_depth_query.shape = _viewmodel_depth_shape
	_viewmodel_depth_query.margin = GameConfig.VIEWMODEL_WALL_MARGIN
	_viewmodel_depth_query.exclude = [get_rid()]
	_viewmodel_depth_query.collide_with_areas = false
	var reset := ViewmodelDepthReset.new()
	reset.name = "ViewmodelDepthReset"
	reset.process_priority = -1
	add_child(reset)


## 武器姿态 priority=0 更新前还原显示变换，避免换弹/后坐读取上帧压缩坐标。
func _restore_viewmodel_depth() -> void:
	if _viewmodel_depth_hidden:
		_weapon_mount.visible = _viewmodel_depth_mount_visible
		_viewmodel_depth_hidden = false
	if not _viewmodel_depth_applied:
		return
	_weapon_mount.position = _viewmodel_depth_mount_home
	for model in _viewmodel_depth_models:
		var home: Dictionary = _viewmodel_depth_homes[model]
		model.position = home.position
		model.scale = home.scale
	_viewmodel_depth_applied = false


## 从眼位到完整枪臂的包围盒包含相机原点，缩小后的盒体严格嵌套。
## 相比角点射线，实体查询也能拦截盒内的窄门框、柱子和墙角。
func _apply_viewmodel_depth(delta: float) -> void:
	var bounds := AABB(Vector3.ZERO, Vector3.ZERO)
	var has_geometry := false
	var camera_inverse := _camera.global_transform.affine_inverse()
	for instance in _viewmodel_depth_meshes:
		if not instance.is_visible_in_tree() or instance.mesh == null:
			continue
		has_geometry = true
		var box: AABB = _viewmodel_skin_bounds.get_pose_bounds(instance)
		var to_camera := camera_inverse * instance.global_transform
		for corner in 8:
			var point := box.position + box.size * Vector3(float(corner & 1), float((corner >> 1) & 1), float((corner >> 2) & 1))
			bounds = bounds.expand(to_camera * point)
	var target_scale := 1.0
	if has_geometry and _viewmodel_box_overlaps(bounds, 1.0):
		var clear_scale: float = GameConfig.VIEWMODEL_WALL_MIN_SCALE
		if _viewmodel_box_overlaps(bounds, clear_scale):
			# 连最小非零显示体积也无安全空间：不写零缩放或奇异 transform。
			_viewmodel_depth_mount_visible = _weapon_mount.visible
			_weapon_mount.visible = false
			_viewmodel_depth_hidden = true
			return
		var blocked_scale := 1.0
		for step in GameConfig.VIEWMODEL_WALL_SEARCH_STEPS:
			var middle := (clear_scale + blocked_scale) * 0.5
			if _viewmodel_box_overlaps(bounds, middle):
				blocked_scale = middle
			else:
				clear_scale = middle
		target_scale = clear_scale
	# 接近时立即满足安全上限；退开时只从安全侧恢复，不在过渡帧穿墙。
	_viewmodel_depth_scale = minf(target_scale, move_toward(_viewmodel_depth_scale, target_scale, delta / GameConfig.VIEWMODEL_WALL_RELEASE_TIME))
	if is_equal_approx(_viewmodel_depth_scale, 1.0):
		return
	_viewmodel_depth_mount_home = _weapon_mount.position
	_weapon_mount.position *= _viewmodel_depth_scale
	for model in _viewmodel_depth_models:
		_viewmodel_depth_homes[model] = {"position": model.position, "scale": model.scale}
		model.position *= _viewmodel_depth_scale
		model.scale *= _viewmodel_depth_scale
	_viewmodel_depth_applied = true
	# 眼位投影不变，近平面同比例收缩，避免枪臂在眼前被截断。
	_camera.near = maxf(GameConfig.VIEWMODEL_WALL_MIN_NEAR, _camera.near * _viewmodel_depth_scale)
	if GameState.current_weapon == &"em120r":
		# 既有事件刷新光束，起点跟随压缩后的枪口，世界目标保持原位置。
		Events.ec120_aim_changed.emit(GameState.em120r_aim_point)


func _viewmodel_box_overlaps(bounds: AABB, depth_scale: float) -> bool:
	_viewmodel_depth_shape.size = bounds.size * depth_scale
	_viewmodel_depth_query.transform = Transform3D(_camera.global_basis, _camera.global_transform * (bounds.get_center() * depth_scale))
	var hits := get_world_3d().direct_space_state.intersect_shape(_viewmodel_depth_query, 1)
	return not hits.is_empty()


func _shotgun_mount_for_weight(weight: float) -> Vector3:
	var hip_q := Quaternion(Vector3.UP, GameConfig.SHOTGUN_HIP_POSE_YAW) * Quaternion(Vector3.RIGHT, GameConfig.SHOTGUN_HIP_POSE_PITCH)
	var current_q := Quaternion(Vector3.UP, GameConfig.SHOTGUN_HIP_POSE_YAW * (1.0 - weight)) \
		* Quaternion(Vector3.RIGHT, GameConfig.SHOTGUN_HIP_POSE_PITCH * (1.0 - weight))
	var hip_center := _mount_hip_pos + hip_q * _shotgun_optic_center
	var desired_center := hip_center.lerp(Vector3(GameConfig.SHOTGUN_ADS_OFFSET_X, 0.0, hip_center.z), weight)
	var rotated_center := current_q * _shotgun_optic_center
	return Vector3(desired_center.x - rotated_center.x, desired_center.y - rotated_center.y, _mount_hip_pos.z)


## 当前移速：趴下 > 瞄准 > 疾跑（Shift+W 前进中）> 站立取基速。
## （2026-10-21 单一生命值制：腿部受伤减速机制随三部位耐久一同退役。）
func _current_speed() -> float:
	var base: float
	if GameState.is_prone:
		base = GameConfig.SPEED_PRONE
	elif GameState.is_aiming:
		base = GameConfig.SPEED_AIM
	elif _power_sprint_requested():
		base = GameConfig.NANO_POWER_SPEED if GameState.armor > 0.0 else GameConfig.SPEED_SPRINT
	else:
		base = GameConfig.SPEED_STAND
	return base


func _power_sprint_requested() -> bool:
	return not GameState.is_prone and not GameState.is_aiming \
		and Input.is_physical_key_pressed(KEY_SPRINT) and Input.is_physical_key_pressed(KEY_FORWARD)


## 移速状态变化广播（供 HUD；契约既有信号）。
func _update_speed_state() -> void:
	var state: StringName = &"normal"
	if GameState.is_prone:
		state = &"prone"
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


func _toggle_big_map() -> void:
	if _big_map == null:
		return
	_big_map.visible = not _big_map.visible
	if _big_map.visible:
		_big_map.call("_refresh_markers")
		_big_map.queue_redraw()


## 右键按住开镜（2026-10-19 机主立项重做：原切换式只减速像潜行，现带挂载归中 +
## FOV 收窄 + 青蓝准星覆盖层三件套）。is_aiming 语义不变（散布/移速/灵敏度下游零改动）。
func _set_aiming(aiming: bool) -> void:
	if GameState.is_aiming == aiming:
		return
	if aiming and GameState.current_weapon in [&"em86s", &"em127g", &"em127m", &"em120r"]:
		_em86s_zoom_index = 0
	GameState.is_aiming = aiming
	Events.player_aim_changed.emit(aiming)


func _scope_fovs() -> Array[float]:
	return GameConfig.EM127G_SCOPE_FOVS if GameState.current_weapon in [&"em127g", &"em127m", &"em120r"] else GameConfig.EM86S_SCOPE_FOVS


func _scope_zooms() -> Array[int]:
	return GameConfig.EM127G_SCOPE_ZOOMS if GameState.current_weapon in [&"em127g", &"em127m", &"em120r"] else GameConfig.EM86S_SCOPE_ZOOMS


func _adjust_em86s_zoom(direction: int) -> void:
	_em86s_zoom_index = clampi(_em86s_zoom_index + direction, 0, _scope_fovs().size() - 1)


## 武器后坐接收（蜂后裁决：recoil_kick 不上总线，player.tscn 内局部连接）。
## 语义即「rotation.x += delta」：增量同步进 _pitch 保持鼠标/后坐状态一致，
## 沿用既有俯仰钳制，避免后坐把相机推出 ±PITCH_CLAMP。
func _on_weapon_recoil_kick(pitch_delta: float) -> void:
	_pitch = clampf(_pitch + pitch_delta, -GameConfig.PITCH_CLAMP, GameConfig.PITCH_CLAMP)
	_camera.rotation.x = _pitch


func _select_weapon_category(category_number: int) -> void:
	Events.weapon_category_selected.emit(category_number)
	for category: Dictionary in GameConfig.WEAPON_CATEGORIES:
		if category.number != category_number:
			continue
		var weapons: Array = category.weapons
		if weapons.is_empty():
			Events.message_posted.emit("该武器类别尚未获取")
			return
		var current_index := weapons.find(GameState.current_weapon)
		if current_index >= 0:
			for step in range(1, weapons.size()):
				var candidate: StringName = weapons[(current_index + step) % weapons.size()]
				if GameState.weapon_unlocked.get(candidate, false):
					_switch_weapon(candidate)
					return
		else:
			for weapon_id: StringName in weapons:
				if GameState.weapon_unlocked.get(weapon_id, false):
					_switch_weapon(weapon_id)
					return
		if current_index < 0:
			Events.message_posted.emit("该类别武器尚未领取——前往 JB-02 后舱雷暴装备位")
		return


func _cycle_unlocked_weapon(direction: int) -> void:
	var available: Array[StringName] = []
	for weapon_id: StringName in GameConfig.WEAPON_SCROLL_ORDER:
		if GameState.weapon_unlocked.get(weapon_id, false):
			available.append(weapon_id)
	if available.is_empty():
		return
	var index := available.find(GameState.current_weapon)
	if index < 0:
		index = 0 if direction > 0 else available.size() - 1
	else:
		index = posmod(index + direction, available.size())
	var target := available[index]
	_switch_weapon(target)
	Events.weapon_category_selected.emit(_weapon_category_for(target))


func _weapon_category_for(weapon_id: StringName) -> int:
	for category: Dictionary in GameConfig.WEAPON_CATEGORIES:
		if weapon_id in category.weapons:
			return category.number
	return 1


## 改写 GameState.current_weapon + 发信号；类别选择与滚轮共用此入口。
func _switch_weapon(weapon_id: StringName) -> void:
	if GameState.current_weapon == weapon_id:
		return
	if not GameState.weapon_unlocked.get(weapon_id, false):
		Events.message_posted.emit("尚未领取该武器——前往 JB-02 后舱雷暴装备位")
		return
	GameState.current_weapon = weapon_id
	Events.weapon_switched.emit(weapon_id)
	if weapon_id == &"em120r":
		_update_ec120_aim()


func _set_nano_mode(mode: StringName) -> void:
	if mode == &"stealth" and GameState.armor <= 0.0:
		Events.message_posted.emit("护甲能量不足，无法隐形")
		return
	GameState.nano_mode = mode
	Events.nano_mode_changed.emit(mode)
	var labels := {&"normal": "常规", &"armor": "装甲", &"stealth": "隐形"}
	Events.message_posted.emit("模式：%s" % labels.get(mode, "常规"))


func _toggle_armor() -> void:
	_set_nano_mode(&"normal" if GameState.nano_mode == &"armor" else &"armor")


func _toggle_stealth() -> void:
	_set_nano_mode(&"normal" if GameState.nano_mode == &"stealth" else &"stealth")


func _apply_nano_visuals() -> void:
	_visual_nano_mode = GameState.nano_mode
	for mesh in _weapon_mount.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).transparency = 0.82 if GameState.nano_mode == &"stealth" else 0.0


## X：各武器只循环机主配置的射击模式；EM-86M 无点射，EM-40T-1 固定半自动。
func _cycle_fire_mode() -> void:
	var w := GameState.current_weapon
	if w == &"em120r":
		GameState.em120r_guidance_mode = &"homing" if GameState.em120r_guidance_mode == &"laser" else &"laser"
		Events.ec120_guidance_changed.emit(GameState.em120r_guidance_mode)
		return
	if w in [&"g17", &"dmr", &"spas12", &"magnum", &"em86s", &"em86d", &"em127g", &"em40t1"]:
		return
	const ORDER_RIFLE: Array[StringName] = [&"auto", &"semi", &"burst", &"grenade"]
	const ORDER_PISTOL: Array[StringName] = [&"auto", &"burst", &"semi"]
	const ORDER_SHOTGUN: Array[StringName] = [&"semi", &"auto"]
	const ORDER_EM86B: Array[StringName] = [&"burst", &"semi", &"auto", &"grenade"]
	const ORDER_EM57S2: Array[StringName] = [&"auto", &"semi", &"burst"]
	const ORDER_AUTO_SEMI: Array[StringName] = [&"auto", &"semi"]
	var order: Array[StringName] = ORDER_PISTOL
	if w in [&"rifle", &"smg"]:
		order = ORDER_RIFLE
	elif w == &"mpx":
		order = ORDER_PISTOL ## 机主配置：全自动 / 三发点射 / 半自动，无榴弹档。
	elif w in [&"shotgun", &"em12g2"]:
		order = ORDER_SHOTGUN
	elif w == &"em86b":
		order = ORDER_EM86B
	elif w == &"em57s2":
		order = ORDER_EM57S2
	elif w in [&"em86m", &"em127m"]:
		order = ORDER_AUTO_SEMI
	var cur: StringName = GameState.fire_modes.get(w, &"auto")
	GameState.fire_modes[w] = order[(order.find(cur) + 1) % order.size()]
	Events.fire_mode_changed.emit(w, GameState.fire_modes[w])


## N：夜视仪切换占位。白天禁开（§11.2）：白天且当前未开启时直接返回；关闭不限时段。
func _toggle_night_vision() -> void:
	if not GameState.is_night and not GameState.night_vision:
		return
	GameState.night_vision = not GameState.night_vision
	Events.night_vision_toggled.emit(GameState.night_vision)


## F：药包占位——生命值 +MEDKIT_HEAL（不超上限），库存 -1，广播信号。
func _use_medkit() -> void:
	if GameState.medkits <= 0:
		return
	GameState.medkits -= 1
	Events.medkit_used.emit(GameState.medkits)
	GameState.hp = minf(GameState.hp + GameConfig.MEDKIT_HEAL, GameConfig.HEALTH_MAX)
	Events.player_health_changed.emit(&"hp", GameState.hp, GameConfig.HEALTH_MAX)


## 玩家承伤管线（2026-10-21 机主裁决：单一生命值制——先扣护甲能量（任意命中，
## 吸收上限 = 原始伤害 × ARMOR_ABSORB_FACTOR），剩余扣生命值；生命值清零即结算。
## 发射侧（enemy_base._damage_player）的 part 标签不再参与结算。
## 任务结束态（COMPLETED/GAME_OVER）不再承伤。
func _apply_damage(_part: StringName, amount: float) -> void:
	if GameState.mission_phase == GameState.MissionPhase.COMPLETED \
			or GameState.mission_phase == GameState.MissionPhase.GAME_OVER:
		return
	var actual := amount * (GameConfig.NANO_ARMOR_DAMAGE_FACTOR if GameState.nano_mode == &"armor" else 1.0)
	# 受击即打断生命值/护甲回充计时（纳米服式回充）。
	_armor_regen_wait = 0.0
	if GameState.armor > 0.0:
		var armor_absorb := minf(GameState.armor, amount * GameConfig.ARMOR_ABSORB_FACTOR)
		GameState.armor -= armor_absorb
		actual -= armor_absorb
		Events.armor_changed.emit(GameState.armor, GameConfig.ARMOR_MAX)
	GameState.hp = maxf(0.0, GameState.hp - actual)
	Events.player_health_changed.emit(&"hp", GameState.hp, GameConfig.HEALTH_MAX)
	if GameState.hp <= 0.0:
		GameState.mission_phase = GameState.MissionPhase.GAME_OVER
		Events.game_over.emit(&"enemy")


## H：呼叫直升机占位——仅在已解锁时发信号。
func _call_heli() -> void:
	if GameState.heli_unlocked:
		Events.heli_called.emit()


## 开镜准星覆盖层（2026-10-19 机主立项）：青蓝 (0.4,0.95,1.0) 全息风。
## 长枪 = 全息圆环 + 心点 + 四向刻度（榴档共用）；pistol = 点状准星；none = 不画。
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
			&"dmr":
				# 高倍全息镜：青蓝十字边线 + 中央圆圈与瞄点。
				for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					draw_line(center + dir * 28.0, center + dir * maxf(size.x, size.y), color, 1.2, true)
				draw_arc(center, 18.0, 0.0, TAU, 64, color, 1.6, true)
				draw_circle(center, 2.2, color)
			&"em86m":
				var tick_inner: float = size.y * GameConfig.EM86M_RETICLE_TICK_INNER_RATIO
				var tick_outer: float = size.y * GameConfig.EM86M_RETICLE_TICK_OUTER_RATIO
				var ring_radius: float = size.y * GameConfig.EM86M_RETICLE_RING_RADIUS_RATIO
				var dot_radius: float = size.y * GameConfig.EM86M_RETICLE_DOT_RADIUS_RATIO
				var line_width: float = size.y * GameConfig.EM86M_RETICLE_LINE_WIDTH_RATIO
				for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					draw_line(center + dir * tick_inner, center + dir * tick_outer, color, line_width, true)
				draw_arc(center, ring_radius, 0.0, TAU, 64, color, line_width, true)
				draw_circle(center, dot_radius, color)
			&"em57s2":
				draw_arc(center, 10.0, 0.0, TAU, 64, color, 1.4, true)
				draw_circle(center, 1.3, color)
				for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					draw_line(center + dir * 12.0, center + dir * 15.0, color, 1.4, true)
			&"em86b":
				# 镜筒内局部准星：短十字不穿入空心圆，中央保留瞄点。
				for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					draw_line(center + dir * 28.0, center + dir * 48.0, color, 1.2, true)
				draw_arc(center, 18.0, 0.0, TAU, 64, color, 1.6, true)
				draw_circle(center, 2.2, color)
			&"rifle", &"shotgun", &"smg", &"lmg", &"mpx":
				# 全息环：外环 + 心点 + 四向短刻度
				draw_arc(center, 22.0, 0.0, TAU, 64, color, 1.6, true)
				draw_circle(center, 2.2, color)
				for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					draw_line(center + dir * 26.0, center + dir * 31.0, color, 1.6, true)
			&"pistol", &"magnum":
				# 点状准星：心点 + 微光晕圈
				draw_arc(center, 5.0, 0.0, TAU, 32, Color(color, alpha * 0.45), 1.2, true)
				draw_circle(center, 2.0, color)
