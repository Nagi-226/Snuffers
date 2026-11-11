## GameConfig — 全部可调参数的单一事实源（Autoload 单例）
##
## AGENTS.md 约束 #2：禁止在业务脚本里硬编码手感参数，一律引用本文件。
## 数值来源：desktop-port/godot-spike/00-spike-plan.md §7 手感参数对照表，
## 由调研代理从 index.html 逐行提取；注释中 Lxxxx 为网页版行号出处。
## 修改任何对应参数必须同步更新对照表并说明理由（约束 #6）。
extends Node

# ===== 玩家移动（G1 门禁基准）=====
const SPEED_STAND: float = 4.5 ## 站立移速 u/s（0.15×0.5×60，L3432/L3244）
const SPEED_AIM: float = 1.5 ## 瞄准移速 u/s（0.05×0.5×60，L3432）
const SPEED_SPRINT: float = 6.75 ## 疾跑移速 u/s = 站立×1.5（2026-10-19 机主立项：W+左 Shift；网页版无对应项，Godot 版新增）
const SPEED_PRONE: float = 0.72 ## 趴下移速 u/s（0.08×0.15×60，L3432/L3239）
# （LEG_INJURED_FACTOR / LEG_CRITICAL_FACTOR / LEG_INJURED_THRESHOLD 随 2026-10-21
#  三部位耐久制取消一并退役——腿部受伤减速机制不再存在。）

const MOUSE_SENS_BASE: float = 0.002 ## 视角系数 movement×0.002×sens（L2815）
const AIM_SENS_FACTOR: float = 0.3 ## 开镜灵敏度倍率（L2814）
const PITCH_CLAMP: float = 1.2 ## 俯仰 ±rad（L2817）
var view_sensitivity: float = 2.0 ## 设置滑条 0.3–5.0，默认 2.0（L326/L255）

const CAM_HEIGHT_STAND: float = 1.65 ## 站立相机高（2026-10-18 机主裁决：2.0→1.65，原值对 2.1-2.3m 门洞视觉上像 2.5m 巨人；1.65 为真人站姿眼高）
const CAM_HEIGHT_PRONE: float = 0.5 ## 趴下相机高（L2695）
const CAM_HEIGHT_LERP_TIME: float = 0.15 ## 趴下过渡 150ms（有意改进：网页版瞬切，L2695）

const JUMP_VELOCITY: float = 4.5 ## 跳跃初速 u/s（空格；2026-10-18 机主立项：g=9.8 下跳高约 1.03m，可上路缘/矮台）
const NANO_POWER_SPEED: float = 16.67 ## 力量模式疾跑约 60km/h
const NANO_POWER_JUMP_VELOCITY: float = 11.3 ## 力量模式跳跃高度约 6.5m
const NANO_ARMOR_DAMAGE_FACTOR: float = 0.35 ## 护甲模式承伤系数
const NANO_AWARENESS_GAIN: float = 0.45 ## 敌人看见玩家时察觉度增长/s
const NANO_AWARENESS_DECAY: float = 0.22 ## 未看见玩家时察觉度下降/s
const NANO_STEALTH_WALK_DRAIN_PER_SEC: float = 12.0 ## 隐形普通步行能量消耗/s
const NANO_STEALTH_SPRINT_DRAIN_PER_SEC: float = 24.0 ## 隐形力量疾跑总能量消耗/s
const NANO_POWER_SPRINT_DRAIN_PER_SEC: float = 8.0 ## 常规/装甲下力量疾跑能量消耗/s
const NANO_POWER_JUMP_COST: float = 15.0 ## 强力跳跃单次能量消耗
const NANO_POWER_JUMP_HOLD_TIME: float = 1.0 ## 空格长按强力跳阈值 s，短按普通跳
const STEP_MAX_HEIGHT: float = 0.35 ## 自动上台阶最大高度 m（2026-10-18 机主立项：路缘 0.145/门槛/阳台板 0.14 免跳直上；>0.35 的墙仍需跳或绕）
const INTERACT_RANGE: float = 2.4 ## E 键通用交互距离 m（2026-10-18 机主立项：开门等；准星射线命中才生效）
const NV_SFX_CUT_TIME: float = 0.85 ## 夜视开关音效截短时长 s（2026-10-18 机主裁决：原音源偏长，播到此时长后 0.12s 淡出截停）

const FOV_BASE: float = 75.0 ## 主相机 FOV（L465）
# —— 按住开镜（ADS，2026-10-19 机主立项：右键由「切换潜行观感」改为按住开镜）——
const RIFLE_ADS_FOV: float = 60.0 ## EM-68A 全息瞄具开镜 FOV（全息=低倍率，微收窄）
const PISTOL_ADS_FOV: float = 65.0 ## EM-57P 点状瞄具开镜 FOV
const DMR_ADS_FOV: float = 35.0 ## EM-68D 精确射手瞄具开镜 FOV
const DMR_SCOPE_REFRESH_INTERVAL: float = 1.0 / 30.0 ## 测距/遮挡查询频率 s；投影绘制仍逐帧
const DMR_SCOPE_MAX_TARGETS: int = 6 ## 同屏蓝框上限，按离准星距离优先
const DMR_SCOPE_ACQUIRE_TIME: float = 0.15 ## Target Finder 式蓝框出现扫描过渡 s
const DMR_SCOPE_MIL_STEPS: Array[int] = [50, 100, 150, 200] ## 大镜圈角度刻度；当前 hitscan 无下坠补偿
const SHOTGUN_ADS_FOV: float = 60.0 ## EM-12G-1 低倍率瞄具开镜 FOV
const ADS_LERP_TIME: float = 0.12 ## 开镜/关镜过渡时长 s（挂载位移与 FOV 同步插值）
const ADS_RIFLE_OPTIC_BORE_LOCAL := Vector3(0.00092, 0.18047, -0.0204) ## EM-68A 镜孔轴心（网格局部空间，Blender 实测，轴系已换算 glTF；2026-10-19 开窗手术配套）
const ADS_PISTOL_OPTIC_WINDOW_LIFT: float = 0.15 ## 手枪瞄窗自 AABB 中心上移比例（EM-57P 维持原标定）

const WORLD_BOUND_X: float = 98.0 ## 活动范围 x（L3438）
const WORLD_BOUND_Z: float = 100.0 ## 活动范围 z（2026-10-23 机主裁决：58→100——58 是网页版灰盒残留钳制，
## 在街景图形成力场幕墙前的「空气墙」（南场 z=68/北场 z=-95 永远无法走近）。放宽到幕墙之外，
## 由幕墙实体碰撞做真实拦截；玩家/寄生体共用此钳制（player_controller/infantry 同口径）
const DISTRICT_B_WORLD_BOUNDS := Vector2(228.0, 158.0) ## 第二关 460×320m 庭院，实体围墙前留 1m 余量
const PLAYER_RADIUS: float = 0.4 ## 碰撞半径（L3388）
const PLAYER_HEIGHT_STAND: float = 1.8 ## 站立碰撞高（L3389）
const PLAYER_HEIGHT_PRONE: float = 0.4 ## 趴下碰撞高（L3413）

const STILL_SPEED_THRESHOLD: float = 0.05 ## 静止判定 u/s（L3458）
const SNIPER_STILL_TIME: float = 1.0 ## 静止多久触发狙杀 s（L1086）

# ===== 玩家生存 =====
# 2026-10-21 机主裁决：取消头/躯/腿三部位耐久，改为单一生命值 + 护甲能量双轨，
# 两者均脱战后自动恢复（沿用 10-19 纳米服式回充延迟）。旧三部位常量退役。
const HEALTH_MAX: float = 100.0 ## 生命值上限（2026-10-21 机主裁决：替代 HEALTH_HEAD/BODY/LEGS 三部位制）
const ARMOR_MAX: float = 100.0 ## 护甲能量（L327）
const ARMOR_ABSORB_FACTOR: float = 0.6 ## 护甲吸收上限 = 伤害×0.6（L3271；2026-10-21 起不再限躯体，任意命中先扣护甲）
# —— 生命值/护甲能量自动回复（2026-10-19 机主立项：孤岛危机纳米服式——脱战一小段时间后逐渐回充）——
const ARMOR_REGEN_DELAY: float = 4.0 ## 最后一次受击后进入回充的脱战时长 s（生命值与护甲共用同一延迟）
const ARMOR_REGEN_RATE: float = 12.0 ## 护甲回充速率 点/s（满充 100 约 8.3s）
const HEALTH_REGEN_RATE: float = 8.0 ## 生命值回复速率 点/s（与护甲同延迟同步回复，慢于护甲）
const MEDKIT_HEAL: float = 50.0 ## 生命值 +50（2026-10-21 单一生命值制）
const MEDKIT_PICKUP_RADIUS: float = 3.0 ## 拾取半径（L849）
const MEDKIT_MAX_CARRY: int = 5 ## 携带上限（L2305）

# ===== 拾取（2026-10-07 机主裁决冻结：居民区室内补给 = 电池组/医疗注射/取证终端，无 RPG）=====
const BATTERY_PICKUP_ROUNDS: int = 300 ## EC-68 电池组单件补充数（2026-11-10 机主裁决）
const PISTOL_AMMO_PICKUP_ROUNDS: int = 300 ## EC-57 弹匣组单件补充数（2026-11-10 机主裁决）
const RIFLE_RESERVE_MAX: int = 1800 ## EC-68 备弹携带上限（与初始备弹一致）
const PISTOL_RESERVE_MAX: int = 3000 ## EC-57 共享备弹携带上限（2026-11-08 机主裁决）
const PICKUP_TRIGGER_RADIUS: float = 0.7 ## 拾取触发半径（贴近即拾，无需按键）
const PICKUP_BOB_AMP: float = 0.05 ## 浮动振幅 m
const PICKUP_BOB_HZ: float = 1.2 ## 浮动频率 Hz
const PICKUP_SPIN_DEG: float = 45.0 ## 自转角速度 度/s
const GRENADE_PICKUP_ROUNDS: int = 20 ## EC-40 榴弹单件补充数（2026-11-10 机主裁决；雷池总数制无上限）

# ===== 铁栅栏门门禁（2026-10-25 机主指令：门 B 通行前置=钥匙 + 取证终端；
#       需求量 3 台=机主四轮裁决「拿到3个才完成」，全图恰 3 处须全部收集）=====
const GATE_INTEL_REQUIRED: int = 3 ## 坚固铁栅栏门通行所需取证终端数（E1 二层/E2 三层/E3 车库各 1）

# ===== 弹药口径伤害（2026-10-22 机主裁决：单发伤害绑定弹药口径而非具体枪——
#       凡用 EC-68 无壳步枪弹的武器一律 75，凡用 EC-57 无壳手枪弹的一律 45；
#       新增武器按所用弹药取本组值，不再单独设枪伤）=====
const AMMO_DMG_EC68: float = 75.0 ## EC-68 无壳步枪弹单发身体伤害
const AMMO_DMG_EC57: float = 45.0 ## EC-57 无壳手枪弹单发身体伤害

