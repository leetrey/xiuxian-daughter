extends Node

# 本局状态只有一份；UI 读取它，ScheduleManager 提交培养与活动结果。
# 剧情条件只读、播放提交独立；存档与继承选择尚未实现。
signal state_changed
# phase 是本回合的操作阶段；growth_phase() 才是用于日程开放和立绘的成长阶段。
enum Phase { FREE, RESOLVING, RESULTS, FINISHED, STORY }
const CONFIG_PATH := "res://data/cultivation.json"
const CAVE_CONFIG_PATH := "res://data/cave.json"
const ITEMS_PATH := "res://data/items.json"
const RECIPES_PATH := "res://data/recipes.json"
const STORY_PATH := "res://data/story.json"
const Cave = preload("res://scripts/cave_rules.gd")
const Content = preload("res://scripts/content_tables.gd")
const Story = preload("res://scripts/story_rules.gd")
const StoryFlow = preload("res://scripts/story_flow.gd")

# 配置是内容模板；下方 inventory、cave 等才是会随玩家操作变化的本局数据。
var config: Dictionary = {}
var cave_config: Dictionary = {}
var story_config: Dictionary = {}
var story: Dictionary = {}
var unlocked_activities: Array[String] = []
# 活动 ID -> 最早生效回合；与剧情完成记录分开，不能用已读节点冒充已经开放。
var pending_activity_unlocks: Dictionary = {}
# 图纸不进入物品库存、不按建造次数消耗，也不代表土地或剧情已经推进。
var unlocked_blueprints: Array[String] = []
var pending_blueprint_unlocks: Dictionary = {}
var config_error := ""
# 只有全部配置检查返回成功才置真，防止脚本异常中断加载后仍打印校验成功。
var configs_validated := false
var cave: Dictionary = {}
var last_production: Dictionary = {}
# 生产提交标记与报告分开，避免重复确认同一回合时再次发放产物。
var last_production_turn := 0
var base_stats: Dictionary = {}
# 只预留三件装备的属性贡献口径；完整换装系统尚未实现。
var equipment_bonuses: Dictionary = {}
var inventory: Dictionary = {}
# 槽位保存活动 ID 而非按钮序号或中文名；空字符串表示尚未安排。
var plan: Array[String] = []
var last_results: Array[Dictionary] = []
var phase := Phase.FREE
var turn := 1
var energy := 0
var pressure := 0
var schedule_slots := 3
# 培养共用这一份随机源；界面预览不能消耗它，否则开关菜单也会改变结果。
var rng := RandomNumberGenerator.new()


## Autoload 先于主场景初始化；配置失败时直接停止，避免用半份配置继续运行。
func _ready() -> void:
	# 加载函数意外中断时也走失败出口，不对异常返回值继续调用字符串方法。
	var load_error: Variant = _load_configs()
	config_error = load_error if load_error is String else "配置加载异常中断，请检查前面的脚本错误"
	if not configs_validated and config_error.is_empty():
		config_error = "配置初始化未完成，请检查前面的脚本错误"
	if not config_error.is_empty():
		push_error(config_error)
		get_tree().quit(1)
		return
	reset_game()


func _load_configs() -> String:
	configs_validated = false
	var sources: Dictionary = {}
	for path in [CONFIG_PATH, CAVE_CONFIG_PATH, ITEMS_PATH, RECIPES_PATH, STORY_PATH]:
		var result := Content.read_object(path)
		if not str(result.error).is_empty():
			return str(result.error)
		sources[path] = result.data
	config = sources[CONFIG_PATH]
	cave_config = sources[CAVE_CONFIG_PATH]
	story_config = sources[STORY_PATH]
	if config.has("items"):
		return "data/cultivation.json: 物品定义请放到 data/items.json，不能重复定义 items"
	if cave_config.has("recipes"):
		return "data/cave.json: 配方定义请放到 data/recipes.json，建筑中只保留配方 ID 列表"
	if not sources[ITEMS_PATH].get("items") is Dictionary:
		return "data/items.json items: 需要对象"
	if not sources[RECIPES_PATH].get("recipes") is Dictionary:
		return "data/recipes.json recipes: 需要对象"
	# 文件按内容归属拆开，加载后沿用现有规则与 UI 的查询入口，不复制第二套物品状态。
	config.items = sources[ITEMS_PATH].items
	cave_config.recipes = sources[RECIPES_PATH].recipes
	var error := validate_config()
	if not error.is_empty():
		return error
	error = validate_cave_config()
	if not error.is_empty():
		return error
	error = Story.validate_config(story_config, config.items, config.activities, cave_config.buildings)
	if not error.is_empty():
		return error
	# 标记放在加载函数末尾；若此函数直接因脚本异常中断，调用方不能替它宣布成功。
	configs_validated = true
	return ""


## 校验培养表及其物品引用；返回空字符串表示通过，否则返回首个可定位的问题。
func validate_config() -> String:
	for key in ["rules", "groups", "items", "initial_inventory"]:
		if not config.get(key) is Dictionary:
			return "配置缺少对象: " + key
	for key in ["activities", "outcomes", "pressure_bands"]:
		if not config.get(key) is Array:
			return "配置缺少数组: " + key
	var content_error := Content.validate_items(config.items)
	if not content_error.is_empty():
		return content_error
	content_error = Content.validate_amounts(config.initial_inventory, config.items, "data/cultivation.json initial_inventory")
	if not content_error.is_empty():
		return content_error
	var rules: Dictionary = config.rules
	for key in ["schedule_slots", "max_energy", "initial_attribute", "initial_pressure"]:
		if not Content.is_integer(rules.get(key)) or float(rules[key]) < 0:
			return "data/cultivation.json rules.%s: 需要非负整数" % key
	if rules.schedule_slots < 3 or rules.schedule_slots > 5:
		return "data/cultivation.json rules.schedule_slots: 培养槽数量必须为 3 至 5"
	for key in ["require_full_schedule", "allow_repeat"]:
		if not rules.get(key) is bool:
			return "data/cultivation.json rules.%s: 需要布尔值" % key
	if not rules.get("phase_turns") is Array or rules.phase_turns.size() != 3:
		return "必须配置三个成长阶段"
	for length in rules.phase_turns:
		if not Content.is_integer(length) or float(length) <= 0:
			return "data/cultivation.json rules.phase_turns: 阶段回合数必须为正整数"
	if not ["round", "floor"].has(rules.get("rounding", "")):
		return "取整只支持 round 或 floor"
	# 不调用尚未验证数据的 stat_names()，先逐层检查再汇总，避免 merge() 被坏类型击穿。
	var names: Dictionary = {}
	for group_id in config.groups:
		var group: Variant = config.groups[group_id]
		var path := "data/cultivation.json groups." + str(group_id)
		if not group is Dictionary:
			return path + ": 需要对象"
		if not group.get("name") is String or str(group.name).strip_edges().is_empty():
			return path + ".name: 需要非空名称"
		if not group.get("stats") is Dictionary:
			return path + ".stats: 需要对象"
		for key in group.stats:
			if not key is String or str(key).strip_edges().is_empty() or names.has(key):
				return path + ".stats: 属性 ID 必须非空且不能跨组重复"
			if not group.stats[key] is String or str(group.stats[key]).strip_edges().is_empty():
				return path + ".stats." + str(key) + ": 需要非空名称"
			names[key] = group.stats[key]
	if names.size() != 16:
		return "需要 16 项细分属性"
	if config.outcomes.size() != 3:
		return "需要大成功、成功、失败三种结果"
	for index in range(config.outcomes.size()):
		var outcome: Variant = config.outcomes[index]
		var path := "data/cultivation.json outcomes[%d]" % index
		if not outcome is Dictionary:
			return path + ": 需要对象"
		if not outcome.get("name") is String or str(outcome.name).strip_edges().is_empty():
			return path + ".name: 需要非空名称"
		if not Content.is_number(outcome.get("multiplier")) or float(outcome.multiplier) < 0:
			return path + ".multiplier: 需要非负有限数值"
	var boundary := 0
	# 压力档为左闭右开区间，最后必须到 101，才能包含合法的压力值 100。
	for index in range(config.pressure_bands.size()):
		var band: Variant = config.pressure_bands[index]
		var path := "data/cultivation.json pressure_bands[%d]" % index
		if not band is Dictionary:
			return path + ": 需要对象"
		for key in ["min", "max_exclusive"]:
			if not Content.is_integer(band.get(key)) or float(band[key]) < 0 or float(band[key]) > 101:
				return path + "." + key + ": 需要 0 至 101 的整数"
		if int(band.min) != boundary or int(band.max_exclusive) <= boundary:
			return path + ": 压力区间必须连续且不能重叠"
		boundary = int(band.max_exclusive)
		if not band.get("probabilities") is Array:
			return path + ".probabilities: 需要数组"
		if band.probabilities.size() != config.outcomes.size():
			return path + ".probabilities: 结果与概率数量不一致"
		var total := 0.0
		for probability_index in range(band.probabilities.size()):
			var probability: Variant = band.probabilities[probability_index]
			if not Content.is_number(probability) or float(probability) < 0.0 or float(probability) > 1.0:
				return path + ".probabilities[%d]: 需要 0 至 1 的有限数值" % probability_index
			total += float(probability)
		if not is_equal_approx(total, 1.0):
			return path + ".probabilities: 每档概率之和必须为 1"
	if boundary != 101:
		return "data/cultivation.json pressure_bands: 压力区间必须覆盖 0 至 100"
	var ids: Array[String] = []
	for activity in config.activities:
		if not activity is Dictionary or not activity.get("id") is String or str(activity.id).is_empty():
			return "data/cultivation.json activities: 每项活动需要非空 id"
		var path := "data/cultivation.json activities." + str(activity.id)
		if not activity.get("name") is String or str(activity.name).strip_edges().is_empty():
			return path + ".name: 需要非空名称"
		if not activity.get("growth") is Dictionary or not Content.is_number(activity.get("pressure")):
			return path + ": 需要 growth 对象与 pressure 数值"
		if ids.has(str(activity.id)) or not ["schedule", "free"].has(activity.get("kind")):
			return "活动 ID 重复或类型错误"
		ids.append(str(activity.id))
		if not Content.is_integer(activity.get("energy_cost", 0)) or float(activity.get("energy_cost", 0)) < 0:
			return path + ".energy_cost: 需要非负整数"
		if not Content.is_integer(activity.get("min_phase", 0)) or not [0, 1, 2].has(int(activity.get("min_phase", 0))):
			return path + ".min_phase: 需要 0、1 或 2"
		if activity.has("requires_unlock") and not activity.requires_unlock is bool:
			return path + ".requires_unlock: 需要布尔值"
		for key in activity.growth:
			if not names.has(key) or not Content.is_number(activity.growth[key]) or float(activity.growth[key]) < 0:
				return path + ".growth." + str(key) + ": 需要已知属性的非负有限数值"
		content_error = Content.validate_amounts(activity.get("costs", {}), config.items, path + ".costs")
		if not content_error.is_empty():
			return content_error
	return ""


