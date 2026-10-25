## SceneLink — HL 式关卡衔接门（2026-10-25 机主立项：巷口铁栅栏门=下一场景入口，
## 参考《半衰期》穿门加载下一张地图、返回再穿=读回上一张的模式）。
##
## 机制：Area3D 触发 → change_scene_to_file(目标场景)；跨场景到达锚点用本类
## **静态变量**传递（静态变量随脚本类存活于整个进程，零契约变更、零新 autoload；
## GameState/Events/GameConfig 本就是 autoload，弹药/血量等跨场景自动延续）。
## 到达端：目标场景里 anchor_id 匹配的 SceneLink 在 _ready 把玩家挪到自身位置
## （延迟一帧等玩家就绪），并给 1.2s 触发免疫防止落地即回传。
## 敌人持久化（2026-10-25 机主指令）：穿门离场前把当前场景存活敌人（死亡者已
## queue_free 天然不在组内）的名单/位置/血量存进静态快照；返回到达时按快照恢复
## ——存活者归位回血、不在名单的（离场后阵亡的）移除，不再全量刷新。
class_name SceneLink
extends Node3D

## 本次穿门要到达的锚点 id（""=无待到达，用场景默认出生点）。
static var arrive_anchor: String = ""
## 到达免疫截止时刻（msec，防到达即再触发回传）。
static var _immune_until: int = 0
## 跨场景敌人快照：scene_path → Array[Dictionary]（name/pos/health）。
## 静态字典随进程存活；每次离场覆盖写同键，初进游戏为空=全量刷新（首次行为不变）。
static var enemy_snapshots: Dictionary = {}
## 跨场景拾取物快照：scene_path → Array[String]（离场时仍存活的拾取节点名）。
## 返回时不在名单的=离场前已拾取 → 恢复期删除（关键道具不再刷新，2026-10-25 机主报修）。
static var pickup_snapshots: Dictionary = {}

@export var target_scene: String = ""
## 穿门后到达【目标场景】里的哪个锚点（目标场景中 anchor_id 与此相同的
## SceneLink 负责接人；空=用目标场景默认出生点）。
@export var target_anchor: String = ""
@export var anchor_id: String = ""
## 锁门（2026-10-25 机主裁决：E1/E2 巷子尽头=坚固铁栅栏门，单人几乎破不开，
## 需在钥匙场景取得钥匙）：true 时无钥匙只提示不穿门。
@export var requires_key := false


func _on_body_entered(body: Node3D) -> void:
	if target_scene == "" or not body.is_in_group(&"player"):
		return
	if Time.get_ticks_msec() < SceneLink._immune_until:
		return
	# 门禁两连（2026-10-25 机主指令：钥匙之外还需 2 个取证终端，缺啥报啥）
	if requires_key and not GameState.gate_key_have:
		Events.message_posted.emit("铁栅栏门被重型锁扣死——需要找到钥匙（E5 车库后院）")
		return
	if requires_key and GameState.intel < GameConfig.GATE_INTEL_REQUIRED:
		Events.message_posted.emit("门禁校验未通过——取证终端 %d/%d（E1/E2 楼内）"
			% [GameState.intel, GameConfig.GATE_INTEL_REQUIRED])
		return
	if not ResourceLoader.exists(target_scene):
		push_warning("SceneLink: 目标场景不存在 %s" % target_scene)
		return
	_capture_enemies()
	_capture_pickups()
	SceneLink.arrive_anchor = target_anchor
	get_tree().change_scene_to_file(target_scene)
## 到达时玩家相对本节点的落位偏移（本节点面向由场景摆放决定）。
@export var spawn_offset: Vector3 = Vector3(0, 0.2, -1.5)

@onready var _area: Area3D = $TriggerArea


