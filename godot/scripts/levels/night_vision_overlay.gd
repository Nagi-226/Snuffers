## NightVisionOverlay — 夜视仪屏幕采样亮度增益（W7 昼夜域，派单 16 选项 2）
##
## 契约约束（AGENTS.md）：
## - 消费 Events.night_vision_toggled（已存在，events.gd L81）。
## - 读取 GameState.night_vision 同步状态。
## - 键位 N（§11.2 机主裁决，player_controller.gd 已翻正）；有玩家在场时本脚本让位，
##   由 player_controller 统一发信号；白天禁开门控读 GameState.is_night。
##
## 效果：①场景环境光抬升（2026-10-25 机主指令：vm-shot 取证全图提亮融入——
## 黑夜中大面积纯黑抬不出几何细节，先真实照亮全场景）+ ②屏幕采样亮度增益
## （派单 16 选项 2）——`hint_screen_texture` 取全屏 back-buffer
## → 暗部 lift → 去饱和 → 绿磷光色调 → 过曝区趋白 → 扫描线 + 暗角。
## 自发光体（应急灯/力场蓝光/天际线亮窗）在增益下自然过曝发白，是真实夜视仪
## 光晕行为，属特性而非缺陷（05 文档 §4.2 选项 2）。
## 仅黑夜模式下可用（白天按 N 无反应）。
extends CanvasLayer

## 夜视效果着色器源码（W7 域内内联；G4 后由 W5 替换正式夜视素材/后期）。
## 采样范式取自 Godot 官方 screen-reading shaders 文档的 brightness/contrast/
## saturation 示例：`textureLod(screen_texture, SCREEN_UV, 0.0)`。
## 首个使用 hint_screen_texture 的材质会触发全屏 back-buffer 拷贝；本 overlay
## 是场景内唯一的屏幕采样者，不存在「第二个采样者读到旧缓冲」的问题。
const _NV_SHADER_CODE: String = "
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float gain : hint_range(0.0, 4.0);
uniform float shadow_lift_gamma : hint_range(0.2, 1.0);
uniform float black_floor : hint_range(0.0, 0.2);
uniform float desaturation : hint_range(0.0, 1.0);
uniform vec3 phosphor;
uniform float bloom_start : hint_range(0.0, 2.0);
uniform float bloom_width : hint_range(0.01, 2.0);
uniform float bloom_strength : hint_range(0.0, 1.0);
uniform float scanline_density : hint_range(100.0, 1200.0) = 600.0;
uniform float scanline_alpha : hint_range(0.0, 0.5) = 0.08;
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.45;
uniform float vignette_floor : hint_range(0.0, 1.0);

void fragment() {
	vec3 src = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;

	// 暗部 lift：gamma 趾部抬升（暗部提升远大于亮部，故不会把夜景洗成白昼）
	// + 曝光增益 + 纯黑抬底（像增强管自带底噪，绝对黑不存在）。
	vec3 g = pow(max(src, vec3(0.0)), vec3(shadow_lift_gamma)) * gain + vec3(black_floor);

	// 去饱和：像增强管只有单色磷光，色信息基本丢失。
	float luma = dot(g, vec3(0.2126, 0.7152, 0.0722));
	g = mix(g, vec3(luma), desaturation);

	// 绿磷光着色；过曝区把三通道一起回灌 → 自发光体发白发亮（传感器 blooming）。
	vec3 tinted = g * phosphor;
	float bloom = smoothstep(bloom_start, bloom_start + bloom_width, luma);
	tinted = mix(tinted, vec3(1.0), bloom * bloom_strength);

	// 扫描线（明暗相间条纹）+ 暗角（圆形像增强器边缘衰减，保留 floor 不全黑）。
	float scanline = sin(UV.y * scanline_density * 3.14159) * scanline_alpha;
	float dist = length(UV - 0.5);
	float vignette = smoothstep(0.7, 0.7 - vignette_softness, dist);
	tinted *= (1.0 - scanline) * mix(vignette_floor, 1.0, vignette);

	// intensity = 夜视强度总推子：0 为原画，1 为满夜视。
	COLOR = vec4(mix(src, tinted, intensity), 1.0);
}
"

## 增益/去饱和/绿调色相（派单 16：留脚本本地 const，不入 game_config.gd 契约）。
## 若后续需要跨模块调参，按外部 Agent 协同协议 #3 提「契约变更申请」，勿自行入契约。
const NV_GAIN := 1.15                  ## 曝光增益（乘在 lift 之后）
const NV_SHADOW_LIFT_GAMMA := 0.55     ## <1 抬暗部；越小暗部越亮
const NV_BLACK_FLOOR := 0.02           ## 纯黑抬底（管底噪）
const NV_DESATURATION := 0.88          ## 去饱和度（1 = 全灰）
const NV_PHOSPHOR := Vector3(0.35, 0.92, 1.0)  ## 青蓝磷光色调（乘性；2026-10-18 机主裁决：绿→青蓝，贴合雷暴部队夜视仪形象设定）
const NV_BLOOM_START := 0.62           ## 过曝趋白的亮度阈值
const NV_BLOOM_WIDTH := 0.35           ## 过曝趋白的过渡宽度
const NV_BLOOM_STRENGTH := 0.75        ## 过曝区回灌到白的比例
const NV_VIGNETTE_FLOOR := 0.22        ## 暗角最暗处保留的亮度比例

