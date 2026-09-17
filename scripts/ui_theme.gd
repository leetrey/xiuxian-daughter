extends RefCounted

# 养成与洞天共用的视觉参数；不参与任何玩法数值。
# 普通 RefCounted 工具脚本，通过静态方法调用；不是第三个 Autoload。
const BACKGROUND := Color("#f5f7f5")
const PAPER := Color("#ffffff")
const INK := Color("#263c38")
const MUTED := Color("#71817b")
const LINE := Color("#dce5df")
const JADE := Color("#287764")
const PALE := Color("#eaf3ee")
const RED := Color("#b85f61")
const HUD := Color("#203d38ed")
const GOLD := Color("#dad4ac")
const LIGHT := Color("#f4f7eb")
const GROUP_COLORS := {"physique": Color("#ae6955"), "dao": Color("#507f9a"), "affinity": Color("#946886"), "arts": JADE}
static var _icons: Dictionary = {}


## 每次创建独立样式，后续改一个面板的边距/边框不会连带修改其他控件。
static func panel(color: Color, border: Color = Color.TRANSPARENT, padding: int = 12, radius: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0 else 0)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	return style


static func icon(name: String) -> Texture2D:
	# 共享工具图标并保留纹理引用；用于自绘时也不会在 draw 命令完成前被释放。
	if not _icons.has(name):
		_icons[name] = load("res://assets/icons/%s.svg" % name)
	return _icons[name] as Texture2D


## 根界面设置此 Theme，子控件自动继承；个别主按钮和 HUD 再用 override 覆盖。
static func make_theme() -> Theme:
	var value := Theme.new()
	var font := SystemFont.new()
	# 使用本机可用字体，工程未内置字体文件；跨平台缺字时检查这些候选字体。
	font.font_names = PackedStringArray(["Hiragino Sans GB", "PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC"])
	value.default_font = font
	value.default_font_size = 16
	value.set_color("font_color", "Label", INK)
	value.set_color("default_color", "RichTextLabel", INK)
	for type in ["Button", "OptionButton"]:
		value.set_stylebox("normal", type, panel(PAPER, LINE))
		value.set_stylebox("hover", type, panel(PALE, Color("#91b9a7")))
		value.set_stylebox("pressed", type, panel(Color("#d6e9df"), JADE))
		value.set_stylebox("disabled", type, panel(Color("#f0f3f0"), Color("#e4eae5")))
		var focus := panel(Color.TRANSPARENT, JADE, 0)
		focus.set_border_width_all(2)
		value.set_stylebox("focus", type, focus)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			value.set_color(state, type, INK)
		value.set_color("font_disabled_color", type, Color("#9aa9a1"))
		value.set_color("icon_disabled_color", type, Color("#aebcb4"))
		value.set_constant("h_separation", type, 10)
	value.set_icon("arrow", "OptionButton", icon("chevron-down"))
	value.set_constant("modulate_arrow", "OptionButton", 1)
	value.set_constant("arrow_margin", "OptionButton", 12)
	value.set_stylebox("panel", "TabContainer", panel(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	for state in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"]:
		var tab := panel(Color.TRANSPARENT, Color.TRANSPARENT, 12, 0)
		tab.content_margin_left = 24
		tab.content_margin_right = 24
		if state == "tab_selected":
			tab.bg_color = PALE
			tab.border_color = JADE
			tab.border_width_bottom = 3
		for type in ["TabBar", "TabContainer"]:
			value.set_stylebox(state, type, tab)
	for type in ["TabBar", "TabContainer"]:
		value.set_color("font_selected_color", type, JADE)
		value.set_color("font_unselected_color", type, MUTED)
		value.set_color("font_hovered_color", type, INK)
		value.set_font_size("font_size", type, 18)
	var divider := panel(LINE, Color.TRANSPARENT, 0, 0)
	divider.content_margin_top = 1
	value.set_stylebox("separator", "HSeparator", divider)
	value.set_constant("separation", "HSeparator", 12)
	value.set_stylebox("panel", "PopupMenu", panel(PAPER, LINE, 8))
	value.set_stylebox("hover", "PopupMenu", panel(PALE, Color.TRANSPARENT, 8))
	value.set_color("font_color", "PopupMenu", INK)
	value.set_color("font_hover_color", "PopupMenu", JADE)
	value.set_color("font_disabled_color", "PopupMenu", MUTED)
	value.set_constant("v_separation", "PopupMenu", 16)
	value.set_stylebox("panel", "AcceptDialog", panel(PAPER, LINE, 20, 8))
	var window_frame := ThemeDB.get_default_theme().get_stylebox("embedded_border", "Window").duplicate() as StyleBoxFlat
	window_frame.bg_color = JADE
	window_frame.border_color = JADE
	value.set_stylebox("embedded_border", "Window", window_frame)
	value.set_color("title_color", "Window", PAPER)
	value.set_stylebox("panel", "TooltipPanel", panel(INK, Color.TRANSPARENT, 10))
	value.set_color("font_color", "TooltipLabel", PAPER)
	value.set_stylebox("scroll", "VScrollBar", panel(Color.TRANSPARENT, Color.TRANSPARENT, 2, 2))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		value.set_stylebox(state, "VScrollBar", panel(Color("#b8ccc0"), Color.TRANSPARENT, 3, 3))
	return value


static func primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", panel(JADE, Color.TRANSPARENT, 14))
	button.add_theme_stylebox_override("hover", panel(Color("#358872"), Color.TRANSPARENT, 14))
	button.add_theme_stylebox_override("pressed", panel(Color("#1f5e4e"), Color.TRANSPARENT, 14))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(state, PAPER)


static func hud_panel(padding: int = 16) -> StyleBoxFlat:
	var style := panel(HUD, Color("#afbe9673"), padding, 3)
	style.shadow_color = Color(0.06, 0.15, 0.12, 0.25)
	style.shadow_size = 8
	return style


## 场景按钮统一处理正常、悬停、按下和禁用外观；emphasized 用于右下角主操作。
static func game_button(button: Button, emphasized: bool = false) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var color := Color("#893f43f5") if emphasized else HUD
		if state == "hover":
			color = color.lightened(0.12)
		elif state == "pressed":
			color = color.darkened(0.15)
		elif state == "disabled":
			color = Color("#344640ba")
		button.add_theme_stylebox_override(state, panel(color, GOLD.darkened(0.3), 14, 3))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(state, LIGHT)
	button.add_theme_font_size_override("font_size", 18)


static func title_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Songti SC", "STSong", "SimSun", "Noto Serif CJK SC"])
	return font
