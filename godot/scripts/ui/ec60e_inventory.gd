## EC-60E 常驻手雷库存；独立于当前枪械与 EC-40 榴弹栏。
extends Control

const ICON_TEXTURE := preload("res://assets/ui/weapons/ec60e.svg")

var stock: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = Control.TEXTURE_FILTER_LINEAR
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	var bounds := GameConfig.EC60E_HUD_RECT
	offset_left = bounds.x
	offset_top = bounds.y
	offset_right = bounds.z
	offset_bottom = bounds.w
	stock = GameState.ec60e_grenades
	Events.ec60e_stock_changed.connect(_on_stock_changed)
	queue_redraw()


func _exit_tree() -> void:
	Events.ec60e_stock_changed.disconnect(_on_stock_changed)


func _on_stock_changed(total: int) -> void:
	stock = maxi(0, total)
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	draw_string(font, GameConfig.EC60E_HUD_TITLE_POINT, "EC-60E · 闷罐",
			HORIZONTAL_ALIGNMENT_LEFT, -1, GameConfig.EC60E_HUD_FONTS.x, GameConfig.EC60E_HUD_SECONDARY)
	draw_string(font, GameConfig.EC60E_HUD_COUNT_POINT, str(stock),
			HORIZONTAL_ALIGNMENT_LEFT, -1, GameConfig.EC60E_HUD_FONTS.y, GameConfig.EC60E_HUD_COLOR)
	draw_string(font, GameConfig.EC60E_HUD_HINT_POINT, "[G] 投掷手雷  ·  [T] 药包",
			HORIZONTAL_ALIGNMENT_LEFT, -1, GameConfig.EC60E_HUD_FONTS.z, GameConfig.EC60E_HUD_SECONDARY)
	draw_texture_rect(ICON_TEXTURE, GameConfig.EC60E_HUD_ICON_RECT, false)
