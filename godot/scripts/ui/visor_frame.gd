## VisorFrame — 头盔面甲屏显边框（2026-10-19 机主立项：HUD 科幻化，灯塔 ASI 接入视角，
## 参考《孤岛危机》2/3 战术屏显）。纯绘制层：四角括号 + 上下细扫描基线 + 两侧短刻度，
## 低透明青色，不遮挡战斗信息；无逻辑无状态，_draw 一次成型（分辨率变化时重绘）。
extends Control

const FRAME_COLOR := Color(0.4, 0.95, 1.0, 0.22) ## 面甲框线青（低透明，氛围件不抢信息）
const ACCENT_COLOR := Color(0.4, 0.95, 1.0, 0.45) ## 角括号高亮
const BRACKET_LEN: float = 42.0 ## 角括号臂长 px
const BRACKET_W: float = 2.0
const MARGIN: float = 14.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 分辨率/窗口尺寸变化时重绘
	get_viewport().size_changed.connect(queue_redraw)


func _draw() -> void:
	var s := size
	var m := MARGIN
	var l := BRACKET_LEN
	# 四角括号（面甲取景框）
	for corner: Vector2 in [Vector2(m, m), Vector2(s.x - m, m), Vector2(m, s.y - m), Vector2(s.x - m, s.y - m)]:
		var sx: float = 1.0 if corner.x < s.x * 0.5 else -1.0
		var sy: float = 1.0 if corner.y < s.y * 0.5 else -1.0
		draw_line(corner, corner + Vector2(sx * l, 0.0), ACCENT_COLOR, BRACKET_W, true)
		draw_line(corner, corner + Vector2(0.0, sy * l), ACCENT_COLOR, BRACKET_W, true)
	# 上下细基线（屏显上沿/下沿参考线，中段断开留出视野）
	var mid_gap: float = s.x * 0.28
	draw_line(Vector2(m + l + 8, m), Vector2(s.x * 0.5 - mid_gap * 0.5, m), FRAME_COLOR, 1.0, true)
	draw_line(Vector2(s.x * 0.5 + mid_gap * 0.5, m), Vector2(s.x - m - l - 8, m), FRAME_COLOR, 1.0, true)
	draw_line(Vector2(m + l + 8, s.y - m), Vector2(s.x * 0.5 - mid_gap * 0.5, s.y - m), FRAME_COLOR, 1.0, true)
	draw_line(Vector2(s.x * 0.5 + mid_gap * 0.5, s.y - m), Vector2(s.x - m - l - 8, s.y - m), FRAME_COLOR, 1.0, true)
	# 两侧中段短刻度（水平仪暗示）
	for side: float in [m, s.x - m]:
		for i in range(-1, 2):
			var y: float = s.y * 0.5 + i * 26.0
			draw_line(Vector2(side, y), Vector2(side + (10.0 if side < s.x * 0.5 else -10.0), y),
				FRAME_COLOR, 1.2, true)
