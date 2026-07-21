## Infantry — 步兵五态状态机（W3 敌智蜂）
##
## PATROL → ALERT → TAKE_COVER → PEEK → ENGAGE，逐行复刻网页版 Enemy 类
## （index.html L1123-1426）。HP/移速/射速/伤害与行为调参全部引用 GameConfig
## （§7 敌兵行 + G2 冻结 INFANTRY_* 调参组，契约已落地；web 行号出处保留在
## game_config.gd 注释中）。
## 掩体消费约定：以 group "cover_point" 标记的节点作为掩体候选（W4 并行施工
## 按同一约定产出，最终由蜂后对齐），评分公式复刻 web L1350-1363。
extends "res://scripts/enemies/enemy_base.gd"

## ===== web 内联行为值（G2 冻结契约未收录的残留调参，已登记交付报告）=====
const STRAFE_SPEED_CLOSE: float = 2.5 ## 交战近距离横移速度（L1284）
const STRAFE_SPEED_MID: float = 2.0 ## 交战中距离横移速度（L1289）
const BACKOFF_FACTOR: float = 0.45 ## 交战后退系数（-1.5×0.3，L1285-1287）

enum State { PATROL, ALERT, TAKE_COVER, PEEK, ENGAGE }

## 当前状态（暴露给 headless 冒烟断言，勿在类外改写）。
## 注意：用 int 标注而非 State 枚举类型——W6 的匿名编译校验链对「enum 作类型
## 标注」会报双重身份解析错误（gdscript://-xxx.gd.State vs State），int 语义相同。
var current_state: int = State.PATROL

var _state_timer: float = 0.0
var _target_pos: Vector3 = Vector3.ZERO
var _has_target: bool = false
var _peek_timer: float = 0.0
var _shots_in_burst: int = 0
var _max_burst: int = 0
var _patrol_time: float = 0.0
var _patrol_center: Vector3 = Vector3.ZERO
var _attack_cooldown: float = 0.0
var _strafe_time: float = 0.0

@onready var _muzzle: Marker3D = $Muzzle


func _ready() -> void:
	super()
	enemy_kind = &"infantry"
	health = GameConfig.INFANTRY_HP
	_patrol_center = global_position
	_patrol_time = randf() * 100.0
	_max_burst = randi_range(GameConfig.INFANTRY_BURST_MIN, GameConfig.INFANTRY_BURST_MAX)


## 状态名（headless 冒烟断言用）。
func get_state_name() -> StringName:
	return StringName(State.keys()[current_state])


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta

	# 玩家缺席（冒烟/未入组且 GameState 未写入）时保持巡逻，不做任何战斗转移。
	var has_player := _has_player()
	var player_pos := _get_player_position() if has_player else global_position
	var dist := global_position.distance_to(player_pos) if has_player else INF
	var can_see := _update_sight(delta, player_pos) if has_player else false
	if can_see and not alerted:
		alerted = true

	_state_timer -= delta
	_attack_cooldown -= delta
	_strafe_time += delta

	match current_state:
		State.PATROL:
			_update_patrol(delta, player_pos, dist, can_see)
		State.ALERT:
			_update_alert(player_pos, dist)
		State.TAKE_COVER:
			_update_take_cover(player_pos)
		State.PEEK:
			_update_peek(delta, player_pos, dist, can_see)
		State.ENGAGE:
			_update_engage(player_pos, dist, can_see)

	move_and_slide()
	# 世界边界钳制（web clampPosition L1398-1403）。
	global_position.x = clampf(global_position.x, -GameConfig.WORLD_BOUND_X, GameConfig.WORLD_BOUND_X)
	global_position.z = clampf(global_position.z, -GameConfig.WORLD_BOUND_Z, GameConfig.WORLD_BOUND_Z)


## PATROL：绕出生点圆周巡逻；看见玩家且在索敌半径内 → ALERT（L1201-1216）。
func _update_patrol(delta: float, player_pos: Vector3, dist: float, can_see: bool) -> void:
	if can_see and dist < GameConfig.INFANTRY_DETECT_RADIUS:
		_set_state(State.ALERT, GameConfig.INFANTRY_ALERT_DELAY)
		velocity.x *= 0.3
		velocity.z *= 0.3
		return
	_patrol_time += delta * 0.3
	var tx := _patrol_center.x + cos(_patrol_time) * GameConfig.INFANTRY_PATROL_RADIUS
	var tz := _patrol_center.z + sin(_patrol_time) * GameConfig.INFANTRY_PATROL_RADIUS
	var dir := Vector3(tx - global_position.x, 0.0, tz - global_position.z)
	if dir.length() > 0.01:
		dir = dir.normalized()
		velocity.x = dir.x * GameConfig.INFANTRY_PATROL_SPEED
		velocity.z = dir.z * GameConfig.INFANTRY_PATROL_SPEED
		_face_position(Vector3(tx, global_position.y, tz))
	else:
		velocity.x = 0.0
		velocity.z = 0.0


