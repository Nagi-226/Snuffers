## WeaponData — 数据驱动武器定义资源（W2 火力蜂）
##
## 借鉴 Jeh3no 脚手架的 Resource 模式（见 addons/jeh3no_fps_weapon_system/ATTRIBUTION.md）：
## 每把武器一份 .tres，脚本零数值硬编码。
##
## 单一事实源纪律（AGENTS.md 约束 #2）：
## - GameConfig 已有的字段，运行时由 sync_from_config() 逐项覆盖（以 GameConfig 为准）；
##   .tres 中的同名字段仅供编辑器查看与 L2 契约对照，填写时必须与 GameConfig 一致。
## - G2 契约冻结（2026-07-21）后，原「契约缺口」字段已全部补参接管；
##   仅 RPG 的 recoil_view_offset / recoil_decay 契约无 RPG 专属项，沿用 .tres 值
##   （与步枪同值 0.08 / 0.82；若后续需 RPG 独立值须先改契约）。
class_name WeaponData
extends Resource

enum Kind { HITSCAN, PROJECTILE } ## 0=即时命中（步枪），1=投射物（RPG）

# ===== 通用 =====
@export var weapon_id: StringName = &"rifle" ## 对应 GameState.current_weapon / Events.weapon_fired
@export var kind: Kind = Kind.HITSCAN

# ===== 伤害（hitscan）=====
@export var damage_body: float = 25.0 ## 身体伤害（GameConfig.RIFLE_DMG_BODY）
@export var headshot_factor: float = 2.0 ## 爆头倍率（GameConfig.RIFLE_DMG_HEAD_FACTOR）
@export var dmg_vs_sniper: float = 999.0 ## 对狙击手固定伤害（GameConfig.RIFLE_DMG_VS_SNIPER）

# ===== 射速 / 弹药 / 换弹（hitscan）=====
@export var fire_interval: float = 0.1 ## 射速 s/发（GameConfig.RIFLE_FIRE_INTERVAL）
@export var mag_size: int = 30 ## 弹匣（GameConfig.RIFLE_MAG）
@export var reserve_size: int = 150 ## 备弹（GameConfig.RIFLE_RESERVE）
@export var reload_time: float = 2.0 ## 换弹 s（GameConfig.RIFLE_RELOAD_TIME）
@export var hitscan_range: float = 100.0 ## 射程上限 u（GameConfig.RIFLE_RANGE）

# ===== 散布（hitscan；网页版为 NDC 偏移，Godot 版作局部空间角偏移近似，数值沿用）=====
@export var spread_hip: float = 0.004 ## 腰射（GameConfig.RIFLE_SPREAD_HIP）
@export var spread_prone: float = 0.002 ## 趴下（GameConfig.RIFLE_SPREAD_PRONE）
@export var spread_aim: float = 0.0005 ## 瞄准（GameConfig.RIFLE_SPREAD_AIM）

# ===== 后坐 =====
@export var recoil_pitch: float = 0.003 ## 每发相机上跳 rad（步枪=GameConfig.RIFLE_RECOIL_PITCH，
## RPG=GameConfig.RPG_RECOIL_PITCH；G2 冻结采纳暂定值 0.01，
## 修复网页版 RPG 后坐永不触发缺陷，index.html L2959）
@export var recoil_view_offset: float = 0.08 ## 视图模型后坐量（步枪=GameConfig.RIFLE_RECOIL_VIEW_OFFSET；
## RPG 契约无专属项，沿用 .tres 值）
@export var recoil_decay: float = 0.82 ## 视图模型衰减/帧（步枪=GameConfig.RIFLE_RECOIL_DECAY；
## RPG 契约无专属项，沿用 .tres 值）
@export var recoil_recover_rate: float = 6.0 ## 相机上跳恢复速率 /s
## （步枪=GameConfig.RIFLE_RECOIL_RECOVER_RATE，RPG=GameConfig.RPG_RECOIL_RECOVER_RATE；
## Godot 版有意改进：网页版 rotY 永久上跳不恢复，index.html L2959）
@export var view_recoil_rot_factor: float = 2.25 ## 视图模型俯仰系数
## （步枪=GameConfig.RIFLE_RECOIL_VIEW_ROT，RPG=GameConfig.RPG_RECOIL_VIEW_ROT；index.html L3205/L3189）
@export var view_recoil_y_factor: float = 0.025 ## 视图模型上移系数
## （步枪=GameConfig.RIFLE_RECOIL_VIEW_Y_FACTOR，RPG=GameConfig.RPG_RECOIL_VIEW_Y_FACTOR；L3206/L3190）
@export var view_recoil_z_factor: float = 0.05 ## 视图模型后缩系数
## （步枪=GameConfig.RIFLE_RECOIL_VIEW_Z_FACTOR，RPG=GameConfig.RPG_RECOIL_VIEW_Z_FACTOR；L3207/L3191）