# ===== 步枪（G2 门禁基准）=====
const RIFLE_DMG_HEAD_FACTOR: float = 2.0 ## 爆头倍率（L2985）
const RIFLE_DMG_VS_SNIPER: float = 999.0 ## 对狙击手固定伤害（L3014）
const RIFLE_FIRE_INTERVAL: float = 0.075 ## 全自动/三发点射射速 s/发 = 800 RPM（2026-10-19 机主裁决：原 600 RPM L2609 提速）
const RIFLE_SEMI_FIRE_INTERVAL: float = 0.1 ## 半自动最小击发间隔 s（机主口径：半自动维持原 600 RPM 手感上限不变）
const RIFLE_MAG: int = 60 ## 弹匣（2026-10-19 机主裁决：按 EDAA 雷械设定 EM-68A 通用弹匣 60 发，原 30 为网页版 L327 值）
const RIFLE_RESERVE: int = 1800 ## EC-68 备弹（2026-11-07 机主裁决：EM-68A/D/L 共用）
const RIFLE_RELOAD_TIME: float = 2.0 ## 换弹 s（L2714）
const RIFLE_RANGE: float = 100.0 ## 射程上限 u（L2971）
const RIFLE_SPREAD_HIP: float = 0.004 ## 腰射散布（L2966）
const RIFLE_SPREAD_PRONE: float = 0.002 ## 趴下散布（L2967）
const RIFLE_SPREAD_AIM: float = 0.0005 ## 瞄准散布（L2967）
const RIFLE_RECOIL_PITCH: float = 0.003 ## 每发上跳 rad（L2959）；Godot 版加恢复（有意改进：网页版永久累积）
const RIFLE_RECOIL_VIEW_OFFSET: float = 0.08 ## 视图模型后坐量（L2959）
const RIFLE_RECOIL_DECAY: float = 0.82 ## 后坐衰减/帧（L3192）
const RIFLE_RECOIL_RECOVER_RATE: float = 6.0 ## 相机后坐恢复速率 /s（有意改进：网页版永久上跳，Godot 版指数恢复）
const RIFLE_RECOIL_VIEW_ROT: float = 2.25 ## 视图模型后坐旋转系数（L3205-3207）
const RIFLE_RECOIL_VIEW_Y_FACTOR: float = 0.025 ## 视图模型后坐位移系数 Y（L3205-3207）
const RIFLE_RECOIL_VIEW_Z_FACTOR: float = 0.05 ## 视图模型后坐位移系数 Z（L3205-3207）
const SCOPE_SHAKE_TIME: float = 0.2 ## 开镜击发抖动时长 s（L2960）
const SCOPE_SHAKE_PIXELS: float = 6.0 ## 抖动幅度 ±px（L2962）
const SCOPE_BREATH_PIXELS: float = 1.5 ## 呼吸摆动 ±px（L3225）

# ===== 按真实弹匣位置换弹（2026-11-10，机主批准分步方案 A）=====
# 方向和抓点按武器正交坐标，距离为实际米；阶段按原 reload_time 的比例。
const MAGAZINE_RELOAD_PROFILES: Dictionary = {
	&"mpx": {
		"extraction_direction": Vector3.DOWN,
		"extraction_distance": 0.225,
		"grip_offset": Vector3(-0.036, -0.105, -0.163),
		"contact_phase": 0.18,
		"pull_phase": 0.42,
		"new_phase": 0.58,
		"seat_phase": 0.82,
	},
	&"rifle": {
		"extraction_direction": Vector3.DOWN,
		"extraction_distance": 0.20,
		"grip_offset": Vector3(-0.028, -0.065, 0),
		"contact_phase": 0.18,
		"pull_phase": 0.42,
		"new_phase": 0.58,
		"seat_phase": 0.82,
	},
	&"dmr": {
		"extraction_direction": Vector3.DOWN,
		"extraction_distance": 0.193547,
		"grip_offset": Vector3(-0.044993, -0.079274, 0),
		"contact_phase": 0.18,
		"pull_phase": 0.42,
		"new_phase": 0.58,
		"seat_phase": 0.82,
	},
	&"shotgun": {
		"extraction_direction": Vector3.DOWN,
		"extraction_distance": 0.153306,
		"grip_offset": Vector3(-0.036268, -0.059153, 0),
		"contact_phase": 0.18,
		"pull_phase": 0.42,
		"new_phase": 0.58,
		"seat_phase": 0.82,
	},
	&"smg": {
		"extraction_direction": Vector3.DOWN,
		"extraction_distance": 0.317761,
		"grip_offset": Vector3(-0.036212, -0.141381, 0),
		"contact_phase": 0.18,
		"pull_phase": 0.42,
		"new_phase": 0.58,
		"seat_phase": 0.82,
	},
	&"lmg": {
		"extraction_direction": Vector3.DOWN,
		"extraction_distance": 0.261768,
		"grip_offset": Vector3(-0.135471, -0.113384, 0),
		"contact_phase": 0.18,
		"pull_phase": 0.42,
		"new_phase": 0.58,
		"seat_phase": 0.82,
	},
	&"em57s2": {
		"extraction_direction": Vector3.UP,
		"extraction_distance": 0.130342,
		"grip_offset": Vector3(-0.044387, 0.047671, 0),
		"contact_phase": 0.18,
		"pull_phase": 0.42,
		"new_phase": 0.58,
		"seat_phase": 0.82,
	},
	&"em86b": {
		"extraction_direction": Vector3.DOWN,
		"extraction_distance": 0.247431,
		"grip_offset": Vector3(-0.049001, -0.106215, 0),
		"contact_phase": 0.18,
		"pull_phase": 0.42,
		"new_phase": 0.58,
		"seat_phase": 0.82,
	},
	&"em86d": {
		"extraction_direction": Vector3.DOWN,
		"extraction_distance": 0.217271,
		"grip_offset": Vector3(-0.041524, -0.091136, 0),
		"contact_phase": 0.18,
		"pull_phase": 0.42,
		"new_phase": 0.58,
		"seat_phase": 0.82,
	},
	&"em86s": {
		"extraction_direction": Vector3.DOWN,
		"extraction_distance": 0.165484,
		"grip_offset": Vector3(-0.038280, -0.065242, 0),
		"contact_phase": 0.18,
		"pull_phase": 0.42,
		"new_phase": 0.58,
		"seat_phase": 0.82,
	},
	&"em86m": {
		"extraction_direction": Vector3.DOWN,
		"extraction_distance": 0.210270,
		"grip_offset": Vector3(-0.132613, -0.087635, 0),
		"contact_phase": 0.18,
		"pull_phase": 0.42,
		"new_phase": 0.58,
		"seat_phase": 0.82,
	},
	&"em12g2": {
		"extraction_direction": Vector3.DOWN,
		"extraction_distance": 0.194915,
		"grip_offset": Vector3(-0.086754, -0.079957, 0),
		"contact_phase": 0.18,
		"pull_phase": 0.42,
		"new_phase": 0.58,
		"seat_phase": 0.82,
	},
	&"em127g": {
		"extraction_direction": Vector3.DOWN,
		"extraction_distance": 0.189247,
		"grip_offset": Vector3(-0.041744, -0.077124, 0),
		"contact_phase": 0.18,
		"pull_phase": 0.42,
		"new_phase": 0.58,
		"seat_phase": 0.82,
	},
	&"em127m": {
		"extraction_direction": Vector3.DOWN,
		"extraction_distance": 0.256413,
		"grip_offset": Vector3(-0.104539, -0.110707, 0),
		"contact_phase": 0.18,
		"pull_phase": 0.42,
		"new_phase": 0.58,
		"seat_phase": 0.82,
	},
	&"em40t1": {
		"extraction_direction": Vector3.DOWN,
		"extraction_distance": 0.239185,
		"grip_offset": Vector3(-0.056883, -0.102092, 0),
		"contact_phase": 0.18,
		"pull_phase": 0.42,
		"new_phase": 0.58,
		"seat_phase": 0.82,
	},
}
const MAGAZINE_RELOAD_ELBOW_POLE := Vector3(0.08, -0.35, 0.22)
const MAGAZINE_RELOAD_EXCHANGE_DISTANCE: float = 0.18 ## 旧匣离井后的交换段额外行程，m

# 原生60骨黑臂：掌心接触点为枪局部米坐标，表面留2mm布料间隙。
const BLACK_LONG_GUN_RIGHT_ELBOW_POLE := Vector3(0.08, -0.35, 0.22)
const BLACK_LONG_GUN_LEFT_ELBOW_POLE := Vector3(-0.08, -0.35, 0.22)
const BLACK_LONG_GUN_SHOULDER_REACH: float = 0.94
const BLACK_LONG_GUN_PALM_WEIGHT: float = 0.65
const BLACK_LONG_GUN_PROFILES: Dictionary = {
	&"mpx": {
		"right_grip": Vector3(0.014, -0.060, 0.025),
		"hip_depth": 0.0,
		"reload_depth": 0.15,
		"support_grip_hip": Vector3(-0.034, -0.025, -0.245),
		"support_grip_ads": Vector3(-0.034, -0.025, -0.245),
		"support_rotation": Vector3.ZERO,
		"reload_cant": Vector3(0.05, -0.04, -0.30),
		"reload_lift": Vector3(0, 0.035, -0.04),
	},
	&"spas12": {
		"right_grip": Vector3(0.065951, -0.143531, 0.187622),
		"hip_depth": 0.0,
		"hip_rearward": 0.32, ## 常规腰射恢复枪托连接处取景；ADS/装填按阶段淡出。
		"support_grip_hip": Vector3(0.014655, -0.015053, -0.370225),
		"support_grip_ads": Vector3(0.014655, -0.015053, -0.370225),
		"support_rotation": Vector3(0, 0, PI / 2.0),
		"reload_cant": Vector3(0, 0, 0.3),
		"reload_lift": SPAS12_RELOAD_LIFT,
	},
	&"em120r": {
		"right_grip": Vector3(0.019053, -0.208801, 0.133105),
		"hip_depth": 0.0,
		"hip_rearward": 0.32,
		"support_grip_hip": Vector3(-0.06034, -0.065675, -0.278539),
		"support_grip_ads": Vector3(-0.06034, -0.065675, -0.278539),
		"support_rotation": Vector3.ZERO,
		"reload_cant": Vector3(0.15, -PI / 2.0, -0.18),
		"reload_lift": Vector3(0.36, -0.20, -0.24),
	},
	&"rifle": {
		"right_grip": Vector3(0.02879577, -0.09, 0.175),
		"hip_depth": 0.0,
		"reload_depth": 0.32, ## 只在协同换弹中平滑前移，常规腰射保留原取景。
		"support_grip_hip": Vector3(-0.02766985, -0.023918, -0.16968082),
		"support_grip_ads": Vector3(-0.02766985, -0.023918, -0.16968082),
		"support_rotation": Vector3.ZERO,
		"reload_cant": Vector3(0.05, -0.04, -0.30),
		"reload_lift": Vector3(0, 0.035, -0.04),
	},
	&"dmr": {
		"right_grip": Vector3(0.02325584, -0.09, 0.25),
		"hip_depth": 0.0,
		"reload_depth": 0.32,
		"support_grip_hip": Vector3(-0.02272169, -0.03831264, -0.16319647),
		"support_grip_ads": Vector3(-0.02272169, -0.03831264, -0.16319647),
		"support_rotation": Vector3.ZERO,
		"reload_cant": Vector3(0.05, -0.04, -0.30),
		"reload_lift": Vector3(0, 0.035, -0.04),
	},
	&"shotgun": {
		"right_grip": Vector3(0.02208694, -0.09, 0.15),
		"hip_depth": 0.0,
		"reload_depth": 0.32,
		"support_grip_hip": Vector3(-0.01707988, -0.02225382, -0.15895115),
		"support_grip_ads": Vector3(-0.01707988, -0.02225382, -0.15895115),
		"support_rotation": Vector3.ZERO,
		"reload_cant": Vector3(0.05, -0.04, -0.30),
		"reload_lift": Vector3(0, 0.035, -0.04),
	},
	&"smg": {
		"right_grip": Vector3(0.02351493, -0.065, 0.13),
		"hip_depth": 0.0,
		"reload_depth": 0.32,
		"support_grip_hip": Vector3(-0.01459263, 0.00605233, -0.15236323),
		"support_grip_ads": Vector3(-0.01459263, 0.00605233, -0.15236323),
		"support_rotation": Vector3.ZERO,
		"reload_cant": Vector3(0.05, -0.04, -0.30),
		"reload_lift": Vector3(0, 0.035, -0.04),
	},
	&"lmg": {
		"right_grip": Vector3(0.02005969, -0.09, 0.15),
		"hip_depth": 0.0,
		"reload_depth": 0.32,
		"support_grip_hip": Vector3(-0.06183238, -0.05336965, -0.15414836),
		"support_grip_ads": Vector3(-0.06183238, -0.05336965, -0.15414836),
		"support_rotation": Vector3.ZERO,
		"reload_cant": Vector3(0.05, -0.04, -0.30),
		"reload_lift": Vector3(0, 0.035, -0.04),
	},
	&"em57s2": {
		"right_grip": Vector3(0.02146934, -0.065, 0.3),
		"hip_depth": 0.0,
		"reload_depth": 0.32,
		"support_grip_hip": Vector3(-0.03233485, -0.03223716, -0.17953514),
		"support_grip_ads": Vector3(-0.03233485, -0.03223716, -0.17953514),
		"support_rotation": Vector3.ZERO,
		"reload_cant": Vector3(0.05, -0.04, -0.30),
		"reload_lift": Vector3(0, 0.035, -0.04),
	},
	&"em86b": {
		"right_grip": Vector3(0.02454021, -0.09, 0.2),
		"hip_depth": 0.0,
		"reload_depth": 0.32,
		"support_grip_hip": Vector3(-0.04121753, -0.03943384, -0.16922508),
		"support_grip_ads": Vector3(-0.04121753, -0.03943384, -0.16922508),
		"support_rotation": Vector3.ZERO,
		"reload_cant": Vector3(0.05, -0.04, -0.30),
		"reload_lift": Vector3(0, 0.035, -0.04),
	},
	&"em86d": {
		"right_grip": Vector3(0.01914745, -0.065, 0.3),
		"hip_depth": 0.0,
		"reload_depth": 0.32,
		"support_grip_hip": Vector3(-0.02531621, -0.02250865, -0.13559248),
		"support_grip_ads": Vector3(-0.02531621, -0.02250865, -0.13559248),
		"support_rotation": Vector3.ZERO,
		"reload_cant": Vector3(0.05, -0.04, -0.30),
		"reload_lift": Vector3(0, 0.035, -0.04),
	},
	&"em86s": {
		"right_grip": Vector3(0.02084804, -0.09, 0.3),
		"hip_depth": 0.0,
		"reload_depth": 0.32,
		"support_grip_hip": Vector3(-0.0263424, -0.03455873, -0.14105143),
		"support_grip_ads": Vector3(-0.0263424, -0.03455873, -0.14105143),
		"support_rotation": Vector3.ZERO,
		"reload_cant": Vector3(0.05, -0.04, -0.30),
		"reload_lift": Vector3(0, 0.035, -0.04),
	},
	&"em86m": {
		"right_grip": Vector3(0.02378764, -0.09, 0.2),
		"hip_depth": 0.0,
		"reload_depth": 0.32,
		"support_grip_hip": Vector3(-0.05580504, -0.04708992, -0.17166756),
		"support_grip_ads": Vector3(-0.05580504, -0.04708992, -0.17166756),
		"support_rotation": Vector3.ZERO,
		"reload_cant": Vector3(0.05, -0.04, -0.30),
		"reload_lift": Vector3(0, 0.035, -0.04),
	},
	&"em12g2": {
		"right_grip": Vector3(0.02247028, -0.09, 0.15),
		"hip_depth": 0.0,
		"reload_depth": 0.32,
		"support_grip_hip": Vector3(-0.02535065, -0.03460014, -0.14815541),
		"support_grip_ads": Vector3(-0.02535065, -0.03460014, -0.14815541),
		"support_rotation": Vector3.ZERO,
		"reload_cant": Vector3(0.05, -0.04, -0.30),
		"reload_lift": Vector3(0, 0.035, -0.04),
	},
	&"em127g": {
		"right_grip": Vector3(0.01917667, -0.09, 0.3),
		"hip_depth": 0.0,
		"reload_depth": 0.32,
		"support_grip_hip": Vector3(-0.03591655, -0.03562932, -0.13826118),
		"support_grip_ads": Vector3(-0.03591655, -0.03562932, -0.13826118),
		"support_rotation": Vector3.ZERO,
		"reload_cant": Vector3(0.05, -0.04, -0.30),
		"reload_lift": Vector3(0, 0.035, -0.04),
	},
	&"em127m": {
		"right_grip": Vector3(0.02397544, -0.09, 0.2),
		"hip_depth": 0.0,
		"reload_depth": 0.32,
		"support_grip_hip": Vector3(-0.04158144, -0.04646479, -0.16884027),
		"support_grip_ads": Vector3(-0.04158144, -0.04646479, -0.16884027),
		"support_rotation": Vector3.ZERO,
		"reload_cant": Vector3(0.05, -0.04, -0.30),
		"reload_lift": Vector3(0, 0.035, -0.04),
	},
	&"em40t1": {
		"right_grip": Vector3(0.03194549, -0.115, 0.15),
		"hip_depth": 0.0,
		"reload_depth": 0.32,
		"support_grip_hip": Vector3(-0.03856448, -0.03090639, -0.18151964),
		"support_grip_ads": Vector3(-0.03856448, -0.03090639, -0.18151964),
		"support_rotation": Vector3.ZERO,
		"reload_cant": Vector3(0.05, -0.04, -0.30),
		"reload_lift": Vector3(0, 0.035, -0.04),
	},
}

