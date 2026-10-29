## HUD — 战斗抬头显示（CanvasLayer）
##
## 布局（W5 派单）：
##   左上：头/躯/腿三部位血条 + 护甲条；右上：击杀数；
##   右下：弹药；顶部中央：腿部警告（分级 injured/critical）+ 直升机倒计时；
##   中央：飘字 + 十字准星；准星上方：击杀反馈；全屏底层：受击红晕闪屏。
##
## 数据来源：全部经 Events 信号驱动 + GameState 读取（契约约束 #2/#3）。
## 护甲有专用信号 armor_changed（2026-10-19 纳米服式回充配套；头盔模块同日取消）。
## UI 反馈数值（准星放大/停留、飘字停留、红晕峰值/淡出、击杀反馈停留）已随 G2 契约
## 冻结迁入 GameConfig「UI 反馈动效」组，本文件不再保留同名常量；其余纯视觉样式常量
## （颜色/字号/过渡时长/上飘像素）契约未含，集中在本文件头部。
extends CanvasLayer

@export var district_mode: bool = false

## 准星恢复过渡时长 s（视觉表现常量）。
const CROSSHAIR_RECOVER_TIME: float = 0.1
## 飘字淡出时长 s（视觉表现常量）。
const MESSAGE_FADE_TIME: float = 0.3
## 击杀反馈淡出时长 s（视觉表现常量）。
const KILL_FEEDBACK_FADE_TIME: float = 0.4
## 击杀反馈淡出时上飘距离 px（视觉表现常量）。
const KILL_FEEDBACK_RISE_PIXELS: float = 24.0
## 伤害飘字淡出时长 s（视觉表现常量；契约冻结未含，如需调参由蜂后下轮冻结迁入）。
const DAMAGE_TEXT_FADE_TIME: float = 0.5
## 即杀阈值：amount ≥ 900（狙击即杀 999 / RPG 爆径 9999）时飘字显示「击毙」而非数字
## （契约冻结未含，如需调参由蜂后下轮冻结迁入）。
const DAMAGE_TEXT_INSTAKILL_THRESHOLD: float = 900.0
## 即杀飘字文案（阈值内不显示裸数值，避免 999/9999 观感突兀）。
const DAMAGE_TEXT_INSTAKILL_LABEL: String = "击毙"
## 伤害飘字上飘距离 px（视觉表现常量）。
const DAMAGE_TEXT_RISE_PIXELS: float = 28.0
## 伤害飘字字号：普通 / 爆头（视觉样式常量）。
const DAMAGE_TEXT_FONT_SIZE: int = 16
const DAMAGE_TEXT_FONT_SIZE_HEADSHOT: int = 22
## 伤害飘字颜色：普通米白 / 爆头警示橙（视觉样式常量）。
const DAMAGE_TEXT_COLOR: Color = Color(0.85, 0.83, 0.78)
const DAMAGE_TEXT_COLOR_HEADSHOT: Color = Color(0.9, 0.55, 0.25)
## 腿部警告分级颜色与「⚠ 腿部受伤」机制已于 2026-10-21 随三部位耐久制一同退役
## （场景内 LegWarningLabel 节点保留但隐藏，HUD 编辑时清理）。

@onready var _body_bar: ProgressBar = %BodyBar
@onready var _armor_bar: ProgressBar = %ArmorBar
@onready var _kills_label: Label = %KillsLabel
@onready var _ammo_label: Label = %AmmoLabel
@onready var _message_label: Label = %MessageLabel
@onready var _heli_timer_label: Label = %HeliTimerLabel
@onready var _intel_label: Label = %IntelLabel
@onready var _crosshair: Control = %Crosshair
@onready var _damage_flash: ColorRect = %DamageFlash
@onready var _kill_label: Label = %KillLabel
@onready var _damage_label: Label = %DamageLabel
@onready var _mission_title: Label = %MissionTitle
@onready var _mission_key: Label = %MissionKey
@onready var _mission_intel: Label = %MissionIntel

## 任务栏文案色（视觉样式常量）：完成=绿 / 未完成=米白。
const MISSION_DONE_COLOR := Color(0.55, 0.95, 0.55, 1.0)
const MISSION_TODO_COLOR := Color(0.88, 0.86, 0.8, 0.95)

