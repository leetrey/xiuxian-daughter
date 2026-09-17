extends Node

# 一份场景覆盖培养与洞天主干。--ui-snapshot=/tmp/目录 可导出真实渲染截图。
# 这些是程序回归例子，含默认数值断言；作者仅检查填表应运行 validate_content.tscn。
var failures := 0
var ui_completed := false


## 默认只跑规则；带截图参数时才创建界面。退出码便于终端判断，不只依赖最后一行文字。
func _ready() -> void:
	if not GameState.config_error.is_empty():
		get_tree().quit(1)
		return
	_run_content_rules()
	_run_rules()
	_run_cave_rules()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ui-snapshot="):
			await _capture_ui(argument.trim_prefix("--ui-snapshot="))
			_check(ui_completed, "真实窗口走查必须完整执行，脚本中断不得报成功")
	if failures == 0:
		print("SMOKE_TEST_OK")
	else:
		printerr("SMOKE_TEST_FAILED: ", failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)


func _fill(id: String = "sword") -> void:
	for i in range(GameState.schedule_slots):
		_check(ScheduleManager.assign_slot(i, id).is_empty(), "安排日程")


## 临时修改内存配置验证错误和扩展场景，不写入 JSON；用完恢复，避免污染后续测试。
func _run_content_rules() -> void:
	var items: Dictionary = GameState.config.items.duplicate(true)
	var cave: Dictionary = GameState.cave_config.duplicate(true)
	_check(GameState.Content.validate_items(items).is_empty(), "独立物品表有效")
	_check(GameState.Content.validate_recipes(cave.recipes, items).is_empty(), "独立配方表有效")
	_check(items.qingyun_grass.category == "herb" and items.wood.category == "resource", "药材独立于基础资源")
	var parsed: Dictionary = GameState.Content.parse_object('{"items":', "bad.json")
	_check(str(parsed.error).contains("bad.json") and str(parsed.error).contains("JSON"), "JSON 语法错误包含文件位置")
	_check(not str(GameState.Content.parse_object("[]", "array.json").error).is_empty(), "配置根节点必须为对象")
	_check(not str(GameState.Content.read_object("res://data/missing-test-file.json").error).is_empty(), "缺少文件明确报错")
	for bad_value in [-1, 1.5, "3", true, null]:
		var error: String = GameState.Content.validate_amounts({"qingyun_grass": bad_value}, items, "test.inputs")
		_check(error.contains("test.inputs.qingyun_grass"), "物品数量错误定位到具体字段")
	_check(GameState.Content.validate_amounts({"qingyun_grass": 0}, items, "stock").is_empty(), "库存允许零数量")
	_check(not GameState.Content.validate_amounts({"qingyun_grass": 0}, items, "outputs", false).is_empty(), "配方不接受零数量产物")
	_check(not GameState.Content.validate_amounts({"missing": 1}, items, "stock").is_empty(), "库存不能引用未定义物品")
	for bad_item in [null, {}, {"name": "草", "category": "food"}, {"name": " ", "category": "herb"}]:
		var changed: Dictionary = items.duplicate(true)
		changed.qingyun_grass = bad_item
		_check(GameState.Content.validate_items(changed).contains("qingyun_grass"), "物品结构错误定位到 ID")
	for bad_recipe in [null, {}, {"name": "无产出", "inputs": {}, "outputs": {}}, {"name": "未知物品", "inputs": {}, "outputs": {"missing": 2}}]:
		_check(GameState.Content.validate_recipes({"broken": bad_recipe}, items).contains("broken"), "配方结构错误定位到 ID")
	var field_data: Dictionary = cave.buildings.herb_field.duplicate(true)
	field_data.recipes = ["missing"]
	_check(GameState.Content.validate_building_recipes(field_data, cave.recipes, items, "herb_field").contains("missing"), "建筑配方引用检查")
	field_data.recipes = ["gather_wood"]
	_check(GameState.Content.validate_building_recipes(field_data, cave.recipes, items, "herb_field").contains("output_categories"), "灵田拒绝基础资源产物")
	field_data.recipes = ["make_clearheart"]
	_check(not GameState.Content.validate_building_recipes(field_data, cave.recipes, items, "herb_field").is_empty(), "灵田拒绝加工制品")
	field_data.recipes = ["grow_clearheart", "grow_clearheart"]
	_check(not GameState.Content.validate_building_recipes(field_data, cave.recipes, items, "herb_field").is_empty(), "拒绝重复挂载配方")
	field_data.recipes = ["grow_qingyun"]
	field_data.output_categories = []
	_check(not GameState.Content.validate_building_recipes(field_data, cave.recipes, items, "herb_field").is_empty(), "生产建筑必须明确允许的产物分类")
	GameState.cave_config.recipes.grow_qingyun.outputs.wood = 1
	_check(GameState.validate_cave_config().contains("grow_qingyun"), "基础资源副产物也不能混入灵田配方")
	GameState.cave_config = cave.duplicate(true)
	GameState.config.initial_inventory.missing = 1
	_check(GameState.validate_config().contains("initial_inventory.missing"), "初始库存跨表引用检查")
	GameState.config.initial_inventory.erase("missing")
	var sword := ScheduleManager.activity_by_id("sword")
	sword.costs = {"qingyun_grass": 1.5}
	_check(GameState.validate_config().contains("activities.sword.costs.qingyun_grass"), "活动材料数量检查")
	sword.erase("costs")
	GameState.cave_config.buildings.herb_field.costs.wood = "4"
	_check(GameState.validate_cave_config().contains("buildings.herb_field.costs.wood"), "建筑材料数量检查")
	GameState.cave_config = cave.duplicate(true)

	# 模拟作者仅增加数据：新药材、新种植任务和双原料丹方，不为新品种加规则分支。
	GameState.config.items.test_herb = {"name": "测试药材", "category": "herb"}
	GameState.cave_config.recipes.grow_test = {"name": "测试种植", "inputs": {}, "outputs": {"test_herb": 3}}
	GameState.cave_config.recipes.make_test = {"name": "测试双料加工", "inputs": {"qingyun_grass": 2, "test_herb": 3}, "outputs": {"clearheart_pill": 1}}
	GameState.cave_config.buildings.herb_field.recipes.append("grow_test")
	GameState.cave_config.buildings.alchemy.recipes.append("make_test")
	var validation_error := GameState.validate_config() + GameState.validate_cave_config()
	_check(validation_error.is_empty(), "数据扩充无需修改生产规则: " + validation_error)
	GameState.reset_game(42)
	var field := _build("herb_field", Vector2i(1, 2), "grow_qingyun")
	_build("herb_field", Vector2i(4, 2), "grow_test")
	var alchemy := _build("alchemy", Vector2i(2, 4), "make_test")
	var preview: Dictionary = GameState.Cave.preview()
	_check(preview.produced.qingyun_grass == 4 and preview.produced.test_herb == 3, "新物品可被产出预测识别")
	_check(_row(preview, alchemy).outputs.is_empty(), "新配方仍不能使用同批次产物")
	_fill()
	ScheduleManager.confirm_schedule()
	_check(GameState.inventory.qingyun_grass == 4 and GameState.inventory.test_herb == 3, "未列入初始库存的新物品自动入库")
	GameState.advance_turn()
	GameState.Cave.set_recipe(field, "grow_clearheart")
	preview = GameState.Cave.preview()
	_check(preview.consumed.qingyun_grass == 2 and preview.consumed.test_herb == 3, "双原料配方一起预算")
	_check(preview.produced.clearheart_pill == 1, "新加工配方产出可预测")
	_fill()
	ScheduleManager.confirm_schedule()
	_check(GameState.last_production == preview and GameState.inventory.qingyun_grass == 2, "双原料配方预览与实算一致")
	GameState.advance_turn()
	GameState.inventory.test_herb = 2
	preview = GameState.Cave.preview()
	_check(preview.consumed.is_empty() and _row(preview, alchemy).outputs.is_empty(), "缺少一种材料时整批不扣料")
	GameState.config.items = items
	GameState.cave_config = cave
	GameState.reset_game()


