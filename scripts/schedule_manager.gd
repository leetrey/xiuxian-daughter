extends Node

# 两类活动共用定义，只有自由活动扣精力。草稿不产生收益。
# 先完整校验日程，再锁住阶段结算，防止重复点击或部分扣费。

func activities(kind: String) -> Array:
	return GameState.config.activities.filter(func(a: Dictionary) -> bool: return a.kind == kind)


func activity_by_id(id: String) -> Dictionary:
	for activity in GameState.config.activities:
		if activity.id == id:
			return activity
	return {}


func availability(activity: Dictionary) -> String:
	if activity.is_empty():
		return "未知活动"
	if int(activity.get("min_phase", 0)) > GameState.growth_phase():
		return "尚未开放"
	return ""


func assign_slot(index: int, id: String) -> String:
	if GameState.phase != GameState.Phase.FREE:
		return "日程已确认"
	if index < 0 or index >= GameState.plan.size():
		return "无效槽位"
	if id.is_empty():
		GameState.plan[index] = ""
		GameState.state_changed.emit()
		return ""
	var activity := activity_by_id(id)
	var reason := availability(activity)
	if not reason.is_empty():
		return reason
	if activity.kind != "schedule":
		return "自由活动不占培养槽"
	if not GameState.config.rules.allow_repeat:
		for i in range(GameState.plan.size()):
			if i != index and GameState.plan[i] == id:
				return "当前配置不允许重复安排"
	GameState.plan[index] = id
	GameState.state_changed.emit()
	return ""


func swap_slots(first: int, second: int) -> void:
	if GameState.phase != GameState.Phase.FREE:
		return
	if first < 0 or second < 0 or first >= GameState.plan.size() or second >= GameState.plan.size():
		return
	var previous: String = GameState.plan[first]
	GameState.plan[first] = GameState.plan[second]
	GameState.plan[second] = previous
	GameState.state_changed.emit()


func pressure_band(value: int) -> Dictionary:
	for band in GameState.config.pressure_bands:
		if value >= int(band.min) and value < int(band.max_exclusive):
			return band
	return {}


func outcome_for_roll(value: int, roll: float) -> Dictionary:
	# 独立选择函数允许直接测试概率边界，不必大量随机重跑。
	var cumulative := 0.0
	var probabilities: Array = pressure_band(clampi(value, 0, 100)).probabilities
	for i in range(probabilities.size()):
		cumulative += float(probabilities[i])
		if roll < cumulative:
			return GameState.config.outcomes[i]
	return GameState.config.outcomes.back()


func plan_error() -> String:
	if GameState.phase != GameState.Phase.FREE:
		return "本回合已结算"
	if GameState.plan.size() != GameState.schedule_slots:
		return "培养槽数量不符"
	var selected: Array[String] = []
	var costs: Dictionary = {}
	for id in GameState.plan:
		if id.is_empty():
			if GameState.config.rules.require_full_schedule:
				return "还有未安排的培养槽"
			continue
		var activity := activity_by_id(id)
		var reason := availability(activity)
		if not reason.is_empty():
			return reason
		if activity.kind != "schedule":
			return "日程中包含自由活动"
		if not GameState.config.rules.allow_repeat and selected.has(id):
			return "当前配置不允许重复安排"
		selected.append(id)
		for key in activity.get("costs", {}):
			costs[key] = int(costs.get(key, 0)) + int(activity.costs[key])
	if selected.is_empty():
		return "至少安排一项培养"
	return _cost_error(costs)


func confirm_schedule(ignore_idle: bool = false) -> Dictionary:
	var error := plan_error()
	if not error.is_empty():
		return {"ok": false, "message": error}
	var idle: Array[String] = GameState.Cave.idle_buildings()
	if not ignore_idle and not idle.is_empty():
		var summary := "以下建筑未安排生产：\n" + "\n".join(idle.slice(0, 6))
		if idle.size() > 6:
			summary += "\n另有 %d 栋，共 %d 栋" % [idle.size() - 6, idle.size()]
		return {"ok": false, "needs_confirmation": true, "message": summary}
	GameState.phase = GameState.Phase.RESOLVING
	GameState.last_results.clear()
	for id in GameState.plan:
		if id.is_empty():
			continue
		var activity := activity_by_id(id)
		var before: int = GameState.pressure
		var outcome := outcome_for_roll(before, GameState.rng.randf())
		_pay_costs(activity.get("costs", {}))
		var gains := _apply_growth(activity.growth, float(outcome.multiplier))
		GameState.pressure = clampi(before + int(activity.pressure), 0, 100)
		GameState.last_results.append({
			"id": id, "name": activity.name, "outcome": outcome.name,
			"multiplier": outcome.multiplier, "gains": gains,
			"pressure_before": before, "pressure_after": GameState.pressure
		})
	# 培养材料已扣除，再用剩余库存结算洞天；随后才应接入未来的剧情升级判断。
	GameState.Cave.settle()
	GameState.phase = GameState.Phase.RESULTS
	GameState.state_changed.emit()
	return {"ok": true, "message": "培养已完成"}


func free_action_error(id: String) -> String:
	if GameState.phase != GameState.Phase.FREE:
		return "自由活动已结束"
	var activity := activity_by_id(id)
	var error := availability(activity)
	if not error.is_empty():
		return error
	if activity.kind != "free":
		return "该活动需要安排培养槽"
	if GameState.energy < int(activity.get("energy_cost", 0)):
		return "精力不足"
	if int(activity.pressure) < 0 and GameState.pressure == 0:
		return "当前无需减压"
	return _cost_error(activity.get("costs", {}))


func execute_free_action(id: String) -> Dictionary:
	var error := free_action_error(id)
	if not error.is_empty():
		return {"ok": false, "message": error}
	var activity := activity_by_id(id)
	GameState.energy -= int(activity.get("energy_cost", 0))
	_pay_costs(activity.get("costs", {}))
	var gains := _apply_growth(activity.growth, 1.0)
	var before: int = GameState.pressure
	GameState.pressure = clampi(before + int(activity.pressure), 0, 100)
	GameState.state_changed.emit()
	return {"ok": true, "message": str(activity.name), "gains": gains, "pressure_change": GameState.pressure - before}


func _cost_error(costs: Dictionary) -> String:
	return GameState.cost_error(costs, GameState.inventory)


func _pay_costs(costs: Dictionary) -> void:
	GameState.pay_costs(costs)


func _apply_growth(growth: Dictionary, multiplier: float) -> Dictionary:
	var gains: Dictionary = {}
	for key in growth:
		var value := float(growth[key]) * multiplier
		var amount := floori(value) if GameState.config.rules.rounding == "floor" else roundi(value)
		GameState.base_stats[key] = int(GameState.base_stats[key]) + amount
		gains[key] = amount
	return gains
