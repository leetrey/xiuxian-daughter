extends Control

# 场景与菜单只提交选择并展示结果，不在刷新时掷骰、扣费或增加属性。
# main.tscn 只提供根节点；运行时由 _build_* 创建控件，_refresh 同步数值。
const ThemeKit = preload("res://scripts/ui_theme.gd")
const TEXT := ThemeKit.INK
const MUTED := ThemeKit.MUTED
const ACCENT := ThemeKit.JADE
# 缓存控件引用，刷新时按槽位或属性 ID 更新，不反复创建整套界面。
var selectors: Array[OptionButton] = []
var slot_details: Array[Label] = []
var slot_tools: Array[Button] = []
var free_buttons: Dictionary = {}
var stat_labels: Dictionary = {}
var group_labels: Dictionary = {}
var summary_labels: Dictionary = {}
var energy_label: Label
var pressure_label: Label
var pressure_bar: ProgressBar
var status_label: Label
var notice: Label
var results: RichTextLabel
var planning: VBoxContainer
var journal: VBoxContainer
var schedule_scroll: ScrollContainer
var confirm_button: Button
var next_button: Button
var schedule_button: Button
var home_button: Button
var location_label: Label
var cave_view: Control
var home: Control
var portrait: TextureRect
var portrait_stage := -1
var idle_dialog: ConfirmationDialog
var overlay: Control
var modal: PanelContainer
var modal_title: Label
var work_page: VBoxContainer
var attributes_page: ScrollContainer
var activities_page: ScrollContainer
# 这些是界面临时状态，与 GameState.phase 无关；开关菜单不会推进回合。
var active_menu := ""
var in_cave := false
var elapsed := 0.0
var portrait_origin := Vector2.ZERO


## 按背景、场景内容、HUD、浮层的顺序添加节点，让前景控件覆盖场景并接收点击。
func _ready() -> void:
	if not GameState.config_error.is_empty():
		return
	theme = ThemeKit.make_theme()
	get_window().min_size = Vector2i(960, 540)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	home = Control.new()
	home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(home)
	var backdrop := TextureRect.new()
	backdrop.texture = load("res://assets/home_courtyard.png")
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.add_child(backdrop)
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	portrait.tooltip_text = "宁宁"
	portrait.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			open_menu("attributes"))
	home.add_child(portrait)
	_build_home_summary()
	cave_view = load("res://scenes/cave.tscn").instantiate()
	cave_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cave_view)
	cave_view.hide()
	_build_hud()
	_build_overlay()
	idle_dialog = ConfirmationDialog.new()
	idle_dialog.title = "生产安排"
	idle_dialog.ok_button_text = "仍然结算"
	idle_dialog.cancel_button_text = "返回洞天"
	idle_dialog.confirmed.connect(_confirm_ignoring_idle)
	idle_dialog.canceled.connect(show_cave)
	add_child(idle_dialog)
	resized.connect(_layout)
	# 控件全部创建后再订阅；每次合法操作提交完成时，状态层通知界面重读数据。
	GameState.state_changed.connect(_refresh)
	_refresh()
	_layout()


func _build_home_summary() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(28, 116)
	panel.custom_minimum_size.x = 206
	panel.add_theme_stylebox_override("panel", ThemeKit.hud_panel(18))
	home.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var name_label := _label("宁宁", 30, ThemeKit.LIGHT)
	name_label.add_theme_font_override("font", ThemeKit.title_font())
	column.add_child(name_label)
	for group_id in GameState.config.groups:
		var row := HBoxContainer.new()
		var name_text := _label(str(GameState.config.groups[group_id].name), 17, ThemeKit.GOLD)
		name_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_text)
		var amount := _label("", 22, ThemeKit.LIGHT)
		amount.custom_minimum_size.x = 70
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(amount)
		summary_labels[group_id] = amount
		column.add_child(row)
	var details_button := _button("人物详情")
	details_button.icon = ThemeKit.icon("users")
	ThemeKit.game_button(details_button)
	details_button.pressed.connect(open_menu.bind("attributes"))
	column.add_child(details_button)