# 原生黑色手臂整体等比摆位，G17食指局部旋转校准；不改骨rest/蒙皮或骨pose缩放。
const BLACK_PISTOL_PROFILES: Dictionary = {
	&"g17": {
		"weapon_anchor": Vector3(-0.004, 0.0019, 0.065),
		"trigger_finger_curl": -0.2,
		"magazine_grip": Vector3(-0.025, -0.065, 0.06),
		"source_rotation": Vector3(0, PI, 0),
		"root_scale": 1.0,
		"lock_idle": true,
		"lock_ads_idle": false,
		"reload_contact_phase": 0.20,
		"reload_seat_phase": 0.84,
		"left_elbow_pole": Vector3(-0.1, -0.3, 0.15),
	},
	&"pistol": {
		"weapon_anchor": Vector3(-0.007154029, -0.064155, 0.353723),
		"magazine_grip": Vector3(-0.069989, -0.064596, 0.083652),
		"source_rotation": Vector3(0, PI, 0),
		"root_scale": 1.0,
		"lock_idle": true, ## 机主实机要求只保留射击和换弹动作，腰射与ADS待机均稳定。
		"lock_ads_idle": false,
		"reload_contact_phase": 0.20,
		"reload_seat_phase": 0.84,
		"left_elbow_pole": Vector3(-0.1, -0.3, 0.15),
	},
	&"magnum": {
		"weapon_anchor": Vector3(-0.006295202, -0.083208, 0.329047),
		"magazine_grip": Vector3(-0.075189, -0.056939, 0),
		"source_rotation": Vector3(0, PI, 0),
		"root_scale": 1.0,
		"lock_idle": true,
		"lock_ads_idle": true, ## 原生idle中段枪身会遮住ADS中心，开镜待机固定标定首帧。
		"reload_contact_phase": 0.20,
		"reload_seat_phase": 0.84,
		"left_elbow_pole": Vector3(-0.1, -0.3, 0.15),
	},
	&"gen5": {
		"weapon_anchor": Vector3(0, -0.055, 0.06),
		"magazine_grip": Vector3(-0.025, -0.065, 0.06),
		"source_rotation": Vector3(0, PI, 0),
		"root_scale": 1.0,
		"lock_idle": false,
		"lock_ads_idle": false,
		"reload_contact_phase": 0.20,
		"reload_seat_phase": 0.84,
		"left_elbow_pole": Vector3(-0.1, -0.3, 0.15),
	},
}

# ===== 手枪（EM-57P「掣」，2026-10-19 机主立项：EDAA 雷械设定落地，2 号键位；
#       网页版无手枪，数值按设定文档+手感类比定标，G4 试玩复核）=====
const PISTOL_DMG_HEAD_FACTOR: float = 2.0 ## 爆头倍率
const PISTOL_DMG_VS_SNIPER: float = 999.0 ## 对狙击手固定伤害（沿用步枪语义）
const PISTOL_FIRE_INTERVAL: float = 0.06 ## 全自动/三发点射射速 s/发 = 1000 RPM（2026-10-19 机主裁决）
const PISTOL_SEMI_FIRE_INTERVAL: float = 0.15 ## 半自动最小击发间隔 s（≈400 RPM 上限，机主口径：半自动不变）
const PISTOL_MAG: int = 30 ## 弹匣（EDAA 设定：30 发制式弹匣）
const PISTOL_RESERVE: int = 3000 ## EC-57 共享备弹（2026-11-08 机主裁决：3000 发）
const PISTOL_RELOAD_TIME: float = 1.6 ## 换弹 s（无托手枪快于步枪）
const PISTOL_RANGE: float = 80.0 ## 射程上限 u
const PISTOL_SPREAD_HIP: float = 0.006 ## 腰射散布（略劣于步枪）
const PISTOL_SPREAD_PRONE: float = 0.003 ## 趴下散布
const PISTOL_SPREAD_AIM: float = 0.001 ## 瞄准散布
const PISTOL_RECOIL_PITCH: float = 0.002 ## 每发上跳 rad（EDAA 设定：后坐仅 .22 级）
const PISTOL_RECOIL_VIEW_OFFSET: float = 0.05 ## 视图模型后坐量（轻于步枪）
const PISTOL_RECOIL_DECAY: float = 0.85 ## 后坐衰减/帧
const PISTOL_RECOIL_RECOVER_RATE: float = 8.0 ## 相机后坐恢复速率 /s（轻快恢复）
const PISTOL_RECOIL_VIEW_ROT: float = 2.0 ## 视图模型后坐旋转系数
const PISTOL_RECOIL_VIEW_Y_FACTOR: float = 0.02 ## 视图模型后坐位移系数 Y
const PISTOL_RECOIL_VIEW_Z_FACTOR: float = 0.04 ## 视图模型后坐位移系数 Z

# ===== EM-57S-1「雹·Ⅰ」冲锋枪（与 EM-57P 共用 EC-57 备弹池）=====
const SMG_FIRE_INTERVAL: float = 0.06 ## 全自动/三发点射 1000 RPM
const SMG_SEMI_FIRE_INTERVAL: float = 0.12 ## 半自动击发间隔
const SMG_MAG: int = 100
const SMG_RELOAD_TIME: float = 1.8
const SMG_RANGE: float = 90.0
const SMG_SPREAD_HIP: float = 0.005
const SMG_SPREAD_PRONE: float = 0.0025
const SMG_SPREAD_AIM: float = 0.0008
const SMG_RECOIL_PITCH: float = 0.0022
const SMG_RECOIL_VIEW_OFFSET: float = 0.055
const SMG_RECOIL_DECAY: float = 0.84
const SMG_RECOIL_RECOVER_RATE: float = 8.0
const SMG_RECOIL_VIEW_ROT: float = 2.0
const SMG_RECOIL_VIEW_Y_FACTOR: float = 0.02
const SMG_RECOIL_VIEW_Z_FACTOR: float = 0.04
const SMG_ADS_FOV: float = 60.0
const SMG_ARMS_OFFSET := Vector3(0, -0.033, -0.097) ## EM-57S-1右掌贴合实模扳机握把，原生完整右臂/手指姿态不变
const SMG_SOUND_PITCH: float = 1.1

# ===== EM-68L「殷雷」班用机枪（与 EM-68A/D 共用 EC-68 备弹池）=====
const LMG_FIRE_INTERVAL: float = 0.05 ## 全自动/三发点射 1200 RPM
const LMG_SEMI_FIRE_INTERVAL: float = 0.12 ## 半自动击发间隔
const LMG_MAG: int = 600
const LMG_RELOAD_TIME: float = 3.2
const LMG_RANGE: float = 140.0
const LMG_SPREAD_HIP: float = 0.006
const LMG_SPREAD_PRONE: float = 0.002
const LMG_SPREAD_AIM: float = 0.0008
const LMG_RECOIL_PITCH: float = 0.0035
const LMG_RECOIL_VIEW_OFFSET: float = 0.09
const LMG_RECOIL_DECAY: float = 0.82
const LMG_RECOIL_RECOVER_RATE: float = 6.5
const LMG_RECOIL_VIEW_ROT: float = 2.25
const LMG_RECOIL_VIEW_Y_FACTOR: float = 0.025
const LMG_RECOIL_VIEW_Z_FACTOR: float = 0.05
const LMG_ADS_FOV: float = 60.0
const LMG_SOUND_PITCH: float = 0.75