## 任务栏缓存态（_process 轮询去抖：值没变不重写文本）。
var _mission_sig := ""
var _weapon_selector: PanelContainer
var _selector_slots: Dictionary = {}
var _selector_name: Label
var _selector_time_left: float = 0.0
var _selector_style_normal: StyleBoxFlat
var _selector_style_active: StyleBoxFlat

var _message_tween: Tween
var _crosshair_tween: Tween
var _damage_flash_tween: Tween
var _kill_tween: Tween
var _damage_tween: Tween
## 击杀标签基准 y（_ready 时记录，上飘动画的起点）。
var _kill_label_base_y: float = 0.0
## 伤害飘字基准 y（_ready 时记录，上飘动画的起点）。
var _damage_label_base_y: float = 0.0


func _ready() -> void:
	_kill_label_base_y = _kill_label.position.y
	_damage_label_base_y = _damage_label.position.y
	_damage_flash.color.a = 0.0
	if district_mode:
		get_node("Minimap").visible = false
		get_node("CompassBar").show_mission_markers = false
		_intel_label.visible = false
	_build_weapon_selector()
	_refresh_all_from_state()
	_refresh_mission(true)
	_connect_events()


func _process(delta: float) -> void:
	_refresh_mission(false)
	if _selector_time_left > 0.0:
		_selector_time_left -= delta
		if _selector_time_left <= 0.0:
			_weapon_selector.visible = false
			_heli_timer_label.offset_top = 48.0
			_heli_timer_label.offset_bottom = 80.0


func _build_weapon_selector() -> void:
	_weapon_selector = PanelContainer.new()
	_weapon_selector.name = "WeaponSelector"
	_weapon_selector.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_weapon_selector.offset_left = -400.0
	_weapon_selector.offset_right = 400.0
	_weapon_selector.offset_top = 54.0
	_weapon_selector.offset_bottom = 132.0
	_weapon_selector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_selector.visible = false
	_weapon_selector.set_meta("category", 0)
	_weapon_selector.add_theme_stylebox_override("panel", _selector_style(
		Color(0.015, 0.025, 0.03, 0.88), Color(0.95, 0.72, 0.22, 0.5)))
	add_child(_weapon_selector)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 7)
	_weapon_selector.add_child(margin)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 4)
	margin.add_child(rows)
	var slots := HBoxContainer.new()
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slots.add_theme_constant_override("separation", 4)
	rows.add_child(slots)
	_selector_style_normal = _selector_style(Color(0.035, 0.065, 0.08, 0.78), Color(0.4, 0.75, 0.85, 0.25))
	_selector_style_active = _selector_style(Color(0.24, 0.18, 0.045, 0.94), Color(1.0, 0.8, 0.22, 0.95))
	for category: Dictionary in GameConfig.WEAPON_CATEGORIES:
		var slot := PanelContainer.new()
		slot.custom_minimum_size.x = 122.0
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_theme_stylebox_override("panel", _selector_style_normal)
		slots.add_child(slot)
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_theme_constant_override("separation", 0)
		slot.add_child(column)
		column.add_child(_selector_label(str(category.number), 16, Color(0.65, 0.9, 1.0)))
		column.add_child(_selector_label(category.name, 12, Color(0.65, 0.8, 0.85)))
		_selector_slots[category.number] = slot
	_selector_name = _selector_label("", 14, Color(1.0, 0.84, 0.35))
	rows.add_child(_selector_name)


func _selector_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	return style


func _selector_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _show_weapon_selector(category_number: int) -> void:
	_weapon_selector.set_meta("category", category_number)
	_weapon_selector.visible = true
	_heli_timer_label.offset_top = 142.0
	_heli_timer_label.offset_bottom = 174.0
	_selector_time_left = GameConfig.WEAPON_SELECTOR_HOLD_TIME
	for category: Dictionary in GameConfig.WEAPON_CATEGORIES:
		var number: int = category.number
		var slot := _selector_slots[number] as PanelContainer
		var unlocked := false
		for weapon_id: StringName in category.weapons:
			unlocked = unlocked or GameState.weapon_unlocked.get(weapon_id, false)
		slot.modulate = Color.WHITE if unlocked else Color(1.0, 1.0, 1.0, 0.32)
		slot.add_theme_stylebox_override("panel",
			_selector_style_active if number == category_number else _selector_style_normal)
		if number == category_number:
			if GameState.current_weapon in category.weapons:
				_selector_name.text = _weapon_display_name(GameState.current_weapon)
			else:
				_selector_name.text = category.name + (" · 预留" if category.weapons.is_empty() else " · 未领取")


