extends Control

var weapon_id: StringName = &"rifle"
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(120, 58)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var color := Color(0.38, 0.86, 1.0, 1.0 if selected else 0.58)
	var long_gun := weapon_id != &"pistol"
	if long_gun:
		_line(Vector2(8, 24), Vector2(104, 24), color)
		_line(Vector2(18, 18), Vector2(72, 18), color)
		_line(Vector2(18, 18), Vector2(12, 31), color)
		_line(Vector2(12, 31), Vector2(28, 35), color)
		_line(Vector2(28, 35), Vector2(45, 27), color)
		_line(Vector2(72, 18), Vector2(82, 26), color)
		_line(Vector2(82, 26), Vector2(105, 26), color)
		_line(Vector2(104, 24), Vector2(114, 20), color)
		_line(Vector2(45, 27), Vector2(47, 48), color)
		_line(Vector2(47, 48), Vector2(57, 48), color)
		_line(Vector2(57, 48), Vector2(56, 28), color)
		_line(Vector2(82, 26), Vector2(88, 37), color)
		if weapon_id == &"dmr":
			draw_rect(Rect2(Vector2(48, 7), Vector2(26, 9)), color, false, 2.0)
			_line(Vector2(105, 20), Vector2(116, 20), color)
		elif weapon_id == &"spas12":
			_line(Vector2(62, 31), Vector2(100, 31), color)
			_line(Vector2(24, 35), Vector2(42, 44), color)
		else:
			draw_rect(Rect2(Vector2(50, 8), Vector2(19, 8)), color, false, 2.0)
	else:
		_line(Vector2(34, 19), Vector2(82, 19), color)
		_line(Vector2(82, 19), Vector2(87, 24), color)
		_line(Vector2(87, 24), Vector2(57, 27), color)
		_line(Vector2(57, 27), Vector2(50, 49), color)
		_line(Vector2(50, 49), Vector2(38, 49), color)
		_line(Vector2(38, 49), Vector2(40, 29), color)
		_line(Vector2(40, 29), Vector2(34, 19), color)
		_line(Vector2(82, 16), Vector2(91, 16), color)


func _line(from: Vector2, to: Vector2, color: Color) -> void:
	draw_line(from, to, color, 2.0, true)