# ===== EM-127P「锏」马格南重型手枪（独立 EC-127 弹药）=====
const MAGNUM_DAMAGE_BODY: float = 150.0
const MAGNUM_FIRE_INTERVAL: float = 0.55 ## 仅半自动
const MAGNUM_SEMI_FIRE_INTERVAL: float = 0.55
const MAGNUM_MAG: int = 15
const MAGNUM_RESERVE: int = 1500 ## EC-127 备弹（2026-11-07 机主裁决）
const MAGNUM_RELOAD_TIME: float = 2.0
const MAGNUM_RANGE: float = 120.0
const MAGNUM_SPREAD_HIP: float = 0.003
const MAGNUM_SPREAD_PRONE: float = 0.0015
const MAGNUM_SPREAD_AIM: float = 0.0004
const MAGNUM_RECOIL_PITCH: float = 0.018
const MAGNUM_RECOIL_VIEW_OFFSET: float = 0.17
const MAGNUM_RECOIL_DECAY: float = 0.8
const MAGNUM_RECOIL_RECOVER_RATE: float = 5.0
const MAGNUM_RECOIL_VIEW_ROT: float = 2.5
const MAGNUM_RECOIL_VIEW_Y_FACTOR: float = 0.03
const MAGNUM_RECOIL_VIEW_Z_FACTOR: float = 0.06
const MAGNUM_ADS_FOV: float = 65.0
const MAGNUM_SOUND_PITCH: float = 0.55

const LONG_GUN_SHOULDER_DIRECTION := Vector3(0.03, -0.36, 0.14) ## 新长枪双臂 IK 的肩部收拢方向

# ===== EM-68D「穿杨」精确射手步枪（2026-10-26 机主裁决：弹匣与备弹池均和 EM-68A 通用）=====
const DMR_DAMAGE_BODY: float = 90.0 ## 机主指定单发伤害；DMR 精准平台专项值，不改 EC-68 通用 75
const DMR_DMG_HEAD_FACTOR: float = 2.0
const DMR_DMG_VS_SNIPER: float = 999.0
const DMR_FIRE_INTERVAL: float = 0.22 ## 仅半自动；与半自动间隔一致，便于数据资源统一
const DMR_SEMI_FIRE_INTERVAL: float = 0.22 ## 约 272 RPM，突出有节奏单发
const DMR_MAG: int = 60
const DMR_RELOAD_TIME: float = 2.2
const DMR_RANGE: float = 180.0
const DMR_SPREAD_HIP: float = 0.0025
const DMR_SPREAD_PRONE: float = 0.001
const DMR_SPREAD_AIM: float = 0.00012
const DMR_RECOIL_PITCH: float = 0.006
const DMR_RECOIL_VIEW_OFFSET: float = 0.11
const DMR_RECOIL_DECAY: float = 0.82
const DMR_RECOIL_RECOVER_RATE: float = 6.0
const DMR_RECOIL_VIEW_ROT: float = 2.25
const DMR_RECOIL_VIEW_Y_FACTOR: float = 0.025
const DMR_RECOIL_VIEW_Z_FACTOR: float = 0.05
const DMR_SOUND_PITCH: float = 0.85 ## 复用步枪音源，较低音高区分重型枪管
const DMR_HIP_POSE_YAW: float = 0.26
const DMR_HIP_POSE_PITCH: float = 0.05
const DMR_ARMS_OFFSET := Vector3(0, -0.02, 0.07)
const DMR_SUPPORT_WRIST_HIP := Vector3(-0.05, -0.045, -0.14)
const DMR_SUPPORT_WRIST_ADS := Vector3(-0.05, -0.10, -0.13)

# ===== EM-86 系列（共享 EC-86；S/B/D 45 发弹匣，M 500 发弹箱）=====
const EM86_MAG: int = 45
const EM86_RESERVE: int = 4500 ## EM-86S/B/D/M共享EC-86备弹；2026-11-08机主裁决
const EM86_RELOAD_TIME: float = 2.4
const EM86_RECOIL_DECAY: float = 0.82
const EM86_RECOIL_RECOVER_RATE: float = 6.0
const EM86_RECOIL_VIEW_ROT: float = 2.25
const EM86_RECOIL_VIEW_Y_FACTOR: float = 0.025
const EM86_RECOIL_VIEW_Z_FACTOR: float = 0.05
const EM86S_DAMAGE_BODY: float = 240.0
const EM86S_SEMI_FIRE_INTERVAL: float = 0.35
const EM86S_RANGE: float = 260.0
const EM86S_SPREAD_HIP: float = 0.002
const EM86S_SPREAD_PRONE: float = 0.0008
const EM86S_SPREAD_AIM: float = 0.00006
const EM86S_RECOIL_PITCH: float = 0.012
const EM86S_RECOIL_VIEW_OFFSET: float = 0.18
const EM86S_SCOPE_FOVS: Array[float] = [35.0, 17.5, 8.75] ## 8/16/32 倍；8x 沿用 DMR 视野
const EM86S_SCOPE_ZOOMS: Array[int] = [8, 16, 32]
const EM86S_SOUND_PITCH: float = 0.65
const EM86B_DAMAGE_BODY: float = 120.0
const EM86B_FIRE_INTERVAL: float = 60.0 / 650.0 ## 全自动 650 RPM
const EM86B_BURST_FIRE_INTERVAL: float = 60.0 / 900.0 ## 三发点射 900 RPM
const EM86B_SEMI_FIRE_INTERVAL: float = 0.12
const EM86B_RANGE: float = 200.0
const EM86B_SPREAD_HIP: float = 0.0035
const EM86B_SPREAD_PRONE: float = 0.0015
const EM86B_SPREAD_AIM: float = 0.0003
const EM86B_RECOIL_PITCH: float = 0.005
const EM86B_RECOIL_VIEW_OFFSET: float = 0.1
const EM86B_ADS_FOV: float = 60.0
const EM86B_SOUND_PITCH: float = 0.8
const EM86D_DAMAGE_BODY: float = 180.0
const EM86D_SEMI_FIRE_INTERVAL: float = 0.28
const EM86D_RANGE: float = 240.0
const EM86D_SPREAD_HIP: float = 0.0022
const EM86D_SPREAD_PRONE: float = 0.0009
const EM86D_SPREAD_AIM: float = 0.00008
const EM86D_RECOIL_PITCH: float = 0.009
const EM86D_RECOIL_VIEW_OFFSET: float = 0.15
const EM86D_ADS_FOV: float = 35.0
const EM86D_SOUND_PITCH: float = 0.72

# ===== EM-57S-2「雹·Ⅱ」无托顶置供弹冲锋枪（2026-11-08 机主裁决）=====
const EM57S2_DAMAGE_BODY: float = 45.0
const EM57S2_FIRE_INTERVAL: float = 0.05 ## 全自动/半自动/三发点射均为 1200 RPM
const EM57S2_SEMI_FIRE_INTERVAL: float = 0.05
const EM57S2_BURST_FIRE_INTERVAL: float = 0.05
const EM57S2_MAG: int = 200 ## 2026-11-08 机主裁决
const EM57S2_RELOAD_TIME: float = 2.0
const EM57S2_RANGE: float = 100.0
const EM57S2_SPREAD_HIP: float = 0.0045
const EM57S2_SPREAD_PRONE: float = 0.0022
const EM57S2_SPREAD_AIM: float = 0.0007
const EM57S2_RECOIL_PITCH: float = 0.0022
const EM57S2_RECOIL_VIEW_OFFSET: float = 0.055
const EM57S2_ADS_FOV: float = 60.0
const EM57S2_ADS_MOUNT_Z: float = -0.15 ## 眼位到前方小瞄具约30cm，弹匣尾盖退至相机后方
const EM57S2_ADS_NEAR: float = 0.005 ## 仅该枪开镜：让枪壳近平面截口落至画面下缘之外
const EM57S2_SOUND_PITCH: float = 1.18

# ===== EM-86M 中口径通用机枪（与 EM-86S/B/D 共用 EC-86）=====
const EM86M_DAMAGE_BODY: float = 180.0
const EM86M_FIRE_INTERVAL: float = 0.075 ## 全自动/半自动均为 800 RPM，无三发点射
const EM86M_SEMI_FIRE_INTERVAL: float = 0.075
const EM86M_MAG: int = 500
const EM86M_RELOAD_TIME: float = 3.2
const EM86M_RANGE: float = 220.0
const EM86M_SPREAD_HIP: float = 0.0035
const EM86M_SPREAD_PRONE: float = 0.0015
const EM86M_SPREAD_AIM: float = 0.0003
const EM86M_RECOIL_PITCH: float = 0.006
const EM86M_RECOIL_VIEW_OFFSET: float = 0.12
const EM86M_ADS_FOV: float = 60.0
## 镜内准星随视口高度缩放，1080高时刻度15→22px，保留通光区边缘余量。
const EM86M_RETICLE_TICK_INNER_RATIO: float = 15.0 / 1080.0
const EM86M_RETICLE_TICK_OUTER_RATIO: float = 22.0 / 1080.0
const EM86M_RETICLE_RING_RADIUS_RATIO: float = 10.0 / 1080.0
const EM86M_RETICLE_DOT_RADIUS_RATIO: float = 1.8 / 1080.0
const EM86M_RETICLE_LINE_WIDTH_RATIO: float = 1.4 / 1080.0
const EM86M_SOUND_PITCH: float = 0.7

# ===== EM-40T-1 半自动榴弹发射器（与下挂模块共用 EC-40 雷池）=====
const EM40T1_MAG: int = 20
const EM40T1_RELOAD_TIME: float = 2.8
const EM40T1_ADS_FOV: float = 35.0
const EM40T1_RECOIL_PITCH: float = 0.012
const EM40T1_RECOIL_VIEW_OFFSET: float = 0.22
const EM40T1_SCOPE_HOLDOVER_METERS: Array[int] = [50, 100, 150, 200] ## 按共享初速/重力实时换算下坠角

# ===== EM-127G「凿空」重型反器材高斯狙击枪（2026-11-07 机主裁决）=====
const EM127G_DAMAGE_BODY: float = 450.0
const EM127G_CHARGE_TIME: float = 1.0 ## 按住满 1 秒发射充能弹；不足 1 秒松开发射普通弹
const EM127G_CHARGED_DAMAGE_BODY: float = 900.0
const EM127G_SEMI_FIRE_INTERVAL: float = 0.5
const EM127G_MAG: int = 30
const EM127G_RELOAD_TIME: float = 3.0
const EM127G_RANGE: float = 320.0
const EM127G_SPREAD_HIP: float = 0.0015
const EM127G_SPREAD_PRONE: float = 0.0005
const EM127G_SPREAD_AIM: float = 0.00003
const EM127G_RECOIL_PITCH: float = 0.025
const EM127G_RECOIL_VIEW_OFFSET: float = 0.24
const EM127G_RECOIL_DECAY: float = 0.8
const EM127G_RECOIL_RECOVER_RATE: float = 4.5
const EM127G_RECOIL_VIEW_ROT: float = 2.5
const EM127G_RECOIL_VIEW_Y_FACTOR: float = 0.035
const EM127G_RECOIL_VIEW_Z_FACTOR: float = 0.07
const EM127G_SCOPE_FOVS: Array[float] = [17.5, 8.75, 4.375] ## 16/32/64 倍
const EM127G_SCOPE_ZOOMS: Array[int] = [16, 32, 64]

