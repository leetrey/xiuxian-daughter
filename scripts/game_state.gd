extends Node

# GameState 是全局状态仓库，在 project.godot 中注册为 Autoload。
# 其他脚本通过 GameState.xxx 读写同一份数据，因此切换场景也不会丢失进度。

# 界面只监听信号，不需要每帧轮询状态：
# - state_changed：数值发生变化，要求界面整体刷新。
# - feedback_emitted：显示本次行动或月底结算的叙事反馈。
# - game_ended：打开结局界面。
signal state_changed
signal feedback_emitted(message: String, tone: String)
signal game_ended(title: String, description: String)

# 境界使用数组下标保存，例如 0 表示炼气、1 表示筑基。
const REALM_NAMES := ["炼气", "筑基", "金丹", "元婴", "化神"]
const MAX_MONTHS := 96

# 时间状态。八年共 96 个行动月，女儿每跨过 12 个月增长一岁。
var cycle_year := 1
var month := 1
var daughter_age := 10
var elapsed_months := 0

# 父女共享同一个精力槽和家庭库存。
var max_energy := 10
var energy := 10
var spirit_stones := 120
var herbs := 2

# 父女各自拥有境界和修为进度，但行动时消耗上面的共享精力。
var daughter_realm := 0
var daughter_progress := 12
var father_realm := 0
var father_progress := 52

# 原型先用四项聚合属性跑通玩法，后续可替换成 GDD 中的 16 项细分属性。
var daughter_stats := {
	"physique": 12,
	"dao": 14,
	"affinity": 11,
	"arts": 8,
}
var bond := 50
var heart_demon := 8

# 两条隐藏轴相互独立：坦白真相不等于选择复仇。
var vengeance := 35
var truth_revealed := 5

# 每月临时状态在 advance_month() 中重置。
var sect_status := "尚未入门"
var monthly_action_counts := {}
var rest_used := false
var action_history: Array[String] = []

# 结局触发后锁住所有行动，并把结果交给界面展示。
var game_finished := false
var ending_title := ""
var ending_description := ""


func reset_game() -> void:
	# 集中重置所有可变数据，确保“重新开始”和首次开局使用同一套初值。
	cycle_year = 1
	month = 1
	daughter_age = 10
	elapsed_months = 0
	max_energy = 10
	energy = max_energy
	spirit_stones = 120
	herbs = 2
	daughter_realm = 0
	daughter_progress = 12
	father_realm = 0
	father_progress = 52
	daughter_stats = {"physique": 12, "dao": 14, "affinity": 11, "arts": 8}
	bond = 50
	heart_demon = 8
	vengeance = 35
	truth_revealed = 5
	sect_status = "尚未入门"
	monthly_action_counts.clear()
	rest_used = false
	action_history.clear()
	game_finished = false
	ending_title = ""
	ending_description = ""
	state_changed.emit()
	feedback_emitted.emit("新的八年，从边城这间小屋开始。", "story")


func advance_month() -> void:
	# 月底结算顺序：家庭开销 -> 时间推进 -> 月度资源刷新 ->
	# 固定剧情节点 -> 失败/结局判定 -> 通知界面。
	if game_finished:
		return

	var notes: Array[String] = []
	# 开销随年份缓慢增加，让父亲做工和资源经营始终有价值。
	var upkeep := 30 + (cycle_year - 1) * 5
	if spirit_stones >= upkeep:
		spirit_stones -= upkeep
		notes.append("本月家用支出 %d 灵石。" % upkeep)
	else:
		spirit_stones = 0
		heart_demon = mini(100, heart_demon + 8)
		notes.append("家用不足，她看出了你的窘迫，心魔有所增长。")

	elapsed_months += 1
	month += 1
	if month > 12:
		month = 1
		cycle_year += 1
		daughter_age += 1
		notes.append("她迎来了 %d 岁的生辰。" % daughter_age)

	energy = max_energy
	monthly_action_counts.clear()
	rest_used = false

	# 第三年山门试炼失败不会截断主线，而是进入收入较低的杂役路线。
	if cycle_year == 3 and month == 1:
		if daughter_realm >= 1:
			sect_status = "外门弟子"
			notes.append("她通过山门试炼，正式成为外门弟子。")
		else:
			sect_status = "杂役弟子"
			notes.append("她未能通过试炼，暂以杂役弟子的身份留在宗门。")
	elif cycle_year >= 3 and sect_status != "尚未入门":
		var stipend := 18 if sect_status == "杂役弟子" else 32
		spirit_stones += stipend
		notes.append("宗门发下 %d 灵石月例。" % stipend)

	# 道陨是即时失败，所以必须早于八年期满的普通结局判定。
	if heart_demon >= 100:
		finish_ending("道陨", "执念吞没了道心。山中长风依旧，她却没能走出这一劫。")
		return

	if elapsed_months >= MAX_MONTHS:
		_determine_ending()
		return

	state_changed.emit()
	feedback_emitted.emit(_join_lines(notes), "month")


func finish_ending(title: String, description: String) -> void:
	# 所有结局都从这个入口收束，避免各系统分别操作结局界面。
	game_finished = true
	ending_title = title
	ending_description = description
	state_changed.emit()
	game_ended.emit(title, description)


func daughter_realm_name() -> String:
	return REALM_NAMES[daughter_realm]


func father_realm_name() -> String:
	return REALM_NAMES[father_realm]


func vengeance_descriptor() -> String:
	# 隐藏数值不直接显示，只向玩家提供有叙事意味的区间描述。
	if vengeance >= 70:
		return "决意追索"
	if vengeance >= 45:
		return "难平旧恨"
	if vengeance >= 20:
		return "克制观望"
	return "愿放旧事"


func truth_descriptor() -> String:
	if truth_revealed >= 75:
		return "真相已明"
	if truth_revealed >= 45:
		return "旧事渐显"
	if truth_revealed >= 15:
		return "察觉隐情"
	return "身世深埋"


func register_action(action_id: String) -> void:
	# 次数用于计算同月重复行动的收益衰减；历史记录为后续事件系统预留。
	monthly_action_counts[action_id] = int(monthly_action_counts.get(action_id, 0)) + 1
	action_history.append(action_id)
	if action_history.size() > 24:
		action_history.pop_front()


func _determine_ending() -> void:
	# 从上到下就是结局优先级，先匹配成功的分支立即结束判定。
	if heart_demon >= 100:
		finish_ending("道陨", "执念吞没了道心。")
	elif daughter_realm >= 4:
		finish_ending("飞升", "她越过化神天关，终于看见群山之外的天光。")
	elif vengeance >= 70 and daughter_realm >= 2:
		finish_ending("复仇雪恨", "旧案昭雪，但她选择如何记住这段血色岁月。")
	elif vengeance < 30 and truth_revealed >= 65 and bond >= 70:
		finish_ending("重建宗门", "你们以真相为基，重新点亮了青云宗的山门。")
	elif vengeance < 30 and bond >= 75:
		finish_ending("归隐", "你们没有回头，只在青山深处守住寻常岁月。")
	elif daughter_stats["arts"] >= 75:
		finish_ending("百艺通明", "她以手中技艺，在仙途上写下了自己的名字。")
	else:
		finish_ending("散修", "她不依山门，不循旧路，从此自在行走天地。")


func _join_lines(lines: Array[String]) -> String:
	var result := ""
	for line in lines:
		if not result.is_empty():
			result += "\n"
		result += line
	return result