func _ready() -> void:
	_area.body_entered.connect(_on_body_entered)
	# 到达端：锚点匹配则把玩家挪到门口内侧。
	if anchor_id != "" and SceneLink.arrive_anchor == anchor_id:
		SceneLink.arrive_anchor = ""
		SceneLink._immune_until = Time.get_ticks_msec() + 1200
		_teleport_player.call_deferred()
		_restore_enemies.call_deferred()
		_restore_pickups.call_deferred()


## 离场快照：当前场景存活敌人（group "enemy"；死亡者 _die 已 queue_free，
## 天然不在组内=快照只含活口）记录节点名/位置/血量，按场景文件路径存静态字典。
## 节点名=场景文件驻军实例名（Host_F1 等，场景内唯一）。返回快照数组（探针用）。
func _capture_enemies() -> Array:
	var snap: Array = []
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var eb := e as Node3D
		if eb == null:
			continue
		var hp: float = 1.0
		var hp_v: Variant = eb.get("health")
		if hp_v != null:
			hp = hp_v
		snap.append({"name": String(eb.name), "pos": eb.global_position, "health": hp})
	SceneLink.enemy_snapshots[_scene_path()] = snap
	return snap


## 返回恢复（延迟一帧等场景全员入树+入组）：按快照把存活者归位/回血；
## 不在快照名单里的（离场后才阵亡的）移除——「走前剩谁回来还是谁」。
## 归位后调 on_scene_restored() 钩子（步兵以此重锚巡逻圈）。
func _restore_enemies() -> void:
	if not SceneLink.enemy_snapshots.has(_scene_path()):
		return
	var by_name := {}
	for rec in SceneLink.enemy_snapshots[_scene_path()]:
		by_name[rec["name"]] = rec
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var eb := e as Node3D
		if eb == null:
			continue
		if by_name.has(String(eb.name)):
			var rec: Dictionary = by_name[String(eb.name)]
			eb.global_position = rec["pos"]
			eb.set("health", rec["health"])
			if eb.has_method(&"on_scene_restored"):
				eb.call(&"on_scene_restored")
		else:
			eb.queue_free()


## 本 link 所属场景根的 scene_file_path：从自身向上走到工程根（root）的直接
## 子节点。不用 get_tree().current_scene——到达端 _ready 时 engine 尚未指派
## current_scene，自链上行在离场/到达两端都稳定成立。
func _scene_path() -> String:
	var n: Node = self
	while n.get_parent() != null and n.get_parent() != get_tree().root:
		n = n.get_parent()
	return n.scene_file_path


## 离场拾取物快照：记录 group "pickup" 里仍存活的节点名（死亡=已拾取的
## queue_free 后不在组内）。返回恢复时不在名单的删除（含其任务标记）——
## 取证终端/钥匙等关键道具不再随场景重载刷新（2026-10-25 机主报修）。
func _capture_pickups() -> void:
	var names: Array = []
	for p in get_tree().get_nodes_in_group(&"pickup"):
		names.append(String((p as Node).name))
	SceneLink.pickup_snapshots[_scene_path()] = names


## 返回恢复（延迟一帧）：不在离场快照名单里的拾取节点=已拾取 → 删除并同步
## 擦除其任务标记（builder 重建时会重新登记全部标记，此处收尾对齐）。
func _restore_pickups() -> void:
	if not SceneLink.pickup_snapshots.has(_scene_path()):
		return
	var alive: Array = SceneLink.pickup_snapshots[_scene_path()]
	for p in get_tree().get_nodes_in_group(&"pickup"):
		var pn := p as Node
		if not alive.has(String(pn.name)):
			GameState.mission_points.erase(String(pn.name))
			pn.queue_free()


func _teleport_player() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null:
		return
	player.global_position = global_position + (basis * spawn_offset)
	var pc := player.get_node_or_null("Camera3D") as Camera3D
	if pc != null:
		pc.rotation_degrees.x = 0.0
	# 顶层 Node（玩家 yaw 载体）朝向门内方向。
	if player.has_method(&"_face_position"):
		player.call("_face_position", global_position + basis * Vector3(0, 0, -10))
