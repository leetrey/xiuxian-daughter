extends Node

# ScheduleManager 是“规则层”，同样在 project.godot 中注册为 Autoload。
# 界面只提交 action_id；这里负责检查条件、扣除成本并修改 GameState。

# 行动的展示字段集中放在数据表中，新增普通行动时通常只需：
# 1. 在这里增加定义；2. 在 execute_activity() 的 match 中增加效果。
# accent 是界面卡片的强调色，不参与玩法结算。
const ACTIVITIES := [
	{"id": "daughter_cultivate", "actor": "女儿", "title": "晨昏吐纳", "cost": 3, "summary": "修为大幅增长，道法提升，略增心魔", "accent": "6fba8c"},
	{"id": "daughter_sword", "actor": "女儿", "title": "庭中习剑", "cost": 2, "summary": "提升体魄，并积累少量修为", "accent": "d55f55"},
	{"id": "daughter_classics", "actor": "女儿", "title": "研读经义", "cost": 2, "summary": "提升仙缘，安定心神", "accent": "d6ac5b"},
	{"id": "daughter_alchemy", "actor": "女儿", "title": "辨药试丹", "cost": 3, "summary": "消耗 1 药材，提升杂学并获得灵石", "accent": "7fa85a"},
	{"id": "daughter_breakthrough", "actor": "女儿", "title": "叩问天关", "cost": 4, "summary": "修为圆满后主动破境，有失败风险", "accent": "df8f49"},
	{"id": "father_cultivate", "actor": "父亲", "title": "调息重修", "cost": 3, "summary": "修补旧伤，恢复父亲修为", "accent": "6aa8b5"},
	{"id": "father_breakthrough", "actor": "父亲", "title": "重筑道基", "cost": 4, "summary": "修为圆满后重返筑基，解锁宗门洞天", "accent": "77a6d1"},
	{"id": "father_gather", "actor": "父亲", "title": "入山采药", "cost": 2, "summary": "取得药材与少量灵石", "accent": "77a56b"},
	{"id": "father_work", "actor": "父亲", "title": "边城做工", "cost": 3, "summary": "赚取灵石，维持家中开销", "accent": "b9845e"},
	{"id": "cave_farm", "actor": "父亲", "title": "洞天种田", "cost": 2, "summary": "筑基后可用，稳定产出灵药", "accent": "65a66f"},
	{"id": "family_talk", "actor": "共同", "title": "秉烛夜谈", "cost": 2, "summary": "增进羁绊，逐步公开身世真相", "accent": "ca7b83"},
	{"id": "investigate", "actor": "共同", "title": "追查旧案", "cost": 3, "summary": "推动复仇倾向，也带来心魔压力", "accent": "9d6b72"},
	{"id": "rest", "actor": "共同", "title": "围炉小憩", "cost": 0, "summary": "每月一次，恢复 3 精力并降低心魔", "accent": "8fa7b3"},
]


func get_activities() -> Array:
	# 主界面读取这份列表并自动生成全部行动按钮。
	return ACTIVITIES


func get_activity(action_id: String) -> Dictionary:
	# 原型数据量很小，线性查找足够；内容增多后可改为 id -> Dictionary 索引。
	for activity in ACTIVITIES:
		if activity["id"] == action_id:
			return activity
	return {}


func lock_reason(action_id: String) -> String:
	# 空字符串代表行动已解锁，非空字符串同时用于禁用按钮和显示原因。
	# 这个函数只读状态，不扣资源，因此界面可以随时调用它刷新按钮。
	match action_id:
		"daughter_breakthrough":
			if GameState.daughter_realm >= GameState.REALM_NAMES.size() - 1:
				return "已达当前最高境界"
			if GameState.daughter_progress < 100:
				return "修为尚未圆满"
		"father_breakthrough":
			if GameState.father_realm >= 1:
				return "父亲已经重返筑基"
			if GameState.father_progress < 100:
				return "父亲修为尚未圆满"
		"cave_farm":
			if GameState.father_realm < 1:
				return "父亲筑基后解锁"
		"daughter_alchemy":
			if GameState.herbs < 1:
				return "至少需要 1 份药材"
		"investigate":
			if GameState.cycle_year < 2:
				return "第二年后才有旧案线索"
		"rest":
			if GameState.rest_used:
				return "本月已经休息过"
	return ""