## 固定种子保证可复现；每组案例重开本局，分别验证阶段、成本、随机与 A/B 边界。
func _run_rules() -> void:
	GameState.reset_game(42)
	_check(GameState.base_stats.size() == 16, "16 项细分")
	_check(GameState.plan.size() == 3, "默认三槽")
	GameState.equipment_bonuses.weapon = {"power": 1000}
	_check(GameState.attribute("power") == 8, "A 不含装备")
	_check(GameState.attribute("power", true) == 1008, "A+B 正确")
	_check(GameState.group_total("physique") == 32, "四维 A 不被装备改写")
	GameState.equipment_bonuses.weapon.clear()

	var thresholds := [0, 19, 20, 49, 50, 79, 80, 100]
	var expected := [1.5, 1.5, 1.3, 1.3, 1.0, 1.0, 0.9, 0.9]
	for i in range(thresholds.size()):
		var band := ScheduleManager.pressure_band(thresholds[i])
		var mean := 0.0
		var cumulative := 0.0
		for j in range(3):
			var probability: float = band.probabilities[j]
			var midpoint := cumulative + probability / 2.0
			_check(ScheduleManager.outcome_for_roll(thresholds[i], midpoint).name == GameState.config.outcomes[j].name, "概率区间")
			mean += probability * float(GameState.config.outcomes[j].multiplier)
			cumulative += probability
		_check(is_equal_approx(mean, expected[i]), "压力期望")
	_check(ScheduleManager.outcome_for_roll(0, 0.34).name == "成功", "大成功右边界")
	_check(ScheduleManager.outcome_for_roll(0, 0.96).name == "失败", "失败区间")

	_check(not GameState.advance_turn(), "未结算不能跳回合")
	var initial: Dictionary = GameState.base_stats.duplicate()
	var rng_state: int = GameState.rng.state
	_check(not ScheduleManager.confirm_schedule().ok, "空日程不能确认")
	_check(GameState.base_stats == initial and GameState.rng.state == rng_state, "校验失败不产生收益或随机数")
	_check(not ScheduleManager.assign_slot(0, "visit").is_empty(), "自由活动不能进培养槽")
	_check(not ScheduleManager.assign_slot(0, "focused_breathing").is_empty(), "中期吐纳阶段限制")
	_check(ScheduleManager.execute_free_action("visit").ok, "自由活动可执行")
	_check(GameState.energy == 8 and GameState.plan.count("") == 3, "只扣精力不占槽")
	GameState.pressure = 10
	_check(ScheduleManager.execute_free_action("clearheart").ok, "物品减压")
	_check(GameState.pressure == 0 and GameState.inventory.clearheart_grass == 2, "减压下限与实际消耗")
	_check(not ScheduleManager.execute_free_action("clearheart").ok, "零压力不浪费物品")
	GameState.energy = 0
	_check(not ScheduleManager.execute_free_action("visit").ok, "精力不足不执行")
	GameState.pressure = 18
	_fill()
	ScheduleManager.assign_slot(1, "breathing")
	ScheduleManager.swap_slots(0, 1)
	_check(GameState.plan[0] == "breathing", "日程排序")
	_check(ScheduleManager.confirm_schedule().ok, "零精力仍可培养")
	_check(GameState.energy == 0 and GameState.last_results.size() == 3, "培养不扣精力")
	_check(GameState.last_results[0].pressure_before == 18 and GameState.last_results[1].pressure_before == 24, "逐槽使用实时压力")
	initial = GameState.base_stats.duplicate()
	_check(not ScheduleManager.confirm_schedule().ok, "不可重复结算")
	_check(GameState.base_stats == initial, "重复确认不重复成长")
	_check(not ScheduleManager.execute_free_action("visit").ok, "结算后禁自由活动")
	_check(not ScheduleManager.assign_slot(0, "music").is_empty(), "结算后不能编辑")
	var pressure_before: int = GameState.pressure
	_check(GameState.advance_turn(), "进入下一回合")
	_check(GameState.energy == 10 and GameState.pressure == pressure_before, "精力恢复而压力保留")
	_check(GameState.plan.count("") == 3, "下一回合清空草稿")

	GameState.pressure = 100
	_fill()
	ScheduleManager.confirm_schedule()
	_check(GameState.phase == GameState.Phase.RESULTS and GameState.pressure == 100, "压力满值不道陨")
	for pair in [[12, 1], [36, 2]]:
		GameState.turn = pair[0]
		GameState.phase = GameState.Phase.RESULTS
		GameState.advance_turn()
		_check(GameState.growth_phase() == pair[1], "阶段边界")
	_check(ScheduleManager.availability(ScheduleManager.activity_by_id("inner_breathing")).is_empty(), "后期吐纳开放")
	GameState.turn = 60
	GameState.phase = GameState.Phase.RESULTS
	GameState.advance_turn()
	_check(GameState.phase == GameState.Phase.FINISHED and not GameState.advance_turn(), "最终回合不越界")

	for count in [4, 5]:
		GameState.config.rules.schedule_slots = count
		GameState.reset_game(7)
		_fill()
		_check(ScheduleManager.confirm_schedule().ok and GameState.last_results.size() == count, "可配置四/五槽")
	GameState.config.rules.schedule_slots = 3
	GameState.config.rules.allow_repeat = false
	GameState.reset_game(7)
	ScheduleManager.assign_slot(0, "sword")
	_check(not ScheduleManager.assign_slot(1, "sword").is_empty(), "禁重复配置")
	GameState.config.rules.allow_repeat = true
	GameState.config.rules.require_full_schedule = false
	_check(ScheduleManager.confirm_schedule().ok and GameState.last_results.size() == 1, "允许留空配置")
	GameState.config.rules.require_full_schedule = true

	# 聚合校验成本，不能前两项扣完后第三项才失败。
	GameState.reset_game(8)
	var sword := ScheduleManager.activity_by_id("sword")
	sword.costs = {"clearheart_grass": 2}
	_fill()
	initial = GameState.base_stats.duplicate()
	_check(not ScheduleManager.confirm_schedule().ok, "总材料不足")
	_check(GameState.inventory.clearheart_grass == 3 and GameState.base_stats == initial, "失败整批不扣材料")
	sword.erase("costs")
	GameState.base_stats.power = 1000
	ScheduleManager.confirm_schedule()
	_check(GameState.base_stats.power > 1000, "永久成长不受旧上限截断")
	GameState.reset_game(99)
	_fill()
	ScheduleManager.confirm_schedule()
	var first_run: Array = GameState.last_results.duplicate(true)
	GameState.reset_game(99)
	_fill()
	ScheduleManager.confirm_schedule()
	_check(GameState.last_results == first_run, "相同种子重现培养结果")
	GameState.reset_game()


