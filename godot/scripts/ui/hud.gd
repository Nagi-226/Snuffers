## HUD — 战斗抬头显示（CanvasLayer）
##
## 布局（W5 派单）：
##   左上：头/躯/腿三部位血条 + 头盔/护甲条；右上：击杀数；
##   右下：弹药；顶部中央：腿部警告（分级 injured/critical）+ 直升机倒计时；
##   中央：飘字 + 十字准星；准星上方：击杀反馈；全屏底层：受击红晕闪屏。
##
## 数据来源：全部经 Events 信号驱动 + GameState 读取（契约约束 #2/#3）。
## 头盔/护甲无专用变更信号，在 player_damaged / player_health_changed 触发时
## 从 GameState 刷新（见交付报告「需蜂后裁决」）。
## UI 反馈数值（准星 1.3×/1.8×/60ms、飘字 0.8s、红晕/击杀反馈时长）为派单口径，
## 与 events.gd hit_confirmed / message_posted 注释一致；GameConfig 暂无对应参数，
## 未硬编码手感数值（视觉反馈常量集中在本文件头部，缺口清单见交付报告）。
extends CanvasLayer

## 准星命中放大倍率（派单口径；events.gd hit_confirmed 注释：1.3× / 爆头 1.8×）。
const CROSSHAIR_HIT_SCALE: float = 1.3
const CROSSHAIR_HEADSHOT_SCALE: float = 1.8
## 准星放大保持时长 s（派单口径 60ms）。
const CROSSHAIR_PULSE_HOLD: float = 0.06
## 准星恢复过渡时长 s。
const CROSSHAIR_RECOVER_TIME: float = 0.1
## 飘字停留时长 s（派单口径 0.8s，对应网页版 msgArea 800ms）。
const MESSAGE_HOLD_TIME: float = 0.8
## 飘字淡出时长 s。
const MESSAGE_FADE_TIME: float = 0.3
## 受击红晕峰值透明度（派单口径；GameConfig 缺口 DAMAGE_FLASH_PEAK_ALPHA）。
const DAMAGE_FLASH_PEAK_ALPHA: float = 0.35
## 受击红晕淡出时长 s（派单口径；GameConfig 缺口 DAMAGE_FLASH_FADE_TIME）。
const DAMAGE_FLASH_FADE_TIME: float = 0.4
## 击杀反馈停留时长 s（派单口径；GameConfig 缺口 KILL_FEEDBACK_HOLD_TIME）。
const KILL_FEEDBACK_HOLD_TIME: float = 0.6
## 击杀反馈淡出时长 s。
const KILL_FEEDBACK_FADE_TIME: float = 0.4
## 击杀反馈淡出时上飘距离 px。
const KILL_FEEDBACK_RISE_PIXELS: float = 24.0
## 腿部警告分级颜色（视觉样式常量）：受伤橙 / 重伤红。
const LEG_WARN_COLOR_INJURED: Color = Color(0.78, 0.62, 0.35)
const LEG_WARN_COLOR_CRITICAL: Color = Color(0.8, 0.3, 0.25)

@onready var _head_bar: ProgressBar = %HeadBar
@onready var _body_bar: ProgressBar = %BodyBar
@onready var _legs_bar: ProgressBar = %LegsBar
@onready var _helmet_bar: ProgressBar = %HelmetBar
@onready var _armor_bar: ProgressBar = %ArmorBar
@onready var _kills_label: Label = %KillsLabel
@onready var _ammo_label: Label = %AmmoLabel
@onready var _leg_warning_label: Label = %LegWarningLabel
@onready var _message_label: Label = %MessageLabel
@onready var _heli_timer_label: Label = %HeliTimerLabel
@onready var _crosshair: Control = %Crosshair
@onready var _damage_flash: ColorRect = %DamageFlash
@onready var _kill_label: Label = %KillLabel

var _message_tween: Tween
var _crosshair_tween: Tween
var _damage_flash_tween: Tween
var _kill_tween: Tween
## 击杀标签基准 y（_ready 时记录，上飘动画的起点）。
var _kill_label_base_y: float = 0.0


func _ready() -> void:
	_kill_label_base_y = _kill_label.position.y
	_damage_flash.color.a = 0.0
	_refresh_all_from_state()
	_connect_events()


func _exit_tree() -> void:
	_disconnect_events()


## 初始化：从 GameState 全量刷新一次（开局默认值）。
func _refresh_all_from_state() -> void:
	_refresh_vitals()
	_refresh_ammo()
	_refresh_kills(GameState.kills)
	_on_leg_state_changed(GameState.leg_state)


