extends Control

# 全屏对话覆盖日常 HUD；只负责展示与发出“推进这一行”的请求，不自行发奖。
const ThemeKit = preload("res://scripts/ui_theme.gd")
var portrait: TextureRect
var title_label: Label
var speaker_label: Label
var dialogue: RichTextLabel
var effect_label: RichTextLabel
var page_label: Label
var advance_button: Button
var panel: PanelContainer
var shown_id := ""
var shown_line := -1
var shown_stage := -1


func _ready() -> void:
	theme = ThemeKit.make_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := TextureRect.new()
	backdrop.texture = load("res://assets/home_courtyard.png")
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait)
	title_label = Label.new()
	title_label.position = Vector2(36, 26)
	title_label.add_theme_font_override("font", ThemeKit.title_font())
	title_label.add_theme_font_size_override("font_size", 25)
	title_label.add_theme_color_override("font_color", ThemeKit.LIGHT)
	title_label.add_theme_color_override("font_outline_color", Color("#17382db0"))
	title_label.add_theme_constant_override("outline_size", 4)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.max_lines_visible = 2
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(title_label)
	panel = PanelContainer.new()
	var panel_style := ThemeKit.panel(Color("#183b36f5"), ThemeKit.GOLD, 24, 0)
	panel_style.content_margin_left = 40
	panel_style.content_margin_right = 40
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	speaker_label = Label.new()
	speaker_label.add_theme_font_override("font", ThemeKit.title_font())
	speaker_label.add_theme_font_size_override("font_size", 25)
	speaker_label.add_theme_color_override("font_color", ThemeKit.GOLD)
	speaker_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(speaker_label)
	dialogue = RichTextLabel.new()
	dialogue.bbcode_enabled = false
	dialogue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialogue.add_theme_font_size_override("normal_font_size", 22)
	dialogue.add_theme_color_override("default_color", ThemeKit.LIGHT)
	dialogue.add_theme_constant_override("line_separation", 8)
	dialogue.scroll_active = true
	column.add_child(dialogue)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	column.add_child(footer)
	effect_label = RichTextLabel.new()
	effect_label.bbcode_enabled = false
	effect_label.custom_minimum_size.y = 56
	effect_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effect_label.add_theme_font_size_override("normal_font_size", 15)
	effect_label.add_theme_color_override("default_color", ThemeKit.GOLD)
	footer.add_child(effect_label)
	page_label = Label.new()
	page_label.custom_minimum_size.x = 72
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	page_label.add_theme_color_override("font_color", ThemeKit.LIGHT)
	footer.add_child(page_label)
	advance_button = Button.new()
	advance_button.icon = ThemeKit.icon("arrow-right")
	advance_button.custom_minimum_size = Vector2(56, 56)
	advance_button.expand_icon = true
	advance_button.add_theme_constant_override("icon_max_width", 24)
	ThemeKit.game_button(advance_button, true)
	advance_button.pressed.connect(_advance)
	footer.add_child(advance_button)
	resized.connect(_layout)
	GameState.state_changed.connect(_refresh)
	_refresh()
	_layout()


func _layout() -> void:
	if panel == null:
		return
	var band_height := clampf(size.y * 0.32, 230, 300)
	panel.position = Vector2(0, size.y - band_height)
	panel.size = Vector2(size.x, band_height)
	var portrait_height := size.y * 0.86
	portrait.size = Vector2(portrait_height * 0.5, portrait_height)
	portrait.position = Vector2(size.x * 0.63 - portrait.size.x * 0.5, size.y * 0.025)
	title_label.size = Vector2(size.x * 0.40 - 36, 80)


func _refresh() -> void:
	visible = GameState.phase == GameState.Phase.STORY and not GameState.story.active.is_empty()
	if not visible:
		shown_id = ""
		shown_line = -1
		return
	var active: Dictionary = GameState.story.active
	var id := str(active.node.id)
	var line := int(active.line)
	var stage := int(active.growth_phase)
	var changed := shown_id != id or shown_line != line
	if shown_id != id or shown_stage != stage:
		var definition: Dictionary = active.presentation.get("portrait", {})
		if definition.is_empty():
			# 无专用立绘时沿用家园的当前阶段女儿，不因台词说话人去猜其他人物素材。
			definition = {"texture": "res://assets/daughter_stages.png", "region": [stage * 512, 0, 512, 1024]}
		var texture: Texture2D = load(str(definition.texture))
		if definition.has("region"):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			var region: Array = definition.region
			atlas.region = Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
			atlas.filter_clip = true
			texture = atlas
		portrait.texture = texture
	shown_id = id
	shown_line = line
	shown_stage = stage
	title_label.text = str(active.node.name)
	title_label.tooltip_text = title_label.text
	speaker_label.text = str(active.presentation.lines[line].speaker)
	speaker_label.tooltip_text = speaker_label.text
	dialogue.text = str(active.presentation.lines[line].text)
	page_label.text = "%d / %d" % [line + 1, active.presentation.lines.size()]
	var last_line: bool = line + 1 == active.presentation.lines.size()
	effect_label.text = _effects(active.node) if last_line else ""
	advance_button.tooltip_text = "结束对话" if last_line else "继续"
	if changed:
		dialogue.scroll_to_line(0)
		effect_label.scroll_to_line(0)
		advance_button.grab_focus()


func _advance() -> void:
	var result: Dictionary = GameState.StoryFlow.advance(shown_id, shown_line)
	if not result.ok:
		effect_label.text = str(result.message)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey:
		return
	# 在 GUI 焦点控件之前统一接住按下/松开，避免 Enter 同时触发按钮和对话快捷推进。
	if event.is_action("ui_accept"):
		get_viewport().set_input_as_handled()
		if event.is_pressed() and not event.is_echo():
			_advance()
	elif event.is_action("ui_cancel"):
		# Escape 不关闭尚未完成的剧情，防止露出被锁定的自由操作。
		get_viewport().set_input_as_handled()


func _effects(node: Dictionary) -> String:
	var parts: Array[String] = []
	for id in node.get("costs", {}):
		parts.append("%s -%d" % [GameState.config.items[id].name, int(node.costs[id])])
	var rewards: Dictionary = node.get("rewards", {})
	for id in rewards.get("items", {}):
		parts.append("%s +%d" % [GameState.config.items[id].name, int(rewards.items[id])])
	for id in rewards.get("activities", []):
		var activity := ScheduleManager.activity_by_id(str(id))
		parts.append("%s%s" % [activity.name, " · 下回合开放" if rewards.get("unlock_timing", "next_turn") == "next_turn" else " · 对话后开放"])
	return "    ".join(parts)
