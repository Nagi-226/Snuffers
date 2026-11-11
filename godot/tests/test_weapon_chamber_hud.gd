## Real HUD event routes for container+chamber and conventional accessory labels.
extends SceneTree

const IDS := [&"rifle", &"pistol", &"g17", &"dmr", &"shotgun", &"spas12", &"smg", &"mpx", &"em57s2", &"lmg", &"magnum", &"em86s", &"em86b", &"em86d", &"em86m", &"em127g", &"em127m", &"em12g2"]
const RESERVES := {
	&"rifle": &"rifle_reserve", &"dmr": &"rifle_reserve", &"lmg": &"rifle_reserve",
	&"pistol": &"pistol_reserve", &"smg": &"pistol_reserve", &"em57s2": &"pistol_reserve",
	&"g17": &"ammo_9x19_reserve", &"mpx": &"ammo_9x19_reserve",
	&"shotgun": &"shotgun_reserve", &"em12g2": &"shotgun_reserve", &"spas12": &"spas12_reserve",
	&"magnum": &"magnum_reserve", &"em127g": &"magnum_reserve", &"em127m": &"magnum_reserve",
	&"em86s": &"em86_reserve", &"em86b": &"em86_reserve", &"em86d": &"em86_reserve", &"em86m": &"em86_reserve",
}
const LABELS := {&"laser": "红点", &"flashlight": "手电", &"combined": "红点+手电"}
const OUTPUT := "res://tmp_shots/weapon_chamber_hud"
const BONUS_FONT_SIZE := 12
const BONUS_OFFSET := Vector2(3, -28)