func execute_activity(action_id: String) -> Dictionary:
	# 统一执行管线：
	# 1. 校验游戏状态和解锁条件。
	# 2. 校验共享精力。
	# 3. 计算重复行动衰减并应用具体效果。
	# 4. 扣精力、记录行动、触发失败判定和界面信号。
	if GameState.game_finished:
		return _result(false, "本局已经结束。", "error")

	var activity := get_activity(action_id)
	if activity.is_empty():
		return _result(false, "未知行动。", "error")

	var reason := lock_reason(action_id)
	if not reason.is_empty():
		return _result(false, reason, "error")

	var cost: int = activity["cost"]
	if GameState.energy < cost:
		return _result(false, "精力不足，无法执行这项日程。", "error")

	# 同一行动当月每重复一次，效率降低 18%，最低保留 55% 收益。
	# 月底 GameState 会清空 monthly_action_counts。
	var times := int(GameState.monthly_action_counts.get(action_id, 0))
	var efficiency := maxf(0.55, 1.0 - 0.18 * times)
	var message := ""
	var tone := "growth"

	# match 是原型阶段的行动效果表。以后可把纯数值行动迁移到 JSON，
	# 把破境等含特殊逻辑的行动继续保留为代码处理。
	match action_id:
		"daughter_cultivate":
			var cultivation_gain := _scaled(22, efficiency)
			var dao_gain := _gain_stat("dao", 3, efficiency)
			GameState.daughter_progress = mini(100, GameState.daughter_progress + cultivation_gain)
			GameState.heart_demon = mini(100, GameState.heart_demon + 2)
			message = "她按你教的法门运转周天。修为 +%d，道法 +%d。" % [cultivation_gain, dao_gain]
		"daughter_sword":
			var physique_gain := _gain_stat("physique", 4, efficiency)
			var progress_gain := _scaled(8, efficiency)
			GameState.daughter_progress = mini(100, GameState.daughter_progress + progress_gain)
			GameState.heart_demon = mini(100, GameState.heart_demon + 1)
			message = "剑锋还显稚嫩，脚步却稳了许多。体魄 +%d，修为 +%d。" % [physique_gain, progress_gain]
		"daughter_classics":
			var affinity_gain := _gain_stat("affinity", 4, efficiency)
			GameState.heart_demon = maxi(0, GameState.heart_demon - 2)
			message = "她把经义读给你听，偶尔停下来问一句旧事。仙缘 +%d。" % affinity_gain
		"daughter_alchemy":
			GameState.herbs -= 1
			var arts_gain := _gain_stat("arts", 5, efficiency)
			var income := _scaled(14, efficiency)
			GameState.spirit_stones += income
			message = "丹炉里升起清苦药香。杂学 +%d，灵石 +%d。" % [arts_gain, income]
		"daughter_breakthrough":
			# 破境不会自动发生，而是玩家主动安排的一项行动。
			var outcome := _daughter_breakthrough()
			if not outcome["ok"]:
				return outcome
			message = outcome["message"]
			tone = outcome["tone"]
		"father_cultivate":
			var father_gain := _scaled(26, efficiency)
			GameState.father_progress = mini(100, GameState.father_progress + father_gain)
			message = "你压下金丹碎裂留下的暗伤，旧日经脉又通了一分。父亲修为 +%d。" % father_gain
		"father_breakthrough":
			# 父亲是在恢复旧境界，因此当前原型使用确定成功的资源门槛。
			if GameState.spirit_stones < 35 or GameState.herbs < 1:
				return _result(false, "重筑道基需要 35 灵石与 1 份药材。", "error")
			GameState.spirit_stones -= 35
			GameState.herbs -= 1
			GameState.father_realm = 1
			GameState.father_progress = 0
			message = "破碎的道基重新合拢。你重返筑基，也再次感应到了宗门洞天。"
			tone = "breakthrough"
		"father_gather":
			var herb_gain := _scaled(3, efficiency)
			var gather_income := _scaled(8, efficiency)
			GameState.herbs += herb_gain
			GameState.spirit_stones += gather_income
			message = "你从熟悉的山路带回一篓药草。药材 +%d，灵石 +%d。" % [herb_gain, gather_income]
		"father_work":
			var work_income := _scaled(46, efficiency)
			GameState.spirit_stones += work_income
			message = "你在边城忙到暮色四合。灵石 +%d。" % work_income
		"cave_farm":
			var cave_herbs := _scaled(7, efficiency)
			GameState.herbs += cave_herbs
			message = "洞天灵土仍认得旧主，新苗在雾气里舒展。药材 +%d。" % cave_herbs
		"family_talk":
			GameState.bond = mini(100, GameState.bond + _scaled(4, efficiency))
			GameState.truth_revealed = mini(100, GameState.truth_revealed + _scaled(7, efficiency))
			GameState.heart_demon = maxi(0, GameState.heart_demon - 4)
			message = "你讲起青云宗的旧事，没有再把每一句都咽回去。羁绊加深。"
			tone = "story"
		"investigate":
			GameState.vengeance = mini(100, GameState.vengeance + _scaled(8, efficiency))
			GameState.truth_revealed = mini(100, GameState.truth_revealed + 2)
			GameState.heart_demon = mini(100, GameState.heart_demon + 4)
			message = "一枚旧宗门令牌把线索指向北方，旧恨也随之翻涌。"
			tone = "story"
		"rest":
			# 休息不消耗精力，但每月仅能执行一次，防止无限恢复。
			GameState.rest_used = true
			GameState.energy = mini(GameState.max_energy, GameState.energy + 3)
			GameState.bond = mini(100, GameState.bond + 2)
			GameState.heart_demon = maxi(0, GameState.heart_demon - 5)
			message = "炉火很小，屋里却暖。你们什么也没赶，只说了些寻常话。精力恢复 3。"
			tone = "rest"

	# 所有效果成功应用后才扣精力。资源不足等失败不会吞掉行动点。
	GameState.energy -= cost
	GameState.register_action(action_id)

	# 即时检查心魔，保证“道陨”优先于后续所有成就类结局。
	if GameState.heart_demon >= 100:
		GameState.finish_ending("道陨", "执念吞没了道心。山中长风依旧，她却没能走出这一劫。")
	else:
		GameState.state_changed.emit()
		GameState.feedback_emitted.emit(message, tone)

	return _result(true, message, tone)


