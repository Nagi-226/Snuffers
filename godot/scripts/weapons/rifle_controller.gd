## RifleController — 步枪 hitscan（W2 火力蜂）
##
## 参数基准（§7 对照表 G2 行；2026-10-22 机主裁决伤害改按弹药口径）：75/爆头150 伤害（EC-68 步枪弹）· 800RPM 连发档 · 60/600 弹药 ·
## 2s 换弹 · 三档散布（腰射 0.004 / 趴 0.002 / 瞄 0.0005，瞄准优先，index.html L2966-2967）·
## 后坐每发 +0.003 rad 带相机恢复（修正网页版永久上跳缺陷）。
##
## 解耦：
## - 伤害结算：射线命中 → HitSolver 鸭子探测 take_damage，禁止引用 enemies 域节点；
##   take_damage 保留为投递机制，随后发 Events.damage_dealt(amount, is_headshot)
##   供 HUD 伤害飘字消费（G2 冻结信号，与 hit_confirmed 互补）。
## - 命中反馈：Events.hit_confirmed(is_headshot)（契约已有，HUD 准星 1.3×/1.8× 由 W5 消费）。
## - 碉堡跳弹：Events.ricochet_on_bunker()（契约已有）。
##
## 换弹责任划分（蜂后裁决：换弹归武器域自足，W1 已移除 player_controller 占位分发）：
## R 键监听在本脚本 _unhandled_input（门控与基类左键开火同款），
## 本脚本监听 Events.weapon_reload_started/reloaded 做状态封锁与弹药结算；
## 弹尽自动换弹（网页版 L2954）与 R 键手动换弹共用 _start_reload，两条路径信号序列一致。
extends WeaponController

## 射击模式机制已上收基类（2026-10-19：半自动/三发点射/全自动三档，X 键切换）；
## 本子类只保留弹药结算、散布射线与换弹三件套。
var _is_reloading: bool = false
var _reload_generation: int = 0

# Cransh 原生手臂与动画；EM 枪身和弹匣共享原生武器骨，不再跨手臂重定向。
@onready var _magazine: Node3D = get_node_or_null("ViewModel/EM68A/em68a_magazine")
@onready var _weapon_node: Node3D = $ViewModel/EM68A
@onready var _arms_node: Node3D = $ViewModel/ArmsEM68A
var _mag_home_transform: Transform3D = Transform3D.IDENTITY
var _weapon_home: Transform3D = Transform3D.IDENTITY
var _arms_animation: AnimationPlayer = null
var _arms_skeleton: Skeleton3D = null
var _mag_bone: int = -1
var _weapon_bone: int = -1
var _mag_motion_start: Transform3D = Transform3D.IDENTITY
var _weapon_motion_start: Transform3D = Transform3D.IDENTITY
# 左臂主流姿势的腰射/ADS 目标插值权重（本地平滑，与 player_controller 的 ADS
# 挂载插值同款节奏；is_aiming 布尔读契约，无新参数）。
var _aim_weight: float = 0.0
# 主流FPS持枪基座姿态（2026-10-24 机主指令：大量参考截图反复修正）：
# 参考共识（机主腰射参考图+塔科夫ADS实测）——枪口 54-68%W/57-58%H 指向画面
# 中心、枪身横贯下缘而非陡立右侧、左手 35-47%W/75-80%H。现状实测枪尾→枪口
# 连线约 72° 陡立、枪口 75%W/63%H 偏右。旋转施加在 ViewModel 两子节点上
# （EM68A/ArmsEM68A 场景同位同原点，同旋转即枪臂联动；基类后坐独占 ViewModel
# 旋转不能放父节点）。开镜时随 _aim_weight 回正归零——瞄具轴重新平行相机轴，
# player_controller 的 ADS 平移归中逻辑零改动。
const HIP_POSE_YAW := 0.26
const HIP_POSE_PITCH := 0.05
# 换弹净侧倾上限（2026-10-25 机主路线A裁决）：Cransh 剪辑把枪滚到近 80°（骨
# 空间 44-51°），主流有托步枪换弹只倾 15-30°（CoD/BF 参考）。超出部分整套
# 枪+臂组件反向滚转抵消（走 _pose_extra 通道，motion 公式自动剥离，粘合不破）。
const RELOAD_MAX_CANT := deg_to_rad(22.0)
var _pose_extra: Transform3D = Transform3D.IDENTITY
var _arms_placed: Transform3D = Transform3D.IDENTITY
var _reload_counter: float = 0.0
# 基座旋转与左臂姿势推迟到首个 _process 帧施加：player_controller._ready 的
# ADS 标定在子节点就绪后跑，必须量到未旋转（=开镜态）的瞄具位——否则按腰射
# 旋转态标定，开镜旋转回正后枪身整体偏左（2026-10-24 机主实机指认）。
var _pose_pending: bool = false
# 左臂链实测骨长（就绪时 Run 姿势采样；两骨 IK 求解用）。
var _arm_upper_len: float = 0.0
var _arm_fore_len: float = 0.0