func _category_for_weapon(weapon_id: StringName) -> int:
	for category: Dictionary in GameConfig.WEAPON_CATEGORIES:
		if weapon_id in category.weapons:
			return category.number
	return 1


func _weapon_display_name(weapon_id: StringName) -> String:
	match weapon_id:
		&"pistol":
			return "EM-57P 手枪"
		&"rifle":
			return "EM-68A 突击步枪"
		&"dmr":
			return "EM-68D 穿杨 · DMR"
		&"shotgun":
			return "EM-12G-1 霰·Ⅰ"
	return "未获取"


## 任务栏（2026-10-25 机主立项）：生命值/护甲框【下方框外】常驻显示当前任务与
## 目标进度——门 B 通行前置 = 铁栅栏门钥匙（E5 车库后院）+ 取证终端（E1/E2 楼内）。
## 数据源 GameState（gate_key_have / intel / intel_total）+ GameConfig（GATE_INTEL_REQUIRED）。
func _refresh_mission(force: bool) -> void:
	if district_mode:
		var dmr_done: bool = GameState.weapon_unlocked.get(&"dmr", false)
		var shotgun_done: bool = GameState.weapon_unlocked.get(&"shotgun", false)
		var district_sig := "%s|%s" % [dmr_done, shotgun_done]
		if not force and district_sig == _mission_sig:
			return
		_mission_sig = district_sig
		_mission_title.text = "任务：前往 JB-02 后舱领取雷暴装备"
		_mission_key.text = ("✔ EM-68D 穿杨 已领取" if dmr_done else "◇ EM-68D 穿杨 待领取")
		_mission_key.add_theme_color_override("font_color", MISSION_DONE_COLOR if dmr_done else MISSION_TODO_COLOR)
		_mission_intel.text = ("✔ EM-12G-1 霰·Ⅰ 已领取" if shotgun_done else "◇ EM-12G-1 霰·Ⅰ 待领取")
		_mission_intel.add_theme_color_override("font_color", MISSION_DONE_COLOR if shotgun_done else MISSION_TODO_COLOR)
		return
	var key_done: bool = GameState.gate_key_have
	var intel_need: int = GameConfig.GATE_INTEL_REQUIRED
	var intel_total: int = maxi(GameState.intel_total, intel_need)
	var intel_done: bool = GameState.intel >= intel_need
	var sig := "%s|%d" % [key_done, GameState.intel]
	if not force and sig == _mission_sig:
		return
	_mission_sig = sig
	_mission_key.text = ("✔ 铁栅栏门钥匙  已取得" if key_done
		else "◇ 铁栅栏门钥匙 0/1（E5 车库后院）")
	_mission_key.add_theme_color_override("font_color",
		MISSION_DONE_COLOR if key_done else MISSION_TODO_COLOR)
	# 终端行：需求=全图总数（机主四轮裁决 3 台全收），三处位置入文案
	_mission_intel.text = ("✔ 取证终端 已集齐 %d/%d" % [GameState.intel, intel_total]
		if intel_done else "◇ 取证终端 %d/%d（E1 二层·E2 三层·E3 车库）"
		% [GameState.intel, intel_need])
	_mission_intel.add_theme_color_override("font_color",
		MISSION_DONE_COLOR if intel_done else MISSION_TODO_COLOR)
	_mission_title.text = ("任务：穿过 E1/E2 巷尽头的铁栅栏门" if key_done and intel_done
		else "任务：收集铁栅栏门通行凭证")


func _exit_tree() -> void:
	_disconnect_events()


## 初始化：从 GameState 全量刷新一次（开局默认值）。
func _refresh_all_from_state() -> void:
	_refresh_vitals()
	_refresh_ammo()
	_refresh_kills(GameState.kills)


