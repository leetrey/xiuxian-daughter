extends Control

# Main 是“表现层”：创建控件、收集玩家输入、把 GameState 渲染到界面。
# 它不直接计算行动收益，所有规则都交给 ScheduleManager，便于以后换 UI。

# 原型主题色集中定义，构建控件时复用，避免颜色散落在各函数中。
const COLOR_PAPER := Color("f4f0e5")
const COLOR_MUTED := Color("aeb9b0")
const COLOR_JADE := Color("65a875")
const COLOR_GOLD := Color("d1a657")
const COLOR_RED := Color("bf6259")
const COLOR_PANEL := Color("17231fe8")
const COLOR_PANEL_LIGHT := Color("22312bea")

# 下列引用在构建 UI 时赋值，之后由刷新和交互函数统一使用。
var activity_grid: GridContainer
var queue_flow: HFlowContainer
var queue_label: Label
var execute_button: Button
var undo_button: Button
var next_month_button: Button

var time_label: Label
var energy_label: Label
var resource_label: Label
var daughter_realm_label: Label
var daughter_progress: ProgressBar
var father_realm_label: Label
var father_progress: ProgressBar
var stat_labels := {}
var bond_label: Label
var heart_label: Label
var stance_label: Label
var feedback_label: RichTextLabel
var sect_label: Label

# 日程队列只存行动 id，不提前改变 GameState；按“执行”后才真正结算。
var scheduled_actions: Array[String] = []
var activity_buttons := {}
var ending_overlay: ColorRect
var ending_title_label: Label
var ending_description_label: Label


func _ready() -> void:
	# 先创建界面，再连接全局信号，最后执行一次初始渲染。
	# 信号连接让规则层和界面层解耦：规则只广播“状态变了”。
	theme = _build_theme()
	_build_interface()
	GameState.state_changed.connect(_refresh)
	GameState.feedback_emitted.connect(_show_feedback)
	GameState.game_ended.connect(_show_ending)
	_refresh()
	_show_feedback("她把第一本吐纳诀放在膝上，等你开口。", "story")


func _build_interface() -> void:
	# 画面按添加顺序从底到顶分为：兜底色、背景图、暗色遮罩、交互界面。
	# 即使背景素材暂时缺失，兜底色也能保证界面可读。
	var fallback := ColorRect.new()
	fallback.color = Color("314c40")
	fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fallback)

	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://assets/cultivation_home.png"):
		background.texture = load("res://assets/cultivation_home.png")
	add_child(background)

	# 遮罩压低背景对比度，避免背景细节影响按钮和文字辨识。
	var veil := ColorRect.new()
	veil.color = Color("0c1611a8")
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)

	# 页面纵向分成顶部资源栏、中部内容区、底部日程栏。
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	margin.add_child(page)
	page.add_child(_build_header())
	page.add_child(_build_content())
	page.add_child(_build_schedule_bar())
	_build_ending_overlay()


func _build_header() -> Control:
	# 顶栏只展示全局概览：时间、共享精力和家庭资源。
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 72
	panel.add_theme_stylebox_override("panel", _panel_style(COLOR_PANEL, 6, Color("66827090"), 1))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	margin.add_child(row)

	var brand := VBoxContainer.new()
	brand.custom_minimum_size.x = 300
	brand.add_theme_constant_override("separation", 0)
	brand.add_child(_make_label("山河养成录", 28, COLOR_PAPER))
	brand.add_child(_make_label("青云旧事 · 原型章", 13, COLOR_MUTED))
	row.add_child(brand)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	time_label = _make_label("", 17, COLOR_PAPER)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(time_label)
	energy_label = _make_label("", 17, COLOR_GOLD)
	energy_label.custom_minimum_size.x = 128
	energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(energy_label)
	resource_label = _make_label("", 16, COLOR_PAPER)
	resource_label.custom_minimum_size.x = 180
	resource_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(resource_label)
	return panel