## ALERT：面向玩家减速戒备；计时到 → 有掩体且距玩家够远则 TAKE_COVER，否则 ENGAGE（L1217-1233）。
func _update_alert(player_pos: Vector3, dist: float) -> void:
	_face_position(player_pos)
	velocity.x *= 0.5
	velocity.z *= 0.5
	if _state_timer <= 0.0:
		var cover := _find_nearest_cover(player_pos)
		if cover["found"] and dist > GameConfig.INFANTRY_COVER_MIN_DIST:
			_set_state(State.TAKE_COVER)
			_target_pos = cover["pos"]
			_has_target = true
		else:
			_set_state(State.ENGAGE, GameConfig.INFANTRY_ALERT_ENGAGE_TIME)
			_shots_in_burst = 0


## TAKE_COVER：加速奔向掩体点；到达 → PEEK（L1234-1252）。
func _update_take_cover(player_pos: Vector3) -> void:
	if not _has_target:
		_set_state(State.ENGAGE)
		return
	if _horizontal_distance_to(_target_pos) < GameConfig.INFANTRY_COVER_ARRIVE_DIST:
		_set_state(State.PEEK, 1.0 + randf())
		_peek_timer = 0.0
		velocity.x *= 0.2
		velocity.z *= 0.2
	else:
		var dir := _target_pos - global_position
		dir.y = 0.0
		dir = dir.normalized()
		var speed := GameConfig.INFANTRY_SPEED * GameConfig.INFANTRY_COVER_SPEED_FACTOR
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		_face_position(player_pos)


## PEEK：隐蔽 0.5s → 探头窗口开火（0.2s/发）→ 周期末 30% 再探头，否则 ENGAGE（L1253-1276）。
func _update_peek(delta: float, player_pos: Vector3, dist: float, can_see: bool) -> void:
	_peek_timer += delta
	if _peek_timer > GameConfig.INFANTRY_PEEK_FIRE_DELAY and _peek_timer < GameConfig.INFANTRY_PEEK_CYCLE_TIME:
		_face_position(player_pos)
		if (can_see or dist < GameConfig.INFANTRY_BLIND_FIRE_DIST) and _attack_cooldown <= 0.0:
			_attack(GameConfig.INFANTRY_PEEK_INTERVAL)
	elif _peek_timer >= GameConfig.INFANTRY_PEEK_CYCLE_TIME:
		_peek_timer = 0.0
		_shots_in_burst = 0
		if randf() < GameConfig.INFANTRY_PEEK_REPEAT_CHANCE:
			_state_timer = 1.0 + randf()
		else:
			_set_state(State.ENGAGE, GameConfig.INFANTRY_PEEK_ENGAGE_TIME)
	else:
		velocity.x *= 0.1
		velocity.z *= 0.1


## ENGAGE：距离带移动（逼近/后退横移/横移），0.25s/发；
## 计时耗尽或打满点射 → TAKE_COVER（L1277-1304）。
func _update_engage(player_pos: Vector3, dist: float, can_see: bool) -> void:
	_face_position(player_pos)
	if dist > GameConfig.INFANTRY_ENGAGE_APPROACH_DIST:
		var dir := player_pos - global_position
		dir.y = 0.0
		dir = dir.normalized()
		velocity.x = dir.x * GameConfig.INFANTRY_SPEED
		velocity.z = dir.z * GameConfig.INFANTRY_SPEED
	elif dist < GameConfig.INFANTRY_ENGAGE_BACKOFF_DIST:
		var strafe := sin(_strafe_time / 0.3) * STRAFE_SPEED_CLOSE
		velocity.x = (player_pos.x - global_position.x) * -BACKOFF_FACTOR + strafe
		velocity.z = (player_pos.z - global_position.z) * -BACKOFF_FACTOR
	else:
		velocity.x = sin(_strafe_time / 0.4) * STRAFE_SPEED_MID
		velocity.z *= 0.5
	if (can_see or dist < GameConfig.INFANTRY_BLIND_FIRE_DIST) and _attack_cooldown <= 0.0:
		_attack(GameConfig.INFANTRY_ENGAGE_INTERVAL)
	if _state_timer <= 0.0 or _shots_in_burst >= _max_burst:
		_shots_in_burst = 0
		var cover := _find_nearest_cover(player_pos)
		_set_state(State.TAKE_COVER)
		# web：无掩体时以当前位置为目标（原地转入 PEEK，L1302）。
		_target_pos = cover["pos"] if cover["found"] else global_position
		_has_target = true


