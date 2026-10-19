extends Area3D
## Pickup — 室内拾取物（2026-10-07 机主裁决：电池组/医疗注射/取证终端三类，贴近即拾；
## 2026-10-19 机主立项新增 pistol_ammo 手枪弹匣组，与电池组视觉/效果区分）。
##
## 契约（已冻结）：Events.battery_picked / medkit_picked（既有）/ intel_picked；
## 状态写入 GameState（rifle_reserve / medkits / intel），反馈走 Events.message_posted 中央飘字。
## 视觉件由 builder 按 kind 装载 pickup_<kind>.glb；浮动+自转参数走 GameConfig.PICKUP_*。

@export var kind: StringName = &"battery"
## 取证终端专用：本图收集品总数（builder 注入；其他 kind 忽略）
var intel_total: int = 0

var _base_y: float = 0.0
var _phase: float = 0.0
var _collected: bool = false

const MODELS := {
	&"battery": "res://assets/models/pickup_battery.glb",
	&"pistol_ammo": "res://assets/models/pickup_pistol_ammo.glb",
	&"medkit": "res://assets/models/pickup_medkit.glb",
	&"intel": "res://assets/models/pickup_intel.glb",
}


func _ready() -> void:
	# 触发区（贴近即拾；半径走契约，禁止硬编码）
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = GameConfig.PICKUP_TRIGGER_RADIUS
	shape.shape = sphere
	add_child(shape)
	body_entered.connect(_on_body_entered)
	# 视觉件
	var path: String = MODELS.get(kind, "")
	if path != "" and ResourceLoader.exists(path):
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		inst.name = "Visual"
		add_child(inst)
	_base_y = position.y
	_phase = randf() * TAU  # 逐件相位错开，去同步感


func _process(delta: float) -> void:
	if _collected:
		return
	_phase += delta * TAU * GameConfig.PICKUP_BOB_HZ
	position.y = _base_y + sin(_phase) * GameConfig.PICKUP_BOB_AMP
	rotation_degrees.y += GameConfig.PICKUP_SPIN_DEG * delta


func _on_body_entered(body: Node3D) -> void:
	if _collected or not body.is_in_group("player"):
		return
	match kind:
		&"battery":
			if GameState.rifle_reserve >= GameConfig.RIFLE_RESERVE_MAX:
				return  # 备弹达携带上限：留在原地不吞件（2026-10-19 机主口径）
			GameState.rifle_reserve = mini(GameState.rifle_reserve + GameConfig.BATTERY_PICKUP_ROUNDS,
				GameConfig.RIFLE_RESERVE_MAX)
			Events.ammo_changed.emit(&"rifle", GameState.rifle_mag, GameState.rifle_reserve)
			Events.battery_picked.emit(GameState.rifle_reserve)
			Events.message_posted.emit("E 系列电池组  备弹 +%d" % GameConfig.BATTERY_PICKUP_ROUNDS)
		&"pistol_ammo":
			if GameState.pistol_reserve >= GameConfig.PISTOL_RESERVE_MAX:
				return  # 同上：达上限不吞件
			GameState.pistol_reserve = mini(GameState.pistol_reserve + GameConfig.PISTOL_AMMO_PICKUP_ROUNDS,
				GameConfig.PISTOL_RESERVE_MAX)
			Events.ammo_changed.emit(&"pistol", GameState.pistol_mag, GameState.pistol_reserve)
			Events.pistol_ammo_picked.emit(GameState.pistol_reserve)
			Events.message_posted.emit("EM-57P 弹匣组  手枪备弹 +%d" % GameConfig.PISTOL_AMMO_PICKUP_ROUNDS)
		&"medkit":
			if GameState.medkits >= GameConfig.MEDKIT_MAX_CARRY:
				return  # 携带上限：留在原地不吞件
			GameState.medkits += 1
			Events.medkit_picked.emit(GameState.medkits)
			Events.message_posted.emit("医疗注射  +1（F 使用）")
		&"intel":
			GameState.intel += 1
			Events.intel_picked.emit(GameState.intel, intel_total)
			Events.message_posted.emit("取证终端已回收  %d / %d" % [GameState.intel, intel_total])
		_:
			push_warning("pickup: unknown kind %s" % kind)
			return
	_collected = true
	queue_free()