func _build_content() -> Control:
	# 中部左侧是可滚动行动列表，右侧是父女状态与本月札记。
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)

	var actions_panel := PanelContainer.new()
	actions_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_panel.add_theme_stylebox_override("panel", _panel_style(COLOR_PANEL, 6, Color("66827070"), 1))
	row.add_child(actions_panel)

	var actions_margin := MarginContainer.new()
	actions_margin.add_theme_constant_override("margin_left", 18)
	actions_margin.add_theme_constant_override("margin_right", 18)
	actions_margin.add_theme_constant_override("margin_top", 15)
	actions_margin.add_theme_constant_override("margin_bottom", 15)
	actions_panel.add_child(actions_margin)

	var actions_column := VBoxContainer.new()
	actions_column.add_theme_constant_override("separation", 10)
	actions_margin.add_child(actions_column)
	var actions_heading := HBoxContainer.new()
	actions_heading.add_child(_make_label("安排本月行动", 22, COLOR_PAPER))
	var actions_heading_spacer := Control.new()
	actions_heading_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_heading.add_child(actions_heading_spacer)
	actions_heading.add_child(_make_label("重复行动收益递减", 13, COLOR_MUTED))
	actions_column.add_child(actions_heading)
	var rule := HSeparator.new()
	rule.modulate = Color("66827090")
	actions_column.add_child(rule)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	actions_column.add_child(scroll)
	activity_grid = GridContainer.new()
	activity_grid.columns = 2
	activity_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	activity_grid.add_theme_constant_override("h_separation", 10)
	activity_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(activity_grid)
	_build_activity_buttons()
	row.add_child(_build_status_panel())
	return row


func _build_activity_buttons() -> void:
	# 按 ACTIVITIES 数据自动生成按钮。以后增加行动时无需手写新的 UI 节点。
	for activity in ScheduleManager.get_activities():
		var button := Button.new()
		button.custom_minimum_size = Vector2(310, 78)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 16)
		button.add_theme_color_override("font_color", COLOR_PAPER)
		button.add_theme_color_override("font_disabled_color", Color("89928d"))
		button.add_theme_stylebox_override("normal", _panel_style(Color("26362fef"), 5, Color(activity["accent"] + "88"), 1))
		button.add_theme_stylebox_override("hover", _panel_style(Color("31483cef"), 5, Color(activity["accent"]), 1))
		button.add_theme_stylebox_override("pressed", _panel_style(Color("1d2d27f4"), 5, COLOR_GOLD, 2))
		button.add_theme_stylebox_override("disabled", _panel_style(Color("202823d9"), 5, Color("58615d70"), 1))
		# bind 把当前 action_id 固定到回调中，所有按钮共用同一个处理函数。
		button.pressed.connect(_queue_activity.bind(activity["id"]))
		activity_grid.add_child(button)
		activity_buttons[activity["id"]] = button


