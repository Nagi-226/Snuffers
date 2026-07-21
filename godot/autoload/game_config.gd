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
const SPEED_PRONE: float = 0.72 ## 趴下移速 u/s（0.08×0.15×60，L3432/L3239）
const LEG_INJURED_FACTOR: float = 0.5 ## 腿血 ≤60%：站立速度×0.5 → 2.25 u/s（倍率 0.25 vs 0.5，L3243）
const LEG_CRITICAL_FACTOR: float = 0.25 ## 腿血 =0：站立速度×0.25 → 1.125 u/s（倍率 0.125，L3242）
const LEG_INJURED_THRESHOLD: float = 0.6 ## 腿血比例阈值（L3243）

const MOUSE_SENS_BASE: float = 0.002 ## 视角系数 movement×0.002×sens（L2815）
const AIM_SENS_FACTOR: float = 0.3 ## 开镜灵敏度倍率（L2814）
const PITCH_CLAMP: float = 1.2 ## 俯仰 ±rad（L2817）
var view_sensitivity: float = 2.0 ## 设置滑条 0.3–5.0，默认 2.0（L326/L255）

const CAM_HEIGHT_STAND: float = 2.0 ## 站立相机高（L3440）
const CAM_HEIGHT_PRONE: float = 0.5 ## 趴下相机高（L2695）
const CAM_HEIGHT_LERP_TIME: float = 0.15 ## 趴下过渡 150ms（有意改进：网页版瞬切，L2695）

const FOV_BASE: float = 75.0 ## 主相机 FOV（L465）
const FOV_SCOPE: float = 25.0 ## 瞄准镜 FOV = 75/3（L512）

const WORLD_BOUND_X: float = 98.0 ## 活动范围 x（L3438）
const WORLD_BOUND_Z: float = 58.0 ## 活动范围 z（L3439）
const PLAYER_RADIUS: float = 0.4 ## 碰撞半径（L3388）
const PLAYER_HEIGHT_STAND: float = 1.8 ## 站立碰撞高（L3389）
const PLAYER_HEIGHT_PRONE: float = 0.4 ## 趴下碰撞高（L3413）

const STILL_SPEED_THRESHOLD: float = 0.05 ## 静止判定 u/s（L3458）
const SNIPER_STILL_TIME: float = 1.0 ## 静止多久触发狙杀 s（L1086）

# ===== 玩家生存 =====
const HEALTH_HEAD: float = 35.0 ## 头部 HP（L327）
const HEALTH_BODY: float = 85.0 ## 躯体 HP（L327）
const HEALTH_LEGS: float = 65.0 ## 腿部 HP（L327）
const HELMET_MAX: float = 50.0 ## 头盔（L327）
const ARMOR_MAX: float = 100.0 ## 护甲（L327）
const DMG_TAKEN_HEAD_FACTOR: float = 1.5 ## 命中头部伤害系数（L3276）
const DMG_TAKEN_LEGS_FACTOR: float = 0.8 ## 命中腿部伤害系数（L3277）
const DMG_TAKEN_PRONE_HEAD_FACTOR: float = 0.6 ## 趴下被爆头再系数（L3278）
const ARMOR_ABSORB_FACTOR: float = 0.6 ## 护甲吸收上限 = 伤害×0.6（L3271）
const MEDKIT_HEAL: float = 50.0 ## 三部位各 +50（L866）
const MEDKIT_PICKUP_RADIUS: float = 3.0 ## 拾取半径（L849）
const MEDKIT_MAX_CARRY: int = 5 ## 携带上限（L2305）

# ===== 步枪（G2 门禁基准）=====
const RIFLE_DMG_BODY: float = 25.0 ## 身体伤害（L2985）
const RIFLE_DMG_HEAD_FACTOR: float = 2.0 ## 爆头倍率 → 50（L2985）
const RIFLE_DMG_VS_SNIPER: float = 999.0 ## 对狙击手固定伤害（L3014）
const RIFLE_FIRE_INTERVAL: float = 0.1 ## 射速 s/发 = 600 RPM（L2609）
const RIFLE_MAG: int = 30 ## 弹匣（L327）
const RIFLE_RESERVE: int = 150 ## 备弹（L327）
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

# ===== RPG =====
const RPG_AMMO: int = 5 ## 火箭弹数（L327）
const RPG_PROJECTILE_SPEED: float = 120.0 ## 初速 u/s（L3127）
const RPG_GRAVITY: float = 9.8 ## 弹道下坠（L3139）
const RPG_MAX_RANGE: float = 300.0 ## 最大射程 u（L3131）
const RPG_EXPLODE_RADIUS: float = 10.0 ## 爆炸半径 u（L1511）
const RPG_BUNKER_RADIUS_BONUS: float = 5.0 ## 对碉堡判定半径加成（L1593）
const RPG_SELF_DAMAGE: bool = false ## 网页版爆炸对玩家零伤害（L1645-1657）；G2 复核是否保留
const RPG_RECOIL_PITCH: float = 0.01 ## RPG 独立后坐上跳 rad（修复网页版后坐永不触发缺陷；暂定值，G2 试玩手感裁决）
const RPG_RECOIL_RECOVER_RATE: float = 6.0 ## RPG 后坐恢复速率 /s（Godot 版新增，网页版无）
const RPG_RECOIL_VIEW_ROT: float = 2.5 ## 视图模型后坐旋转系数（L3189-3191）
const RPG_RECOIL_VIEW_Y_FACTOR: float = 0.025 ## 视图模型后坐位移系数 Y（L3189-3191）
const RPG_RECOIL_VIEW_Z_FACTOR: float = 0.075 ## 视图模型后坐位移系数 Z（L3189-3191）
const RPG_EXPLODE_DAMAGE: float = 9999.0 ## 爆径内即杀伤害（L1556-1591）
const RPG_EXPLODE_BELOW_Y: float = -10.0 ## 坠地自爆高度（L3172）

# ===== 敌人（G2 门禁基准）=====
const INFANTRY_HP: float = 50.0 ## 步兵血量（L1139）
const INFANTRY_SPEED: float = 3.5 ## 步兵移动速度 u/s（L1140）
const INFANTRY_COVER_SPEED_FACTOR: float = 1.2 ## 找掩体加速（L1140）
const INFANTRY_PATROL_SPEED: float = 2.0 ## 巡逻速度 u/s（L1210）
const INFANTRY_DETECT_RADIUS: float = 80.0 ## 索敌半径（L1143）
const INFANTRY_ENGAGE_INTERVAL: float = 0.25 ## 交战射击间隔 s（L1294）
const INFANTRY_PEEK_INTERVAL: float = 0.2 ## 探头射击间隔 s（L1258）
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
const INFANTRY_ENGAGE_APPROACH_DIST: float = 12.0 ## 交战逼近距离
const INFANTRY_ENGAGE_BACKOFF_DIST: float = 5.0 ## 交战后退距离
const INFANTRY_BLIND_FIRE_DIST: float = 3.0 ## 盲射距离
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
