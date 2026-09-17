extends Node

# 只检查作者当前填写的表，不执行依赖示例数值的冒烟测试或推进游戏回合。
# GameState Autoload 已完成读取与校验；本场景仅输出结果码，0 成功、1 失败。
func _ready() -> void:
	if not GameState.config_error.is_empty():
		get_tree().quit(1)
		return
	print("CONTENT_CONFIG_OK")
	get_tree().quit(0)
