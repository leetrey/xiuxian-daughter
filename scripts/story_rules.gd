extends RefCounted

# 剧情的只读规则层：接收配置与状态快照，不扣费、不发奖、不记录完成，也不消耗随机数。
# 播放与提交由 story_flow.gd 执行；候选节点不等于已经播放或完成的任务。
const Content = preload("res://scripts/content_tables.gd")
const CHECKPOINTS := ["turn_start", "turn_end"]
const KINDS := ["main", "side"]
const STAGES := ["0", "1", "2"]


## 配置先整体通过校验，再用于条件查询；空字符串表示通过。
static func validate_config(config: Dictionary, items: Dictionary, activities: Array = []) -> String:
	var path := "data/story.json"
	var error := _unknown_fields(config, ["version", "note", "nodes"], path)
	if not error.is_empty():
		return error
	if not _integer(config.get("version"), 1) or int(config.version) != 1:
		return path + ".version: 当前只支持整数版本 1"
	if config.has("note") and not config.note is String:
		return path + ".note: 需要字符串"
	if not config.get("nodes") is Array:
		return path + ".nodes: 需要节点数组，暂无剧情可填 []"
	var by_id: Dictionary = {}
	for i in range(config.nodes.size()):
		var node = config.nodes[i]
		var location := path + ".nodes[%d]" % i
		if not node is Dictionary or not _text(node.get("id")):
			return location + ".id: 需要非空字符串 ID"
		location += "(" + str(node.id) + ")"
		if by_id.has(node.id):
			return location + ".id: 剧情 ID 重复"
		by_id[node.id] = node
		error = _validate_node(node, items, activities, location)
		if not error.is_empty():
			return error
	# 第二遍检查引用，允许前置节点写在本节点之后，数组位置不代表剧情先后。
	for id in by_id:
		var node: Dictionary = by_id[id]
		for field in ["requires_completed", "excludes_completed"]:
			for other in node.get(field, []):
				var location: String = path + ".nodes." + str(id) + "." + field
				if not by_id.has(other) or other == id:
					return location + ": 未知节点或引用自身 " + str(other)
				if field == "requires_completed" and node.get("excludes_completed", []).has(other):
					return location + ": 同一节点不能同时作为前置和排除条件 " + str(other)
	# 三色遍历仅检查前置环；排除条件不当作依赖边，不擅自规定互斥组完成规则。
	var visiting: Dictionary = {}
	var visited: Dictionary = {}
	for id in by_id:
		if _has_cycle(str(id), by_id, visiting, visited):
			return path + ".nodes." + str(id) + ".requires_completed: 前置关系存在循环"
	return ""