## 五条条：三部位血量 + 头盔 + 护甲（max 取自 GameConfig，禁止硬编码）。
func _refresh_vitals() -> void:
	_set_bar(_head_bar, float(GameState.health.get(&"head", GameConfig.HEALTH_HEAD)), GameConfig.HEALTH_HEAD)
	_set_bar(_body_bar, float(GameState.health.get(&"body", GameConfig.HEALTH_BODY)), GameConfig.HEALTH_BODY)
	_set_bar(_legs_bar, float(GameState.health.get(&"legs", GameConfig.HEALTH_LEGS)), GameConfig.HEALTH_LEGS)
	_set_bar(_helmet_bar, GameState.helmet, GameConfig.HELMET_MAX)
	_set_bar(_armor_bar, GameState.armor, GameConfig.ARMOR_MAX)


func _set_bar(bar: ProgressBar, current: float, maximum: float) -> void:
	bar.max_value = maximum
	bar.value = clampf(current, 0.0, maximum)


func _connect_events() -> void:
	Events.player_health_changed.connect(_on_player_health_changed)
	Events.player_damaged.connect(_on_player_damaged)
	Events.ammo_changed.connect(_on_ammo_changed)
	Events.weapon_switched.connect(_on_weapon_switched)
	Events.leg_state_changed.connect(_on_leg_state_changed)
	Events.message_posted.connect(_on_message_posted)
	Events.kills_changed.connect(_refresh_kills)
	Events.hit_confirmed.connect(_on_hit_confirmed)
	Events.enemy_died.connect(_on_enemy_died)
	Events.heli_called.connect(_on_heli_called)
	Events.heli_timer_updated.connect(_on_heli_timer_updated)
	Events.heli_arrived.connect(_on_heli_arrived)
	Events.mission_completed.connect(_on_mission_ended)
	Events.game_over.connect(_on_game_over)


func _disconnect_events() -> void:
	Events.player_health_changed.disconnect(_on_player_health_changed)
	Events.player_damaged.disconnect(_on_player_damaged)
	Events.ammo_changed.disconnect(_on_ammo_changed)
	Events.weapon_switched.disconnect(_on_weapon_switched)
	Events.leg_state_changed.disconnect(_on_leg_state_changed)
	Events.message_posted.disconnect(_on_message_posted)
	Events.kills_changed.disconnect(_refresh_kills)
	Events.hit_confirmed.disconnect(_on_hit_confirmed)
	Events.enemy_died.disconnect(_on_enemy_died)
	Events.heli_called.disconnect(_on_heli_called)
	Events.heli_timer_updated.disconnect(_on_heli_timer_updated)
	Events.heli_arrived.disconnect(_on_heli_arrived)
	Events.mission_completed.disconnect(_on_mission_ended)
	Events.game_over.disconnect(_on_game_over)


## 部位血量变化：刷新对应条；头盔/护甲顺带从 GameState 同步（无专用信号）。
func _on_player_health_changed(part: StringName, current: float, maximum: float) -> void:
	match part:
		&"head":
			_set_bar(_head_bar, current, maximum)
		&"body":
			_set_bar(_body_bar, current, maximum)
		&"legs":
			_set_bar(_legs_bar, current, maximum)
	_refresh_vitals()


## 受伤（含护甲全吸收不掉血的情况）：五条全量同步 + 受击红晕闪屏。
func _on_player_damaged(_part: StringName, _amount: float) -> void:
	_refresh_vitals()
	_flash_damage_vignette()


## 受击红晕：全屏红层瞬间到峰值后淡出；连续受击重新起峰（派单口径）。
func _flash_damage_vignette() -> void:
	if _damage_flash_tween != null and _damage_flash_tween.is_valid():
		_damage_flash_tween.kill()
	_damage_flash.color.a = DAMAGE_FLASH_PEAK_ALPHA
	_damage_flash_tween = create_tween()
	_damage_flash_tween.tween_property(_damage_flash, "color:a", 0.0, DAMAGE_FLASH_FADE_TIME)


## 弹药变化：仅当报告的是当前武器才刷新显示。
func _on_ammo_changed(weapon_id: StringName, mag: int, reserve: int) -> void:
	if weapon_id != GameState.current_weapon:
		return
	_set_ammo_text(weapon_id, mag, reserve)


## 切枪后按 GameState 刷新（ammo_changed 不一定随切枪重播）。
func _on_weapon_switched(_weapon_id: StringName) -> void:
	_refresh_ammo()


