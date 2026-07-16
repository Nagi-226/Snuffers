## smoke_contracts.gd -- L1 contract assertions for the Godot spike.
##
## Run headless from the project root:
##   godot --headless --path . -s res://tests/smoke_contracts.gd
##
## NOTE: in -s mode autoload singletons are NOT instantiated, so each
## contract script is created manually via load(...).new() before asserting.
## load() is dynamic, so the locals stay untyped on purpose (static member
## checks cannot see through load() anyway).
##
## Prints one PASS/FAIL line per assertion; quit(1) if any FAIL.
extends SceneTree

var _failures: int = 0


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _init() -> void:
	# -- game_config.gd: frozen feel parameters must keep contract values --
	var config = load("res://autoload/game_config.gd").new()
	_assert(config.SPEED_STAND == 4.5, "game_config.gd SPEED_STAND == 4.5")
	_assert(config.RIFLE_FIRE_INTERVAL == 0.1, "game_config.gd RIFLE_FIRE_INTERVAL == 0.1")

	# -- events.gd: signal bus must expose the contracted signals --
	var events = load("res://autoload/events.gd").new()
	_assert(events.has_signal(&"weapon_fired"), "events.gd has signal weapon_fired")
	_assert(events.has_signal(&"game_over"), "events.gd has signal game_over")

	# -- game_state.gd: reset() must restore the three body-part health keys --
	var state = load("res://autoload/game_state.gd").new()
	state.reset()
	_assert(state.health.has(&"head"), "game_state.gd reset() health has key 'head'")
	_assert(state.health.has(&"body"), "game_state.gd reset() health has key 'body'")
	_assert(state.health.has(&"legs"), "game_state.gd reset() health has key 'legs'")

	# Free the manual instances so the headless run exits without leak noise.
	config.free()
	events.free()
	state.free()

	if _failures > 0:
		print("smoke_contracts: " + str(_failures) + " assertion(s) FAILED")
		quit(1)
	else:
		print("smoke_contracts: all assertions passed")
		quit(0)
