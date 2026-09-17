extends RefCounted

# 普通脚本，不新增 Autoload。所有位置、分配与产出只修改 GameState 中的洞天。
# 预览返回纯结果；提交结算才扣库存。道路为四向连通，资源按建筑 ID 顺序分配。
# definition 读取建筑类型模板，find_building 返回本局某一栋实例；二者不可混写。
const NEIGHBORS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


static func definition(building: Dictionary) -> Dictionary:
	return GameState.cave_config.buildings[building.type]


## 返回本局建筑的原字典，修改字段会写回 GameState；预演操作须先深复制。
static func find_building(id: int) -> Dictionary:
	for building in GameState.cave.buildings:
		if int(building.id) == id:
			return building
	return {}


## position 是逻辑左上格，size 是格数；规则层不使用等距画面的像素坐标。
static func cells(building: Dictionary) -> Array[Vector2i]:
	var occupied: Array[Vector2i] = []
	var footprint: Array = definition(building).size
	for y in range(int(footprint[1])):
		for x in range(int(footprint[0])):
			occupied.append(Vector2i(building.position) + Vector2i(x, y))
	return occupied


static func inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < int(GameState.cave_config.width) and cell.y < int(GameState.cave_config.height)


static func entrance() -> Vector2i:
	return Vector2i(int(GameState.cave_config.entrance[0]), int(GameState.cave_config.entrance[1]))


static func building_at(cell: Vector2i) -> Dictionary:
	for building in GameState.cave.buildings:
		if cells(building).has(cell):
			return building
	return {}


## 从入口广度优先遍历四向道路；seen 同时作为去重集合和有效路网查询表。
static func connected_roads(roads: Array) -> Dictionary:
	var seen: Dictionary = {entrance(): true}
	var frontier: Array[Vector2i] = [entrance()]
	var index := 0
	while index < frontier.size():
		var current := frontier[index]
		index += 1
		for direction in NEIGHBORS:
			var next: Vector2i = current + direction
			if roads.has(next) and not seen.has(next):
				seen[next] = true
				frontier.append(next)
	return seen


static func connected(building: Dictionary, network: Dictionary) -> bool:
	if definition(building).category == "landscape":
		return true
	for cell in cells(building):
		for direction in NEIGHBORS:
			if network.has(cell + direction):
				return true
	return false


static func capacity(world: Dictionary) -> int:
	var network := connected_roads(world.roads)
	var total := 0
	for building in world.buildings:
		if connected(building, network):
			total += int(definition(building).get("capacity", 0))
	return total


static func residents(world: Dictionary) -> int:
	var count := 0
	for worker in world.workers:
		if int(worker.building_id) >= 0:
			count += 1
	return count


## 只检查占地。移动时排除自身原占地；材料和民居容量由实际操作入口另查。
static func placement_error(type: String, position: Vector2i, moving_id: int = -1) -> String:
	if not GameState.cave_config.buildings.has(type):
		return "未知建筑"
	var candidate := {"type": type, "position": position}
	for cell in cells(candidate):
		if not inside(cell):
			return "超出洞天边界"
		if cell == entrance() or GameState.cave.roads.has(cell):
			return "不能占用入口或道路"
		for other in GameState.cave.buildings:
			if int(other.id) != moving_id and cells(other).has(cell):
				return "位置已被建筑占用"
	return ""


## 校验成功才扣建材和创建实例；稳定 id 不随移动变化，也用于生产分料排序。
static func build(type: String, position: Vector2i) -> Dictionary:
	if GameState.phase != GameState.Phase.FREE:
		return _result(false, "本回合管理已结束")
	var error := placement_error(type, position)
	if not error.is_empty():
		return _result(false, error)
	var costs: Dictionary = GameState.cave_config.buildings[type].costs
	error = GameState.cost_error(costs, GameState.inventory)
	if not error.is_empty():
		return _result(false, error)
	var id: int = GameState.cave.next_id
	GameState.pay_costs(costs)
	GameState.cave.next_id += 1
	GameState.cave.buildings.append({"id": id, "type": type, "position": position, "recipe": ""})
	GameState.state_changed.emit()
	return {"ok": true, "message": "建造完成", "id": id}


