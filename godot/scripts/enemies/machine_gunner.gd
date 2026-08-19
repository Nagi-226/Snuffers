## MachineGunner — 沙袋机枪手（W3 敌智蜂）
##
## 定点持续火力：复刻网页版 MachineGunner 类（index.html L860-1048）。
## HP80、60ms/发、100 发弹链、10s 换弹，全部引用 GameConfig（§7 敌兵行）。
## 狙击手（sniper.gd）与碉堡机枪（bunker_machine_gunner.gd）继承本类，
## 通过 _get_xxx() 配置钩子差异化（与 web 的 Sniper extends MachineGunner 一致）。
extends "res://scripts/enemies/enemy_base.gd"

var _fixed_position: Vector3 = Vector3.ZERO
var _magazine: int = 0
var _reloading: bool = false
var _reload_elapsed: float = 0.0
var _fire_cooldown: float = 0.0

@onready var _muzzle: Marker3D = $Muzzle


func _ready() -> void:
	super()
	enemy_kind = &"machine_gunner"
	health = GameConfig.MG_HP
	_magazine = _get_mag_size()
	_fixed_position = global_position


## ===== 配置钩子（子类覆盖；契约参数一律引用 GameConfig）=====
func _get_fire_interval() -> float:
	return GameConfig.MG_FIRE_INTERVAL


func _get_mag_size() -> int:
	return GameConfig.MG_MAG


func _get_reload_time() -> float:
	return GameConfig.MG_RELOAD_TIME


func _get_range() -> float:
	return GameConfig.MG_RANGE


## 单发伤害 6 + rand×3（web L1027）。
func _roll_damage() -> float:
	return GameConfig.MG_DAMAGE_MIN + randf() * GameConfig.MG_DAMAGE_RAND


## 子类钩子：本轮是否允许开火（碉堡机枪以趴下停火机制覆盖）。
func _can_fire_now() -> bool:
	return true


func _physics_process(delta: float) -> void:
	if _dead:
		return
	# 定点武器：钉住部署点（web L957 每帧回写 fixedPosition）。
	velocity = Vector3.ZERO
	global_position = _fixed_position

	if _reloading:
		_reload_elapsed += delta
		if _reload_elapsed >= _get_reload_time():
			_magazine = _get_mag_size()
			_reloading = false
		else:
			return

	if not _has_player():
		return
	var player_pos := _get_player_position()
	var can_see := _update_sight(delta, player_pos)
	var dist := global_position.distance_to(player_pos)
	# 进入交战：射程内且通视，或已被警戒（web L958；警戒后无距离/视线限制）。
	if (dist < _get_range() and can_see) or alerted:
		_face_position(player_pos)
		_fire_cooldown -= delta
		if _fire_cooldown <= 0.0 and _can_fire_now():
			_shoot(player_pos)


## 开火：弹道被遮挡则本轮放弃（不耗弹、不进冷却，下帧重试，web L1013-1019）。
func _shoot(player_pos: Vector3) -> void:
	if _reloading:
		return
	if _magazine <= 0:
		_start_reload()
		return
	if _shot_blocked(player_pos):
		return
	_fire_cooldown = _get_fire_interval()
	_magazine -= 1
	# 开火广播（G2 冻结信号，W5 枪口音效/火光锚点；碉堡机枪继承本实现）。
	# 狙击手亦发本信号（kind=&"rifle" 复用步枪音源，见 sniper.gd）。
	var muzzle_pos := _muzzle.global_position if _muzzle != null else global_position
	Events.enemy_fired.emit(&"machine_gun", muzzle_pos)
	_damage_player(_roll_damage())


func _start_reload() -> void:
	_reloading = true
	_reload_elapsed = 0.0


## Muzzle → 玩家射线：命中物距终点 >0.5u 才算遮挡（web L1015-1019）。
func _shot_blocked(player_pos: Vector3) -> bool:
	if _muzzle == null:
		return false
	var world := get_world_3d()
	if world == null:
		return false
	var from := _muzzle.global_position
	var query := PhysicsRayQueryParameters3D.create(from, player_pos)
	query.exclude = _los_exclude_rids()
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	return from.distance_to(hit["position"]) < from.distance_to(player_pos) - 0.5
