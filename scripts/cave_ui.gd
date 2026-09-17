extends Control

# 洞天的交互层：Board 给出逻辑格，本脚本按模式调用 Cave 规则，再展示结果。
# 不在这里重算收益或直接改库存；与 main.gd 一样监听 state_changed 刷新。
const Board = preload("res://scripts/cave_board.gd")
const ThemeKit = preload("res://scripts/ui_theme.gd")
const TEXT := ThemeKit.INK
var board: Control
var catalog: OptionButton
var inventory_label: Label
var cost_label: Label
var population_label: Label
var title_label: Label
var details: RichTextLabel
var overview: Label
var notice: Label
var recipe_picker: OptionButton
var workers_box: VBoxContainer
var inspector_panel: PanelContainer
var toolbar_panel: PanelContainer
var worker_pickers: Array[OptionButton] = []
var mode_buttons: Dictionary = {}
var current_mode := "select"
var selected_id := -1
# 记录详情面板对应的建筑；与 selected_id 不同时才重建配方和工作槽控件。
var inspector_id := -2


## 场景画布和边缘控件分层创建；建筑详情隐藏时把空间交还给地块与工具栏。
func _ready() -> void:
	var background := TextureRect.new()
	background.texture = load("res://assets/cave_valley.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	board = Board.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.offset_left = 28
	board.offset_right = -28
	board.offset_top = 182
	board.offset_bottom = -210
	board.cell_clicked.connect(_cell_clicked)
	board.cancelled.connect(_set_mode.bind("select"))
	add_child(board)
	var inventory_panel := PanelContainer.new()
	inventory_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	inventory_panel.offset_left = 28
	inventory_panel.offset_right = -28
	inventory_panel.offset_top = 98
	inventory_panel.offset_bottom = 140
	inventory_panel.add_theme_stylebox_override("panel", ThemeKit.hud_panel(10))
	add_child(inventory_panel)
	var stock_row := HBoxContainer.new()
	stock_row.add_theme_constant_override("separation", 20)
	inventory_panel.add_child(stock_row)
	inventory_label = _label("", 15, ThemeKit.LIGHT)
	inventory_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stock_row.add_child(inventory_label)
	population_label = _label("", 15, ThemeKit.GOLD)
	stock_row.add_child(population_label)
	overview = _label("", 15, ThemeKit.LIGHT)
	overview.position = Vector2(28, 147)
	overview.add_theme_color_override("font_shadow_color", Color("#274931"))
	overview.add_theme_constant_override("shadow_offset_y", 1)
	overview.add_theme_color_override("font_outline_color", Color("#284532"))
	overview.add_theme_constant_override("outline_size", 3)
	add_child(overview)
	toolbar_panel = PanelContainer.new()
	toolbar_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	toolbar_panel.offset_left = 28
	toolbar_panel.offset_right = -28
	toolbar_panel.offset_top = -187
	toolbar_panel.offset_bottom = -105
	toolbar_panel.add_theme_stylebox_override("panel", ThemeKit.hud_panel(12))
	add_child(toolbar_panel)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	toolbar_panel.add_child(toolbar)
	var group := ButtonGroup.new()
	for entry in [["select", "mouse-pointer-2"], ["build", "plus"], ["road", "route"], ["move", "move"]]:
		var button := Button.new()
		button.icon = ThemeKit.icon(entry[1])
		button.custom_minimum_size = Vector2(48, 48)
		button.toggle_mode = true
		button.button_group = group
		ThemeKit.game_button(button)
		button.tooltip_text = {"select": "查看建筑", "build": "放置建筑", "road": "添加或移除道路", "move": "移动已选建筑"}[entry[0]]
		button.pressed.connect(_set_mode.bind(str(entry[0])))
		toolbar.add_child(button)
		mode_buttons[entry[0]] = button
	catalog = OptionButton.new()
	catalog.custom_minimum_size = Vector2(190, 48)
	catalog.fit_to_longest_item = false
	for id in GameState.cave_config.buildings:
		catalog.add_item(str(GameState.cave_config.buildings[id].name))
		catalog.set_item_metadata(catalog.item_count - 1, id)
	catalog.select(mini(1, catalog.item_count - 1))
	catalog.item_selected.connect(func(_index: int) -> void: _set_mode("build"))
	toolbar.add_child(catalog)
	var cost_column := VBoxContainer.new()
	cost_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toolbar.add_child(cost_column)
	cost_label = _label("", 14, ThemeKit.LIGHT)
	cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cost_column.add_child(cost_label)
	notice = _label("", 14, ThemeKit.GOLD)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cost_column.add_child(notice)
	inspector_panel = PanelContainer.new()
	inspector_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	inspector_panel.offset_left = -330
	inspector_panel.offset_right = -28
	inspector_panel.offset_top = 184
	inspector_panel.offset_bottom = -105
	inspector_panel.add_theme_stylebox_override("panel", ThemeKit.panel(Color("#f3f5edf5"), ThemeKit.GOLD, 16, 3))
	add_child(inspector_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector_panel.add_child(scroll)
	var inspector := VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.add_theme_constant_override("separation", 12)
	scroll.add_child(inspector)
	var heading := HBoxContainer.new()
	inspector.add_child(heading)
	title_label = _label("", 24)
	title_label.add_theme_font_override("font", ThemeKit.title_font())
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_child(title_label)
	var close := Button.new()
	close.icon = ThemeKit.icon("x")
	close.tooltip_text = "收起建筑详情"
	close.custom_minimum_size = Vector2(36, 36)
	close.pressed.connect(func() -> void:
		selected_id = -1
		_refresh())
	heading.add_child(close)
	recipe_picker = OptionButton.new()
	recipe_picker.fit_to_longest_item = false
	recipe_picker.custom_minimum_size = Vector2(250, 40)
	recipe_picker.item_selected.connect(_recipe_changed)
	inspector.add_child(recipe_picker)
	workers_box = VBoxContainer.new()
	workers_box.add_theme_constant_override("separation", 8)
	inspector.add_child(workers_box)
	details = RichTextLabel.new()
	details.bbcode_enabled = true
	details.fit_content = true
	details.scroll_active = false
	details.custom_minimum_size.y = 180
	details.add_theme_color_override("default_color", TEXT)
	inspector.add_child(details)
	GameState.state_changed.connect(_refresh)
	_set_mode("select")


func _set_mode(value: String) -> void:
	current_mode = value
	notice.text = ""
	_refresh()


## 同一个格子点击按当前模式解释；移动先选实例，再选落点，不生成新建筑 ID。
func _cell_clicked(cell: Vector2i) -> void:
	var result: Dictionary = {}
	match current_mode:
		"build":
			result = GameState.Cave.build(str(catalog.get_selected_metadata()), cell)
			if result.ok:
				selected_id = int(result.id)
		"road":
			result = GameState.Cave.toggle_road(cell)
		"move":
			if selected_id < 0:
				var found: Dictionary = GameState.Cave.building_at(cell)
				selected_id = int(found.get("id", -1))
			else:
				result = GameState.Cave.move_building(selected_id, cell)
				if result.ok:
					current_mode = "select"
		_:
			var found: Dictionary = GameState.Cave.building_at(cell)
			selected_id = int(found.get("id", -1))
	_refresh()
	notice.text = str(result.get("message", ""))


## 同时响应规则变化与本地选中变化；结果阶段仍能查看，但禁用管理操作。
func _refresh() -> void:
	if board == null:
		return
	var editable: bool = GameState.phase == GameState.Phase.FREE
	if not editable:
		current_mode = "select"
	for id in mode_buttons:
		# 刷新选中外观时不再触发模式切换信号，避免 UI 与回调互相调用。
		mode_buttons[id].set_pressed_no_signal(id == current_mode)
		mode_buttons[id].disabled = not editable and id != "select"
	catalog.disabled = not editable
	board.mode = current_mode
	board.build_type = str(catalog.get_selected_metadata())
	if GameState.Cave.find_building(selected_id).is_empty():
		selected_id = -1
	board.selected_id = selected_id
	# 查看详情时给场景让出空间；建造模式不因自动选中新建筑挪动地块。
	inspector_panel.visible = selected_id >= 0 and current_mode == "select"
	board.offset_right = -354 if inspector_panel.visible else -28
	toolbar_panel.offset_right = -354 if inspector_panel.visible else -28
	board.queue_redraw()
	inventory_label.text = _amounts(GameState.inventory)
	inventory_label.tooltip_text = inventory_label.text
	var data: Dictionary = GameState.cave_config.buildings[board.build_type]
	cost_label.text = "%s  %d×%d  ·  %s" % [data.name, int(data.size[0]), int(data.size[1]), _amounts(data.costs)]
	population_label.text = "入住 %d / %d  ·  御灵 %d" % [
		GameState.Cave.residents(GameState.cave), GameState.Cave.capacity(GameState.cave), GameState.cave.workers.size()]
	# 自由阶段显示预测；结算后读保存的报告，不能用已经入库的库存重算本回合。
	var report: Dictionary = GameState.Cave.preview() if editable else GameState.last_production
	if report.is_empty():
		report = {"rows": [], "consumed": {}, "produced": {}}
	var prefix := "预计" if editable else "本次"
	overview.text = "%s投入  %s    ·    %s收获  %s" % [prefix, _amounts(report.consumed), prefix, _amounts(report.produced)]
	overview.tooltip_text = overview.text
	overview.size.x = size.x - 56
	overview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_refresh_inspector(report, editable)


## 切换建筑时重建控件；同一建筑刷新时只同步选项，保留稳定的控件结构。
func _refresh_inspector(report: Dictionary, editable: bool) -> void:
	var building: Dictionary = GameState.Cave.find_building(selected_id)
	var changed := inspector_id != selected_id
	if changed:
		inspector_id = selected_id
		recipe_picker.clear()
		for child in workers_box.get_children():
			# 先立即脱离容器，再延迟释放，避免新旧工作槽在当前帧同时参与布局。
			workers_box.remove_child(child)
			child.queue_free()
		worker_pickers.clear()
	recipe_picker.visible = false
	if building.is_empty():
		title_label.text = "未选择建筑"
		var names: Array[String] = []
		for worker in GameState.cave.workers:
			names.append("%s · %s" % [worker.name, "待命" if int(worker.building_id) < 0 else "已分配"])
		details.text = "\n".join(names)
		return
	var data: Dictionary = GameState.Cave.definition(building)
	title_label.text = "%s #%d" % [data.name, selected_id]
	if changed:
		recipe_picker.add_item("未安排生产")
		recipe_picker.set_item_metadata(0, "")
		for id in data.recipes:
			recipe_picker.add_item(str(GameState.cave_config.recipes[id].name))
			recipe_picker.set_item_metadata(recipe_picker.item_count - 1, id)
		for slot in range(int(data.worker_slots)):
			workers_box.add_child(_label("工作槽 %d" % (slot + 1), 16))
			var picker := OptionButton.new()
			picker.fit_to_longest_item = false
			picker.custom_minimum_size.y = 40
			picker.add_item("未派御灵")
			picker.set_item_metadata(0, "")
			for worker in GameState.cave.workers:
				var aptitude := int(worker.aptitudes.get(data.get("work_type", ""), 0))
				picker.add_item("%s · 适应性 %d" % [worker.name, aptitude])
				picker.set_item_metadata(picker.item_count - 1, worker.id)
			picker.item_selected.connect(_worker_changed.bind(slot, picker))
			workers_box.add_child(picker)
			worker_pickers.append(picker)
	recipe_picker.visible = not data.recipes.is_empty()
	recipe_picker.disabled = not editable
	recipe_picker.select(0)
	for i in range(recipe_picker.item_count):
		if recipe_picker.get_item_metadata(i) == building.recipe:
			recipe_picker.select(i)
	for slot in range(worker_pickers.size()):
		var picker: OptionButton = worker_pickers[slot]
		picker.disabled = not editable
		picker.select(0)
		for worker in GameState.cave.workers:
			if int(worker.building_id) == selected_id and int(worker.slot) == slot:
				for i in range(picker.item_count):
					if picker.get_item_metadata(i) == worker.id:
						picker.select(i)
	var network: Dictionary = GameState.Cave.connected_roads(GameState.cave.roads)
	var connection := "无需道路" if data.category == "landscape" else ("道路已连通" if GameState.Cave.connected(building, network) else "道路未连通")
	var text := connection + "\n"
	if data.has("capacity"):
		text += "\n民居容量 %d" % int(data.capacity)
	if data.has("bonus"):
		text += "\n%s加成\n相邻 +%.0f%% · 距离范围 %d" % [data.bonus.label, float(data.bonus.peak) * 100, int(data.bonus.radius)]
	for row in report.rows:
		if int(row.id) != selected_id:
			continue
		text += "\n" + (str(row.reason) if not str(row.reason).is_empty() else "正常生产")
		text += "\n\n投入  " + _amounts(row.inputs)
		text += "\n产出  " + _amounts(row.outputs)
		text += "\n\n御灵乘区 ×%.2f\n景观乘区 ×%.2f" % [float(row.factors.workers), float(row.factors.landscape)]
	details.text = text


func _recipe_changed(index: int) -> void:
	var result: Dictionary = GameState.Cave.set_recipe(selected_id, str(recipe_picker.get_item_metadata(index)))
	_refresh()
	notice.text = str(result.message)


## index 是菜单序号，slot 是建筑工作槽；从 metadata 取御灵 ID，不能混用三者。
func _worker_changed(index: int, slot: int, picker: OptionButton) -> void:
	var result: Dictionary = GameState.Cave.assign_worker(selected_id, slot, str(picker.get_item_metadata(index)))
	_refresh()
	notice.text = str(result.message)


func _amounts(amounts: Dictionary) -> String:
	var parts: Array[String] = []
	for key in amounts:
		parts.append("%s %d" % [GameState.config.items[key].name, int(amounts[key])])
	return " · ".join(parts) if not parts.is_empty() else "无"


func _label(value: String, font_size: int, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
