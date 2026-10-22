## probe_fx_textures.gd — 爆炸特效程序纹理直出取证（2026-10-22）
## 用法：godot --headless --path godot -s res://tools/probe_fx_textures.gd -- <out_dir>
## 把 explosion_fx.gd 运行时合成的 4 张纹理原样存盘，用于排查面片边缘/颜色问题。
extends SceneTree

const AUTOLOADS: Array = [
	["Events", "res://autoload/events.gd"],
	["GameConfig", "res://autoload/game_config.gd"],
	["GameState", "res://autoload/game_state.gd"],
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var nodes: Array = []
	for pair: Array in AUTOLOADS:
		var n = (load(pair[1]) as Script).new()
		n.name = pair[0]
		root.add_child(n)
		nodes.append(n)
	var fx = (load("res://scripts/weapons/explosion_fx.gd") as Script).new()
	root.add_child(fx)
	var out_dir := "user://"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	for pair: Array in [
		["fireball", fx._fireball_texture],
		["smoke", fx._smoke_texture],
		["ring", fx._ring_texture],
		["scorch", fx._scorch_texture],
	]:
		var path: String = out_dir.path_join("fx_%s.png" % pair[0])
		(pair[1] as ImageTexture).get_image().save_png(path)
		print("PROBE saved=", path)
	for n: Node in nodes:
		n.queue_free()
	quit()