## 单发攻击：web attack() L1416-1425，直接结算 5 伤（命中判定由调用方视线门控）。
## 开火广播 Events.enemy_fired(&"rifle", 枪口位置)（G2 冻结信号，W5 音效/火光锚点）。
func _attack(interval: float) -> void:
	_attack_cooldown = interval
	_shots_in_burst += 1
	var muzzle_pos := _muzzle.global_position if _muzzle != null else global_position
	Events.enemy_fired.emit(&"rifle", muzzle_pos)
	_damage_player(GameConfig.INFANTRY_DAMAGE)


## 掩体搜索：group "cover_point" 候选，25u 内按
## score = -距离×0.5 + 夹角×10 评分取最优（web findNearestCover L1350-1363）。
## 返回 {"found": bool, "pos": Vector3}（pos 为 XZ 平面点，y=0）。
func _find_nearest_cover(player_pos: Vector3) -> Dictionary:
	var best := Vector3.ZERO
	var best_score := -9999.0
	var found := false
	for node: Node in get_tree().get_nodes_in_group(&"cover_point"):
		var point := node as Node3D
		if point == null:
			continue
		var cover_pos := Vector3(point.global_position.x, 0.0, point.global_position.z)
		var d := _horizontal_distance_to(cover_pos)
		if d > GameConfig.INFANTRY_COVER_SEARCH_RADIUS:
			continue
		var to_player := Vector3(player_pos.x - cover_pos.x, 0.0, player_pos.z - cover_pos.z).normalized()
		var to_enemy := Vector3(global_position.x - cover_pos.x, 0.0, global_position.z - cover_pos.z).normalized()
		var score := -d * GameConfig.INFANTRY_COVER_SCORE_DIST + to_player.dot(to_enemy) * GameConfig.INFANTRY_COVER_SCORE_ALIGN
		if score > best_score:
			best_score = score
			best = cover_pos
			found = true
	return {"found": found, "pos": best}


## 无掩体时的受击后退点：远离攻击者 5u（web findFallbackPos L1364-1367）。
func _find_fallback_pos(attacker_pos: Vector3) -> Vector3:
	var dir := global_position - attacker_pos
	dir.y = 0.0
	dir = dir.normalized()
	return global_position + dir * GameConfig.INFANTRY_FALLBACK_COVER_DIST


## 受击反应（web onHit L1368-1397）：巡逻/戒备中 → 找掩体；探头中 → 缩回重置。
func _on_damaged(_amount: float, attacker_pos: Vector3) -> void:
	alerted = true
	if current_state == State.PATROL or current_state == State.ALERT:
		var cover := _find_nearest_cover(attacker_pos)
		_set_state(State.TAKE_COVER)
		_target_pos = cover["pos"] if cover["found"] else _find_fallback_pos(attacker_pos)
		_has_target = true
	elif current_state == State.PEEK:
		_peek_timer = 0.0
		_state_timer = 0.5


## 同伴警戒联动（web alertNearbyEnemies L3032-3046）：半径内同伴死亡 →
## 有掩体且距死亡点 >5u 则 TAKE_COVER，否则 ENGAGE 10s。
## 发射侧（击杀者）广播半径应使用 GameConfig.ALERT_ON_DEATH_RADIUS（见交付报告）。
func _on_enemies_alerted(origin: Vector3, radius: float) -> void:
	if _dead:
		return
	var flat_origin := Vector3(origin.x, 0.0, origin.z)
	var dist := _horizontal_distance_to(flat_origin)
	if dist >= radius:
		return
	alerted = true
	var player_pos := _get_player_position() if _has_player() else global_position
	var cover := _find_nearest_cover(player_pos)
	if cover["found"] and dist > GameConfig.INFANTRY_COMPANION_COVER_DIST:
		_set_state(State.TAKE_COVER)
		_target_pos = cover["pos"]
		_has_target = true
	else:
		_set_state(State.ENGAGE, GameConfig.INFANTRY_COMPANION_ENGAGE_TIME)
	_shots_in_burst = 0


func _set_state(new_state: int, timer: float = 0.0) -> void:
	current_state = new_state
	_state_timer = timer