func _ready() -> void:
	super()
	if _magazine != null:
		_mag_home_transform = _magazine.transform
	_weapon_home = _weapon_node.transform
	var players := $ViewModel/ArmsEM68A.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_arms_animation = players[0] as AnimationPlayer
		_prepare_native_reload("Armature|Arms_FPS_Anim_Reload_Fast")
		_prepare_native_hold("Armature|Arms_FPS_Anim_Run")
	var skeletons := $ViewModel/ArmsEM68A.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_arms_skeleton = skeletons[0] as Skeleton3D
		_mag_bone = _arms_skeleton.find_bone("Pmag_061")
		_weapon_bone = _arms_skeleton.find_bone("ACRRifle_058")
		_align_native_arms()
		_arms_placed = _arms_node.transform
		_measure_left_arm()
		# 基座旋转/姿势不在 _ready 施加（见 _pose_pending 注释）；motion 起点
		# 在未旋转状态采样，_process 公式的 E⁻¹ 修正保证同基一致。
		_pose_pending = true
		if _weapon_bone >= 0:
			_weapon_motion_start = _weapon_motion()
		if _magazine != null and _mag_bone >= 0:
			_mag_motion_start = _magazine_motion()
		Events.weapon_reload_started.connect(_on_reload_started)
	Events.weapon_reloaded.connect(_on_weapon_reloaded)


func _prepare_native_reload(clip: StringName) -> void:
	var animation := _arms_animation.get_animation(clip).duplicate() as Animation
	var source_length := animation.length
	for track in animation.get_track_count():
		for key in animation.track_get_key_count(track):
			animation.track_set_key_time(track, key,
				animation.track_get_key_time(track, key) * weapon_data.reload_time / source_length)
	animation.length = weapon_data.reload_time
	_arms_animation.get_animation_library("").add_animation(&"reload", animation)
	_arms_animation.play(&"reload")
	_arms_animation.advance(0.0)
	_arms_animation.stop()


## 常态保持姿势：Run 剪辑第 0 帧定格。作者的全部持枪族姿势（Idle/Shoot/Walk/
## Draw 末帧/Reload 首帧）左手都架在机匣上方 +0.15m（风格化高位托枪），遮挡
## EM-68A 瞄具视线（2026-10-24 机主实机反馈）；Run 第 0 帧是唯一左手低位
## （y≈+0.04，护木下方）的姿势，定格作持枪位。
func _prepare_native_hold(clip: StringName) -> void:
	var animation := _arms_animation.get_animation(clip).duplicate() as Animation
	_arms_animation.get_animation_library("").add_animation(&"hold", animation)
	_arms_animation.play(&"hold")
	_arms_animation.seek(0.0, true)
	_arms_animation.pause()


