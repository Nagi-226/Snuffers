## 已批准的原生黑色手臂 + Gen5 动作校准场景。
extends Node3D

const NativeArms = preload("res://scripts/player/native_pistol_arms.gd")
var adapter = NativeArms.new()
var _reload_remaining := 0.0

func _ready() -> void:
	if not adapter.configure($Arms, $G17Gen5Olight, $G17Gen5Olight.find_child("Magazine", true, false), GameConfig.BLACK_PISTOL_PROFILES[&"gen5"]):
		push_error("Gen5 preview: native arms setup failed")

func _process(delta: float) -> void:
	adapter.update(delta)
	if _reload_remaining > 0.0:
		_reload_remaining -= delta
		if _reload_remaining <= 0.0:
			adapter.reset()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey:
		match (event as InputEventKey).keycode:
			KEY_1:
				adapter.play_fire()
			KEY_2, KEY_3:
				var empty := (event as InputEventKey).keycode == KEY_3
				_reload_remaining = adapter.animation.get_animation(&"reload_empty" if empty else &"reload").length
				adapter.play_reload(_reload_remaining, empty)
			KEY_4:
				adapter.animation.play(&"hide")
			KEY_5:
				adapter.animation.play(&"ready")
			KEY_6:
				adapter.reset()