static func move_building(id: int, position: Vector2i) -> Dictionary:
	if GameState.phase != GameState.Phase.FREE:
		return _result(false, "本回合管理已结束")
	var building := find_building(id)
	if building.is_empty():
		return _result(false, "未选择建筑")
	var error := placement_error(str(building.type), position, id)
	if not error.is_empty():
		return _result(false, error)
	# 先在副本中验证搬迁后的连通容量，不通过时真实位置和御灵安排完全不动。
	var proposed: Dictionary = GameState.cave.duplicate(true)
	for item in proposed.buildings:
		if int(item.id) == id:
			item.position = position
	if residents(proposed) > capacity(proposed):
		return _result(false, "连通民居容量不足，请先取消部分御灵分配")
	building.position = position
	GameState.state_changed.emit()
	return _result(true, "位置已更新")


## 增删道路也先预演容量，防止拆路后已工作的御灵失去民居名额。
static func toggle_road(cell: Vector2i) -> Dictionary:
	if GameState.phase != GameState.Phase.FREE:
		return _result(false, "本回合管理已结束")
	if not inside(cell) or cell == entrance() or not building_at(cell).is_empty():
		return _result(false, "此处不能调整道路")
	var proposed: Dictionary = GameState.cave.duplicate(true)
	if proposed.roads.has(cell):
		proposed.roads.erase(cell)
	else:
		proposed.roads.append(cell)
	if residents(proposed) > capacity(proposed):
		return _result(false, "此路连接着已入住的民居，请先取消御灵分配")
	GameState.cave.roads = proposed.roads
	GameState.state_changed.emit()
	return _result(true, "道路已更新")


static func set_recipe(id: int, recipe: String) -> Dictionary:
	if GameState.phase != GameState.Phase.FREE:
		return _result(false, "本回合管理已结束")
	var building := find_building(id)
	if building.is_empty() or (not recipe.is_empty() and not definition(building).recipes.has(recipe)):
		return _result(false, "无效生产任务")
	building.recipe = recipe
	GameState.state_changed.emit()
	return _result(true, "生产安排已更新")


## slot 从 0 开始，空 worker_id 表示撤下。先清目标槽，再改该御灵唯一的归属。
static func assign_worker(building_id: int, slot: int, worker_id: String) -> Dictionary:
	if GameState.phase != GameState.Phase.FREE:
		return _result(false, "本回合管理已结束")
	var building := find_building(building_id)
	if building.is_empty() or slot < 0 or slot >= int(definition(building).worker_slots):
		return _result(false, "无效工作槽")
	var proposed: Dictionary = GameState.cave.duplicate(true)
	var found := worker_id.is_empty()
	for worker in proposed.workers:
		if int(worker.building_id) == building_id and int(worker.slot) == slot:
			worker.building_id = -1
			worker.slot = -1
	for worker in proposed.workers:
		if worker.id == worker_id:
			worker.building_id = building_id
			worker.slot = slot
			found = true
	if not found:
		return _result(false, "未获得此御灵")
	if residents(proposed) > capacity(proposed):
		return _result(false, "连通民居容量不足")
	GameState.cave.workers = proposed.workers
	GameState.state_changed.emit()
	return _result(true, "御灵分配已更新")


## 只提醒未选生产任务的建筑；没有御灵但已选任务，仍可按基础产出生产。
static func idle_buildings() -> Array[String]:
	var names: Array[String] = []
	for building in GameState.cave.buildings:
		if not definition(building).recipes.is_empty() and str(building.recipe).is_empty():
			names.append("%s #%d" % [definition(building).name, int(building.id)])
	return names


## 比较所有占地格，取最近距离而非中心距离，让大型建筑也按边界接受景观加成。
static func distance(first: Dictionary, second: Dictionary) -> int:
	var shortest := 100000
	for a in cells(first):
		for b in cells(second):
			var delta: Vector2i = (a - b).abs()
			var value := maxi(delta.x, delta.y) if GameState.cave_config.distance_metric == "chebyshev" else delta.x + delta.y
			shortest = mini(shortest, value)
	return shortest