## HUD 是贴在场景边缘的状态与操作区；锚点固定边缘，offset 留出内边距。
func _build_hud() -> void:
	var header := HBoxContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 28
	header.offset_right = -28
	header.offset_top = 24
	header.offset_bottom = 80
	header.add_theme_constant_override("separation", 12)
	add_child(header)
	home_button = _button("")
	home_button.icon = ThemeKit.icon("house")
	home_button.tooltip_text = "返回山居"
	home_button.custom_minimum_size = Vector2(52, 52)
	ThemeKit.game_button(home_button)
	home_button.pressed.connect(show_home)
	header.add_child(home_button)
	location_label = _label("山居", 32, ThemeKit.LIGHT)
	location_label.add_theme_font_override("font", ThemeKit.title_font())
	location_label.add_theme_color_override("font_shadow_color", Color("#294735"))
	location_label.add_theme_constant_override("shadow_offset_y", 2)
	header.add_child(location_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var vitals := PanelContainer.new()
	vitals.add_theme_stylebox_override("panel", ThemeKit.hud_panel(12))
	header.add_child(vitals)
	var vitals_row := HBoxContainer.new()
	vitals_row.add_theme_constant_override("separation", 28)
	vitals.add_child(vitals_row)
	energy_label = _label("", 17, ThemeKit.LIGHT)
	vitals_row.add_child(energy_label)
	var pressure_column := VBoxContainer.new()
	pressure_column.custom_minimum_size.x = 130
	vitals_row.add_child(pressure_column)
	pressure_label = _label("", 15, ThemeKit.LIGHT)
	pressure_column.add_child(pressure_label)
	pressure_bar = ProgressBar.new()
	pressure_bar.custom_minimum_size.y = 5
	pressure_bar.show_percentage = false
	pressure_bar.add_theme_stylebox_override("fill", ThemeKit.panel(Color("#e2b499"), Color.TRANSPARENT, 0, 0))
	pressure_bar.add_theme_stylebox_override("background", ThemeKit.panel(Color("#52665a"), Color.TRANSPARENT, 0, 0))
	pressure_column.add_child(pressure_bar)
	var bottom := HBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 28
	bottom.offset_right = -28
	bottom.offset_top = -88
	bottom.offset_bottom = -24
	bottom.add_theme_constant_override("separation", 12)
	add_child(bottom)
	var activities_button := _button("自由活动")
	activities_button.icon = ThemeKit.icon("leaf")
	activities_button.custom_minimum_size.x = 170
	ThemeKit.game_button(activities_button)
	activities_button.pressed.connect(open_menu.bind("activities"))
	bottom.add_child(activities_button)
	var cave_button := _button("洞天")
	cave_button.icon = ThemeKit.icon("mountain")
	cave_button.custom_minimum_size.x = 142
	ThemeKit.game_button(cave_button)
	cave_button.pressed.connect(show_cave)
	bottom.add_child(cave_button)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(space)
	schedule_button = _button("安排日程")
	schedule_button.icon = ThemeKit.icon("arrow-right")
	schedule_button.custom_minimum_size.x = 240
	ThemeKit.game_button(schedule_button, true)
	schedule_button.pressed.connect(open_menu.bind("work"))
	bottom.add_child(schedule_button)
	# 自由行动反馈贴在场景上，不伪装成尚未实现的剧情对话。
	notice = _label("", 17, ThemeKit.LIGHT)
	notice.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	notice.offset_left = 28
	notice.offset_right = -28
	notice.offset_top = -135
	notice.offset_bottom = -100
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_theme_stylebox_override("normal", ThemeKit.hud_panel(8))
	notice.hide()
	add_child(notice)


## 三种菜单共用遮罩和外框；遮罩接住背景点击，避免点穿到下方场景。
func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.07, 0.16, 0.13, 0.38)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close_menu())
	overlay.add_child(shade)
	modal = PanelContainer.new()
	modal.add_theme_stylebox_override("panel", ThemeKit.panel(Color("#f3f5ed"), ThemeKit.GOLD, 24, 3))
	overlay.add_child(modal)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	modal.add_child(column)
	var heading := HBoxContainer.new()
	modal_title = _label("", 28)
	modal_title.add_theme_font_override("font", ThemeKit.title_font())
	modal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(modal_title)
	var close := _button("")
	close.icon = ThemeKit.icon("x")
	close.tooltip_text = "收起"
	close.custom_minimum_size = Vector2(42, 42)
	close.pressed.connect(close_menu)
	heading.add_child(close)
	column.add_child(heading)
	work_page = VBoxContainer.new()
	work_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	work_page.add_theme_constant_override("separation", 12)
	column.add_child(work_page)
	_build_work(work_page)
	attributes_page = _scroll_page(column)
	var attributes := VBoxContainer.new()
	attributes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attributes.add_theme_constant_override("separation", 18)
	attributes_page.add_child(attributes)
	_build_attributes(attributes)
	activities_page = _scroll_page(column)
	var activities := VBoxContainer.new()
	activities.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	activities.add_theme_constant_override("separation", 16)
	activities_page.add_child(activities)
	for activity in ScheduleManager.activities("free"):
		var button := _button(str(activity.name))
		button.custom_minimum_size.y = 84
		button.icon = ThemeKit.icon("leaf" if activity.id == "clearheart" else ("flask-conical" if activity.has("costs") else "users"))
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(_free_action.bind(str(activity.id)))
		activities.add_child(button)
		free_buttons[activity.id] = button
	overlay.hide()


