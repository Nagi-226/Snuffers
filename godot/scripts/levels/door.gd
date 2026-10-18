extends Node3D
## Door — 可交互门扇（2026-10-18 机主立项：E 键通用交互开门，半衰期式）。
##
## 常闭门；玩家准星对准按 E 开/关。铰链在门洞一侧门垛，向室内旋转开启。
## 交互契约：player_controller 射线命中碰撞体后沿父链找 interact() /
## interact_prompt()，本脚本实现这两个方法即接入，无需新信号/新契约。
## 视觉/碰撞由 setup() 按 builder 传入的门洞尺寸现场生成，参数来自
## street_builder 的 SHELL_DOOR_* 常量（本脚本不硬编码门洞尺寸）。

const DOOR_LEAF_T: float = 0.06 ## 门板厚 m
const OPEN_TIME: float = 0.45   ## 开/关动画时长 s

var _open: bool = false
var _open_deg: float = 105.0    ## 开启角（带符号：东排 +105 内开 / 西排 -105）
var _tween: Tween = null
var _leaf: AnimatableBody3D = null  ## 铰链枢轴=物理体本体（直接旋转物理体，保证物理服务器同步；
                                    ## 曾踩坑：旋转父 Node3D 时子物理体变换不进入物理空间，射线仍见旧位）


## hinge_pos：铰链世界位（门洞一侧、地面）；w/h：门扇宽高；open_deg：带符号开启角。
func setup(hinge_pos: Vector3, w: float, h: float, open_deg: float, color: Color) -> void:
	position = hinge_pos
	_open_deg = open_deg
	_leaf = AnimatableBody3D.new()
	_leaf.name = "Leaf"
	add_child(_leaf)
	# 碰撞形与门板网格同为物理体子节点，随体一并旋转
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(DOOR_LEAF_T, h, w)
	col.shape = box
	col.position = Vector3(0.0, h * 0.5, w * 0.5)
	_leaf.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(DOOR_LEAF_T, h, w)
	mesh.mesh = bm
	mesh.position = Vector3(0.0, h * 0.5, w * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mesh.material_override = mat
	_leaf.add_child(mesh)


func interact() -> void:
	_open = not _open
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_leaf, "rotation_degrees:y",
		_open_deg if _open else 0.0, OPEN_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func interact_prompt() -> String:
	return "E  关门" if _open else "E  开门"
