extends Control

const HEX_RADIUS := 9.0
const HEX_STEP_X := 15.5
const HEX_STEP_Y := 13.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	for row in int(ceil(size.y / HEX_STEP_Y)) + 1:
		for column in int(ceil(size.x / HEX_STEP_X)) + 1:
			var center := Vector2(column * HEX_STEP_X + (row % 2) * HEX_STEP_X * 0.5, row * HEX_STEP_Y)
			var normalized := (center - size * 0.5) / Vector2(size.x * 0.38, size.y * 0.36)
			if normalized.length_squared() > 1.0:
				_draw_hex(center)


func _draw_hex(center: Vector2) -> void:
	var points := PackedVector2Array()
	for index in 7:
		var angle := TAU * float(index) / 6.0
		points.append(center + Vector2(cos(angle), sin(angle)) * HEX_RADIUS)
	draw_polyline(points, Color(0.55, 0.72, 0.76, 0.22), 1.0, true)