## 日程行只创建一次；滚动容器承载 3 至 5 槽，确认按钮放在滚动区外。
func _build_work(column: VBoxContainer) -> void:
	planning = VBoxContainer.new()
	planning.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(planning)
	schedule_scroll = _scroll_page(planning)
	var slots := VBoxContainer.new()
	slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots.add_theme_constant_override("separation", 10)
	schedule_scroll.add_child(slots)
	for i in range(GameState.schedule_slots):
		var tile := PanelContainer.new()
		tile.add_theme_stylebox_override("panel", ThemeKit.panel(Color("#ffffff99"), ThemeKit.LINE, 10, 3))
		var row := HBoxContainer.new()
		tile.add_child(row)
		row.add_theme_constant_override("separation", 14)
		var number := _label("%02d" % (i + 1), 24, ACCENT)
		number.custom_minimum_size.x = 38
		row.add_child(number)
		var activity_column := VBoxContainer.new()
		activity_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		activity_column.add_theme_constant_override("separation", 6)
		row.add_child(activity_column)
		var picker := OptionButton.new()
		picker.custom_minimum_size = Vector2(160, 36)
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.fit_to_longest_item = false
		picker.add_item("待安排")
		picker.set_item_metadata(0, "")
		# 名称负责显示，metadata 保存稳定 ID；菜单顺序或中文名改变不会串活动。
		for activity in ScheduleManager.activities("schedule"):
			picker.add_item(str(activity.name))
			picker.set_item_metadata(picker.item_count - 1, str(activity.id))
		# 信号先传选项序号，bind 再追加控件与槽位，最终调用 _choose(option, picker, i)。
		picker.item_selected.connect(_choose.bind(picker, i))
		activity_column.add_child(picker)
		var detail := _label("", 14, MUTED)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		activity_column.add_child(detail)
		slot_details.append(detail)
		selectors.append(picker)
		for delta in [-1, 1]:
			var move := _button("")
			move.icon = ThemeKit.icon("arrow-up" if delta == -1 else "arrow-down")
			move.custom_minimum_size = Vector2(40, 40)
			move.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			move.tooltip_text = "上移日程" if delta == -1 else "下移日程"
			move.pressed.connect(ScheduleManager.swap_slots.bind(i, i + delta))
			move.set_meta("edge", i + delta < 0 or i + delta >= GameState.schedule_slots)
			row.add_child(move)
			slot_tools.append(move)
		var clear := _button("")
		clear.icon = ThemeKit.icon("x")
		clear.custom_minimum_size = Vector2(40, 40)
		clear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		clear.tooltip_text = "清空此槽"
		clear.pressed.connect(_clear.bind(i))
		row.add_child(clear)
		slot_tools.append(clear)
		slots.add_child(tile)
	journal = VBoxContainer.new()
	journal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(journal)
	results = RichTextLabel.new()
	results.bbcode_enabled = true
	results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	results.add_theme_color_override("default_color", TEXT)
	results.add_theme_constant_override("line_separation", 8)
	journal.add_child(results)
	status_label = _label("", 15, MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status_label)
	var commands := HBoxContainer.new()
	commands.alignment = BoxContainer.ALIGNMENT_END
	confirm_button = _button("确认日程", true)
	confirm_button.icon = ThemeKit.icon("arrow-right")
	confirm_button.custom_minimum_size.x = 190
	confirm_button.pressed.connect(_confirm)
	commands.add_child(confirm_button)
	next_button = _button("下一回合", true)
	next_button.icon = ThemeKit.icon("arrow-right")
	next_button.custom_minimum_size.x = 190
	next_button.pressed.connect(_next)
	commands.add_child(next_button)
	column.add_child(commands)


