extends Node3D

const SCENE_GATE := preload("res://scripts/levels/scene_link.gd")
const PICKUP_SCENE := preload("res://scenes/levels/pickup.tscn")
const APC_MODEL := "res://assets/models/vehicles/jb02_apc.glb"
const TEXTURES := {
	"concrete": "res://assets/textures/warehouse/wall_concrete.bmp",
	"panel": "res://assets/textures/warehouse/facade_panel.bmp",
	"windows": "res://assets/textures/warehouse/facade_windows.bmp",
	"gate": "res://assets/textures/warehouse/gate_cargo_open.bmp",
}


func _ready() -> void:
	_world_env()
	_build_yard()
	_build_warehouse()
	_build_apc_bay()
	_build_return_link()


func _build_yard() -> void:
	_box("Ground", Vector3(0, -0.15, 0), Vector3(64, 0.3, 58), _material("concrete", Color(0.32, 0.34, 0.36)))
	_box("WallNorth", Vector3(0, 1.5, -28), Vector3(64, 3, 0.3), _material("panel", Color(0.5, 0.52, 0.54)))
	_box("WallSouthWest", Vector3(-17, 1.5, 28), Vector3(30, 3, 0.3), _material("panel", Color(0.5, 0.52, 0.54)))
	_box("WallSouthEast", Vector3(17, 1.5, 28), Vector3(30, 3, 0.3), _material("panel", Color(0.5, 0.52, 0.54)))
	_box("WallWest", Vector3(-32, 1.5, 0), Vector3(0.3, 3, 56), _material("panel", Color(0.5, 0.52, 0.54)))
	_box("WallEast", Vector3(32, 1.5, 0), Vector3(0.3, 3, 56), _material("panel", Color(0.5, 0.52, 0.54)))
	for x in [-23.0, 23.0]:
		for z in [-18.0, 5.0, 21.0]:
			var pole := _box("YardLampPole", Vector3(x, 2.5, z), Vector3(0.14, 5, 0.14), _plain(Color(0.12, 0.14, 0.16)))
			pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			_lamp(Vector3(x, 4.7, z), 13.0, 1.4, Color(0.55, 0.72, 1.0))


func _build_warehouse() -> void:
	var concrete := _material("concrete", Color(0.64, 0.66, 0.68))
	var panel := _material("panel", Color(0.7, 0.72, 0.74))
	_box("WarehouseFloor", Vector3(0, 0.05, -12), Vector3(26, 0.1, 18), concrete)
	_box("WarehouseBack", Vector3(0, 3.5, -21), Vector3(26, 7, 0.35), concrete)
	_box("WarehouseWest", Vector3(-13, 3.5, -12), Vector3(0.35, 7, 18), concrete)
	_box("WarehouseEast", Vector3(13, 3.5, -12), Vector3(0.35, 7, 18), concrete)
	_box("WarehouseFrontWest", Vector3(-8, 3.5, -3), Vector3(10, 7, 0.35), panel)
	_box("WarehouseFrontEast", Vector3(8, 3.5, -3), Vector3(10, 7, 0.35), panel)
	_box("WarehouseDoorHeader", Vector3(0, 5.8, -3), Vector3(6, 2.4, 0.35), panel)
	_box("WarehouseRoof", Vector3(0, 7.1, -12), Vector3(27, 0.25, 19), _plain(Color(0.16, 0.19, 0.22), 0.72))
	_quad("WarehouseWindowBand", Vector3(0, 4.5, -2.8), Vector2(21.5, 2.0), "windows")
	_quad("CargoDoorOpen", Vector3(0, 4.05, -2.79), Vector2(6, 0.9), "gate")
	_quad("WarehouseWindowsWest", Vector3(-13.2, 4.5, -12), Vector2(15, 2.0), "windows", -90.0)
	_quad("WarehouseWindowsEast", Vector3(13.2, 4.5, -12), Vector2(15, 2.0), "windows", 90.0)
	_label("WarehouseSign", "EDAA 转运仓库", Vector3(0, 6.35, -2.75), 48)
	for x in [-8.0, 0.0, 8.0]:
		_box("WarehouseColumn", Vector3(x, 3.0, -12), Vector3(0.45, 6, 0.45), concrete)
	for item in [[-9.0, -17.5], [-6.5, -17.5], [7.5, -16.0], [9.0, -8.0], [-9.0, -7.0]]:
		_box("CargoCrate", Vector3(item[0], 0.75, item[1]), Vector3(1.5, 1.5, 1.5), _plain(Color(0.32, 0.27, 0.2)))
	for x in [-7.0, 7.0]:
		_lamp(Vector3(x, 5.5, -12), 12.0, 1.8, Color(0.65, 0.82, 1.0))
	_lamp(Vector3(0, 5.0, -1), 13.0, 1.6, Color(0.55, 0.72, 1.0))


