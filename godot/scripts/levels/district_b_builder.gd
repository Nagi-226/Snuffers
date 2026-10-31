extends Node3D

const SCENE_GATE := preload("res://scripts/levels/scene_link.gd")
const PICKUP_SCENE := preload("res://scenes/levels/pickup.tscn")
const LORE_NOTE := preload("res://scripts/levels/lore_note.gd")
const APC_MODEL := "res://assets/models/vehicles/jb02_apc.glb"
const SPAS_MODEL := "res://assets/models/weapons/spas12_display.glb"
const HULKING_SCENE := preload("res://scenes/enemies/hulking_host.tscn")
const INFANTRY_SCENE := preload("res://scenes/enemies/infantry.tscn")
const SPORE_SCENE := preload("res://scenes/enemies/spore_husk.tscn")
const TEXTURES := {
	"concrete": "res://assets/textures/warehouse/wall_concrete.bmp",
	"panel": "res://assets/textures/warehouse/facade_panel.bmp",
	"windows": "res://assets/textures/warehouse/facade_windows.bmp",
	"gate": "res://assets/textures/warehouse/gate_cargo_open.bmp",
}


func _ready() -> void:
	($Player as CharacterBody3D).set("world_bounds", GameConfig.DISTRICT_B_WORLD_BOUNDS)
	_world_env()
	_build_yard()
	_build_warehouse()
	_build_prequel_lore()
	_spawn_district_enemies()
	_build_apc_bay()
	_build_return_link()


func _build_yard() -> void:
	_box("Ground", Vector3(0, -0.15, 0), Vector3(460, 0.3, 320), _material("concrete", Color(0.32, 0.34, 0.36)))
	_box("WallNorth", Vector3(0, 1.5, -159), Vector3(460, 3, 0.3), _material("panel", Color(0.5, 0.52, 0.54)))
	_box("WallSouthWest", Vector3(-116, 1.5, 159), Vector3(228, 3, 0.3), _material("panel", Color(0.5, 0.52, 0.54)))
	_box("WallSouthEast", Vector3(116, 1.5, 159), Vector3(228, 3, 0.3), _material("panel", Color(0.5, 0.52, 0.54)))
	_box("WallWest", Vector3(-229, 1.5, 0), Vector3(0.3, 3, 318), _material("panel", Color(0.5, 0.52, 0.54)))
	_box("WallEast", Vector3(229, 1.5, 0), Vector3(0.3, 3, 318), _material("panel", Color(0.5, 0.52, 0.54)))
	for x in [-205.0, 205.0]:
		for z in [-135.0, -45.0, 45.0, 135.0]:
			var pole := _box("YardLampPole", Vector3(x, 4.5, z), Vector3(0.22, 9, 0.22), _plain(Color(0.12, 0.14, 0.16)))
			pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			_lamp(Vector3(x, 8.7, z), 34.0, 2.0, Color(0.55, 0.72, 1.0))
	_build_legacy_landmarks()