static func _validate_node(node: Dictionary, items: Dictionary, activities: Array, path: String) -> String:
	var error := _unknown_fields(node, ["id", "name", "note", "enabled", "kind", "order", "checkpoints", "requires_completed", "excludes_completed", "conditions", "variants", "costs", "rewards"], path)
	if not error.is_empty():
		return error
	if not _text(node.get("name")) or not KINDS.has(node.get("kind")):
		return path + ": 需要非空 name，kind 只支持 main 或 side"
	if node.has("note") and not node.note is String:
		return path + ".note: 需要字符串"
	if node.has("enabled") and not node.enabled is bool:
		return path + ".enabled: 需要布尔值"
	if not _integer(node.get("order", 0), 0):
		return path + ".order: 需要非负整数，越小越靠前"
	error = _string_list(node.get("checkpoints"), path + ".checkpoints", CHECKPOINTS)
	if not error.is_empty():
		return error
	if node.checkpoints.is_empty():
		return path + ".checkpoints: 至少指定一个检查点"
	for field in ["requires_completed", "excludes_completed"]:
		error = _string_list(node.get(field, []), path + "." + field)
		if not error.is_empty():
			return error
	var conditions = node.get("conditions", {})
	if not conditions is Dictionary:
		return path + ".conditions: 需要对象"
	error = _unknown_fields(conditions, ["turn_min", "turn_max", "growth_phases", "total_a_gt", "inventory_min"], path + ".conditions")
	if not error.is_empty():
		return error
	for field in ["turn_min", "turn_max", "total_a_gt"]:
		if conditions.has(field) and not _integer(conditions[field], 0 if field == "total_a_gt" else 1):
			return path + ".conditions." + field + ": 需要合法整数，回合从 1 开始，属性阈值不能为负"
	if conditions.has("turn_max") and int(conditions.turn_max) < int(conditions.get("turn_min", 1)):
		return path + ".conditions.turn_max: 不能小于 turn_min"
	if conditions.has("growth_phases"):
		if not conditions.growth_phases is Array or conditions.growth_phases.is_empty():
			return path + ".conditions.growth_phases: 需要非空的 0/1/2 数组"
		var seen: Array[int] = []
		for stage in conditions.growth_phases:
			if not _integer(stage, 0) or int(stage) > 2 or seen.has(int(stage)):
				return path + ".conditions.growth_phases: 阶段必须为 0/1/2 且不重复"
			seen.append(int(stage))
	error = Content.validate_amounts(conditions.get("inventory_min", {}), items, path + ".conditions.inventory_min", false)
	if not error.is_empty():
		return error
	error = Content.validate_amounts(node.get("costs", {}), items, path + ".costs", false)
	if not error.is_empty():
		return error
	var rewards = node.get("rewards", {})
	if not rewards is Dictionary:
		return path + ".rewards: 需要对象"
	error = _unknown_fields(rewards, ["items", "activities", "unlock_timing"], path + ".rewards")
	if not error.is_empty():
		return error
	error = Content.validate_amounts(rewards.get("items", {}), items, path + ".rewards.items", false)
	if not error.is_empty():
		return error
	error = _string_list(rewards.get("activities", []), path + ".rewards.activities")
	if not error.is_empty():
		return error
	var activity_ids: Array[String] = []
	for activity in activities:
		activity_ids.append(str(activity.id))
	for id in rewards.get("activities", []):
		if not activity_ids.has(id):
			return path + ".rewards.activities: 未知活动 " + str(id)
	if not ["immediate", "next_turn"].has(rewards.get("unlock_timing", "next_turn")):
		return path + ".rewards.unlock_timing: 只支持 immediate 或 next_turn"
	if not node.get("variants") is Dictionary:
		return path + ".variants: 需要表现版本对象"
	var variants: Dictionary = node.variants
	error = _unknown_fields(variants, STAGES if node.kind == "main" else STAGES + ["default"], path + ".variants")
	if not error.is_empty():
		return error
	# 主线三份表现共用同一个逻辑 ID；支线允许公共版本，不强制三倍内容量。
	for key in (STAGES if node.kind == "main" else ["default"]):
		if not variants.has(key):
			return path + ".variants." + str(key) + ": 缺少表现版本"
	for key in variants:
		error = _validate_variant(variants[key], path + ".variants." + str(key))
		if not error.is_empty():
			return error
	return ""


static func _validate_variant(variant: Variant, path: String) -> String:
	if not variant is Dictionary:
		return path + ": 需要对象"
	var error := _unknown_fields(variant, ["lines", "portrait"], path)
	if not error.is_empty():
		return error
	if not variant.get("lines") is Array or variant.lines.is_empty():
		return path + ".lines: 至少需要一行对话"
	for i in range(variant.lines.size()):
		var line = variant.lines[i]
		var location := path + ".lines[%d]" % i
		if not line is Dictionary:
			return location + ": 需要对象"
		error = _unknown_fields(line, ["speaker", "text"], location)
		if not error.is_empty():
			return error
		if not line.get("speaker") is String or not _text(line.get("text")):
			return location + ": speaker 必须为字符串（旁白可留空），text 不能为空"
	if variant.has("portrait"):
		var portrait = variant.portrait
		if not portrait is Dictionary:
			return path + ".portrait: 需要 texture 和可选 region 的对象"
		error = _unknown_fields(portrait, ["texture", "region"], path + ".portrait")
		if not error.is_empty():
			return error
		if not _text(portrait.get("texture")) or not str(portrait.texture).begins_with("res://") or not ResourceLoader.exists(portrait.texture):
			return path + ".portrait.texture: 需要存在的 res:// 图像资源"
		var texture = load(portrait.texture)
		if not texture is Texture2D:
			return path + ".portrait.texture: 资源必须为 Texture2D"
		if portrait.has("region"):
			var region = portrait.region
			if not region is Array or region.size() != 4:
				return path + ".portrait.region: 需要 [x, y, width, height]"
			for i in range(4):
				if not _integer(region[i], 0 if i < 2 else 1):
					return path + ".portrait.region: 坐标为非负整数，宽高为正整数"
			if region[0] + region[2] > texture.get_width() or region[1] + region[3] > texture.get_height():
				return path + ".portrait.region: 裁剪区域超出图像尺寸"
	return ""