## 两条条：生命值 + 护甲能量（2026-10-21 机主裁决：三部位耐久制取消；
## 场景内头部/腿部行保留但脚本不再驱动，HUD 编辑时隐藏）。
func _refresh_vitals() -> void:
	_set_bar(_body_bar, GameState.hp, GameConfig.HEALTH_MAX)
	_set_bar(_armor_bar, GameState.armor, GameConfig.ARMOR_MAX)


func _set_bar(bar: ProgressBar, current: float, maximum: float) -> void:
	bar.max_value = maximum
	bar.value = clampf(current, 0.0, maximum)


func _connect_events() -> void:
	Events.player_health_changed.connect(_on_player_health_changed)
	Events.player_damaged.connect(_on_player_damaged)
	Events.armor_changed.connect(_on_armor_changed)
	Events.player_aim_changed.connect(_on_player_aim_changed)
	Events.ammo_changed.connect(_on_ammo_changed)
	Events.weapon_switched.connect(_on_weapon_switched)
	Events.weapon_category_selected.connect(_show_weapon_selector)
	Events.fire_mode_changed.connect(_on_fire_mode_changed)
	Events.message_posted.connect(_on_message_posted)
	Events.kills_changed.connect(_refresh_kills)
	Events.intel_picked.connect(_on_intel_picked)
	Events.hit_confirmed.connect(_on_hit_confirmed)
	Events.enemy_died.connect(_on_enemy_died)
	Events.damage_dealt.connect(_on_damage_dealt)
	Events.bunker_destroyed.connect(_on_bunker_destroyed)
	Events.heli_called.connect(_on_heli_called)
	Events.heli_timer_updated.connect(_on_heli_timer_updated)
	Events.heli_arrived.connect(_on_heli_arrived)
	Events.mission_completed.connect(_on_mission_ended)
	Events.game_over.connect(_on_game_over)


func _disconnect_events() -> void:
	Events.player_health_changed.disconnect(_on_player_health_changed)
	Events.player_damaged.disconnect(_on_player_damaged)
	Events.armor_changed.disconnect(_on_armor_changed)
	Events.player_aim_changed.disconnect(_on_player_aim_changed)
	Events.ammo_changed.disconnect(_on_ammo_changed)
	Events.weapon_switched.disconnect(_on_weapon_switched)
	Events.weapon_category_selected.disconnect(_show_weapon_selector)
	Events.fire_mode_changed.disconnect(_on_fire_mode_changed)
	Events.message_posted.disconnect(_on_message_posted)
	Events.kills_changed.disconnect(_refresh_kills)
	Events.intel_picked.disconnect(_on_intel_picked)
	Events.hit_confirmed.disconnect(_on_hit_confirmed)
	Events.enemy_died.disconnect(_on_enemy_died)
	Events.damage_dealt.disconnect(_on_damage_dealt)
	Events.bunker_destroyed.disconnect(_on_bunker_destroyed)
	Events.heli_called.disconnect(_on_heli_called)
	Events.heli_timer_updated.disconnect(_on_heli_timer_updated)
	Events.heli_arrived.disconnect(_on_heli_arrived)
	Events.mission_completed.disconnect(_on_mission_ended)
	Events.game_over.disconnect(_on_game_over)


## 生命值变化：刷新生命条 + 全量同步（part 恒为 &"hp"，2026-10-21 单一生命值制）。
func _on_player_health_changed(_part: StringName, current: float, maximum: float) -> void:
	_set_bar(_body_bar, current, maximum)
	_refresh_vitals()


## 受伤（含护甲全吸收不掉血的情况）：两条全量同步 + 受击红晕闪屏。
func _on_player_damaged(_part: StringName, _amount: float) -> void:
	_refresh_vitals()
	_flash_damage_vignette()


## 护甲能量变化（脱战回充专用信号，2026-10-19 机主立项）。
func _on_armor_changed(current: float, maximum: float) -> void:
	_set_bar(_armor_bar, current, maximum)


