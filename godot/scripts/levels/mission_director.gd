## MissionDirector — 任务流程控制器（G3 任务链串联，2026-08-19 Phase 0b 蜂后集成）
##
## 契约驱动零硬编码：点位/距离/时长全部读 GameConfig（EXTRACT_POS/CABIN_POS/
## HELI_UNLOCK_*_DIST/HELI_COUNTDOWN/EXTRACT_BOARD_RADIUS/EVENT_SNIPER_*）。
## 信号零新增：复用 events.gd 既有任务信号组（heli_unlock_changed/heli_called/
## heli_timer_updated/heli_arrived/mission_completed/game_over/minefield_triggered）。
## 玩家位置/偏航读 GameState.player_position（W1 每帧写入），无跨模块节点引用。
##
## 任务链：渗透（撤离点 15u / 通讯小屋 6u 解锁呼叫）→ H 呼叫 → 60s 坚守
## （+2 事件狙击手，呼机后 EVENT_SNIPER_SPAWN_DELAY 秒刷出）→ 直升机到达
## → 撤离环 EXTRACT_BOARD_RADIUS 内登机 → mission_completed。
extends Node3D

## 事件狙击手场景（main.tscn 总装时注入 sniper.tscn；组合层显式依赖，脚本不 preload 跨域场景）。
@export var event_sniper_scene: PackedScene

var _timer_broadcast_second: int = -1


func _ready() -> void:
	Events.heli_called.connect(_on_heli_called)
	Events.minefield_triggered.connect(_on_minefield_triggered)
	Events.game_over.connect(_on_game_over)
	Events.mission_completed.connect(_on_mission_completed)


func _exit_tree() -> void:
	Events.heli_called.disconnect(_on_heli_called)
	Events.minefield_triggered.disconnect(_on_minefield_triggered)
	Events.game_over.disconnect(_on_game_over)
	Events.mission_completed.disconnect(_on_mission_completed)


func _physics_process(delta: float) -> void:
	match GameState.mission_phase:
		GameState.MissionPhase.INFILTRATE:
			_check_unlock()
		GameState.MissionPhase.DEFEND:
			_tick_countdown(delta)
		GameState.MissionPhase.BOARD:
			_check_boarding()


## 撤离解锁：玩家进入撤离点 HELI_UNLOCK_EXTRACT_DIST 或通讯小屋 HELI_UNLOCK_CABIN_DIST
## 范围（水平距，web L3749），一次性置位并广播。
func _check_unlock() -> void:
	if GameState.heli_unlocked:
		return
	var pxz := Vector2(GameState.player_position.x, GameState.player_position.z)
	if pxz.distance_to(GameConfig.EXTRACT_POS) <= GameConfig.HELI_UNLOCK_EXTRACT_DIST \
			or pxz.distance_to(GameConfig.CABIN_POS) <= GameConfig.HELI_UNLOCK_CABIN_DIST:
		GameState.heli_unlocked = true
		Events.heli_unlock_changed.emit(true)
		Events.message_posted.emit("撤离频道已接通——按 H 呼叫直升机")


## 坚守倒计时：GameState.heli_time_left 递减，整秒变化时广播 heli_timer_updated
## （契约注释「每秒广播」）；归零 → 直升机到达，转登机阶段。
func _tick_countdown(delta: float) -> void:
	GameState.heli_time_left = maxf(0.0, GameState.heli_time_left - delta)
	var whole := ceili(GameState.heli_time_left)
	if whole != _timer_broadcast_second:
		_timer_broadcast_second = whole
		Events.heli_timer_updated.emit(GameState.heli_time_left)
	if GameState.heli_time_left <= 0.0:
		GameState.mission_phase = GameState.MissionPhase.BOARD
		Events.heli_arrived.emit()


## 登机判定：直升机到达后玩家进入撤离环 EXTRACT_BOARD_RADIUS（水平距）即任务完成。
func _check_boarding() -> void:
	var pxz := Vector2(GameState.player_position.x, GameState.player_position.z)
	if pxz.distance_to(GameConfig.EXTRACT_POS) <= GameConfig.EXTRACT_BOARD_RADIUS:
		GameState.mission_phase = GameState.MissionPhase.COMPLETED
		Events.mission_completed.emit()


## H 呼叫（player_controller 已在 unlocked 门控后发射）：转坚守阶段并刷事件狙击手。
func _on_heli_called() -> void:
	if GameState.mission_phase != GameState.MissionPhase.INFILTRATE:
		return
	GameState.mission_phase = GameState.MissionPhase.DEFEND
	GameState.heli_time_left = GameConfig.HELI_COUNTDOWN
	_timer_broadcast_second = -1
	_spawn_event_snipers()


## 事件狙击手 ×2（§7 部署 18 固定 + 2 事件）：呼机 EVENT_SNIPER_SPAWN_DELAY 秒后，
## 在撤离点 EVENT_SNIPER_SPAWN_DIST 距离的两个内侧方向刷出（web L3671-3673）。
## 注：EVENT_SNIPER_INTERVAL/MAG/RANGE 差异化参数需 sniper.gd 加 event_mode（W3 域），
## 本轮以标准狙击手刷出，差异化列 Phase 1 候选（见 handoff）。
func _spawn_event_snipers() -> void:
	if event_sniper_scene == null:
		push_warning("MissionDirector: event_sniper_scene 未注入，事件狙击手跳过")
		return
	await get_tree().create_timer(GameConfig.EVENT_SNIPER_SPAWN_DELAY).timeout
	if GameState.mission_phase != GameState.MissionPhase.DEFEND:
		return
	var extract := GameConfig.EXTRACT_POS
	# 两个刷出方向取撤离点朝场区内侧 ±45°（撤离点在西北角，内侧即东南象限）。
	for angle_deg: float in [45.0, -45.0]:
		var dir := Vector2.RIGHT.rotated(deg_to_rad(angle_deg))
		var pos2 := extract + dir * GameConfig.EVENT_SNIPER_SPAWN_DIST
		var sniper := event_sniper_scene.instantiate()
		get_parent().add_child(sniper)
		(sniper as Node3D).global_position = Vector3(pos2.x, 0.0, pos2.y)


## 地雷（§6 修复：HP 清零即结算；雷场本体属拉伸项，信号通路先行接通）。
func _on_minefield_triggered() -> void:
	if GameState.mission_phase == GameState.MissionPhase.COMPLETED \
			or GameState.mission_phase == GameState.MissionPhase.GAME_OVER:
		return
	for part: StringName in GameState.health:
		GameState.health[part] = 0.0
		Events.player_health_changed.emit(part, 0.0, _part_max(part))
	GameState.mission_phase = GameState.MissionPhase.GAME_OVER
	Events.game_over.emit(&"mine")


func _part_max(part: StringName) -> float:
	match part:
		&"head":
			return GameConfig.HEALTH_HEAD
		&"body":
			return GameConfig.HEALTH_BODY
		&"legs":
			return GameConfig.HEALTH_LEGS
	return 0.0


## 结束态同步（幂等：狙击秒杀与承伤管线可能双发 game_over，先到先得；结束态不互相覆盖）。
func _on_game_over(_reason: StringName) -> void:
	if GameState.mission_phase == GameState.MissionPhase.COMPLETED:
		return
	GameState.mission_phase = GameState.MissionPhase.GAME_OVER


func _on_mission_completed() -> void:
	if GameState.mission_phase == GameState.MissionPhase.GAME_OVER:
		return
	GameState.mission_phase = GameState.MissionPhase.COMPLETED
