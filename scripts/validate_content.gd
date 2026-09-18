extends Node

# 只检查作者当前填写的表，不执行依赖示例数值的冒烟测试或推进游戏回合。
# GameState Autoload 已完成读取与校验；本场景仅输出结果码，0 成功、1 失败。
func _ready() -> void:
	if not GameState.configs_validated or not GameState.config_error.is_empty():
		printerr("CONTENT_CONFIG_FAILED: 配置初始化未完成，请检查前面的错误")
		get_tree().quit(1)
		return
	if OS.get_cmdline_user_args().has("--story-preview"):
		_print_story_preview()
	print("CONTENT_CONFIG_OK")
	get_tree().quit(0)


## 作者诊断入口：条件用新局真实状态，文本单独列出三阶段，不把预览记作完成。
func _print_story_preview() -> void:
	var context := GameState.story_context()
	print("STORY_PREVIEW: 新局只读检查，完成记录为空；列出各阶段文本不代表节点可触发")
	for node in GameState.story_config.nodes:
		print("\n", node.id, " | ", node.name)
		for checkpoint in node.checkpoints:
			var reasons: Array[String] = GameState.Story.blocking_reasons(node, context, str(checkpoint), str(node.kind))
			print("  ", checkpoint, "/", node.kind, ": ", "满足条件（尚未播放或完成）" if reasons.is_empty() else "；".join(reasons))
		for stage in range(3):
			var variant: Dictionary = GameState.Story.presentation(GameState.story_config, str(node.id), stage)
			print("  表现阶段 ", stage, " | 立绘: ", variant.get("portrait", {}))
			for line in variant.lines:
				print("    ", line.speaker, ": ", line.text)
