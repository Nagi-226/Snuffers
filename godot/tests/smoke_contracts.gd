## smoke_contracts.gd -- L1 contract assertions for the Godot spike.
##
## Run headless from the project root:
##   godot --headless --path . -s res://tests/smoke_contracts.gd
##
## G2 修复（挂起根因）：G2 契约冻结后 game_state.gd 的 _ready 编译期引用
## Events.enemy_died，-s 模式 autoload 节点不存在 → 成员解析失败 → 编译报错
## → _init 中途流产 → quit() 永不执行 → headless 挂起。
## 现沿用 tests/check_scripts.gd 既定模式：_init 仅 call_deferred，先把
## autoload 三件套以正确名字挂到 root（编译期标识符与运行时节点双双就绪），
## 再跑断言；任何路径（含 autoload 装载失败）都保证到达 quit()。
##
## 注意：本脚本自身在 -s 启动时先于任何节点挂载被编译，因此脚本体内禁止直接
## 引用 Events/GameConfig/GameState 标识符——一律经手动挂载的实例动态访问
## （locals 保持非类型化，静态成员检查本来就看不穿动态引用）。
##
## Prints one PASS/FAIL line per assertion; quit(1) if any FAIL.
extends SceneTree

## 顺序敏感：game_state.gd 编译期引用 Events / GameConfig。
const AUTOLOADS: Array = [
	["Events", "res://autoload/events.gd"],
	["GameConfig", "res://autoload/game_config.gd"],
	["GameState", "res://autoload/game_state.gd"],
]

var _failures: int = 0
var _autoload_nodes: Array = []


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _init() -> void:
	# root 在 _init 内未就绪，推迟到首帧执行（与 check_scripts.gd 同模式）。
	call_deferred("_run")


func _run() -> void:
	if not _recreate_autoloads():
		_free_autoloads()
		print("smoke_contracts: autoload setup FAILED")
		quit(1)
		return

	# 非类型化局部引用（Variant），动态成员访问。
	var events = _autoload_nodes[0]
	var config = _autoload_nodes[1]
	var state = _autoload_nodes[2]

	# -- game_config.gd: frozen feel parameters must keep contract values --
	_assert(config.SPEED_STAND == 4.5, "game_config.gd SPEED_STAND == 4.5")
	_assert(config.RIFLE_FIRE_INTERVAL == 0.1, "game_config.gd RIFLE_FIRE_INTERVAL == 0.1")
	# G2 冻结新增参数抽查（RPG 独立后坐 / 狙杀开关 / 命中准星倍率）。
	_assert(config.RPG_RECOIL_PITCH == 0.01, "game_config.gd RPG_RECOIL_PITCH == 0.01")
	_assert(config.SNIPER_LETHAL == true, "game_config.gd SNIPER_LETHAL == true")
	_assert(config.CROSSHAIR_HIT_SCALE == 1.3, "game_config.gd CROSSHAIR_HIT_SCALE == 1.3")

	# -- events.gd: signal bus must expose the contracted signals --
	_assert(events.has_signal(&"weapon_fired"), "events.gd has signal weapon_fired")
	_assert(events.has_signal(&"game_over"), "events.gd has signal game_over")
	# G2 冻结新增信号（5 个）。
	_assert(events.has_signal(&"player_moving_changed"), "events.gd has signal player_moving_changed")
	_assert(events.has_signal(&"rpg_exploded"), "events.gd has signal rpg_exploded")
	_assert(events.has_signal(&"damage_dealt"), "events.gd has signal damage_dealt")
	_assert(events.has_signal(&"bunker_destroyed"), "events.gd has signal bunker_destroyed")
	_assert(events.has_signal(&"enemy_fired"), "events.gd has signal enemy_fired")

	# -- game_state.gd: reset() must restore the three body-part health keys --
	# 挂载时 _ready 已跑过一次 reset()（含 Events.enemy_died 连接）；再调一次验证幂等。
	state.reset()
	_assert(state.health.has(&"head"), "game_state.gd reset() health has key 'head'")
	_assert(state.health.has(&"body"), "game_state.gd reset() health has key 'body'")
	_assert(state.health.has(&"legs"), "game_state.gd reset() health has key 'legs'")

	_free_autoloads()

	if _failures > 0:
		print("smoke_contracts: " + str(_failures) + " assertion(s) FAILED")
		quit(1)
	else:
		print("smoke_contracts: all assertions passed")
		quit(0)


## 手动重建 autoload 单例（-s 模式不自动实例化）。节点名必须与 project.godot
## 的 [autoload] 注册名一致，否则其他脚本里的 Events/GameConfig 标识符在
## 编译期成员解析与运行时访问都会失败。任一装载失败即返回 false。
func _recreate_autoloads() -> bool:
	var ok := true
	for entry in AUTOLOADS:
		var script = load(entry[1])
		if script == null:
			_failures += 1
			print("FAIL: cannot load autoload script " + entry[1])
			ok = false
			continue
		var node = script.new()
		node.name = entry[0]
		root.add_child(node)
		_autoload_nodes.append(node)
	return ok


## 释放手动实例，避免 headless 退出时的泄漏噪音。
func _free_autoloads() -> void:
	for node in _autoload_nodes:
		root.remove_child(node)
		node.free()
	_autoload_nodes.clear()
