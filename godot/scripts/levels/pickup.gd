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
	&"shotgun_ammo": "res://assets/models/weapons/em12g1_magazine.glb",
	&"dmr": "res://assets/models/weapons/em68d_viewmodel.glb",
	&"shotgun": "res://assets/models/weapons/em12g1_viewmodel.glb",
	&"medkit": "res://assets/models/pickup_medkit.glb",
	&"intel": "res://assets/models/pickup_intel.glb",
	# 榴弹补给（2026-10-25 机主立项）：复用项目自有 EM-40G 弹体模型，放大 2.5 倍做悬浮件
	&"grenade": "res://assets/models/weapons/em40g_grenade.glb",
}


func _ready() -> void:
	add_to_group(&"pickup")  # 跨场景持久化枚举用（SceneLink 离场快照/返回恢复）
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
		if kind == &"grenade":
			inst.scale = Vector3.ONE * 2.5  # 弹体原生 0.2m，放大到拾取物可读尺寸
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
				return  # EC-68 共享备弹池已满：留在原地不吞件
			GameState.rifle_reserve = mini(GameState.rifle_reserve + GameConfig.BATTERY_PICKUP_ROUNDS,
				GameConfig.RIFLE_RESERVE_MAX)
			Events.ammo_changed.emit(&"rifle", GameState.rifle_mag, GameState.rifle_reserve)
			Events.ammo_changed.emit(&"dmr", GameState.dmr_mag, GameState.rifle_reserve)
			Events.battery_picked.emit(GameState.rifle_reserve)
			Events.message_posted.emit("EC-68 电池组  步枪/DMR 共享备弹 +%d" % GameConfig.BATTERY_PICKUP_ROUNDS)
		&"pistol_ammo":
			if GameState.pistol_reserve >= GameConfig.PISTOL_RESERVE_MAX:
				return  # 同上：达上限不吞件
			GameState.pistol_reserve = mini(GameState.pistol_reserve + GameConfig.PISTOL_AMMO_PICKUP_ROUNDS,
				GameConfig.PISTOL_RESERVE_MAX)
			Events.ammo_changed.emit(&"pistol", GameState.pistol_mag, GameState.pistol_reserve)
			Events.pistol_ammo_picked.emit(GameState.pistol_reserve)
			Events.message_posted.emit("EM-57P 弹匣组  手枪备弹 +%d" % GameConfig.PISTOL_AMMO_PICKUP_ROUNDS)
		&"shotgun_ammo":
			if GameState.shotgun_reserve >= GameConfig.SHOTGUN_RESERVE_MAX:
				return
			GameState.shotgun_reserve = mini(GameState.shotgun_reserve + GameConfig.SHOTGUN_AMMO_PICKUP_ROUNDS,
				GameConfig.SHOTGUN_RESERVE_MAX)
			Events.ammo_changed.emit(&"shotgun", GameState.shotgun_mag, GameState.shotgun_reserve)
			Events.shotgun_ammo_picked.emit(GameState.shotgun_reserve)
			Events.message_posted.emit("EC-12 弹匣组  霰弹备弹 +%d" % GameConfig.SHOTGUN_AMMO_PICKUP_ROUNDS)
		&"dmr", &"shotgun":
			GameState.weapon_unlocked[kind] = true
			GameState.current_weapon = kind
			var reserve: int = GameState.rifle_reserve if kind == &"dmr" else GameState.shotgun_reserve
			Events.ammo_changed.emit(kind, GameState.get(kind + "_mag"), reserve)
			Events.weapon_switched.emit(kind)
			Events.message_posted.emit("雷暴装备已领取：%s" % ("EM-68D 穿杨" if kind == &"dmr" else "EM-12G-1 霰·Ⅰ"))
		&"medkit":
			if GameState.medkits >= GameConfig.MEDKIT_MAX_CARRY:
				return  # 携带上限：留在原地不吞件
			GameState.medkits += 1
			Events.medkit_picked.emit(GameState.medkits)
			Events.message_posted.emit("医疗注射  +1（F 使用）")
		&"intel":
			GameState.intel += 1
			GameState.mission_points.erase(String(name))  # 任务标记收尾（小地图/罗盘）
			Events.intel_picked.emit(GameState.intel, intel_total)
			Events.message_posted.emit("取证终端已回收  %d / %d" % [GameState.intel, intel_total])
		&"grenade":
			# 榴弹补给（雷池总数制无上限；ammo_changed 联动榴档弹药显示）
			GameState.rifle_grenades += GameConfig.GRENADE_PICKUP_ROUNDS
			Events.ammo_changed.emit(&"rifle", GameState.rifle_mag, GameState.rifle_reserve)
			Events.message_posted.emit("EM-40G 滚雷榴弹 +%d（雷池 %d）"
				% [GameConfig.GRENADE_PICKUP_ROUNDS, GameState.rifle_grenades])
		_:
			push_warning("pickup: unknown kind %s" % kind)
			return
	_collected = true
	queue_free()
