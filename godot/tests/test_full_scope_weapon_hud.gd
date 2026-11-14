extends SceneTree

const FULL_SCOPE_IDS: Array[StringName] = [&"dmr", &"em86s", &"em86d", &"em127g", &"em127m", &"em40t1", &"em120r"]
const OUTPUT_DIR := "tmp_shots/full_scope_weapon_hud"

var _failures := 0
var _completed := 0
var _world: Node3D
var _player: CharacterBody3D
var _hud: CanvasLayer
var _ammo: Control
var _inventory: Control
var _state
var _started_msec := 0


func _init() -> void:
	call_deferred("_run")


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _run() -> void:
	_started_msec = Time.get_ticks_msec()
	create_timer(45.0).timeout.connect(_timeout)
	_state = root.get_node("GameState")
	_state.reset()
	root.size = Vector2i(1600, 900)
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	_world.add_child(_player)
	_hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as CanvasLayer
	_world.add_child(_hud)
	_ammo = _hud._weapon_ammo
	_inventory = _hud.find_child("EC60EInventory", true, false) as Control
	if _inventory == null:
		_abort("production HUD is missing its grenade inventory")
		return
	for id in _state.weapon_unlocked:
		_state.weapon_unlocked[id] = true
	# Keep world geometry and tactical labels fixed across paired renders.
	for node in _world.find_children("*", "Node", true, false):
		node.set_process(false)
		node.set_physics_process(false)
		node.set_process_unhandled_input(false)
	var error := DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	if error != OK:
		_abort("cannot create render evidence directory")
		return
	for id in FULL_SCOPE_IDS:
		_player._set_aiming(false)
		_player._switch_weapon(id)
		_player._set_aiming(true)
		_settle()
		if not await _check_fields(id):
			_abort("render field checks did not complete for %s" % id)
			return
		if id in [&"em86s", &"em127g", &"em127m", &"em120r"]:
			for step in 2:
				_player._adjust_em86s_zoom(1)
				_player._process(1.0 / 60.0)
				_assert(is_equal_approx(_player._camera.fov, _player._scope_fovs()[_player._em86s_zoom_index]), "%s uses the selected zoom FOV" % id)
				if not await _check_corner("%s_zoom_%d" % [id, step + 1]):
					return
		_player._set_aiming(false)
		_player._process(0.01)
		if not await _check_corner("%s_closing" % id):
			return
		_settle()
		if not await _check_corner("%s_hip_restored" % id):
			return
		_completed += 1
		print("FULL_SCOPE_RENDER_PROGRESS: ", id, " elapsed_ms=", Time.get_ticks_msec() - _started_msec)
	_player._switch_weapon(&"em120r")
	_player._set_aiming(true)
	_settle()
	_player._switch_weapon(&"dmr")
	_player._process(0.01)
	_assert(_ammo.weapon_id == &"dmr", "switching weapons while scoped updates the status widget immediately")
	if not await _check_corner("scope_switch_to_dmr"):
		return
	_settle()
	_player._toggle_big_map()
	_assert(_player._big_map.visible, "map opens while the scope is active")
	if not await _check_corner("scope_map_open"):
		return
	_player._toggle_big_map()
	_assert(not _player._big_map.visible, "map closes and returns to the scoped view")
	if not await _check_corner("scope_map_closed"):
		return
	if not await _check_end_screen_order():
		_abort("end-screen layer test did not complete")
		return
	_assert(_completed == FULL_SCOPE_IDS.size(), "all seven full-screen weapon scopes completed actual render checks")
	_world.queue_free()
	await process_frame
	print("FULL_SCOPE_WEAPON_HUD failures=", _failures, " scopes_completed=", _completed)
	quit(1 if _failures else 0)


func _settle() -> void:
	for frame in 35:
		_player._process(1.0 / 60.0)


func _capture(label: String = "") -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	if result == null or result.is_empty():
		_abort("renderer produced no image")
		return null
	if label != "":
		var error := result.save_png("%s/%s.png" % [OUTPUT_DIR, label])
		if error != OK:
			_abort("could not save screenshot %s" % label)
			return null
	return result


func _corner(image: Image) -> Rect2i:
	# Includes the name drawn above the Control and the icon child at x=128.
	return Rect2i(image.get_width() - 320, image.get_height() - 160, 320, 160)


