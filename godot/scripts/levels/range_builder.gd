extends Node3D

const TARGET_SCRIPT := preload("res://scripts/levels/range_target.gd")
const TARGET_SCENES: Dictionary = {
	&"infantry": preload("res://scenes/enemies/infantry.tscn"),
	&"machine_gunner": preload("res://scenes/enemies/machine_gunner.tscn"),
	&"sniper": preload("res://scenes/enemies/sniper.tscn"),
	&"bunker": preload("res://scenes/enemies/bunker_machine_gunner.tscn"),
	&"spore": preload("res://scenes/enemies/spore_husk.tscn"),
	&"hulking": preload("res://scenes/enemies/hulking_host.tscn"),
}

var _concrete: StandardMaterial3D
var _metal: StandardMaterial3D
var _accent: StandardMaterial3D
var _targets: Node3D


func _ready() -> void:
	for weapon_id in GameState.weapon_unlocked:
		GameState.weapon_unlocked[weapon_id] = true
	_concrete = _plain(Color(0.28, 0.32, 0.36))
	_metal = _plain(Color(0.16, 0.21, 0.25), 0.62)
	_accent = _emissive(Color(0.2, 0.72, 0.9), 0.8)
	_targets = _root("Targets")
	_build_maze()
	_build_near_overwatch()
	_build_sniper_access()
	_build_far_roosts()
	_build_targets()
	_build_signs()


func _build_maze() -> void:
	var maze := _root("IndoorMaze")
	_box(maze, "Floor", Vector3(45, 0.04, 35), Vector3(30, 0.08, 24), _concrete)
	_box(maze, "Roof", Vector3(45, 3.2, 35), Vector3(30.4, 0.25, 24.4), _metal)
	_box(maze, "West", Vector3(30, 1.6, 35), Vector3(0.3, 3.2, 24), _concrete)
	_box(maze, "East", Vector3(60, 1.6, 35), Vector3(0.3, 3.2, 24), _concrete)
	_box(maze, "NorthLeft", Vector3(36, 1.6, 23), Vector3(12, 3.2, 0.3), _concrete)
	_box(maze, "NorthRight", Vector3(53, 1.6, 23), Vector3(14, 3.2, 0.3), _concrete)
	_box(maze, "SouthLeft", Vector3(39.5, 1.6, 47), Vector3(19, 3.2, 0.3), _concrete)
	_box(maze, "SouthRight", Vector3(57, 1.6, 47), Vector3(6, 3.2, 0.3), _concrete)
	_box(maze, "TurnOne", Vector3(41, 1.6, 29), Vector3(22, 3.2, 0.25), _concrete)
	_box(maze, "TurnTwo", Vector3(49, 1.6, 35), Vector3(22, 3.2, 0.25), _concrete)
	_box(maze, "TurnThree", Vector3(41, 1.6, 41), Vector3(22, 3.2, 0.25), _concrete)
	_box(maze, "RoomA", Vector3(38, 1.6, 25.5), Vector3(0.25, 3.2, 5), _concrete)
	_box(maze, "RoomB", Vector3(52, 1.6, 37.5), Vector3(0.25, 3.2, 5), _concrete)
	_box(maze, "DoorHeaderNorth", Vector3(44, 2.85, 23), Vector3(4, 0.7, 0.35), _metal)
	_box(maze, "DoorHeaderSouth", Vector3(52, 2.85, 47), Vector3(4, 0.7, 0.35), _metal)
	for z in [26.0, 32.0, 38.0, 44.0]:
		_box(maze, "GuideLight", Vector3(45, 0.1, z), Vector3(0.18, 0.04, 1.1), _accent, false)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(45, 2.65, z)
		lamp.omni_range = 8.0
		lamp.light_energy = 0.8
		lamp.light_color = Color(0.45, 0.72, 1.0)
		maze.add_child(lamp)


func _build_near_overwatch() -> void:
	var deck := _root("NearOverwatch")
	_box(deck, "Platform", Vector3(30, 3.75, -25), Vector3(6, 0.5, 6), _metal)
	for x in [27.2, 32.8]:
		for z in [-27.8, -22.2]:
			_box(deck, "Support", Vector3(x, 1.75, z), Vector3(0.35, 3.5, 0.35), _metal)
		_box(deck, "SideRail", Vector3(x, 4.65, -25), Vector3(0.15, 1.3, 6), _metal)
	_box(deck, "NorthRail", Vector3(30, 4.25, -27.9), Vector3(6, 0.5, 0.15), _metal)
	_stairs(deck, "Access", Vector3(30, 0, -17), Vector3.FORWARD, 16, 0.35, 2.2)


func _build_sniper_access() -> void:
	var stairs := _root("SniperAccessStairs")
	_stairs(stairs, "Step", Vector3(80, 0, 18), Vector3.FORWARD, 48, 0.35, 2.0)
	_box(stairs, "Landing", Vector3(80, 11.85, 2.4), Vector3(3.4, 0.3, 2.4), _metal)


