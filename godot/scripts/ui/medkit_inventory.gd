## 药包常驻库存；并列于手雷 HUD，消费既有拾取与使用事件。
extends Control

const ICON_TEXTURE := preload("res://assets/ui/weapons/medkit.svg")

var stock: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = Control.TEXTURE_FILTER_LINEAR
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	var bounds := GameConfig.MEDKIT_HUD_RECT
	offset_left = bounds.x
	offset_top = bounds.y
	offset_right = bounds.z
	offset_bottom = bounds.w
	stock = GameState.medkits
	Events.medkit_picked.connect(_on_stock_changed)
	Events.medkit_used.connect(_on_stock_changed)
	queue_redraw()


func _exit_tree() -> void:
	Events.medkit_picked.disconnect(_on_stock_changed)
	Events.medkit_used.disconnect(_on_stock_changed)


func _on_stock_changed(total: int) -> void:
	stock = maxi(0, total)
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	draw_string(font, GameConfig.MEDKIT_HUD_TITLE_POINT, "药包",
			HORIZONTAL_ALIGNMENT_LEFT, -1, GameConfig.MEDKIT_HUD_FONTS.x, GameConfig.MEDKIT_HUD_SECONDARY)
	draw_string(font, GameConfig.MEDKIT_HUD_COUNT_POINT, str(stock),
			HORIZONTAL_ALIGNMENT_LEFT, -1, GameConfig.MEDKIT_HUD_FONTS.y, GameConfig.MEDKIT_HUD_COLOR)
	draw_texture_rect(ICON_TEXTURE, GameConfig.MEDKIT_HUD_ICON_RECT, false)