## 腰射基座旋转随 _aim_weight 收放：1=腰射全姿态，0=开镜回正（瞄具轴平行
## 相机轴，挂载平移归中保持 player_controller 原逻辑）。两子节点同源点同旋转。
## 换弹期间叠加 _reload_counter 反向滚转（绕视线轴，见 RELOAD_MAX_CANT）。
func _apply_pose_rotation() -> void:
	var w := 1.0 - _aim_weight
	var q := Quaternion(Vector3.UP, HIP_POSE_YAW * w) \
		* Quaternion(Vector3.RIGHT, HIP_POSE_PITCH * w) \
		* Quaternion(Vector3.BACK, _reload_counter)
	_pose_extra = Transform3D(Basis(q), Vector3.ZERO)
	_arms_node.transform = _pose_extra * _arms_placed
	_weapon_node.transform = _pose_extra * _weapon_home


## 换弹剪辑当前枪身绕视线轴的带符号滚转（E 已剥离的 motion 增量空间，
## hold 基线为 0）。超出主流上限的角度即反向滚转量：净侧倾=剪辑滚转被
## 截到 ±RELOAD_MAX_CANT，剪辑自身的缓入缓出形状保留。
func _reload_cant_counter() -> float:
	if _weapon_bone < 0:
		return 0.0
	var delta: Transform3D = _weapon_motion_start.affine_inverse() * _weapon_motion()
	var q := delta.basis.get_rotation_quaternion()
	if q.get_angle() < 0.01:
		return 0.0
	var roll := q.get_angle() * signf(q.get_axis().z)
	return roll - clampf(roll, -RELOAD_MAX_CANT, RELOAD_MAX_CANT)


