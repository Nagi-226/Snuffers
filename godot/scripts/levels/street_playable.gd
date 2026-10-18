extends Node3D
## street_playable.gd — 街景可玩验收场景（实机第一人称 + N 键夜视）
## 复用 street_test 地图/昼夜驱动/驻军，照 main.tscn 模式总装 Player/HUD/AudioManager。
## 仅清掉开发用 OverviewCamera(fly_camera)，避免与玩家相机争 current。
## 注：OverviewCamera 只被 street_builder 的 --shot 截图路径引用，本场景不走该路径，可安全移除。

func _ready() -> void:
	var cam := get_node_or_null("StreetTest/OverviewCamera")
	if cam:
		cam.queue_free()
