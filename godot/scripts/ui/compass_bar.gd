extends Control
## CompassBar — 顶部滚动罗盘方位条（2026-10-25 机主立项：多数 FPS 式平视罗盘）
##
## 随 GameState.player_yaw 滚动：北/东/南/西 四方位字符 + 45° 斜方位度数 +
## 15° 细刻度；中央方位角读数（000°~359°）。任务关键点（GameState.mission_points：
## 铁栅栏门钥匙=金 / 取证终端=青）按玩家→目标方位角在条带上投影菱形标记，
## 出带即钳到条带边缘（多数 FPS 同款「目标在背后」指示）。
## 纯视觉样式常量集中本文件头部（hud.gd 同规）；heading/bearing 数学与 minimap
## 的玩家箭头约定一致（yaw+=西转，北=世界 -Z）。

## 条带视野角（±半角可见；视觉样式常量）。
const SPAN_DEG: float = 120.0
## 细刻度间隔（度）。
const TICK_DEG: float = 15.0
## 四方位（顺时针从北；北向字符用暖色高亮）。
const CARDINALS := [
	[0.0, "北"], [90.0, "东"], [180.0, "南"], [270.0, "西"]]
## 斜方位度数刻度（45° 步进，字符标注）。
const DIAGONALS := [45.0, 135.0, 225.0, 315.0]

const COLOR_TICK := Color(0.55, 0.85, 0.95, 0.55)
const COLOR_TICK_MAJOR := Color(0.45, 0.95, 1.0, 0.9)
const COLOR_TEXT := Color(0.75, 0.95, 1.0, 0.95)
const COLOR_NORTH := Color(1.0, 0.62, 0.45, 1.0)
const COLOR_READOUT := Color(0.45, 0.95, 1.0, 1.0)
## 任务标记色：钥匙=金 / 取证终端=青（与拾取物发光色呼应）。
const COLOR_KEY := Color(1.0, 0.8, 0.3, 1.0)
const COLOR_INTEL := Color(0.45, 0.95, 1.0, 0.95)
const COLOR_MARKER_DIM := 0.45 ## 边缘钳制态标记透明度（目标在条带外）

@export var show_mission_markers: bool = true

@onready var _font: Font = get_theme_default_font()


func _process(_delta: float) -> void:
	queue_redraw()


## 当前航向角（罗盘口径：0=北，顺时针增，0..360）。
## Godot yaw+ 为西转（-Z 前向绕 +Y 逆时针），故 heading = -yaw。
func _heading_deg() -> float:
	return wrapf(-rad_to_deg(GameState.player_yaw), 0.0, 360.0)


## 玩家→目标方位角（同口径）。
func _bearing_deg(target: Vector3) -> float:
	var d := target - GameState.player_position
	return wrapf(rad_to_deg(atan2(d.x, -d.z)), 0.0, 360.0)


func _draw() -> void:
	var heading := _heading_deg()
	var half := SPAN_DEG * 0.5
	var px_per_deg := size.x / SPAN_DEG
	var cx := size.x * 0.5
	var cy := size.y
	# —— 刻度带（0..360 每 TICK_DEG 一根，相对角出带即裁）——
	var deg := 0.0
	while deg < 360.0:
		var rel := wrapf(deg - heading, -180.0, 180.0)
		if absf(rel) <= half:
			var x := cx + rel * px_per_deg
			var is_cardinal: bool = is_equal_approx(fmod(deg, 90.0), 0.0)
			var is_diag: bool = is_equal_approx(fmod(deg, 45.0), 0.0)
			var tick_h := 10.0 if is_cardinal else (7.0 if is_diag else 4.0)
			draw_line(Vector2(x, cy - tick_h), Vector2(x, cy),
				COLOR_TICK_MAJOR if is_cardinal else COLOR_TICK,
				2.0 if is_cardinal else 1.0)
			if is_cardinal:
				for c in CARDINALS:
					if is_equal_approx(c[0], deg):
						var col := COLOR_NORTH if deg == 0.0 else COLOR_TEXT
						_draw_char_c(c[1], Vector2(x, cy - tick_h - 14.0), col)
			elif is_diag:
				_draw_char_c("%d" % int(deg), Vector2(x, cy - tick_h - 12.0),
					Color(COLOR_TEXT, 0.7))
		deg += TICK_DEG
	# —— 任务关键点菱形（出带钳到边缘）——
	for key in GameState.mission_points if show_mission_markers else []:
		var rec: Dictionary = GameState.mission_points[key]
		var rel2 := wrapf(_bearing_deg(rec["pos"]) - heading, -180.0, 180.0)
		var clamped := absf(rel2) > half
		var mx := cx + clampf(rel2, -half, half) * px_per_deg
		var col: Color = COLOR_KEY if rec["kind"] == &"gate_key" else COLOR_INTEL
		col.a = COLOR_MARKER_DIM if clamped else 1.0
		_draw_diamond(Vector2(mx, cy - 18.0), 5.0, col)
	# —— 中央照门 + 航向读数（读数置顶，与下方刻度带的方位字符错层不重叠）——
	draw_line(Vector2(cx, cy - 2.0), Vector2(cx, cy + 4.0), COLOR_READOUT, 2.0)
	draw_polygon(PackedVector2Array([Vector2(cx - 4, 0), Vector2(cx + 4, 0), Vector2(cx, 6)]),
		PackedColorArray([COLOR_READOUT, COLOR_READOUT, COLOR_READOUT]))
	var readout := "%03d°" % (int(round(heading)) % 360)
	_draw_char_c(readout, Vector2(cx, 1.0), COLOR_READOUT)


## 默认字体小字（无主题标签依赖，Control _draw 内自绘）。
func _draw_char_c(text: String, top_center: Vector2, col: Color) -> void:
	if _font == null:
		return
	var fs := 13
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(top_center.x - w * 0.5, top_center.y + fs), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_diamond(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(c.x, c.y - r), Vector2(c.x + r, c.y),
		Vector2(c.x, c.y + r), Vector2(c.x - r, c.y)]), col)
	draw_polyline(PackedVector2Array([
		Vector2(c.x, c.y - r), Vector2(c.x + r, c.y), Vector2(c.x, c.y + r),
		Vector2(c.x - r, c.y), Vector2(c.x, c.y - r)]), Color(0, 0, 0, 0.5), 1.0)