var _overlay: ColorRect
var _is_active: bool = false

func _ready() -> void:
	# layer 0 = 世界之上、HUD(layer 1)之下：夜视膜只处理 3D 画面，不染色 HUD。
	# 实测（派单 16 设计要求 3）：layer 100 时膜盖住 HUD，血条的红/绿/蓝色彩编码
	# 被染成同一种绿、四角被暗角压暗；layer 0 时 HUD 完全清晰且世界夜视效果不变。
	# 两张对照图见 03-handoff-2026-10-18-w7.md。
	layer = 0
	_build_overlay()
	Events.night_vision_toggled.connect(_on_night_vision_toggled)
	# 同步初始状态（场景重载时 GameState 可能已为 true）。
	_set_active(GameState.night_vision)
	# 取证钩子：headless 截图按不了 N 键，用 --nv-on 强制开启。
	# 沿用 street_builder._ready() / kit_light_probe.gd 的 OS.get_cmdline_user_args()
	# 先例；不传该参数时本分支完全不生效，正常游玩路径零变化。
	if OS.get_cmdline_user_args().has("--nv-on"):
		GameState.night_vision = true
		_set_active(true)


func _unhandled_input(event: InputEvent) -> void:
	# 演示场景用：N 键切换夜视。场景内存在玩家（player 组）时让位给
	# player_controller 统一处理，避免双头切换（蜂后集成 2026-07-30）。
	if get_tree().get_first_node_in_group("player") != null:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_N:
			_toggle_night_vision()
			get_viewport().set_input_as_handled()


func _toggle_night_vision() -> void:
	# 白天禁开（§11.2）：GameState.is_night 由 DayNightController 维护。
	if not GameState.is_night and not GameState.night_vision:
		return
	GameState.night_vision = not GameState.night_vision
	Events.night_vision_toggled.emit(GameState.night_vision)


func _on_night_vision_toggled(enabled: bool) -> void:
	_set_active(enabled)


func _set_active(active: bool) -> void:
	_is_active = active
	if _overlay != null:
		_overlay.visible = active
	_set_scene_ambient(active)


## 场景环境光抬升（2026-10-25 机主指令：vm-shot 取证用的全图提亮融入夜视仪）：
## 屏幕增益只放大已有像素，夜里大面积纯黑抬不出几何细节；叠加真实环境光后
## 全场景被"照亮"再过磷光膜，才符合真实夜视仪在黑夜看清周围环境的作用。
## 原值存取按同一 Environment 实例守卫（换场景后不误回写）；street_playable
## vm-shot fill 同款就地改写先例。
var _saved_env: Environment = null
var _saved_source: int = 0
var _saved_color: Color = Color.WHITE
var _saved_energy: float = 1.0


func _set_scene_ambient(active: bool) -> void:
	var holder := get_tree().current_scene
	if holder == null:
		return
	var found: Array = holder.find_children("*", "WorldEnvironment", true, false)
	if found.is_empty():
		return
	var env: Environment = (found[0] as WorldEnvironment).environment
	if env == null:
		return
	if active:
		if _saved_env != env:
			_saved_env = env
			_saved_source = env.ambient_light_source
			_saved_color = env.ambient_light_color
			_saved_energy = env.ambient_light_energy
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = GameConfig.NIGHT_VISION_AMBIENT_COLOR
		env.ambient_light_energy = GameConfig.NIGHT_VISION_AMBIENT_ENERGY
	elif _saved_env == env:
		env.ambient_light_source = _saved_source as Environment.AmbientSource
		env.ambient_light_color = _saved_color
		env.ambient_light_energy = _saved_energy


func _build_overlay() -> void:
	_overlay = ColorRect.new()
	_overlay.name = "NightVisionRect"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader := Shader.new()
	shader.code = _NV_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	# 增益/色调类参数无 shader 默认值，一律由脚本本地 const 供给（单一事实源）。
	mat.set_shader_parameter("gain", NV_GAIN)
	mat.set_shader_parameter("shadow_lift_gamma", NV_SHADOW_LIFT_GAMMA)
	mat.set_shader_parameter("black_floor", NV_BLACK_FLOOR)
	mat.set_shader_parameter("desaturation", NV_DESATURATION)
	mat.set_shader_parameter("phosphor", NV_PHOSPHOR)
	mat.set_shader_parameter("bloom_start", NV_BLOOM_START)
	mat.set_shader_parameter("bloom_width", NV_BLOOM_WIDTH)
	mat.set_shader_parameter("bloom_strength", NV_BLOOM_STRENGTH)
	mat.set_shader_parameter("vignette_floor", NV_VIGNETTE_FLOOR)
	_overlay.material = mat
	_overlay.visible = false

	add_child(_overlay)
