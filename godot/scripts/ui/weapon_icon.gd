extends Control

const ICONS: Dictionary = {
	&"pistol": preload("res://assets/ui/weapons/em57p.svg"),
	&"rifle": preload("res://assets/ui/weapons/em68a.svg"),
	&"dmr": preload("res://assets/ui/weapons/em68d.svg"),
	&"shotgun": preload("res://assets/ui/weapons/em12g1.svg"),
	&"spas12": preload("res://assets/ui/weapons/spas12.svg"),
	&"smg": preload("res://assets/ui/weapons/em57s1.svg"),
	&"em57s2": preload("res://assets/ui/weapons/em57s2.svg"),
	&"em86m": preload("res://assets/ui/weapons/em86m.svg"),
	&"em40t1": preload("res://assets/ui/weapons/em40t1.svg"),
	&"lmg": preload("res://assets/ui/weapons/em68l.svg"),
	&"magnum": preload("res://assets/ui/weapons/em127p.svg"),
	&"em86s": preload("res://assets/ui/weapons/em86s.svg"),
	&"em86b": preload("res://assets/ui/weapons/em86b.svg"),
	&"em86d": preload("res://assets/ui/weapons/em86d.svg"),
	&"em127g": preload("res://assets/ui/weapons/em127g.svg"),
	&"em127m": preload("res://assets/ui/weapons/em127m.svg"),
	&"em120r": preload("res://assets/ui/weapons/em120r.svg"),
	&"em12g2": preload("res://assets/ui/weapons/em12g2.svg"),
}

var weapon_id: StringName = &"rifle":
	set(value):
		weapon_id = value
		queue_redraw()
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(120, 58)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = Control.TEXTURE_FILTER_LINEAR


func _draw() -> void:
	var texture: Texture2D = ICONS.get(weapon_id, ICONS[&"rifle"])
	var tint := Color(1.0, 1.0, 1.0, 1.0 if selected else 0.62)
	draw_texture_rect(texture, Rect2(Vector2.ZERO, Vector2(120, 58)), false, tint)
