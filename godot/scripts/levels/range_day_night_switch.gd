extends StaticBody3D

var _controller: Node
var _status_material: StandardMaterial3D


func setup(controller: Node) -> void:
	_controller = controller


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.55, 1.1, 0.4)
	collision.shape = shape
	collision.position.y = 0.55
	add_child(collision)

	var housing_material := StandardMaterial3D.new()
	housing_material.albedo_color = Color(0.12, 0.17, 0.2)
	housing_material.metallic = 0.65
	housing_material.roughness = 0.42
	_box("Housing", Vector3(0, 0.55, 0), Vector3(0.55, 1.1, 0.4), housing_material)
	_box("Panel", Vector3(0, 0.82, -0.215), Vector3(0.43, 0.32, 0.05), housing_material)

	_status_material = StandardMaterial3D.new()
	_status_material.emission_enabled = true
	_status_material.emission_energy_multiplier = 1.4
	_box("Status", Vector3(0, 0.86, -0.25), Vector3(0.28, 0.1, 0.025), _status_material)

	var label := Label3D.new()
	label.name = "Caption"
	label.text = "昼夜切换"
	label.position = Vector3(0, 1.35, 0)
	label.font_size = 42
	label.outline_size = 6
	label.pixel_size = 0.005
	label.modulate = Color(0.45, 0.86, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	_refresh_status()


func interact() -> void:
	if _controller == null:
		return
	_controller.toggle_mode()
	_refresh_status()
	Events.message_posted.emit("靶场照明：黑夜" if _controller.is_night() else "靶场照明：白天")


func interact_prompt() -> String:
	if _controller != null and _controller.is_night():
		return "F  切换白天"
	return "F  切换黑夜"


func _refresh_status() -> void:
	if _status_material == null:
		return
	var night: bool = _controller == null or _controller.is_night()
	_status_material.albedo_color = Color(0.05, 0.25, 0.35) if night else Color(0.8, 0.55, 0.12)
	_status_material.emission = Color(0.2, 0.72, 0.9) if night else Color(1.0, 0.78, 0.3)


func _box(nm: String, center: Vector3, size: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = nm
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = center
	add_child(mesh_instance)
