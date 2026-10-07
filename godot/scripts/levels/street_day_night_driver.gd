## StreetDayNightDriver — 街区图昼夜驱动器（W7 昼夜/夜视域；派单 13 §S2 方案 A）
##
## 为什么不复用 day_night_controller.gd（派单 13 冲突集 C1-C5）：
## 那套自带 WorldEnvironment + SunLight 子节点，且 NIGHT 预设是 greybox 竞技场的值
## （ambient 0.15 / fog_density 0.005 / BG_COLOR），挂进 street_test 会出现双环境、
## 双平行光，并把已冻结的街区蓝调夜景冲掉。
## 本驱动器**不持有**任何环境/光源子节点，改为向父场景借用 street_test.tscn 既有的
## WorldEnvironment + MoonLight（同 skyline_builder._build_panorama_cards() 的
## get_parent() 先例）。
##
## NIGHT = 零视觉差异冻结：所有夜间值都在运行时从场景/builder 捕获后原样写回，
## 脚本内不存在任何夜间常量，因此日后改 street_test.tscn 不需要同步改这里。
##
## 夜雾事实源仍是 street_builder._apply_fog() + GameConfig.NIGHT_FOG_*：
## NIGHT 态不自作主张定义雾，只回放 builder 写进 Environment 的那三个值。
## DAY 态消费 GameConfig.FOG_*（30m 能见度 / 回南天浓雾）。
extends Node

enum Mode { DAY, NIGHT }

@export var initial_mode: Mode = Mode.NIGHT

var current_mode: Mode = Mode.NIGHT

signal mode_changed(new_mode: Mode)

# 借用来的父场景对象（本驱动器一个都不新建）
var _root: Node = null
var _env: Environment = null
var _sky: ProceduralSkyMaterial = null
var _light: DirectionalLight3D = null

var _bound: bool = false
var _fog_overridden: bool = false

# NIGHT 基线：全部运行时捕获，脚本内零硬编码
var _n_ambient_energy: float = 0.0
var _n_sky_top: Color = Color.BLACK
var _n_sky_horizon: Color = Color.BLACK
var _n_ground_horizon: Color = Color.BLACK
var _n_light_color: Color = Color.BLACK
var _n_light_energy: float = 0.0
var _n_shadow_enabled: bool = false
var _n_fog_density: float = 0.0
var _n_fog_light_color: Color = Color.BLACK
var _n_fog_sun_scatter: float = 0.0

# 自发光衰减目标：天际线塔楼/天线 + Backdrop 楼块（instance uniform brightness）
var _dim_targets: Array[GeometryInstance3D] = []
var _dim_bases: Array[float] = []
# 幕布卡没有 brightness，只能按材质 uniform 衰减（gain）+ 同步天色（sky_color）
var _cards: Array[ShaderMaterial] = []
var _card_gain_bases: Array[float] = []
var _card_sky_bases: Array = []
# 幕布卡节点本体：skyline_card.gdshader 是 unshaded + fog_disabled，
# ALBEDO 直出夜景贴图，昼间无论 gain 衰减还是 sky_color 同步都擦不掉那道夜城色带，
# 唯一契约内解法是昼间隐藏卡节点、夜间原样恢复（故须并行记录节点与捕获的基线可见性）。
var _card_nodes: Array[GeometryInstance3D] = []
var _card_vis_bases: Array[bool] = []


func _ready() -> void:
	current_mode = initial_mode
	if not _bind():
		push_warning("street_day_night_driver: 父场景未提供 WorldEnvironment(ProceduralSky)/MoonLight，驱动器空转（须挂为 street_test.tscn 根节点的子节点）")
		return
	_capture_scene_base()
	# 子节点 _ready 先于父节点：street_builder._ready() 还没跑，Backdrop 与夜雾都不存在。
	# 顺序必须是「先捕获夜雾基线，之后才可能写昼间雾」——否则 initial_mode=DAY 时
	# 同一轮迭代里 physics_frame 早于 process_frame 落地，昼间雾会被当成夜间基线捕走，
	# 之后每次回 NIGHT 都回不到真夜景。
	await get_tree().process_frame
	_capture_runtime_base()
	_apply_mode(current_mode)