# ===== 投射物（RPG）=====
@export var projectile_scene: PackedScene ## 投射物场景（rpg_projectile.tscn）
@export var projectile_speed: float = 120.0 ## 初速 u/s（GameConfig.RPG_PROJECTILE_SPEED）
@export var projectile_gravity: float = 9.8 ## 弹道下坠（GameConfig.RPG_GRAVITY）
@export var projectile_max_range: float = 300.0 ## 最大射程 u（GameConfig.RPG_MAX_RANGE）
@export var projectile_explode_below_y: float = -10.0 ## 低于此高度自爆（GameConfig.RPG_EXPLODE_BELOW_Y，index.html L3172）
@export var explode_radius: float = 10.0 ## 爆炸半径 u（GameConfig.RPG_EXPLODE_RADIUS）
@export var explode_damage: float = 9999.0 ## 爆径内伤害（GameConfig.RPG_EXPLODE_DAMAGE；网页版爆径内即杀，不经 HP，L1556-1591）
@export var bunker_radius_bonus: float = 5.0 ## 对碉堡判定半径加成（GameConfig.RPG_BUNKER_RADIUS_BONUS）
@export var self_damage: bool = false ## 爆炸是否伤玩家（GameConfig.RPG_SELF_DAMAGE）
@export var ammo_count: int = 5 ## 总弹数（GameConfig.RPG_AMMO）


## 以 GameConfig 为准覆盖运行时字段（武器脚本 _ready 时调用）。
## 契约已冻结字段全部在此同步；RPG 的 recoil_view_offset / recoil_decay 契约无专属项，
## 保留 .tres 值（见文件头注释）。
func sync_from_config() -> void:
	match weapon_id:
		&"rifle":
			damage_body = GameConfig.RIFLE_DMG_BODY
			headshot_factor = GameConfig.RIFLE_DMG_HEAD_FACTOR
			dmg_vs_sniper = GameConfig.RIFLE_DMG_VS_SNIPER
			fire_interval = GameConfig.RIFLE_FIRE_INTERVAL
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
		&"rpg":
			projectile_speed = GameConfig.RPG_PROJECTILE_SPEED
			projectile_gravity = GameConfig.RPG_GRAVITY
			projectile_max_range = GameConfig.RPG_MAX_RANGE
			projectile_explode_below_y = GameConfig.RPG_EXPLODE_BELOW_Y
			explode_radius = GameConfig.RPG_EXPLODE_RADIUS
			explode_damage = GameConfig.RPG_EXPLODE_DAMAGE
			bunker_radius_bonus = GameConfig.RPG_BUNKER_RADIUS_BONUS
			self_damage = GameConfig.RPG_SELF_DAMAGE
			ammo_count = GameConfig.RPG_AMMO
			recoil_pitch = GameConfig.RPG_RECOIL_PITCH
			recoil_recover_rate = GameConfig.RPG_RECOIL_RECOVER_RATE
			view_recoil_rot_factor = GameConfig.RPG_RECOIL_VIEW_ROT
			view_recoil_y_factor = GameConfig.RPG_RECOIL_VIEW_Y_FACTOR
			view_recoil_z_factor = GameConfig.RPG_RECOIL_VIEW_Z_FACTOR
