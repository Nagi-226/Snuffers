## Minimap — HUD 右上角圆形小地图（灯塔 ASI 战术探测视图）
## 2026-10-21 机主立项：地形随玩家位置实时推进，红点=敌人（ASI 探测信息）。
##
## 结构（hud.tscn 内）：
##   Minimap(本脚本, Control)
##   ├─ View(SubViewportContainer, 圆形遮罩 shader)
##   │   └─ Sub(SubViewport 176²)
##   │       ├─ MapTex(TextureRect, 俯视底图, 位置/缩放每帧驱动)
##   │       └─ Dots(Control, 红点+玩家箭头 _draw)
##   边框圆环/北向刻线由本节点 _draw 绘制（遮罩外）。
##
## 底图与标定：tools/capture_minimap.gd 离线渲染（assets/ui/minimap_street.png/.json），
## 北向固定（图上=世界 -Z），玩家箭头随 GameState.player_yaw 旋转。
## 参数全部契约化（GameConfig.MINIMAP_*）；底图缺失时整体隐藏（降级不伤 HUD）。
extends Control

@onready var _map_tex: TextureRect = %MapTex
@onready var _dots: Control = %Dots

## 世界→像素标定（capture_minimap.gd 同批产物）
var _calib_min := Vector2.ZERO ## (min_x, min_z)
var _calib_ppm: float = 1.0 ## 底图像素/米
var _map_ok: bool = false
var _enemies: Array = []


func _ready() -> void:
	var tex: Texture2D = load(GameConfig.MINIMAP_MAP_TEXTURE)
	var calib := _load_calib(GameConfig.MINIMAP_MAP_CALIB)
	if tex == null or calib.is_empty():
		visible = false
		return
	_map_ok = true
	_map_tex.texture = tex
	_calib_min = Vector2(calib["min_x"], calib["min_z"])
	_calib_ppm = float(calib["img"]) / maxf(calib["max_x"] - calib["min_x"], 0.001)
	custom_minimum_size = Vector2(GameConfig.MINIMAP_SIZE_PX, GameConfig.MINIMAP_SIZE_PX)
	size = custom_minimum_size
	_dots.draw.connect(_dots_draw)
	_dots.queue_redraw()


func _load_calib(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


func _process(_delta: float) -> void:
	if not _map_ok:
		return
	var center := size * 0.5
	## 缩放：让契约半径 MINIMAP_RANGE_M 恰好铺满小地图半径
	var zoom := (size.x * 0.5) / (GameConfig.MINIMAP_RANGE_M * _calib_ppm)
	var player_map_px := (Vector2(GameState.player_position.x, GameState.player_position.z)
		- _calib_min) * _calib_ppm
	_map_tex.scale = Vector2(zoom, zoom)
	_map_tex.position = center - player_map_px * zoom
	_enemies = get_tree().get_nodes_in_group(&"enemy")
	_dots.queue_redraw()
	queue_redraw()


## 敌人红点 + 玩家箭头（SubViewport 内，随容器圆形遮罩裁剪）
func _dots_draw() -> void:
	var center := _dots.size * 0.5
	var m2px := (_dots.size.x * 0.5) / GameConfig.MINIMAP_RANGE_M
	var player_xz := Vector2(GameState.player_position.x, GameState.player_position.z)
	for e in _enemies:
		if not (e is Node3D) or not (e as Node3D).visible:
			continue
		var exz := Vector2((e as Node3D).global_position.x, (e as Node3D).global_position.z)
		var off := (exz - player_xz) * m2px
		if off.length() > _dots.size.x * 0.5 - GameConfig.MINIMAP_ENEMY_DOT_R:
			continue
		_dots.draw_circle(center + off, GameConfig.MINIMAP_ENEMY_DOT_R, GameConfig.MINIMAP_ENEMY_COLOR)
	## 玩家箭头：北向固定图，箭头随偏航旋转（Godot 前向 -Z，屏幕上=-Z）
	_dots.draw_set_transform(center, -GameState.player_yaw, Vector2.ONE)
	var r := 5.0
	_dots.draw_colored_polygon(PackedVector2Array([
		Vector2(0, -r * 1.4), Vector2(r, r), Vector2(0, r * 0.45), Vector2(-r, r)]),
		GameConfig.MINIMAP_PLAYER_COLOR)
	_dots.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 圆环边框 + 北向刻线（遮罩外，画在容器边框上）
func _draw() -> void:
	if not _map_ok:
		return
	var center := size * 0.5
	var radius := size.x * 0.5
	draw_circle(center, radius, GameConfig.MINIMAP_BG_COLOR)
	draw_arc(center, radius - 1.5, 0.0, TAU, 64, GameConfig.MINIMAP_BORDER_COLOR, 2.0, true)
	## 北向刻线（图固定北向上）
	draw_line(center + Vector2(0, -radius + 3.0), center + Vector2(0, -radius + 9.0),
		GameConfig.MINIMAP_PLAYER_COLOR, 2.0, true)