## 受击红晕：全屏红层瞬间到峰值后淡出；连续受击重新起峰（派单口径）。
func _flash_damage_vignette() -> void:
	if _damage_flash_tween != null and _damage_flash_tween.is_valid():
		_damage_flash_tween.kill()
	_damage_flash.color.a = GameConfig.DAMAGE_FLASH_PEAK_ALPHA
	_damage_flash_tween = create_tween()
	_damage_flash_tween.tween_property(_damage_flash, "color:a", 0.0, GameConfig.DAMAGE_FLASH_FADE_TIME)


## 弹药变化：仅当报告的是当前武器才刷新显示。
func _on_ammo_changed(weapon_id: StringName, mag: int, reserve: int) -> void:
	if weapon_id != GameState.current_weapon:
		return
	_set_ammo_text(weapon_id, mag, reserve)


## 切枪后按 GameState 刷新（ammo_changed 不一定随切枪重播）；准星显隐同步复评。
func _on_weapon_switched(_weapon_id: StringName) -> void:
	_refresh_ammo()
	_on_player_aim_changed(GameState.is_aiming)
	_show_weapon_selector(_category_for_weapon(_weapon_id))


## 开镜时隐藏 HUD 腰射准星（ADS 覆盖层接管；榴档开镜同样接管）。
func _on_player_aim_changed(aiming: bool) -> void:
	_crosshair.visible = not aiming


func _refresh_ammo() -> void:
	match GameState.current_weapon:
		&"pistol":
			_set_ammo_text(&"pistol", GameState.pistol_mag, GameState.pistol_reserve)
		&"dmr":
			_set_ammo_text(&"dmr", GameState.dmr_mag, GameState.rifle_reserve)
		&"shotgun":
			_set_ammo_text(&"shotgun", GameState.shotgun_mag, GameState.shotgun_reserve)
		_:
			_set_ammo_text(&"rifle", GameState.rifle_mag, GameState.rifle_reserve)


## 射击模式切换（X 键，2026-10-19 机主立项）：仅当报告的是当前武器才刷新显示。
func _on_fire_mode_changed(weapon_id: StringName, _mode: StringName) -> void:
	if weapon_id == GameState.current_weapon:
		_refresh_ammo()


## 弹药行：步枪/手枪附加当前射击模式标（GameState.fire_modes 契约字段）。
## 步枪榴档（&"grenade"，EM-40G 滚雷，2026-10-22 并入）显示榴弹余量而非弹匣——
## 模块总数制无备弹，余量直读 GameState.rifle_grenades。
func _set_ammo_text(weapon_id: StringName, mag: int, reserve: int) -> void:
	var mode: StringName = GameState.fire_modes.get(weapon_id, &"auto")
	if weapon_id == &"rifle" and mode == &"grenade":
		_ammo_label.text = "EM-68A [滚雷] EC-40P 破垒榴弹：%d" % GameState.rifle_grenades
		return
	var mode_tag := ""
	match mode:
		&"auto":
			mode_tag = "[全自动]"
		&"burst":
			mode_tag = "[三点射]"
		&"semi":
			mode_tag = "[半自动]"
	match weapon_id:
		&"pistol":
			_ammo_label.text = "EM-57P %s EC-57 无壳手枪弹：%d / %d" % [mode_tag, mag, reserve]
		&"dmr":
			_ammo_label.text = "EM-68D 穿杨 %s EC-68 无壳步枪弹：%d / %d" % [mode_tag, mag, reserve]
		&"shotgun":
			_ammo_label.text = "EM-12G-1 霰·Ⅰ %s EC-12 砂：%d / %d" % [mode_tag, mag, reserve]
		_:
			_ammo_label.text = "EM-68A %s EC-68 无壳步枪弹：%d / %d" % [mode_tag, mag, reserve]


## 腿部警告分级（2026-10-21 随三部位耐久制退役，函数移除）。


## 中央飘字：显示 GameConfig.MESSAGE_HOLD_TIME 秒后淡出；新消息顶替旧消息。
func _on_message_posted(text: String) -> void:
	_message_label.text = text
	_message_label.modulate.a = 1.0
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(GameConfig.MESSAGE_HOLD_TIME)
	_message_tween.tween_property(_message_label, "modulate:a", 0.0, MESSAGE_FADE_TIME)


func _refresh_kills(kills: int) -> void:
	_kills_label.text = "击杀：%d" % kills