## 切换昼夜。派单要求 #6：只提供接口，不接任何玩法入口。
func set_mode(mode: Mode) -> void:
	if mode == current_mode:
		return
	current_mode = mode
	_apply_mode(mode)
	mode_changed.emit(mode)


func toggle_mode() -> void:
	set_mode(Mode.DAY if current_mode == Mode.NIGHT else Mode.NIGHT)


func is_night() -> bool:
	return current_mode == Mode.NIGHT


func _bind() -> bool:
	_root = get_parent()
	if _root == null:
		return false
	var we := _root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_light = _root.get_node_or_null("MoonLight") as DirectionalLight3D
	if we == null or we.environment == null or _light == null:
		return false
	_env = we.environment
	if _env.sky != null:
		_sky = _env.sky.sky_material as ProceduralSkyMaterial
	if _sky == null:
		return false
	_bound = true
	return true


func _capture_scene_base() -> void:
	_n_ambient_energy = _env.ambient_light_energy
	_n_sky_top = _sky.sky_top_color
	_n_sky_horizon = _sky.sky_horizon_color
	_n_ground_horizon = _sky.ground_horizon_color
	_n_light_color = _light.light_color
	_n_light_energy = _light.light_energy
	_n_shadow_enabled = _light.shadow_enabled


func _capture_runtime_base() -> void:
	_n_fog_density = _env.fog_density
	_n_fog_light_color = _env.fog_light_color
	_n_fog_sun_scatter = _env.fog_sun_scatter
	_collect_emission_targets()


func _collect_emission_targets() -> void:
	_dim_targets.clear()
	_dim_bases.clear()
	_cards.clear()
	_card_gain_bases.clear()
	_card_sky_bases.clear()
	_card_nodes.clear()
	_card_vis_bases.clear()
	# owned=false 是必须的：天际线塔楼与 Backdrop 楼块都是运行时 add_child 出来的，
	# owner 为空，用默认的 owned=true 会整个漏掉（find_children 的第四个参数）。
	for child in _root.find_children("*", "GeometryInstance3D", true, false):
		var gi := child as GeometryInstance3D
		if gi.name.begins_with("PanoCard_") and gi.material_override is ShaderMaterial:
			_register_card(gi)
			continue
		# brightness 是 skyline_facade（v3 塔楼）与 skyline_windows（天线 / Backdrop 楼块）
		# 共有的 instance uniform；逐塔由 skyline_builder._spawn_tower 注入，
		# 逐楼块由 street_builder._add_windowed_block 注入。
		# 只认已被显式注入过的实例——应急灯与力场幕布没有该参数，天然不受影响（派单要求 #7）。
		var base: Variant = gi.get_instance_shader_parameter("brightness")
		if typeof(base) == TYPE_FLOAT:
			_dim_targets.append(gi)
			_dim_bases.append(base)


func _register_card(gi: GeometryInstance3D) -> void:
	var mat := gi.material_override as ShaderMaterial
	var gain: Variant = mat.get_shader_parameter("gain")
	if typeof(gain) != TYPE_FLOAT:
		return
	_cards.append(mat)
	_card_gain_bases.append(gain)
	# sky_color 声明为 vec3，读回来可能是 Color 也可能是 Vector3；
	# 原样存原样写回，不做任何类型转换。
	_card_sky_bases.append(mat.get_shader_parameter("sky_color"))
	_card_nodes.append(gi)
	_card_vis_bases.append(gi.visible)


