## WeaponData — 数据驱动武器定义资源（W2 火力蜂）
##
## 借鉴 Jeh3no 脚手架的 Resource 模式（见 addons/jeh3no_fps_weapon_system/ATTRIBUTION.md）：
## 每把武器一份 .tres，脚本零数值硬编码。
##
## 单一事实源纪律（AGENTS.md 约束 #2）：
## - GameConfig 已有的字段，运行时由 sync_from_config() 逐项覆盖（以 GameConfig 为准）；
##   .tres 中的同名字段仅供编辑器查看与 L2 契约对照，填写时必须与 GameConfig 一致。
## - G2 契约冻结（2026-07-21）后，原「契约缺口」字段已全部补参接管；
##   2026-10-22 旧 RPG 退役，RPG_RECOIL_* 契约组随之移除，榴弹参数改由 GRENADE_* 组接管。
class_name WeaponData
extends Resource

enum Kind { HITSCAN, PROJECTILE } ## 0=即时命中（步枪），1=投射物（RPG）

# ===== 通用 =====
@export var weapon_id: StringName = &"rifle" ## 对应 GameState.current_weapon / Events.weapon_fired
@export var kind: Kind = Kind.HITSCAN

# ===== 伤害（hitscan）=====
@export var damage_body: float = 25.0 ## 身体伤害（按弹药口径：GameConfig.AMMO_DMG_EC68 / AMMO_DMG_EC57）
@export var headshot_factor: float = 2.0 ## 爆头倍率（GameConfig.RIFLE_DMG_HEAD_FACTOR）
@export var dmg_vs_sniper: float = 999.0 ## 对狙击手固定伤害（GameConfig.RIFLE_DMG_VS_SNIPER）

# ===== 射速 / 弹药 / 换弹（hitscan）=====
@export var fire_interval: float = 0.1 ## 全自动/点射射速 s/发（GameConfig.RIFLE_FIRE_INTERVAL）
@export var semi_fire_interval: float = 0.1 ## 半自动击发间隔 s/发（GameConfig.RIFLE_SEMI_FIRE_INTERVAL / PISTOL_SEMI_FIRE_INTERVAL，2026-10-19 机主口径：半自动射速独立于连发档位）
@export var mag_size: int = 30 ## 弹匣（GameConfig.RIFLE_MAG）
@export var reserve_size: int = 150 ## 备弹（GameConfig.RIFLE_RESERVE）
@export var reload_time: float = 2.0 ## 换弹 s（GameConfig.RIFLE_RELOAD_TIME）
@export var hitscan_range: float = 100.0 ## 射程上限 u（GameConfig.RIFLE_RANGE）
@export var pellet_count: int = 1 ## 单次击发射线数（EM-12G-1=12，其余为 1）

# ===== 散布（hitscan；网页版为 NDC 偏移，Godot 版作局部空间角偏移近似，数值沿用）=====
@export var spread_hip: float = 0.004 ## 腰射（GameConfig.RIFLE_SPREAD_HIP）
@export var spread_prone: float = 0.002 ## 趴下（GameConfig.RIFLE_SPREAD_PRONE）
@export var spread_aim: float = 0.0005 ## 瞄准（GameConfig.RIFLE_SPREAD_AIM）

# ===== 后坐 =====
@export var recoil_pitch: float = 0.003 ## 每发相机上跳 rad（GameConfig.RIFLE_RECOIL_PITCH / PISTOL_RECOIL_PITCH）
@export var recoil_view_offset: float = 0.08 ## 视图模型后坐量（GameConfig.RIFLE_RECOIL_VIEW_OFFSET / PISTOL_RECOIL_VIEW_OFFSET）
@export var recoil_decay: float = 0.82 ## 视图模型衰减/帧（GameConfig.RIFLE_RECOIL_DECAY / PISTOL_RECOIL_DECAY）
@export var recoil_recover_rate: float = 6.0 ## 相机上跳恢复速率 /s
## （GameConfig.RIFLE_RECOIL_RECOVER_RATE / PISTOL_RECOIL_RECOVER_RATE；
## Godot 版有意改进：网页版 rotY 永久上跳不恢复，index.html L2959）
@export var view_recoil_rot_factor: float = 2.25 ## 视图模型俯仰系数
## （GameConfig.RIFLE_RECOIL_VIEW_ROT / PISTOL_RECOIL_VIEW_ROT；index.html L3205/L3189）
@export var view_recoil_y_factor: float = 0.025 ## 视图模型上移系数
## （GameConfig.RIFLE_RECOIL_VIEW_Y_FACTOR / PISTOL_RECOIL_VIEW_Y_FACTOR；L3206/L3190）
@export var view_recoil_z_factor: float = 0.05 ## 视图模型后缩系数
## （GameConfig.RIFLE_RECOIL_VIEW_Z_FACTOR / PISTOL_RECOIL_VIEW_Z_FACTOR；L3207/L3191）

