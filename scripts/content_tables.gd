extends RefCounted

# 作者修改的是 JSON 表；这里仅负责读取、类型与跨表引用检查，不执行玩法。
# 读取函数返回 {data, error}；校验函数返回错误文字，空字符串表示通过。
const ITEM_CATEGORIES := ["resource", "herb", "product"]


static func read_object(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"data": {}, "error": "%s: 无法读取文件 (%s)" % [path, FileAccess.get_open_error()]}
	return parse_object(file.get_as_text(), path)


## 与磁盘读取分开，使测试可以直接传入错误 JSON；path 只用于定位报错来源。
static func parse_object(source: String, path: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(source) != OK:
		return {"data": {}, "error": "%s: JSON 第 %d 行: %s" % [path, parser.get_error_line() + 1, parser.get_error_message()]}
	if not parser.data is Dictionary:
		return {"data": {}, "error": path + ": 根节点必须为对象"}
	return {"data": parser.data, "error": ""}


static func validate_items(items: Variant) -> String:
	if not items is Dictionary or items.is_empty():
		return "data/items.json items: 需要非空对象"
	for id in items:
		var path := "data/items.json items." + str(id)
		if not (id is String or id is StringName) or str(id).is_empty():
			return path + ": 物品 ID 不能为空"
		var item = items[id]
		if not item is Dictionary:
			return path + ": 物品必须为对象"
		if not _has_name(item):
			return path + ".name: 需要非空名称"
		if not ITEM_CATEGORIES.has(item.get("category")):
			return path + ".category: 只支持 resource、herb、product"
		if item.has("description") and not item.description is String:
			return path + ".description: 需要字符串"
	return ""


## 库存/成本允许零；配方投入产出传 allow_zero=false，无投入用空对象表达。
static func validate_amounts(amounts: Variant, items: Dictionary, path: String, allow_zero: bool = true) -> String:
	if not amounts is Dictionary:
		return path + ": 需要物品 ID 到整数数量的对象"
	for id in amounts:
		var field := path + "." + str(id)
		if not items.has(id):
			return field + ": 未知物品，请先在 data/items.json 定义"
		var value = amounts[id]
		# JSON 数字读取为浮点数；禁止把小数、字符串和布尔值静默转成库存整数。
		if not (value is int or value is float):
			return field + ": 数量必须为整数"
		if not is_finite(float(value)) or float(value) != floor(float(value)) or float(value) < (0 if allow_zero else 1):
			return field + (": 数量必须为非负整数" if allow_zero else ": 数量必须为正整数；无需材料时使用空对象 {}")
	return ""


static func validate_recipes(recipes: Variant, items: Dictionary) -> String:
	if not recipes is Dictionary or recipes.is_empty():
		return "data/recipes.json recipes: 需要非空对象"
	for id in recipes:
		var path := "data/recipes.json recipes." + str(id)
		if not (id is String or id is StringName) or str(id).is_empty():
			return path + ": 配方 ID 不能为空"
		var recipe = recipes[id]
		if not recipe is Dictionary:
			return path + ": 配方必须为对象"
		if not _has_name(recipe):
			return path + ".name: 需要非空名称"
		for field in ["inputs", "outputs"]:
			var error := validate_amounts(recipe.get(field), items, path + "." + field, false)
			if not error.is_empty():
				return error
		if recipe.outputs.is_empty():
			return path + ".outputs: 至少需要一种产物"
	return ""


## 建筑只持有配方 ID；这里把建筑、配方、物品三张表连起来检查产物分类。
static func validate_building_recipes(building: Dictionary, recipes: Dictionary, items: Dictionary, path: String) -> String:
	var allowed = building.get("output_categories", [])
	if not allowed is Array:
		return path + ".output_categories: 需要分类数组"
	for category in allowed:
		if not ITEM_CATEGORIES.has(category):
			return path + ".output_categories: 未知物品分类 " + str(category)
	if not building.get("recipes") is Array:
		return path + ".recipes: 需要配方 ID 数组"
	if not building.recipes.is_empty() and allowed.is_empty():
		return path + ".output_categories: 有生产任务的建筑必须声明允许的产物分类"
	var seen: Array[String] = []
	for id in building.recipes:
		if not id is String or not recipes.has(id):
			return path + ".recipes: 未知配方 " + str(id) + "，请先在 data/recipes.json 定义"
		if seen.has(id):
			return path + ".recipes: 配方重复 " + id
		seen.append(id)
		# 先校验整个配方表，再检查建筑的所有产物，避免副产物绕过分类约束。
		for item_id in recipes[id].outputs:
			if not allowed.is_empty() and not allowed.has(items[item_id].category):
				return "%s.recipes.%s: 产物 %s 的分类 %s 不在 output_categories 中" % [path, id, item_id, items[item_id].category]
	return ""


static func _has_name(data: Dictionary) -> bool:
	return data.get("name") is String and not str(data.name).strip_edges().is_empty()