func _refresh_ammo() -> void:
	if GameState.current_weapon == &"rpg":
		_set_ammo_text(&"rpg", GameState.rpg_ammo, -1)
	else:
		_set_ammo_text(&"rifle", GameState.rifle_mag, GameState.rifle_reserve)


## RPG 无弹匣概念：reserve = -1 时只显示火箭弹数（events.gd ammo_changed 注释）。
func _set_ammo_text(weapon_id: StringName, mag: int, reserve: int) -> void:
	if weapon_id == &"rpg" or reserve < 0:
		_ammo_label.text = "火箭弹：%d" % mag
	else:
		_ammo_label.text = "步枪 弹药：%d / %d" % [mag, reserve]


## 腿部警告分级：injured 显示橙色「⚠ 腿部受伤」，critical 显示红色「⚠ 腿部重伤」。
func _on_leg_state_changed(state: StringName) -> void:
	match state:
		&"injured":
			_leg_warning_label.text = "⚠ 腿部受伤"
			_leg_warning_label.add_theme_color_override("font_color", LEG_WARN_COLOR_INJURED)
			_leg_warning_label.visible = true
		&"critical":
			_leg_warning_label.text = "⚠ 腿部重伤"
			_leg_warning_label.add_theme_color_override("font_color", LEG_WARN_COLOR_CRITICAL)
			_leg_warning_label.visible = true
		_:
			_leg_warning_label.visible = false


## 中央飘字：显示 MESSAGE_HOLD_TIME 秒后淡出；新消息顶替旧消息。
func _on_message_posted(text: String) -> void:
	_message_label.text = text
	_message_label.modulate.a = 1.0
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(MESSAGE_HOLD_TIME)
	_message_tween.tween_property(_message_label, "modulate:a", 0.0, MESSAGE_FADE_TIME)


func _refresh_kills(kills: int) -> void:
	_kills_label.text = "击杀：%d" % kills


## 命中反馈：准星放大（普通 1.3× / 爆头 1.8×），保持 60ms 后恢复。
func _on_hit_confirmed(is_headshot: bool) -> void:
	var target_scale: float = CROSSHAIR_HEADSHOT_SCALE if is_headshot else CROSSHAIR_HIT_SCALE
	if _crosshair_tween != null and _crosshair_tween.is_valid():
		_crosshair_tween.kill()
	_crosshair.scale = Vector2.ONE * target_scale
	_crosshair_tween = create_tween()
	_crosshair_tween.tween_interval(CROSSHAIR_PULSE_HOLD)
	_crosshair_tween.tween_property(_crosshair, "scale", Vector2.ONE, CROSSHAIR_RECOVER_TIME)


## 击杀反馈：准星上方飘出确认文字，停留后上飘淡出；连续击杀重新触发。
## 伤害数值飘字契约无对应信号（hit_confirmed 不带伤害量），缺口见交付报告。
func _on_enemy_died(_enemy: Node) -> void:
	if _kill_tween != null and _kill_tween.is_valid():
		_kill_tween.kill()
	_kill_label.position.y = _kill_label_base_y
	_kill_label.modulate.a = 1.0
	_kill_label.visible = true
	_kill_tween = create_tween()
	_kill_tween.tween_interval(KILL_FEEDBACK_HOLD_TIME)
	_kill_tween.tween_property(_kill_label, "modulate:a", 0.0, KILL_FEEDBACK_FADE_TIME)
	_kill_tween.parallel().tween_property(
		_kill_label, "position:y", _kill_label_base_y - KILL_FEEDBACK_RISE_PIXELS, KILL_FEEDBACK_FADE_TIME
	)
	_kill_tween.tween_callback(_kill_label.hide)


## 呼叫后显示倒计时（未呼叫时保持隐藏，派单口径）。
func _on_heli_called() -> void:
	_heli_timer_label.text = "直升机抵达：%d 秒" % ceili(GameState.heli_time_left)
	_heli_timer_label.visible = true


func _on_heli_timer_updated(seconds_left: float) -> void:
	_heli_timer_label.text = "直升机抵达：%d 秒" % ceili(seconds_left)
	_heli_timer_label.visible = true


func _on_heli_arrived() -> void:
	_heli_timer_label.text = "直升机已抵达！"


func _on_mission_ended() -> void:
	_heli_timer_label.visible = false


func _on_game_over(_reason: StringName) -> void:
	_heli_timer_label.visible = false