func _build_far_roosts() -> void:
	var roosts := _root("FarTargetRoosts")
	for z in [-45.0, 0.0, 45.0]:
		_box(roosts, "Roost", Vector3(-85, 10.75, z), Vector3(10, 0.5, 10), _metal)
		for x in [-89.5, -80.5]:
			for dz in [-4.5, 4.5]:
				_box(roosts, "RoostSupport", Vector3(x, 5.25, z + dz), Vector3(0.45, 10.5, 0.45), _metal)
		_box(roosts, "Backstop", Vector3(-89.8, 13, z), Vector3(0.35, 4, 10), _concrete)


func _build_targets() -> void:
	_target(&"infantry", "CloseTarget", Vector3(44, 0.1, 26), GameConfig.INFANTRY_HP, "近战靶 / 7m")
	_target(&"hulking", "MazeHeavyTarget", Vector3(56, 0.1, 32), GameConfig.HULKING_HOST_HP, "迷宫重装靶")
	_target(&"spore", "MazeSporeTarget", Vector3(34, 0.1, 38), GameConfig.SPORE_HUSK_HP, "迷宫孢子靶")
	_target(&"infantry", "MazeExitTarget", Vector3(56, 0.1, 44), GameConfig.INFANTRY_HP, "迷宫出口靶")
	_target(&"machine_gunner", "NearRangeTarget", Vector3(30, 0.1, -40), GameConfig.MG_HP, "近距靶 / 15m")
	_target(&"infantry", "MidRangeTarget", Vector3(60, 0.1, -45), GameConfig.INFANTRY_HP, "中距靶 / 52m")
	_target(&"spore", "MidSporeTarget", Vector3(80, 0.1, -48), GameConfig.SPORE_HUSK_HP, "中距孢子靶")
	_target(&"sniper", "FarSniperTarget", Vector3(-85, 11.05, -45), GameConfig.SNIPER_HP, "远距靶 / 172m", -PI * 0.5)
	_target(&"machine_gunner", "FarMachineTarget", Vector3(-85, 11.05, 0), GameConfig.MG_HP, "远距靶 / 165m", -PI * 0.5)
	_target(&"bunker", "FarBunkerTarget", Vector3(-85, 11.05, 45), GameConfig.MG_HP, "远距靶 / 172m", -PI * 0.5)


func _build_signs() -> void:
	_label(self, "RangeGuide", "综合武器靶场\n前方：室内近战 / 迷宫\n北侧：近距高台与远程狙击", Vector3(40, 2.4, 23.1), 34)
	_label(self, "NearGuide", "近距高台 / 4m\n15–55m 靶区", Vector3(30, 6.4, -25), 42)
	_label(self, "SniperGuide", "远程狙击塔 / 12m\n165–172m 高台靶", Vector3(80, 14.5, 0), 46)
	for z in [-45.0, 0.0, 45.0]:
		_label(self, "FarGuide", "远距 NPC 靶\n安全测试 / 不反击", Vector3(-85, 14.8, z), 46)


func _target(kind: StringName, nm: String, pos: Vector3, hp: float, caption: String, yaw: float = 0.0) -> void:
	var scene: PackedScene = TARGET_SCENES[kind]
	var target := scene.instantiate() as CharacterBody3D
	target.set_script(TARGET_SCRIPT)
	target.set("target_health", hp)
	target.name = nm
	target.position = pos
	target.rotation.y = yaw
	target.set_meta("range_caption", caption)
	_targets.add_child(target)
	_label(_targets, nm + "Label", caption, pos + Vector3(0, 2.6, 0), 34)


func _stairs(parent: Node3D, prefix: String, start: Vector3, direction: Vector3, count: int, depth: float, width: float) -> void:
	for i in count:
		var height := 0.25 * float(i + 1)
		var center := start + direction * depth * (float(i) + 0.5) + Vector3(0, height * 0.5, 0)
		var size := Vector3(width, height, depth) if absf(direction.z) > 0.5 else Vector3(depth, height, width)
		_box(parent, "%s_%02d" % [prefix, i + 1], center, size, _metal)


func _root(nm: String) -> Node3D:
	var root := Node3D.new()
	root.name = nm
	add_child(root)
	return root


func _box(parent: Node3D, nm: String, center: Vector3, size: Vector3, mat: Material, visual: bool = true) -> void:
	var body := StaticBody3D.new()
	body.name = nm
	body.position = center
	parent.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mesh_instance.mesh = mesh
	mesh_instance.visible = visual
	body.add_child(mesh_instance)


func _label(parent: Node3D, nm: String, text: String, pos: Vector3, font_size: int) -> void:
	var label := Label3D.new()
	label.name = nm
	label.text = text
	label.position = pos
	label.font_size = font_size
	label.outline_size = 5
	label.pixel_size = 0.006
	label.modulate = Color(0.45, 0.86, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)


func _plain(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var mat := _plain(color * 0.2, 0.55)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat
