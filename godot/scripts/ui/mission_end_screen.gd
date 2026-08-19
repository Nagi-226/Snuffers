## MissionEndScreen — 结算/失败界面（W5 颜面蜂域，2026-08-19 Phase 0b）
##
## 监听 mission_completed / game_over（幂等，先到先得），暂停游戏树并显示
## 档案卡风格结算：结果 / 击杀数 / 作业用时。L0 叙事皮肤（档案卡体例文案）
## 待机主裁决（08 路线图 #2），本轮用中性文案。
## R 重新开始（GameState.reset + 重载主场景）；Esc 返回标题画面。
extends CanvasLayer

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const TITLE_SCENE_PATH: String = "res://scenes/ui/title_screen.tscn"
## 失败原因文案（契约 reason 词表：enemy/machine_gunner/sniper/mine/generic）。
const REASON_TEXTS: Dictionary = {
	&"enemy": "阵亡——宿主武装火力",
	&"machine_gunner": "阵亡——机枪压制火力",
	&"sniper": "狙击手狙杀",
	&"mine": "触雷",
	&"generic": "任务失败",
}

var _shown: bool = false
var _start_ticks: int = 0

@onready var _panel: Control = $Panel
@onready var _title_label: Label = $Panel/VBox/TitleLabel
@onready var _stats_label: Label = $Panel/VBox/StatsLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.visible = false
	_start_ticks = Time.get_ticks_msec()
	Events.mission_completed.connect(_on_mission_completed)
	Events.game_over.connect(_on_game_over)


## 倒计时期间 pause 后本节点仍须响应按键 → process_mode ALWAYS（_ready 已设）。
func _unhandled_input(event: InputEvent) -> void:
	if not _shown or not (event is InputEventKey and (event as InputEventKey).pressed):
		return
	match (event as InputEventKey).physical_keycode:
		KEY_R:
			_restart()
		KEY_ESCAPE:
			_back_to_title()


func _on_mission_completed() -> void:
	_show(true, "")


func _on_game_over(reason: StringName) -> void:
	_show(false, REASON_TEXTS.get(reason, REASON_TEXTS[&"generic"]))


func _show(victory: bool, reason_text: String) -> void:
	if _shown:
		return
	_shown = true
	var elapsed := (Time.get_ticks_msec() - _start_ticks) / 1000.0
	_title_label.text = "【作业完成 · 已撤离】" if victory else "【任务失败】"
	if not victory:
		_title_label.text += "\n" + reason_text
	_stats_label.text = "宿主清除：%d        作业用时：%02d:%02d" % [
		GameState.kills, int(elapsed) / 60, int(elapsed) % 60,
	]
	_panel.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _restart() -> void:
	GameState.reset()
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _back_to_title() -> void:
	GameState.reset()
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE_SCENE_PATH)