static func multipliers(building: Dictionary) -> Dictionary:
	# 每只御灵独立相乘；景观先按词条合并加法，再把各词条作为独立乘区。
	var work_type := str(definition(building).get("work_type", ""))
	var worker_factor := 1.0
	for worker in GameState.cave.workers:
		if int(worker.building_id) == int(building.id):
			worker_factor *= 1.0 + float(worker.aptitudes.get(work_type, 0)) / 100.0
	var groups: Dictionary = {}
	for other in GameState.cave.buildings:
		var bonus: Dictionary = definition(other).get("bonus", {})
		if bonus.is_empty() or not bonus.work_types.has(work_type):
			continue
		var separation := distance(building, other)
		# 以最近占地格计距；相邻为满额，距离 radius + 1 时归零。
		var weight := maxf(0.0, 1.0 - float(separation - 1) / float(bonus.radius))
		groups[bonus.affix] = float(groups.get(bonus.affix, 0.0)) + float(bonus.peak) * weight
	var landscape_factor := 1.0
	for value in groups.values():
		landscape_factor *= 1.0 + float(value)
	return {"workers": worker_factor, "landscape": landscape_factor, "groups": groups}


## 只读当前布局与传入库存，返回逐栋 rows、总消耗 consumed 和总产出 produced。
## 预览和真实结算共用此函数，避免界面显示与到账结果使用两套公式。
static func forecast(stock: Dictionary) -> Dictionary:
	# budget 只减投入，outputs 单独累积；同批新产出绝不成为下一栋的原料。
	var budget: Dictionary = stock.duplicate()
	var consumed: Dictionary = {}
	var produced: Dictionary = {}
	var rows: Array[Dictionary] = []
	var ordered: Array = GameState.cave.buildings.duplicate()
	# 绘制可以按前后遮挡排序，但缺料分配顺序必须始终按建造 id，不能随位置变化。
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	var network := connected_roads(GameState.cave.roads)
	for building in ordered:
		if definition(building).recipes.is_empty():
			continue
		var factors := multipliers(building)
		var row := {"id": building.id, "name": definition(building).name, "reason": "", "inputs": {}, "outputs": {}, "factors": factors}
		if str(building.recipe).is_empty():
			row.reason = "未安排生产"
		elif not connected(building, network):
			row.reason = "道路未连通，停产"
		else:
			var recipe: Dictionary = GameState.cave_config.recipes[building.recipe]
			row.reason = GameState.cost_error(recipe.inputs, budget)
			if str(row.reason).is_empty():
				# 全部原料都够才扣本栋预算；缺一种时整单停产，不先扣另一种。
				row.inputs = recipe.inputs.duplicate()
				for key in recipe.inputs:
					var amount := int(recipe.inputs[key])
					budget[key] = int(budget.get(key, 0)) - amount
					consumed[key] = int(consumed.get(key, 0)) + amount
				for key in recipe.outputs:
					var raw := float(recipe.outputs[key]) * float(factors.workers) * float(factors.landscape)
					var amount := roundi(raw) if GameState.cave_config.output_rounding == "round" else floori(raw)
					row.outputs[key] = amount
					produced[key] = int(produced.get(key, 0)) + amount
		rows.append(row)
	return {"rows": rows, "consumed": consumed, "produced": produced}


static func preview() -> Dictionary:
	# 培养先于生产，因此预测扣去草稿已安排的材料；这不是库存预留或真实扣费。
	var stock: Dictionary = GameState.inventory.duplicate()
	if GameState.phase == GameState.Phase.FREE:
		for id in GameState.plan:
			var activity: Dictionary = ScheduleManager.activity_by_id(id)
			for key in activity.get("costs", {}):
				stock[key] = maxi(0, int(stock.get(key, 0)) - int(activity.costs[key]))
	return forecast(stock)


## 唯一的生产入库入口；阶段和回合标记共同防重，最后由培养流程统一发刷新信号。
static func settle() -> Dictionary:
	if GameState.phase != GameState.Phase.RESOLVING or GameState.last_production_turn == GameState.turn:
		return _result(false, "生产已结算或不在结算阶段")
	var report := forecast(GameState.inventory)
	GameState.pay_costs(report.consumed)
	for key in report.produced:
		GameState.inventory[key] = int(GameState.inventory.get(key, 0)) + int(report.produced[key])
	GameState.last_production = report
	GameState.last_production_turn = GameState.turn
	return {"ok": true, "message": "生产已入库"}


static func _result(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}