func _daughter_breakthrough() -> Dictionary:
	# 境界越高，破境所需灵石和药材越多。
	var stone_cost := 40 + GameState.daughter_realm * 35
	var herb_cost := 2 + GameState.daughter_realm
	if GameState.spirit_stones < stone_cost or GameState.herbs < herb_cost:
		return _result(false, "破境需要 %d 灵石与 %d 份药材。" % [stone_cost, herb_cost], "error")

	GameState.spirit_stones -= stone_cost
	GameState.herbs -= herb_cost
	var insight := int(GameState.daughter_stats["dao"])
	# 基础成功率 72%，道法提高成功率，心魔降低成功率。
	# 30%-95% 的边界保留了失败风险，也避免极端数值让突破必败。
	var success_chance := clampf(0.72 + insight * 0.004 - GameState.heart_demon * 0.005, 0.30, 0.95)

	if randf() <= success_chance:
		GameState.daughter_realm += 1
		GameState.daughter_progress = 0
		GameState.heart_demon = maxi(0, GameState.heart_demon - 8)
		for key in GameState.daughter_stats:
			GameState.daughter_stats[key] = mini(100, int(GameState.daughter_stats[key]) + 2)
		return _result(true, "灵息冲开天关，她踏入%s。所有主属性 +2。" % GameState.daughter_realm_name(), "breakthrough")

	GameState.daughter_progress = 55
	GameState.heart_demon = mini(100, GameState.heart_demon + 14)
	return _result(true, "天关未开，灵气反噬。修为回落，心魔明显增长。", "danger")


func _gain_stat(key: String, base_amount: int, efficiency: float) -> int:
	# 返回实际增量，方便反馈文本展示本次获得了多少属性。
	var amount := _scaled(base_amount, efficiency)
	GameState.daughter_stats[key] = mini(100, int(GameState.daughter_stats[key]) + amount)
	return amount


func _scaled(base_amount: int, efficiency: float) -> int:
	return maxi(1, roundi(base_amount * efficiency))


func _result(ok: bool, message: String, tone: String) -> Dictionary:
	# 所有行动返回相同结构，界面无需知道每种行动的内部实现。
	return {"ok": ok, "message": message, "tone": tone}