## 主流FPS左臂姿势（机主参考图 2026-10-24：左手托护木、前臂近垂直伸入、肘出画）。
## v1 版（e979f81/6f4540e）三处结构性缺陷（骨架探针实测，2026-10-24 找茬复核）：
## ① 前臂唯一子骨 BoneTwist_03.L 与前臂原点共位（零向量尖端）→ 前臂旋转失效；
## ② 肩钉死 Run 原位（肩→腕目标 635mm > 臂展 ~420mm）→ 链够不着；
## ③ 手（IK 独立子树）被平移到不可达目标 → 距前臂尖端 462mm 悬浮断腕；
## 另手保持 Run 朝向致指尖指枪尾（与枪口差 85°）。
## v2 版：肩锚从腕目标沿「正下偏后」退 0.94×臂展（肘弯自然、肩在画面外下方），
## 余弦定理两骨 IK（肘距肩=上臂长、腕距肘=前臂长恒成立）+ 骨轴约定实测
## （本骨架骨轴=basis.y，肩→肘夹角 0.00001°）→ 链端与腕目标数学重合，
## 手定位链端闭合腕缝，掌向旋至指尖朝枪口。play/seek 重置骨骼，须在每次
## hold 应用后调用。
func _pose_left_arm_mainstream(weight: float = 0.0) -> void:
	# 幂等重放：seek 回 hold 第 0 帧清掉上次改写，再按当前插值目标重写。
	_arms_animation.seek(0.0, true)
	var uparm := _find_bone_by_prefix("UpArm_L")
	var fore := _find_bone_by_prefix("Forearm_L")
	var ctrl := _find_bone_by_prefix("IK_Hand_Cntrl_L")
	var hand := _find_bone_by_prefix("Hand_L")
	if uparm < 0 or fore < 0 or ctrl < 0 or hand < 0 or _arm_upper_len <= 0.0 or _arm_fore_len <= 0.0:
		push_warning("左臂链骨骼/臂长未就绪，主流姿势改写跳过")
		return
	var to_skel_from_weapon: Transform3D = _arms_skeleton.global_transform.affine_inverse() * _weapon_node.global_transform
	# 腕目标（武器局部系，坐标来自 EM68A 网格实测 AABB）：护木下表面=下挂榴弹
	# 模块 gl_module（x±0.046，底面 y=-0.044，z -0.43[筒口]~-0.11[尾]）。腰射——
	# 掌心贴榴弹筒左下缘、四指朝枪口包握；z 取 -0.17（筒身后段：2026-10-24 机主
	# 两轮指正——手须碰到枪身，且 v17 前段位 z-0.26 挡筒口，后撤）；ADS——保持
	# 机主已验收位（弹匣井前下）。
	var wrist_t := to_skel_from_weapon * Vector3(-0.05, -0.045, -0.17).lerp(Vector3(-0.05, -0.10, -0.16), weight)
	# 肩锚与极向量（武器局部偏移转骨架系）：肩从腕沿正下偏后退臂展 94%；
	# 极向量把肘压向腕下方偏后——上臂/袖管沉画面外，不穿枪身。
	var shoulder_t := wrist_t + to_skel_from_weapon.basis * (Vector3(0.03, -0.36, 0.14).normalized() * (_arm_upper_len + _arm_fore_len) * 0.94)
	var pole_t := wrist_t + to_skel_from_weapon.basis * Vector3(0.08, -0.35, 0.22)
	# 两骨 IK（余弦定理）。
	var d := wrist_t - shoulder_t
	var dist := clampf(d.length(), absf(_arm_upper_len - _arm_fore_len) + 0.001, _arm_upper_len + _arm_fore_len - 0.001)
	d = d.normalized()
	var a := (_arm_upper_len * _arm_upper_len - _arm_fore_len * _arm_fore_len + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(0.0, _arm_upper_len * _arm_upper_len - a * a))
	var pole_off := pole_t - shoulder_t
	pole_off -= d * pole_off.dot(d)
	pole_off = pole_off / maxf(pole_off.length(), 0.0001)
	var elbow_t := shoulder_t + d * a + pole_off * h
	# FK 施加：上臂先平移到肩锚（子骨随动），再转 Y 轴指肘；前臂 Y 转指腕。
	var up_g := _arms_skeleton.get_bone_global_pose(uparm)
	_arms_skeleton.set_bone_global_pose(uparm, Transform3D(up_g.basis, shoulder_t))
	_aim_bone_y_at(uparm, elbow_t)
	_aim_bone_y_at(fore, wrist_t)
	# 手（IK 独立子树）：定位到链端闭合腕关节（数学上=腕目标）。
	var fore_g := _arms_skeleton.get_bone_global_pose(fore)
	var wrist_end := fore_g.origin + fore_g.basis.y * _arm_fore_len
	var ctrl_g := _arms_skeleton.get_bone_global_pose(ctrl)
	_arms_skeleton.set_bone_global_pose(ctrl, Transform3D(ctrl_g.basis, wrist_end))
	# 掌向：Run 朝向指尖指枪尾，旋至沿枪口方向（主流托握指尖朝枪口）。
	var hand_g := _arms_skeleton.get_bone_global_pose(hand)
	var muzzle_dir := to_skel_from_weapon.basis * Vector3(0.0, 0.0, -1.0)
	var palm_rot := Quaternion(hand_g.basis.y, muzzle_dir)
	_arms_skeleton.set_bone_global_pose(hand, Transform3D(Basis(palm_rot) * hand_g.basis, hand_g.origin))


## 骨架里按名字前缀找骨（导出后缀漂移：BoneTwist_03.L_05 等），找不到返回 -1。
func _find_bone_by_prefix(prefix: String) -> int:
	for b in _arms_skeleton.get_bone_count():
		if _arms_skeleton.get_bone_name(b).begins_with(prefix):
			return b
	return -1


## 就绪时从 Run 姿势实测左臂两段骨长（腕在作者姿势下与前臂末端对齐）。
func _measure_left_arm() -> void:
	var uparm := _find_bone_by_prefix("UpArm_L")
	var fore := _find_bone_by_prefix("Forearm_L")
	var hand := _find_bone_by_prefix("Hand_L")
	if uparm < 0 or fore < 0 or hand < 0:
		return
	var g_u := _arms_skeleton.get_bone_global_pose(uparm).origin
	var g_f := _arms_skeleton.get_bone_global_pose(fore).origin
	var g_h := _arms_skeleton.get_bone_global_pose(hand).origin
	_arm_upper_len = g_u.distance_to(g_f)
	_arm_fore_len = g_f.distance_to(g_h)
	print("LEFT_ARM_LEN upper=", _arm_upper_len, " fore=", _arm_fore_len)


