extends Control
## Main —— 主场景脚本（最小闭环原型）
## 跑通「排日程 → 属性/境界变化 → 女儿反馈」闭环，验证 GDD §1 的 H1 养成感假设。
## UI 全部用代码构建，不依赖美术资源；立绘用 emoji + 颜色随境界变化占位。


# ---------- 配色（修仙水墨风） ----------
const COLOR_BG        := Color("#191522")   # 整体背景（深墨）
const COLOR_PANEL     := Color("#251e33")   # 面板底
const COLOR_PANEL_LN  := Color("#3a2f4d")   # 面板描边
const COLOR_GOLD      := Color("#d4c24f")   # 强调金
const COLOR_TEXT      := Color("#ece4d4")   # 主文字（米白）
const COLOR_TEXT_DIM  := Color("#9a8f7a")   # 次文字（灰）
const COLOR_DANGER    := Color("#c96a5a")   # 心魔警示红

# 主属性 → 进度条颜色
const MAIN_COLORS := {
	"体魄": Color("#c9705a"),
	"道法": Color("#6a9cc9"),
	"仙缘": Color("#c9a24f"),
	"杂学": Color("#6aa37a"),
}


# ---------- 节点引用（代码构建后用变量保存） ----------
var time_label: Label
var realm_label: Label
var energy_label: Label
var stones_label: Label
var demon_label: Label

var portrait_emoji: Label
var portrait_name: Label
var portrait_desc: Label
var realm_progress_bar: ProgressBar

var main_stat_bars: Dictionary = {}      # main名 -> ProgressBar
var main_stat_labels: Dictionary = {}    # main名 -> Label（细分小字）
var bond_bar: ProgressBar

var daughter_bubble: Label               # 女儿当前这句话（大字）
var log_rtl: RichTextLabel               # 滚动日志

var latest_feedback: String = ""


func _ready() -> void:
	_build_theme()
	_build_ui()
	_connect_signals()
	_refresh_ui()
	_append_log("你带着满门被屠的秘密，在边陲小城以「父女」身份与阿凝相依为命。", COLOR_TEXT_DIM)
	_append_log("她十岁了，你偷偷塞进她手里的第一本功法，已在夜里泛出微光。", COLOR_TEXT_DIM)
	_set_bubble("爹，我好像……能感受到灵气了。", false)


# ================= 主题 =================
func _build_theme() -> void:
	var theme := Theme.new()
	var font := SystemFont.new()
	# 指定支持中文的系统字体回退链（macOS 用苹方）
	font.font_names = PackedStringArray(
		["PingFang SC", "Hiragino Sans GB", "Noto Sans CJK SC", "Microsoft YaHei", "sans-serif"])
	theme.default_font = font
	theme.default_font_size = 15
	theme.default_base_scale = 1.0
	self.theme = theme


# ================= UI 构建 =================
func _build_ui() -> void:
	# 背景
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 最外层边距
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	# ---- 顶部信息栏 ----
	root.add_child(_build_top_bar())
	# ---- 主体（左状态卡 + 右互动区）----
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)
	body.add_child(_build_left_panel())
	body.add_child(_build_right_panel())
	# ---- 底部操作栏 ----
	root.add_child(_build_bottom_bar())


# ---------- 顶部信息栏 ----------
func _build_top_bar() -> Control:
	var panel := _make_panel()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 28)
	panel.add_child(hb)

	time_label = Label.new()
	time_label.add_theme_font_size_override("font_size", 17)
	time_label.add_theme_color_override("font_color", COLOR_GOLD)
	hb.add_child(time_label)

	realm_label = Label.new()
	realm_label.add_theme_font_size_override("font_size", 17)
	realm_label.add_theme_color_override("font_color", COLOR_TEXT)
	hb.add_child(realm_label)

	energy_label = Label.new()
	energy_label.add_theme_color_override("font_color", COLOR_TEXT)
	hb.add_child(energy_label)

	stones_label = Label.new()
	stones_label.add_theme_color_override("font_color", COLOR_TEXT)
	hb.add_child(stones_label)

	demon_label = Label.new()
	demon_label.add_theme_color_override("font_color", COLOR_TEXT)
	hb.add_child(demon_label)

	return panel