## 从已加载的配置创建新局，不重新读取 JSON。传入非负种子可复现培养结果。
func reset_game(random_seed: int = -1) -> void:
	base_stats.clear()
	for key in stat_names():
		base_stats[key] = int(config.rules.initial_attribute)
	equipment_bonuses = {"weapon": {}, "armor": {}, "accessory": {}}
	# Dictionary/Array 默认共享引用；深复制避免游戏消耗反过来修改开局模板。
	inventory = config.initial_inventory.duplicate(true)
	schedule_slots = int(config.rules.schedule_slots)
	turn = 1
	phase = Phase.FREE
	energy = int(config.rules.max_energy)
	pressure = clampi(int(config.rules.initial_pressure), 0, 100)
	plan.clear()
	plan.resize(schedule_slots)
	plan.fill("")
	last_results.clear()
	cave = {"roads": [], "buildings": [], "workers": [], "next_id": 1}
	for cell in cave_config.initial_roads:
		cave.roads.append(Vector2i(int(cell[0]), int(cell[1])))
	for source in cave_config.workers:
		var worker: Dictionary = source.duplicate(true)
		# 工作归属只保存在御灵上；-1 表示待命，建筑不再保存第二份派工列表。
		worker.building_id = -1
		worker.slot = -1
		cave.workers.append(worker)
	last_production.clear()
	last_production_turn = 0
	story = {"completed": {}, "checked": {}, "checkpoint": "", "kind": "", "active": {}, "results": []}
	unlocked_activities.clear()
	pending_activity_unlocks.clear()
	unlocked_blueprints.assign(cave_config.initial_blueprints)
	pending_blueprint_unlocks.clear()
	if random_seed < 0:
		rng.randomize()
	else:
		rng.seed = random_seed
	StoryFlow.begin("turn_start")