## 把 bone 的骨轴（basis.y，本骨架实测骨轴约定）旋到指向 target_pos（骨架系），
## 最小弧、保扭转。
func _aim_bone_y_at(bone: int, target_pos: Vector3) -> void:
	var g := _arms_skeleton.get_bone_global_pose(bone)
	var rot := Quaternion(g.basis.y, (target_pos - g.origin).normalized())
	_arms_skeleton.set_bone_global_pose(bone, Transform3D(Basis(rot) * g.basis, g.origin))


func _align_native_arms() -> void:
	# 位置无关解算：S_new × 弹匣骨局部位 = 弹匣世界位（旋转按武器骨、平移按弹匣骨），
	# 骨位取骨架局部 get_bone_global_pose（与 Armature 摆在世界何处无关）。
	# 装备组武器骨系与 EM 约定差 Y 轴 180°（枪尾/枪口与左右互反，2026-10-24 机主实机
	# 目验「持枪手臂前后搞反」；24 候选旋转暴力验证唯一几何合理解），R 矩阵插在武器
	# 旋转与骨位逆之间。旧实现把世界坐标骨位混入旋转乘法，仅在武器接近世界原点时碰巧正确——真机
	# 出生点 z≈29.6，z 经置换基泄漏进 y，臂组装被摔进地下 14m（常态隐形根因）。
	var chain: Transform3D = $ViewModel/ArmsEM68A.global_transform.affine_inverse() * _arms_skeleton.global_transform
	var weapon_bone_local := _arms_skeleton.get_bone_global_pose(_weapon_bone)
	var mag_bone_local := _arms_skeleton.get_bone_global_pose(_mag_bone)
	var basis := _weapon_node.global_basis.orthonormalized() * Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)) * weapon_bone_local.basis.orthonormalized().inverse()
	var origin := _magazine.global_position - basis * mag_bone_local.origin
	print("NATIVE_ALIGN2 rifle basis=", basis, " origin=", origin)
	# 握持微调（2026-10-24 机主手感迭代）：Run 持枪姿势左手横伸，前臂斜穿画面
	# 中部（机主反馈「高、过于靠前」）——整套臂组装沿武器局部系下沉+后移收回右下角。
	var placed: Transform3D = Transform3D(basis, origin) * chain.affine_inverse()
	var weapon_basis := _weapon_node.global_basis
	placed.origin += weapon_basis * Vector3(0, -0.02, 0.07)
	$ViewModel/ArmsEM68A.global_transform = placed
	# 手臂蒙皮网格按 mesh 资源名保留（两枪均为 arms_arms_0）；节点名不可靠——
	# 步枪手臂网格是 Object_10、手枪是 Object_9，两次导出的 Object_N 编号漂移过。
	# 隐藏对象是 Cransh 自带的枪械渲染件（枪身/消音/镜/弹匣），实机用 EM68A 真模。
	for node in $ViewModel/ArmsEM68A.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null or not mesh.resource_name.contains("arms"):
			(node as MeshInstance3D).visible = false


