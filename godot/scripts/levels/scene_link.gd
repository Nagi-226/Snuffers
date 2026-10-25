## SceneLink — HL 式关卡衔接门（2026-10-25 机主立项：巷口铁栅栏门=下一场景入口，
## 参考《半衰期》穿门加载下一张地图、返回再穿=读回上一张的模式）。
##
## 机制：Area3D 触发 → change_scene_to_file(目标场景)；跨场景到达锚点用本类
## **静态变量**传递（静态变量随脚本类存活于整个进程，零契约变更、零新 autoload；
## GameState/Events/GameConfig 本就是 autoload，弹药/血量等跨场景自动延续）。
## 到达端：目标场景里 anchor_id 匹配的 SceneLink 在 _ready 把玩家挪到自身位置
## （延迟一帧等玩家就绪），并给 1.2s 触发免疫防止落地即回传。
class_name SceneLink
extends Node3D

## 本次穿门要到达的锚点 id（""=无待到达，用场景默认出生点）。
static var arrive_anchor: String = ""
## 到达免疫截止时刻（msec，防到达即再触发回传）。
static var _immune_until: int = 0

@export var target_scene: String = ""
## 穿门后到达【目标场景】里的哪个锚点（目标场景中 anchor_id 与此相同的
## SceneLink 负责接人；空=用目标场景默认出生点）。
@export var target_anchor: String = ""
@export var anchor_id: String = ""
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


func _on_body_entered(body: Node3D) -> void:
	if target_scene == "" or not body.is_in_group(&"player"):
		return
	if Time.get_ticks_msec() < SceneLink._immune_until:
		return
	if not ResourceLoader.exists(target_scene):
		push_warning("SceneLink: 目标场景不存在 %s" % target_scene)
		return
	SceneLink.arrive_anchor = target_anchor
	get_tree().change_scene_to_file(target_scene)