func _build_warehouse() -> void:
	var concrete := _pbr_material("concrete_floor_02", Color(0.68, 0.72, 0.76), Vector3(10, 4, 1))
	var panel := _pbr_material("corrugated_iron", Color(0.64, 0.7, 0.74), Vector3(10, 3, 1))
	var steel := _plain(Color(0.16, 0.19, 0.22), 0.72)
	_box("WarehouseFloor", Vector3(0, 0.05, -20), Vector3(350, 0.1, 200), concrete)
	_box("WarehouseBack", Vector3(0, 11, -120), Vector3(350, 22, 0.5), concrete)
	_box("WarehouseWest", Vector3(-175, 11, -20), Vector3(0.5, 22, 200), concrete)
	_box("WarehouseEast", Vector3(175, 11, -20), Vector3(0.5, 22, 200), concrete)
	_box("WarehouseRoof", Vector3(0, 22.15, -20), Vector3(351, 0.35, 201), steel)
	var piers := [[-151.0, 48.0], [-80.0, 66.0], [0.0, 66.0], [80.0, 66.0], [151.0, 48.0]]
	for i in piers.size():
		var pier: Array = piers[i]
		_box("WarehouseFrontPier_%d" % i, Vector3(pier[0], 11, 80), Vector3(pier[1], 22, 0.5), panel)
		_quad("WarehouseWindowBand_%d" % i, Vector3(pier[0], 16.5, 80.28), Vector2(pier[1] - 4.0, 3.0), "windows")
	var door_x := [-120.0, -40.0, 40.0, 120.0]
	for i in door_x.size():
		var x: float = door_x[i]
		_box("CargoDoorHeader_%d" % i, Vector3(x, 15.5, 80), Vector3(14, 13, 0.5), panel)
		_quad("CargoDoorOpen_%d" % i, Vector3(x, 8.2, 80.28), Vector2(14, 1.2), "gate")
		_screen("CargoDoorLabel_%d" % i, "货运通道 %02d" % [i + 1], Vector3(x, 10.2, 80.32), 54)
		_lamp(Vector3(x, 8.5, 77), 24.0, 2.2, Color(0.55, 0.72, 1.0))
	_screen("WarehouseSign", "EDAA 转运仓库", Vector3(0, 20.0, 80.32), 96)
	for z in [-95.0, -55.0, -15.0, 25.0, 65.0]:
		_quad("WarehouseWindowsWest", Vector3(-175.28, 16.5, z), Vector2(28, 3.0), "windows", -90.0)
		_quad("WarehouseWindowsEast", Vector3(175.28, 16.5, z), Vector2(28, 3.0), "windows", 90.0)
	for x in [-140.0, -105.0, -70.0, -35.0, 0.0, 35.0, 70.0, 105.0, 140.0]:
		for z in [-90.0, -50.0, -10.0, 30.0]:
			_box("WarehouseColumn", Vector3(x, 10.5, z), Vector3(0.8, 21, 0.8), concrete)
			_detail_box("ColumnBase", Vector3(x, 0.35, z), Vector3(1.5, 0.7, 1.5), steel)
		_detail_box("RoofBeamLongitudinal", Vector3(x, 20.8, -20), Vector3(0.35, 0.45, 199), steel)
	for z in [-100.0, -60.0, -20.0, 20.0, 60.0]:
		_detail_box("RoofTruss", Vector3(0, 20.2, z), Vector3(349, 0.55, 0.55), steel)
		for x in [-120.0, -40.0, 40.0, 120.0]:
			_lamp(Vector3(x, 18.5, z), 38.0, 2.4, Color(0.65, 0.82, 1.0))
	_build_storage_racks()
	_build_mezzanine()
	_build_warehouse_rooms()


func _build_storage_racks() -> void:
	var rack_mat := _plain(Color(0.18, 0.27, 0.31), 0.58)
	var shelf_mat := _plain(Color(0.38, 0.31, 0.2), 0.82)
	var crate_mat := _material("panel", Color(0.4, 0.36, 0.28))
	var uprights: Array[Vector3] = []
	var shelves: Array[Vector3] = []
	var crates: Array[Vector3] = []
	for x in [-140.0, -105.0, -70.0, -35.0, 35.0, 70.0, 105.0, 140.0]:
		for z in [-90.0, -55.0, -20.0, 15.0, 50.0]:
			if x < -95.0 and z < -45.0:
				continue
			_box("StorageRackCollision", Vector3(x, 2.75, z), Vector3(18, 5.5, 2.4), rack_mat, false)
			for dx in [-8.85, 8.85]:
				for dz in [-1.1, 1.1]:
					uprights.append(Vector3(x + dx, 2.75, z + dz))
			for y in [0.35, 1.65, 2.95, 4.25, 5.55]:
				shelves.append(Vector3(x, y, z))
			for dx in [-6.0, 0.0, 6.0]:
				for y in [1.0, 2.3, 3.6]:
					crates.append(Vector3(x + dx, y, z))
	_multi_boxes("RackUprights", Vector3(0.16, 5.5, 0.16), uprights, rack_mat)
	_multi_boxes("RackShelves", Vector3(18, 0.14, 2.4), shelves, shelf_mat)
	_multi_boxes("RackCrates", Vector3(3.6, 1.05, 1.8), crates, crate_mat)