func _process(delta: float) -> void:
	super._process(delta)
	# 常态与换弹均由武器骨驱动枪身（idle 微摆与换弹动效同一套相对运动公式）。
	if _arms_skeleton == null:
		return
	# 首帧补施基座旋转与左臂姿势（_ready 里让位给 ADS 标定，见 _pose_pending）。
	if _pose_pending:
		_pose_pending = false
		_apply_pose_rotation()
		_pose_left_arm_mainstream(_aim_weight)
	# 左臂姿势与基座姿态随 ADS 平滑收放（换弹期间臂归剪辑所有，不重摆）。
	if not _is_reloading and _arms_animation != null and _arms_animation.has_animation(&"hold"):
		var aim_target := 1.0 if GameState.is_aiming else 0.0
		if not is_equal_approx(_aim_weight, aim_target):
			_aim_weight = move_toward(_aim_weight, aim_target, delta * 4.0)
			_apply_pose_rotation()
			_pose_left_arm_mainstream(_aim_weight)
	elif _is_reloading:
		# 换弹反向滚转逐帧跟踪剪辑滚转（净侧倾截到主流上限）。
		var counter := _reload_cant_counter()
		if not is_equal_approx(counter, _reload_counter):
			_reload_counter = counter
			_apply_pose_rotation()
	if _weapon_bone >= 0:
		_weapon_node.transform = _pose_extra * _weapon_home * _weapon_motion_start.affine_inverse() * _weapon_motion()
	if _magazine != null and _mag_bone >= 0:
		_magazine.transform = _mag_home_transform * _mag_motion_start.affine_inverse() * _magazine_motion()


func _weapon_motion() -> Transform3D:
	# 基座姿态旋转因子从骨架全局位中剥除（E 在两子节点上，motion 保持
	# 「未旋转装配空间」，与就绪时采样的 start 同基；否则旋转被算两次）。
	var raw: Transform3D = _view_model.global_transform.affine_inverse() * _arms_skeleton.global_transform * _arms_skeleton.get_bone_global_pose(_weapon_bone)
	return _pose_extra.affine_inverse() * raw


func _magazine_motion() -> Transform3D:
	var raw: Transform3D = _magazine.get_parent().global_transform.affine_inverse() * _arms_skeleton.global_transform * _arms_skeleton.get_bone_global_pose(_mag_bone)
	return _pose_extra.affine_inverse() * raw


func _exit_tree() -> void:
	Events.weapon_reload_started.disconnect(_on_reload_started)
	Events.weapon_reloaded.disconnect(_on_weapon_reloaded)
	super()


## R 键换弹监听：门控与基类左键开火同款——仅鼠标捕获态 + 当前手持武器响应。
## RPG 无换弹概念，故监听放本子类而非基类。
func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.keycode != KEY_R or not key.pressed or key.echo:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not _is_current_weapon():
		return
	_start_reload()


## 全自动/点射 tick 已收口基类（_tick_weapon）；本子类仅实现单发流程。


## 单发流程：榴档分流投射物；否则弹药门控 → 扣弹广播 → 后坐 → 散布射线 → 命中结算。
## 返回是否真正击发。
func _fire() -> bool:
	if _current_fire_mode() == &"grenade":
		return _fire_grenade()
	if _is_reloading:
		return false
	if GameState.rifle_mag <= 0:
		# 网页版弹尽自动换弹（index.html L2954）。
		_start_reload()
		return false

	GameState.rifle_mag -= 1
	Events.ammo_changed.emit(&"rifle", GameState.rifle_mag, GameState.rifle_reserve)
	Events.weapon_fired.emit(&"rifle")
	# 微弱青蓝枪口焰（2026-10-19 机主立项）：炮口近似位 = 武器原点沿 -Z 前移 PLAYER_MUZZLE_OFFSET。
	Events.player_muzzle_flash.emit(&"rifle",
		global_position + (-global_transform.basis.z) * GameConfig.PLAYER_MUZZLE_OFFSET)
	_apply_recoil()

	var hit := _cast_spread_ray()
	if hit.is_empty():
		return true
	var collider: Object = hit.collider

	# 碉堡跳弹：提示需用火箭筒（index.html L2973-2980）；碉体为金属，附带火星+弹痕。
	if HitSolver.find_group_ancestor(collider, &"bunker") != null:
		Events.bullet_impacted.emit(hit.position, hit.normal, true)
		Events.ricochet_on_bunker.emit()
		return true

	var target := HitSolver.find_damageable(collider)
	if target == null:
		# 命中环境（墙/地/金属物件）：弹坑贴花；金属表面加溅射火星（2026-10-19 机主立项）。
		Events.bullet_impacted.emit(hit.position, hit.normal, HitSolver.is_metal_surface(collider))
		return true

	var is_head := HitSolver.is_headshot(collider)
	var damage: float = weapon_data.damage_body * (weapon_data.headshot_factor if is_head else 1.0)
	# 狙击手固定伤害（index.html L3014：网页版不分部位一律 999）。
	if HitSolver.find_group_ancestor(collider, &"sniper") != null:
		damage = weapon_data.dmg_vs_sniper
	target.take_damage(damage, is_head)
	# G2 冻结契约：HUD 伤害飘字（与 hit_confirmed 互补；狙击手固定伤害如实广播）。
	Events.damage_dealt.emit(damage, is_head)
	Events.hit_confirmed.emit(is_head)
	return true


