## NightVisionOverlay — 夜视仪占位视觉效果（W7 昼夜域）
##
## 契约约束（AGENTS.md）：
## - 消费 Events.night_vision_toggled（已存在，events.gd L81）。
## - 读取 GameState.night_vision 同步状态。
## - 键位 N（§11.2 机主裁决）；当前 player_controller.gd 仍为 V（W1 域待改），
##   本脚本在演示场景中自行处理 N 键，集成后由 player_controller 统一发信号。
##
## 效果：绿色磷光全屏覆盖 + 扫描线 + 暗角（占位，G4 后替换正式素材）。
## 仅黑夜模式下可用（白天按 N 无反应）。
extends CanvasLayer

## 夜视效果着色器源码（占位；G4 后由 W5 替换正式夜视素材/后期）。
const _NV_SHADER_CODE: String = "
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float scanline_density : hint_range(100.0, 1200.0) = 600.0;
uniform float scanline_alpha : hint_range(0.0, 0.5) = 0.08;
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	vec2 uv = UV;
	// 绿色磷光基调
	vec3 nv_green = vec3(0.15, 0.95, 0.25);
	// 扫描线
	float scanline = sin(uv.y * scanline_density * 3.14159) * scanline_alpha;
	// 暗角
	vec2 center = uv - 0.5;
	float dist = length(center);
	float vignette = smoothstep(0.7, 0.7 - vignette_softness, dist);
	// 合成
	float alpha = (0.3 + scanline) * vignette * intensity;
	COLOR = vec4(nv_green, alpha);
}
"

var _overlay: ColorRect
var _is_active: bool = false

## 可选：引用 DayNightController 以限制白天不可用。
## 若为 null 则不做模式限制（向后兼容）。
var day_night_ref: Node = null


func _ready() -> void:
	layer = 100
	_build_overlay()
	Events.night_vision_toggled.connect(_on_night_vision_toggled)
	# 同步初始状态（场景重载时 GameState 可能已为 true）。
	_set_active(GameState.night_vision)


func _unhandled_input(event: InputEvent) -> void:
	# 演示用：N 键切换夜视（集成后由 player_controller 发信号，本段可删）。
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_N:
			_toggle_night_vision()
			get_viewport().set_input_as_handled()


func _toggle_night_vision() -> void:
	# 白天模式下禁止开启夜视（§11.2：夜视仪黑夜模式下可用）。
	if day_night_ref != null and day_night_ref.has_method("is_night"):
		if not day_night_ref.is_night() and not GameState.night_vision:
			return
	GameState.night_vision = not GameState.night_vision
	Events.night_vision_toggled.emit(GameState.night_vision)


func _on_night_vision_toggled(enabled: bool) -> void:
	_set_active(enabled)


func _set_active(active: bool) -> void:
	_is_active = active
	if _overlay != null:
		_overlay.visible = active


func _build_overlay() -> void:
	_overlay = ColorRect.new()
	_overlay.name = "NightVisionRect"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader := Shader.new()
	shader.code = _NV_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_overlay.material = mat
	_overlay.visible = false

	add_child(_overlay)
