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
	# G2 冻结新增参数全量锁定（commit 99dc010；RPG 后坐/步兵调参/狙杀 lethal/UI 动效四组）。
	# 步枪后坐组（网页版永久上跳缺陷修正，Godot 版指数恢复）
	_assert(config.RIFLE_RECOIL_RECOVER_RATE == 6.0, "game_config.gd RIFLE_RECOIL_RECOVER_RATE == 6.0")
	_assert(config.RIFLE_RECOIL_VIEW_ROT == 2.25, "game_config.gd RIFLE_RECOIL_VIEW_ROT == 2.25")
	_assert(config.RIFLE_RECOIL_VIEW_Y_FACTOR == 0.025, "game_config.gd RIFLE_RECOIL_VIEW_Y_FACTOR == 0.025")
	_assert(config.RIFLE_RECOIL_VIEW_Z_FACTOR == 0.05, "game_config.gd RIFLE_RECOIL_VIEW_Z_FACTOR == 0.05")
	# RPG 后坐 + 爆炸组（修复网页版 RPG 后坐永不触发缺陷）
	_assert(config.RPG_RECOIL_PITCH == 0.01, "game_config.gd RPG_RECOIL_PITCH == 0.01")
	_assert(config.RPG_RECOIL_RECOVER_RATE == 6.0, "game_config.gd RPG_RECOIL_RECOVER_RATE == 6.0")
	_assert(config.RPG_RECOIL_VIEW_ROT == 2.5, "game_config.gd RPG_RECOIL_VIEW_ROT == 2.5")
	_assert(config.RPG_RECOIL_VIEW_Y_FACTOR == 0.025, "game_config.gd RPG_RECOIL_VIEW_Y_FACTOR == 0.025")
	_assert(config.RPG_RECOIL_VIEW_Z_FACTOR == 0.075, "game_config.gd RPG_RECOIL_VIEW_Z_FACTOR == 0.075")
	_assert(config.RPG_EXPLODE_DAMAGE == 9999.0, "game_config.gd RPG_EXPLODE_DAMAGE == 9999.0")
	_assert(config.RPG_EXPLODE_BELOW_Y == -10.0, "game_config.gd RPG_EXPLODE_BELOW_Y == -10.0")
	# 步兵行为调参组（G2 冻结自 W3 脚本常量迁入）
	_assert(config.INFANTRY_PATROL_RADIUS == 40.0, "game_config.gd INFANTRY_PATROL_RADIUS == 40.0")
	_assert(config.INFANTRY_ALERT_DELAY == 1.0, "game_config.gd INFANTRY_ALERT_DELAY == 1.0")
	_assert(config.INFANTRY_COVER_SEARCH_RADIUS == 25.0, "game_config.gd INFANTRY_COVER_SEARCH_RADIUS == 25.0")
	_assert(config.INFANTRY_COVER_MIN_DIST == 8.0, "game_config.gd INFANTRY_COVER_MIN_DIST == 8.0")
	_assert(config.INFANTRY_COVER_ARRIVE_DIST == 1.5, "game_config.gd INFANTRY_COVER_ARRIVE_DIST == 1.5")
	_assert(config.INFANTRY_COVER_SCORE_DIST == 0.5, "game_config.gd INFANTRY_COVER_SCORE_DIST == 0.5")
	_assert(config.INFANTRY_COVER_SCORE_ALIGN == 10.0, "game_config.gd INFANTRY_COVER_SCORE_ALIGN == 10.0")
	_assert(config.INFANTRY_PEEK_FIRE_DELAY == 0.5, "game_config.gd INFANTRY_PEEK_FIRE_DELAY == 0.5")
	_assert(config.INFANTRY_PEEK_CYCLE_TIME == 1.0, "game_config.gd INFANTRY_PEEK_CYCLE_TIME == 1.0")
	_assert(config.INFANTRY_PEEK_REPEAT_CHANCE == 0.3, "game_config.gd INFANTRY_PEEK_REPEAT_CHANCE == 0.3")
	_assert(config.INFANTRY_PEEK_ENGAGE_TIME == 1.5, "game_config.gd INFANTRY_PEEK_ENGAGE_TIME == 1.5")
	_assert(config.INFANTRY_ALERT_ENGAGE_TIME == 2.0, "game_config.gd INFANTRY_ALERT_ENGAGE_TIME == 2.0")
	_assert(config.INFANTRY_ENGAGE_APPROACH_DIST == 12.0, "game_config.gd INFANTRY_ENGAGE_APPROACH_DIST == 12.0")
	_assert(config.INFANTRY_ENGAGE_BACKOFF_DIST == 5.0, "game_config.gd INFANTRY_ENGAGE_BACKOFF_DIST == 5.0")
	_assert(config.INFANTRY_BLIND_FIRE_DIST == 3.0, "game_config.gd INFANTRY_BLIND_FIRE_DIST == 3.0")
	_assert(config.INFANTRY_FALLBACK_COVER_DIST == 5.0, "game_config.gd INFANTRY_FALLBACK_COVER_DIST == 5.0")
	_assert(config.INFANTRY_COMPANION_COVER_DIST == 5.0, "game_config.gd INFANTRY_COMPANION_COVER_DIST == 5.0")
	_assert(config.INFANTRY_COMPANION_ENGAGE_TIME == 10.0, "game_config.gd INFANTRY_COMPANION_ENGAGE_TIME == 10.0")
	# 碉堡机枪（G2 冻结；停火裁决采 A，机主签字）
	_assert(config.BUNKER_MG_DAMAGE_RAND == 3.0, "game_config.gd BUNKER_MG_DAMAGE_RAND == 3.0")
	_assert(config.BUNKER_PRONE_CEASEFIRE_TIME == 7.0, "game_config.gd BUNKER_PRONE_CEASEFIRE_TIME == 7.0")
	# 狙击手 lethal 组（§6 死代码裁决参数化）
	_assert(config.SNIPER_LETHAL == true, "game_config.gd SNIPER_LETHAL == true")
	_assert(config.SNIPER_KILL_DAMAGE == 999.0, "game_config.gd SNIPER_KILL_DAMAGE == 999.0")
	_assert(config.SNIPER_NON_LETHAL_DAMAGE == 8.0, "game_config.gd SNIPER_NON_LETHAL_DAMAGE == 8.0")
	# UI 反馈动效组（G2 冻结自 W5 脚本常量迁入）
	_assert(config.CROSSHAIR_HIT_SCALE == 1.3, "game_config.gd CROSSHAIR_HIT_SCALE == 1.3")
	_assert(config.CROSSHAIR_HEADSHOT_SCALE == 1.8, "game_config.gd CROSSHAIR_HEADSHOT_SCALE == 1.8")
	_assert(config.CROSSHAIR_PULSE_HOLD == 0.06, "game_config.gd CROSSHAIR_PULSE_HOLD == 0.06")
	_assert(config.MESSAGE_HOLD_TIME == 0.8, "game_config.gd MESSAGE_HOLD_TIME == 0.8")
	_assert(config.DAMAGE_FLASH_PEAK_ALPHA == 0.35, "game_config.gd DAMAGE_FLASH_PEAK_ALPHA == 0.35")
	_assert(config.DAMAGE_FLASH_FADE_TIME == 0.4, "game_config.gd DAMAGE_FLASH_FADE_TIME == 0.4")
	_assert(config.KILL_FEEDBACK_HOLD_TIME == 0.6, "game_config.gd KILL_FEEDBACK_HOLD_TIME == 0.6")

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
