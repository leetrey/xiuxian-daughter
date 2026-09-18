extends Node

# 一份场景覆盖培养、洞天、剧情查询与执行。--ui-snapshot=/tmp/目录 可导出真实渲染截图。
# 这些是程序回归例子，含默认数值断言；作者仅检查填表应运行 validate_content.tscn。
var failures := 0
var ui_completed := false
var story_completed := false
var story_flow_completed := false
var story_ui_completed := false
var review_regressions_completed := false
var blueprints_completed := false
var blueprint_ui_completed := false


## 默认只跑规则；带截图参数时才创建界面。退出码便于终端判断，不只依赖最后一行文字。
func _ready() -> void:
	if not GameState.configs_validated or not GameState.config_error.is_empty():
		printerr("SMOKE_TEST_FAILED: 配置初始化未完成")
		get_tree().quit(1)
		return
	# 旧规则用空剧情表隔离前置对话；下方另用真实剧情流程验证集成，不在正式代码加跳过开关。
	var story_config: Dictionary = GameState.story_config
	GameState.story_config = {"version": 1, "nodes": []}
	_run_content_rules()
	_run_review_regressions()
	_check(review_regressions_completed, "配置与贴图回归必须完整执行，脚本中断不得报成功")
	_run_story_rules(story_config)
	_check(story_completed, "剧情规则测试必须完整执行，脚本中断不得报成功")
	_run_rules()
	_run_cave_rules()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ui-snapshot="):
			await _capture_ui(argument.trim_prefix("--ui-snapshot="))
			_check(ui_completed, "真实窗口走查必须完整执行，脚本中断不得报成功")
	GameState.story_config = story_config
	_run_story_flow()
	_check(story_flow_completed, "剧情执行测试必须完整执行")
	_run_blueprints()
	_check(blueprints_completed, "图纸规则测试必须完整执行")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ui-snapshot="):
			await _capture_story_ui(argument.trim_prefix("--ui-snapshot="))
			_check(story_ui_completed, "剧情窗口走查必须完整执行")
			await _capture_blueprint_ui(argument.trim_prefix("--ui-snapshot="))
			_check(blueprint_ui_completed, "图纸窗口走查必须完整执行")
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


## 坏配置只改深复制的内存表；保留 Variant 返回值检查，异常中断不能被当成校验通过。
func _run_review_regressions() -> void:
	var config: Dictionary = GameState.config.duplicate(true)
	var cases: Array[Dictionary] = []
	for value in [null, "bad", [], {}, true]:
		cases.append({"keys": ["pressure_bands", 0], "value": value, "error": "pressure_bands[0]"})
	for field in ["min", "max_exclusive"]:
		for value in [null, "20", true, [], {}, -1, 0.5, 102, INF, NAN]:
			cases.append({"keys": ["pressure_bands", 0, field], "value": value, "error": "pressure_bands[0]." + field})
	for value in [null, "bad", {}, true, [], [0.5, 0.5], [0.3, 0.3, 0.3]]:
		cases.append({"keys": ["pressure_bands", 0, "probabilities"], "value": value, "error": "pressure_bands[0].probabilities"})
	for value in [null, "0.34", true, [], {}, -0.1, 1.1, INF, NAN]:
		cases.append({"keys": ["pressure_bands", 0, "probabilities", 0], "value": value, "error": "probabilities[0]"})
	for value in [null, "bad", [], {}]:
		cases.append({"keys": ["outcomes", 0], "value": value, "error": "outcomes[0]"})
	for value in [null, "2.5", true, [], {}, -1, INF, NAN]:
		cases.append({"keys": ["outcomes", 0, "multiplier"], "value": value, "error": "outcomes[0].multiplier"})
	for value in [null, "bad", [], {}]:
		cases.append({"keys": ["groups", "physique"], "value": value, "error": "groups.physique"})
	cases.append({"keys": ["groups", "physique", "stats"], "value": [], "error": "groups.physique.stats"})
	cases.append({"keys": ["rules", "phase_turns", 0], "value": "12", "error": "rules.phase_turns"})
	cases.append({"keys": ["rules", "initial_pressure"], "value": {}, "error": "rules.initial_pressure"})
	cases.append({"keys": ["rules", "allow_repeat"], "value": "true", "error": "rules.allow_repeat"})
	cases.append({"keys": ["activities", 0, "growth", "power"], "value": {}, "error": "activities.sword.growth.power"})
	for case in cases:
		GameState.config = config.duplicate(true)
		var parent: Variant = GameState.config
		for index in range(case.keys.size() - 1):
			parent = parent[case.keys[index]]
		parent[case.keys.back()] = case.value
		var error: Variant = GameState.validate_config()
		_check(error is String and error.contains(case.error), "畸形配置返回字段错误: " + str(case.keys))
	for field in ["min", "max_exclusive", "probabilities"]:
		GameState.config = config.duplicate(true)
		GameState.config.pressure_bands[0].erase(field)
		var error: Variant = GameState.validate_config()
		_check(error is String and error.contains("pressure_bands[0]." + field), "缺少压力档字段: " + field)
	for boundary in [19, 21]:
		GameState.config = config.duplicate(true)
		GameState.config.pressure_bands[1].min = boundary
		_check(GameState.validate_config().contains("pressure_bands[1]"), "压力档重叠或间断仍被拒绝")
	GameState.config = config.duplicate(true)
	GameState.config.pressure_bands.back().max_exclusive = 100
	_check(not GameState.validate_config().is_empty(), "压力档必须覆盖压力 100")
	GameState.config = config
	_check(GameState.validate_config().is_empty(), "恢复后的培养表正常通过")

	var building: Dictionary = GameState.cave_config.buildings.herb_field
	var original_index: int = int(building.sprite_index)
	for value in [-1, 8, 1.5, "1", true, null, [], {}, INF, NAN]:
		building.sprite_index = value
		var error: Variant = GameState.validate_cave_config()
		_check(error is String and error.contains("buildings.herb_field.sprite_index"), "建筑图格拒绝错误类型及越界")
	for index in range(8):
		building.sprite_index = index
		_check(GameState.validate_cave_config().is_empty(), "合法建筑图格可配置")
	building.erase("sprite_index")
	_check(GameState.validate_cave_config().is_empty(), "旧建筑允许省略图格")
	var board: Control = load("res://scripts/cave_board.gd").new()
	_check(board._sprite_index(building) == 1, "未配置图格仍沿用同类映射")
	building.sprite_index = 6
	_check(board._sprite_index(building) == 6, "显式图格优先于类别与工作类型")
	building.sprite_index = original_index
	board.free()

	var visuals = preload("res://scripts/ui_theme.gd")
	var sheet := GradientTexture2D.new()
	sheet.width = 900
	sheet.height = 600
	for stage in range(3):
		var portrait: AtlasTexture = visuals.daughter_portrait(stage, sheet)
		_check(portrait.region == Rect2(stage * 300, 0, 300, 600), "非 512x1024 立绘按真实尺寸三等分")
		_check(portrait.atlas == sheet and portrait.filter_clip, "保留原纹理引用与图格裁切")
	sheet.width = 800
	sheet.height = 600
	for index in range(8):
		var sprite: AtlasTexture = visuals.atlas_cell(sheet, GameState.Content.BUILDING_ATLAS_GRID, index)
		_check(sprite.region == Rect2((index % 4) * 200, (index / 4) * 300, 200, 300), "建筑图集不依赖 384x512 像素")

	# 提前标记下一检查点，刻意让 begin() 无通知早退，验证 advance_turn 自己负责刷新。
	GameState.reset_game(42)
	var notifications: Array[int] = []
	var listener := func() -> void: notifications.append(GameState.phase)
	GameState.state_changed.connect(listener)
	GameState.phase = GameState.Phase.RESULTS
	GameState.energy = 0
	GameState.story.checked["2:turn_start"] = true
	_check(GameState.advance_turn(), "已处理的剧情检查点不阻止回合推进")
	_check(notifications == [GameState.Phase.FREE] and GameState.turn == 2 and GameState.energy == 10, "剧情早退时仍通知最终回合状态")
	notifications.clear()
	GameState.phase = GameState.Phase.RESULTS
	_check(GameState.advance_turn() and not notifications.is_empty(), "正常新回合也发送刷新通知")
	notifications.clear()
	GameState.turn = GameState.total_turns()
	GameState.phase = GameState.Phase.RESULTS
	_check(GameState.advance_turn() and notifications == [GameState.Phase.FINISHED], "最终回合发送结束通知")
	notifications.clear()
	_check(not GameState.advance_turn() and notifications.is_empty(), "无效推进不发送变更通知")
	GameState.state_changed.disconnect(listener)
	GameState.reset_game(42)
	review_regressions_completed = true


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