## 取证终端收集进度（2026-10-07 拾取契约的信号消费端）：
## 首次拾取后常驻显示——中央飘字 MESSAGE_HOLD_TIME 后即淡出，
## 而收集品的「还差几个」属于需要常读的信息；总数由地图 builder 注入。
func _on_intel_picked(collected: int, total: int) -> void:
	_intel_label.text = "取证终端：%d / %d" % [collected, total]
	_intel_label.visible = true


## 命中反馈：准星放大（普通 / 爆头倍率见 GameConfig「UI 反馈动效」组），保持后恢复。
func _on_hit_confirmed(is_headshot: bool) -> void:
	var target_scale: float = (
		GameConfig.CROSSHAIR_HEADSHOT_SCALE if is_headshot else GameConfig.CROSSHAIR_HIT_SCALE
	)
	if _crosshair_tween != null and _crosshair_tween.is_valid():
		_crosshair_tween.kill()
	_crosshair.scale = Vector2.ONE * target_scale
	_crosshair_tween = create_tween()
	_crosshair_tween.tween_interval(GameConfig.CROSSHAIR_PULSE_HOLD)
	_crosshair_tween.tween_property(_crosshair, "scale", Vector2.ONE, CROSSHAIR_RECOVER_TIME)


## 击杀反馈：准星上方飘出确认文字，停留后上飘淡出；连续击杀重新触发。
func _on_enemy_died(_enemy: Node) -> void:
	if _kill_tween != null and _kill_tween.is_valid():
		_kill_tween.kill()
	_kill_label.position.y = _kill_label_base_y
	_kill_label.modulate.a = 1.0
	_kill_label.visible = true
	_kill_tween = create_tween()
	_kill_tween.tween_interval(GameConfig.KILL_FEEDBACK_HOLD_TIME)
	_kill_tween.tween_property(_kill_label, "modulate:a", 0.0, KILL_FEEDBACK_FADE_TIME)
	_kill_tween.parallel().tween_property(
		_kill_label, "position:y", _kill_label_base_y - KILL_FEEDBACK_RISE_PIXELS, KILL_FEEDBACK_FADE_TIME
	)
	_kill_tween.tween_callback(_kill_label.hide)


## 伤害数值飘字：准星下方显示伤害量，上飘淡出；爆头加大字号 + 警示橙区分；
## 即杀量（≥ DAMAGE_TEXT_INSTAKILL_THRESHOLD，如狙击 999 / RPG 爆径 9999）显示「击毙」替代数字。
func _on_damage_dealt(amount: float, is_headshot: bool) -> void:
	if amount >= DAMAGE_TEXT_INSTAKILL_THRESHOLD:
		_damage_label.text = DAMAGE_TEXT_INSTAKILL_LABEL
	else:
		_damage_label.text = "%d" % roundi(amount)
	_damage_label.add_theme_font_size_override(
		"font_size", DAMAGE_TEXT_FONT_SIZE_HEADSHOT if is_headshot else DAMAGE_TEXT_FONT_SIZE
	)
	_damage_label.add_theme_color_override(
		"font_color", DAMAGE_TEXT_COLOR_HEADSHOT if is_headshot else DAMAGE_TEXT_COLOR
	)
	if _damage_tween != null and _damage_tween.is_valid():
		_damage_tween.kill()
	_damage_label.position.y = _damage_label_base_y
	_damage_label.modulate.a = 1.0
	_damage_label.visible = true
	_damage_tween = create_tween()
	_damage_tween.tween_property(_damage_label, "modulate:a", 0.0, DAMAGE_TEXT_FADE_TIME)
	_damage_tween.parallel().tween_property(
		_damage_label, "position:y", _damage_label_base_y - DAMAGE_TEXT_RISE_PIXELS, DAMAGE_TEXT_FADE_TIME
	)
	_damage_tween.tween_callback(_damage_label.hide)


## 碉堡被摧毁：走中央飘字通道（对应网页版 msgArea 语义；KillLabel 专司击杀确认，
## 碉堡摧毁非击杀事件，不走 GameState 击杀记账链路）。
func _on_bunker_destroyed() -> void:
	_on_message_posted("碉堡被摧毁！")


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
