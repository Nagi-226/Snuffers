extends OmniLight3D
## 闪烁应急灯（可进入建筑试点·照明 B 方案，2026-09-27 机主裁决）
## 设定：城中村断电但偶有备用电——暖橙光 + 接触不良式随机闪烁，兼做室内动线引导
## 参数契约：GameConfig.EMERGENCY_*（禁止在本脚本硬编码手感参数）

var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _lit := true


func _ready() -> void:
	light_color = GameConfig.EMERGENCY_LIGHT_COLOR
	light_energy = GameConfig.EMERGENCY_LIGHT_ENERGY
	omni_range = GameConfig.EMERGENCY_LIGHT_RANGE
	shadow_enabled = false  # 性能纪律：室内点光源不开阴影
	_rng.seed = hash(name) + 12345
	_timer = _rng.randf_range(GameConfig.EMERGENCY_FLICKER_MIN_S, GameConfig.EMERGENCY_FLICKER_MAX_S)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	if _rng.randf() < GameConfig.EMERGENCY_DARK_PROB:
		# 长灭（接触不良）：压到近黑 0.4~1.2s
		_lit = false
		light_energy = GameConfig.EMERGENCY_LIGHT_ENERGY * GameConfig.EMERGENCY_DIM_RATIO * 0.2
		_timer = _rng.randf_range(0.4, 1.2)
	elif _lit:
		# 暗态：留底光不完全熄灭
		_lit = false
		light_energy = GameConfig.EMERGENCY_LIGHT_ENERGY * GameConfig.EMERGENCY_DIM_RATIO
		_timer = _rng.randf_range(GameConfig.EMERGENCY_FLICKER_MIN_S, GameConfig.EMERGENCY_FLICKER_MAX_S)
	else:
		_lit = true
		light_energy = GameConfig.EMERGENCY_LIGHT_ENERGY * _rng.randf_range(0.85, 1.1)
		_timer = _rng.randf_range(GameConfig.EMERGENCY_FLICKER_MIN_S, GameConfig.EMERGENCY_FLICKER_MAX_S * 2.0)