# ===== 投射物（EM-40G 榴弹 / 旧 RPG 共用 rpg_projectile.tscn）=====
@export var projectile_scene: PackedScene ## 投射物场景（rpg_projectile.tscn）
@export var projectile_speed: float = 90.0 ## 初速 u/s（GameConfig.GRENADE_PROJECTILE_SPEED）
@export var projectile_gravity: float = 2.0 ## 弹道下坠（GameConfig.GRENADE_GRAVITY）
@export var projectile_max_range: float = 200.0 ## 最大射程 u（GameConfig.GRENADE_MAX_RANGE）
@export var projectile_explode_below_y: float = -10.0 ## 低于此高度自爆（GameConfig.GRENADE_EXPLODE_BELOW_Y）
@export var explode_radius: float = 10.0 ## 伤害半径上限 u（GameConfig.GRENADE_EXPLODE_RADIUS，超出无伤）
@export var explode_kill_radius: float = 5.0 ## 必杀半径 u（GameConfig.GRENADE_EXPLODE_KILL_RADIUS，圈内即杀）
@export var explode_kill_damage: float = 9999.0 ## 必杀圈伤害（GameConfig.GRENADE_EXPLODE_KILL_DAMAGE）
@export var explode_falloff_factor: float = 0.5 ## 过渡带伤害系数（GameConfig.GRENADE_EXPLODE_FALLOFF_FACTOR；kill_radius–explode_radius 半伤）
@export var explode_damage: float = 450.0 ## 爆炸基准伤害（GameConfig.GRENADE_EXPLODE_DAMAGE）
@export var bunker_radius_bonus: float = 5.0 ## 对碉堡判定半径加成（GameConfig.GRENADE_BUNKER_RADIUS_BONUS）
@export var self_damage: bool = false ## 爆炸是否伤玩家（GameConfig.GRENADE_SELF_DAMAGE）
@export var grenade_fire_interval: float = 0.8 ## 榴弹击发间隔 s（GameConfig.GRENADE_FIRE_INTERVAL，仅步枪榴档用）


