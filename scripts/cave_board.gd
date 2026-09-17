extends Control

# 逻辑仍是方格；绘制和鼠标命中共用等距投影，不改变道路或距离规则。
# 本脚本不提交建造；只发 cell_clicked/cancelled，由 cave_ui.gd 解释当前工具。
signal cell_clicked(cell: Vector2i)
signal cancelled
const ThemeKit = preload("res://scripts/ui_theme.gd")
var selected_id := -1
var mode := "select"
var build_type := "herb_field"
var hover_cell := Vector2i(-1, -1)
var sprites: Array[AtlasTexture] = []
# 缓存原图像素用于透明区域命中；不能每次鼠标移动都重新读取纹理。
var sprite_pixels: Image


func _ready() -> void:
	clip_contents = true
	var sheet: Texture2D = load("res://assets/cave_buildings.png")
	sprite_pixels = sheet.get_image()
	# 图集为 4 列 2 行，单格 384x512；素材布局改变时须同步这些取图区域。
	for index in range(8):
		var sprite := AtlasTexture.new()
		sprite.atlas = sheet
		sprite.region = Rect2((index % 4) * 384, (index / 4) * 512, 384, 512)
		sprite.filter_clip = true
		sprites.append(sprite)
	resized.connect(queue_redraw)
	mouse_exited.connect(func() -> void:
		hover_cell = Vector2i(-1, -1)
		queue_redraw())


## 返回一格菱形的屏幕宽度；取宽高两个限制的较小值，并留出屋顶与边缘空间。
func cell_size() -> float:
	var span: float = GameState.cave_config.width + GameState.cave_config.height
	return maxf(1, minf((size.x - 24) / (span * 0.5), (size.y - 70) / (span * 0.25)))


func grid_origin() -> Vector2:
	var step := cell_size()
	var span: float = GameState.cave_config.width + GameState.cave_config.height
	return Vector2((size.x + (GameState.cave_config.height - GameState.cave_config.width) * step * 0.5) / 2.0, (size.y - span * step * 0.25) / 2.0 + 24)


## 逻辑坐标 -> 本控件局部像素；横向用 x-y，纵向用 x+y，得到宽高比 2:1 的菱形。
func project(point: Vector2) -> Vector2:
	return grid_origin() + Vector2((point.x - point.y) * 0.5, (point.x + point.y) * 0.25) * cell_size()


func cell_center(cell: Vector2i) -> Vector2:
	return project(Vector2(cell) + Vector2(0.5, 0.5))


## project 的逆变换；floor 得到所属格，不是四舍五入到最近格心。
func cell_at(point: Vector2) -> Vector2i:
	var offset := (point - grid_origin()) / cell_size()
	return Vector2i(floori(offset.x + offset.y * 2), floori(offset.y * 2 - offset.x))


## 放置和移动落点使用地面格；选择建筑时优先命中可见像素，让屋顶也能被点选。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		hover_cell = cell_at(event.position)
		if mode == "select" or (mode == "move" and selected_id < 0):
			var hit := building_at_point(event.position)
			if not hit.is_empty():
				hover_cell = hit.position
		queue_redraw()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancelled.emit()
		elif event.button_index == MOUSE_BUTTON_LEFT and GameState.Cave.inside(hover_cell):
			cell_clicked.emit(hover_cell)
		accept_event()


func _footprint(point: Vector2, footprint: Vector2 = Vector2.ONE) -> PackedVector2Array:
	return PackedVector2Array([project(point), project(point + Vector2(footprint.x, 0)), project(point + footprint), project(point + Vector2(0, footprint.y))])


func _outline(points: PackedVector2Array, color: Color, width: float = 1) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, color, width, true)


