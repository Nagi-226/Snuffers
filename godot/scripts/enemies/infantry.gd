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
## （2026-10-22 机主裁决：寄生体近战定位重排距离带，web 交战横移/后退三组残留随之后退逻辑一并退役）

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
var _lose_sight_timer: float = 0.0 ## 持续丢视线时长（脱战用）
var _animation_player: AnimationPlayer = null

@onready var _muzzle: Marker3D = $Muzzle


func _ready() -> void:
	super()
	enemy_kind = &"infantry"
	health = GameConfig.INFANTRY_HP
	_patrol_center = global_position
	_patrol_time = randf() * 100.0
	_max_burst = randi_range(GameConfig.INFANTRY_BURST_MIN, GameConfig.INFANTRY_BURST_MAX)
	var players := $BodyMesh.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_animation_player = players[0] as AnimationPlayer
		_animation_player.animation_finished.connect(_on_animation_finished)
		for clip_name in [&"idle", &"walk", &"run", &"attack", &"death"]:
			var clip := _animation_player.get_animation(clip_name)
			if clip != null:
				clip.loop_mode = Animation.LOOP_LINEAR if clip_name in [&"idle", &"walk", &"run"] else Animation.LOOP_NONE
		_play_animation(&"walk")


func _play_animation(clip_name: StringName, restart: bool = false) -> void:
	if _animation_player == null or not _animation_player.has_animation(clip_name):
		return
	if not restart and _animation_player.current_animation == clip_name:
		return
	_animation_player.play(clip_name, 0.15)


func _sync_state_animation() -> void:
	match current_state:
		State.PATROL:
			_play_animation(&"walk")
		State.TAKE_COVER, State.ENGAGE:
			_play_animation(&"run")
		_:
			_play_animation(&"idle")


func _on_animation_finished(clip_name: StringName) -> void:
	if clip_name == &"death" and _dead:
		queue_free()
	elif clip_name == &"attack" and not _dead:
		_sync_state_animation()


func _die() -> void:
	if _dead:
		return
	_dead = true
	remove_from_group(&"enemy")
	collision_layer = 0
	collision_mask = 0
	$HeadHitbox.collision_layer = 0
	$HeadHitbox.collision_mask = 0
	Events.enemy_died.emit(self)
	_play_animation(&"death")
	if _animation_player == null or _animation_player.current_animation != &"death":
		queue_free()


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

	# 脱战计时（2026-10-20 机主裁决）：持续丢视线累加，复见清零；
	# ENGAGE 中超 INFANTRY_LOSE_SIGHT_TIME → 回巡逻（见 _update_engage）。
	if can_see:
		_lose_sight_timer = 0.0
	else:
		_lose_sight_timer += delta

	match current_state:
		State.PATROL:
			_update_patrol(delta, player_pos, dist, can_see)
		State.ALERT:
			_update_alert(player_pos, dist, can_see)
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
## 2026-10-20 机主裁决：计时到必须仍看得见才升级交战，否则回巡逻——
## 杜绝「瞄到一眼后隔墙锁定、绕楼追打」。
func _update_alert(player_pos: Vector3, dist: float, can_see: bool) -> void:
	_face_position(player_pos)
	velocity.x *= 0.5
	velocity.z *= 0.5
	if _state_timer <= 0.0:
		if not can_see:
			_set_state(State.PATROL)
			return
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


## PEEK：隐蔽 0.5s → 探头窗口孢子（0.2s/发）→ 周期末 30% 再探头，否则 ENGAGE（L1253-1276）。
## 2026-10-22 机主裁决：出手必须 can_see——盲射旁路（dist<3m 无视视线）退役，
## 该旁路是「隔墙听见建筑内敌人出手声」的根因；玩家贴近至逼近分界内 → 放弃掩体转 ENGAGE 近身。
func _update_peek(delta: float, player_pos: Vector3, dist: float, can_see: bool) -> void:
	_peek_timer += delta
	if dist <= GameConfig.INFANTRY_ENGAGE_APPROACH_DIST:
		_set_state(State.ENGAGE, GameConfig.INFANTRY_PEEK_ENGAGE_TIME)
		return
	if _peek_timer > GameConfig.INFANTRY_PEEK_FIRE_DELAY and _peek_timer < GameConfig.INFANTRY_PEEK_CYCLE_TIME:
		_face_position(player_pos)
		if can_see and _attack_cooldown <= 0.0:
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