# ---------- 左侧：女儿状态卡 ----------
func _build_left_panel() -> Control:
	var panel := _make_panel()
	panel.custom_minimum_size = Vector2(430, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	# 立绘占位（居中）
	var portrait_center := CenterContainer.new()
	vb.add_child(portrait_center)
	var portrait_vb := VBoxContainer.new()
	portrait_center.add_child(portrait_vb)

	portrait_emoji = Label.new()
	portrait_emoji.add_theme_font_size_override("font_size", 72)
	portrait_emoji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_vb.add_child(portrait_emoji)

	portrait_name = Label.new()
	portrait_name.add_theme_font_size_override("font_size", 22)
	portrait_name.add_theme_color_override("font_color", COLOR_GOLD)
	portrait_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_vb.add_child(portrait_name)

	portrait_desc = Label.new()
	portrait_desc.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	portrait_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_vb.add_child(portrait_desc)

	vb.add_child(_make_hsep())

	# 境界进度条
	var realm_hb := HBoxContainer.new()
	vb.add_child(realm_hb)
	var realm_cap := Label.new()
	realm_cap.text = "境界  "
	realm_cap.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	realm_hb.add_child(realm_cap)
	realm_progress_bar = ProgressBar.new()
	realm_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	realm_progress_bar.show_percentage = false
	realm_progress_bar.custom_minimum_size = Vector2(0, 16)
	realm_progress_bar.add_theme_color_override("fill", COLOR_GOLD)
	realm_hb.add_child(realm_progress_bar)

	vb.add_child(_make_hsep())

	# 四大主属性
	for main in GameData.MAIN_STATS:
		var sub_keys: Array = GameData.MAIN_TO_SUB[main]
		# 一行：主属性名 + 数值
		var line := HBoxContainer.new()
		vb.add_child(line)
		var name_label := Label.new()
		name_label.text = "%s" % main
		name_label.custom_minimum_size = Vector2(64, 0)
		name_label.add_theme_color_override("font_color", COLOR_TEXT)
		line.add_child(name_label)

		var bar := ProgressBar.new()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 14)
		bar.add_theme_color_override("fill", MAIN_COLORS[main])
		line.add_child(bar)
		main_stat_bars[main] = bar

		var val_label := Label.new()
		val_label.custom_minimum_size = Vector2(52, 0)
		val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_label.add_theme_color_override("font_color", COLOR_TEXT)
		line.add_child(val_label)
		main_stat_labels[main] = val_label

		# 细分小字
		var sub_label := Label.new()
		sub_label.text = "　" + " · ".join(sub_keys.map(func(k): return GameData.sub_name(k)))
		sub_label.add_theme_font_size_override("font_size", 12)
		sub_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		vb.add_child(sub_label)

	vb.add_child(_make_hsep())

	# 情缘条
	var bond_hb := HBoxContainer.new()
	vb.add_child(bond_hb)
	var bond_cap := Label.new()
	bond_cap.text = "情缘  "
	bond_cap.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	bond_hb.add_child(bond_cap)
	bond_bar = ProgressBar.new()
	bond_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bond_bar.show_percentage = false
	bond_bar.custom_minimum_size = Vector2(0, 14)
	bond_bar.add_theme_color_override("fill", Color("#c96a8a"))
	bond_hb.add_child(bond_bar)

	return panel


# ---------- 右侧：互动区 ----------
func _build_right_panel() -> Control:
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 12)

	# 女儿反馈气泡
	var bubble_panel := _make_panel()
	vb.add_child(bubble_panel)
	var bubble_vb := VBoxContainer.new()
	bubble_panel.add_child(bubble_vb)
	var bubble_title := Label.new()
	bubble_title.text = "女儿说"
	bubble_title.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	bubble_title.add_theme_font_size_override("font_size", 12)
	bubble_vb.add_child(bubble_title)
	daughter_bubble = Label.new()
	daughter_bubble.add_theme_font_size_override("font_size", 19)
	daughter_bubble.add_theme_color_override("font_color", COLOR_TEXT)
	daughter_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble_vb.add_child(daughter_bubble)

	# 事件日志
	var log_panel := _make_panel()
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(log_panel)
	var scroll := ScrollContainer.new()
	log_panel.add_child(scroll)
	log_rtl = RichTextLabel.new()
	log_rtl.bbcode_enabled = true
	log_rtl.scroll_following = true
	log_rtl.fit_content = false
	log_rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_rtl.custom_minimum_size = Vector2(0, 180)
	scroll.add_child(log_rtl)

	# 活动按钮区
	var act_panel := _make_panel()
	vb.add_child(act_panel)
	var act_vb := VBoxContainer.new()
	act_vb.add_theme_constant_override("separation", 10)
	act_panel.add_child(act_vb)
	var act_title := Label.new()
	act_title.text = "安排本月日程"
	act_title.add_theme_color_override("font_color", COLOR_GOLD)
	act_title.add_theme_font_size_override("font_size", 16)
	act_vb.add_child(act_title)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	act_vb.add_child(grid)

	for act in GameData.ACTIVITIES:
		var btn := _make_activity_button(act)
		grid.add_child(btn)

	return vb


# ---------- 底部操作栏 ----------
func _build_bottom_bar() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)

	var next_btn := Button.new()
	next_btn.text = "结束本月，进入下月 ▶"
	next_btn.add_theme_color_override("font_color", COLOR_TEXT)
	next_btn.add_theme_color_override("font_hover_color", COLOR_GOLD)
	next_btn.pressed.connect(_on_next_month)
	hb.add_child(next_btn)

	var reset_btn := Button.new()
	reset_btn.text = "重置"
	reset_btn.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	reset_btn.pressed.connect(_on_reset)
	hb.add_child(reset_btn)

	return hb