# ===== EM-127M 雷霆 / EM-120R 长弓（2026-11-09 机主批准）=====
const EM127M_DAMAGE_BODY: float = 450.0
const EM127M_MAG: int = 500
const EM127M_FIRE_INTERVAL: float = 60.0 / 700.0
const EM127M_SEMI_FIRE_INTERVAL: float = 60.0 / 700.0
const EM127M_RELOAD_TIME: float = EM86M_RELOAD_TIME
const EM127M_RANGE: float = EM127G_RANGE
const EM127M_SPREAD_HIP: float = EM127G_SPREAD_HIP
const EM127M_SPREAD_PRONE: float = EM127G_SPREAD_PRONE
const EM127M_SPREAD_AIM: float = EM127G_SPREAD_AIM
const EM127M_RECOIL_PITCH: float = EM86M_RECOIL_PITCH
const EM127M_RECOIL_VIEW_OFFSET: float = EM86M_RECOIL_VIEW_OFFSET
const EM127M_SOUND_PITCH: float = 0.5
const EM120R_MAG: int = 10
const EM120R_RESERVE: int = 150 ## 机主指定备弹150发；独立 EC-120 不借用 EC-40
const EM120R_FIRE_INTERVAL: float = 0.8
const EM120R_RELOAD_TIME: float = 3.0
const EM120R_DAMAGE_BODY: float = 1200.0
const EM120R_EXPLODE_RADIUS: float = 35.0
const EM120R_INNER_RADIUS: float = 20.0
const EM120R_INNER_DAMAGE: float = 1200.0
const EM120R_OUTER_DAMAGE: float = 800.0
const EM120R_EJECT_SPEED: float = 12.0
const EM120R_IGNITION_DISTANCE: float = 3.0
const EM120R_PROJECTILE_SPEED: float = 80.0
const EM120R_MAX_RANGE: float = 1500.0
const EM120R_TURN_RATE: float = deg_to_rad(120.0)
const EM120R_LOCK_TIME: float = 1.0
const EM120R_MODEL_POSITION := Vector3(0, 0.18, 0.06)
const EM120R_MODEL_ROTATION := Vector3.ZERO
const EM120R_MUZZLE_POSITION := Vector3(0, 0, -0.6)
const EM120R_RIGHT_GRIP := Vector3(0, -0.17, 0.04)
const EM120R_SUPPORT_GRIP := Vector3(0, -0.10, -0.28)
const EM120R_RIGHT_ELBOW := Vector3(0.17, -0.35, 0.35)
const EM120R_LEFT_ELBOW := Vector3(-0.25, -0.4, 0.05)
const EM120R_LASER_WIDTH: float = 0.012
const EM120R_LASER_COLOR := Color(0.2, 0.85, 1.0)
const EM120R_LASER_ENERGY: float = 2.0
const EM120R_LASER_ORIGIN := Vector3(0.08, 0.08, -0.48)
const EM120R_ENGINE_FLAME_LENGTH: float = 0.5
const EM120R_ENGINE_FLAME_RADIUS: float = 0.055
const EM120R_ENGINE_FLAME_COLOR := Color(0.45, 0.9, 1.0)
const EM120R_ENGINE_LIGHT_ENERGY: float = 2.0
const EM120R_ENGINE_LIGHT_RANGE: float = 2.0
const EM120R_RECOIL_PITCH: float = 0.006
const EM120R_RECOIL_VIEW_OFFSET: float = 0.08
const EM120R_SOUND_PITCH: float = 0.7

# ===== EM-12G-2「霰·Ⅱ」有托前置供弹霰弹枪（2026-11-07 机主裁决）=====
const EM12G2_FIRE_INTERVAL: float = 60.0 / 650.0 ## 全自动 650 RPM
const EM12G2_SEMI_FIRE_INTERVAL: float = 0.25
const EM12G2_MAG: int = 64
const EM12G2_RELOAD_TIME: float = 2.8
const EM12G2_SOUND_PITCH: float = 0.65

# ===== EM-12G-1「霰·Ⅰ」无托电磁霰弹枪（2026-10-26 机主数值裁决）=====
const AMMO_DMG_EC12_PELLET: float = 30.0 ## EC-12「砂」单丸身体伤害；一次击发 12 丸
const SHOTGUN_DMG_HEAD_FACTOR: float = 1.5
const SHOTGUN_DMG_VS_SNIPER: float = 999.0
const SHOTGUN_PELLET_COUNT: int = 12
const SHOTGUN_FIRE_INTERVAL: float = 0.12 ## 全自动 500 RPM
const SHOTGUN_SEMI_FIRE_INTERVAL: float = 0.25
const SHOTGUN_MAG: int = 32
const SHOTGUN_RESERVE: int = 160
const SHOTGUN_RESERVE_MAX: int = 160
const SHOTGUN_AMMO_PICKUP_ROUNDS: int = 32
const SHOTGUN_RELOAD_TIME: float = 2.4
const SHOTGUN_RANGE: float = 50.0
const SHOTGUN_SPREAD_START: float = 15.0 ## 准星首中距离超过 15m 才开始弹丸扩散
const SHOTGUN_SPREAD_HIP: float = 0.055
const SHOTGUN_SPREAD_PRONE: float = 0.04
const SHOTGUN_SPREAD_AIM: float = 0.035
const SHOTGUN_RECOIL_PITCH: float = 0.012
const SHOTGUN_RECOIL_VIEW_OFFSET: float = 0.16
const SHOTGUN_RECOIL_DECAY: float = 0.8
const SHOTGUN_RECOIL_RECOVER_RATE: float = 7.0
const SHOTGUN_RECOIL_VIEW_ROT: float = 2.5
const SHOTGUN_RECOIL_VIEW_Y_FACTOR: float = 0.03
const SHOTGUN_RECOIL_VIEW_Z_FACTOR: float = 0.06
const SHOTGUN_SOUND_PITCH: float = 0.65 ## 复用步枪音源，低音高突出单次面打击
const SHOTGUN_HIP_POSE_YAW: float = 0.26
const SHOTGUN_HIP_POSE_PITCH: float = 0.05
const SHOTGUN_ARMS_OFFSET := Vector3(0, -0.02, 0.07)
const SHOTGUN_SUPPORT_WRIST_HIP := Vector3(-0.04, -0.05, -0.16)
const SHOTGUN_SUPPORT_WRIST_ADS := Vector3(-0.04, -0.08, -0.10)
const SHOTGUN_ELBOW_POLE := Vector3(-0.18, -0.45, 0.12) ## 开镜支撑肘向左下收拢，避免前臂横挡镜头
const SHOTGUN_RIGHT_ELBOW_POLE := Vector3(0.12, -0.25, -0.45) ## 右握枪肘向前下方收拢，保留原生右手握点
const SHOTGUN_ADS_CAMERA_FORWARD: float = 0.04 ## 玩家视角向瞄具前移4cm；枪挂载不再向远处推，视觉上枪相应后收
const SHOTGUN_ADS_OFFSET_X: float = 0.003 ## 仅开镜向右补偿3mm，修正OpticAim相对实际镜孔的水平偏差

# ===== SPAS-12 传统泵动霰弹枪（独立 12GA 弹药，不与 EC-12 混用）=====
const SPAS12_DAMAGE_BODY: float = 20.0
const SPAS12_DMG_HEAD_FACTOR: float = 1.5
const SPAS12_DMG_VS_SNIPER: float = 999.0
const SPAS12_PELLET_COUNT: int = 8
const SPAS12_FIRE_INTERVAL: float = 0.85
const SPAS12_SEMI_FIRE_INTERVAL: float = 0.85
const SPAS12_MAG: int = 8
const SPAS12_RESERVE: int = 40
const SPAS12_RESERVE_MAX: int = 64
const SPAS12_AMMO_PICKUP_ROUNDS: int = 8
const SPAS12_RELOAD_SHELL_TIME: float = 0.55
const SPAS12_RANGE: float = 35.0
const SPAS12_SPREAD_START: float = 10.0
const SPAS12_SPREAD_HIP: float = 0.07
const SPAS12_SPREAD_PRONE: float = 0.05
const SPAS12_SPREAD_AIM: float = 0.045
const SPAS12_RECOIL_PITCH: float = 0.016
const SPAS12_RECOIL_VIEW_OFFSET: float = 0.18
const SPAS12_RECOIL_DECAY: float = 0.8
const SPAS12_RECOIL_RECOVER_RATE: float = 7.0
const SPAS12_RECOIL_VIEW_ROT: float = 2.5
const SPAS12_RECOIL_VIEW_Y_FACTOR: float = 0.03
const SPAS12_RECOIL_VIEW_Z_FACTOR: float = 0.06
const SPAS12_SOUND_PITCH: float = 0.58
const SPAS12_PUMP_TIME: float = 0.62
const SPAS12_RELOAD_CANT: float = 0.3
const SPAS12_MODEL_POSITION := Vector3(-0.04, -0.035, -0.20)
const SPAS12_PUMP_DISTANCE: float = 0.09
const SPAS12_SHELL_START := Vector3(-0.16, -0.18, 0.08)
const SPAS12_SHELL_PORT := Vector3(0.05, -0.02, -0.06)
const SPAS12_SHELL_HAND_OFFSET := Vector3(-0.015, 0, 0)
const SPAS12_SHELL_RETRIEVE_PHASE: float = 0.18
const SPAS12_SHELL_INSERT_PHASE: float = 0.78
const SPAS12_RELOAD_LIFT := Vector3(0, 0.025, -0.02)
const EM120R_REAR_BREECH := Vector3(0, 0, 0.587)
const EM120R_REAR_START_NOSE := Vector3(0, 0.08, 0.65)
const EM120R_REAR_MISSILE_GRIP := Vector3(-0.036765660, -0.013928436, 0.39881194)
const EM120R_REAR_CLEARANCE: float = 0.04
const EM120R_REAR_SHOW_PHASE: float = 0.08
const EM120R_REAR_CONTACT_PHASE: float = 0.18
const EM120R_REAR_ALIGN_PHASE: float = 0.42
const EM120R_REAR_RELEASE_PHASE: float = 0.80
const EM120R_REAR_SEAT_PHASE: float = 0.90
const EM120R_REAR_HAND_CLEARANCE := Vector3(-0.14, -0.12, 0)
const EM120R_REAR_SHOULDER_DIRECTION := Vector3(0, -1, 1)
const SPAS12_ADS_FOV: float = 65.0
const SPAS12_PICKUP_TRIGGER_OFFSET := Vector3(0, -1.0, 0.65) ## 枪留高层货架，触发区下探至玩家可接近处
const SPAS12_SUPPORT_WRIST_ADS := Vector3(0.04, -0.08, -0.10)
const SPAS12_RIGHT_WRIST_ADS := Vector3(0.08, -0.14, 0.36)
const SPAS12_RIGHT_ELBOW_ADS := Vector3(0.22, -0.32, 0.18)

# ===== EM-40G「滚雷」下挂榴弹模块（2026-10-22 机主裁决：并入 EM-68A 第四射击档，
#       X 键闭环 全自动→半自动→三发点射→榴→全自动；旧 3 号位 RPG 火箭筒整体退役）=====
# 设定出处（E系列电磁轻武器-概念图谱）：直射档=EC-40P「破垒」全功率平直弹道；
# 模块自带 6 发弹匣即雷池（换匣即换电）；「闸不合，榴不发」=榴档与实弹击发互斥；
# 投射物场景复用 rpg_projectile.tscn（抛物线/爆炸/碉堡结算链路原样接管）。
const GRENADE_AMMO: int = 200 ## EC-40 共享雷池（下挂直接消耗；EM-40T-1 作为 20 发弹匣的共享备弹）
const GRENADE_FIRE_INTERVAL: float = 0.8 ## 榴弹击发间隔 s（合闸-复位节奏，半自动边沿触发）
const GRENADE_PROJECTILE_SPEED: float = 90.0 ## 直射档初速 u/s（全功率平直弹道）
const GRENADE_GRAVITY: float = 2.0 ## 直射档微下坠（远小于旧火箭 9.8，弹道平直）
const GRENADE_MAX_RANGE: float = 200.0 ## 最大射程 u
const GRENADE_EXPLODE_RADIUS: float = 15.0 ## 伤害半径上限 m（2026-10-25 机主裁决：10→15；超 15m 无伤，球形查询天然截断）
const GRENADE_EXPLODE_KILL_RADIUS: float = 10.0 ## 必杀半径 m（2026-10-25 机主裁决：5→10，圈内定值直伤）
const GRENADE_EXPLODE_KILL_DAMAGE: float = 750.0 ## 必杀圈伤害（2026-10-25 机主裁决：9999→750 定值；杀伤圈内无视建筑墙体——球形查询本无遮挡，属既定口径非缺陷）
const GRENADE_EXPLODE_FALLOFF_FACTOR: float = 0.5 ## 10–15m 过渡带伤害系数（750×0.5=375 半伤，2026-10-25 机主裁决新口径）
const GRENADE_EXPLODE_DAMAGE: float = 750.0 ## 爆炸基准伤害（2026-10-25 机主裁决：450→750，与必杀圈同基，带内吃 falloff 半伤；附带碉堡特杀半径随上限扩至 15+bonus）
const NIGHT_VISION_AMBIENT_COLOR: Color = Color(0.72, 0.9, 0.78) ## 夜视仪环境光抬升色（2026-10-25 机主指令：vm-shot 取证全图提亮融入夜视仪——真实夜视仪=把黑夜放大到看清环境，屏幕增益之上叠加真实环境光；青绿偏白与磷光色调同系）
const NIGHT_VISION_AMBIENT_ENERGY: float = 1.6 ## 夜视仪环境光抬升强度（对齐 vm-shot fill 取证量级 1.5，略增）
const GRENADE_BUNKER_RADIUS_BONUS: float = 5.0 ## 对碉堡判定半径加成（破垒本职，沿用 L1593）
const GRENADE_SELF_DAMAGE: bool = false ## 爆炸对玩家零伤害（沿用网页版口径 L1645-1657）
const GRENADE_EXPLODE_BELOW_Y: float = -10.0 ## 坠地自爆高度（L3172）
const GRENADE_LAUNCH_FORWARD: float = 0.7 ## 出膛点沿枪管前移量 m（下挂发射器位于护木前下方，
## 从武器原点直接出膛会显得"从手臂处发射"）
const GRENADE_LAUNCH_DROP: float = 0.15 ## 出膛点下移量 m（发射管挂在枪管下方）