func _build_status_panel() -> Control:
	# 状态面板把数值拆成女儿成长、父亲重修、关系/剧情三块。
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 390
	panel.add_theme_stylebox_override("panel", _panel_style(COLOR_PANEL_LIGHT, 6, Color("66827070"), 1))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var daughter_header := HBoxContainer.new()
	daughter_header.add_child(_make_label("宁宁", 24, COLOR_PAPER))
	var daughter_header_spacer := Control.new()
	daughter_header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	daughter_header.add_child(daughter_header_spacer)
	sect_label = _make_label("", 13, COLOR_GOLD)
	daughter_header.add_child(sect_label)
	column.add_child(daughter_header)
	daughter_realm_label = _make_label("", 16, Color("c8e0cf"))
	column.add_child(daughter_realm_label)
	daughter_progress = _make_progress(COLOR_JADE)
	column.add_child(daughter_progress)

	var stats_grid := GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 12)
	stats_grid.add_theme_constant_override("v_separation", 5)
	for stat in [["physique", "体魄"], ["dao", "道法"], ["affinity", "仙缘"], ["arts", "杂学"]]:
		var stat_label := _make_label("", 15, COLOR_PAPER)
		stats_grid.add_child(stat_label)
		stat_labels[stat[0]] = {"label": stat_label, "name": stat[1]}
	column.add_child(stats_grid)

	var divider_one := HSeparator.new()
	divider_one.modulate = Color("66827080")
	column.add_child(divider_one)
	father_realm_label = _make_label("", 16, Color("c8dbe0"))
	column.add_child(father_realm_label)
	father_progress = _make_progress(Color("68a3af"))
	column.add_child(father_progress)
	var divider_two := HSeparator.new()
	divider_two.modulate = Color("66827080")
	column.add_child(divider_two)

	bond_label = _make_label("", 15, COLOR_PAPER)
	heart_label = _make_label("", 15, COLOR_PAPER)
	stance_label = _make_label("", 14, COLOR_MUTED)
	stance_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(bond_label)
	column.add_child(heart_label)
	column.add_child(stance_label)

	var feedback_panel := PanelContainer.new()
	feedback_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feedback_panel.add_theme_stylebox_override("panel", _panel_style(Color("111c18cc"), 4, Color("526b5f80"), 1))
	column.add_child(feedback_panel)
	var feedback_margin := MarginContainer.new()
	feedback_margin.add_theme_constant_override("margin_left", 12)
	feedback_margin.add_theme_constant_override("margin_right", 12)
	feedback_margin.add_theme_constant_override("margin_top", 10)
	feedback_margin.add_theme_constant_override("margin_bottom", 10)
	feedback_panel.add_child(feedback_margin)
	feedback_label = RichTextLabel.new()
	feedback_label.bbcode_enabled = true
	feedback_label.fit_content = false
	feedback_label.scroll_active = true
	feedback_label.add_theme_font_size_override("normal_font_size", 15)
	feedback_label.add_theme_color_override("default_color", COLOR_PAPER)
	feedback_margin.add_child(feedback_label)
	return panel


func _build_schedule_bar() -> Control:
	# 日程栏展示尚未执行的队列，并提供撤销、执行和结束本月三个命令。
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 118
	panel.add_theme_stylebox_override("panel", _panel_style(COLOR_PANEL, 6, Color("66827090"), 1))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var schedule_column := VBoxContainer.new()
	schedule_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	schedule_column.add_theme_constant_override("separation", 6)
	row.add_child(schedule_column)
	queue_label = _make_label("本月日程", 16, COLOR_MUTED)
	schedule_column.add_child(queue_label)
	queue_flow = HFlowContainer.new()
	queue_flow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	queue_flow.add_theme_constant_override("h_separation", 7)
	queue_flow.add_theme_constant_override("v_separation", 7)
	schedule_column.add_child(queue_flow)

	var controls := VBoxContainer.new()
	controls.custom_minimum_size.x = 188
	controls.add_theme_constant_override("separation", 7)
	row.add_child(controls)
	var edit_row := HBoxContainer.new()
	edit_row.add_theme_constant_override("separation", 7)
	controls.add_child(edit_row)
	undo_button = _make_command_button("撤销", false)
	undo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	undo_button.pressed.connect(_undo_schedule)
	edit_row.add_child(undo_button)
	execute_button = _make_command_button("执行", true)
	execute_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	execute_button.pressed.connect(_execute_schedule)
	edit_row.add_child(execute_button)
	next_month_button = _make_command_button("结束本月", false)
	next_month_button.pressed.connect(_advance_month)
	controls.add_child(next_month_button)
	return panel


func _build_ending_overlay() -> void:
	# 结局层最后加入场景树，所以显示时自然覆盖整个主界面并拦截鼠标。
	ending_overlay = ColorRect.new()
	ending_overlay.color = Color("07100de8")
	ending_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ending_overlay.visible = false
	ending_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(ending_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ending_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 300)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("1b2923fa"), 6, COLOR_GOLD, 2))
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_right", 42)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 34)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	column.add_child(_make_label("八年之后", 15, COLOR_GOLD))
	ending_title_label = _make_label("", 34, COLOR_PAPER)
	ending_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(ending_title_label)
	ending_description_label = _make_label("", 17, COLOR_MUTED)
	ending_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ending_description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(ending_description_label)
	var restart := _make_command_button("重新开始", true)
	restart.custom_minimum_size.x = 180
	restart.pressed.connect(_restart)
	column.add_child(restart)