## 返回不满足条件的原因；conditions 内所有条件都必须满足，不支持任意表达式。
static func blocking_reasons(node: Dictionary, context: Dictionary, checkpoint: String, kind: String) -> Array[String]:
	var reasons: Array[String] = []
	if not CHECKPOINTS.has(checkpoint) or not KINDS.has(kind):
		reasons.append("未知剧情检查点或类型")
		return reasons
	if not bool(node.get("enabled", true)):
		reasons.append("节点已禁用")
	if node.kind != kind or not node.checkpoints.has(checkpoint):
		reasons.append("不属于当前检查点或类型")
	var completed: Array = context.completed
	if completed.has(node.id):
		reasons.append("节点已经完成")
	for id in node.get("requires_completed", []):
		if not completed.has(id):
			reasons.append("前置节点未完成: " + str(id))
	for id in node.get("excludes_completed", []):
		if completed.has(id):
			reasons.append("命中已完成的排除节点: " + str(id))
	var conditions: Dictionary = node.get("conditions", {})
	if int(context.turn) < int(conditions.get("turn_min", 1)):
		reasons.append("尚未到允许回合")
	if conditions.has("turn_max") and int(context.turn) > int(conditions.turn_max):
		reasons.append("已经超过允许回合")
	if conditions.has("growth_phases") and not conditions.growth_phases.has(int(context.growth_phase)):
		reasons.append("当前成长阶段不允许触发")
	if conditions.has("total_a_gt"):
		var total_a := 0
		for value in context.base_stats.values():
			total_a += int(value)
		if total_a <= int(conditions.total_a_gt):
			reasons.append("永久属性总和须大于 %d（当前 %d）" % [int(conditions.total_a_gt), total_a])
	for id in conditions.get("inventory_min", {}):
		if int(context.inventory.get(id, 0)) < int(conditions.inventory_min[id]):
			reasons.append("库存不足: " + str(id))
	for id in node.get("costs", {}):
		if int(context.inventory.get(id, 0)) < int(node.costs[id]):
			reasons.append("剧情消耗材料不足: " + str(id))
	return reasons


## 一次只查询一个主/支线检查点；返回排序后的 ID，不自动串联、不标记完成。
static func candidates(config: Dictionary, context: Dictionary, checkpoint: String, kind: String) -> Array[String]:
	var nodes: Array[Dictionary] = []
	for node in config.nodes:
		if blocking_reasons(node, context, checkpoint, kind).is_empty():
			nodes.append(node)
	# 相同顺序值用稳定 ID 排序，不依赖 JSON 中的摆放位置。
	nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_order := int(a.get("order", 0))
		var b_order := int(b.get("order", 0))
		return str(a.id) < str(b.id) if a_order == b_order else a_order < b_order
	)
	var ids: Array[String] = []
	for node in nodes:
		ids.append(str(node.id))
	return ids


## 表现返回深复制，可供未来对话界面使用；改文字或裁剪不能污染内容模板。
static func presentation(config: Dictionary, id: String, growth_phase: int) -> Dictionary:
	if growth_phase < 0 or growth_phase > 2:
		return {}
	for node in config.nodes:
		if node.id == id:
			var key := str(growth_phase)
			if not node.variants.has(key):
				key = "default"
			return node.variants.get(key, {}).duplicate(true)
	return {}


static func _unknown_fields(data: Dictionary, allowed: Array, path: String) -> String:
	for key in data:
		if not allowed.has(key):
			return path + "." + str(key) + ": 未支持的字段，请检查拼写；土地、图纸、选择与并发组尚未接入"
	return ""


static func _string_list(value: Variant, path: String, allowed: Array = []) -> String:
	if not value is Array:
		return path + ": 需要字符串数组"
	var seen: Array[String] = []
	for entry in value:
		if not _text(entry) or seen.has(str(entry)) or (not allowed.is_empty() and not allowed.has(entry)):
			return path + ": 条目为空、重复或不在允许范围内"
		seen.append(str(entry))
	return ""


static func _integer(value: Variant, minimum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum


static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()


static func _has_cycle(id: String, nodes: Dictionary, visiting: Dictionary, visited: Dictionary) -> bool:
	if visiting.has(id):
		return true
	if visited.has(id):
		return false
	visiting[id] = true
	for prerequisite in nodes[id].get("requires_completed", []):
		if _has_cycle(str(prerequisite), nodes, visiting, visited):
			return true
	visiting.erase(id)
	visited[id] = true
	return false
