## EC-60E 专用青蓝等离子脉冲池；只消费独立爆炸事件。
## 复用 Player 根下 FX 节点模式，池实例 top_level 保持爆点世界坐标。
extends Node3D

const PLASMA_SHADER := preload("res://assets/shaders/ec60e_plasma.gdshader")

var _instances: Array[Dictionary] = []
var _cursor := 0


func _ready() -> void:
	for i in GameConfig.EC60E_FX_POOL:
		_instances.append(_build_instance(i))
	Events.ec60e_exploded.connect(_on_exploded)


func _exit_tree() -> void:
	Events.ec60e_exploded.disconnect(_on_exploded)


func _build_instance(index: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "PlasmaPulse%d" % index
	root.top_level = true
	root.visible = false
	add_child(root)
	var wave_material := ShaderMaterial.new()
	wave_material.shader = PLASMA_SHADER
	wave_material.set_shader_parameter("pulse_color", GameConfig.EC60E_FX_COLOR)
	wave_material.set_shader_parameter("core", 0.0)
	var core_material := ShaderMaterial.new()
	core_material.shader = PLASMA_SHADER
	core_material.set_shader_parameter("pulse_color", GameConfig.EC60E_FX_CORE_COLOR)
	core_material.set_shader_parameter("core", 1.0)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	var wave := MeshInstance3D.new()
	wave.name = "Wave"
	wave.mesh = sphere
	wave.material_override = wave_material
	wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(wave)
	var core := MeshInstance3D.new()
	core.name = "Core"
	core.mesh = sphere
	core.material_override = core_material
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var light := OmniLight3D.new()
	light.name = "FlashLight"
	light.light_color = GameConfig.EC60E_FX_COLOR
	light.omni_range = GameConfig.EC60E_FX_FLASH_RANGE
	light.shadow_enabled = false
	root.add_child(light)
	return {"root": root, "wave": wave, "core": core, "light": light,
		"wave_material": wave_material, "core_material": core_material,
		"time": 0.0, "active": false}


func _on_exploded(position: Vector3) -> void:
	if _instances.is_empty() or not position.is_finite():
		return
	var instance: Dictionary = _instances[_cursor]
	_cursor = (_cursor + 1) % _instances.size()
	var root := instance["root"] as Node3D
	root.global_position = position
	root.reset_physics_interpolation()
	root.visible = true
	instance["time"] = 0.0
	instance["active"] = true
	_update_instance(instance)


func _process(delta: float) -> void:
	for instance in _instances:
		if not instance["active"]:
			continue
		instance["time"] += delta
		if instance["time"] >= GameConfig.EC60E_FX_LIFETIME:
			(instance["root"] as Node3D).visible = false
			instance["active"] = false
			continue
		_update_instance(instance)


func _update_instance(instance: Dictionary) -> void:
	var time: float = instance["time"]
	var expansion := clampf(time / GameConfig.EC60E_FX_WAVE_TIME, 0.0, 1.0)
	var fade := clampf(1.0 - time / GameConfig.EC60E_FX_LIFETIME, 0.0, 1.0)
	var wave := instance["wave"] as MeshInstance3D
	wave.scale = Vector3.ONE * maxf(GameConfig.EC60E_QUERY_RADIUS, GameConfig.EC60E_OUTER_RADIUS * expansion)
	var wave_material := instance["wave_material"] as ShaderMaterial
	wave_material.set_shader_parameter("pulse_time", time)
	wave_material.set_shader_parameter("strength", fade)
	var flash := clampf(1.0 - time / GameConfig.EC60E_FX_FLASH_TIME, 0.0, 1.0)
	var core := instance["core"] as MeshInstance3D
	core.visible = flash > 0.0
	core.scale = Vector3.ONE * GameConfig.EC60E_FX_CORE_RADIUS
	var core_material := instance["core_material"] as ShaderMaterial
	core_material.set_shader_parameter("pulse_time", time)
	core_material.set_shader_parameter("strength", flash * flash)
	var light := instance["light"] as OmniLight3D
	light.visible = flash > 0.0
	light.light_energy = GameConfig.EC60E_FX_FLASH_ENERGY * flash * flash
