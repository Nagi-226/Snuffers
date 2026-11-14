## Native consumable HUD: real pickup/use signals, paired pixels and corner layout.
extends SceneTree

const OUTPUT_DIR := "res://tmp_shots/consumable_hud"
var _assertions := 0
var _failures := 0
var _world: Node3D
var _player: CharacterBody3D
var _hud: CanvasLayer
var _grenade: Control
var _medicine: Control
var _state: Node
var _config: Node


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		print("FAIL: ", label)


func _run() -> void:
	_assert(DisplayServer.get_name() != "headless", "consumable evidence uses native rendering")
	if _failures:
		quit(1)
		return
	create_timer(50.0, true).timeout.connect(_timeout)
	root.size = Vector2i(1920, 1080)
	_assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR)) == OK, "consumable screenshot directory is available")
	_state = root.get_node("GameState")
	_config = root.get_node("GameConfig")
	_state.reset()
	_world = (load("res://scenes/levels/weapons_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	current_scene = _world
	_player = _world.get_node("Player") as CharacterBody3D
	_player.global_position = Vector3(0, 0.1, 4)
	for frame in 12:
		await process_frame
	_freeze(_world)
	var driver := _world.get_node("GreyboxArena/DayNightController")
	driver.set_mode(driver.Mode.DAY)
	_player.global_position = Vector3(0, 0.1, 4)
	_player.rotation = Vector3.ZERO
	_player._pitch = 0.0
	(_player.get_node("Camera3D") as Camera3D).rotation = Vector3.ZERO
	_player._set_aiming(false)
	_player._switch_weapon(&"rifle")
	_hud = _world.get_node("HUD") as CanvasLayer
	_grenade = _hud.find_child("EC60EInventory", true, false) as Control
	_medicine = _hud.find_child("MedkitInventory", true, false) as Control
	_assert(_grenade != null, "actual range contains the grenade inventory")
	_assert(_medicine != null, "actual range contains a separate medkit inventory")
	if _grenade != null:
		await _no_hint_check()
	if _grenade != null and _medicine != null:
		_layout_check("1920x1080")
		await _stock_and_icon_checks()
		await _pickup_checks()
		await _switch_and_resize_checks()
		await _rebuild_check()
	await _finish()


func _freeze(node: Node) -> void:
	for child: Node in node.find_children("*", "Node", true, false):
		child.set_process(false)
		child.set_physics_process(false)
		child.set_process_unhandled_input(false)
		if child is AnimationPlayer:
			(child as AnimationPlayer).pause()


func _capture(name: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	_assert(not result.is_empty() and result.get_size() == root.size, name + " captures the actual viewport")
	_assert(result.save_png(OUTPUT_DIR.path_join(name + ".png")) == OK, name + " saves native evidence")
	return result


func _changed(first: Image, second: Image, rect: Rect2i, cyan_only: bool = false) -> int:
	var count := 0
	var clipped := rect.intersection(Rect2i(Vector2i.ZERO, first.get_size()))
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			if cyan_only:
				if b.g - a.g > 0.025 and b.b - a.b > 0.025 and b.b > b.r * 1.05 and b.g > b.r:
					count += 1
			elif absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.05:
				count += 1
	return count


func _region(control: Control, offset: Vector2, extent: Vector2i) -> Rect2i:
	return Rect2i(Vector2i(control.get_global_rect().position + offset), extent)


func _no_hint_check() -> void:
	var shown := await _capture("initial_consumables")
	_grenade.visible = false
	var hidden := await _capture("grenade_reference_hidden")
	_assert(_changed(hidden, shown, _region(_grenade, Vector2(0, 72), Vector2i(88, 16))) == 0, "the old G/T instruction line is absent from the grenade HUD")
	_grenade.visible = true


func _layout_check(label: String) -> void:
	var grenade := _grenade.get_global_rect()
	var medicine := _medicine.get_global_rect()
	var grenade_icon: Rect2 = _config.EC60E_HUD_ICON_RECT
	var medicine_icon: Rect2 = _config.MEDKIT_HUD_ICON_RECT
	_assert(grenade.size == Vector2(270, 96) and medicine.size == grenade.size, label + " consumable groups retain readable 270x96 bounds")
	_assert(is_equal_approx(grenade.position.x, 16.0) and is_equal_approx(grenade.end.y, root.size.y - 16.0), label + " consumables stay 16px from the left and bottom")
	_assert(is_equal_approx(medicine.position.y, grenade.position.y) and is_equal_approx(medicine.position.x - grenade.end.x, 16.0), label + " medkit appears horizontally beside the grenade with a 16px gap")
	_assert(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(medicine), label + " both consumable groups remain inside the viewport")
	_assert(grenade_icon.position.x >= 0.0 and grenade_icon.position.x <= 100.0, label + " grenade outline sits close beside its text")
	_assert(medicine_icon.position.x >= 0.0 and medicine_icon.position.x <= 60.0, label + " medkit outline sits close beside its text")
	_assert(grenade_icon.position.y == medicine_icon.position.y and grenade_icon.size.y == medicine_icon.size.y, label + " both consumable outlines retain matching vertical alignment and height")


func _stock_and_icon_checks() -> void:
	_assert(_state.medkits == 0 and _medicine.get("stock") == 0 and _medicine.is_visible_in_tree(), "zero initial medkit stock remains visible")
	_assert(_grenade.get("stock") == 100 and _grenade.is_visible_in_tree(), "grenade stock remains independently visible at 100")
	var shown := await _capture("both_initial")
	_grenade.visible = false
	_medicine.visible = false
	var hidden := await _capture("both_reference_hidden")
	for item: Control in [_grenade, _medicine]:
		var label := String(item.name)
		var icon_bounds: Rect2 = _config.EC60E_HUD_ICON_RECT if item == _grenade else _config.MEDKIT_HUD_ICON_RECT
		var icon := _region(item, icon_bounds.position, Vector2i(icon_bounds.size))
		var icon_pixels := _changed(hidden, shown, icon, true)
		print("CONSUMABLE_ICON ", label, " cyan_pixels=", icon_pixels)
		_assert(icon_pixels > 150, label + " contributes visible cyan outline pixels")
		_assert(_changed(hidden, shown, _region(item, Vector2.ZERO, Vector2i(4, 96))) == 0, label + " has no outer frame or background at its left edge")
		_assert(_changed(hidden, shown, _region(item, Vector2(4, 1), Vector2i(262, 4))) == 0, label + " blank top area remains transparent")
	_grenade.visible = true
	_medicine.visible = true


func _pickup_medkit() -> void:
	var pickup := (load("res://scenes/levels/pickup.tscn") as PackedScene).instantiate() as Area3D
	pickup.kind = &"medkit"
	pickup.position = Vector3(1000, 0, 1000)
	_world.add_child(pickup)
	pickup.set_process(false)
	pickup.call("_on_body_entered", _player)
	await process_frame


func _pickup_checks() -> void:
	var empty := await _capture("medkit_zero")
	await _pickup_medkit()
	_assert(_state.medkits == 1 and _medicine.get("stock") == 1, "real medkit Pickup updates both State and HUD to one")
	var picked := await _capture("medkit_picked_one")
	var count_rect := _region(_medicine, Vector2(10, 30), Vector2i(120, 40))
	_assert(_changed(empty, picked, count_rect) > 30, "real pickup visibly redraws the medkit count glyph")
	_state.armor = 0.0
	_state.hp = 21.0
	_player._apply_damage(&"hp", 2.0)
	_assert(_state.medkits == 0 and _medicine.get("stock") == 0 and _state.hp == _config.HEALTH_MAX, "real damage automatically consumes the medkit and updates HUD to zero")
	var used := await _capture("medkit_automatic_zero")
	_assert(_changed(picked, used, count_rect) > 30, "automatic medkit use visibly redraws its count glyph")
	var icon_bounds: Rect2 = _config.MEDKIT_HUD_ICON_RECT
	_assert(_changed(picked, used, _region(_medicine, icon_bounds.position, Vector2i(icon_bounds.size))) == 0, "automatic use preserves the medkit outline at zero")
	_assert(_state.ec60e_grenades == 100 and _grenade.get("stock") == 100, "medkit pickup and automatic use leave the independent grenade count intact")


func _switch_and_resize_checks() -> void:
	var grenade := _grenade.get_global_rect()
	var medicine := _medicine.get_global_rect()
	for weapon: StringName in [&"pistol", &"smg", &"rifle", &"spas12", &"lmg", &"em120r"]:
		_player._switch_weapon(weapon)
		_assert(_grenade.get_global_rect() == grenade and _medicine.get_global_rect() == medicine and _medicine.get("stock") == _state.medkits and _grenade.is_visible_in_tree() and _medicine.is_visible_in_tree(), "%s gun switch preserves both consumable inventories" % weapon)
	_player._switch_weapon(&"rifle")
	root.size = Vector2i(1280, 720)
	await process_frame
	_layout_check("1280x720")
	await _capture("consumables_720p")
	root.size = Vector2i(1920, 1080)
	await process_frame


func _rebuild_check() -> void:
	await _pickup_medkit()
	_assert(_state.medkits == 1, "real pickup prepares retained stock for HUD reconstruction")
	_hud.queue_free()
	await process_frame
	_hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as CanvasLayer
	_hud.range_mode = true
	_world.add_child(_hud)
	_freeze(_hud)
	_grenade = _hud.find_child("EC60EInventory", true, false) as Control
	_medicine = _hud.find_child("MedkitInventory", true, false) as Control
	_assert(_medicine != null and _grenade != null, "reconstructed production HUD restores both consumable widgets")
	if _medicine == null or _grenade == null:
		return
	_assert(_medicine.get("stock") == 1 and _grenade.get("stock") == 100, "reconstructed HUD reads current State rather than hardcoded initial counts")
	await _pickup_medkit()
	_assert(_state.medkits == 2 and _medicine.get("stock") == 2, "reconstructed medkit HUD continues receiving real pickup signals")
	_state.armor = 0.0
	_state.hp = 21.0
	_player._apply_damage(&"hp", 2.0)
	_assert(_state.medkits == 1 and _medicine.get("stock") == 1, "reconstructed medkit HUD continues receiving automatic use signals")
	await _capture("rebuilt_consumables")


func _finish() -> void:
	_world.queue_free()
	current_scene = null
	await process_frame
	await RenderingServer.frame_post_draw
	print("CONSUMABLE_HUD COMPLETED assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures else 0)


func _timeout() -> void:
	print("FAIL: CONSUMABLE_HUD timed out before completion")
	quit(1)