class ExpectedGlyphs extends Control:
	var font: Font
	var main_count: int
	var spare_count: int
	var bonus: bool

	func _draw() -> void:
		var color := Color(0.38, 0.86, 1.0, 0.95)
		var secondary := Color(0.38, 0.86, 1.0, 0.68)
		draw_string(font, Vector2(0, 40), str(main_count), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, color)
		draw_string(font, Vector2(70, 32), str(spare_count), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, secondary)
		if bonus:
			var width := font.get_string_size(str(main_count), HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
			draw_string(font, Vector2(width + 3, 12), "+1", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)

var _assertions := 0
var _failures := 0
var _world: Node3D
var _hud
var _ammo: Control
var _state
var _events
var _config
var _capacities: Dictionary = {}
var _evidence: Array[Dictionary] = []
var _native := false
var _draw_cases := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(100.0).timeout.connect(func() -> void:
		push_error("weapon chamber HUD timed out")
		quit(1))
	_native = DisplayServer.get_name() != "headless"
	root.size = Vector2i(1600, 900)
	_state = root.get_node("GameState")
	_events = root.get_node("Events")
	_config = root.get_node("GameConfig")
	_state.reset()
	for id: StringName in IDS:
		var data := WeaponData.new()
		data.weapon_id = id
		data.sync_from_config()
		_capacities[id] = data.mag_size
		_set_supply(id, data.mag_size - 1, true)
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	_hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	_world.add_child(_hud)
	_ammo = _hud.get_node("WeaponStatusLayer/WeaponAmmo") as Control
	for node in _world.find_children("*", "Node", true, false):
		node.set_process(false)
		node.set_physics_process(false)
		node.set_process_unhandled_input(false)
	await process_frame
	_assert(_ammo != null and _ammo == _hud._weapon_ammo and _ammo.is_visible_in_tree(), "real HUD exposes its visible WeaponStatusLayer/WeaponAmmo control")
	_assert(DirAccess.make_dir_recursive_absolute(OUTPUT) == OK, "HUD evidence output opens")
	for id: StringName in IDS:
		await _check_gun(id)
	_check_exceptions()
	await _check_accessories()
	_assert(_draw_cases == (42 if _native else 0), "HUD completes all 18 count, eighteen overflow and six accessory native draw cases when rendering is available")
	if not _native:
		print("SKIP: native HUD pixel checks require a native display; real Control/event checks completed")
	var report := FileAccess.open(OUTPUT + "/report.json", FileAccess.WRITE)
	_assert(report != null, "HUD report opens")
	if report != null:
		report.store_string(JSON.stringify({"assertions": _assertions, "failures": _failures, "native": _native, "native_draw_cases": _draw_cases, "evidence": _evidence}, "\t"))
		report.close()
	_world.queue_free()
	current_scene = null
	await process_frame
	print("WEAPON_CHAMBER_HUD COMPLETED assertions=", _assertions, " failures=", _failures, " native_draw_cases=", _draw_cases)
	quit(1 if _failures > 0 else 0)


func _set_supply(id: StringName, mag: int, chamber: bool) -> void:
	_state.set(String(id) + "_mag", mag)
	_state.weapon_chambered[id] = chamber


func _switch(id: StringName) -> void:
	_state.current_weapon = id
	_events.weapon_switched.emit(id)


func _emit_ammo(id: StringName) -> void:
	_events.ammo_changed.emit(id, int(_state.get(String(id) + "_mag")), int(_state.get(RESERVES[id])))


func _check_display(id: StringName, wanted: int, label: String) -> void:
	_assert(_ammo.get("weapon_id") == id and _ammo.get("mag") == wanted and _ammo.get("reserve") == _state.get(RESERVES[id]), label + " shows the current identity, total available rounds and unchanged reserve")
	_assert(_ammo.get("show_chamber_bonus") == (wanted == int(_capacities[id]) + 1), label + " only marks the one round overflowing the nominal capacity")
	_assert(_ammo.get("weapon_name") != "" and _ammo.get_child_count() == 1 and _ammo.get_child(0).get("weapon_id") == id, label + " retains the actual named weapon icon without adding UI children")


func _check_gun(id: StringName) -> void:
	var capacity: int = _capacities[id]
	_set_supply(id, capacity - 1, true)
	_switch(id)
	_check_display(id, capacity, "%s switch initial M" % id)
	if _native:
		await _check_drawn_count(id, capacity)
	_set_supply(id, capacity, true)
	_emit_ammo(id)
	_check_display(id, capacity + 1, "%s tactical event M+1" % id)
	var tactical: Image
	if _native:
		tactical = await _capture(String(id) + "_tactical_bonus")
	_set_supply(id, capacity - 1, true)
	_emit_ammo(id)
	_check_display(id, capacity, "%s shot event total M" % id)
	if _native:
		var ordinary := await _capture(String(id) + "_shot_without_bonus")
		_set_supply(id, capacity - 1, true)
		_emit_ammo(id)
		_check_display(id, capacity, "%s empty reload event total M" % id)
		var empty_reload := await _capture(String(id) + "_empty_reload_without_bonus")
		await _check_drawn_bonus(id, capacity, tactical, ordinary, empty_reload)
	_set_supply(id, 0, true)
	_emit_ammo(id)
	_check_display(id, 1, "%s final chamber event" % id)
	_set_supply(id, 0, false)
	_emit_ammo(id)
	_check_display(id, 0, "%s truly empty event" % id)
	_set_supply(id, 2, false)
	_emit_ammo(id)
	_check_display(id, 2, "%s empty-chamber event" % id)
	var before := _snapshot()
	var other := &"pistol" if id != &"pistol" else &"rifle"
	_events.ammo_changed.emit(other, 999, 888)
	_assert(_snapshot() == before, "%s non-current ammo event cannot overwrite the real current widget" % id)
	_evidence.append({"weapon": id, "initial": capacity, "tactical": capacity + 1, "last_chamber": 1})


func _check_exceptions() -> void:
	# Deliberately stale unsupported state must not give missiles/grenades a chamber.
	for item: Array in [[&"em120r", _config.EM120R_MAG, &"em120r_reserve"], [&"em40t1", _config.EM40T1_MAG, &"rifle_grenades"]]:
		var id: StringName = item[0]
		_state.set(String(id) + "_mag", int(item[1]))
		_state.weapon_chambered[id] = true
		_switch(id)
		_assert(_ammo.get("weapon_id") == id and _ammo.get("mag") == item[1] and _ammo.get("reserve") == _state.get(item[2]), "%s switch ignores unsupported chamber state and preserves original capacity" % id)
		_assert(_ammo.get("show_chamber_bonus") == false, "%s unsupported chamber state cannot add an overflow badge" % id)
		_events.ammo_changed.emit(id, 3, 7)
		_assert(_ammo.get("mag") == 3 and _ammo.get("reserve") == 7, "%s same-name event retains raw grenade/missile counts without +1" % id)
		_assert(_ammo.get("show_chamber_bonus") == false, "%s launcher ammo event retains its ordinary raw-count display" % id)
		_state.weapon_chambered.erase(id)
	_set_supply(&"rifle", _capacities[&"rifle"], true)
	_state.fire_modes[&"rifle"] = &"grenade"
	_state.rifle_grenades = 6
	_switch(&"rifle")
	_assert(_ammo.get("mag") == int(_capacities[&"rifle"]) + 1 and _ammo.get("grenade_stock") == 6 and _ammo.get("show_grenades") and _ammo.get("mode_tag") == "滚雷", "underbarrel mode preserves primary chamber total and unchanged separate six-grenade stock")
	_assert(_ammo.get("show_chamber_bonus") == true, "underbarrel mode retains the primary weapon overflow badge without adding one to grenade stock")
	_state.fire_modes[&"rifle"] = &"auto"


func _check_accessories() -> void:
	for id: StringName in [&"g17", &"mpx"]:
		_state.fire_modes[id] = &"semi" if id == &"g17" else &"auto"
		_set_supply(id, int(_capacities[id]) - 1, true)
		_state.weapon_accessory_modes[id] = &"laser"
		_switch(id)
		_assert(_ammo.get("mode_tag") == _expected_tag(id, &"laser"), "%s switch displays its default Chinese laser accessory tag" % id)
		for mode: StringName in [&"flashlight", &"combined", &"laser"]:
			_state.weapon_accessory_modes[id] = mode
			_events.weapon_accessory_mode_changed.emit(id, mode)
			_assert(_ammo.get("mode_tag") == _expected_tag(id, mode) and _ammo.get("mag") == _capacities[id] and _ammo.get("ammo_type") == "9×19mm", "%s real accessory event displays %s while retaining firing mode and ammunition" % [id, LABELS[mode]])
			if _native:
				await _check_drawn_accessory(id, mode)
		var before := _snapshot()
		var other := &"mpx" if id == &"g17" else &"g17"
		_state.weapon_accessory_modes[other] = &"combined"
		_events.weapon_accessory_mode_changed.emit(other, &"combined")
		_assert(_snapshot() == before, "%s non-current accessory event cannot replace the current tag or ammunition" % id)
	_state.weapon_accessory_modes[&"g17"] = &"flashlight"
	_state.weapon_accessory_modes[&"mpx"] = &"combined"
	for id: StringName in [&"g17", &"mpx", &"g17"]:
		_switch(id)
		_assert(_ammo.get("mode_tag") == _expected_tag(id, _state.weapon_accessory_modes[id]), "%s switch restores its own independently remembered accessory label" % id)
	_switch(&"rifle")
	var before := _snapshot()
	_events.weapon_accessory_mode_changed.emit(&"g17", &"laser")
	_assert(_snapshot() == before and not "红点" in String(_ammo.get("mode_tag")) and not "手电" in String(_ammo.get("mode_tag")), "unsupported current rifle cannot inherit conventional accessory labels")
	_state.reset()
	for id: StringName in [&"g17", &"mpx"]:
		_switch(id)
		_assert(_ammo.get("mode_tag") == _expected_tag(id, &"laser"), "%s reset and switch restore the default Chinese laser tag" % id)


func _expected_tag(id: StringName, mode: StringName) -> String:
	return ("半自动" if id == &"g17" else "全自动") + "·" + String(LABELS[mode])


func _snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for field: StringName in [&"weapon_id", &"weapon_name", &"mag", &"reserve", &"mode_tag", &"ammo_type", &"show_grenades", &"grenade_stock", &"show_chamber_bonus"]:
		snapshot[field] = _ammo.get(field)
	return snapshot


func _check_drawn_count(id: StringName, wanted: int) -> void:
	var original: int = _ammo.get("mag")
	var full := await _capture(String(id) + "_count")
	_ammo.set("mag", wanted + 19)
	var changed := await _capture(String(id) + "_count_changed")
	_ammo.set("mag", original)
	if full == null or changed == null:
		return
	var region := Rect2i(Vector2i(_ammo.global_position), Vector2i(65, 50))
	var count := _pixel_difference(full, changed, region)
	_assert(count > 8, "%s actual count glyphs render in the visible HUD (%d changed pixels)" % [id, count])
	_draw_cases += 1


func _check_drawn_bonus(id: StringName, capacity: int, tactical: Image, ordinary: Image, empty_reload: Image) -> void:
	if tactical == null or ordinary == null or empty_reload == null:
		return
	var font := _ammo.get_theme_default_font()
	var big_width := font.get_string_size(str(capacity), HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	var small_width := font.get_string_size("+1", HORIZONTAL_ALIGNMENT_LEFT, -1, BONUS_FONT_SIZE).x
	var origin := Vector2i(_ammo.global_position)
	var badge_position := Vector2i(ceili(big_width + BONUS_OFFSET.x), 0)
	var badge_region := Rect2i(origin + badge_position, Vector2i(ceili(small_width) + 3, 14))
	# The independent glyph reference excludes the existing 弹药 label at y=49.
	var count_region := Rect2i(origin + Vector2i(0, 16), Vector2i(65, 33))
	var reserve_region := Rect2i(origin + Vector2i(70, 16), Vector2i(65, 27))
	# Independent expected glyphs: no WeaponAmmo script or its count/bonus logic.
	var reference_layer := CanvasLayer.new()
	reference_layer.layer = 5
	_world.add_child(reference_layer)
	var reference := ExpectedGlyphs.new()
	reference.font = font
	reference.main_count = capacity
	reference.spare_count = int(_state.get(RESERVES[id]))
	reference.bonus = true
	reference.position = _ammo.global_position
	reference_layer.add_child(reference)
	_ammo.hide()
	var expected_bonus := await _capture(String(id) + "_expected_M_plus_one_glyphs")
	reference.bonus = false
	reference.queue_redraw()
	var expected_ordinary := await _capture(String(id) + "_expected_M_ordinary_glyphs")
	_ammo.show()
	reference_layer.queue_free()
	await process_frame
	if expected_bonus == null or expected_ordinary == null:
		return
	var badge_pixels := _pixel_difference(tactical, ordinary, badge_region)
	var main_pixels := _pixel_difference(tactical, ordinary, count_region)
	var reserve_pixels := _pixel_difference(tactical, ordinary, reserve_region)
	_assert(badge_pixels > 8, "%s actual small +1 glyph renders above and after its %d main count (%d pixels)" % [id, capacity, badge_pixels])
	_assert(_pixel_difference(tactical, expected_bonus, badge_region) == 0, "%s actual +1 glyph matches the independent twelve-point upper-right reference" % id)
	_assert(_pixel_difference(tactical, expected_bonus, count_region) == 0 and _pixel_difference(ordinary, expected_ordinary, count_region) == 0, "%s actual tactical and fired large glyphs match independently drawn %d rather than %d" % [id, capacity, capacity + 1])
	_assert(_pixel_difference(ordinary, expected_ordinary, badge_region) == 0 and _pixel_difference(empty_reload, expected_ordinary, badge_region) == 0, "%s firing and empty reload remove the actual overflow glyph" % id)
	_assert(main_pixels == 0, "%s tactical M+1 and fired M retain the same actual large M glyphs" % id)
	_assert(reserve_pixels == 0, "%s overflow glyph does not alter or collide with actual reserve glyphs" % id)
	_assert(_pixel_difference(ordinary, empty_reload, Rect2i(origin, Vector2i(135, 50))) == 0, "%s empty reload M has the same actual ordinary count and no +1 badge" % id)
	_draw_cases += 1
	_evidence.append({"weapon": id, "large_count": capacity, "total_tactical": capacity + 1, "bonus_baseline": 40.0 + BONUS_OFFSET.y, "bonus_region": badge_region, "bonus_pixels": badge_pixels, "large_glyph_changed_pixels": main_pixels, "reserve_changed_pixels": reserve_pixels})


func _check_drawn_accessory(id: StringName, mode: StringName) -> void:
	var original: String = _ammo.get("mode_tag")
	var full := await _capture(String(id) + "_" + String(mode))
	_ammo.set("mode_tag", "半自动" if id == &"g17" else "全自动")
	var stripped := await _capture(String(id) + "_" + String(mode) + "_without_accessory")
	_ammo.set("mode_tag", original)
	if full == null or stripped == null:
		return
	var region := Rect2i(Vector2i(_ammo.global_position) + Vector2i(0, 62), Vector2i(200, 24))
	var count := _pixel_difference(full, stripped, region)
	_assert(count > 8, "%s %s Chinese accessory suffix actually renders in the HUD (%d changed pixels)" % [id, LABELS[mode], count])
	_draw_cases += 1
	_evidence.append({"weapon": id, "accessory": mode, "tag": original, "native_suffix_pixels": count})


func _capture(label: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_assert(image != null and not image.is_empty(), "%s native HUD image exists" % label)
	if image == null or image.is_empty():
		return null
	_assert(image.save_png(OUTPUT + "/" + label + ".png") == OK, "%s native HUD image saves" % label)
	return image


func _pixel_difference(first: Image, second: Image, region: Rect2i) -> int:
	var count := 0
	for y in range(maxi(0, region.position.y), mini(first.get_height(), region.end.y)):
		for x in range(maxi(0, region.position.x), mini(first.get_width(), region.end.x)):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 0.025:
				count += 1
	return count


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