func _build_attributes(column: VBoxContainer) -> void:
	for group_id in GameState.config.groups:
		var group: Dictionary = GameState.config.groups[group_id]
		var heading := _label("", 22, ThemeKit.GROUP_COLORS.get(group_id, ACCENT))
		group_labels[group_id] = heading
		column.add_child(heading)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 28)
		grid.add_theme_constant_override("v_separation", 10)
		for key in group.stats:
			var value := _label("", 17)
			value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			grid.add_child(value)
			stat_labels[key] = value
		column.add_child(grid)


## 按当前 Control 画布尺寸布局，不直接使用操作系统窗口像素；缩放由项目设置处理。
func _layout() -> void:
	if portrait == null or modal == null:
		return
	var height := size.y * 0.88
	portrait.size = Vector2(height / 2.0, height)
	portrait_origin = Vector2(size.x * 0.63 - portrait.size.x / 2.0, size.y - height - 55)
	portrait.position = portrait_origin
	var width := minf(820 if active_menu == "work" else 520, size.x - 64)
	modal.position = Vector2((size.x - width) / 2.0, 70)
	modal.size = Vector2(width, size.y - 140)


## 每帧仅做立绘轻微起伏；任何扣费、压力变化或回合推进都不能放在这里。
func _process(delta: float) -> void:
	elapsed += delta
	if is_instance_valid(portrait) and home.visible:
		portrait.position.y = portrait_origin.y + sin(elapsed * 1.4) * 1.8


## work 按游戏阶段展示日程或札记；重新打开不会重新执行已经完成的培养。
func open_menu(menu: String) -> void:
	active_menu = menu
	work_page.visible = menu == "work"
	attributes_page.visible = menu == "attributes"
	activities_page.visible = menu == "activities"
	modal_title.text = {"attributes": "宁宁 · 人物", "activities": "自由活动", "work": "培养日程" if GameState.phase == GameState.Phase.FREE else "成长札记"}[menu]
	overlay.show()
	_layout()


func close_menu() -> void:
	overlay.hide()
	active_menu = ""


## 家园与洞天节点都保留在树中，只切换可见性；日程草稿与建筑状态不会被重建。
func show_cave() -> void:
	close_menu()
	in_cave = true
	home.hide()
	cave_view.show()
	location_label.text = "洞天"
	home_button.show()


func show_home() -> void:
	close_menu()
	in_cave = false
	home.show()
	cave_view.hide()
	location_label.text = "山居"
	home_button.hide()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if overlay.visible:
			close_menu()
		elif in_cave:
			show_home()
		get_viewport().set_input_as_handled()