## 测试和正式加载都提供完整引用表，避免合法的新奖励被误判为未知 ID。
func _validate_story(config: Dictionary) -> String:
	return GameState.Story.validate_config(config, GameState.config.items, GameState.config.activities, GameState.cave_config.buildings)


## 剧情查询只读；完成记录由测试显式传入，不把候选查询冒充正式剧情推进。
func _run_story_rules(source: Dictionary) -> void:
	_check(_validate_story(source).is_empty(), "剧情示例配置有效")
	_check(_validate_story({"version": 1, "nodes": []}).is_empty(), "允许暂不填写剧情")
	var bad_root_fields := {"version": 2, "nodes": {}, "note": false, "rewards": {}}
	for field in bad_root_fields:
		var changed: Dictionary = source.duplicate(true)
		changed[field] = bad_root_fields[field]
		_check(not _validate_story(changed).is_empty(), "剧情根字段校验 " + str(field))
	var bad_node_fields := {
		"id": " ", "name": "", "kind": "unknown", "enabled": 1, "order": true,
		"checkpoints": ["before_battle"], "requires_completed": "example_herb_conversation",
		"excludes_completed": ["missing"], "conditions": [], "variants": [], "rewards": [],
	}
	for field in bad_node_fields:
		var changed: Dictionary = source.duplicate(true)
		changed.nodes[0][field] = bad_node_fields[field]
		_check(not _validate_story(changed).is_empty(), "剧情节点字段校验 " + str(field))
	for conditions in [
		{"turn_min": 0}, {"turn_max": 1.5}, {"turn_min": 3, "turn_max": 2},
		{"total_a_gt": -1}, {"total_a_gt": "1000"}, {"total_a_gt": true},
		{"growth_phases": []}, {"growth_phases": [0, 3]}, {"growth_phases": [1, 1]},
		{"growth_phases": [true]}, {"inventory_min": {"missing": 1}},
		{"inventory_min": {"wood": 0}}, {"inventory_min": {"wood": 1.5}}, {"total_b_gt": 10},
	]:
		var changed: Dictionary = source.duplicate(true)
		changed.nodes[0].conditions = conditions
		_check(_validate_story(changed).contains("conditions"), "剧情条件错误定位到字段")
	for variant in [
		{}, {"lines": []}, {"lines": [{"speaker": 1, "text": "台词"}]},
		{"lines": [{"speaker": "女儿", "text": " "}]},
		{"lines": [{"speaker": "女儿", "text": "台词", "choice": "暂不支持"}]},
	]:
		var changed: Dictionary = source.duplicate(true)
		changed.nodes[0].variants["0"] = variant
		_check(_validate_story(changed).contains("variants.0"), "剧情对话错误定位到版本")
	for portrait in [
		{"texture": "res://assets/missing-story-test.png"},
		{"texture": "res://scenes/main.tscn"},
		{"texture": "res://assets/daughter_stages.png", "region": [0, 0, 0, 1024]},
		{"texture": "res://assets/daughter_stages.png", "region": [1024, 0, 513, 1024]},
	]:
		var changed: Dictionary = source.duplicate(true)
		changed.nodes[0].variants["0"].portrait = portrait
		_check(_validate_story(changed).contains("portrait"), "立绘引用和裁剪校验")
	var changed: Dictionary = source.duplicate(true)
	changed.nodes[0].variants.erase("2")
	_check(_validate_story(changed).contains("variants.2"), "主线必须填写三阶段表现")
	changed = source.duplicate(true)
	changed.nodes[1].variants.erase("default")
	_check(_validate_story(changed).contains("variants.default"), "支线公共表现不能缺失")
	changed = source.duplicate(true)
	changed.nodes.append(changed.nodes[0].duplicate(true))
	_check(_validate_story(changed).contains("ID 重复"), "同一逻辑节点不能重复定义")
	for prerequisites in [["missing"], ["example_breakthrough"], ["example_herb_conversation", "example_herb_conversation"]]:
		changed = source.duplicate(true)
		changed.nodes[0].requires_completed = prerequisites
		_check(_validate_story(changed).contains("requires_completed"), "拒绝未知、自身或重复前置")
	changed = source.duplicate(true)
	changed.nodes[0].requires_completed = ["example_herb_conversation"]
	changed.nodes[0].excludes_completed = ["example_herb_conversation"]
	_check(not _validate_story(changed).is_empty(), "前置与排除条件不能直接矛盾")
	changed.nodes[0].excludes_completed = []
	changed.nodes[1].requires_completed = ["example_breakthrough"]
	_check(_validate_story(changed).contains("循环"), "拒绝前置依赖环")

	GameState.reset_game(42)
	GameState.equipment_bonuses.weapon.power = 10000
	var rng_state: int = GameState.rng.state
	var stats: Dictionary = GameState.base_stats.duplicate(true)
	var stock: Dictionary = GameState.inventory.duplicate(true)
	var context := GameState.story_context()
	_check(GameState.Story.candidates(source, context, "turn_start", "main").is_empty(), "装备 B 不能满足剧情 A 门槛")
	_check(GameState.Story.candidates(source, context, "turn_start", "side") == ["example_herb_conversation"], "主支线候选分开查询")
	_check(GameState.Story.candidates(source, context, "unknown", "main").is_empty(), "未知检查点不返回候选")
	context.base_stats = {"power": 1000}
	_check(GameState.Story.candidates(source, context, "turn_end", "main").is_empty(), "剧情严格大于门槛，等于不触发")
	context.base_stats.power = 1001
	_check(GameState.Story.candidates(source, context, "turn_end", "main") == ["example_breakthrough"], "超过 A 门槛成为候选")
	context.completed.append("example_breakthrough")
	for stage in range(3):
		context.growth_phase = stage
		_check(GameState.Story.candidates(source, context, "turn_end", "main").is_empty(), "换成长阶段不能重复完成同一逻辑 ID")
		var variant: Dictionary = GameState.Story.presentation(source, "example_breakthrough", stage)
		_check(variant.portrait.region[0] == stage * 512, "三阶段选择对应立绘区域")
		variant.lines[0].text = "不应写回配置"
		_check(source.nodes[0].variants[str(stage)].lines[0].text != "不应写回配置", "表现副本不污染配置")
		_check(GameState.Story.presentation(source, "example_herb_conversation", stage) == source.nodes[1].variants.default, "支线使用公共版本")
	_check(GameState.Story.presentation(source, "missing", 0).is_empty(), "未知节点无表现")
	_check(GameState.Story.presentation(source, "example_breakthrough", 3).is_empty(), "未知成长阶段不能选错版本")
	changed = source.duplicate(true)
	changed.nodes[1].variants["1"] = {"lines": [{"speaker": "女儿", "text": "支线中期覆盖示例"}]}
	_check(_validate_story(changed).is_empty(), "支线可以增加阶段覆盖文本")
	_check(GameState.Story.presentation(changed, "example_herb_conversation", 1).lines[0].text == "支线中期覆盖示例", "阶段覆盖优先于公共版本")
	_check(GameState.Story.presentation(changed, "example_herb_conversation", 2) == source.nodes[1].variants.default, "未覆盖阶段仍使用公共版本")
	context.inventory.clearheart_grass = 0
	_check(GameState.Story.candidates(source, context, "turn_start", "side").is_empty(), "库存条件按真实数量判断")
	_check(GameState.base_stats == stats and GameState.inventory == stock and GameState.rng.state == rng_state, "剧情快照查询不修改属性库存随机源")
	_check(GameState.story_config.nodes.is_empty() and GameState.plan.count("") == 3, "剧情查询不写配置或日程")

	# 用内存例子验证前置、排除、时段和稳定排序，不向正式内容表扩充剧情。
	changed = source.duplicate(true)
	changed.nodes[1] = changed.nodes[0].duplicate(true)
	changed.nodes[1].id = "a_followup"
	changed.nodes[1].requires_completed = ["example_breakthrough"]
	context = GameState.story_context()
	context.base_stats = {"power": 2000}
	_check(GameState.Story.candidates(changed, context, "turn_start", "main") == ["example_breakthrough"], "前置成为候选不等于完成，不自动串联")
	context.completed = ["example_breakthrough"]
	_check(GameState.Story.candidates(changed, context, "turn_start", "main") == ["a_followup"], "显式完成前置后才可查询后续")
	context.completed = []
	changed.nodes[1].requires_completed = []
	_check(GameState.Story.candidates(changed, context, "turn_start", "main") == ["a_followup", "example_breakthrough"], "同 order 时按 ID 确定顺序")
	changed.nodes[1].order = 200
	_check(GameState.Story.candidates(changed, context, "turn_start", "main") == ["example_breakthrough", "a_followup"], "不同 order 先按数值排序")
	changed.nodes[1].excludes_completed = ["example_breakthrough"]
	context.completed = ["example_breakthrough"]
	_check(GameState.Story.candidates(changed, context, "turn_start", "main").is_empty(), "已完成排除节点会阻止触发")
	var node: Dictionary = changed.nodes[0]
	node.conditions = {"turn_min": 3, "turn_max": 5, "growth_phases": [1]}
	context.completed = []
	context.growth_phase = 1
	for turn in [2, 3, 5, 6]:
		context.turn = turn
		_check(GameState.Story.blocking_reasons(node, context, "turn_start", "main").is_empty() == (turn >= 3 and turn <= 5), "允许回合区间包含两端")
	context.turn = 3
	context.growth_phase = 0
	_check(not GameState.Story.blocking_reasons(node, context, "turn_start", "main").is_empty(), "成长阶段限制独立于回合")
	node.conditions = {}
	node.enabled = false
	_check(not GameState.Story.blocking_reasons(node, context, "turn_start", "main").is_empty(), "已禁用节点不成为候选")

	# 预测出的药草不能满足剧情库存门槛；真实生产入库后才可以。
	GameState.reset_game(42)
	_build("herb_field", Vector2i(1, 2), "grow_qingyun")
	changed = source.duplicate(true)
	changed.nodes[0].conditions = {"inventory_min": {"qingyun_grass": 1}}
	_check(GameState.Cave.preview().produced.qingyun_grass > 0, "存在预计收成")
	_check(GameState.Story.candidates(changed, GameState.story_context(), "turn_end", "main").is_empty(), "未入库预测不能满足剧情条件")
	_fill()
	_check(ScheduleManager.confirm_schedule().ok, "剧情库存测试先完成正常培养生产")
	stock = GameState.inventory.duplicate(true)
	_check(GameState.Story.candidates(changed, GameState.story_context(), "turn_end", "main") == ["example_breakthrough"], "生产入库后剧情条件可满足")
	_check(GameState.inventory == stock, "满足持有条件不等于消耗材料")
	GameState.reset_game()
	story_completed = true