func _build_mezzanine() -> void:
	var steel := _plain(Color(0.18, 0.22, 0.25), 0.68)
	_box("MezzanineFloor", Vector3(-135, 5.825, -95), Vector3(60, 0.35, 30), steel)
	for x in [-160.0, -135.0, -110.0]:
		_box("MezzanineSupport", Vector3(x, 2.9, -82), Vector3(0.45, 5.8, 0.45), steel)
	_detail_box("MezzanineRailWest", Vector3(-164.7, 6.8, -95), Vector3(0.12, 1.5, 29), steel)
	_detail_box("MezzanineRailFrontA", Vector3(-139.5, 6.8, -80.2), Vector3(50, 1.5, 0.12), steel)
	_detail_box("MezzanineRailFrontB", Vector3(-106.0, 6.8, -80.2), Vector3(2, 1.5, 0.12), steel)
	var steps := 24
	for i in steps:
		var height := 6.0 * float(i + 1) / steps
		var z := -52.0 - 28.0 * (float(i) + 0.5) / steps
		_detail_box("MezzanineStairStep", Vector3(-110, height * 0.5, z), Vector3(4, height, 28.0 / steps), steel)
	_stair_ramp(Vector3(-110, 0, -52), Vector3(-110, 6, -80), 4.0, steel)


func _build_warehouse_rooms() -> void:
	var concrete := _pbr_material("concrete_floor_02", Color(0.62, 0.67, 0.71), Vector3(4, 2, 1))
	var metal := _plain(Color(0.16, 0.22, 0.25), 0.65)
	_box("PartitionWestA", Vector3(-20, 2.75, 10), Vector3(0.35, 5.5, 50), concrete)
	_box("PartitionWestB", Vector3(-20, 2.75, -45), Vector3(0.35, 5.5, 30), concrete)
	_box("PartitionWestC", Vector3(-20, 2.75, 45), Vector3(0.35, 5.5, 10), concrete)
	_box("PartitionEastA", Vector3(55, 2.75, 10), Vector3(0.35, 5.5, 50), concrete)
	_box("PartitionEastB", Vector3(55, 2.75, -50), Vector3(0.35, 5.5, 40), concrete)
	_box("PartitionEastC", Vector3(55, 2.75, 50), Vector3(0.35, 5.5, 20), concrete)
	for wall in [[-130.0, 90.0], [-45.0, 50.0], [25.0, 60.0], [120.0, 110.0]]:
		_box("CrossStoreWall", Vector3(wall[0], 2.75, 40), Vector3(wall[1], 5.5, 0.35), concrete)
	_box("ReceivingOffice", Vector3(-150, 2.75, 45), Vector3(30, 5.5, 0.35), concrete)
	_box("OfficeWest", Vector3(-165, 2.75, 57.5), Vector3(0.35, 5.5, 25), concrete)
	_box("OfficeEastNorth", Vector3(-135, 2.75, 48.5), Vector3(0.35, 5.5, 7), concrete)
	_box("OfficeEastSouth", Vector3(-135, 2.75, 66.5), Vector3(0.35, 5.5, 7), concrete)
	_box("OfficeFront", Vector3(-150, 2.75, 70), Vector3(30, 5.5, 0.35), concrete)
	_box("OfficeDesk", Vector3(-151, 0.5, 54), Vector3(3.2, 1.0, 1.2), metal)
	_detail_box("OfficeTerminal", Vector3(-151, 1.15, 54), Vector3(0.75, 0.5, 0.08), _emissive(Color(0.2, 0.65, 0.8), 0.65))
	_screen("OfficeSign", "收货登记 / RECEIVING", Vector3(-150, 3.9, 69.75), 36)
	_lamp(Vector3(-150, 4.2, 56), 14, 1.8, Color(0.55, 0.78, 1.0))
	for x in [-20.0, 55.0]:
		for z in [-30.0, 37.5]:
			_detail_box("PartitionDoorFrame", Vector3(x, 2.2, z), Vector3(0.55, 4.4, 0.55), metal)
			_lamp(Vector3(x, 4.4, z), 10, 1.2, Color(0.4, 0.75, 1.0))
	for z in [60.0, 20.0, -20.0, -60.0]:
		_detail_box("CargoLaneMarking", Vector3(0, 0.115, z), Vector3(0.18, 0.015, 18), _plain(Color(0.72, 0.58, 0.12), 0.8))
		_screen("RouteSign", "收货 → 复检 → 储运", Vector3(-19.75, 3.3, z), 28, 90.0)
	var pallet_positions := [Vector3(-160, 0, 25), Vector3(-155, 0, -15), Vector3(-90, 0, 55), Vector3(75, 0, 55), Vector3(145, 0, 15), Vector3(115, 0, -85)]
	for i in pallet_positions.size():
		_prop_model("res://assets/models/prop_pallet.glb", "CargoPallet_%d" % i, pallet_positions[i], 1.8, i * 0.35)
		_detail_box("PalletCargo", pallet_positions[i] + Vector3(0, 1.0, 0), Vector3(2.2, 1.4, 1.5), _material("panel", Color(0.36, 0.3, 0.22)))
	for i in 6:
		_prop_model("res://assets/models/prop_barrel.glb", "CargoBarrel_%d" % i, Vector3(82 + (i % 3) * 1.2, 0, -65 + int(i / 3) * 1.2), 1.4, i * 0.4)
	for i in 8:
		_prop_model("res://assets/models/prop_cone.glb", "SafetyCone_%d" % i, Vector3(-7 + (i % 2) * 14, 0, 65 - int(i / 2) * 22), 1.2, 0.0)
	for i in 4:
		_prop_model("res://assets/models/prop_toolbox.glb", "MaintenanceToolbox_%d" % i, Vector3(-45 + i * 30, 0, 32), 1.2, i * 0.3)