func _difference(first: Image, second: Image) -> Dictionary:
	var count := 0
	var mass := 0.0
	var region := _corner(first)
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			var difference := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
			if difference > 0.025:
				count += 1
			mass += difference
	return {"count": count, "mass": mass}


func _check_fields(id: StringName) -> bool:
	_assert(_inventory.is_visible_in_tree(), "%s scope keeps the grenade inventory visible above its mask" % id)
	var full: Image = await _capture("%s_full_scope" % id)
	if full == null:
		return false
	_ammo.visible = false
	# Isolate the existing black scope surround; the new inventory also overlaps
	# the top four pixels of this fixed ammunition sampling region.
	var inventory_visible := _inventory.visible
	_inventory.visible = false
	var mask: Image = await _capture()
	_ammo.visible = true
	_inventory.visible = inventory_visible
	if mask == null:
		return false
	var maximum := 0.0
	var region := _corner(mask)
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var color := mask.get_pixel(x, y)
			maximum = maxf(maximum, maxf(color.r, maxf(color.g, color.b)))
	_assert(maximum < 0.03, "%s status region is inside the actual opaque black scope surround" % id)
	for property: StringName in [&"weapon_name", &"mag", &"reserve", &"mode_tag", &"ammo_type"]:
		var original: Variant = _ammo.get(property)
		_ammo.set(property, int(original) + 19 if property in [&"mag", &"reserve"] else "")
		var omitted: Image = await _capture()
		_ammo.set(property, original)
		if omitted == null:
			return false
		var difference := _difference(full, omitted)
		_assert(difference.count > 8, "%s %s is rendered above the mask (%d changed corner pixels)" % [id, property, difference.count])
	_ammo._icon.visible = false
	var no_icon: Image = await _capture()
	_ammo._icon.visible = true
	if no_icon == null:
		return false
	var icon_difference := _difference(full, no_icon)
	_assert(icon_difference.count > 8, "%s actual weapon icon is rendered above the mask (%d changed pixels)" % [id, icon_difference.count])
	return true


func _check_corner(label: String) -> bool:
	var full: Image = await _capture(label)
	_ammo.visible = false
	var hidden: Image = await _capture()
	_ammo.visible = true
	if full == null or hidden == null:
		_abort("transition capture did not complete: %s" % label)
		return false
	var difference := _difference(full, hidden)
	_assert(difference.count > 50, "%s retains the actual rendered weapon status (%d pixels)" % [label, difference.count])
	return true


func _check_end_screen_order() -> bool:
	var full: Image = await _capture()
	_ammo.visible = false
	var hidden: Image = await _capture()
	_ammo.visible = true
	if full == null or hidden == null:
		return false
	var normal_mass: float = _difference(full, hidden).mass
	var end_screen := (load("res://scenes/ui/mission_end_screen.tscn") as PackedScene).instantiate()
	_world.add_child(end_screen)
	end_screen.set_process_unhandled_input(false)
	# The production panel is centered. Move only the test instance over the
	# status region to prove its real layer-20 foreground still wins overlap.
	var panel := end_screen.get_node("Panel") as Control
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = _ammo.get_global_transform_with_canvas().origin - Vector2(20, 25)
	panel.size = Vector2(320, 180)
	print("MISSION_END_FIXTURE: moved the real centered Panel over the HUD solely to test layer-20 overlap; production end screen is not a fullscreen mask")
	root.get_node("Events").mission_completed.emit()
	var end_full: Image = await _capture("mission_end_overlap")
	_ammo.visible = false
	var end_hidden: Image = await _capture()
	_ammo.visible = true
	paused = false
	if end_full == null or end_hidden == null:
		return false
	var foreground_mass: float = _difference(end_full, end_hidden).mass
	_assert(end_screen._shown and normal_mass > 10.0 and foreground_mass < normal_mass * 0.3, "real mission-end layer 20 covers the weapon HUD at overlap instead of being covered by it")
	end_screen.queue_free()
	return true


func _abort(reason: String) -> void:
	push_error("FULL_SCOPE_HUD_ABORT: " + reason)
	paused = false
	quit(1)


func _timeout() -> void:
	_abort("render checks timed out before completing all phases")
