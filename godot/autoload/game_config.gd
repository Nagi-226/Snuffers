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
const STEP_MAX_HEIGHT: float = 0.35 ## 自动上台阶最大高度 m（2026-10-18 机主立项：路缘 0.145/门槛/阳台板 0.14 免跳直上；>0.35 的墙仍需跳或绕）
const INTERACT_RANGE: float = 2.4 ## E 键通用交互距离 m（2026-10-18 机主立项：开门等；准星射线命中才生效）
const NV_SFX_CUT_TIME: float = 0.85 ## 夜视开关音效截短时长 s（2026-10-18 机主裁决：原音源偏长，播到此时长后 0.12s 淡出截停）

const FOV_BASE: float = 75.0 ## 主相机 FOV（L465）
# —— 按住开镜（ADS，2026-10-19 机主立项：右键由「切换潜行观感」改为按住开镜）——
const RIFLE_ADS_FOV: float = 60.0 ## EM-68A 全息瞄具开镜 FOV（全息=低倍率，微收窄）
const PISTOL_ADS_FOV: float = 65.0 ## EM-57P 点状瞄具开镜 FOV
const DMR_ADS_FOV: float = 35.0 ## EM-68D 精确射手瞄具开镜 FOV
const SHOTGUN_ADS_FOV: float = 60.0 ## EM-12G-1 低倍率瞄具开镜 FOV
const ADS_LERP_TIME: float = 0.12 ## 开镜/关镜过渡时长 s（挂载位移与 FOV 同步插值）
const ADS_RIFLE_OPTIC_BORE_LOCAL := Vector3(0.00092, 0.18047, -0.0204) ## EM-68A 镜孔轴心（网格局部空间，Blender 实测，轴系已换算 glTF；2026-10-19 开窗手术配套）
const ADS_PISTOL_OPTIC_WINDOW_LIFT: float = 0.15 ## 手枪瞄窗自 AABB 中心上移比例（EM-57P 维持原标定）

const WORLD_BOUND_X: float = 98.0 ## 活动范围 x（L3438）
const WORLD_BOUND_Z: float = 100.0 ## 活动范围 z（2026-10-23 机主裁决：58→100——58 是网页版灰盒残留钳制，
## 在街景图形成力场幕墙前的「空气墙」（南场 z=68/北场 z=-95 永远无法走近）。放宽到幕墙之外，
## 由幕墙实体碰撞做真实拦截；玩家/寄生体共用此钳制（player_controller/infantry 同口径）
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
const BATTERY_PICKUP_ROUNDS: int = 60 ## 电池组补充步枪备弹数
const PISTOL_AMMO_PICKUP_ROUNDS: int = 60 ## 手枪弹匣组补充手枪备弹数（2026-10-19 机主立项）
const RIFLE_RESERVE_MAX: int = 600 ## 步枪备弹携带上限（达上限不可拾取，2026-10-19 机主口径：与初始备弹拉平 600）
const PISTOL_RESERVE_MAX: int = 600 ## 手枪备弹携带上限（同口径：600）
const PICKUP_TRIGGER_RADIUS: float = 0.7 ## 拾取触发半径（贴近即拾，无需按键）
const PICKUP_BOB_AMP: float = 0.05 ## 浮动振幅 m
const PICKUP_BOB_HZ: float = 1.2 ## 浮动频率 Hz
const PICKUP_SPIN_DEG: float = 45.0 ## 自转角速度 度/s
const GRENADE_PICKUP_ROUNDS: int = 6 ## 榴弹补给件补充数（2026-10-25 机主立项；雷池总数制无上限）

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
const RIFLE_RESERVE: int = 600 ## 备弹（2026-10-19 机主裁决：60/600，原 150 为网页版 L327 值）
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

# ===== 手枪（EM-57P「掣」，2026-10-19 机主立项：EDAA 雷械设定落地，2 号键位；
#       网页版无手枪，数值按设定文档+手感类比定标，G4 试玩复核）=====
const PISTOL_DMG_HEAD_FACTOR: float = 2.0 ## 爆头倍率
const PISTOL_DMG_VS_SNIPER: float = 999.0 ## 对狙击手固定伤害（沿用步枪语义）
const PISTOL_FIRE_INTERVAL: float = 0.06 ## 全自动/三发点射射速 s/发 = 1000 RPM（2026-10-19 机主裁决）
const PISTOL_SEMI_FIRE_INTERVAL: float = 0.15 ## 半自动最小击发间隔 s（≈400 RPM 上限，机主口径：半自动不变）
const PISTOL_MAG: int = 30 ## 弹匣（EDAA 设定：30 发制式弹匣）
const PISTOL_RESERVE: int = 600 ## 备弹（2026-10-19 机主裁决：30/600，原 120）
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
const SHOTGUN_ADS_FORWARD: float = 0.08 ## 开镜挂载前移，避免无托枪托抵脸的观感

# ===== EM-40G「滚雷」下挂榴弹模块（2026-10-22 机主裁决：并入 EM-68A 第四射击档，
#       X 键闭环 全自动→半自动→三发点射→榴→全自动；旧 3 号位 RPG 火箭筒整体退役）=====
# 设定出处（E系列电磁轻武器-概念图谱）：直射档=EC-40P「破垒」全功率平直弹道；
# 模块自带 6 发弹匣即雷池（换匣即换电）；「闸不合，榴不发」=榴档与实弹击发互斥；
# 投射物场景复用 rpg_projectile.tscn（抛物线/爆炸/碉堡结算链路原样接管）。
const GRENADE_AMMO: int = 30 ## 榴弹总数（2026-10-22 机主裁决 6→30：雷池总数制，无备弹/换弹概念）
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
const EXPLOSION_FX_SCORCH_MAX_HEIGHT: float = 2.5 ## 爆心低于此高度才留地面焦痕 m（空中/墙面爆炸不留）

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
const MINIMAP_ENEMY_COLOR := Color(1.0, 0.28, 0.22, 0.95) ## 敌人红点（ASI 威胁标记）
const MINIMAP_PLAYER_COLOR := Color(0.45, 0.95, 1.0, 1.0) ## 玩家箭头（青蓝，HUD 主色）
const MINIMAP_BORDER_COLOR := Color(0.4, 0.95, 1.0, 0.55) ## 圆环边框
const MINIMAP_BG_COLOR := Color(0.02, 0.06, 0.09, 0.78) ## 底图未覆盖区域底色
const MINIMAP_ENEMY_DOT_R: float = 3.0 ## 红点半径 px