func _story_fixture(id: String, kind: String = "main", checkpoint: String = "turn_start") -> Dictionary:
	var node: Dictionary = GameState.story_config.nodes[0].duplicate(true)
	node.id = id
	node.name = id
	node.kind = kind
	node.order = 100
	node.checkpoints = [checkpoint]
	node.conditions = {}
	node.requires_completed = []
	node.excludes_completed = []
	node.costs = {}
	node.rewards = {}
	if kind == "side":
		node.variants = {"default": node.variants["0"].duplicate(true)}
	return node


func _finish_active_story() -> void:
	if GameState.story.active.is_empty():
		_check(false, "需要一条正在播放的剧情")
		return
	var id: String = GameState.story.active.node.id
	var remaining: int = GameState.story.active.presentation.lines.size() - int(GameState.story.active.line)
	for i in range(remaining):
		var result: Dictionary = GameState.StoryFlow.advance(id, int(GameState.story.active.line))
		_check(result.ok, "逐句推进剧情: " + str(result.message))
		if not result.ok:
			return


## 真实检查点与提交路径：主线 -> 支线；结束逐项重查；成本与奖励不在 UI 刷新中执行。
func _run_story_flow() -> void:
	var original: Dictionary = GameState.story_config
	var activities: Array = GameState.config.activities.duplicate(true)
	var first := _story_fixture("a_start")
	first.costs = {"wood": 2}
	first.rewards = {"items": {"clearheart_grass": 1}, "activities": ["music"], "unlock_timing": "next_turn"}
	var follow := _story_fixture("b_follow")
	follow.requires_completed = ["a_start"]
	var competition := _story_fixture("c_competition")
	competition.costs = {"wood": 35, "stone": 1}
	var side := _story_fixture("d_side", "side")
	side.order = 0
	side.rewards = {"activities": ["craft"], "unlock_timing": "immediate"}
	var from_side := _story_fixture("e_from_side")
	from_side.requires_completed = ["d_side"]
	from_side.checkpoints = ["turn_start", "turn_end"]
	var ending := _story_fixture("f_end", "main", "turn_end")
	ending.order = 0
	ending.costs = {"qingyun_grass": 1}
	ending.rewards = {"items": {"clearheart_pill": 1}}
	var config := {"version": 1, "nodes": [first, follow, competition, side, from_side, ending]}
	_check(_validate_story(config).is_empty(), "可执行剧情配置和奖励引用通过校验")
	for reward in [{"items": {"missing": 1}}, {"items": {"wood": 0}}, {"activities": ["missing"]}, {"activities": ["music", "music"]}, {"unlock_timing": "later"}, {"land": 2}]:
		var invalid: Dictionary = config.duplicate(true)
		invalid.nodes[0].rewards = reward
		_check(_validate_story(invalid).contains("rewards"), "无效奖励不会静默接受")
	var invalid: Dictionary = config.duplicate(true)
	invalid.nodes[0].costs = {"wood": 1.5}
	_check(_validate_story(invalid).contains("costs"), "剧情费用必须是合法物品整数")
	GameState.story_config = config
	ScheduleManager.activity_by_id("music").requires_unlock = true
	ScheduleManager.activity_by_id("craft").requires_unlock = true
	GameState.reset_game(42)
	var stock: Dictionary = GameState.inventory.duplicate(true)
	var rng_state: int = GameState.rng.state
	_check(GameState.phase == GameState.Phase.STORY and GameState.story.active.node.id == "a_start", "开局先播放主线，支线低 order 不越过主线")
	_check(not GameState.advance_turn() and not ScheduleManager.confirm_schedule().ok, "对话期间不能推进或确认培养")
	_check(not ScheduleManager.assign_slot(0, "sword").is_empty() and not ScheduleManager.execute_free_action("visit").ok, "对话期间不能安排日程或消耗精力")
	_check(not GameState.Cave.build("house", Vector2i(1, 4)).ok and not GameState.Cave.toggle_road(Vector2i(6, 3)).ok, "对话期间不能建造改路")
	_check(GameState.inventory == stock and GameState.story.completed.is_empty(), "开始展示不扣材料或完成节点")
	_check(GameState.StoryFlow.advance("a_start", 0).ok, "第一句可以推进")
	_check(not GameState.StoryFlow.advance("a_start", 0).ok, "重复旧行请求不推进")
	GameState.inventory.wood = 1
	_check(not GameState.StoryFlow.advance("a_start", 1).ok and GameState.story.completed.is_empty(), "末句提交前重新校验，失败不完成节点")
	_check(GameState.inventory.clearheart_grass == stock.clearheart_grass and GameState.unlocked_activities.is_empty(), "费用不足不发奖励或解锁")
	GameState.inventory.wood = stock.wood
	_check(GameState.StoryFlow.advance("a_start", 1).ok, "材料足够后原节点可完成")
	_check(GameState.inventory.wood == int(stock.wood) - 2 and GameState.inventory.clearheart_grass == int(stock.clearheart_grass) + 1, "完成时准确扣费发奖一次")
	_check(GameState.story.active.node.id == "b_follow" and GameState.story.completed.size() == 1, "完成前置后同类剧情重新查找")
	_check(not GameState.StoryFlow.advance("a_start", 1).ok, "已完成节点不能重复领取")
	_check(not ScheduleManager.availability(ScheduleManager.activity_by_id("music")).is_empty(), "下回合解锁尚不可用")
	_finish_active_story()
	_check(GameState.story.active.node.id == "d_side", "主线耗尽后处理支线，缺料主线不部分扣费")
	_check(GameState.inventory.stone == stock.stone and not GameState.story.completed.has("c_competition"), "材料竞争节点缺料不扣其他材料")
	_finish_active_story()
	_check(GameState.phase == GameState.Phase.FREE and GameState.story.completed.size() == 3, "读完开始剧情才进入自由阶段")
	_check(ScheduleManager.availability(ScheduleManager.activity_by_id("craft")).is_empty(), "即时活动解锁在对话后可用")
	_check(not GameState.story.completed.has("e_from_side"), "支线新开放的主线留给下一检查点，不倒序回跳")
	_check(not GameState.StoryFlow.begin("turn_start") and GameState.rng.state == rng_state, "同回合同检查点不重复，剧情不使用培养随机数")
	_build("herb_field", Vector2i(1, 2), "grow_qingyun")
	_fill()
	_check(ScheduleManager.confirm_schedule().ok and GameState.phase == GameState.Phase.STORY, "培养生产之后进入结束剧情")
	_check(GameState.story.active.node.id == "f_end" and GameState.inventory.qingyun_grass == 4, "当回合入库资源满足剧情成本，但读完之前不扣")
	var production: Dictionary = GameState.last_production.duplicate(true)
	_check(not ScheduleManager.confirm_schedule().ok and not GameState.advance_turn(), "结束剧情期间不可重复生产或跳下一回合")
	_finish_active_story()
	_check(GameState.inventory.qingyun_grass == 3 and GameState.inventory.clearheart_pill == 1, "生产后剧情真实消耗与奖励")
	_check(GameState.story.active.node.id == "e_from_side", "结束检查点承接开始支线开放的主线")
	_finish_active_story()
	_check(GameState.phase == GameState.Phase.RESULTS and GameState.last_production == production, "剧情结束返回札记，不重算生产报告")
	_check(GameState.advance_turn(), "完成结束剧情后可以进入下一回合")
	_check(GameState.phase == GameState.Phase.FREE and GameState.story.active.is_empty(), "已完成剧情不会在新回合重播")
	_check(GameState.unlocked_activities.has("music") and GameState.pending_activity_unlocks.is_empty(), "下回合开始时激活待解锁活动")
	_check(ScheduleManager.assign_slot(0, "music").is_empty(), "解锁日程实际可安排")
	GameState.turn = 12
	GameState.phase = GameState.Phase.RESULTS
	GameState.advance_turn()
	_check(GameState.growth_phase() == 1 and GameState.story.active.is_empty(), "切成长阶段不重复完成同一节点")
	GameState.turn = 60
	GameState.phase = GameState.Phase.RESULTS
	GameState.advance_turn()
	_check(GameState.phase == GameState.Phase.FINISHED, "最终回合仍可正常结束")
	GameState.reset_game(42)
	_check(GameState.story.completed.is_empty() and GameState.unlocked_activities.is_empty() and GameState.pending_activity_unlocks.is_empty(), "新局清空完成记录与解锁状态")
	GameState.story_config = original
	GameState.config.activities = activities
	GameState.reset_game(42)
	story_flow_completed = true


