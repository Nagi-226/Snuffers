extends Control

const HEX_RADIUS := 9.0
const HEX_STEP_X := 15.5
const HEX_STEP_Y := 13.5
const CORNER_SIZE := Vector2(190, 150)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var origins := [
		Vector2.ZERO,
		Vector2(size.x - CORNER_SIZE.x, 0),
		Vector2(0, size.y - CORNER_SIZE.y),
		size - CORNER_SIZE,
	]
	for origin in origins:
		for row in 11:
			for column in 13:
				var center: Vector2 = origin + Vector2(column * HEX_STEP_X + (row % 2) * HEX_STEP_X * 0.5, row * HEX_STEP_Y)
				_draw_hex(center)


func _draw_hex(center: Vector2) -> void:
	var points := PackedVector2Array()
	for index in 7:
		var angle := TAU * float(index) / 6.0
		points.append(center + Vector2(cos(angle), sin(angle)) * HEX_RADIUS)
	draw_polyline(points, Color(0.35, 0.85, 1.0, 0.2), 1.0, true)