func _queue_activity(action_id: String) -> void:
	# 加入队列前只做“当前状态下”的轻量校验，不立即扣精力或资源。
	# projected_cost 防止队列中的总成本超过当前共享精力。
	var activity := ScheduleManager.get_activity(action_id)
	var reason := ScheduleManager.lock_reason(action_id)
	if not reason.is_empty():
		_show_feedback(reason, "error")
		return
	var projected_cost := _scheduled_cost() + int(activity["cost"])
	if projected_cost > GameState.energy:
		_show_feedback("当前日程会超过共享精力，请先执行或调整安排。", "error")
		return
	if action_id == "rest" and scheduled_actions.has("rest"):
		_show_feedback("本月只能安排一次围炉小憩。", "error")
		return
	scheduled_actions.append(action_id)
	_refresh_schedule()


func _undo_schedule() -> void:
	# 日程是有顺序的，因此撤销最近加入的一项即可。
	if scheduled_actions.is_empty():
		return
	scheduled_actions.pop_back()
	_refresh_schedule()


func _execute_schedule() -> void:
	# 复制队列后立即清空原队列，避免执行期间的状态刷新重复结算。
	# 每项行动依次进入 ScheduleManager；任一项失败就停止剩余日程。
	if scheduled_actions.is_empty():
		_show_feedback("先为这个月安排一项行动。", "error")
		return
	var actions_to_run := scheduled_actions.duplicate()
	scheduled_actions.clear()
	for action_id in actions_to_run:
		var result := ScheduleManager.execute_activity(action_id)
		if not result["ok"]:
			_show_feedback(result["message"], result["tone"])
			break
		if GameState.game_finished:
			break
	_refresh_schedule()


func _advance_month() -> void:
	# 防止玩家误把已安排但尚未执行的日程直接跳过。
	if not scheduled_actions.is_empty():
		_show_feedback("还有未执行的日程，请先执行或逐项撤销。", "error")
		return
	GameState.advance_month()


func _refresh() -> void:
	# 这是 GameState -> UI 的单向渲染入口。
	# 任何系统修改状态并发出 state_changed 后，所有可见信息在这里同步。
	time_label.text = "第 %d 年 · %d 月｜%d 岁" % [GameState.cycle_year, GameState.month, GameState.daughter_age]
	energy_label.text = "共享精力 %d/%d" % [GameState.energy, GameState.max_energy]
	resource_label.text = "灵石 %d｜药材 %d" % [GameState.spirit_stones, GameState.herbs]
	daughter_realm_label.text = "女儿境界  %s  ·  修为 %d/100" % [GameState.daughter_realm_name(), GameState.daughter_progress]
	daughter_progress.value = GameState.daughter_progress
	for key in stat_labels:
		var item: Dictionary = stat_labels[key]
		item["label"].text = "%s  %02d" % [item["name"], GameState.daughter_stats[key]]
	father_realm_label.text = "父亲修为  %s  ·  重修 %d/100" % [GameState.father_realm_name(), GameState.father_progress]
	father_progress.value = GameState.father_progress
	bond_label.text = "父女羁绊  %d/100" % GameState.bond
	heart_label.text = "心魔压力  %d/100" % GameState.heart_demon
	heart_label.modulate = COLOR_RED if GameState.heart_demon >= 70 else COLOR_PAPER
	stance_label.text = "旧案心境：%s｜身世线索：%s" % [GameState.vengeance_descriptor(), GameState.truth_descriptor()]
	sect_label.text = GameState.sect_status

	# 解锁条件可能随一次行动立刻改变，例如父亲筑基后洞天种田立即可用。
	for activity in ScheduleManager.get_activities():
		var button: Button = activity_buttons[activity["id"]]
		var reason := ScheduleManager.lock_reason(activity["id"])
		button.disabled = not reason.is_empty() or GameState.game_finished
		button.tooltip_text = reason if not reason.is_empty() else activity["summary"]
		var suffix := "\n%s" % activity["summary"]
		if not reason.is_empty():
			suffix = "\n锁定：%s" % reason
		button.text = "%s · %s    %d 精力%s" % [activity["actor"], activity["title"], activity["cost"], suffix]
	next_month_button.disabled = GameState.game_finished
	_refresh_schedule()


