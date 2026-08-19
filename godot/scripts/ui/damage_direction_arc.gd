## DamageDirectionArc — 受击方向指示弧（§11.1 A 方案三件套之三，W5 颜面蜂域，
## 2026-08-19 Phase 0b）
##
## 监听 Events.player_hit_direction(from_position)（2026-08-19 冻结新增信号，
## 与 player_damaged 同点发射）。以来源世界方向 − 玩家偏航（GameState.player_yaw）
## 算出相对角，在屏幕中心准星外圈画一段红色圆弧，DAMAGE_ARC_SHOW_TIME 秒内淡出。
## 自包含：信号连接/计时/绘制全部在本类收口，hud.gd 零改动（hud.tscn 仅挂节点）。
extends Control

## 弧半径 px（相对 1920×1080 设计分辨率，anchor 居中后即为像素偏移）
const ARC_RADIUS: float = 90.0
## 弧半张角 rad（弧段总宽约 46°）
const ARC_HALF_SPAN: float = 0.4
const ARC_WIDTH: float = 6.0
const ARC_COLOR: Color = Color(0.85, 0.2, 0.15)

## 存活弧段：[{"rel_angle": float, "remaining": float}]
var _arcs: Array = []


func _ready() -> void:
	Events.player_hit_direction.connect(_on_player_hit_direction)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _exit_tree() -> void:
	Events.player_hit_direction.disconnect(_on_player_hit_direction)


func _process(delta: float) -> void:
	if _arcs.is_empty():
		return
	for i in range(_arcs.size() - 1, -1, -1):
		_arcs[i]["remaining"] -= delta
		if _arcs[i]["remaining"] <= 0.0:
			_arcs.remove_at(i)
	queue_redraw()


## 来源方向 → 相对玩家朝向的角度（0 = 正前方，顺时针为正，屏幕极坐标）。
## Godot 前向为 -Z：前向方位角 = atan2(-sin(yaw), -cos(yaw)) = yaw + π（取模意义下）。
func _on_player_hit_direction(from_position: Vector3) -> void:
	var d := from_position - GameState.player_position
	if Vector2(d.x, d.z).length() < 0.01:
		return
	var source_bearing := atan2(d.x, d.z)
	var rel := wrapf(source_bearing - GameState.player_yaw - PI, -PI, PI)
	_arcs.append({"rel_angle": rel, "remaining": GameConfig.DAMAGE_ARC_SHOW_TIME})
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	for arc: Dictionary in _arcs:
		var fade: float = clampf(arc["remaining"] / GameConfig.DAMAGE_ARC_SHOW_TIME, 0.0, 1.0)
		var color := Color(ARC_COLOR, ARC_COLOR.a * fade)
		# 屏幕角：rel=0 指正前方（屏幕上方）；draw_arc 以 +X 为 0 逆时针，
		# 换算：screen_angle = rel - PI/2（上 = -Y）。
		var a := (arc["rel_angle"] as float) - PI * 0.5
		draw_arc(center, ARC_RADIUS, a - ARC_HALF_SPAN, a + ARC_HALF_SPAN, 16, color, ARC_WIDTH, true)