## 榴档单发（EM-40G「滚雷」，2026-10-22 机主裁决并入第四射击档）：
## 模块 6 发弹匣=雷池（GameState.rifle_grenades 总数制，无换弹）；投射物复用
## rpg_projectile 链路（直射档参数：GRENADE_* 契约组，平直弹道微下坠）。
## 「闸不合，榴不发」——本路径只在 &"grenade" 档下可达，实弹击发互斥。
func _fire_grenade() -> bool:
	if _is_reloading:
		return false
	if GameState.rifle_grenades <= 0:
		Events.message_posted.emit("滚雷模块弹药耗尽")
		return false
	if weapon_data.projectile_scene == null:
		push_error("rifle.tres 未配置 projectile_scene（EM-40G 投射物）")
		return false
	GameState.rifle_grenades -= 1
	Events.ammo_changed.emit(&"rifle", GameState.rifle_grenades, -1)
	Events.weapon_fired.emit(&"grenade")
	_apply_recoil()
	var projectile: Node3D = weapon_data.projectile_scene.instantiate()
	# 投射物挂到关卡根（武器随玩家移动，投射物需独立存在于世界空间）。
	var container: Node = get_tree().current_scene
	if container == null:
		container = get_tree().root
	container.add_child(projectile)
	# 出膛点 = 武器原点 前移 GRENADE_LAUNCH_FORWARD + 下移 GRENADE_LAUNCH_DROP
	# （下挂发射管位于护木前下方；方向仍取相机 -Z 保证准星所指即弹道所向）。
	var launch_xform := global_transform
	launch_xform.origin += (-global_transform.basis.z) * GameConfig.GRENADE_LAUNCH_FORWARD \
		+ Vector3.DOWN * GameConfig.GRENADE_LAUNCH_DROP
	projectile.global_transform = launch_xform
	projectile.setup(
		-global_transform.basis.z,
		HitSolver.collect_owner_rids(self),
		weapon_data
	)
	return true


## 散布射线：从武器原点（挂 WeaponMount，即炮口）沿 -Z，
## 局部空间角偏移近似网页版 NDC 散布（数值沿用 §7 对照表）。
func _cast_spread_ray() -> Dictionary:
	var spread := _current_spread()
	var local_dir := Vector3(
		randf_range(-spread, spread),
		randf_range(-spread, spread),
		-1.0
	).normalized()
	var from := global_position
	var to: Vector3 = from + (global_transform.basis * local_dir) * weapon_data.hitscan_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = HitSolver.collect_owner_rids(self)
	query.collide_with_areas = true
	return get_world_3d().direct_space_state.intersect_ray(query)


## 三档散布：瞄准 > 趴下 > 腰射（index.html L2966-2967）。
func _current_spread() -> float:
	if GameState.is_aiming:
		return weapon_data.spread_aim
	if GameState.is_prone:
		return weapon_data.spread_prone
	return weapon_data.spread_hip