func _refresh_schedule() -> void:
	# 队列较短，直接重建标签比维护节点差异更简单，也更不容易显示旧数据。
	for child in queue_flow.get_children():
		child.queue_free()
	if scheduled_actions.is_empty():
		queue_flow.add_child(_make_label("尚未安排。选择上方行动加入日程。", 14, Color("829089")))
	else:
		for action_id in scheduled_actions:
			var activity := ScheduleManager.get_activity(action_id)
			var chip := Label.new()
			chip.text = "%s  -%d" % [activity["title"], activity["cost"]]
			chip.add_theme_font_size_override("font_size", 14)
			chip.add_theme_color_override("font_color", COLOR_PAPER)
			chip.add_theme_stylebox_override("normal", _panel_style(Color(activity["accent"] + "55"), 4, Color(activity["accent"]), 1))
			queue_flow.add_child(chip)
	queue_label.text = "本月日程  已用 %d/%d 精力" % [_scheduled_cost(), GameState.energy]
	execute_button.disabled = scheduled_actions.is_empty() or GameState.game_finished
	undo_button.disabled = scheduled_actions.is_empty() or GameState.game_finished


func _scheduled_cost() -> int:
	# 队列只保存 id，所以成本始终从行动定义读取，避免保存两份数据。
	var total := 0
	for action_id in scheduled_actions:
		total += int(ScheduleManager.get_activity(action_id)["cost"])
	return total


func _show_feedback(message: String, tone: String) -> void:
	# tone 只决定反馈颜色，不影响游戏逻辑。
	# RichTextLabel 允许同一块区域同时表现小标题和正文层级。
	if feedback_label == null:
		return
	var color := "#f4f0e5"
	match tone:
		"growth": color = "#b9dbbf"
		"breakthrough": color = "#e7bd68"
		"danger": color = "#e58a80"
		"error": color = "#d99188"
		"rest": color = "#b8ced5"
		"story": color = "#e0c7a1"
	feedback_label.text = "[color=#91a199][font_size=13]本月札记[/font_size][/color]\n[color=%s]%s[/color]" % [color, message]


func _show_ending(title: String, description: String) -> void:
	# GameState 决定得到什么结局，Main 只负责展示结果。
	ending_title_label.text = title
	ending_description_label.text = description
	ending_overlay.visible = true


func _restart() -> void:
	scheduled_actions.clear()
	ending_overlay.visible = false
	GameState.reset_game()


func _make_progress(fill_color: Color) -> ProgressBar:
	# 以下是小型 UI 工厂函数，用于统一控件尺寸和样式。
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 10
	bar.max_value = 100
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _panel_style(Color("0e1714"), 3))
	bar.add_theme_stylebox_override("fill", _panel_style(fill_color, 3))
	return bar


func _make_label(text_value: String, size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text_value
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	return result


func _make_command_button(text_value: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 38
	button.add_theme_font_size_override("font_size", 15)
	var normal_color := Color("416e50") if primary else Color("293b33")
	var hover_color := Color("50845f") if primary else Color("354c41")
	button.add_theme_stylebox_override("normal", _panel_style(normal_color, 4, Color("7fa58b80"), 1))
	button.add_theme_stylebox_override("hover", _panel_style(hover_color, 4, COLOR_GOLD, 1))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("203129"), 4, COLOR_GOLD, 2))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("222a26"), 4))
	return button


func _panel_style(color: Color, radius: int = 4, border_color: Color = Color.TRANSPARENT, border_width: int = 0) -> StyleBoxFlat:
	# Godot 的 StyleBoxFlat 类似一块可复用的 CSS 面板样式。
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


func _build_theme() -> Theme:
	# 优先使用系统中文字体；候选列表让工程在不同操作系统上仍有回退。
	var result := Theme.new()
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray(["PingFang SC", "Noto Sans CJK SC", "Microsoft YaHei"])
	system_font.font_weight = 500
	result.default_font = system_font
	result.default_font_size = 16
	result.set_color("font_color", "Label", COLOR_PAPER)
	result.set_color("font_color", "Button", COLOR_PAPER)
	return result
