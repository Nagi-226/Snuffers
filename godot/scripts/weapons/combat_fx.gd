## CombatFX — 敌弹曳光 + 枪口火光（§11.1 A 方案表现层三件套之二，W2 火力蜂域，
## 2026-08-19 Phase 0b；机主裁决纳入 G4 前施工）
##
## 单一锚点：监听 Events.enemy_fired(kind, muzzle_position)（G2 冻结信号，
## 步兵/机枪手/碉堡/狙击手全部覆盖）。曳光自枪口画向玩家胸口
## （GameState.player_position + 1.2u；表现层近似——不考虑脱靶/遮挡，见 handoff）。
## 参数全部契约化（TRACER_*/MUZZLE_FLASH_*），禁硬编码。
## 受击方向指示弧为第三件套，归 HUD 域（damage_direction_arc.gd）。
extends Node3D

## 曳光材质（加色混合发光，夜战可见性核心）。
var _tracer_material: StandardMaterial3D
## 存活特效池：[{node, remaining}]，_process 统一倒计时回收。
var _live: Array = []


func _ready() -> void:
	_tracer_material = StandardMaterial3D.new()
	_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tracer_material.albedo_color = Color(1.0, 0.85, 0.45)
	_tracer_material.emission_enabled = true
	_tracer_material.emission = Color(1.0, 0.8, 0.4)
	Events.enemy_fired.connect(_on_enemy_fired)


func _exit_tree() -> void:
	Events.enemy_fired.disconnect(_on_enemy_fired)


func _process(delta: float) -> void:
	for i in range(_live.size() - 1, -1, -1):
		var entry: Dictionary = _live[i]
		entry["remaining"] -= delta
		if entry["remaining"] <= 0.0:
			(entry["node"] as Node).queue_free()
			_live.remove_at(i)


func _on_enemy_fired(_kind: StringName, muzzle_position: Vector3) -> void:
	_spawn_muzzle_flash(muzzle_position)
	_spawn_tracer(muzzle_position)


## 枪口火光：OmniLight3D 短促点亮（夜战敌位暴露的关键反馈）。
func _spawn_muzzle_flash(pos: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.4)
	light.light_energy = GameConfig.MUZZLE_FLASH_ENERGY
	light.omni_range = 6.0
	add_child(light)
	light.global_position = pos
	_live.append({"node": light, "remaining": GameConfig.MUZZLE_FLASH_LIFETIME})


## 曳光：枪口 → 玩家胸口的细长发光盒，驻留 TRACER_LIFETIME 秒。
func _spawn_tracer(from: Vector3) -> void:
	var to := GameState.player_position + Vector3(0.0, 1.2, 0.0)
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(GameConfig.TRACER_WIDTH, GameConfig.TRACER_WIDTH, length)
	var beam := MeshInstance3D.new()
	beam.mesh = mesh
	beam.material_override = _tracer_material
	add_child(beam)
	beam.global_position = (from + to) * 0.5
	beam.look_at(to, Vector3.UP)
	_live.append({"node": beam, "remaining": GameConfig.TRACER_LIFETIME})
