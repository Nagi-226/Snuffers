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
var show_chamber_bonus: bool = false:
	set(value):
		show_chamber_bonus = value
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
	var mag_text := str(mag - 1 if show_chamber_bonus else mag)
	draw_string(font, Vector2(0, 40), mag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, color)
	if show_chamber_bonus:
		var width := font.get_string_size(mag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		var bonus_position := Vector2(width, 40) + GameConfig.WEAPON_CHAMBER_BONUS_OFFSET
		draw_string(font, bonus_position, "+1", HORIZONTAL_ALIGNMENT_LEFT, -1, GameConfig.WEAPON_CHAMBER_BONUS_FONT_SIZE, color)
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