# ===== 敌人（G2 门禁基准）=====
const INFANTRY_HP: float = 150.0 ## 步兵血量（2026-10-22 机主裁决 50→150：寄生体宿主强化，步枪 75 伤 2 发/手枪 45 伤 4 发击杀；原 50 为网页版 L1139 值）
const INFANTRY_SPEED: float = 3.5 ## 步兵移动速度 u/s（L1140）
const INFANTRY_COVER_SPEED_FACTOR: float = 1.2 ## 找掩体加速（L1140）
const INFANTRY_PATROL_SPEED: float = 2.0 ## 巡逻速度 u/s（L1210）
const INFANTRY_DETECT_RADIUS: float = 25.0 ## 索敌半径（2026-10-20 机主裁决：80→25——主街直线视廊下 80m 等于半图索敌，夜战被锁定却看不见敌人；25m 契合寄生体近战定位）
const INFANTRY_ENGAGE_INTERVAL: float = 2.6 ## 交战孢子投掷间隔 s——对齐 attack 剪辑 2.63s（2026-10-25 机主指令：音效又快又响且与动作不搭，根因=0.25s 间隔下 2.63s 动画/1.48s 音效反复重启叠播；对齐后单发慎重投掷，参考《针锋相对》戈诺姆远程孢子）
const INFANTRY_PEEK_INTERVAL: float = 2.6 ## 探头孢子投掷间隔 s（同上对齐剪辑；探头窗口 0.5-1.0s 内至多一发）
const INFANTRY_DAMAGE: float = 5.0 ## 单发伤害（L1424）
const INFANTRY_BURST_MIN: int = 3 ## 点射下限（L1157）
const INFANTRY_BURST_MAX: int = 5 ## 点射上限（L1157）
const ALERT_ON_DEATH_RADIUS: float = 40.0 ## 同伴死亡警戒半径（L3042）
# —— 步兵行为调参组（G2 冻结自 W3 脚本常量迁入，出处行为 W3 报告标注）——
const INFANTRY_PATROL_RADIUS: float = 40.0 ## 巡逻半径
const INFANTRY_ALERT_DELAY: float = 1.0 ## 警戒延迟 s
const INFANTRY_COVER_SEARCH_RADIUS: float = 25.0 ## 掩体搜索半径
const INFANTRY_COVER_MIN_DIST: float = 8.0 ## 掩体最小间距
const INFANTRY_COVER_ARRIVE_DIST: float = 1.5 ## 到达掩体判定距离
const INFANTRY_COVER_SCORE_DIST: float = 0.5 ## 掩体评分·距离权重
const INFANTRY_COVER_SCORE_ALIGN: float = 10.0 ## 掩体评分·朝向权重
const INFANTRY_PEEK_FIRE_DELAY: float = 0.5 ## 探头开火延迟 s
const INFANTRY_PEEK_CYCLE_TIME: float = 1.0 ## 探头周期 s
const INFANTRY_PEEK_REPEAT_CHANCE: float = 0.3 ## 重复探头概率
const INFANTRY_PEEK_ENGAGE_TIME: float = 1.5 ## 探头转交战时长 s
const INFANTRY_ALERT_ENGAGE_TIME: float = 2.0 ## 警戒转交战时长 s
const INFANTRY_ENGAGE_APPROACH_DIST: float = 10.0 ## 交战逼近/孢子分界（2026-10-22 机主裁决：10m 内优先近身，孢子带 10–15m）
const INFANTRY_ENGAGE_BACKOFF_DIST: float = 5.0 ## 交战后退距离（2026-10-22 起脚本不再消费——寄生体近战定位不后退；常量保留护 G2 断言）
const INFANTRY_SPORE_RANGE: float = 15.0 ## 孢子投掷命中上限距离 m（2026-10-22 机主裁决：10→15；须已发现玩家[视线确认]才出手，盲射旁路退役）
const INFANTRY_SPORE_SPEED: float = 14.0 ## 孢子团飞行初速 m/s（2026-10-25 机主指令：远程孢子须有真实飞行投射物，15m 带 ~1.1s 飞行可闪避）
const INFANTRY_SPORE_GRAVITY: float = 9.8 ## 孢子团下坠 m/s²（戈诺姆式弧线投掷手感）
const INFANTRY_SPORE_MAX_RANGE: float = 25.0 ## 孢子团超程自毁 m
const INFANTRY_MELEE_RANGE: float = 2.2 ## 近身攻击出手距离 m（2026-10-22 机主裁决：寄生体主战手段）
const INFANTRY_MELEE_DAMAGE: float = 15.0 ## 近身攻击伤害（重击，高于孢子 5.0）
const INFANTRY_MELEE_INTERVAL: float = 1.0 ## 近身攻击间隔 s
const SPORE_HUSK_HP: float = 30.0
const SPORE_HUSK_SPEED: float = 2.0
const SPORE_HUSK_ALERT_RANGE: float = 12.0
const SPORE_HUSK_LEAP_MIN: float = 2.0
const SPORE_HUSK_LEAP_MAX: float = 7.0
const SPORE_HUSK_LEAP_HORIZONTAL: float = 7.5
const SPORE_HUSK_LEAP_VERTICAL: float = 5.2
const SPORE_HUSK_DAMAGE: float = 10.0
const SPORE_HUSK_COOLDOWN: float = 1.4
const HULKING_HOST_HP: float = 300.0
const HULKING_HOST_SPEED: float = 1.8
const HULKING_HOST_MELEE_RANGE: float = 2.8
const HULKING_HOST_WINDUP: float = 1.15
const HULKING_HOST_RECOVER: float = 1.0
const HULKING_HOST_DAMAGE: float = 35.0
const HULKING_HOST_COOLDOWN: float = 2.0
const HULKING_HOST_MODEL_YAW_OFFSET: float = -PI * 0.5 ## GLB 模型本地 +X 朝前，转为 Godot -Z 前进
const HULKING_HOST_SMASH_SOUND_PITCH: float = 0.65
const INFANTRY_LOSE_SIGHT_TIME: float = 4.0 ## 脱战时长 s（2026-10-20 机主裁决新增：持续丢失视线超过该时长 → 回巡逻，杜绝"隔墙锁定后无限追打"）
const INFANTRY_FALLBACK_COVER_DIST: float = 5.0 ## 撤退掩体距离
const INFANTRY_COMPANION_COVER_DIST: float = 5.0 ## 同伴掩体距离
const INFANTRY_COMPANION_ENGAGE_TIME: float = 10.0 ## 同伴交战时长 s

const MG_HP: float = 80.0 ## 机枪手血量（L908）
const MG_FIRE_INTERVAL: float = 0.06 ## 射速 s/发 ≈ 1000 RPM（L910）
const MG_DAMAGE_MIN: float = 6.0 ## 单发伤害下限（L1027）
const MG_DAMAGE_RAND: float = 3.0 ## 单发伤害随机浮动（L1027）
const MG_MAG: int = 100 ## 弹匣（L914）
const MG_RELOAD_TIME: float = 10.0 ## 换弹 s（L918）
const MG_RANGE: float = 100.0 ## 射程（L911）

const BUNKER_MG_FIRE_INTERVAL: float = 0.08 ## 碉堡机枪射速（L1822）
const BUNKER_MG_DAMAGE_MIN: float = 5.0 ## 碉堡机枪伤害下限（L1822）
const BUNKER_MG_DAMAGE_RAND: float = 3.0 ## 碉堡机枪伤害随机浮动（同公式 L1027/L1822）
const BUNKER_MG_RANGE: float = 60.0 ## 碉堡机枪射程（L1823）
const BUNKER_PRONE_CEASEFIRE_TIME: float = 7.0 ## 趴下即停火的安全窗口时长 s；窗口耗尽或起身立即恢复射击（L941-949/L964；G2 裁决采 A 语义，2026-07-21 机主签字）

const SNIPER_HP: float = 80.0 ## 狙击手血量（继承，L1050）
const SNIPER_FIRE_INTERVAL: float = 4.0 ## 射击间隔 s（L1057）
const SNIPER_MAG: int = 5 ## 弹匣（L1058）
const SNIPER_RELOAD_TIME: float = 5.0 ## 换弹 s（L1060）
const SNIPER_RANGE: float = 150.0 ## 射程（L1056）
const SNIPER_TOWER_HEIGHT: float = 12.0 ## 狙击塔高（L2254）
const SNIPER_LETHAL: bool = true ## 狙杀开关（§6 死代码裁决：参数化保留秒杀为默认，G2 试玩可切 8 伤档）
const SNIPER_KILL_DAMAGE: float = 999.0 ## 狙杀伤害（lethal=true）
const SNIPER_NON_LETHAL_DAMAGE: float = 8.0 ## 普通弹伤害（lethal=false，L3678 死代码启用量）

const EVENT_SNIPER_COUNT: int = 2 ## 事件狙击手数量（L3671）
const EVENT_SNIPER_INTERVAL: float = 5.0 ## 射击间隔 s（L3677）
const EVENT_SNIPER_MAG: int = 3 ## 弹匣（L3677）
const EVENT_SNIPER_RANGE: float = 80.0 ## 射程（L3677）
const EVENT_SNIPER_SPAWN_DELAY: float = 3.0 ## 呼机后刷出延迟 s（L3671）
const EVENT_SNIPER_SPAWN_DIST: float = 35.0 ## 距撤离点刷出距离（L3673）
## 事件狙击手 lethal 死代码（L3678）→ 已裁决：契约化 SNIPER_LETHAL 开关，默认 true 保留秒杀，G2 试玩可切 8 伤档

# ===== 地图关键点（L452-460）=====
const MAP_SIZE: Vector2 = Vector2(200.0, 120.0) ## 地图尺寸
const START_POS: Vector2 = Vector2(90.0, -55.0) ## 出生点（东）
const EXTRACT_POS: Vector2 = Vector2(-60.0, 40.0) ## 撤离点
const BUNKER_POS: Vector2 = Vector2(-50.0, 40.0) ## 碉堡
const CABIN_POS: Vector2 = Vector2(-70.0, 0.0) ## 通讯小屋
const SNIPER_POS: Vector2 = Vector2(80.0, 0.0) ## 狙击塔
const MG1_POS: Vector2 = Vector2(12.0, -20.0) ## 沙袋机枪 1
const MG2_POS: Vector2 = Vector2(12.0, 20.0) ## 沙袋机枪 2

# ===== 任务 =====
const HELI_COUNTDOWN: float = 60.0 ## 坚守时长 s（L327）
const HELI_UNLOCK_EXTRACT_DIST: float = 15.0 ## 撤离点解锁距离（L3749）
const HELI_UNLOCK_CABIN_DIST: float = 6.0 ## 通讯小屋解锁距离（L3749）
const EXTRACT_BOARD_RADIUS: float = 5.0 ## 登机判定半径（L3694）