func _build(type: String, position: Vector2i, recipe: String = "") -> int:
	var result: Dictionary = GameState.Cave.build(type, position)
	_check(result.ok, "建造 " + type)
	var id := int(result.get("id", -1))
	if not recipe.is_empty():
		_check(GameState.Cave.set_recipe(id, recipe).ok, "选择生产任务")
	return id


func _row(report: Dictionary, id: int) -> Dictionary:
	for row in report.rows:
		if int(row.id) == id:
			return row
	return {}


## 用小布局验证核心生产闭环；重点检查拒绝操作无副作用、预览等于实算及防重复入库。
func _run_cave_rules() -> void:
	var config: Dictionary = GameState.cave_config.duplicate(true)
	for key in ["buildings", "recipes", "entrance", "initial_roads", "workers"]:
		GameState.cave_config.erase(key)
		_check(not GameState.validate_cave_config().is_empty(), "洞天缺少配置字段时明确报错")
		GameState.cave_config = config.duplicate(true)
	GameState.cave_config.buildings.herb_field.recipes = ["missing"]
	_check(not GameState.validate_cave_config().is_empty(), "配置拒绝未知配方")
	GameState.cave_config = config.duplicate(true)
	GameState.cave_config.buildings.spring.bonus.radius = 0
	_check(not GameState.validate_cave_config().is_empty(), "配置拒绝零半径")
	GameState.cave_config = config
	GameState.reset_game(42)
	var field := _build("herb_field", Vector2i(1, 2), "grow_clearheart")
	var stock: Dictionary = GameState.inventory.duplicate()
	var energy: int = GameState.energy
	_check(not GameState.Cave.build("herb_field", Vector2i(2, 2)).ok, "禁止重叠")
	_check(not GameState.Cave.build("house", Vector2i(1, 3)).ok, "禁止占路")
	_check(not GameState.Cave.build("house", Vector2i(0, 3)).ok, "禁止占入口")
	_check(not GameState.Cave.build("herb_field", Vector2i(7, 5)).ok, "完整占地不能越界")
	_check(GameState.inventory == stock, "无效建造不扣费")
	GameState.inventory.wood = 0
	_check(not GameState.Cave.build("house", Vector2i(1, 4)).ok, "建材不足不能施工")
	_check(GameState.inventory.stone == stock.stone and GameState.cave.buildings.size() == 1, "建材不足无部分扣费或新增建筑")
	GameState.inventory = stock.duplicate()
	_check(GameState.energy == energy and GameState.plan.count("") == 3, "洞天管理不占精力或日程")
	_check(GameState.Cave.preview().produced.clearheart_grass == 4, "无御灵仍有基础产出")
	_check(not GameState.Cave.assign_worker(field, 0, "qinghe").ok, "入住需要连通民居")
	var house := _build("house", Vector2i(1, 4))
	_check(GameState.Cave.assign_worker(field, 0, "qinghe").ok, "民居支持派工")
	var alchemy := _build("alchemy", Vector2i(4, 2), "make_clearheart")
	_check(GameState.Cave.assign_worker(alchemy, 0, "qinghe").ok, "同一御灵可调岗")
	_check(GameState.Cave.residents(GameState.cave) == 1, "调岗不重复占人口")
	_check(is_equal_approx(GameState.Cave.multipliers(GameState.Cave.find_building(field)).workers, 1.0), "原工作槽恢复基础产出")
	GameState.Cave.assign_worker(field, 0, "qinghe")
	GameState.Cave.assign_worker(alchemy, 0, "xuansha")
	var world: Dictionary = GameState.cave.duplicate(true)
	_check(not GameState.Cave.assign_worker(field, 0, "missing").ok, "拒绝未知御灵")
	_check(not GameState.Cave.assign_worker(field, 1, "qinghe").ok, "小建筑不能越槽")
	_check(not GameState.Cave.move_building(house, Vector2i(7, 0)).ok, "不能断开已入住民居")
	_check(not GameState.Cave.toggle_road(Vector2i(1, 3)).ok, "不能移除维持人口的道路")
	_check(GameState.cave == world, "失败派工与道路操作保持原状")
	_build("scarecrow", Vector2i(1, 1))
	_build("scarecrow", Vector2i(2, 1))
	var spring := _build("spring", Vector2i(3, 2))
	var factors: Dictionary = GameState.Cave.multipliers(GameState.Cave.find_building(field))
	_check(is_equal_approx(factors.workers, 1.5), "适应性乘区")
	_check(is_equal_approx(factors.groups.harvest, 1.0) and is_equal_approx(factors.landscape, 2.5), "同词条相加、不同词条相乘")
	_check(GameState.Cave.preview().produced.clearheart_grass == 15, "御灵与景观独立乘区")
	stock = GameState.inventory.duplicate()
	_check(GameState.Cave.move_building(spring, Vector2i(3, 1)).ok, "景观自由移动")
	factors = GameState.Cave.multipliers(GameState.Cave.find_building(field))
	_check(is_equal_approx(factors.groups.spirit, 0.125), "景观距离递减")
	GameState.cave_config.output_rounding = "round"
	_check(GameState.Cave.preview().produced.clearheart_grass == 14, "产出可配置四舍五入")
	GameState.cave_config.output_rounding = "floor"
	_check(GameState.Cave.preview().produced.clearheart_grass == 13, "产出默认向下取整")
	GameState.cave_config.distance_metric = "chebyshev"
	_check(GameState.Cave.distance(GameState.Cave.find_building(field), GameState.Cave.find_building(spring)) == 1, "可配置距离度量")
	GameState.cave_config.distance_metric = "manhattan"
	_check(GameState.Cave.move_building(field, Vector2i(2, 4)).ok, "移动生产建筑")
	_check(GameState.Cave.find_building(field).recipe == "grow_clearheart", "移动保留 ID 与任务")
	_check(GameState.cave.workers[0].building_id == field and GameState.inventory == stock, "移动保留御灵且无费用")
	GameState.cave_config.buildings.herb_field.worker_slots = 2
	GameState.Cave.assign_worker(field, 1, "xuansha")
	factors = GameState.Cave.multipliers(GameState.Cave.find_building(field))
	_check(is_equal_approx(factors.workers, 1.65), "多御灵分别相乘")
	GameState.cave_config.buildings.herb_field.worker_slots = 1

	# 一批只分配已有原料；首回合草产出不能直接变成丹药。
	GameState.reset_game(42)
	field = _build("herb_field", Vector2i(1, 2), "grow_clearheart")
	alchemy = _build("alchemy", Vector2i(4, 2), "make_clearheart")
	GameState.inventory.clearheart_grass = 0
	var preview: Dictionary = GameState.Cave.preview()
	stock = GameState.inventory.duplicate()
	world = GameState.cave.duplicate(true)
	var rng_state: int = GameState.rng.state
	_check(preview.produced.get("clearheart_pill", 0) == 0 and preview.consumed.is_empty(), "不串联当回合新产出")
	_check(not _row(preview, alchemy).reason.is_empty(), "缺料停产有原因")
	GameState.Cave.preview()
	_check(GameState.inventory == stock and GameState.cave == world and GameState.rng.state == rng_state, "预览不改库存、布局、随机状态")
	_fill()
	_check(ScheduleManager.confirm_schedule().ok, "培养后统一生产")
	_check(GameState.last_production == preview and GameState.inventory.clearheart_grass == 4, "首次预览与实际结算一致")
	stock = GameState.inventory.duplicate()
	_check(not GameState.Cave.build("house", Vector2i(1, 4)).ok, "结算后不能建造")
	_check(not GameState.Cave.move_building(field, Vector2i(2, 4)).ok, "结算后不能移动")
	_check(not GameState.Cave.set_recipe(field, "").ok, "结算后不能改任务")
	_check(not GameState.Cave.toggle_road(Vector2i(6, 3)).ok, "结算后不能改道路")
	GameState.phase = GameState.Phase.RESOLVING
	_check(not GameState.Cave.settle().ok and GameState.inventory == stock, "生产防止重复入库")
	GameState.phase = GameState.Phase.RESULTS
	GameState.advance_turn()
	_check(GameState.Cave.find_building(field).recipe == "grow_clearheart", "次回合保留生产任务")
	preview = GameState.Cave.preview()
	_check(preview.consumed.clearheart_grass == 4 and preview.produced.clearheart_pill == 2, "次回合可加工已有草")
	_fill()
	ScheduleManager.confirm_schedule()
	_check(GameState.last_production == preview and GameState.inventory.clearheart_pill == 2 and GameState.inventory.clearheart_grass == 4, "生产真实扣料并入库")
	_check(not ScheduleManager.execute_free_action("clearheart_pill").ok, "结果页不能立刻用新产品")
	GameState.advance_turn()
	GameState.pressure = 75
	_check(ScheduleManager.execute_free_action("clearheart_pill").ok, "生产物品回流培养")
	_check(GameState.pressure == 25 and GameState.inventory.clearheart_pill == 1, "加工品实际消耗并降低压力")
	_check(GameState.Cave.toggle_road(Vector2i(3, 3)).ok, "未入住时允许断路")
	_check(not _row(GameState.Cave.preview(), alchemy).reason.is_empty(), "断路建筑停产")
	var diagonal: Dictionary = GameState.Cave.connected_roads([Vector2i(1, 2)])
	_check(not diagonal.has(Vector2i(1, 2)), "道路斜角不连通")

	# 抢料顺序不由数组或位置决定，缺料也不会部分扣费。
	GameState.reset_game(42)
	var first := _build("alchemy", Vector2i(1, 2), "make_clearheart")
	var second := _build("alchemy", Vector2i(4, 2), "make_clearheart")
	GameState.inventory.clearheart_grass = 6
	GameState.cave.buildings.reverse()
	GameState.Cave.move_building(first, Vector2i(2, 4))
	preview = GameState.Cave.preview()
	_check(not _row(preview, first).outputs.is_empty() and _row(preview, second).outputs.is_empty(), "建造 ID 决定抢料次序")
	_check(preview.consumed.clearheart_grass == 4, "缺料整单停产，不扣剩余两份")
	var sword := ScheduleManager.activity_by_id("sword")
	sword.costs = {"clearheart_grass": 1}
	_fill()
	preview = GameState.Cave.preview()
	_check(preview.produced.is_empty(), "预览先扣培养计划材料")
	ScheduleManager.confirm_schedule()
	_check(GameState.last_production == preview and GameState.inventory.clearheart_grass == 3, "培养成本优先于生产且与预览一致")
	sword.erase("costs")

	GameState.reset_game(42)
	field = _build("herb_field", Vector2i(1, 2))
	_fill()
	stock = GameState.inventory.duplicate()
	var initial: Dictionary = GameState.base_stats.duplicate()
	var warning := ScheduleManager.confirm_schedule()
	_check(not warning.ok and warning.get("needs_confirmation", false), "未安排生产时提示")
	_check(GameState.inventory == stock and GameState.base_stats == initial and GameState.phase == GameState.Phase.FREE, "提示不进入结算或扣费")
	_check(ScheduleManager.confirm_schedule(true).ok, "可明确忽略闲置继续")
	_check(GameState.last_production.produced.is_empty(), "忽略提示不自动安排任务")
	GameState.reset_game()