## 只把 GameState 投影为文字、选项和可用状态；结果使用结算记录而非再次掷骰。
func _refresh() -> void:
	var editable: bool = GameState.phase == GameState.Phase.FREE
	planning.visible = editable
	journal.visible = not editable
	home_button.visible = in_cave
	energy_label.text = "精力  %d / %d" % [GameState.energy, int(GameState.config.rules.max_energy)]
	pressure_label.text = "压力  %d / 100" % GameState.pressure
	pressure_bar.value = GameState.pressure
	var probabilities: Array = ScheduleManager.pressure_band(GameState.pressure).probabilities
	pressure_label.tooltip_text = "大成功 %.0f%% · 成功 %.0f%% · 失败 %.0f%%" % [float(probabilities[0]) * 100, float(probabilities[1]) * 100, float(probabilities[2]) * 100]
	var stage: int = GameState.growth_phase()
	if stage != portrait_stage:
		# AtlasTexture 取同一张透明图集的一个等宽区域，不在磁盘生成三份裁切图。
		portrait_stage = stage
		var atlas := AtlasTexture.new()
		atlas.atlas = load("res://assets/daughter_stages.png")
		var strip_width := atlas.atlas.get_width() / 3.0
		atlas.region = Rect2(stage * strip_width, 0, strip_width, atlas.atlas.get_height())
		atlas.filter_clip = true
		portrait.texture = atlas
	for i in range(selectors.size()):
		var picker: OptionButton = selectors[i]
		picker.disabled = not editable
		# select() 只回显当前草稿，不发 item_selected；真实修改仍走 _choose。
		picker.select(0)
		for j in range(1, picker.item_count):
			var id := str(picker.get_item_metadata(j))
			var activity := ScheduleManager.activity_by_id(id)
			picker.set_item_disabled(j, not ScheduleManager.availability(activity).is_empty())
			if GameState.plan[i] == id:
				picker.select(j)
				picker.tooltip_text = _growth_text(activity.growth) + " · 压力 +%d" % int(activity.pressure)
				for key in activity.get("costs", {}):
					picker.tooltip_text += " · %s -%d" % [GameState.config.items[key].name, int(activity.costs[key])]
				slot_details[i].text = picker.tooltip_text
		if GameState.plan[i].is_empty():
			picker.tooltip_text = ""
			slot_details[i].text = ""
	for button in slot_tools:
		button.disabled = not editable or bool(button.get_meta("edge", false))
	var selected := GameState.plan.size() - GameState.plan.count("")
	var projected: int = GameState.pressure
	for id in GameState.plan:
		if not id.is_empty():
			projected = clampi(projected + int(ScheduleManager.activity_by_id(id).pressure), 0, 100)
	status_label.text = "已安排 %d / %d   ·   预计压力 %d → %d" % [selected, GameState.schedule_slots, GameState.pressure, projected] if editable else "本回合已结算"
	schedule_button.text = "安排日程  %d / %d" % [selected, GameState.schedule_slots] if editable else "成长札记"
	for activity in ScheduleManager.activities("free"):
		var button: Button = free_buttons[activity.id]
		var reason := ScheduleManager.free_action_error(str(activity.id))
		button.disabled = not reason.is_empty()
		button.text = "%s\n精力 %d" % [activity.name, int(activity.get("energy_cost", 0))]
		var detail := _growth_text(activity.growth)
		if activity.has("costs"):
			for key in activity.costs:
				button.text = "%s\n持有 %d · 压力 %d" % [activity.name, int(GameState.inventory.get(key, 0)), int(activity.pressure)]
				detail = "压力 %d · %s -%d" % [int(activity.pressure), GameState.config.items[key].name, int(activity.costs[key])]
		button.tooltip_text = reason if not reason.is_empty() else detail
	var names := GameState.stat_names()
	for key in stat_labels:
		var bonus: int = GameState.equipment_bonus(key)
		stat_labels[key].text = "%s  %d%s" % [names[key], GameState.attribute(key), (" +%d" % bonus) if bonus != 0 else ""]
	for group_id in group_labels:
		group_labels[group_id].text = "%s  %d" % [GameState.config.groups[group_id].name, GameState.group_total(group_id)]
		summary_labels[group_id].text = str(GameState.group_total(group_id))
		summary_labels[group_id].tooltip_text = summary_labels[group_id].text
	confirm_button.visible = editable
	confirm_button.disabled = not ScheduleManager.plan_error().is_empty()
	confirm_button.tooltip_text = ScheduleManager.plan_error()
	next_button.visible = GameState.phase in [GameState.Phase.RESULTS, GameState.Phase.FINISHED]
	next_button.text = "重新开始" if GameState.phase == GameState.Phase.FINISHED else ("结束养成" if GameState.turn == GameState.total_turns() else "下一回合")
	var lines: Array[String] = []
	for entry in GameState.last_results:
		lines.append("[color=#287764]%s · %s[/color]\n%s   压力 %d → %d" % [entry.name, entry.outcome, _growth_text(entry.gains), entry.pressure_before, entry.pressure_after])
	results.text = "\n\n".join(lines)
	if not GameState.last_production.is_empty() and not GameState.last_production.rows.is_empty():
		results.append_text("\n\n[color=#507f9a]洞天收获[/color]")
		for row in GameState.last_production.rows:
			var production: Array[String] = []
			for key in row.outputs:
				production.append("%s +%d" % [GameState.config.items[key].name, int(row.outputs[key])])
			results.append_text("\n%s · %s" % [row.name, str(row.reason) if not str(row.reason).is_empty() else " · ".join(production)])
	if GameState.phase == GameState.Phase.FINISHED:
		status_label.text = "养成结束"
	if active_menu == "work":
		modal_title.text = "培养日程" if editable else "成长札记"