func _prop_model(path: String, nm: String, pos: Vector3, model_scale: float, yaw: float) -> void:
	if not ResourceLoader.exists(path):
		return
	var model := (load(path) as PackedScene).instantiate() as Node3D
	model.name = nm
	model.position = pos
	model.rotation.y = yaw
	model.scale = Vector3.ONE * model_scale
	add_child(model)


func _build_prequel_lore() -> void:
	var metal := _plain(Color(0.12, 0.17, 0.19), 0.62)
	var cyan := _emissive(Color(0.3, 0.82, 0.92), 1.2)
	_detail_box("ReconPlate", Vector3(-49, 1.45, 80.42), Vector3(0.9, 0.55, 0.06), metal)
	for i in 3:
		_detail_box("ReconMark", Vector3(-49.25 + i * 0.16, 1.55, 80.47), Vector3(0.045, 0.3, 0.025), cyan)
	_screen("ReconText", "提灯 / 已查", Vector3(-48.85, 1.25, 80.48), 24)
	_lore_node(&"LanternReconMarker", Vector3(-49, 0, 80.4), "提灯的侦察标记",
		"转运记录已回传。东侧撤离信标确认——提灯。", "E  查看侦察标记")
	_detail_box("SurveyStand", Vector3(-135, 6.45, -95), Vector3(0.7, 0.9, 0.7), metal)
	_cylinder("SurveyBeacon", Vector3(-135, 7.05, -95), 0.16, 0.32, cyan)
	_detail_box("SurveyMap", Vector3(-134.55, 6.94, -94.8), Vector3(0.65, 0.025, 0.45), _plain(Color(0.65, 0.65, 0.56)))
	_screen("SurveyText", "提灯 / 勘测灯标", Vector3(-135, 6.65, -94.6), 22)
	_lamp(Vector3(-135, 7.25, -95), 4.0, 0.8, Color(0.3, 0.85, 1.0))
	_lore_node(&"LanternSurveyBeacon", Vector3(-135, 6, -95), "提灯留下的勘测灯标",
		"灯还亮着。剩下的，交给雷暴。", "E  查看勘测灯标")
	if ResourceLoader.exists(SPAS_MODEL):
		var spas := (load(SPAS_MODEL) as PackedScene).instantiate() as Node3D
		spas.name = "WickSPAS12"
		spas.position = Vector3(-38, 1.82, 50.65)
		spas.rotation.y = PI * 0.5 + 0.2
		spas.scale = Vector3.ONE * 0.12
		add_child(spas)
	_detail_box("WickAmmoBox", Vector3(-36.6, 1.82, 50.65), Vector3(0.5, 0.3, 0.34), _plain(Color(0.42, 0.32, 0.18), 0.92))
	_detail_box("WickAmmoBoxLid", Vector3(-36.6, 1.98, 50.65), Vector3(0.52, 0.035, 0.36), _plain(Color(0.28, 0.22, 0.13), 0.9))
	_screen("WickAmmoLabel", "12 GAUGE\n25 SHELLS", Vector3(-36.6, 1.82, 50.84), 12)
	for i in 4:
		_cylinder("WickShell", Vector3(-36.1 + i * 0.11, 1.7, 50.7), 0.025, 0.16, _plain(Color(0.45, 0.16, 0.1), 0.5))
	_detail_box("WickIdentityTag", Vector3(-39.1, 1.68, 50.75), Vector3(0.32, 0.025, 0.2), metal)
	_screen("WickText", "灯芯 / 遗物", Vector3(-37.5, 2.4, 50.9), 26)
	_lore_node(&"WickMemento", Vector3(-37.5, 0.65, 51.45), "灯芯的遗物",
		"先一步进入的灯芯已失联，只留下老式 SPAS-12 和几枚霰弹。它不是提灯的装备。", "E  查看灯芯遗物")