func _build_apc_bay() -> void:
	if ResourceLoader.exists(APC_MODEL):
		var apc := (load(APC_MODEL) as PackedScene).instantiate() as Node3D
		apc.name = "JB02APC"
		apc.position = Vector3(0, 0, 9.2)
		add_child(apc)
	else:
		push_warning("district_b: JB-02 GLB is not installed yet")
	_box("APCFrontCollision", Vector3(0, 1.4, 8.4), Vector3(3.5, 2.8, 4.8), _plain(Color(0.12, 0.14, 0.16)), false)
	var dark := _plain(Color(0.035, 0.045, 0.055), 0.78)
	var frame := _plain(Color(0.12, 0.16, 0.19), 0.6)
	_box("CargoFloor", Vector3(0, 0.58, 11.25), Vector3(3.1, 0.14, 2.4), dark)
	_box("CargoBack", Vector3(0, 1.55, 10.1), Vector3(3.1, 2.1, 0.12), dark)
	_box("CargoWest", Vector3(-1.55, 1.55, 11.25), Vector3(0.14, 2.1, 2.4), frame)
	_box("CargoEast", Vector3(1.55, 1.55, 11.25), Vector3(0.14, 2.1, 2.4), frame)
	_box("CargoRoof", Vector3(0, 2.55, 11.25), Vector3(3.2, 0.14, 2.4), frame)
	var ramp := _box("CargoRamp", Vector3(0, 0.292, 13.5), Vector3(3.1, 0.12, 2.1), frame)
	(ramp.get_parent() as Node3D).rotation_degrees.x = 16.0
	_label("EquipmentSign", "雷暴装备领取", Vector3(0, 2.48, 12.52), 40)
	_lamp(Vector3(0, 2.0, 11.7), 4.5, 1.3, Color(0.3, 0.85, 1.0))
	_build_apc_interior(dark, frame)
	_spawn_equipment(&"dmr", Vector3(-0.65, 1.1, 11.65))
	_spawn_equipment(&"shotgun", Vector3(0.65, 1.1, 11.65))


func _build_apc_interior(dark: StandardMaterial3D, frame: StandardMaterial3D) -> void:
	dark.metallic = 0.45
	frame.metallic = 0.6
	frame.roughness = 0.42
	var cushion := _plain(Color(0.075, 0.115, 0.12), 0.88)
	var belt := _plain(Color(0.28, 0.31, 0.29), 0.82)
	var screen := _emissive(Color(0.025, 0.32, 0.42), 0.85)
	var light_strip := _emissive(Color(0.32, 0.78, 0.92), 1.4)
	var warning := _emissive(Color(0.95, 0.52, 0.12), 0.7)
	for side: float in [-1.0, 1.0]:
		var side_name := "L" if side < 0.0 else "R"
		for row in 3:
			var z := 10.65 + row * 0.7
			var nm := "APCSeat_%s%d" % [side_name, row]
			_box(nm, Vector3(side * 1.18, 0.85, z), Vector3(0.5, 0.16, 0.62), frame)
			_detail_box(nm + "Pedestal", Vector3(side * 1.23, 0.71, z), Vector3(0.3, 0.16, 0.42), dark)
			_detail_box(nm + "Cushion", Vector3(side * 1.16, 0.96, z), Vector3(0.5, 0.12, 0.6), cushion)
			_detail_box(nm + "Back", Vector3(side * 1.43, 1.31, z), Vector3(0.14, 0.66, 0.6), cushion)
			_detail_box(nm + "Headrest", Vector3(side * 1.4, 1.7, z), Vector3(0.18, 0.18, 0.46), cushion)
			_detail_box(nm + "Belt", Vector3(side * 1.35, 1.31, z), Vector3(0.025, 0.55, 0.055), belt)
			_detail_box(nm + "Buckle", Vector3(side * 1.13, 1.03, z), Vector3(0.12, 0.025, 0.09), frame)
		for z in [10.75, 11.55]:
			_detail_box("APCEquipmentPanel", Vector3(side * 1.46, 1.93, z), Vector3(0.08, 0.22, 0.54), dark)
			_detail_box("APCPanelStatus", Vector3(side * 1.41, 1.95, z - 0.15), Vector3(0.02, 0.045, 0.12), warning)
			_detail_box("APCPanelVent", Vector3(side * 1.41, 1.91, z + 0.1), Vector3(0.02, 0.08, 0.2), frame)
		_detail_box("APCUpperConduit", Vector3(side * 1.4, 2.03, 11.25), Vector3(0.08, 0.08, 2.15), dark)
	for row in 3:
		var z := 10.65 + row * 0.7
		_detail_box("APCFloorPlate", Vector3(0, 0.665, z), Vector3(1.7, 0.025, 0.6), frame)
		for stripe in 5:
			_detail_box("APCFloorGrip", Vector3(-0.6 + stripe * 0.3, 0.682, z), Vector3(0.035, 0.012, 0.48), dark)
	for z in [10.4, 11.25, 12.1]:
		_detail_box("APCRoofRib", Vector3(0, 2.09, z), Vector3(3.0, 0.08, 0.09), dark)
		_detail_box("APCRoofLight", Vector3(0, 2.035, z), Vector3(1.15, 0.025, 0.075), light_strip)
	_detail_box("APCC4I", Vector3(0, 1.46, 10.2), Vector3(1.38, 0.68, 0.14), frame)
	for side: float in [-1.0, 1.0]:
		_detail_box("APCC4IScreen", Vector3(side * 0.34, 1.5, 10.285), Vector3(0.56, 0.36, 0.025), screen)
		_detail_box("APCC4IKeys", Vector3(side * 0.34, 1.23, 10.285), Vector3(0.48, 0.055, 0.025), dark)
	_label("APCC4ILeftText", "C4I\nONLINE", Vector3(-0.34, 1.51, 10.305), 18)
	_label("APCC4IRightText", "TROOP\n06", Vector3(0.34, 1.51, 10.305), 18)
	_label("APCC4IHeader", "JB-02  //  EDAA", Vector3(0, 1.77, 10.29), 16)
	for side: float in [-1.0, 1.0]:
		var x := side * 0.66
		for y in [0.95, 1.65]:
			_detail_box("APCWeaponRail", Vector3(x, y, 12.22), Vector3(0.74, 0.055, 0.055), frame)
		for clamp_x in [-0.25, 0.25]:
			_detail_box("APCWeaponClamp", Vector3(x + clamp_x, 1.3, 12.25), Vector3(0.06, 0.5, 0.06), frame)
	_lamp(Vector3(0, 1.94, 10.65), 2.2, 0.45, Color(0.36, 0.72, 0.9))
	_lamp(Vector3(0, 1.94, 11.95), 2.2, 0.45, Color(0.36, 0.72, 0.9))