## 图纸是可重复使用的资格；只改内存例子，不把正式剧情或初始解锁写死进测试入口。
func _run_blueprints() -> void:
	var original_story: Dictionary = GameState.story_config
	var initial: Array = GameState.cave_config.initial_blueprints.duplicate()
	var immediate := _story_fixture("blueprint_immediate")
	immediate.rewards = {"blueprints": ["herb_field"], "unlock_timing": "immediate"}
	var delayed := _story_fixture("blueprint_delayed", "main", "turn_end")
	delayed.rewards = {"blueprints": ["herb_field"]}
	for value in [null, "house", {}, [null], [1], [{}], ["missing"], ["house", "house"]]:
		GameState.cave_config.initial_blueprints = value
		_check(GameState.validate_cave_config().contains("initial_blueprints"), "初始图纸拒绝畸形、未知和重复 ID")
	GameState.cave_config.erase("initial_blueprints")
	_check(GameState.validate_cave_config().contains("initial_blueprints"), "缺少初始图纸列表明确报错，不偷偷全开放")
	GameState.cave_config.initial_blueprints = []
	_check(GameState.validate_cave_config().is_empty(), "允许从无图纸开局")
	for value in [null, "house", {}, [null], [1], [{}], ["missing"], ["house", "house"]]:
		var invalid: Dictionary = immediate.duplicate(true)
		invalid.rewards.blueprints = value
		var error: Variant = _validate_story({"version": 1, "nodes": [invalid]})
		_check(error is String and error.contains("rewards.blueprints"), "剧情图纸奖励引用与类型校验")
	_check(_validate_story({"version": 1, "nodes": [immediate, delayed]}).is_empty(), "合法图纸奖励无需物品定义")

	GameState.cave_config.initial_blueprints = ["house"]
	GameState.story_config = {"version": 1, "nodes": []}
	GameState.reset_game(42)
	var stock: Dictionary = GameState.inventory.duplicate(true)
	var cave: Dictionary = GameState.cave.duplicate(true)
	var result: Dictionary = GameState.Cave.build("herb_field", Vector2i(1, 2))
	_check(not result.ok and str(result.message).contains("图纸"), "材料充足但缺图纸仍不能建造")
	_check(GameState.inventory == stock and GameState.cave == cave, "缺图纸不扣材料、不生成实例或占用 ID")
	_check(not GameState.Cave.build("missing", Vector2i(1, 2)).ok, "未知建筑仍被拒绝")
	_check(GameState.unlocked_blueprints == ["house"] and GameState.story.completed.is_empty(), "初始图纸不代表剧情完成")

	GameState.story_config = {"version": 1, "nodes": [immediate]}
	GameState.reset_game(42)
	_check(not GameState.unlocked_blueprints.has("herb_field"), "展示对话未结束时不提前发图纸")
	var rng_state: int = GameState.rng.state
	_finish_active_story()
	_check(GameState.unlocked_blueprints.has("herb_field") and GameState.pending_blueprint_unlocks.is_empty(), "即时图纸完成对话后生效")
	_check(GameState.inventory == stock and GameState.cave == cave and GameState.rng.state == rng_state, "获得图纸不扣材料、不扩土地、不生成建筑、不消耗随机数")
	_check(GameState.cave_config.initial_blueprints == ["house"], "奖励不污染初始图纸模板")
	var first := _build("herb_field", Vector2i(1, 2), "grow_clearheart")
	_build("herb_field", Vector2i(4, 2), "grow_clearheart")
	_check(GameState.unlocked_blueprints.count("herb_field") == 1, "同图纸反复造两栋，不按张数扣除")
	_check(GameState.inventory.wood == stock.wood - 8 and GameState.inventory.stone == stock.stone - 4, "每栋独立扣实际建筑材料")
	_check(GameState.Cave.preview().produced.clearheart_grass == 8, "有图纸建造并安排后当回合即可生产")
	_check(GameState.Cave.move_building(first, Vector2i(1, 4)).ok, "已建建筑可以正常移动")
	var built_world: Dictionary = GameState.cave.duplicate(true)
	GameState.inventory.wood = 0
	_check(not GameState.Cave.build("herb_field", Vector2i(4, 4)).ok and GameState.cave == built_world, "有图纸仍要满足建材条件")
	_check(GameState.unlocked_blueprints.has("herb_field"), "失败建造不会消耗图纸")
	_check(not GameState.Cave.build("herb_field", Vector2i(7, 5)).ok, "图纸不能越过现有土地边界")

	GameState.story_config = {"version": 1, "nodes": [delayed]}
	GameState.reset_game(42)
	_fill()
	_check(ScheduleManager.confirm_schedule().ok and GameState.phase == GameState.Phase.STORY, "回合末图纸奖励进入剧情")
	_finish_active_story()
	_check(GameState.pending_blueprint_unlocks.get("herb_field") == 2 and not GameState.unlocked_blueprints.has("herb_field"), "图纸默认下回合生效，与已掌握状态分开")
	_check(GameState.Cave.blueprint_error("herb_field").contains("下回合"), "待生效图纸有独立不可建原因")
	GameState.StoryFlow.apply_pending_unlocks()
	_check(not GameState.unlocked_blueprints.has("herb_field"), "本回合调用激活入口不会提前解锁")
	_check(GameState.inventory == stock and GameState.story.results[0].rewards.blueprints == ["herb_field"], "奖励报告记录图纸而不是库存物品")
	_check(GameState.advance_turn() and GameState.Cave.blueprint_error("herb_field").is_empty(), "下一回合建造资格生效")
	_check(GameState.pending_blueprint_unlocks.is_empty(), "到期后清除待生效记录")

	# 同一图纸的重复预约不推迟生效；即时奖励可提前激活，已拥有则不重复发放。
	var pending: Dictionary = immediate.duplicate(true)
	pending.rewards.unlock_timing = "next_turn"
	var duplicate: Dictionary = pending.duplicate(true)
	duplicate.id = "blueprint_duplicate"
	duplicate.requires_completed = [pending.id]
	var promote: Dictionary = immediate.duplicate(true)
	promote.id = "blueprint_promote"
	promote.requires_completed = [duplicate.id]
	GameState.story_config = {"version": 1, "nodes": [pending, duplicate, promote]}
	GameState.reset_game(42)
	_finish_active_story()
	_finish_active_story()
	_check(GameState.pending_blueprint_unlocks == {"herb_field": 2} and GameState.story.results[1].rewards.blueprints.is_empty(), "重复图纸不重复预约或报告新增")
	_finish_active_story()
	_check(GameState.pending_blueprint_unlocks.is_empty() and GameState.unlocked_blueprints.count("herb_field") == 1, "即时奖励激活待生效图纸且只有一份资格")
	GameState.cave_config.initial_blueprints = ["house", "herb_field"]
	GameState.story_config = {"version": 1, "nodes": [immediate]}
	GameState.reset_game(42)
	_finish_active_story()
	_check(GameState.story.completed.has(immediate.id) and GameState.story.results[0].rewards.blueprints.is_empty(), "已持有图纸仍可推进故事，不重复报告解锁")
	_check(GameState.inventory == stock, "重复图纸不扣资源、不产生补偿物品")
	# 不把普通物品事件费用误当成图纸研究费；已有图纸不豁免节点显式配置的 costs。
	var paid_event: Dictionary = immediate.duplicate(true)
	paid_event.id = "event_with_existing_blueprint"
	paid_event.costs = {"wood": 2}
	GameState.story_config = {"version": 1, "nodes": [paid_event]}
	GameState.reset_game(42)
	_check(GameState.StoryFlow.advance(str(paid_event.id), 0).ok, "已有图纸仍需逐句完成事件")
	GameState.inventory.wood = 1
	_check(not GameState.StoryFlow.advance(str(paid_event.id), 1).ok and GameState.story.completed.is_empty(), "已有图纸不能绕过普通剧情费用重查")
	_check(GameState.inventory.wood == 1 and GameState.unlocked_blueprints.count("herb_field") == 1, "费用不足不影响库存或已掌握资格")
	GameState.inventory.wood = stock.wood
	_check(GameState.StoryFlow.advance(str(paid_event.id), 1).ok, "补足普通事件材料后可完成")
	_check(GameState.inventory.wood == stock.wood - 2 and GameState.story.results[0].rewards.blueprints.is_empty(), "普通事件只扣明示费用，不重复发图纸或补偿")
	GameState.story_config = {"version": 1, "nodes": []}
	GameState.cave_config.initial_blueprints = ["house"]
	GameState.pending_blueprint_unlocks["spring"] = 2
	GameState.reset_game(42)
	_check(GameState.unlocked_blueprints == ["house"] and GameState.pending_blueprint_unlocks.is_empty(), "新局按配置重建图纸，不携带上局或待生效资格")
	GameState.cave_config.initial_blueprints = initial
	GameState.story_config = original_story
	GameState.reset_game(42)
	blueprints_completed = true


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