func _lore_node(nm: StringName, pos: Vector3, title: String, body: String, prompt: String) -> void:
	var lore := Node3D.new()
	lore.name = nm
	lore.position = pos
	lore.set_script(LORE_NOTE)
	lore.set("title", title)
	lore.set("body", body)
	lore.set("prompt", prompt)
	var body_shape := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 2.0, 0.8)
	collision.shape = box
	collision.position.y = 1.0
	body_shape.add_child(collision)
	lore.add_child(body_shape)
	add_child(lore)


func _build_legacy_landmarks() -> void:
	var steel := _plain(Color(0.22, 0.26, 0.29), 0.72)
	var concrete := _material("concrete", Color(0.5, 0.52, 0.54))
	var tower := Node3D.new()
	tower.name = "WaterTower"
	tower.position = Vector3(205, 0, 10)
	add_child(tower)
	for dx in [-2.0, 2.0]:
		for dz in [-2.0, 2.0]:
			_detail_box("WaterTowerLeg", Vector3(205 + dx, 6, 10 + dz), Vector3(0.45, 12, 0.45), steel)
	_box("WaterTowerPlatform", Vector3(205, 12, 10), Vector3(6, 0.4, 6), steel)
	_cylinder("WaterTowerTank", Vector3(205, 15.5, 10), 5.0, 6.5, concrete)
	_screen("WaterTowerLabel", "小区水塔", Vector3(205, 12.8, 15.1), 44)
	var cabin := Node3D.new()
	cabin.name = "LegacyCabin"
	cabin.position = Vector3(-205, 0, 10)
	add_child(cabin)
	_box("CabinBack", Vector3(-205, 2.25, 5), Vector3(8, 4.5, 0.3), concrete)
	_box("CabinWest", Vector3(-209, 2.25, 10), Vector3(0.3, 4.5, 10), concrete)
	_box("CabinEast", Vector3(-201, 2.25, 10), Vector3(0.3, 4.5, 10), concrete)
	_box("CabinFrontLeft", Vector3(-207.5, 2.25, 15), Vector3(3, 4.5, 0.3), concrete)
	_box("CabinFrontRight", Vector3(-202.5, 2.25, 15), Vector3(3, 4.5, 0.3), concrete)
	_box("CabinRoof", Vector3(-205, 4.65, 10), Vector3(8.6, 0.3, 10.6), steel)
	var bunker := Node3D.new()
	bunker.name = "LegacyBunker"
	bunker.position = Vector3(-195, 0, 130)
	add_child(bunker)
	_box("BunkerCollision", Vector3(-195, 1.5, 130), Vector3(11, 3, 11), concrete, false)
	_cylinder("BunkerWall", Vector3(-195, 1.5, 130), 6.2, 3.0, concrete)
	_cylinder("BunkerRoof", Vector3(-195, 3.1, 130), 6.4, 0.25, steel)
	for i in 8:
		var angle := TAU * float(i) / 8.0
		_box("BunkerSandbag", Vector3(-195 + cos(angle) * 8.0, 0.45, 130 + sin(angle) * 8.0), Vector3(2.4, 0.9, 0.8), _plain(Color(0.38, 0.34, 0.25)))