## 换弹启动（R 键手动 / 弹尽自动共用）：自发 started →（reload_time）→ reloaded 信号序列。
## 守卫：换弹中 / 无备弹 / 弹匣已满时不触发。
func _start_reload() -> void:
	if _is_reloading or GameState.rifle_reserve <= 0:
		return
	if GameState.rifle_mag >= weapon_data.mag_size:
		return
	_reload_generation += 1
	var generation := _reload_generation
	Events.weapon_reload_started.emit(&"rifle")
	await get_tree().create_timer(weapon_data.reload_time).timeout
	if not is_instance_valid(self) or generation != _reload_generation:
		return
	Events.weapon_reloaded.emit(&"rifle")


func _on_reload_started(weapon_id: StringName) -> void:
	if weapon_id == &"rifle":
		_is_reloading = true
		_play_reload_anim()


func _play_reload_anim() -> void:
	_set_sleeve_extenders_visible(false)
	if _magazine != null:
		_magazine.transform = _mag_home_transform
	# 运动基准必须在 play 之前的 hold 态采样：换弹期间枪身/弹匣跟随剪辑
	# 【全量】运动（含 ~44° 战术侧倾——作者为原生枪 author 的换弹姿态，主流
	# 有托步枪换弹同款：侧倾露弹匣井→抽匣→取新匣→插回），双手-枪-弹匣保持
	# 粘合。旧版在 play+advance(0) 后按剪辑第 0 帧重采样——枪身被钉回原地只
	# 残留 ±7° 抖动，双手却按剪辑去操作那把「侧倾 44° 的枪」→ 弹匣悬空漂浮、
	# 左手抓空气（2026-10-25 机主定性「混乱脱节」，probe_reload_anim 实证：
	# 枪骨相对 hold 恒偏 44-51°/110mm，0.9s 相位弹匣孤悬枪右下、手指张开无握持）。
	if _arms_skeleton != null and _mag_bone >= 0:
		_mag_motion_start = _magazine_motion()
	if _arms_skeleton != null and _weapon_bone >= 0:
		_weapon_motion_start = _weapon_motion()
	if _arms_animation != null and _arms_animation.has_animation(&"reload"):
		_arms_animation.play(&"reload", 0.15)
		_arms_animation.advance(0.0)


func _on_weapon_switched(weapon_id: StringName) -> void:
	super._on_weapon_switched(weapon_id)
	if weapon_id != weapon_data.weapon_id:
		_is_reloading = false
		_reload_generation += 1
	_reset_reload_visuals()


func _reset_reload_visuals() -> void:
	_reload_counter = 0.0
	if _magazine != null:
		_magazine.transform = _mag_home_transform
		_magazine.visible = true
	if _arms_animation != null and _arms_animation.has_animation(&"hold"):
		_arms_animation.play(&"hold")
		_arms_animation.seek(0.0, true)
		_arms_animation.pause()
	_apply_pose_rotation()
	if _arms_animation != null and _arms_animation.has_animation(&"hold"):
		_pose_left_arm_mainstream(_aim_weight)
	if _arms_skeleton != null and _weapon_bone >= 0:
		_weapon_motion_start = _weapon_motion()
	if _magazine != null and _mag_bone >= 0:
		_mag_motion_start = _magazine_motion()
	_set_sleeve_extenders_visible(true)


func _set_sleeve_extenders_visible(value: bool) -> void:
	for sleeve in $ViewModel/ArmsEM68A.find_children("sleeve_ext_*", "Node3D", true, false):
		(sleeve as Node3D).visible = value


## 换弹完成：标准弹药迁移（弹匣缺口 ← 备弹），广播 ammo_changed。
func _on_weapon_reloaded(weapon_id: StringName) -> void:
	if weapon_id != &"rifle":
		return
	_reset_reload_visuals()
	_is_reloading = false
	var need: int = weapon_data.mag_size - GameState.rifle_mag
	var take: int = mini(need, GameState.rifle_reserve)
	GameState.rifle_mag += take
	GameState.rifle_reserve -= take
	Events.ammo_changed.emit(&"rifle", GameState.rifle_mag, GameState.rifle_reserve)