func _capture_story_ui(directory: String) -> void:
	GameState.reset_game(42)
	get_window().size = Vector2i(1280, 720)
	var ui: Control = load("res://scenes/main.tscn").instantiate()
	add_child(ui)
	await _snapshot(directory.path_join("11-story-opening.png"))
	_check(ui.story_view.visible and GameState.phase == GameState.Phase.STORY, "真实界面开局进入剧情")
	ui.open_menu("work")
	ui.show_cave()
	_check(not ui.overlay.visible and not ui.in_cave, "对话时不能通过菜单入口绕开锁定")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	ui.story_view._input(escape)
	_check(ui.story_view.visible, "Escape 不跳过未完成剧情")
	for pressed in [true, false]:
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.pressed = pressed
		Input.parse_input_event(enter)
		await get_tree().process_frame
	_check(GameState.story.completed.is_empty() and int(GameState.story.active.get("line", -1)) == 1, "一次回车只推进一句，当前行 %d" % int(GameState.story.active.get("line", -1)))
	ui.story_view.advance_button.pressed.emit()
	_check(GameState.phase == GameState.Phase.FREE and not ui.story_view.visible, "窗口末句之后回到自由操作")
	for stage in range(3):
		GameState.reset_game(42)
		_finish_active_story()
		GameState.base_stats.power = 1001
		GameState.turn = [1, 12, 36][stage]
		GameState.phase = GameState.Phase.RESULTS
		GameState.advance_turn()
		get_window().size = [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1600, 900)][stage]
		await _snapshot(directory.path_join("12-story-stage-%d.png" % stage))
		_check(ui.story_view.portrait.texture.region.position.x == stage * 512, "实际对话显示对应阶段立绘")
		_check(ui.story_view.advance_button.get_global_rect().end.y <= ui.size.y, "小窗口对话按钮不越界")
		ui.story_view.advance_button.pressed.emit()
		_check(ui.story_view.effect_label.text.contains("清心丹") and GameState.inventory.clearheart_pill == 0, "末句提前显示奖励，但尚未入库")
		ui.story_view.advance_button.pressed.emit()
		_check(GameState.inventory.clearheart_pill == 1 and GameState.phase == GameState.Phase.FREE, "窗口完成奖励只发一次")

	GameState.reset_game(42)
	_finish_active_story()
	GameState.base_stats.power = 1001
	_fill()
	ui.open_menu("work")
	ui.confirm_button.pressed.emit()
	_check(ui.story_view.visible and not ui.overlay.visible, "回合末剧情暂时覆盖札记")
	ui.story_view.advance_button.pressed.emit()
	await _snapshot(directory.path_join("13-story-end-reward.png"))
	ui.story_view.advance_button.pressed.emit()
	_check(GameState.phase == GameState.Phase.RESULTS and ui.overlay.visible and ui.journal.visible, "回合末剧情读完自动回札记")
	_check(ui.results.text.contains("清心丹"), "札记包含剧情实际奖励")
	var report: String = ui.results.text
	ui._refresh()
	ui._refresh()
	_check(ui.results.text == report and ui.results.text.count("灵息初成（示例）") == 1, "重复刷新不追加重复剧情或奖励摘要")
	await _snapshot(directory.path_join("14-story-journal.png"))
	ui.next_button.pressed.emit()
	_check(GameState.phase == GameState.Phase.FREE and not ui.overlay.visible, "剧情接入后下一回合仍回到场景")

	# 内容作者可写长台词，文本滚动而按钮和费用区保持固定位置。
	var source: Dictionary = GameState.story_config
	GameState.story_config = source.duplicate(true)
	GameState.story_config.nodes[0].variants["0"].lines[0].text = "山风穿过竹林，草木在晨光里舒展。".repeat(150)
	GameState.reset_game(42)
	_finish_active_story()
	GameState.base_stats.power = 1001
	_fill()
	ui.open_menu("work")
	ui.confirm_button.pressed.emit()
	get_window().size = Vector2i(960, 540)
	await _snapshot(directory.path_join("15-story-long-text.png"))
	_check(ui.story_view.dialogue.get_content_height() > ui.story_view.dialogue.size.y, "长台词进入可滚动文本区")
	_check(not ui.story_view.dialogue.get_global_rect().intersects(ui.story_view.advance_button.get_global_rect()), "长台词不覆盖推进按钮")
	ui.story_view.advance_button.pressed.emit()
	ui.story_view.advance_button.pressed.emit()
	_check(GameState.phase == GameState.Phase.RESULTS, "长台词也能正常完成")
	_check(_check_replacement_assets(ui), "替换素材的界面回归必须完整执行")
	ui.queue_free()
	await get_tree().process_frame
	GameState.story_config = source
	GameState.reset_game(42)
	story_ui_completed = true


