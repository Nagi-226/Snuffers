## 先还原近墙显示深度，再由武器脚本更新本帧后坐与换弹姿态。
extends Node

@onready var _player: Node = get_parent()


func _process(_delta: float) -> void:
	if _player.is_processing():
		_player.call("_restore_viewmodel_depth")