# ===== 音频总线音量（L392）=====
const VOL_SFX: float = 0.8 ## 音效组
const VOL_LOOP: float = 0.4 ## 循环组（脚步/直升机）
const VOL_AMBIENT: float = 0.25 ## 环境组
const SFX_PITCH_JITTER: float = 0.1 ## 枪声音高抖动 ±10%（L392）

# ===== 武器选择分类（2026-10-29 机主裁决：Half-Life 数字类别 + 同键循环 + 滚轮）=====
const WEAPON_CATEGORIES: Array = [
	{"number": 1, "name": "手枪", "weapons": [&"pistol", &"magnum", &"g17"]},
	{"number": 2, "name": "冲锋枪", "weapons": [&"smg", &"em57s2", &"mpx"]},
	{"number": 3, "name": "突击 / DMR", "weapons": [&"rifle", &"dmr", &"em86b", &"em86d"]},
	{"number": 4, "name": "霰弹 / 狙击", "weapons": [&"shotgun", &"spas12", &"em12g2", &"em86s", &"em127g"]},
	{"number": 5, "name": "机枪", "weapons": [&"lmg", &"em86m", &"em127m"]},
	{"number": 6, "name": "爆破重火力", "weapons": [&"em40t1", &"em120r"]},
]
const WEAPON_SCROLL_ORDER: Array[StringName] = [&"pistol", &"magnum", &"g17", &"smg", &"em57s2", &"mpx", &"rifle", &"dmr", &"em86b", &"em86d", &"shotgun", &"spas12", &"em12g2", &"em86s", &"em127g", &"lmg", &"em86m", &"em127m", &"em40t1", &"em120r"]
const WEAPON_SELECTOR_HOLD_TIME: float = 1.6

# ===== UI 反馈动效（G2 冻结自 W5 脚本常量迁入）=====
const CROSSHAIR_HIT_SCALE: float = 1.3 ## 命中准星放大倍率
const CROSSHAIR_HEADSHOT_SCALE: float = 1.8 ## 爆头准星放大倍率
const CROSSHAIR_PULSE_HOLD: float = 0.06 ## 准星放大停留 s
const MESSAGE_HOLD_TIME: float = 0.8 ## 中央飘字停留 s
const DAMAGE_FLASH_PEAK_ALPHA: float = 0.35 ## 受击红晕峰值透明度
const DAMAGE_FLASH_FADE_TIME: float = 0.4 ## 受击红晕淡出 s
const KILL_FEEDBACK_HOLD_TIME: float = 0.6 ## 击杀反馈停留 s

# ===== 表现层三件套（§11.1 A 方案，2026-08-19 机主裁决纳入 G4 前施工，蜂后冻结新增）=====
const TRACER_LIFETIME: float = 0.06 ## 敌弹曳光驻留 s
const TRACER_WIDTH: float = 0.03 ## 曳光束粗细 u
const MUZZLE_FLASH_LIFETIME: float = 0.05 ## 枪口火光驻留 s
const MUZZLE_FLASH_ENERGY: float = 2.0 ## 枪口火光 OmniLight 能量
const DAMAGE_ARC_SHOW_TIME: float = 1.0 ## 受击方向指示弧显示 s

# ===== 玩家弹道特效（2026-10-19 机主立项：弹坑贴花 + 金属溅射火星 + 微弱青蓝枪口焰）=====
const PLAYER_MUZZLE_OFFSET: float = 0.55 ## 枪口焰沿枪管前移量 m（视图模型炮口近似位）
const PLAYER_MUZZLE_FLASH_ENERGY: float = 0.7 ## 枪口焰 OmniLight 能量（微弱口径，电磁武器青蓝焰）
const PLAYER_MUZZLE_FLASH_RANGE: float = 2.5 ## 枪口焰光照半径 m
const BULLET_DECAL_SIZE: float = 0.14 ## 弹坑贴花投影尺寸 m
const BULLET_DECAL_POOL: int = 64 ## 弹坑池上限（FIFO 复用最旧，防贴花无限累积）
const BULLET_DECAL_LIFETIME: float = 60.0 ## 每次真实命中起算，复用重置；60秒后隐藏回收
const BULLET_DECAL_DEPTH: float = 0.4 ## Decal本地Y投影厚度，覆盖简化车辆碰撞盒与真实表皮间距
const BULLET_DECAL_OFFSET: float = 0.002 ## 沿命中法线的中心偏移 m
const BULLET_DECAL_NORMAL_FADE: float = 0.5 ## 抑制背向/侧向表面的串投射
const BULLET_SPARK_COUNT: int = 8 ## 金属命中火花粒子数（2026-10-22 机主裁决：颗数不减，体积大幅缩小）
const BULLET_SPARK_LIFETIME: float = 0.18 ## 火花粒子寿命 s
const BULLET_SPARK_VELOCITY_MIN: float = 0.8 ## 火花初速下限 m/s
const BULLET_SPARK_VELOCITY_MAX: float = 1.6 ## 火花初速上限 m/s
const BULLET_SPARK_SCALE_MIN: float = 0.0015 ## 火花粒径下限 m（微火星口径，勿放大）
const BULLET_SPARK_SCALE_MAX: float = 0.0035 ## 火花粒径上限 m
const BULLET_SPARK_SPREAD: float = 30.0 ## 火花喷射散布角 °
## 金属表面关键词（命中物祖先节点名含其一即溅火星；自行车/铁护栏/阳台栏杆/篮架等）
const BULLET_METAL_KEYWORDS: PackedStringArray = ["bicycle", "fence", "railing", "balcony", "gate", "barrier", "hoop", "shutter"]

# ===== 榴弹爆炸特效（2026-10-22 机主立项：替换灰盒占位橙球，程序化多层组合——
#       爆闪/火球/烟/火花碎屑/冲击波环/地面焦痕；explosion_fx.gd 消费，零第三方资产）=====
const EXPLOSION_FX_POOL: int = 3 ## 同屏爆炸特效实例池（连爆轮转复用）
const EXPLOSION_FX_FLASH_ENERGY: float = 120.0 ## 爆闪 OmniLight 峰值能量（夜战照亮街面）
const EXPLOSION_FX_FLASH_RANGE: float = 18.0 ## 爆闪光照半径 m
const EXPLOSION_FX_FLASH_LIFETIME: float = 0.35 ## 爆闪衰减时长 s
const EXPLOSION_FX_FIREBALL_SIZE: float = 7.0 ## 火球峰值直径 m
const EXPLOSION_FX_FIREBALL_LIFETIME: float = 0.55 ## 火球驻留 s（白炽→橙→暗红褪色）
const EXPLOSION_FX_FIREBALL_QUADS: int = 3 ## 火球错角叠加面片数（伪体积感）
const EXPLOSION_FX_SMOKE_COUNT: int = 7 ## 烟团面片数
const EXPLOSION_FX_SMOKE_SIZE: float = 5.0 ## 烟团峰值直径 m
const EXPLOSION_FX_SMOKE_LIFETIME: float = 2.2 ## 烟团驻留 s（上升膨胀淡出）
const EXPLOSION_FX_SMOKE_RISE: float = 2.5 ## 烟团上升速度 m/s
const EXPLOSION_FX_SPARK_COUNT: int = 28 ## 爆炸火花/碎屑粒子数
const EXPLOSION_FX_SPARK_LIFETIME: float = 0.8 ## 火花寿命 s
const EXPLOSION_FX_SPARK_VELOCITY_MIN: float = 6.0 ## 火花初速下限 m/s
const EXPLOSION_FX_SPARK_VELOCITY_MAX: float = 16.0 ## 火花初速上限 m/s
const EXPLOSION_FX_SPARK_SCALE_MIN: float = 0.03 ## 火花粒径下限 m（爆炸级，大于子弹微火星）
const EXPLOSION_FX_SPARK_SCALE_MAX: float = 0.09 ## 火花粒径上限 m
const EXPLOSION_FX_RING_SIZE: float = 12.0 ## 地面冲击波环峰值直径 m
const EXPLOSION_FX_RING_LIFETIME: float = 0.45 ## 冲击波环扩散时长 s
const EXPLOSION_FX_SCORCH_SIZE: float = 6.0 ## 地面焦痕贴花直径 m
const EXPLOSION_FX_SCORCH_POOL: int = 8 ## 焦痕池上限（FIFO 复用，同弹坑机制）
const EXPLOSION_FX_SCORCH_DEPTH: float = 0.4 ## 真实撞击表面本地Y投影厚度 m
const EXPLOSION_FX_SCORCH_OFFSET: float = 0.002 ## 沿实际表面法线偏移 m
const EXPLOSION_FX_SCORCH_LIFETIME: float = 60.0 ## 炸痕隐藏回收；复用重新计时
const EXPLOSION_FX_SCORCH_NORMAL_FADE: float = 0.5
const EXPLOSION_FX_SCORCH_MAX_HEIGHT: float = 2.5 ## 仅控制旧地面冲击波环；焦痕由真实表面事件决定

# ===== 氛围：浓雾能见度定标（P2，文档10 §1-P2 散射/消光分离思想）=====
# 定标法：先定目标能见度，再反推消光系数，而非直接手调 density
const FOG_VISIBILITY_TARGET_M: float = 30.0 ## 浓雾目标能见度 m（2% 对比度距离，浓雾部队氛围）
const FOG_DENSITY: float = 0.130 ## 指数雾消光密度 = -ln(0.02)/30 ≈ 0.130（由上行派生，勿独立改）
const FOG_LIGHT_COLOR := Color(0.55, 0.58, 0.62) ## 雾色（阴天灰蓝）
const FOG_SUN_SCATTER: float = 0.3 ## 雾中阳光散射强度

# ===== 夜景：蓝调时刻 + 减薄夜雾（street_test 夜景化；夜里本身能见度低，雾减薄）=====
# 机主护栏（2026-09-27）：夜雾能见度不得低于 60m、density 不得高于 0.065，
# fog_sky_affect 不得上调——雾绝不能掩盖远处 CBD 夜景天际线
const NIGHT_FOG_VISIBILITY_TARGET_M: float = 60.0 ## 夜雾目标能见度 m（下限护栏，勿上调 density）
const NIGHT_FOG_DENSITY: float = 0.065 ## = -ln(0.02)/60 ≈ 0.065（由上行派生，勿独立改）
const NIGHT_FOG_LIGHT_COLOR := Color(0.10, 0.12, 0.18) ## 夜雾色（深蓝灰）
const NIGHT_FOG_SUN_SCATTER: float = 0.1 ## 月光散射弱于日光
const NIGHT_FOG_SKY_AFFECT: float = 0.3 ## 雾对天空的影响（压低防灰洗：雾色灰蓝会把靛蓝夜空洗灰，
## 天际线幕布卡 fog_disabled 不吃雾，天空若吃满雾就会出现"两个夜空"）

# ===== 街区图昼间预设（street_day_night_driver 专用；契约申请 1，蜂后冻结 2026-10-07）=====
# c1m1 剧情态恒为夜，DAY 态仅美术对照与未来 c1m2 复用；白天雾直接复用上方 FOG_* 契约，不新增
const STREET_DAY_SKY_TOP_COLOR := Color(0.35, 0.55, 0.85) ## 昼间天空顶色（蓝调→昼间蓝）
const STREET_DAY_SKY_HORIZON_COLOR := Color(0.65, 0.72, 0.80) ## 地平线雾霭色
const STREET_DAY_AMBIENT_ENERGY: float = 1.0 ## Sky 环境光能量（夜 0.38 → 昼）
const STREET_DAY_SUN_COLOR := Color(1.0, 0.95, 0.85) ## 日光色
const STREET_DAY_SUN_ENERGY: float = 1.2 ## 日光能量
const STREET_DAY_SKYLINE_EMISSION_SCALE: float = 0.15 ## 天际线窗灯昼间衰减因子（白天亮窗不可信）

