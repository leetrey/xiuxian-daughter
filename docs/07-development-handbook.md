# 开发与调试手册

适用范围：当前 Godot 原型。更新日期：2026-09-18，本机验证版本为 Godot 4.7.1，代码语言为 GDScript。

这份手册讲如何修改和排查现有工程，不代替玩法设计。规则看 [01 主体设计基线](01-game-design.md)，真实实现范围看 [05 开发进度](05-development-progress.md)，内容填表看 [06 内容填写指南](06-content-authoring.md)。剧情已接入线性播放、完成、物品结算、活动与图纸解锁；父亲恢复、土地扩张、存档、冒险、战斗、继承仍未实现，不能靠新增几个 JSON 字段直接启用。

## 目录

1. [先跑起来](#1-先跑起来)
2. [VS Code 与 Godot 怎么配合](#2-vs-code-与-godot-怎么配合)
3. [目录与脚本职责](#3-目录与脚本职责)
4. [顺着一次操作读代码](#4-顺着一次操作读代码)
5. [怎么添加内容和功能](#5-怎么添加内容和功能)
6. [怎么修改界面与美术](#6-怎么修改界面与美术)
7. [怎么打断点和看日志](#7-怎么打断点和看日志)
8. [怎么运行和补充测试](#8-怎么运行和补充测试)
9. [常见问题排查](#9-常见问题排查)
10. [每天开发的收尾清单](#10-每天开发的收尾清单)

## 1. 先跑起来

### 最短路径

1. 用 Godot 导入根目录的 `project.godot`，等待首次资源导入结束。
2. 在 VS Code 中打开整个工程文件夹，不是只打开某个 `.gd` 文件。
3. 在 Godot 的“运行项目”中启动主场景，确认能看到山居和女儿。
4. 进入“安排日程”，选满三槽并确认，再进入下一回合。
5. 开始改动前跑一次核心测试，留下一份可比较的基线。

本工程不需要 npm、浏览器服务器、Python 环境或 C# SDK。VS Code 负责编辑，Godot 负责运行 GDScript 和渲染游戏。

### 终端命令

本机工程路径为 `/Users/leet/WorkBuddy/独立`。在 VS Code 集成终端进入工程后，下面各条命令单独执行：

```bash
cd "/Users/leet/WorkBuddy/独立"
```

检查引擎版本：

```bash
godot --version
```

打开编辑器：

```bash
godot --path . --editor
```

直接试玩主场景：

```bash
godot --path .
```

若终端提示 `command not found: godot`，本机可使用已安装的完整路径，不必因此重装项目：

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --path "/Users/leet/WorkBuddy/独立"
```

在 Godot 中，“运行项目”使用 `project.godot` 配置的主场景；“运行当前场景”适合单独运行内容校验或测试场景。默认快捷键通常为 F5 / F6，Mac 可能需要 Fn，实际以菜单显示为准。终端选项可查 [Godot 命令行文档](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)。

**当前没有存档。停止程序会丢失本次试玩进度。** 调试前先记录复现步骤，不要把长时间试玩当成唯一可恢复的状态。

## 2. VS Code 与 Godot 怎么配合

### 推荐：VS Code 写代码，Godot 看运行状态

先用这个方式，不必等 VS Code 断点配置完成再开始开发。

1. 两个程序都打开同一份工程，避免一个打开原目录、另一个打开旧副本。
2. VS Code 查看函数、搜索引用、改 GDScript 和 JSON。
3. Godot 负责导入图片、启动游戏、查看报错和运行中的节点。
4. 改完配置或界面创建代码后停止游戏，再重新运行。

可选安装 Godot 官方维护的 **Godot Tools** 扩展，获得 GDScript 补全、跳转和调试支持。Godot 4 引擎路径设置为：

```json
{
  "godotTools.editorPath.godot4": "/Applications/Godot.app/Contents/MacOS/Godot"
}
```

使用编辑器提供语言服务时，保持 Godot 打开当前工程；补全未连接不等于代码一定有错。扩展也有无窗口语言服务模式，具体选项以安装版本为准。[Godot Tools 配置说明](https://github.com/godotengine/godot-vscode-plugin#configuration)

### 可选：在 VS Code 中打断点

在“运行和调试”中由扩展创建 Godot 启动配置；当前官方配置可按如下方式指定本工程主场景：

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "调试山河养成录",
      "type": "godot",
      "request": "launch",
      "project": "${workspaceFolder}",
      "scene": "main"
    }
  ]
}
```

选择此配置后从 VS Code 启动，在可执行语句旁打断点；不要只在普通终端启动游戏后期待 VS Code 自动接管它。配置字段参考 [Godot Tools 调试说明](https://github.com/godotengine/godot-vscode-plugin#gdscript-debugger)。

本轮没有安装扩展、改动你的用户设置或新增 `.vscode` 文件；以上是可选接入步骤，尚未在你的 VS Code 调试会话中验证。Godot 原生运行与工程测试不依赖它们。

### 读代码的方法

在 VS Code 的“大纲”中先看函数名，再沿调用关系阅读。支持语言服务时可用“转到定义”；未连接时也可搜索函数名。新增的 `##` 是函数说明，`#` 是局部解释，不参与游戏运行。

不要一上来从头读完六百行 UI。第一次建议只追四个入口：`GameState._ready()`、`ScheduleManager.confirm_schedule()`、`Cave.forecast()`、`main._refresh()`。

## 3. 目录与脚本职责

```text
project.godot                主场景、两个 Autoload、窗口与渲染设置
scenes/                     场景入口，挂载对应脚本
scripts/                    GDScript 状态、规则、界面与测试
data/                       作者填写的 JSON 内容表
assets/                     背景、立绘、建筑图集与工具图标
docs/                       当前设计、进度、填表和开发说明
.godot/                     引擎生成的导入与编辑器缓存
```

`.godot/` 不手工维护、不提交 Git。原始素材、`.import` 导入设置、`.gd.uid` 标识文件保留在版本管理中。不要为了整理目录移动或重命名这些文件却不检查场景与资源引用。

### 三层分工

| 层 | 脚本 | 修改什么 |
|---|---|---|
| 状态 | [game_state.gd](../scripts/game_state.gd) | 读取配置，保存属性、库存、草稿、洞天与阶段，初始化和推进本局 |
| 培养规则 | [schedule_manager.gd](../scripts/schedule_manager.gd) | 校验日程，扣费，压力概率，成长，自由活动 |
| 洞天规则 | [cave_rules.gd](../scripts/cave_rules.gd) | 占地、道路、派工、景观乘区、预测与生产入库 |
| 剧情查询 | [story_rules.gd](../scripts/story_rules.gd) | 节点校验、条件不满足原因、候选顺序、三阶段表现；只读 |
| 剧情执行 | [story_flow.gd](../scripts/story_flow.gd) | 检查点与当前对话、末句完成、物品结算和活动/图纸生效时点 |
| 剧情界面 | [story_ui.gd](../scripts/story_ui.gd) | 背景、立绘、台词、费用奖励预告、推进按钮 |
| 配置校验 | [content_tables.gd](../scripts/content_tables.gd) | 解析 JSON，检查物品数量、分类与跨表引用 |
| 主界面 | [main.gd](../scripts/main.gd) | 家园、立绘、菜单、按钮、闲置弹窗和成长札记 |
| 洞天界面 | [cave_ui.gd](../scripts/cave_ui.gd) | 工具模式、建筑目录、配方、御灵和产出详情 |
| 地块表现 | [cave_board.gd](../scripts/cave_board.gd) | 等距投影、建筑绘制、透明像素命中与放置预览 |
| 公共外观 | [ui_theme.gd](../scripts/ui_theme.gd) | 字体、颜色、图标、按钮状态和等分图集裁切 |
| 验证 | [validate_content.gd](../scripts/validate_content.gd)、[smoke_test.gd](../scripts/smoke_test.gd) | 作者填表检查、规则回归、实际窗口走查 |

只有 `GameState` 和 `ScheduleManager` 是 Autoload，项目启动时自动创建。`Cave`、`Content`、`Story`、`StoryFlow` 是 `GameState` 预加载的普通脚本，通过静态方法调用；剧情真实状态也只存在 GameState 中。

### 常见写法

| 代码 | 在本工程中的意思 |
|---|---|
| `res://data/items.json` | 从工程根目录找资源，不是系统绝对路径 |
| `Dictionary` / `Array` | 配置与本局记录使用的字典、数组 |
| `duplicate(true)` | 深复制嵌套数据；用于开局模板与拒绝操作前的预演 |
| `signal`、`connect()`、`emit()` | 操作提交后广播状态变化，让界面重新读数据 |
| `preload()` / `load()` | 载入脚本或资源，不代表创建一个场景实例 |
| `instantiate()` | 从场景资源创建运行中的节点实例 |
| `bind()` | 给按钮或选项回调追加活动 ID、槽位等上下文 |
| `queue_free()` | 安排节点稍后释放；不是从场景模板中永久删除 |

特别注意：`activity_by_id()` 和 `find_building()` 返回的是原字典。取出来改字段，会改动配置或当前局，不是只改一个临时变量。只做演算时使用副本。

## 4. 顺着一次操作读代码

### 启动

```text
project.godot
  -> GameState._ready()
     -> _load_configs() 读取五份 JSON
        -> 校验内容及引用
        -> configs_validated = true（加载函数正常完成后才标记）
     -> reset_game() 从配置创建本局数据
        -> StoryFlow.begin("turn_start") 选择开始剧情或直接进入 FREE
  -> ScheduleManager Autoload 就绪
  -> scenes/main.tscn
     -> main._ready() 创建控件并连接信号
     -> main._refresh() 展示本局状态
```

`reset_game()` 只重置运行数据，**不重新读取磁盘 JSON**。改配置后要重新启动游戏进程；点击游戏内“重新开始”不会完成配置热加载。

### 安排日程

```text
OptionButton.item_selected
  -> main._choose()
  -> ScheduleManager.assign_slot()
  -> GameState.plan 保存活动 ID
  -> state_changed.emit()
  -> 界面 _refresh() 更新摘要和可用状态
```

这一步只改草稿，不增长属性、不扣物品、不消耗随机数。菜单显示的中文名和选项序号不是业务 ID，业务 ID 保存在选项 metadata 中。

### 确认与下一回合

```text
main._confirm()
  -> confirm_schedule()
     -> plan_error() 检查整份草稿及全部材料
     -> 未安排生产时返回 needs_confirmation，等待玩家决定
     -> FREE 改为 RESOLVING，锁住操作
     -> 逐槽：当前压力 -> 随机结果 -> 扣材料 -> 增长 -> 更新压力
     -> Cave.settle() 统一生产扣料与入库
     -> StoryFlow.begin("turn_end") 进入主/支线对话，没有剧情则直接 RESULTS
     -> 读完剧情后切到 RESULTS，展示完整札记
  -> 玩家在札记点击下一回合
  -> GameState.advance_turn()
     -> 清日程、回精力、激活到期活动与图纸、检查开始剧情
     -> 保留压力、洞天与剧情完成记录；最后一回合则 FINISHED
```

这里描述当前实际流程，不包含尚未接入的父亲升级与回合末天赋。`phase` 是操作阶段，新增的 STORY 表示正在对话；`growth_phase()` 的 0/1/2 是成长阶段，不要混为同一变量。

### 建造与生产

```text
鼠标像素 -> cave_board 的投影/图像命中 -> cell_clicked(逻辑格)
  -> cave_ui._cell_clicked() 按当前工具分派
  -> Cave.build() / move_building() / toggle_road()
  -> 校验后提交，广播刷新
  -> Cave.preview() -> forecast(临时库存) -> 只显示预测

培养结算完成 -> Cave.settle() -> forecast(真实剩余库存) -> 扣料、发货
```

`forecast()` 本身不改库存。内部 `budget` 只减已有原料，产物另存 `produced`；因此新种出的草不能在同一批生产中立刻被丹炉加工。`last_production_turn` 用于防止同回合重复入库。

## 5. 怎么添加内容和功能

### 先判断改哪一层

| 想做的事 | 优先入口 |
|---|---|
| 改名字、说明、初始资源、成长与压力数值 | `data/`，按 06 填表 |
| 增加一种药材或双原料配方 | 物品表 -> 配方表 -> 建筑配方列表，不新增脚本 |
| 增加同类培养活动 | `cultivation.json.activities`，界面会从表生成菜单 |
| 改日程消耗、结果算法或结算顺序 | `schedule_manager.gd`，必要时调整配置校验 |
| 改道路、御灵、生产倍率或分料行为 | `cave_rules.gd`，同时验证预测与结算 |
| 改窗口布局和点击反馈 | `main.gd` / `cave_ui.gd` / `cave_board.gd` |
| 加剧情、存档、战斗等新系统 | 先明确状态归属和调用时点，再接规则与 UI，不只加 JSON 字段 |

### 练习：添加一个培养活动

以下只是作者练习，不是新增的正式内容。在 `cultivation.json` 的 `activities` 数组中加入一个唯一 ID 的条目即可，例如：

```json
{
  "id": "practice_example",
  "kind": "schedule",
  "name": "示例静修",
  "min_phase": 0,
  "pressure": 4,
  "growth": {"will": 2, "insight": 2}
}
```

1. 先运行内容校验，确保 JSON 和引用合法。
2. 重启游戏，打开日程菜单，找到“示例静修”。
3. 选入一个槽位，检查成长摘要；此时属性不应变化。
4. 填满其他槽并确认，在札记看实际成长和压力变化。
5. 练习结束后保留或删除这条示例；不需要为它改 `main.gd`。

需要额外材料时用已有 `costs` 字段；物品必须先定义，详情见 06。`description` 或任意新字段不会自动变成程序效果。

### 新增规则的固定步骤

1. 先确定输入、允许的阶段、改变哪些状态，以及失败时应保持哪些值不变。
2. 将可调内容放入对应数据表；给新字段补校验，避免错误拖到点击按钮时才出现。
3. 在规则层实现“完整检查 -> 提交变化”，不要从 UI 直接扣库存。
4. 规则完成后再发 `state_changed`，让界面展示完整结果而非中间状态。
5. UI 调用该入口，展示 `ok`、`message` 或报告，不另写第二套收益算法。
6. 加正常、拒绝和重复调用的必要测试，更新 05 的真实实现范围。

已有接口不全是同一种返回值：`assign_slot()` / 各种 `*_error()` 返回错误字符串，空字符串代表通过；`confirm_schedule()` / 洞天操作通常返回含 `ok`、`message` 的字典。调用前先读函数说明，不要统一写成 `result.ok`。

### 调试剧情条件与表现

剧情条件层仍可独立测试，不必真正播放并消耗材料。以下代码适合放在 `smoke_test.gd` 的测试函数中，不是终端命令：

```gdscript
var context := GameState.story_context()
# 修改的是副本，不会给女儿实际增加属性。
context.base_stats = {"power": 1001}
var candidates := GameState.Story.candidates(
    GameState.story_config, context, "turn_end", "main"
)
print(candidates) # 默认配置含 example_breakthrough。
var variant := GameState.Story.presentation(
    GameState.story_config, "example_breakthrough", 1
)
print(variant.lines) # 同一节点的中期版本，不会标记完成。
```

`story_context()` 复制本局回合、成长阶段、A、真实库存和完成 ID，不复制装备 B 或预计生产。测试不同进度可传 `GameState.story_context(["example_breakthrough"])` 或 `GameState.story_context([])` 覆盖快照中的完成列表，但不改变真实进度。

候选为空时，在 `Story.blocking_reasons()` 查看返回的原因列表；表现错误时在 `Story.presentation()` 检查节点 ID 与 `growth_phase`。主线不会默认退回其他年龄版本来掩盖缺失内容，支线才有公共 `default` 版本。

只检查自己的文本和条件，用内容校验场景的附加参数即可，不必修改脚本：

```bash
godot --path . --headless res://scenes/validate_content.tscn -- --story-preview
```

该命令用新局真实状态打印条件结果，另外列出三阶段表现；不会推进游戏内对话。不要在 `_refresh()` 中把候选自动当成已完成任务。

真实执行链为：

```text
StoryFlow.begin(checkpoint) -> 主线候选 -> 当前节点/版本/第 0 行
story_ui 的箭头按钮 -> StoryFlow.advance(屏幕节点 ID, 屏幕行号)
  -> 非末句：只加行号
  -> 末句：重新检查 -> 扣 costs -> 发 rewards.items -> 记录活动与图纸 -> 记录 completed
  -> 重新查询同类候选；主线耗尽后处理支线
  -> 全部读完返回 FREE 或 RESULTS
```

`GameState.story` 保存 active、completed、checked 和当前回合 results；`unlocked_activities` 与 `pending_activity_unlocks` 单独保存即时/延后活动解锁。检查点一回合只进入一次，同一逻辑节点本局只完成一次。`StoryFlow.advance()` 会拒绝旧 ID/行号提交，不能直接用 `completed[id] = true` 冒充结算。

图纸使用 `unlocked_blueprints`（已可用的建筑 ID）与 `pending_blueprint_unlocks`（ID 到生效回合），新局从 `cave.json.initial_blueprints` 重建。`StoryFlow._grant_unlocks()` 复用活动的时点处理，图纸奖励不扣费；`Cave.blueprint_error()` 是建造入口与 UI 共用的资格判断，`build()` 通过后仍检查占地和建材。不要把图纸加进库存或在成功建造后 erase 图纸，移动已有建筑也不重新收费。普通节点 costs 仍按原规则执行，不由重复图纸自动豁免。

在测试里切换阶段不会自动检查剧情；真实入口是新局或 `advance_turn()`，回合末入口是培养确认后。测试剧情读完前不得期待 FREE，必须逐句推进；旧培养单元测试临时用空剧情表隔离，另有真实流程集成测试，不在正式游戏加“跳过剧情”开关。

### 不要破坏的边界

- A 永久属性与 B 装备加成分开，显示 A+B 不代表写回 A。
- 自由活动扣自己的精力，培养占槽，洞天管理不扣这两种额度。
- `_refresh()`、`_draw()` 和打开菜单不能扣费、增长、掷骰或结算。
- 失败操作不应先扣一部分资源；派工与道路预演不能污染真实数据。
- 生产预测与实算共用公式，不能让新产物进入同批原料预算。
- 不用按钮禁用替代规则校验，测试或其他入口仍可能直接调用规则。

## 6. 怎么修改界面与美术

### 为什么场景文件只有一个根节点

这是当前实现方式，不是加载失败：`main.tscn` 和 `cave.tscn` 挂脚本，脚本在 `_ready()` 中创建多数子控件。因此编辑器里的静态场景树看不到完整菜单；运行时才有这些节点。

主界面可按以下顺序阅读：

```text
_ready()               组装场景，连接输入与状态信号
_build_home_summary()  左侧人物摘要
_build_hud()           顶部状态、底部入口
_build_overlay()       遮罩与共用菜单外框
_build_work()          日程、结果、确认和下一回合
_layout()              立绘及浮层位置
_refresh()             属性、库存相关按钮、阶段和结果回显
```

若只修改画面，不要顺便改规则层。当前用户方向是“场景为主体，数据按需展开”，不要再把全部细分属性、生产表和日程常驻堆回首页。

### 改布局时看什么

- `Control` 的锚点决定靠哪条边，`offset_*` 决定边距；`_layout()` 使用游戏画布大小，不是显示器物理像素。
- `HBoxContainer` / `VBoxContainer` 自动排子控件，手动改其子项位置通常会被下一次布局覆盖。
- `custom_minimum_size`、`size_flags_*` 和长文本共同影响最小尺寸；先检查它们，再判断是不是窗口缩放的问题。
- 场景背景不应拦截点击，菜单遮罩应拦截；检查 `mouse_filter`、可见性和节点层叠顺序。
- 修改日程槽数量后重新启动，控件数量在创建界面时决定。

运行时从 Godot 场景面板切到 **Remote** 检查实际节点的 `size`、`position`、`visible` 和 `mouse_filter`；脚本创建的节点可能是自动名称。远程查看与修改只针对运行实例，不等于改好了创建它的源代码。[Godot 调试工具说明](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/overview_of_debugging_tools.html#remote-in-scene-dock)

### 换图与改建筑表现

背景、人物和建筑的尺寸、图集顺序、生成记录集中在 [assets/README.md](../assets/README.md)。人物三列、建筑 4×2 网格不变时可直接替换分辨率，`ui_theme.gd` 的 `atlas_cell()` 按真实纹理尺寸取格；家园和剧情回退共用 `daughter_portrait()`。显式剧情 `portrait.region` 仍是绝对像素，换图须同步更新。改变网格列数/行数属于程序改动，不能只换素材。

建筑的 `sprite_index` 可选填 0–7，优先于同类映射；范围由 `content_tables.gd` 的 `BUILDING_ATLAS_GRID` 约束。`cave_board.gd` 的 `_sprite_index()` 同时供绘制与透明像素命中使用，单格比例也从纹理推导。

洞天有两套坐标：规则层的整数格坐标和界面层的像素坐标。`project()` 正向投影，`cell_at()` 逆向定位，`structure_rect()` 同时服务建筑绘制与透明像素命中。只改绘制、不改命中，会造成屋顶看得到却点不中。

素材改动后让 Godot 完成导入，再重启试玩。跨平台字体目前依赖系统候选字体；本机不缺字不代表其他机器已经验证通过。

## 7. 怎么打断点和看日志

### 第一次断点：看一次培养如何结算

1. 在 Godot 脚本编辑器打开 `schedule_manager.gd`，在 `confirm_schedule()` 内 `GameState.phase = GameState.Phase.RESOLVING` 这一行打断点。
2. 从 Godot 启动项目，填满日程并点击确认；有闲置提醒时明确继续，才会走到此处。
3. 暂停时看 `GameState.plan`、`inventory`、`pressure` 和 `phase`。当前行尚未执行，单步后再看阶段变化。
4. 继续到循环，观察 `id`、`before`、`outcome`、`gains`；一槽结束后，再看下一槽使用的压力。
5. 在 `Cave.settle()` 查看生产报告和库存前后差异，继续运行到札记。

Godot 可在脚本左侧设置断点，使用单步跳过、单步进入、继续和调用栈排查。也支持 `breakpoint` 关键字，但写入代码的临时断点结束调试后应移除。[Godot 断点说明](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/overview_of_debugging_tools.html#script-editor-debug-tools-and-options)

### 按问题选断点

| 问题 | 建议位置 | 看哪些值 |
|---|---|---|
| 启动就退出 | `GameState._load_configs()` / `validate_config()` | `config_error`、错误字段、JSON 类型 |
| 选了日程却不对 | `assign_slot()` | `index`、`id`、`GameState.plan`、`availability()` |
| 压力或成长异常 | `confirm_schedule()` / `_apply_growth()` | `before`、概率档、`outcome.multiplier`、逐项取整结果 |
| 建不了或点错格 | `cave_board._gui_input()` / `placement_error()` | `event.position`、`hover_cell`、占地与返回错误 |
| 派工失败 | `assign_worker()` | `building_id`、`slot`、`worker_id`、预演后的容量与居民数 |
| 产量不对 | `forecast()` / `multipliers()` | `budget`、`row.reason`、`inputs`、`outputs`、`factors` |
| 看起来重复入库 | `settle()` | `phase`、`turn`、`last_production_turn` |
| 剧情没有成为候选 | `Story.blocking_reasons()` | 检查点、main/side、A、真实库存、完成 ID 与未满足原因 |
| 剧情版本不对 | `Story.presentation()` | 节点 ID、0/1/2 阶段、主线三份版本与支线 default |
| 对话读完却没有结果 | `StoryFlow.advance()` | expected_id/line、active、reasons、costs、完成记录；最后一行才提交 |
| 解锁过早或未开放 | `apply_pending_unlocks()` / `availability()` | 生效回合、requires_unlock、unlocked_activities、min_phase |
| 有材料却不能建造 | `Cave.blueprint_error()` / `build()` | initial_blueprints、unlocked_blueprints、pending_blueprint_unlocks，以及占地与建材 |
| 数据变了但界面没变 | 状态提交处 / `_refresh()` | 是否发信号、是否订阅、控件是否可见 |

`forecast()` 在预览时也会被调用，断点可能频繁停住。只想追实际入库时，先在 `settle()` 打断点，再单步进入 `forecast()`。

### 日志与固定种子

不方便断点时，在有关函数内临时打印一次上下文，例如：

```gdscript
print("[培养] turn=", GameState.turn, " phase=", GameState.phase,
    " pressure=", GameState.pressure, " plan=", GameState.plan)
```

不要在 `_process()` 或 `_draw()` 每帧打印，以免日志淹没真正的错误。先看第一条 `SCRIPT ERROR` / `Parse Error` 及文件行号，再读调用栈；后续“对象为空”可能只是前面脚本加载失败的结果。

`GameState.reset_game(42)` 可在测试中重建固定种子的新局。相同配置、相同种子、相同操作及随机调用顺序，才能复现结果；这不等于已有存档回放功能。不要为了查看结果在 UI 多调用一次 `rng.randf()`。

本机默认日志通常位于 `~/Library/Application Support/Godot/app_userdata/山河养成录/logs/`。如需明确的诊断日志，可用：

```bash
godot --path . --verbose --log-file /tmp/xiuxian-debug.log
```

日志命令会持续运行游戏，关闭窗口后结束；它不是自动退出测试。通用参数含义见 [Godot 命令行文档](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)。

## 8. 怎么运行和补充测试

下面命令均在工程根目录执行，成功后自动退出。失败先看错误正文和退出码，不要只凭窗口能打开判断。

### A. 作者改表后：内容校验

```bash
godot --path . --headless res://scenes/validate_content.tscn
```

成功标记：`CONTENT_CONFIG_OK`。检查格式、分类、数量、引用和已实现的配置规则；不要求你保留演示药材的固定产量，也不验证平衡。

### B. 改规则后：核心回归

```bash
godot --path . --headless res://scenes/smoke_test.tscn
```

成功标记：`SMOKE_TEST_OK`。包含培养、压力边界、A/B、道路、派工、景观、材料竞争、跨回合加工和防重复等案例。`_run_review_regressions()` 还覆盖压力档缺字段/错误类型/非有限数值、图格序号、替换尺寸裁切，以及剧情检查提前返回时的回合通知。

`_run_blueprints()` 验证图纸不消耗、逐栋建材、缺图无副作用、剧情发放与生效时点、重复奖励和新局重置。窗口测试中的 `_capture_blueprint_ui()` 临时用丹炉验证锁定、末句预告、下回合开放和连续建造；不修改正式剧情表。

这里有默认数值断言，例如初始属性、配方产量和默认三槽。作者主动调整数值时，可能出现“配置合法，但旧例子的期望值不再成立”；先确认新规则，再更新受影响的测试，不能为全绿而盲改断言。

### C. 改界面后：真实窗口走查

```bash
godot --path . res://scenes/smoke_test.tscn -- --ui-snapshot=/tmp/xiuxian-handbook-ui
```

该命令不能加 `--headless`。独立的 `--` 后面是传给本工程脚本的参数。截图输出到指定目录，覆盖三种窗口尺寸、阶段立绘、菜单、日程、建筑、派工和结果。它触发真实控件信号及地块输入，但不是所有真人键鼠路径的穷举测试。

其中 `_check_replacement_assets()` 临时替换内存资源缓存，检查不同尺寸下家园与支线回退一致、专用立绘遵循显式区域、建筑显示与透明命中一致；测试结束恢复资源，不修改 PNG。

需要人工再看：图片是否完整、文字是否遮挡、按钮是否能点、菜单是否能返回、结算后管理是否锁定。代码检查通过不代表美术或交互已经验收。

### 首次检出或新增素材

先用 Godot 编辑器打开工程完成导入。也可以只做一次无窗口导入检查：

```bash
godot --path . --headless --editor --quit
```

这条命令不是规则测试的替代。运行后的完整输出中不能有 `SCRIPT ERROR`、`Parse Error` 或 `FAIL:`，即使最后看到成功字样也要检查前面的错误。

### 补一条规则测试的例子

测试通常采用“准备状态 -> 调用入口 -> 检查结果与副作用 -> 恢复状态”。下面以减压下限为例，只用于讲解；现有测试已有类似覆盖，不必重复加入：

```gdscript
func _run_pressure_floor_example() -> void:
    GameState.reset_game(42)
    GameState.pressure = 5
    var before := int(GameState.inventory.get("clearheart_grass", 0))
    var result := ScheduleManager.execute_free_action("clearheart")
    _check(result.ok, "有草且存在压力时可以使用")
    _check(GameState.pressure == 0, "压力不低于零")
    _check(int(GameState.inventory.clearheart_grass) == before - 1,
        "只消耗一份库存")
    GameState.reset_game()
```

此例依赖当前示例的初始清心草库存与减压效果。真正新增函数时，在测试场景 `_ready()` 的成功汇总之前调用它，否则只定义函数不会执行。项目现有 `.gd` 使用 Tab 缩进，编辑时保持文件风格一致。

改资源操作至少验证一次拒绝路径：材料不够、容量不足或阶段不允许时，库存、属性、位置不能已经改变。改结算则额外验证重复调用不会再发奖励。

## 9. 常见问题排查

| 现象 | 优先检查 |
|---|---|
| `.tscn` 打开是空的 | 当前 UI 在 `_ready()` 中生成；运行后看 Remote 树和 `_build_*` |
| 改 JSON 后没有效果 | 文件是否在当前工程；是否重新启动进程，而非只点重新开始 |
| 配方不在菜单中 | 是否定义于 recipes 表；是否挂到该建筑 recipes 列表；产物分类是否允许 |
| 物品有描述却不能使用 | 描述不执行效果；当前使用逻辑需有 `kind: free` 的活动定义 |
| 按钮变灰 | 检查当前 `phase`、活动阶段、材料/精力、空槽及规则返回的原因 |
| 建筑有路却停产 | 是否能四向连到入口，不只是旁边恰好存在一格路 |
| 有草产出但丹炉缺料 | 同批产物不能供本批加工；看回合开始已有库存和培养优先消耗 |
| 图像正常但选不中 | 像素坐标是否为 Board 局部坐标；投影、图集、`structure_rect()` 是否一致 |
| 启动后界面残缺、对象为 Nil | 先处理更早的解析错误；检查脚本、资源路径与首次导入 |
| `Cannot infer the type` | Dictionary 返回值类型是否明确；必要时显式写 `var x: Vector2 = ...` 等实际类型 |
| VS Code 补全或断点不工作 | 同一工程、扩展、引擎路径和调试启动方式；补全与断点是两种不同连接 |
| 中文出现方框 | 当前机器是否有主题配置的中文字体，不能仅靠更改文本编码猜修复 |
| 内容校验通过但 smoke 失败 | 是否改了例子默认数值；先区分期望变化和真正行为回归 |

遇到无法立即定位的问题，记录：使用的引擎版本、最近改动文件、从新局开始的操作步骤、第一条错误及调用栈、关键库存/压力/阶段，视觉问题再加截图。

## 10. 每天开发的收尾清单

1. 开始前查看 `git status --short`，辨认已有改动，不覆盖不属于本次任务的内容。
2. 一次改一个明确目标：先内容或规则，再展示，避免数值和界面同时大范围变动。
3. 按改动范围跑内容校验、核心回归或窗口走查，保留失败的复现步骤。
4. 检查差异，移除临时日志、`breakpoint`、强行发资源和固定种子的调试改动。
5. 更新 05 的已实现范围、06 的新字段或本手册的操作流程；仅在规则被确认替代时归档到 history，不把历史提案当现行要求。
6. 确认后再提交 Git；不要提交 `.godot/`、日志、临时截图和与本次工作无关的文件。

提交前可分别执行：

```bash
git status --short
git diff --stat
git diff --check
```

正式内容调整用 06 作入口，程序扩展从规则层及其测试入手，界面调整从对应 `_build_*` 和 `_refresh()` 入手。当前没有配置发布用的 `export_presets.cfg`；本机开发验证通过不代表已完成导出、跨平台字体或正式发布验证。