## 一个完整图纸闭环使用现有丹炉作测试数据，不新增正式建筑或剧情内容。
func _capture_blueprint_ui(directory: String) -> void:
	var source: Dictionary = GameState.story_config
	var initial: Array = GameState.cave_config.initial_blueprints.duplicate()
	var node := _story_fixture("blueprint_ui", "main", "turn_end")
	node.name = "丹炉图纸（测试）"
	node.rewards = {"blueprints": ["alchemy"]}
	node.variants["0"].lines = [
		{"speaker": "师父", "text": "这份丹炉图纸先收好。"},
		{"speaker": "师父", "text": "待图纸整理妥当，便可备料建造。"},
	]
	GameState.story_config = {"version": 1, "nodes": [node]}
	GameState.cave_config.initial_blueprints.erase("alchemy")
	GameState.reset_game(42)
	get_window().size = Vector2i(960, 540)
	var ui: Control = load("res://scenes/main.tscn").instantiate()
	add_child(ui)
	ui.show_cave()
	var cave_ui: Control = ui.cave_view
	var index := -1
	for i in range(cave_ui.catalog.item_count):
		if cave_ui.catalog.get_item_metadata(i) == "alchemy":
			index = i
	_check(index >= 0, "未获得图纸的建筑仍在目录中，可查看锁定原因")
	cave_ui.catalog.select(index)
	cave_ui.catalog.item_selected.emit(index)
	_check(cave_ui.mode_buttons.build.disabled and cave_ui.current_mode == "select", "缺图纸时不能进入建造模式")
	_check(cave_ui.cost_label.text.contains("尚未获得图纸"), "选中锁定项显示具体原因")
	var stock: Dictionary = GameState.inventory.duplicate(true)
	# 绕过按钮状态模拟旧输入，规则层也必须拒绝，不能只靠界面置灰。
	cave_ui.current_mode = "build"
	cave_ui._cell_clicked(Vector2i(1, 2))
	_check(GameState.cave.buildings.is_empty() and GameState.inventory == stock, "旧建造请求不绕过图纸校验")
	await _snapshot(directory.path_join("16-blueprint-locked.png"))
	_check(cave_ui.cost_label.get_global_rect().end.y <= cave_ui.toolbar_panel.get_global_rect().end.y, "小窗口锁定提示不超出工具栏")
	ui.show_home()
	_fill()
	ui.open_menu("work")
	ui.confirm_button.pressed.emit()
	ui.story_view.advance_button.pressed.emit()
	_check(ui.story_view.effect_label.text.contains("丹炉图纸") and ui.story_view.effect_label.text.contains("下回合可用"), "末句预告图纸与生效时点")
	get_window().size = Vector2i(1280, 720)
	await _snapshot(directory.path_join("17-blueprint-dialogue.png"))
	ui.story_view.advance_button.pressed.emit()
	_check(ui.results.text.contains("丹炉图纸") and GameState.inventory == stock, "札记展示图纸奖励，不冒充物品入库或扣材料")
	ui.show_cave()
	_check(cave_ui.cost_label.text.contains("下回合可用") and cave_ui.mode_buttons.build.disabled, "已获得但待生效仍不能建造")
	await _snapshot(directory.path_join("18-blueprint-pending.png"))
	ui.show_home()
	ui.open_menu("work")
	ui.next_button.pressed.emit()
	ui.show_cave()
	_check(not cave_ui.mode_buttons.build.disabled and not cave_ui.cost_label.text.contains("图纸"), "下一回合自动刷新目录与建造资格")
	cave_ui.mode_buttons.build.pressed.emit()
	for position in [Vector2i(1, 2), Vector2i(4, 2)]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = cave_ui.board.cell_center(position)
		cave_ui.board._gui_input(click)
	_check(GameState.cave.buildings.size() == 2 and GameState.unlocked_blueprints.has("alchemy"), "窗口中同一图纸连续建造两栋")
	_check(GameState.inventory.wood == stock.wood - 12 and GameState.inventory.stone == stock.stone - 12, "窗口建造仅扣两份建材")
	await _snapshot(directory.path_join("19-blueprint-built.png"))
	ui.queue_free()
	await get_tree().process_frame
	GameState.story_config = source
	GameState.cave_config.initial_blueprints = initial
	GameState.reset_game(42)
	blueprint_ui_completed = true