## 先验证配方中的物品，再验证建筑可用配方，保证后续跨表查询有合法目标。
func validate_cave_config() -> String:
	for key in ["buildings", "recipes"]:
		if not cave_config.get(key) is Dictionary or cave_config[key].is_empty():
			return "洞天配置缺少非空对象: " + key
	var content_error := Content.validate_recipes(cave_config.recipes, config.items)
	if not content_error.is_empty():
		return content_error
	content_error = Content.validate_blueprints(cave_config.get("initial_blueprints"), cave_config.buildings, "data/cave.json initial_blueprints")
	if not content_error.is_empty():
		return content_error
	for key in ["entrance", "initial_roads", "workers"]:
		if not cave_config.get(key) is Array:
			return "洞天配置缺少数组: " + key
	if cave_config.entrance.size() != 2:
		return "入口需要两个坐标"
	if int(cave_config.get("width", 0)) < 1 or int(cave_config.get("height", 0)) < 1:
		return "洞天尺寸必须为正数"
	if not ["manhattan", "chebyshev"].has(cave_config.get("distance_metric", "")):
		return "景观距离只支持 manhattan 或 chebyshev"
	if not ["round", "floor"].has(cave_config.get("output_rounding", "")):
		return "洞天取整只支持 round 或 floor"
	if not Cave.inside(Cave.entrance()):
		return "入口必须在洞天内"
	var seen: Array[Vector2i] = []
	for point in cave_config.initial_roads:
		if not point is Array or point.size() != 2:
			return "道路需要两个坐标"
		var cell := Vector2i(int(point[0]), int(point[1]))
		if not Cave.inside(cell) or seen.has(cell) or cell == Cave.entrance():
			return "初始道路越界或重复"
		seen.append(cell)
	for building_id in cave_config.buildings:
		var building = cave_config.buildings[building_id]
		var path := "data/cave.json buildings." + str(building_id)
		if not building is Dictionary:
			return path + ": 建筑必须为对象"
		if building.has("sprite_index"):
			var sprite_count: int = Content.BUILDING_ATLAS_GRID.x * Content.BUILDING_ATLAS_GRID.y
			if not Content.is_integer(building.sprite_index) or float(building.sprite_index) < 0 or float(building.sprite_index) >= sprite_count:
				return path + ".sprite_index: 需要 0 至 %d 的整数" % (sprite_count - 1)
		if not building.get("size") is Array or building.size.size() != 2:
			return "建筑占地需要宽高两个值"
		if not building.get("costs") is Dictionary or not building.get("recipes") is Array:
			return "建筑缺少成本或配方列表"
		if not ["housing", "production", "manufacturing", "landscape"].has(building.get("category", "")):
			return "建筑分类不合法"
		if str(building.get("name", "")).is_empty() or not building.has("color") or not building.has("worker_slots"):
			return "建筑缺少名称、颜色或工作槽"
		if int(building.size[0]) < 1 or int(building.size[1]) < 1 or int(building.worker_slots) < 0 or int(building.worker_slots) > 3:
			return "建筑尺寸或工作槽不合法"
		if int(building.get("capacity", 0)) < 0:
			return "民居容量不能为负数"
		content_error = Content.validate_amounts(building.costs, config.items, path + ".costs")
		if not content_error.is_empty():
			return content_error
		content_error = Content.validate_building_recipes(building, cave_config.recipes, config.items, path)
		if not content_error.is_empty():
			return content_error
		if building.has("bonus"):
			var bonus = building.bonus
			if not bonus is Dictionary or not bonus.get("work_types") is Array:
				return "景观缺少适用工作类型"
			if str(bonus.get("affix", "")).is_empty() or str(bonus.get("label", "")).is_empty():
				return "景观缺少词条 ID 或名称"
			if float(bonus.get("radius", 0)) <= 0 or float(bonus.get("peak", -1)) < 0:
				return "景观半径和倍率不合法"
	var worker_ids: Array[String] = []
	for worker in cave_config.workers:
		if not worker is Dictionary or not worker.get("aptitudes") is Dictionary:
			return "御灵缺少适应性对象"
		if str(worker.get("id", "")).is_empty() or str(worker.get("name", "")).is_empty():
			return "御灵缺少 ID 或名称"
		if worker_ids.has(str(worker.id)):
			return "御灵 ID 重复"
		worker_ids.append(str(worker.id))
		for value in worker.aptitudes.values():
			if float(value) < 0:
				return "适应性不能为负数"
	return ""