func _multi_boxes(nm: String, size: Vector3, positions: Array[Vector3], mat: Material) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	multi.mesh = mesh
	multi.instance_count = positions.size()
	for i in positions.size():
		multi.set_instance_transform(i, Transform3D(Basis.IDENTITY, positions[i]))
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = multi
	add_child(mi)


func _cylinder(nm: String, center: Vector3, radius: float, height: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.material = mat
	mi.mesh = mesh
	mi.position = center
	add_child(mi)


func _stair_ramp(low: Vector3, high: Vector3, width: float, mat: Material) -> void:
	var forward := (high - low).normalized()
	var flat := Vector3(forward.x, 0, forward.z).normalized()
	var side := flat.cross(Vector3.UP)
	var up := side.cross(forward)
	var body := StaticBody3D.new()
	body.name = "MezzanineStairRamp"
	body.transform = Transform3D(Basis(forward, up, side), (low + high) * 0.5 - up * 0.1)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(low.distance_to(high), 0.2, width)
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	var stringer := _detail_box("MezzanineStairStringer", Vector3.ZERO, Vector3(low.distance_to(high), 0.15, 0.15), mat)
	stringer.transform = Transform3D(Basis(forward, up, side), (low + high) * 0.5 - up * 0.3)


func _spawn_district_enemies() -> void:
	var host_zones := [
		Vector3(-55, 0, 58), Vector3(20, 0, 58), Vector3(-50, 0, 5),
		Vector3(20, 0, -5), Vector3(90, 0, -40), Vector3(-55, 0, -75),
		Vector3(120, 0, 45), Vector3(-125, 0, 45), Vector3(105, 0, -85), Vector3(-110, 0, -15),
	]
	var host_offsets := [Vector3(-2, 0, -2), Vector3(2, 0, 0), Vector3(0, 0, 2)]
	var index := 0
	for zone in host_zones:
		for offset in host_offsets:
			var host := INFANTRY_SCENE.instantiate() as Node3D
			host.name = "HostParasite_%d" % index
			host.position = zone + offset
			add_child(host)
			index += 1
	var spore_zones := [
		Vector3(-10, 0, 60), Vector3(10, 0, 25), Vector3(-45, 0, -35), Vector3(75, 0, -70),
		Vector3(-120, 0, 60), Vector3(125, 0, 60), Vector3(-90, 0, -10), Vector3(115, 0, -15),
	]
	var spore_offsets := [Vector3.ZERO, Vector3(1.5, 0, 1.5), Vector3(-1.5, 0, -1.5)]
	index = 0
	for zone in spore_zones:
		for offset in spore_offsets:
			var spore := SPORE_SCENE.instantiate() as Node3D
			spore.name = "SporeHusk_%d" % index
			spore.position = zone + offset
			add_child(spore)
			index += 1
	var hulk_positions := [
		Vector3(0, 0, 20), Vector3(-70, 0, 35), Vector3(65, 0, 30),
		Vector3(-115, 0, 0), Vector3(115, 0, 0), Vector3(-55, 0, -55),
		Vector3(45, 0, -65), Vector3(135, 0, -45), Vector3(-135, 0, -45), Vector3(0, 0, -95),
	]
	for i in hulk_positions.size():
		var hulking := HULKING_SCENE.instantiate() as Node3D
		hulking.name = "HulkingHost" if i == 0 else "HulkingHost_%d" % i
		hulking.position = hulk_positions[i]
		add_child(hulking)


func _build_apc_bay() -> void:
	var first_child := get_child_count()
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
	_screen("EquipmentSign", "雷暴装备领取", Vector3(0, 2.48, 12.52), 40)
	_lamp(Vector3(0, 2.0, 11.7), 4.5, 1.3, Color(0.3, 0.85, 1.0))
	_build_apc_interior(dark, frame)
	_spawn_equipment(&"dmr", Vector3(-0.65, 1.1, 11.65))
	_spawn_equipment(&"shotgun", Vector3(0.65, 1.1, 11.65))
	for index in range(first_child, get_child_count()):
		var child := get_child(index) as Node3D
		child.position.z += 100.0


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
	_screen("APCC4ILeftText", "C4I\nONLINE", Vector3(-0.34, 1.51, 10.305), 18)
	_screen("APCC4IRightText", "TROOP\n06", Vector3(0.34, 1.51, 10.305), 18)
	_screen("APCC4IHeader", "JB-02  //  EDAA", Vector3(0, 1.77, 10.29), 16)
	_lamp(Vector3(0, 1.94, 10.65), 2.2, 0.45, Color(0.36, 0.72, 0.9))
	_lamp(Vector3(0, 1.94, 11.95), 2.2, 0.45, Color(0.36, 0.72, 0.9))


func _spawn_equipment(kind: StringName, pos: Vector3) -> void:
	var pickup := PICKUP_SCENE.instantiate() as Node3D
	pickup.name = "Equipment_%s" % kind
	pickup.position = pos
	pickup.set(&"kind", kind)
	add_child(pickup)


func _build_return_link() -> void:
	_box("ReturnPostWest", Vector3(-1.2, 1.2, 150.5), Vector3(0.16, 2.4, 0.16), _plain(Color(0.1, 0.12, 0.14)))
	_box("ReturnPostEast", Vector3(1.2, 1.2, 150.5), Vector3(0.16, 2.4, 0.16), _plain(Color(0.1, 0.12, 0.14)))
	var link := Node3D.new()
	link.name = "Link_DistrictBReturn"
	link.set_script(SCENE_GATE)
	link.position = Vector3(0, 0, 150.0)
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
	env.fog_density = 0.0018
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


func _pbr_material(kind: String, tint: Color, tiling: Vector3) -> StandardMaterial3D:
	var mat := _plain(tint, 1.0)
	var root := "res://assets/textures/warehouse/pbr/" + kind
	mat.albedo_texture = load(root + "_diff_2k.jpg")
	mat.normal_texture = load(root + "_nor_gl_2k.jpg")
	mat.roughness_texture = load(root + "_rough_2k.jpg")
	mat.uv1_scale = tiling
	mat.metallic = 0.55 if kind == "corrugated_iron" else 0.0
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


func _screen(nm: String, text: String, pos: Vector3, font_size: int, yaw: float = 0.0) -> void:
	var root := Node3D.new()
	root.name = nm
	root.position = pos
	root.rotation_degrees.y = yaw
	var panel := MeshInstance3D.new()
	panel.name = "Panel"
	var panel_mesh := BoxMesh.new()
	var width := maxf(1.2, font_size * 0.08)
	var height := maxf(0.45, font_size * 0.025 + 0.22)
	panel_mesh.size = Vector3(width, height, 0.08)
	panel_mesh.material = _plain(Color(0.025, 0.045, 0.055), 0.52)
	panel.mesh = panel_mesh
	root.add_child(panel)
	var label := Label3D.new()
	label.name = "Display"
	label.text = text
	label.font_size = font_size
	label.outline_size = 5
	label.modulate = Color(0.45, 0.85, 1.0)
	label.position.z = 0.055
	root.add_child(label)
	var status := MeshInstance3D.new()
	status.name = "StatusLight"
	var status_mesh := BoxMesh.new()
	status_mesh.size = Vector3(0.06, 0.06, 0.025)
	status_mesh.material = _emissive(Color(0.25, 0.9, 0.65), 1.0)
	status.mesh = status_mesh
	status.position = Vector3(-width * 0.5 + 0.1, -height * 0.5 + 0.1, 0.065)
	root.add_child(status)
	add_child(root)


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
