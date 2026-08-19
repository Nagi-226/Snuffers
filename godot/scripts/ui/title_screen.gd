## TitleScreen — 游戏开头画面（W5 颜面蜂域；2026-08-19 机主指令 + 07 美术设定 §3.1）
##
## 规范：纯黑底，EDAA 徽记居中缓显（刺绣纹理特写 → 拉远至全貌，
## 格言三词随拉远依次可读）；标题与菜单叠加其上。
## 徽记唯一图样基准：godot/assets/branding/edaa_emblem.png（机主原创，禁止变体重绘）。
## 按任意键进入主场景 main.tscn。
extends Control

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
## 缓显时长（特写 → 全貌拉远）
const EMBLEM_REVEAL_TIME: float = 3.2
## 起始放大倍率（刺绣纹理特写感）
const EMBLEM_ZOOM_FROM: float = 1.9

var _started: bool = false

@onready var _emblem: TextureRect = $Emblem
@onready var _title_label: Label = $TitleLabel
@onready var _prompt_label: Label = $PromptLabel


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# 初始状态：徽记不可见、特写放大；标题/提示待徽显后淡入。
	_emblem.modulate.a = 0.0
	_emblem.pivot_offset = _emblem.size * 0.5
	_emblem.scale = Vector2.ONE * EMBLEM_ZOOM_FROM
	_title_label.modulate.a = 0.0
	_prompt_label.modulate.a = 0.0
	_play_reveal()


## 徽记缓显：透明度 0→1 同时从特写倍率拉远到 1.0（一次 Tween 并行两属性）。
func _play_reveal() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_emblem, "modulate:a", 1.0, EMBLEM_REVEAL_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_emblem, "scale", Vector2.ONE, EMBLEM_REVEAL_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_property(_title_label, "modulate:a", 1.0, 0.8)
	tween.tween_property(_prompt_label, "modulate:a", 1.0, 0.8)
	# 提示语呼吸闪烁（循环）。
	tween.tween_property(_prompt_label, "modulate:a", 0.25, 0.9)
	tween.tween_property(_prompt_label, "modulate:a", 1.0, 0.9)
	tween.set_loops()


func _unhandled_input(event: InputEvent) -> void:
	if _started:
		return
	var pressed_key := event is InputEventKey and (event as InputEventKey).pressed
	var pressed_button := event is InputEventMouseButton and (event as InputEventMouseButton).pressed
	if pressed_key or pressed_button:
		_started = true
		get_tree().change_scene_to_file(MAIN_SCENE_PATH)