## 实例化真实主场景，通过控件信号和地块输入走查；这不是全量真人鼠标/键盘自动化。
func _capture_ui(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var ui: Control = load("res://scenes/main.tscn").instantiate()
	if ui.get_script() == null:
		_check(false, "主界面脚本必须成功加载")
		ui.free()
		return
	add_child(ui)
	await _snapshot(directory.path_join("01-ready.png"))
	if ui.get("confirm_button") == null:
		_check(false, "主界面必须成功初始化")
		ui.queue_free()
		return
	_check(ui.confirm_button.disabled, "未安排时确认按钮禁用")
	_check(not ui.overlay.visible and ui.home.visible, "开场先展示家园而非日程表")
	_check(ui.portrait.texture != null and ui.portrait_stage == 0, "初始阶段立绘已加载")
	var sprite: Image = load("res://assets/daughter_stages.png").get_image()
	_check(sprite.get_pixel(0, 0).a < 0.01, "人物素材具有真实透明背景")
	ui.open_menu("attributes")
	await _snapshot(directory.path_join("01a-attributes.png"))
	_check(ui.attributes_page.is_visible_in_tree(), "人物详情按需展开")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	ui._unhandled_key_input(escape)
	_check(not ui.overlay.visible, "Escape 收起菜单")
	ui.open_menu("activities")
	await _snapshot(directory.path_join("01a-free-actions.png"))
	ui.free_buttons.visit.pressed.emit()
	_check(not ui.overlay.visible and GameState.energy == 8, "自由行动实际扣精力并返回场景")
	ui.schedule_button.pressed.emit()
	for i in range(GameState.schedule_slots):
		ui.selectors[i].item_selected.emit(i + 1)
	await _snapshot(directory.path_join("01b-planned.png"))
	var schedule_rect: Rect2 = ui.schedule_scroll.get_global_rect()
	for picker in ui.selectors:
		var tile: Control = picker.get_parent().get_parent().get_parent()
		_check(tile.get_global_rect().end.y <= schedule_rect.end.y, "默认三槽及成长信息在日程区域内完整可见")
	_check(not ui.confirm_button.disabled, "选择槽位后确认可用")
	ui.confirm_button.pressed.emit()
	await _snapshot(directory.path_join("02-results.png"))
	_check(ui.next_button.visible and not ui.confirm_button.visible, "结果界面交互")
	ui.next_button.pressed.emit()
	_check(GameState.phase == GameState.Phase.FREE, "下一回合按钮")
	_check(not ui.overlay.visible and ui.home.visible, "下一回合回到家园")
	for stage in [1, 2]:
		GameState.turn = 13 if stage == 1 else 37
		GameState.state_changed.emit()
		_check(ui.portrait_stage == stage and ui.portrait.texture.region.position.x == stage * 512, "立绘与成长阶段对应")
		await _snapshot(directory.path_join("02-stage-%d.png" % stage))
	ui.queue_free()
	await get_tree().process_frame
	GameState.config.rules.schedule_slots = 5
	GameState.reset_game()
	ui = load("res://scenes/main.tscn").instantiate()
	add_child(ui)
	get_window().size = Vector2i(960, 640)
	ui.open_menu("work")
	for i in range(GameState.schedule_slots):
		ui.selectors[i].item_selected.emit(1)
	await _snapshot(directory.path_join("03-five-slots-small.png"))
	ui.schedule_scroll.scroll_vertical = 1000
	await _snapshot(directory.path_join("03b-five-slots-last.png"))
	_check(ui.confirm_button.get_global_rect().end.y < ui.size.y, "五槽滚动不挤走确认按钮")
	GameState.config.rules.schedule_slots = 3
	ui.queue_free()
	await get_tree().process_frame
	GameState.reset_game(42)
	get_window().size = Vector2i(1280, 720)
	ui = load("res://scenes/main.tscn").instantiate()
	add_child(ui)
	ui.show_cave()
	var cave_ui: Control = ui.cave_view
	await _snapshot(directory.path_join("04-cave-empty.png"))
	_check(not cave_ui.inspector_panel.visible, "未选中建筑时收起详情")
	_check(cave_ui.inventory_label.get_parent().get_parent().size.y < 70, "库存 HUD 不因文字换行遮挡地块")
	var building_sprites: Image = load("res://assets/cave_buildings.png").get_image()
	_check(building_sprites.get_pixel(0, 0).a < 0.01 and cave_ui.board.sprites.size() == 8, "建筑图集透明且完整加载")
	for y in range(int(GameState.cave_config.height)):
		for x in range(int(GameState.cave_config.width)):
			var cell := Vector2i(x, y)
			_check(cave_ui.board.cell_at(cave_ui.board.cell_center(cell)) == cell, "等距投影中心命中原逻辑格")
	for entry in [["house", Vector2i(1, 4)], ["herb_field", Vector2i(1, 2)], ["alchemy", Vector2i(4, 2)], ["scarecrow", Vector2i(1, 1)], ["spring", Vector2i(3, 2)]]:
		for i in range(cave_ui.catalog.item_count):
			if cave_ui.catalog.get_item_metadata(i) == entry[0]:
				cave_ui.catalog.select(i)
				cave_ui.catalog.item_selected.emit(i)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = cave_ui.board.cell_center(entry[1])
		cave_ui.board._gui_input(click)
	_check(GameState.cave.buildings.size() == 5, "界面建造实际落地")
	cave_ui.mode_buttons.select.pressed.emit()
	var house_rect: Rect2 = cave_ui.board.structure_rect(Vector2(1, 4), Vector2.ONE)
	var roof_click := InputEventMouseButton.new()
	roof_click.button_index = MOUSE_BUTTON_LEFT
	roof_click.pressed = true
	roof_click.position = house_rect.position + house_rect.size * Vector2(0.5, 0.4)
	cave_ui.board._gui_input(roof_click)
	_check(cave_ui.selected_id == GameState.Cave.building_at(Vector2i(1, 4)).id, "点击屋顶可选中建筑，不要求点击地面")
	cave_ui.board.cell_clicked.emit(Vector2i(1, 2))
	cave_ui.recipe_picker.item_selected.emit(1)
	cave_ui.worker_pickers[0].item_selected.emit(1)
	_check(GameState.Cave.residents(GameState.cave) == 1, "界面御灵派工")
	await _snapshot(directory.path_join("05-cave-preview.png"))
	_check(not cave_ui.inspector_panel.get_global_rect().intersects(cave_ui.toolbar_panel.get_global_rect()), "详情不遮挡建造工具栏")
	_check(cave_ui.details.get_global_rect().end.y <= cave_ui.inspector_panel.get_global_rect().end.y - 8, "单工作槽的产出与乘区明细完整可见")
	var qingyun_index := -1
	for i in range(cave_ui.recipe_picker.item_count):
		if cave_ui.recipe_picker.get_item_metadata(i) == "grow_qingyun":
			qingyun_index = i
	_check(qingyun_index >= 0, "仅新增配置的青蕴草出现在任务选择器")
	if qingyun_index >= 0:
		cave_ui.recipe_picker.item_selected.emit(qingyun_index)
		_check(GameState.Cave.preview().produced.get("qingyun_grass", 0) > 0, "界面选择新药材后切换预测")
		await _snapshot(directory.path_join("05b-qingyun-preview.png"))
		cave_ui.recipe_picker.item_selected.emit(1)
	_fill()
	ui.show_home()
	ui.open_menu("work")
	ui.confirm_button.pressed.emit()
	await _snapshot(directory.path_join("06-idle-warning.png"))
	_check(ui.idle_dialog.visible and GameState.phase == GameState.Phase.FREE, "界面闲置确认")
	ui.idle_dialog.hide()
	ui.idle_dialog.canceled.emit()
	_check(ui.in_cave and not ui.overlay.visible, "取消提示返回洞天")
	cave_ui.board.cell_clicked.emit(Vector2i(4, 2))
	cave_ui.recipe_picker.item_selected.emit(1)
	cave_ui.worker_pickers[0].item_selected.emit(2)
	GameState.inventory.clearheart_grass = 4
	ui.show_home()
	ui.open_menu("work")
	ui.confirm_button.pressed.emit()
	await _snapshot(directory.path_join("07-cave-results.png"))
	_check(ui.next_button.get_global_rect().end.y <= ui.size.y - 16, "结果页操作不越出窗口底部")
	ui.show_cave()
	get_window().size = Vector2i(960, 640)
	await _snapshot(directory.path_join("08-cave-small.png"))
	_check(cave_ui.mode_buttons.build.disabled and cave_ui.recipe_picker.disabled, "结算后界面锁定管理")
	ui.next_button.pressed.emit()
	_check(not cave_ui.mode_buttons.build.disabled and GameState.Cave.residents(GameState.cave) == 2, "下一回合恢复管理且保留派工")
	ui.show_cave()
	_check(GameState.Cave.build("grove", Vector2i(6, 0)).ok, "林场视觉例子")
	_check(GameState.Cave.build("quarry", Vector2i(5, 4)).ok, "采石场视觉例子")
	cave_ui.board.cell_clicked.emit(Vector2i(7, 5))
	get_window().size = Vector2i(1600, 900)
	await _snapshot(directory.path_join("09-cave-all-buildings.png"))
	ui.show_home()
	await _snapshot(directory.path_join("10-home-wide.png"))
	ui.queue_free()
	await get_tree().process_frame
	ui_completed = true


## 等容器完成布局且本帧渲染结束再读像素；此流程需要有图形输出，不能加 --headless。
func _snapshot(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var frame := get_viewport().get_texture().get_image()
	_check(not frame.is_empty(), "界面渲染非空")
	_check(frame.save_png(path) == OK, "导出截图")
	print("UI_SNAPSHOT: ", path)
