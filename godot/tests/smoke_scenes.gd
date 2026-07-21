## smoke_scenes.gd -- headless 场景节点冒烟（L1 校验链 Sprint 2 加固步）。
##
## 逐个加载注册的 .tscn 并实例化，断言契约关键节点存在。
## optional = true 的用例在场景文件缺失时报 SKIP 而非 FAIL，供并行施工期间
## 保持链路常绿；W2 武器 / W3 兵种场景已于 G2 全量交付，相应用例已按 .tscn
## 实际节点结构补全 expect 并转为正式断言（optional = false）。
##
## 用法（工程根下 headless）：
##   godot --headless --path . -s res://tests/smoke_scenes.gd
## 临时单场景模式（W2/W3 迭代期自助使用）：
##   godot --headless --path . -s res://tests/smoke_scenes.gd -- \
##       res://scenes/weapons/rifle.tscn NodeA NodeB/Sub
##
## 注意：-s 模式下 autoload 单例不会自动实例化，沿用 tests/check_scripts.gd
## 的既定模式先手动重建三件套，否则场景脚本运行时访问 Events/GameState
## 会报错。树置为 paused，物理帧不触发，只验证结构。
extends SceneTree

## 顺序敏感：game_state.gd 编译期引用 GameConfig。
const AUTOLOADS: Array = [
	["Events", "res://autoload/events.gd"],
	["GameConfig", "res://autoload/game_config.gd"],
	["GameState", "res://autoload/game_state.gd"],
]

## 用例注册表。scene = res:// 场景路径；optional = true 表示「尚未交付，
## 缺失时 SKIP」；expect = 相对场景根节点的关键节点路径清单。
const CASES: Array = [
	{
		"scene": "res://scenes/player/player.tscn",
		"optional": false,
		"expect": ["CollisionShape3D", "Camera3D", "Camera3D/WeaponMount"],
	},
	{
		"scene": "res://scenes/levels/greybox_arena.tscn",
		"optional": false,
		"expect": ["WorldEnvironment", "MoonLight", "Ground", "BoundaryWalls", "DividerBuilding", "Markers"],
	},
	{
		"scene": "res://scenes/ui/hud.tscn",
		"optional": false,
		"expect": ["StatusPanel", "KillsLabel", "HeliTimerLabel", "LegWarningLabel", "MessageLabel", "AmmoLabel", "Crosshair"],
	},
	# ===== W2 火力蜂武器场景（已交付入库，G2 转正式断言；expect 按 .tscn 实际节点补全）=====
	{"scene": "res://scenes/weapons/rifle.tscn", "optional": false, "expect": ["ViewModel"]},
	{"scene": "res://scenes/weapons/rpg.tscn", "optional": false, "expect": ["ViewModel"]},
	{"scene": "res://scenes/weapons/rpg_projectile.tscn", "optional": false, "expect": ["Body"]},
	# ===== W3 敌智蜂兵种场景（已交付入库，G2 转正式断言；Eye/Muzzle 为 AI 感知/开火锚点）=====
	{
		"scene": "res://scenes/enemies/infantry.tscn",
		"optional": false,
		"expect": ["CollisionShape3D", "HeadHitbox", "BodyMesh", "HeadMesh", "GunMesh", "Eye", "Muzzle"],
	},
	{
		"scene": "res://scenes/enemies/machine_gunner.tscn",
		"optional": false,
		"expect": ["CollisionShape3D", "HeadHitbox", "BodyMesh", "HeadMesh", "GunMesh", "Eye", "Muzzle"],
	},
	{
		"scene": "res://scenes/enemies/sniper.tscn",
		"optional": false,
		"expect": ["CollisionShape3D", "HeadHitbox", "BodyMesh", "HeadMesh", "GunMesh", "Eye", "Muzzle"],
	},
	{
		"scene": "res://scenes/enemies/bunker_machine_gunner.tscn",
		"optional": false,
		"expect": ["CollisionShape3D", "BodyMesh", "GunMesh", "Eye", "Muzzle"],
	},
]

var _failures: int = 0
var _skips: int = 0
var _autoload_nodes: Array = []


func _init() -> void:
	# root 在 _init 内未就绪，推迟到首帧执行。
	call_deferred("_run")


func _run() -> void:
	_recreate_autoloads()
	# 只验证节点结构，不让 _physics_process 跑起来。
	paused = true

	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		for entry in CASES:
			_smoke_case(entry)
	else:
		# 临时模式：-- 后第一个参数为场景路径，其余为断言节点路径。
		_smoke_case({"scene": args[0], "optional": false, "expect": Array(args.slice(1))})

	_free_autoloads()

	if _failures > 0:
		print("smoke_scenes: " + str(_failures) + " assertion(s) FAILED, " + str(_skips) + " case(s) skipped")
		quit(1)
	else:
		print("smoke_scenes: all cases passed (" + str(_skips) + " skipped)")
		quit(0)


func _smoke_case(entry: Dictionary) -> void:
	var scene_path: String = entry["scene"]
	if not ResourceLoader.exists(scene_path):
		if entry.get("optional", false):
			_skips += 1
			print("SKIP: " + scene_path + " (not delivered yet)")
		else:
			_failures += 1
			print("FAIL: " + scene_path + " (scene file missing)")
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_failures += 1
		print("FAIL: " + scene_path + " (cannot load as PackedScene)")
		return
	var instance := packed.instantiate()
	if instance == null:
		_failures += 1
		print("FAIL: " + scene_path + " (instantiate returned null)")
		return
	root.add_child(instance)
	for node_path in entry["expect"]:
		if instance.has_node(node_path):
			print("PASS: " + scene_path + " has node '" + node_path + "'")
		else:
			_failures += 1
			print("FAIL: " + scene_path + " missing node '" + node_path + "'")
	root.remove_child(instance)
	instance.free()


## 手动重建 autoload 单例（-s 模式不自动实例化）。
func _recreate_autoloads() -> void:
	for entry in AUTOLOADS:
		var node = load(entry[1]).new()
		node.name = entry[0]
		root.add_child(node)
		_autoload_nodes.append(node)


## 释放手动实例，避免 headless 退出时的泄漏噪音。
func _free_autoloads() -> void:
	for node in _autoload_nodes:
		root.remove_child(node)
		node.free()
	_autoload_nodes.clear()