# ================= 组件工厂 =================
func _make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_PANEL
	sb.border_color = COLOR_PANEL_LN
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	return panel


func _make_hsep() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", COLOR_PANEL_LN)
	return sep


func _make_activity_button(act: Dictionary) -> Button:
	var btn := Button.new()
	# 按钮文案：emoji + 名称 + 精力消耗 + 灵石变化提示
	var cost_note := ""
	if act["stones"] < 0:
		cost_note = "  -%d灵石" % -act["stones"]
	elif act["stones"] > 0:
		cost_note = "  +%d灵石" % act["stones"]
	btn.text = "%s%s\n耗 %d 精力%s" % [act["emoji"], act["name"], act["energy"], cost_note]
	btn.tooltip_text = "%s\n精力:%d  心魔:%+d  情缘:%+d  灵石:%+d" % [
		act["desc"], act["energy"], act["demon"], act["bond"], act["stones"]]
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_color_override("font_hover_color", COLOR_GOLD)
	btn.add_theme_font_size_override("font_size", 14)
	btn.custom_minimum_size = Vector2(150, 54)

	# 绑定点击：闭包捕获活动 id
	btn.pressed.connect(_on_activity.bind(act["id"]))
	return btn


# ================= 信号连接 =================
func _connect_signals() -> void:
	GameState.state_changed.connect(_refresh_ui)
	GameState.realm_broken.connect(_on_realm_broken)
	GameState.feedback.connect(_on_feedback)
	GameState.month_passed.connect(_on_month_passed)


# ================= 回调 =================
func _on_activity(activity_id: String) -> void:
	var result: Dictionary = GameState.do_activity(activity_id)
	if not result["ok"]:
		# 精力/灵石不足，给出失败提示
		_append_log("无法执行：%s" % result["reason"], COLOR_DANGER)
		return
	# 增益摘要进日志
	if not result["gains_summary"].is_empty():
		_append_log(" · ".join(result["gains_summary"]), COLOR_TEXT_DIM)
	_set_bubble(result["feedback_text"], false)


func _on_next_month() -> void:
	GameState.next_month()


func _on_reset() -> void:
	get_tree().reload_current_scene()


func _on_month_passed() -> void:
	_append_log("—— 新的一月 ——", COLOR_TEXT_DIM)


func _on_feedback(text: String) -> void:
	pass  # 反馈已在 _on_activity 里处理，这里预留


func _on_realm_broken(from_realm: String, to_realm: String) -> void:
	_append_log("✨ 突破！%s → %s" % [from_realm, to_realm], COLOR_GOLD)
	_set_bubble("爹！我突破了——%s 了！" % to_realm, true)


# ================= 刷新 =================
func _refresh_ui() -> void:
	# 时间 / 境界 / 精力 / 灵石 / 心魔
	time_label.text = GameState.time_text()
	var realm := GameState.get_realm()
	realm_label.text = "境界：%s %s" % [realm["emoji"], realm["name"]]
	energy_label.text = "精力 %d/%d" % [GameState.energy, GameState.ENERGY_MAX]
	stones_label.text = "灵石 %d" % GameState.spirit_stones
	demon_label.text = "心魔 %d" % GameState.heart_demon
	demon_label.add_theme_color_override("font_color",
		COLOR_DANGER if GameState.heart_demon >= 60 else COLOR_TEXT)

	# 立绘占位随境界变化（成长可见的第一层）
	portrait_emoji.text = realm["emoji"]
	portrait_emoji.add_theme_color_override("font_color", Color(realm["color"]))
	portrait_name.text = GameState.daughter_name
	portrait_desc.text = realm["desc"]

	# 境界进度条：当前阶 → 下一阶之间的进度
	var idx := GameState.get_realm_index()
	var cur_threshold: int = GameData.REALMS[idx]["threshold"]
	var next_threshold: int = 999999999
	if idx + 1 < GameData.REALMS.size():
		next_threshold = GameData.REALMS[idx + 1]["threshold"]
	realm_progress_bar.min_value = cur_threshold
	realm_progress_bar.max_value = next_threshold
	realm_progress_bar.value = GameState.realm_progress

	# 四大主属性条
	for main in GameData.MAIN_STATS:
		var val := GameState.get_main_stat(main)
		main_stat_bars[main].min_value = 0
		main_stat_bars[main].max_value = 400
		main_stat_bars[main].value = val
		main_stat_labels[main].text = str(val)

	# 情缘条
	bond_bar.min_value = 0
	bond_bar.max_value = 100
	bond_bar.value = GameState.bond


# ================= 文本工具 =================
func _set_bubble(text: String, highlight: bool) -> void:
	daughter_bubble.text = "「%s」" % text
	daughter_bubble.add_theme_color_override("font_color",
		COLOR_GOLD if highlight else COLOR_TEXT)


func _append_log(text: String, color: Color) -> void:
	if log_rtl == null:
		return
	log_rtl.append_text("[color=#%s]%s[/color]\n" % [color.to_html(false), text])
