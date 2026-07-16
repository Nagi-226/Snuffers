## check_scripts.gd -- per-script compile check for the L1 chain.
##
## Why not `godot --check-only --script`? In headless check-only mode the
## GDScript analyzer cannot resolve autoload MEMBER access (e.g.
## Events.weapon_fired, GameConfig.view_sensitivity, GameState.kills):
## autoload identifiers only resolve when matching nodes exist under the
## scene tree root. That makes --check-only report false
## "Identifier not found" errors on correct scripts. (Constant access like
## GameConfig.FOV_BASE is unaffected - constants are folded at compile time.)
##
## This harness recreates the autoload nodes manually (autoloads are NOT
## auto-instantiated in -s mode), then compiles every target script from
## source text and prints one SCRIPT-OK / SCRIPT-FAIL line per file.
## Exit code 1 if any script fails.
##
## Compile strategy: a fresh GDScript object is fed the file's source code
## and reload()ed. This avoids three traps found the hard way:
##   - load() returns a non-null resource even when compilation failed;
##   - reload() on a cached script fails with ERR_BUSY once instances exist;
##   - reload() on the currently running script crashes the engine.
##
## Usage:
##   godot --headless --path . -s res://tests/check_scripts.gd -- <res:// script paths...>
extends SceneTree

## Order matters: game_state.gd references GameConfig at compile time.
const AUTOLOADS: Array = [
	["Events", "res://autoload/events.gd"],
	["GameConfig", "res://autoload/game_config.gd"],
	["GameState", "res://autoload/game_state.gd"],
]

var _failures: int = 0


func _init() -> void:
	# root is not ready inside _init; defer the real work to the first frame.
	call_deferred("_run")


func _run() -> void:
	var targets: PackedStringArray = OS.get_cmdline_user_args()
	if targets.is_empty():
		print("check_scripts: no target scripts given (pass res:// paths after --)")
		quit(1)
		return

	# Recreate the autoload singletons so autoload identifiers resolve.
	# Instancing a script compiles it; a failure here is already reported by
	# the engine, so the autoload trio needs no separate check pass.
	for entry in AUTOLOADS:
		var node = load(entry[1]).new()
		node.name = entry[0]
		root.add_child(node)

	for path in targets:
		_check_one(path)

	if _failures > 0:
		print("check_scripts: " + str(_failures) + " script(s) FAILED")
		quit(1)
	else:
		print("check_scripts: all scripts OK")
		quit(0)


func _check_one(path: String) -> void:
	var source: String = FileAccess.get_file_as_string(path)
	if source.is_empty() and FileAccess.get_open_error() != OK:
		_failures += 1
		print("SCRIPT-FAIL: " + path + " (cannot read file, error " + str(FileAccess.get_open_error()) + ")")
		return
	# Strip any class_name declaration first: after --import the global class
	# cache already holds the name, so compiling a second declaration errors
	# with "hides a global script class" - a false failure for a syntax check.
	# Keeping a trailing "extends X" (if any) anchored at column 0 stays valid.
	var strip_re := RegEx.new()
	strip_re.compile("(?m)^[ \\t]*class_name[ \\t]+\\w+[ \\t]*")
	source = strip_re.sub(source, "", true)
	# Compile the source in a throwaway GDScript (zero instances, no cache,
	# safe even for this harness's own file).
	var script := GDScript.new()
	script.source_code = source
	var err: int = script.reload()
	if err != OK:
		_failures += 1
		print("SCRIPT-FAIL: " + path + " (compile error " + str(err) + ")")
	else:
		print("SCRIPT-OK: " + path)