## ENGAGE（2026-10-22 机主裁决重排攻击距离带）：逼近至近身距离为止（寄生体近战定位，不后退），
## 出手必须 can_see；≤ MELEE_RANGE 近身重击，APPROACH_DIST–SPORE_RANGE 带（10–15m）投掷孢子。
## 计时耗尽或打满点射 → TAKE_COVER（L1277-1304）。
## 2026-10-20 机主裁决：持续丢视线 > INFANTRY_LOSE_SIGHT_TIME → 回巡逻脱战。
func _update_engage(player_pos: Vector3, dist: float, can_see: bool) -> void:
	if _lose_sight_timer > GameConfig.INFANTRY_LOSE_SIGHT_TIME:
		_set_state(State.PATROL)
		_lose_sight_timer = 0.0
		return
	_face_position(player_pos)
	if dist > GameConfig.INFANTRY_MELEE_RANGE:
		var dir := player_pos - global_position
		dir.y = 0.0
		dir = dir.normalized()
		velocity.x = dir.x * GameConfig.INFANTRY_SPEED
		velocity.z = dir.z * GameConfig.INFANTRY_SPEED
	else:
		velocity.x *= 0.2
		velocity.z *= 0.2
	if can_see and _attack_cooldown <= 0.0:
		if dist <= GameConfig.INFANTRY_MELEE_RANGE:
			_melee()
		elif dist > GameConfig.INFANTRY_ENGAGE_APPROACH_DIST and dist <= GameConfig.INFANTRY_SPORE_RANGE:
			_attack(GameConfig.INFANTRY_ENGAGE_INTERVAL)
	if _state_timer <= 0.0 or _shots_in_burst >= _max_burst:
		_shots_in_burst = 0
		var cover := _find_nearest_cover(player_pos)
		_set_state(State.TAKE_COVER)
		# web：无掩体时以当前位置为目标（原地转入 PEEK，L1302）。
		_target_pos = cover["pos"] if cover["found"] else global_position
		_has_target = true


## 孢子投掷（寄生体远程手段，非枪械）：
## 广播 Events.enemy_fired(&"spore", 出手位置)（黏性孢子音效/特效锚点）；
## 命中结算双门控——①开火瞬间真实视线复核（Eye→玩家胸口，0.1m 严容差堵薄墙穿透）；
## ②距离 ≤ INFANTRY_SPORE_RANGE（15m，2026-10-22 机主裁决 10→15；超出则孢子够不到，只出手不结算——
##   调用方已按 10–15m 带门控，本检查为兜底）。
func _attack(interval: float) -> void:
	_attack_cooldown = interval
	_shots_in_burst += 1
	_play_animation(&"attack", true)
	var muzzle_pos := _muzzle.global_position if _muzzle != null else global_position
	Events.enemy_fired.emit(&"spore", muzzle_pos)
	var dist := global_position.distance_to(_get_player_position())
	if dist > GameConfig.INFANTRY_SPORE_RANGE:
		return
	if _fire_ray_clear():
		_damage_player(GameConfig.INFANTRY_DAMAGE)


## 近身重击（2026-10-22 机主裁决：寄生体主战手段，≤ MELEE_RANGE 出手）。
## 不广播 enemy_fired——音频侧无近战分支，发了会错放枪声；近战音效资产待补（见 handoff）。
## 命中同样过 _fire_ray_clear() 实时射线复核，防隔薄墙抓伤。
func _melee() -> void:
	_attack_cooldown = GameConfig.INFANTRY_MELEE_INTERVAL
	_play_animation(&"attack", true)
	if _fire_ray_clear():
		_damage_player(GameConfig.INFANTRY_MELEE_DAMAGE)


## 开火瞬间实时射线：Eye → 玩家胸口（脚底原点 +1.2m）无遮挡才算命中。
## 不复用 _cached_can_see（2 帧节流缓存，开火判定必须现查）。
## 2026-10-21 收紧：命中容差 0.5→0.1m——旧 0.5m 容差会把「贴薄墙另一侧」的墙体
## 命中当作不遮挡，玩家贴墙站时隔墙掉血；0.1m 只豁免射线端点贴到玩家胶囊的误差。
func _fire_ray_clear() -> bool:
	if _eye == null:
		return false
	var world := get_world_3d()
	if world == null:
		return false
	var from := _eye.global_position
	var target := _get_player_position() + Vector3(0.0, 1.2, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, target)
	query.exclude = _los_exclude_rids()
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return from.distance_to(hit["position"]) > from.distance_to(target) - 0.1


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
	_sync_state_animation()