## 以 GameConfig 为准覆盖运行时字段（武器脚本 _ready 时调用）。
## 契约已冻结字段全部在此同步；RPG 的 recoil_view_offset / recoil_decay 契约无专属项，
## 保留 .tres 值（见文件头注释）。
func sync_from_config() -> void:
	match weapon_id:
		&"rifle":
			damage_body = GameConfig.AMMO_DMG_EC68 ## EM-68A 用 EC-68 步枪弹（伤害绑口径不绑枪，2026-10-22 机主裁决）
			headshot_factor = GameConfig.RIFLE_DMG_HEAD_FACTOR
			dmg_vs_sniper = GameConfig.RIFLE_DMG_VS_SNIPER
			fire_interval = GameConfig.RIFLE_FIRE_INTERVAL
			semi_fire_interval = GameConfig.RIFLE_SEMI_FIRE_INTERVAL
			mag_size = GameConfig.RIFLE_MAG
			reserve_size = GameConfig.RIFLE_RESERVE
			reload_time = GameConfig.RIFLE_RELOAD_TIME
			hitscan_range = GameConfig.RIFLE_RANGE
			spread_hip = GameConfig.RIFLE_SPREAD_HIP
			spread_prone = GameConfig.RIFLE_SPREAD_PRONE
			spread_aim = GameConfig.RIFLE_SPREAD_AIM
			recoil_pitch = GameConfig.RIFLE_RECOIL_PITCH
			recoil_view_offset = GameConfig.RIFLE_RECOIL_VIEW_OFFSET
			recoil_decay = GameConfig.RIFLE_RECOIL_DECAY
			recoil_recover_rate = GameConfig.RIFLE_RECOIL_RECOVER_RATE
			view_recoil_rot_factor = GameConfig.RIFLE_RECOIL_VIEW_ROT
			view_recoil_y_factor = GameConfig.RIFLE_RECOIL_VIEW_Y_FACTOR
			view_recoil_z_factor = GameConfig.RIFLE_RECOIL_VIEW_Z_FACTOR
			# EM-40G「滚雷」榴档投射物参数（2026-10-22 机主裁决并入步枪第四档）
			projectile_speed = GameConfig.GRENADE_PROJECTILE_SPEED
			projectile_gravity = GameConfig.GRENADE_GRAVITY
			projectile_max_range = GameConfig.GRENADE_MAX_RANGE
			projectile_explode_below_y = GameConfig.GRENADE_EXPLODE_BELOW_Y
			explode_radius = GameConfig.GRENADE_EXPLODE_RADIUS
			explode_kill_radius = GameConfig.GRENADE_EXPLODE_KILL_RADIUS
			explode_kill_damage = GameConfig.GRENADE_EXPLODE_KILL_DAMAGE
			explode_falloff_factor = GameConfig.GRENADE_EXPLODE_FALLOFF_FACTOR
			explode_damage = GameConfig.GRENADE_EXPLODE_DAMAGE
			bunker_radius_bonus = GameConfig.GRENADE_BUNKER_RADIUS_BONUS
			self_damage = GameConfig.GRENADE_SELF_DAMAGE
			grenade_fire_interval = GameConfig.GRENADE_FIRE_INTERVAL
		&"pistol":
			# EM-57P「掣」（2026-10-19 冻结新增；EDAA 雷械谱系，GameConfig.PISTOL_* 契约组）
			damage_body = GameConfig.AMMO_DMG_EC57 ## EM-57P 用 EC-57 手枪弹（伤害绑口径不绑枪，2026-10-22 机主裁决）
			headshot_factor = GameConfig.PISTOL_DMG_HEAD_FACTOR
			dmg_vs_sniper = GameConfig.PISTOL_DMG_VS_SNIPER
			fire_interval = GameConfig.PISTOL_FIRE_INTERVAL
			semi_fire_interval = GameConfig.PISTOL_SEMI_FIRE_INTERVAL
			mag_size = GameConfig.PISTOL_MAG
			reserve_size = GameConfig.PISTOL_RESERVE
			reload_time = GameConfig.PISTOL_RELOAD_TIME
			hitscan_range = GameConfig.PISTOL_RANGE
			spread_hip = GameConfig.PISTOL_SPREAD_HIP
			spread_prone = GameConfig.PISTOL_SPREAD_PRONE
			spread_aim = GameConfig.PISTOL_SPREAD_AIM
			recoil_pitch = GameConfig.PISTOL_RECOIL_PITCH
			recoil_view_offset = GameConfig.PISTOL_RECOIL_VIEW_OFFSET
			recoil_decay = GameConfig.PISTOL_RECOIL_DECAY
			recoil_recover_rate = GameConfig.PISTOL_RECOIL_RECOVER_RATE
			view_recoil_rot_factor = GameConfig.PISTOL_RECOIL_VIEW_ROT
			view_recoil_y_factor = GameConfig.PISTOL_RECOIL_VIEW_Y_FACTOR
			view_recoil_z_factor = GameConfig.PISTOL_RECOIL_VIEW_Z_FACTOR
		&"dmr":
			damage_body = GameConfig.DMR_DAMAGE_BODY
			headshot_factor = GameConfig.DMR_DMG_HEAD_FACTOR
			dmg_vs_sniper = GameConfig.DMR_DMG_VS_SNIPER
			fire_interval = GameConfig.DMR_FIRE_INTERVAL
			semi_fire_interval = GameConfig.DMR_SEMI_FIRE_INTERVAL
			mag_size = GameConfig.DMR_MAG
			reserve_size = GameConfig.RIFLE_RESERVE
			reload_time = GameConfig.DMR_RELOAD_TIME
			hitscan_range = GameConfig.DMR_RANGE
			spread_hip = GameConfig.DMR_SPREAD_HIP
			spread_prone = GameConfig.DMR_SPREAD_PRONE
			spread_aim = GameConfig.DMR_SPREAD_AIM
			recoil_pitch = GameConfig.DMR_RECOIL_PITCH
			recoil_view_offset = GameConfig.DMR_RECOIL_VIEW_OFFSET
			recoil_decay = GameConfig.DMR_RECOIL_DECAY
			recoil_recover_rate = GameConfig.DMR_RECOIL_RECOVER_RATE
			view_recoil_rot_factor = GameConfig.DMR_RECOIL_VIEW_ROT
			view_recoil_y_factor = GameConfig.DMR_RECOIL_VIEW_Y_FACTOR
			view_recoil_z_factor = GameConfig.DMR_RECOIL_VIEW_Z_FACTOR
		&"shotgun":
			damage_body = GameConfig.AMMO_DMG_EC12_PELLET
			headshot_factor = GameConfig.SHOTGUN_DMG_HEAD_FACTOR
			dmg_vs_sniper = GameConfig.SHOTGUN_DMG_VS_SNIPER
			pellet_count = GameConfig.SHOTGUN_PELLET_COUNT
			fire_interval = GameConfig.SHOTGUN_FIRE_INTERVAL
			semi_fire_interval = GameConfig.SHOTGUN_SEMI_FIRE_INTERVAL
			mag_size = GameConfig.SHOTGUN_MAG
			reserve_size = GameConfig.SHOTGUN_RESERVE
			reload_time = GameConfig.SHOTGUN_RELOAD_TIME
			hitscan_range = GameConfig.SHOTGUN_RANGE
			spread_hip = GameConfig.SHOTGUN_SPREAD_HIP
			spread_prone = GameConfig.SHOTGUN_SPREAD_PRONE
			spread_aim = GameConfig.SHOTGUN_SPREAD_AIM
			recoil_pitch = GameConfig.SHOTGUN_RECOIL_PITCH
			recoil_view_offset = GameConfig.SHOTGUN_RECOIL_VIEW_OFFSET
			recoil_decay = GameConfig.SHOTGUN_RECOIL_DECAY
			recoil_recover_rate = GameConfig.SHOTGUN_RECOIL_RECOVER_RATE
			view_recoil_rot_factor = GameConfig.SHOTGUN_RECOIL_VIEW_ROT
			view_recoil_y_factor = GameConfig.SHOTGUN_RECOIL_VIEW_Y_FACTOR
			view_recoil_z_factor = GameConfig.SHOTGUN_RECOIL_VIEW_Z_FACTOR
## （旧 &"rpg" 分支已于 2026-10-22 随 RPG 退役删除；榴弹参数并入 &"rifle" 分支）