func _apply_mode(mode: Mode) -> void:
	if not _bound:
		return
	# 同步昼夜运行时状态到契约（GameState.is_night；夜视仪门控消费）
	GameState.is_night = (mode == Mode.NIGHT)
	match mode:
		Mode.NIGHT:
			_env.ambient_light_energy = _n_ambient_energy
			_sky.sky_top_color = _n_sky_top
			_sky.sky_horizon_color = _n_sky_horizon
			_sky.ground_horizon_color = _n_ground_horizon
			_light.light_color = _n_light_color
			_light.light_energy = _n_light_energy
			_light.shadow_enabled = _n_shadow_enabled
			_restore_fog()
			_restore_emission()
		Mode.DAY:
			_env.ambient_light_energy = GameConfig.STREET_DAY_AMBIENT_ENERGY
			_sky.sky_top_color = GameConfig.STREET_DAY_SKY_TOP_COLOR
			_sky.sky_horizon_color = GameConfig.STREET_DAY_SKY_HORIZON_COLOR
			# 夜间不变量：ground_horizon_color == sky_horizon_color（street_test.tscn）。
			# 冻结契约只给了两个天色，昼间沿用同一不变量，不新造常量。
			_sky.ground_horizon_color = GameConfig.STREET_DAY_SKY_HORIZON_COLOR
			_light.light_color = GameConfig.STREET_DAY_SUN_COLOR
			_light.light_energy = GameConfig.STREET_DAY_SUN_ENERGY
			_light.shadow_enabled = true
			_apply_emission()
			_apply_day_fog_deferred()


## DAY 雾延后一个物理帧再写（派单要求 #3）：street_builder._ready() 在本驱动器之后运行，
## 它会用 NIGHT_FOG_* 覆盖 Environment；不延后的话昼间雾会被夜雾冲掉。
## --shot 分支截屏前会等 15 个 process 帧，一个物理帧的延后落在窗口内。
func _apply_day_fog_deferred() -> void:
	await get_tree().physics_frame
	# 快速来回切时可能已被切回 NIGHT，此时不写、也不置位，_restore_fog() 会正确空转。
	if current_mode != Mode.DAY or not _bound:
		return
	_env.fog_density = GameConfig.FOG_DENSITY
	_env.fog_light_color = GameConfig.FOG_LIGHT_COLOR
	_env.fog_sun_scatter = GameConfig.FOG_SUN_SCATTER
	_fog_overridden = true


## 只有真写过昼间雾才回放夜雾——初始即 NIGHT 时本函数一个 fog_* 字节都不写（派单要求 #3）。
func _restore_fog() -> void:
	if not _fog_overridden:
		return
	_env.fog_density = _n_fog_density
	_env.fog_light_color = _n_fog_light_color
	_env.fog_sun_scatter = _n_fog_sun_scatter
	_fog_overridden = false


func _apply_emission() -> void:
	var dim: float = GameConfig.STREET_DAY_SKYLINE_EMISSION_SCALE
	for i in _dim_targets.size():
		_dim_targets[i].set_instance_shader_parameter("brightness", _dim_bases[i] * dim)
	for i in _cards.size():
		_cards[i].set_shader_parameter("gain", _card_gain_bases[i] * dim)
		# 幕布卡的 sky_color 是 skyline_builder 一次性烘焙进去的夜间天色，
		# 不同步就会出现「白天头顶 + 夜天际线」两道天光的分界（机主 2026-09-27 明令禁止）。
		# 幕布贴在 horizon 高度，须对齐 horizon 天色；用 top 天色会在地平线横出一条色带。
		_cards[i].set_shader_parameter("sky_color", GameConfig.STREET_DAY_SKY_HORIZON_COLOR)
	# gain/sky_color 只调发光与顶部收敛色，但卡是 unshaded+fog_disabled，ALBEDO 直出夜景贴图，
	# 昼间那道夜城色带无论怎么调都擦不掉——唯一契约内解法是昼间直接隐藏卡节点。
	for i in _card_nodes.size():
		_card_nodes[i].visible = false


func _restore_emission() -> void:
	for i in _dim_targets.size():
		_dim_targets[i].set_instance_shader_parameter("brightness", _dim_bases[i])
	for i in _cards.size():
		_cards[i].set_shader_parameter("gain", _card_gain_bases[i])
		_cards[i].set_shader_parameter("sky_color", _card_sky_bases[i])
	for i in _card_nodes.size():
		_card_nodes[i].visible = _card_vis_bases[i]
