extends RefCounted

# 普通规则脚本，不新增 Autoload。进度、当前台词和解锁都保存在 GameState。
# 每个检查点先耗尽当前可完成的主线，再处理支线；支线带来的新主线等下个检查点。


## 仅由开局、回合推进和生产结算调用；空剧情表会直接回到 FREE/RESULTS。
static func begin(checkpoint: String) -> bool:
	var expected_phase: int = GameState.Phase.FREE if checkpoint == "turn_start" else GameState.Phase.RESOLVING
	if not GameState.Story.CHECKPOINTS.has(checkpoint) or GameState.phase != expected_phase:
		return false
	if checkpoint == "turn_end" and GameState.last_production_turn != GameState.turn:
		return false
	var key := "%d:%s" % [GameState.turn, checkpoint]
	if GameState.story.checked.has(key):
		return false
	GameState.story.checked[key] = true
	GameState.story.checkpoint = checkpoint
	GameState.story.kind = "main"
	GameState.story.active = {}
	GameState.phase = GameState.Phase.STORY
	_select_next()
	GameState.state_changed.emit()
	return true


## 一次只推进屏幕上那一行。旧按钮事件的 ID/行号不符时拒绝，避免重复提交奖励。
static func advance(expected_id: String, expected_line: int) -> Dictionary:
	var active: Dictionary = GameState.story.active
	if GameState.phase != GameState.Phase.STORY or active.is_empty():
		return {"ok": false, "message": "当前没有待推进的剧情"}
	if active.node.id != expected_id or int(active.line) != expected_line:
		return {"ok": false, "message": "这段对话已经推进"}
	if expected_line + 1 < active.presentation.lines.size():
		active.line = expected_line + 1
		GameState.state_changed.emit()
		return {"ok": true, "message": ""}
	# 最后一行读完才提交。这里重新检查整份条件，检查失败不得部分扣费或记录完成。
	var node: Dictionary = active.node
	var reasons: Array[String] = GameState.Story.blocking_reasons(node, GameState.story_context(), GameState.story.checkpoint, GameState.story.kind)
	if not reasons.is_empty():
		return {"ok": false, "message": "；".join(reasons)}
	var costs: Dictionary = node.get("costs", {})
	var rewards: Dictionary = node.get("rewards", {})
	GameState.pay_costs(costs)
	for id in rewards.get("items", {}):
		GameState.inventory[id] = int(GameState.inventory.get(id, 0)) + int(rewards.items[id])
	var timing := str(rewards.get("unlock_timing", "next_turn"))
	_grant_unlocks(rewards.get("activities", []), GameState.unlocked_activities, GameState.pending_activity_unlocks, timing)
	var applied_rewards: Dictionary = rewards.duplicate(true)
	if rewards.has("blueprints"):
		# 重复图纸不转成库存、材料或补偿，也不在本次报告中冒充新获得。
		applied_rewards.blueprints = _grant_unlocks(rewards.blueprints, GameState.unlocked_blueprints, GameState.pending_blueprint_unlocks, timing)
	GameState.story.completed[node.id] = {"turn": GameState.turn, "growth_phase": int(active.growth_phase)}
	GameState.story.results.append({"id": node.id, "name": node.name, "costs": costs.duplicate(true), "rewards": applied_rewards})
	GameState.story.active = {}
	# 扣费与奖励会改变下一条的资格，因此不缓存整批候选列表。
	_select_next()
	GameState.state_changed.emit()
	return {"ok": true, "message": ""}


## 在回合开始检查剧情之前激活到期日程和图纸；不替代土地扩张或开局继承。
static func apply_pending_unlocks() -> void:
	_apply_pending(GameState.unlocked_activities, GameState.pending_activity_unlocks)
	_apply_pending(GameState.unlocked_blueprints, GameState.pending_blueprint_unlocks)


## 日程和图纸复用生效时点，不合并两类状态；返回本次新生效或新预约的 ID。
static func _grant_unlocks(ids: Array, unlocked: Array[String], pending: Dictionary, timing: String) -> Array[String]:
	var granted: Array[String] = []
	for id in ids:
		if unlocked.has(id):
			continue
		if timing == "immediate":
			unlocked.append(str(id))
			pending.erase(id)
			granted.append(str(id))
		elif not pending.has(id):
			pending[id] = GameState.turn + 1
			granted.append(str(id))
	return granted


static func _apply_pending(unlocked: Array[String], pending: Dictionary) -> void:
	for id in pending.keys():
		if int(pending[id]) <= GameState.turn:
			if not unlocked.has(id):
				unlocked.append(str(id))
			pending.erase(id)


static func _select_next() -> void:
	while true:
		var ids: Array[String] = GameState.Story.candidates(GameState.story_config, GameState.story_context(), GameState.story.checkpoint, GameState.story.kind)
		if not ids.is_empty():
			for node in GameState.story_config.nodes:
				if node.id == ids[0]:
					# 锁定正在展示的内容与费用，UI 只读取快照，不直接编辑配置模板。
					GameState.story.active = {
						"node": node.duplicate(true), "line": 0, "growth_phase": GameState.growth_phase(),
						"presentation": GameState.Story.presentation(GameState.story_config, str(node.id), GameState.growth_phase()),
					}
					return
		if GameState.story.kind == "main":
			GameState.story.kind = "side"
			continue
		GameState.phase = GameState.Phase.FREE if GameState.story.checkpoint == "turn_start" else GameState.Phase.RESULTS
		GameState.story.checkpoint = ""
		GameState.story.kind = ""
		GameState.story.active = {}
		return