## 只检查指定库存是否够用；可用于真实库存，也可用于生产预测的临时预算。
func cost_error(costs: Dictionary, stock: Dictionary) -> String:
	for key in costs:
		if int(stock.get(key, 0)) < int(costs[key]):
			return str(config.items[key].name) + "不足"
	return ""


## 真正扣除本局库存。调用者必须先检查全部成本；这里不校验、不广播刷新。
func pay_costs(costs: Dictionary) -> void:
	for key in costs:
		inventory[key] = int(inventory.get(key, 0)) - int(costs[key])


func stat_names() -> Dictionary:
	var names: Dictionary = {}
	for group in config.groups.values():
		names.merge(group.stats)
	return names


func equipment_bonus(stat: String) -> int:
	var value := 0
	for bonuses in equipment_bonuses.values():
		value += int(bonuses.get(stat, 0))
	return value


func attribute(stat: String, with_equipment: bool = false) -> int:
	# 剧情默认只取 A；比赛显式传 true，换装不能写入永久成长。
	return int(base_stats.get(stat, 0)) + (equipment_bonus(stat) if with_equipment else 0)


func group_total(group_id: String, with_equipment: bool = false) -> int:
	var value := 0
	for key in config.groups[group_id].stats:
		value += attribute(key, with_equipment)
	return value


## 将从 1 开始的回合映射为 0/1/2；这些内部阶段不等于界面应显示的年龄。
func growth_phase() -> int:
	var boundary := 0
	for i in range(config.rules.phase_turns.size()):
		boundary += int(config.rules.phase_turns[i])
		if turn <= boundary:
			return i
	return 2


func total_turns() -> int:
	var total := 0
	for length in config.rules.phase_turns:
		total += int(length)
	return total


## 给只读剧情查询提供独立快照，刻意不包含装备 B 或生产预测。
## 默认读取本局完成记录；测试可显式传 [] 或其他列表来覆盖，不写回本局。
func story_context(completed: Variant = null) -> Dictionary:
	return {
		"turn": turn,
		"growth_phase": growth_phase(),
		"base_stats": base_stats.duplicate(true),
		"inventory": inventory.duplicate(true),
		"completed": story.completed.keys() if completed == null else completed.duplicate(),
	}


## 仅从结果阶段前进；保留属性、压力、库存和洞天安排，清空女儿日程草稿。
func advance_turn() -> bool:
	if phase != Phase.RESULTS:
		return false
	if turn >= total_turns():
		phase = Phase.FINISHED
	else:
		turn += 1
		energy = int(config.rules.max_energy)
		plan.fill("")
		phase = Phase.FREE
		story.results.clear()
		StoryFlow.apply_pending_unlocks()
		# 压力不在此恢复；未来回合末天赋应在独立结算位置执行。
		StoryFlow.begin("turn_start")
	# 回合推进自己保证通知；即使剧情检查点已处理、begin() 提前返回，界面仍会更新。
	state_changed.emit()
	return true