# ===== CBD 远景天际线（多环带 LOD 几何，skyline_builder.gd 消费；确定性种子）=====
const SKYLINE_SEED: int = 20260927 ## 布局随机种子（改则天际线重排）
const SKYLINE_RING_INNER_M: float = 180.0 ## 内环半径 m（低模塔楼 + 亮窗）
const SKYLINE_RING_OUTER_M: float = 420.0 ## 外环半径 m（剪影体块）
const SKYLINE_RING_INNER_JITTER_M: float = 40.0 ## 内环半径抖动 ±m
const SKYLINE_RING_OUTER_JITTER_M: float = 70.0 ## 外环半径抖动 ±m
const SKYLINE_TOWER_COUNT_INNER: int = 36 ## 内环塔楼数
const SKYLINE_TOWER_COUNT_OUTER: int = 18 ## 外环剪影数
const SKYLINE_LIT_RATIO: float = 0.40 ## 亮窗比例（内环）
const SKYLINE_LIT_RATIO_OUTER: float = 0.22 ## 亮窗比例（外环，更稀疏更暗）
const SKYLINE_VISTA_GAP_DEG: float = 15.0 ## 主街轴线 ±扇区不放内环塔楼（留视线走廊）
const SKYLINE_BEACON_MIN_HEIGHT_M: float = 80.0 ## 高于此高度的塔楼顶部亮航空障碍红灯

# --- 天际线 v2 真实化（参考广州珠江新城 CBD 夜景照片特征；skyline_builder 消费）---
const SKYLINE_PODIUM_RATIO: float = 0.50 ## 内环塔楼带裙楼底座的比例
const SKYLINE_PODIUM_HEIGHT_M: float = 12.0 ## 裙楼高度 m（此高度以下商业照明更亮更暖）
const SKYLINE_DARK_FLOOR_RATIO: float = 0.22 ## 整层熄灯（无人加班层）的出现概率
const SKYLINE_NEON_RATIO: float = 0.55 ## 带 LED 轮廓/竖向灯带的塔楼比例（中国 CBD 特色）
const SKYLINE_MEDIA_RATIO: float = 0.12 ## 媒体立面（整楼缓慢变色）塔楼比例，仅 >90m 启用
const SKYLINE_ANTENNA_RATIO: float = 0.50 ## >70m 塔楼带天线桅杆的比例
## 轴线地标塔：[半径m, 高度m, 相对 -Z 轴角偏移rad]——街道尽头视线走廊的远景焦点
const SKYLINE_AXIS_TOWERS := [[320.0, 150.0, -0.03], [470.0, 185.0, 0.05]]
const SKYLINE_AXIS_BRIGHTNESS: float = 0.75 ## 地标塔亮度（远距离衰减感）

# --- 天际线 v3：AI 贴图化（立面贴图塔楼 + 全景幕布卡环带，贴图见 assets/textures/skyline/）---
const SKYLINE_CARD_COUNT: int = 8 ## 全景幕布卡数量（环绕一周）
const SKYLINE_CARD_RADIUS_M: float = 600.0 ## 幕布卡环半径 m
const SKYLINE_CARD_WIDTH_M: float = 640.0 ## 单卡宽 m（相邻卡交叠羽化）
const SKYLINE_CARD_HEIGHT_M: float = 260.0 ## 单卡高 m

# ===== 街道布景层（P2，文档10 §1-P2 props/dressing；street_builder 消费）=====
const STREET_DRESS_SEED: int = 20260927 ## 布景随机种子（tint 抖动/空调/店面roll点）
const STREET_TINT_JITTER: float = 0.10 ## 楼体 albedo 抖动幅度 ±（去复制粘贴感，文档10 tint 纪律）
const WIRE_SPACING_M: float = 10.0 ## 跨街电线纵向间距 m（带抖动）
const WIRE_SAG_M: float = 0.9 ## 悬链线垂度基准 m（±50% 抖动）
const WIRE_HEIGHT_MIN_M: float = 5.5 ## 电线净空最低 m
const WIRE_HEIGHT_MAX_M: float = 8.0 ## 电线净空最高 m
const AC_UNIT_RATIO: float = 0.35 ## 窗户开间挂空调外机的概率
const SHOPFRONT_RATIO: float = 0.50 ## 一层非中间开间改卷帘门商铺的概率（中间开间恒为商铺）

# ===== 可进入建筑试点（2026-09-27 机主裁决：照明 B 方案——闪烁应急灯+手电；
#       城中村断电但偶有备用电的设定，应急灯兼做上楼引导）=====
const EMERGENCY_LIGHT_COLOR := Color(1.0, 0.55, 0.25) ## 应急灯暖橙（备用电瓶灯质感）
const EMERGENCY_LIGHT_ENERGY: float = 1.6 ## 应急灯亮度基准
const EMERGENCY_LIGHT_RANGE: float = 7.5 ## 应急灯照明半径 m
const EMERGENCY_FLICKER_MIN_S: float = 0.05 ## 闪烁最短间隔 s
const EMERGENCY_FLICKER_MAX_S: float = 0.35 ## 闪烁最长间隔 s
const EMERGENCY_DARK_PROB: float = 0.15 ## 每次跳变为长灭（接触不良）的概率
const EMERGENCY_DIM_RATIO: float = 0.25 ## 暗态亮度比例（不完全熄灭，留底光）

# ===== HUD 圆形小地图（2026-10-21 机主立项：灯塔 ASI 战术探测视图；
#       地形为离线俯视渲染底图，随玩家位置实时推进；红点=敌人（ASI 探测信息））=====
const MINIMAP_SIZE_PX: int = 176 ## 小地图直径 px
const MINIMAP_RANGE_M: float = 55.0 ## 显示半径 m（以玩家为圆心）
const MINIMAP_MAP_TEXTURE: String = "res://assets/ui/minimap_street.png" ## 俯视地形底图（tools/capture_minimap.gd 离线渲染）
const MINIMAP_MAP_CALIB: String = "res://assets/ui/minimap_street.json" ## 世界→像素标定（与底图同批生成）
const DISTRICT_MINIMAP_MAP_TEXTURE: String = "res://assets/ui/minimap_district_b.png" ## 第二关仓库俯视底图
const DISTRICT_MINIMAP_MAP_CALIB: String = "res://assets/ui/minimap_district_b.json" ## 第二关世界→像素标定
const RANGE_MINIMAP_MAP_TEXTURE: String = "res://assets/ui/minimap_range.png" ## 综合靶场俯视底图
const RANGE_MINIMAP_MAP_CALIB: String = "res://assets/ui/minimap_range.json" ## 综合靶场世界→像素标定
const MINIMAP_ENEMY_COLOR := Color(1.0, 0.28, 0.22, 0.95) ## 敌人红点（ASI 威胁标记）
const MINIMAP_PLAYER_COLOR := Color(0.45, 0.95, 1.0, 1.0) ## 玩家箭头（青蓝，HUD 主色）
const MINIMAP_BORDER_COLOR := Color(0.4, 0.95, 1.0, 0.55) ## 圆环边框
const MINIMAP_BG_COLOR := Color(0.02, 0.06, 0.09, 0.78) ## 底图未覆盖区域底色
const MINIMAP_ENEMY_DOT_R: float = 3.0 ## 红点半径 px

# ===== 第一关材质样板与主干道路灯（2026-11-09，dev1 试玩）=====
const STREET_SAMPLE_Z_MIN: float = -25.0
const STREET_SAMPLE_Z_MAX: float = 30.0
const STREET_SAMPLE_FULL_SCENE: bool = true ## 完整第一关街区覆面；原Z范围保留作局部基线取证
const STREET_SAMPLE_SURFACE_OFFSET: float = 0.003 ## 覆面离原路面 3mm，碰撞仍走原几何
const STREET_SAMPLE_PLASTER_TILE_M: float = 2.23 ## 扫描抹灰的实际采样宽度
const STREET_SAMPLE_ASPHALT_TILE_M: float = 3.0
const STREET_SAMPLE_METAL_TILE_M: float = 1.0
const STREET_SAMPLE_NORMAL_SCALE: float = 1.0
const STREET_SAMPLE_REFLECTION_SIZE := Vector3(20.0, 9.0, 55.0)
const STREET_SAMPLE_REFLECTION_ORIGIN := Vector3(0.0, 3.0, 2.5)
const STREET_LAMP_START_Z: float = 46.0
const STREET_LAMP_SPACING_M: float = 24.0
const STREET_LAMP_COUNT_PER_SIDE: int = 6
const STREET_LAMP_X_M: float = 5.5
const STREET_LAMP_HEIGHT_M: float = 5.2
const STREET_LAMP_ARM_M: float = 1.0
const STREET_LAMP_POLE_RADIUS_M: float = 0.055
const STREET_LAMP_LIGHT_COLOR := Color(1.0, 0.77, 0.48)
const STREET_LAMP_ENERGY: float = 4.0
const STREET_LAMP_RANGE_M: float = 14.0
const STREET_LAMP_ANGLE_DEG: float = 65.0
const STREET_LAMP_FADE_BEGIN_M: float = 32.0
const STREET_LAMP_FADE_LENGTH_M: float = 12.0
const STREET_LAMP_SHADOW_FADE_M: float = 24.0

# ===== 9x19传统武器（2026-11-11机主批准A；MPX额外三发点射由机主指定）=====
# 容量/MPX循环射速按公开规格；半自动输入上限、备弹、换弹、散布、后坐和射线预算为游戏近似。
const AMMO_DMG_9X19: float = 30.0
const AMMO_9X19_RESERVE: int = 510
const G17_DMG_HEAD_FACTOR: float = 2.0
const G17_DMG_VS_SNIPER: float = 30.0
const G17_MAG: int = 17
const G17_FIRE_INTERVAL: float = 0.15
const G17_SEMI_FIRE_INTERVAL: float = 0.15
const G17_RELOAD_TIME: float = 2.0
const G17_RANGE: float = 80.0
const G17_SPREAD_HIP: float = 0.009
const G17_SPREAD_PRONE: float = 0.0045
const G17_SPREAD_AIM: float = 0.0015
const G17_RECOIL_PITCH: float = 0.006
const G17_RECOIL_VIEW_OFFSET: float = 0.08
const G17_RECOIL_DECAY: float = 0.82
const G17_RECOIL_RECOVER_RATE: float = 8.0
const G17_RECOIL_VIEW_ROT: float = 2.0
const G17_RECOIL_VIEW_Y_FACTOR: float = 0.02
const G17_RECOIL_VIEW_Z_FACTOR: float = 0.04
const G17_ADS_FOV: float = 65.0
const G17_SOUND_PITCH: float = 1.0
const MPX_DMG_HEAD_FACTOR: float = 2.0
const MPX_DMG_VS_SNIPER: float = 30.0
const MPX_MAG: int = 30
const MPX_FIRE_INTERVAL: float = 60.0 / 850.0
const MPX_BURST_FIRE_INTERVAL: float = 60.0 / 850.0
const MPX_SEMI_FIRE_INTERVAL: float = 0.15
const MPX_RELOAD_TIME: float = 2.5
const MPX_RANGE: float = 120.0
const MPX_SPREAD_HIP: float = 0.006
const MPX_SPREAD_PRONE: float = 0.003
const MPX_SPREAD_AIM: float = 0.001
const MPX_RECOIL_PITCH: float = 0.0035
const MPX_RECOIL_VIEW_OFFSET: float = 0.06
const MPX_RECOIL_DECAY: float = 0.84
const MPX_RECOIL_RECOVER_RATE: float = 8.0
const MPX_RECOIL_VIEW_ROT: float = 2.0
const MPX_RECOIL_VIEW_Y_FACTOR: float = 0.02
const MPX_RECOIL_VIEW_Z_FACTOR: float = 0.04
const MPX_ADS_FOV: float = 65.0
const MPX_SOUND_PITCH: float = 1.0

# ===== 第一人称模型近墙保护（视觉深度压缩；武器根节点朝向/射程保持单位尺度）=====
const VIEWMODEL_WALL_MARGIN: float = 0.02 ## 可见模型与场景实体保留 2cm 间距
const VIEWMODEL_WALL_MIN_SCALE: float = 0.02
const VIEWMODEL_WALL_RELEASE_TIME: float = 0.12 ## 接近即时收缩，退开 120ms 恢复
const VIEWMODEL_WALL_SEARCH_STEPS: int = 8
const VIEWMODEL_WALL_MIN_NEAR: float = 0.001