func _choose(option: int, picker: OptionButton, slot: int) -> void:
	_set_notice(ScheduleManager.assign_slot(slot, str(picker.get_item_metadata(option))))
	_refresh()


func _clear(slot: int) -> void:
	_set_notice(ScheduleManager.assign_slot(slot, ""))


func _free_action(id: String) -> void:
	var result := ScheduleManager.execute_free_action(id)
	var message := str(result.message)
	if result.ok:
		message += "  " + _growth_text(result.gains)
		if int(result.pressure_change) != 0:
			message += "  压力 %d" % int(result.pressure_change)
		close_menu()
	_set_notice(message)


## 先让规则层确认；收到 needs_confirmation 才弹闲置提醒，此时尚未结算。
func _confirm() -> void:
	var result := ScheduleManager.confirm_schedule()
	if result.get("needs_confirmation", false):
		idle_dialog.dialog_text = str(result.message)
		idle_dialog.popup_centered(Vector2i(430, 250))
		return
	_set_notice("" if result.ok else str(result.message))
	if result.ok:
		open_menu("work")


func _confirm_ignoring_idle() -> void:
	var result := ScheduleManager.confirm_schedule(true)
	_set_notice("" if result.ok else str(result.message))
	if result.ok:
		open_menu("work")


## 结果页前进与终局重开共用按钮；是否可以推进仍由 GameState 决定。
func _next() -> void:
	if GameState.phase == GameState.Phase.FINISHED:
		GameState.reset_game()
	else:
		GameState.advance_turn()
	_set_notice("")
	show_home()


func _set_notice(message: String) -> void:
	notice.text = message
	notice.visible = not message.strip_edges().is_empty()
	if overlay.visible and not message.is_empty() and active_menu == "work":
		status_label.text = message


func _growth_text(growth: Dictionary) -> String:
	var names := GameState.stat_names()
	var parts: Array[String] = []
	for key in growth:
		parts.append("%s +%d" % [names[key], int(growth[key])])
	return " · ".join(parts)


func _scroll_page(parent: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	return scroll


func _label(value: String, font_size: int, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(value: String, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 46
	if primary:
		ThemeKit.primary(button)
	return button