func _spawn_equipment(kind: StringName, pos: Vector3) -> void:
	var pickup := PICKUP_SCENE.instantiate() as Node3D
	pickup.name = "Equipment_%s" % kind
	pickup.position = pos
	pickup.set(&"kind", kind)
	add_child(pickup)


func _build_return_link() -> void:
	_box("ReturnPostWest", Vector3(-1.2, 1.2, 25.5), Vector3(0.16, 2.4, 0.16), _plain(Color(0.1, 0.12, 0.14)))
	_box("ReturnPostEast", Vector3(1.2, 1.2, 25.5), Vector3(0.16, 2.4, 0.16), _plain(Color(0.1, 0.12, 0.14)))
	var link := Node3D.new()
	link.name = "Link_DistrictBReturn"
	link.set_script(SCENE_GATE)
	link.position = Vector3(0, 0, 25.0)
	var area := Area3D.new()
	area.name = "TriggerArea"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 2.5, 1.2)
	shape.shape = box
	area.add_child(shape)
	link.add_child(area)
	link.set("target_scene", "res://scenes/levels/street_playable.tscn")
	link.set("target_anchor", "street_bgate")
	link.set("anchor_id", "district_b_return")
	link.set("spawn_offset", Vector3(0, 0.2, -1.5))
	add_child(link)


func _world_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.018, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.27, 0.34)
	env.ambient_light_energy = 1.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.035, 0.045, 0.065)
	env.fog_density = 0.006
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-55, -30, 0)
	moon.light_color = Color(0.62, 0.76, 1.0)
	moon.light_energy = 1.1
	add_child(moon)


func _material(key: String, fallback: Color) -> StandardMaterial3D:
	var mat := _plain(fallback)
	var path: String = TEXTURES[key]
	if ResourceLoader.exists(path):
		mat.albedo_texture = load(path)
	return mat


func _plain(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var mat := _plain(color * 0.18, 0.5)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


func _box(nm: String, center: Vector3, size: Vector3, mat: Material, visual: bool = true) -> MeshInstance3D:
	var body := StaticBody3D.new()
	body.name = nm
	body.position = center
	add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	mi.visible = visual
	body.add_child(mi)
	return mi


func _detail_box(nm: String, center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	mi.position = center
	add_child(mi)
	return mi


func _quad(nm: String, pos: Vector3, size: Vector2, texture_key: String, yaw: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var mesh := QuadMesh.new()
	mesh.size = size
	mesh.material = _material(texture_key, Color.WHITE)
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees.y = yaw
	add_child(mi)


func _label(nm: String, text: String, pos: Vector3, font_size: int) -> void:
	var label := Label3D.new()
	label.name = nm
	label.text = text
	label.font_size = font_size
	label.outline_size = 8
	label.modulate = Color(0.55, 0.85, 1.0)
	label.position = pos
	add_child(label)


func _lamp(pos: Vector3, range: float, energy: float, color: Color) -> void:
	var lamp := OmniLight3D.new()
	lamp.position = pos
	lamp.omni_range = range
	lamp.light_energy = energy
	lamp.light_color = color
	add_child(lamp)