## 只临时替换内存中的资源缓存，不改作者的 PNG；验证真实 UI 调用链也使用动态裁切。
func _check_replacement_assets(ui: Control) -> bool:
	var portrait_path := "res://assets/daughter_stages.png"
	var original_portrait: Texture2D = load(portrait_path)
	var replacement := GradientTexture2D.new()
	replacement.width = 900
	replacement.height = 600
	replacement.take_over_path(portrait_path)
	for stage in range(3):
		GameState.reset_game(42)
		GameState.turn = [1, 13, 37][stage]
		GameState.story.active.growth_phase = stage
		GameState.story.active.presentation.erase("portrait")
		ui.portrait_stage = -1
		ui.story_view.shown_stage = -1
		GameState.state_changed.emit()
		var expected := Rect2(stage * 300, 0, 300, 600)
		_check(ui.portrait.texture.region == expected, "更换尺寸后家园立绘正确")
		_check(ui.story_view.portrait.texture.region == expected, "无 portrait 的支线回退与家园一致")
	GameState.story.active.presentation.portrait = {"texture": portrait_path, "region": [10, 20, 100, 200]}
	ui.story_view.shown_stage = -1
	ui.story_view._refresh()
	_check(ui.story_view.portrait.texture.region == Rect2(10, 20, 100, 200), "显式剧情裁切不被默认布局覆盖")
	GameState.story.active.presentation.portrait.erase("region")
	ui.story_view.shown_stage = -1
	ui.story_view._refresh()
	_check(ui.story_view.portrait.texture == replacement, "专用立绘不填 region 时显示整图")
	original_portrait.take_over_path(portrait_path)

	var building_path := "res://assets/cave_buildings.png"
	var original_buildings: Texture2D = load(building_path)
	var pixels := Image.create_empty(800, 600, false, Image.FORMAT_RGBA8)
	# 第 6 格只有右半部分不透明，用来区分显式序号及透明命中，其他格全透明。
	pixels.fill_rect(Rect2i(500, 300, 100, 300), Color.WHITE)
	var building_texture := ImageTexture.create_from_image(pixels)
	building_texture.take_over_path(building_path)
	var cave: Dictionary = GameState.cave
	var house: Dictionary = GameState.cave_config.buildings.house
	var old_index: int = int(house.sprite_index)
	house.sprite_index = 6
	GameState.cave = cave.duplicate(true)
	GameState.cave.buildings = [{"id": 99, "type": "house", "position": Vector2i(1, 4), "recipe": ""}]
	var board: Control = load("res://scripts/cave_board.gd").new()
	board.size = Vector2(800, 600)
	add_child(board)
	_check(board.sprites[6].region == Rect2(400, 300, 200, 300), "真实洞天地块使用替换图集尺寸")
	var rect: Rect2 = board.structure_rect(Vector2(1, 4), Vector2.ONE)
	_check(is_equal_approx(rect.size.y / rect.size.x, 1.5), "建筑显示保持替换图格比例")
	_check(board.building_at_point(rect.position + rect.size * Vector2(0.75, 0.5)).get("id", -1) == 99, "点击命中使用配置图格的真实像素")
	_check(board.building_at_point(rect.position + rect.size * Vector2(0.25, 0.5)).is_empty(), "配置图格的透明部分不命中")
	board.free()
	house.sprite_index = old_index
	GameState.cave = cave
	original_buildings.take_over_path(building_path)
	return true


## 等容器完成布局且本帧渲染结束再读像素；此流程需要有图形输出，不能加 --headless。
func _snapshot(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var frame := get_viewport().get_texture().get_image()
	_check(not frame.is_empty(), "界面渲染非空")
	_check(frame.save_png(path) == OK, "导出截图")
	print("UI_SNAPSHOT: ", path)
