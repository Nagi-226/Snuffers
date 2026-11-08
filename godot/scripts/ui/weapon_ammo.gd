extends Control

const WeaponIcon = preload("res://scripts/ui/weapon_icon.gd")

var weapon_id: StringName = &"rifle":
	set(value):
		weapon_id = value
		if is_instance_valid(_icon):
			_icon.set("weapon_id", value)
			_icon.queue_redraw()
		queue_redraw()
var weapon_name: String = "":
	set(value):
		weapon_name = value
		queue_redraw()
var mag: int = 0:
	set(value):
		mag = value
		queue_redraw()
var reserve: int = 0:
	set(value):
		reserve = value
		queue_redraw()
var mode_tag: String = "":
	set(value):
		mode_tag = value
		queue_redraw()
var ammo_type: String = "EC-68":
	set(value):
		ammo_type = value
		queue_redraw()
var show_grenades: bool = false:
	set(value):
		show_grenades = value
		queue_redraw()
var grenade_stock: int = 0:
	set(value):
		grenade_stock = value
		queue_redraw()

var _icon: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon = WeaponIcon.new()
	_icon.set("weapon_id", weapon_id)
	_icon.set("selected", true)
	_icon.position = Vector2(128, 0)
	add_child(_icon)


func _draw() -> void:
	var font := get_theme_default_font()
	var color := Color(0.38, 0.86, 1.0, 0.95)
	var secondary := Color(0.38, 0.86, 1.0, 0.68)
	if weapon_name != "":
		draw_string(font, Vector2(70, -6), weapon_name, HORIZONTAL_ALIGNMENT_RIGHT, 178, 12, secondary)
	draw_string(font, Vector2(0, 40), str(mag), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, color)
	draw_string(font, Vector2(70, 32), str(reserve), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, secondary)
	draw_string(font, Vector2(1, 60), "弹药", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, secondary)
	draw_string(font, Vector2(70, 60), "备弹", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, secondary)
	if mode_tag != "":
		draw_string(font, Vector2(0, 78), mode_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, secondary)
	draw_string(font, Vector2(128, 78), ammo_type, HORIZONTAL_ALIGNMENT_RIGHT, 120, 12, color)
	if show_grenades:
		draw_string(font, Vector2(0, 98), "榴弹", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, secondary)
		draw_string(font, Vector2(70, 98), str(grenade_stock), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, color)
		draw_string(font, Vector2(128, 98), "EC-40P", HORIZONTAL_ALIGNMENT_RIGHT, 120, 12, color)