## queue_redraw 后由 Godot 调用；按地面、道路、建筑、预览顺序绘制，不修改玩法状态。
func _draw() -> void:
	if GameState.cave_config.is_empty():
		return
	var step := cell_size()
	var extent := Vector2(GameState.cave_config.width, GameState.cave_config.height)
	var ground := _footprint(Vector2.ZERO, extent)
	var shadow := ground.duplicate()
	for i in range(shadow.size()):
		shadow[i].y += 9
	draw_colored_polygon(shadow, Color("#344c43a6"))
	draw_colored_polygon(ground, Color("#769551b8"))
	_outline(ground, Color("#e8e3b0cc"), 2)
	for y in range(int(extent.y)):
		for x in range(int(extent.x)):
			var tile := _footprint(Vector2(x, y))
			if (x + y) % 2 == 0:
				draw_colored_polygon(tile, Color("#c7d79116"))
			if mode != "select":
				_outline(tile, Color("#dce9b660"))
	var network: Dictionary = GameState.Cave.connected_roads(GameState.cave.roads)
	for road in GameState.cave.roads:
		var paving := _footprint(Vector2(road) + Vector2(0.08, 0.08), Vector2(0.84, 0.84))
		draw_colored_polygon(paving, Color("#bdc4a9") if network.has(road) else Color("#b2a7a1"))
		_outline(paving, Color("#798b78"))
		for split in [0.33, 0.66]:
			draw_line(project(Vector2(road) + Vector2(split, 0.08)), project(Vector2(road) + Vector2(split, 0.92)), Color("#899d87"), 1, true)
	var entry := cell_center(GameState.Cave.entrance())
	_draw_sprite(7, entry.x, entry.y + step * 0.35, step)
	for building in _sorted_buildings():
		var data: Dictionary = GameState.Cave.definition(building)
		var point := Vector2(building.position)
		var footprint := Vector2(data.size[0], data.size[1])
		var tile := _footprint(point + Vector2(0.06, 0.06), footprint - Vector2(0.12, 0.12))
		draw_colored_polygon(tile, Color("#9aaa6d"))
		_draw_structure(point, footprint, data)
		var center := project(point + footprint / 2.0)
		if not GameState.Cave.connected(building, network):
			draw_circle(center + Vector2(0, -step * 0.62), 5, ThemeKit.RED)
		elif not data.recipes.is_empty() and str(building.recipe).is_empty():
			draw_circle(center + Vector2(0, -step * 0.62), 5, ThemeKit.GOLD)
		if int(building.id) == selected_id:
			_outline(tile, Color("#fff4ba"), 3)
			_caption(str(data.name), project(point + footprint) + Vector2(0, 17))
	if not GameState.Cave.inside(hover_cell):
		return
	var ghost_type := build_type
	if mode == "move":
		var moving: Dictionary = GameState.Cave.find_building(selected_id)
		if moving.is_empty():
			return
		ghost_type = str(moving.type)
	if mode in ["build", "move"] and GameState.phase == GameState.Phase.FREE:
		var data: Dictionary = GameState.cave_config.buildings[ghost_type]
		# 绿色仅表示占地合法，不保证材料或容量足够；实际操作仍由规则层完整校验。
		var valid: bool = GameState.Cave.placement_error(ghost_type, hover_cell, selected_id if mode == "move" else -1).is_empty()
		var footprint := Vector2(data.size[0], data.size[1])
		var tile := _footprint(Vector2(hover_cell), footprint)
		draw_colored_polygon(tile, Color("#c5f1ce75") if valid else Color("#e49d9a75"))
		_outline(tile, Color("#e3ffd4") if valid else Color("#f78c86"), 2)
	else:
		_outline(_footprint(Vector2(hover_cell)), Color("#fff7bb"), 2)


func _draw_structure(point: Vector2, footprint: Vector2, data: Dictionary) -> void:
	draw_texture_rect(sprites[_sprite_index(data)], structure_rect(point, footprint), false)


func _sprite_index(data: Dictionary) -> int:
	# 未提供独立美术的新增内容暂用同类图；配置与生产不依赖素材名称。
	var index := 5
	var work := str(data.get("work_type", ""))
	if data.category == "housing":
		index = 0
	elif work in ["farming", "forestry", "mining"]:
		index = {"farming": 1, "forestry": 2, "mining": 3}[work]
	elif data.category == "manufacturing":
		index = 4
	elif data.get("bonus", {}).get("affix", "") == "spirit":
		index = 6
	return index


## 图像可超出地面占地；绘制与像素命中共用此矩形，避免缩放后“看得到却点不中”。
func structure_rect(point: Vector2, footprint: Vector2) -> Rect2:
	var center := project(point + footprint / 2.0)
	var width := cell_size() * (footprint.x + footprint.y) * 0.49
	var bottom := project(point + footprint).y + width * 0.10
	var height := width * 4.0 / 3.0
	return Rect2(center.x - width / 2.0, bottom - height, width, height)


## 按占地远端的深度从后往前画；复制数组排序，不改变真实生产分料顺序。
func _sorted_buildings() -> Array:
	var buildings: Array = GameState.cave.buildings.duplicate()
	buildings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_size: Array = GameState.Cave.definition(a).size
		var b_size: Array = GameState.Cave.definition(b).size
		return a.position.x + a.position.y + a_size[0] + a_size[1] < b.position.x + b.position.y + b_size[0] + b_size[1])
	return buildings


func building_at_point(point: Vector2) -> Dictionary:
	# 从最前景向后检验透明像素，让屋顶可点击而透明边缘可以穿透。
	var buildings := _sorted_buildings()
	buildings.reverse()
	for building in buildings:
		var data: Dictionary = GameState.Cave.definition(building)
		var rect := structure_rect(Vector2(building.position), Vector2(data.size[0], data.size[1]))
		if not rect.has_point(point):
			continue
		var region := sprites[_sprite_index(data)].region
		var pixel := Vector2i(region.position + (point - rect.position) / rect.size * region.size)
		if sprite_pixels.get_pixelv(pixel).a > 0.4:
			return building
	return {}


func _draw_sprite(index: int, center_x: float, bottom: float, width: float) -> void:
	var height := width * 4.0 / 3.0
	draw_texture_rect(sprites[index], Rect2(center_x - width / 2.0, bottom - height, width, height), false)


func _caption(value: String, point: Vector2) -> void:
	var font := get_theme_default_font()
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var rect := Rect2(point - Vector2(width / 2 + 8, 16), Vector2(width + 16, 24))
	draw_style_box(ThemeKit.hud_panel(4), rect)
	draw_string(font, point - Vector2(width / 2, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ThemeKit.LIGHT)
